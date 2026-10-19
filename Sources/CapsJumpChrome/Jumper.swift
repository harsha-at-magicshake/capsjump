// One jump, live: read the config, the default browser and the profile lists afresh (so
// edits need no reload), place the site in its browser, gather that browser's windows and
// titles, let Core decide, and carry the decision out.

import AppKit
import CapsJumpCore

public enum Outcome: Sendable, Equatable, CustomStringConvertible {
    case focused(site: String, browser: String, windowID: String, tabIndex: Int)
    case opened(site: String, browser: String, profileDirectory: String?, reason: OpenReason)

    public var description: String {
        switch self {
        case let .focused(site, browser, windowID, tabIndex):
            "\(site): focused tab \(tabIndex) of \(browser) window \(windowID)"
        case let .opened(site, browser, profileDirectory, reason):
            "\(site): opened in \(browser)" + (profileDirectory.map { ", \($0)" } ?? "") + " (\(reason.rawValue))"
        }
    }
}

public enum JumpError: LocalizedError, Equatable, CustomStringConvertible {
    case noConfig(path: String)
    case unreadable(path: String, reason: String)
    case config(ConfigError)
    case unknownSite(String, known: [String])
    case place(site: String, PlaceError)
    case chrome(site: String, ChromeError)

    public var description: String {
        switch self {
        case let .noConfig(path):
            "no config at \(path); run `capsjump init`"
        case let .unreadable(path, reason):
            "could not read \(path): \(reason)"
        case let .config(error):
            "the config has problems (`capsjump check` lists them):\n\(error)"
        case let .unknownSite(name, known):
            "no site `\(name)` in the config" + (known.isEmpty ? "" : "; it has: \(known.joined(separator: ", "))")
        case let .place(site, error):
            "\(site): \(error)"
        case let .chrome(site, error):
            "\(site): \(error)"
        }
    }

    public var errorDescription: String? { description }
}

/// Reads the files every jump and check starts from: the config and each browser's
/// profile list.
public enum Inputs {
    public static func config(at url: URL = Paths.config()) throws(JumpError) -> Config {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw .noConfig(path: url.path)
        } catch {
            throw .unreadable(path: url.path, reason: error.localizedDescription)
        }
        do {
            return try ConfigParser.parse(text)
        } catch {
            throw .config(error)
        }
    }

    /// The browser's profile list, or why it can't be used: not installed (its folder may
    /// outlive it), missing, refused by macOS, or not a profile list.
    public static func catalog(
        for browser: Browser,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        installed: (Browser) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    ) -> CatalogRead {
        guard let url = browser.localState(home: home) else {
            return .unreadable("\(browser) has no profiles CapsJump can read")
        }
        guard installed(browser) else { return .notInstalled }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing(path: url.path)
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .refused(path: url.path)
        } catch {
            return .unreadable("\(browser)'s profile list at \(url.path) can't be read: \(error.localizedDescription)")
        }
        do {
            return .read(try ProfileCatalog.parse(localState: data))
        } catch {
            return .unreadable("\(browser)'s profile list at \(url.path) can't be used: \(error)")
        }
    }

    /// Reads each browser's list at most once: for one jump, or one check.
    public static func catalogs() -> (Browser) -> CatalogRead {
        var read: [Browser: CatalogRead] = [:]
        return { browser in
            if let known = read[browser] { return known }
            let fresh = catalog(for: browser)
            read[browser] = fresh
            return fresh
        }
    }
}

@MainActor
public final class Jumper {
    /// One compiled script per browser, by bundle id.
    private var scripting: [String: ChromeScripting] = [:]

    public init() {}

    public func jump(to name: String) async throws(JumpError) -> Outcome {
        let config = try Inputs.config()
        guard let site = config.site(named: name) else {
            throw .unknownSite(name, known: config.sites.map(\.name))
        }
        let destination: Destination
        do {
            destination = try Placement.place(site, defaultBrowser: Browsers.defaultBrowser(), catalog: Inputs.catalogs())
        } catch {
            throw .place(site: name, error)
        }
        do {
            return try await perform(destination)
        } catch {
            throw .chrome(site: name, error)
        }
    }

    private func perform(_ destination: Destination) async throws(ChromeError) -> Outcome {
        let browser = destination.browser
        let app = browser.support == .full ? ChromeLauncher.running(browser) : nil
        var windows: [ChromeWindow] = []
        var axWindows: [AXWindow] = []
        var scripting: ChromeScripting?
        if let app, destination.target?.canFocus ?? true {
            axWindows = try ChromeAccessibility.windows(of: app, browser: browser)
            if self.scripting[browser.bundleID] == nil {
                self.scripting[browser.bundleID] = try ChromeScripting(browser: browser)
            }
            scripting = self.scripting[browser.bundleID]
            windows = try scripting?.windows() ?? []
        }

        let action = try Jump.decide(
            destination: destination,
            running: app != nil,
            windows: windows,
            titles: axWindows.map(\.title)
        ) { (id: String) throws(ChromeError) -> WindowTabs in
            guard let scripting else { throw .windowGone(browser.displayName) }
            return try scripting.tabs(windowID: id)
        }

        switch action {
        case let .focus(windowID, tabIndex, titleIndex):
            guard let scripting, let app else { throw .windowGone(browser.displayName) }
            try scripting.focus(windowID: windowID, tabIndex: tabIndex)
            app.activate()
            if let titleIndex { ChromeAccessibility.raise(axWindows[titleIndex].element) }
            return .focused(site: destination.site.name, browser: browser.displayName, windowID: windowID, tabIndex: tabIndex)
        case let .open(profileDirectory, url, reason):
            try await ChromeLauncher.open(url, in: browser, profileDirectory: profileDirectory)
            return .opened(site: destination.site.name, browser: browser.displayName, profileDirectory: profileDirectory, reason: reason)
        }
    }
}
