// Which browser Add Current Tab reads: the one in front, or else the one used last. The
// menu bar's menu opens without CapsJump coming forward, so the browser is usually still
// the front app; when something else is (a key brought an app forward, say), the last
// browser that was is remembered here, from macOS's app activations.

import AppKit
import CapsJumpChrome
import CapsJumpCore

@MainActor
final class BrowserTracker {
    private var last: Browser?
    private var observer: NSObjectProtocol?

    init() {
        last = NSWorkspace.shared.frontmostApplication.flatMap(Self.browser)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let browser = app.flatMap(Self.browser) else { return }
            MainActor.assumeIsolated { self?.last = browser }
        }
    }

    /// The browser in front, else the last one in front while it still runs, else Chrome.
    func tabBrowser() -> Browser {
        if let front = NSWorkspace.shared.frontmostApplication.flatMap(Self.browser) { return front }
        if let last, ChromeLauncher.running(last) != nil { return last }
        return .chrome
    }

    private nonisolated static func browser(_ app: NSRunningApplication) -> Browser? {
        Browser.known.first { $0.bundleID == app.bundleIdentifier }
    }
}
