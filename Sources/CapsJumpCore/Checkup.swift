// What `capsjump check` reports about the config and the browsers' profiles: every
// problem, the default browser, for each site the browser it lands in and, when it names
// one, the profile and window label it resolves to, and for each key what it
// does: the app it finds, the site, the window position, or the app that opens its link.
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
    /// `configText` is nil when the file is missing; `catalog` reads one browser's
    /// profile list, and is asked at most once per browser.
    public static func run(configText: String?, configPath: String, defaultBrowser: Browser, catalog: (Browser) -> CatalogRead, lookup: Lookup) -> [Finding] {
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
        return sites(config, defaultBrowser: defaultBrowser, catalog: catalog) + keys(config, lookup: lookup)
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

    private static func sites(_ config: Config, defaultBrowser: Browser, catalog: (Browser) -> CatalogRead) -> [Finding] {
        guard !config.sites.isEmpty else { return [] }
        var read: [Browser: CatalogRead] = [:]
        func once(_ browser: Browser) -> CatalogRead {
            if let known = read[browser] { return known }
            let fresh = catalog(browser)
            read[browser] = fresh
            return fresh
        }
        let plain = defaultBrowser.support == .plain ? " (opens pages only; no tab search)" : ""
        return [Finding(.ok, "default browser: \(defaultBrowser)\(plain)")]
            + config.sites.map { site($0, defaultBrowser: defaultBrowser, catalog: once) }
    }

    /// Where one site lands: its browser and, when it names one, its profile and window
    /// label; or why it can't land anywhere.
    public static func site(_ site: Site, defaultBrowser: Browser, catalog: (Browser) -> CatalogRead) -> Finding {
        do {
            let destination = try Placement.place(site, defaultBrowser: defaultBrowser, catalog: catalog)
            let tag = destination.fellBack ? " (fell back to Chrome)" : destination.isDefault ? " (default)" : ""
            let head = "\(site.name) → \(destination.browser)\(tag), "
            guard destination.browser.support == .full else {
                return Finding(.ok, head + "opens the page; no tab search")
            }
            guard let target = destination.target else {
                return Finding(.ok, head + "its own choice of profile, any window")
            }
            let windows = destination.windowLabel.map { "windows labelled “\($0)”" } ?? "any window"
            let line = head + "\(target.profile.directory), \(windows)"
            guard target.canFocus else {
                let others = target.sharedLabelWith.map(\.directory).joined(separator: ", ")
                return Finding(.note, "\(line); always opens a new tab, because \(others) carries the same label")
            }
            return Finding(.ok, line)
        } catch {
            return Finding(.problem, "\(site.name): \(error)")
        }
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
