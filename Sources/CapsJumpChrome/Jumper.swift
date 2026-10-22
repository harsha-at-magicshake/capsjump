// One jump, live: read the config and every browser's profiles afresh (so edits need no
// reload), gather the site's browser's windows and titles, let Core decide, and carry the
// decision out. An open ends once a jump to the site would find the page's tab, so the next
// key lands on it.

import AppKit
import CapsJumpCore

/// What a jump did, and in which browser: Brave reuses Chrome's folder names, so a folder
/// alone doesn't say. Chrome's lines read as they always have, and Brave's name Brave.
public enum Outcome: Sendable, Equatable, CustomStringConvertible {
    case focused(site: String, browser: Browser, windowID: String, tabIndex: Int)
    case opened(site: String, browser: Browser, profileDirectory: String, reason: OpenReason)

    public var browser: Browser {
        switch self {
        case let .focused(_, browser, _, _), let .opened(_, browser, _, _): browser
        }
    }

    public var description: String {
        let owner = browser == .chrome ? "" : "\(browser)'s "
        return switch self {
        case let .focused(site, _, windowID, tabIndex):
            "\(site): focused tab \(tabIndex) of \(owner)window \(windowID)"
        case let .opened(site, _, profileDirectory, reason):
            "\(site): opened in \(owner)\(profileDirectory) (\(reason.rawValue))"
        }
    }
}

public enum JumpError: LocalizedError, Equatable, CustomStringConvertible {
    case noConfig(path: String)
    case unreadable(path: String, reason: String)
    case config(ConfigError)
    case unknownSite(String, known: [String])
    case place(site: String, PlaceError)
    /// In the site's browser.
    case chrome(site: String, browser: Browser, ChromeError)

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
        case let .chrome(site, browser, error):
            "\(site): \(error.description(in: browser))"
        }
    }

    public var errorDescription: String? { description }
}

/// Reads the two files every jump and check starts from.
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

    /// Every browser's profile list, read afresh.
    public static func lists() -> ProfileLists {
        ProfileLists { catalog(for: $0) }
    }

    /// The browser's profile list, or why it can't be used: not installed (its folder may
    /// outlive it), missing, refused by macOS, or not a profile list.
    public static func catalog(
        for browser: Browser,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        installed: (Browser) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    ) -> CatalogRead {
        guard installed(browser) else { return .notInstalled }
        let url = browser.localState(home: home)
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
            return .read(try ProfileCatalog.parse(localState: data, browser: browser))
        } catch {
            return .unreadable(error.description)
        }
    }
}

@MainActor
public final class Jumper {
    /// Chrome came to the front within 258 ms in every measured jump; a jump looks for up
    /// to 500 ms, and the next key waits that long at most.
    private static let landingReads = 11
    private static let landingPause = Duration.milliseconds(50)
    /// Chrome showed a new window's tab within about 250 ms of its helper quitting in 8
    /// measured opens; a jump looks up to 16 times, 50 ms apart, and the next key waits
    /// that long at most.
    private static let tabReads = 16
    private static let tabPause = Duration.milliseconds(50)

    /// One compiled script per browser.
    private var scripting: [Browser: ChromeScripting] = [:]
    /// Runs before a focus asks macOS to bring the browser forward; what it returns runs
    /// once the landing check has ended. The app uses it to make its request one macOS honours.
    private let activating: @MainActor () -> @MainActor () -> Void

    public init(activating: @escaping @MainActor () -> @MainActor () -> Void = { {} }) {
        self.activating = activating
    }

    public func jump(to name: String) async throws(JumpError) -> Outcome {
        let config = try Inputs.config()
        guard let site = config.site(named: name) else {
            throw .unknownSite(name, known: config.sites.map(\.name))
        }
        let target: Target
        do {
            target = try Placement.resolve(site, in: Inputs.lists())
        } catch {
            throw .place(site: name, error)
        }
        do {
            return try await perform(target)
        } catch {
            throw .chrome(site: name, browser: target.browser, error)
        }
    }

    /// What Chrome shows now, and what a jump to the target would do with it.
    private struct Reading {
        let chrome: NSRunningApplication?
        let axWindows: [AXWindow]
        let scripting: ChromeScripting?
        let action: Action
    }

    private func read(_ target: Target) throws(ChromeError) -> Reading {
        let browser = target.browser
        let chrome = ChromeLauncher.running(browser)
        var windows: [ChromeWindow] = []
        var axWindows: [AXWindow] = []
        var scripting: ChromeScripting?
        if let chrome, target.canFocus {
            axWindows = try ChromeAccessibility.windows(of: chrome)
            if self.scripting[browser] == nil {
                self.scripting[browser] = try ChromeScripting(browser: browser)
            }
            scripting = self.scripting[browser]
            windows = try scripting?.windows() ?? []
        }

        let action = try Jump.decide(
            target: target,
            chromeRunning: chrome != nil,
            windows: windows,
            titles: axWindows.map(\.title)
        ) { (id: String) throws(ChromeError) -> WindowTabs in
            guard let scripting else { throw .windowGone }
            return try scripting.tabs(windowID: id)
        }
        return Reading(chrome: chrome, axWindows: axWindows, scripting: scripting, action: action)
    }

    private func perform(_ target: Target) async throws(ChromeError) -> Outcome {
        let reading = try read(target)
        switch reading.action {
        case let .focus(windowID, tabIndex, titleIndex):
            guard let scripting = reading.scripting, let chrome = reading.chrome else { throw .windowGone }
            let window = reading.axWindows[titleIndex].element
            // Measured on macOS 26: Chrome's own activate, or Accessibility's frontmost,
            // brings every Chrome window forward over the app the person was in. Raised and
            // made main first, this window is the one AppKit's activation brings forward, by
            // default only the main and key windows. The order lands from another app on the
            // notarized release too (#48), as long as the app asking is one macOS honours
            // (`activating`, #46); the landing check reports the jump if it doesn't.
            let carryOut = { () throws(ChromeError) in
                try scripting.focus(windowID: windowID, tabIndex: tabIndex)
                try ChromeAccessibility.raise(window)
                chrome.activate()
            }
            let read = { () throws(ChromeError) -> Foreground in
                let front = NSWorkspace.shared.frontmostApplication
                let chromeInFront = front?.processIdentifier == chrome.processIdentifier
                let focused = chromeInFront ? try ChromeAccessibility.focusedWindow(of: chrome) : nil
                return Foreground(
                    chromeInFront: chromeInFront,
                    frontApp: front?.localizedName,
                    targetFocused: focused.map { CFEqual($0, window) } ?? false
                )
            }
            let restore = activating()
            defer { restore() }
            let missed = try await Landing.land(carryOut: carryOut, read: read, reads: Self.landingReads) {
                try? await Task.sleep(for: Self.landingPause)
            }
            if let missed { throw .notInFront(missed) }
            return .focused(site: target.site.name, browser: target.browser, windowID: windowID, tabIndex: tabIndex)
        case let .open(profileDirectory, url, reason):
            try await ChromeLauncher.open(url, in: target.browser, profileDirectory: profileDirectory)
            // Chrome can show the new tab a moment after the open returns; a key pressed
            // meanwhile would open the page twice. The jump ends once a jump would find it.
            await Handover.waitForTab(target: target, reads: Self.tabReads, decide: { try? self.read(target).action }) {
                try? await Task.sleep(for: Self.tabPause)
            }
            return .opened(site: target.site.name, browser: target.browser, profileDirectory: profileDirectory, reason: reason)
        }
    }
}
