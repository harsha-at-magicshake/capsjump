// What `capsjump check` reports about the config and the browsers' profiles: every problem,
// for each site the profile and window label it resolves to (and its browser, when it isn't
// Chrome or Brave has the name too), and for each key what it does: the app it finds, the
// site, the window position, or the app that opens its link.
// Each site's and key's finding is its own function, which the editing window shows beside
// its row. The disk and the link handlers are injected, so every line is tested. Whether
// the file is in the layout CapsJump writes is a note of its own, apart from `run`, which
// says only what each site and key does; `CheckReport` is what `capsjump check --json`
// prints, the findings about the file apart from those about the app.

import Foundation

public struct Finding: Sendable, Equatable, Encodable {
    public enum Level: String, Sendable, Encodable {
        case ok
        case note
        case problem
    }

    public let level: Level
    public let text: String

    public init(_ level: Level, _ text: String) {
        self.level = level
        self.text = text
    }
}

/// What the checkup may ask of this Mac.
public struct Lookup: Sendable {
    public let home: String
    public let exists: @Sendable (String) -> Bool
    /// The name of the app that opens a link, or nil when none does.
    public let linkHandler: @Sendable (URL) -> String?

    public init(home: String, exists: @escaping @Sendable (String) -> Bool, linkHandler: @escaping @Sendable (URL) -> String?) {
        self.home = home
        self.exists = exists
        self.linkHandler = linkHandler
    }
}

public enum Checkup {
    /// `configText` is nil when the file is missing.
    public static func run(configText: String?, configPath: String, lists: ProfileLists, lookup: Lookup) -> [Finding] {
        guard let configText else {
            return [Finding(.problem, "no config at \(configPath); run `capsjump init`")]
        }
        let config: Config
        do {
            config = try ConfigParser.parse(configText)
        } catch {
            return error.problems.map { Finding(.problem, "\(configPath): \($0)") }
        }
        if config.sites.isEmpty && config.keys.isEmpty {
            return [Finding(.note, "\(configPath) has no sites or keys yet")]
        }
        return sites(config, lists: lists) + keys(config, lookup: lookup)
    }

    /// A note when the file reads fine but isn't laid out as CapsJump writes it; nil when it
    /// is, and when it is missing or broken, which `run` reports.
    public static func layout(configText: String?, configPath: String) -> Finding? {
        guard let configText, (try? ConfigParser.parse(configText)) != nil, !ConfigWriter.isCanonical(configText) else {
            return nil
        }
        return Finding(.note, "\(configPath) isn't in the layout CapsJump writes; `capsjump tidy` rewrites it, and Edit Config… asks before saving over it")
    }

    private static func keys(_ config: Config, lookup: Lookup) -> [Finding] {
        guard config.takesCapsLock else {
            return [Finding(.ok, "no keys, so Caps Lock is left alone")]
        }
        return config.keys.map { key($0, lookup: lookup) }
    }

    /// What one key does on this Mac: the app it finds, or the app that opens its link.
    public static func key(_ binding: KeyBinding, lookup: Lookup) -> Finding {
        let line = "`\(binding.key)` → \(binding.action)"
        switch binding.action {
        case .site, .window:
            return Finding(.ok, line)
        case let .app(target):
            if let path = target.resolve(home: lookup.home, exists: lookup.exists) {
                return Finding(.ok, "`\(binding.key)` → app \(path)")
            }
            switch target {
            case let .name(name):
                let folders = AppTarget.searchFolders.joined(separator: ", ")
                return Finding(.problem, "\(line): no \(name).app in \(folders); give its path instead")
            case .path:
                return Finding(.problem, "\(line): nothing at \(target.candidates(home: lookup.home)[0])")
            }
        case let .url(url):
            guard let app = lookup.linkHandler(url) else {
                return Finding(.note, "\(line): no installed app opens \(url.scheme ?? "these") links")
            }
            return Finding(.ok, "\(line) (opens in \(app))")
        }
    }

    /// Each site's line, in file order; a profile list that stops sites is one problem, in
    /// place of their lines.
    private static func sites(_ config: Config, lists: ProfileLists) -> [Finding] {
        var findings: [Finding] = []
        for site in config.sites {
            do {
                findings.append(line(site, try Placement.resolve(site, in: lists), lists))
            } catch {
                guard case let .lists(problems) = error else {
                    findings.append(Finding(.problem, "\(site.name): \(error)"))
                    continue
                }
                for problem in problems.map({ Finding(.problem, $0) }) where !findings.contains(problem) {
                    findings.append(problem)
                }
            }
        }
        return findings
    }

    /// Where one site lands: its browser, profile and window label, or why it can't.
    public static func site(_ site: Site, in lists: ProfileLists) -> Finding {
        do {
            return line(site, try Placement.resolve(site, in: lists), lists)
        } catch {
            return Finding(.problem, "\(site.name): \(error)")
        }
    }

    private static func line(_ site: Site, _ target: Target, _ lists: ProfileLists) -> Finding {
        let alsoIn = Placement.sameName(as: target, in: lists)
        let browser = target.browser == .chrome && alsoIn.isEmpty ? "" : "\(target.browser), "
        var notes: [String] = []
        if !alsoIn.isEmpty {
            let names = alsoIn.map(\.name).joined(separator: " and ")
            notes.append("\(names) has a profile named “\(site.account ?? "")” too, and a name in both opens in \(target.browser)")
        }
        if !target.canFocus {
            let others = target.sharedLabelWith.map(\.directory).joined(separator: ", ")
            notes.append("always opens a new tab, because \(others) carries the same label")
        }
        let line = "\(site.name) → \(browser)\(target.profile.directory), windows labelled “\(target.label)”"
        return notes.isEmpty ? Finding(.ok, line) : Finding(.note, ([line] + notes).joined(separator: "; "))
    }
}

/// What `capsjump check --json` prints: the file read (symlinks followed), whether nothing
/// anywhere is a problem, what is wrong in the file, and what is wrong with the app, which
/// only the person can fix.
public struct CheckReport: Sendable, Equatable, Encodable {
    public let config: String
    public let ok: Bool
    public let file: [Finding]
    public let app: [Finding]

    public init(config: String, file: [Finding], app: [Finding]) {
        self.config = config
        self.ok = !(file + app).contains { $0.level == .problem }
        self.file = file
        self.app = app
    }
}
