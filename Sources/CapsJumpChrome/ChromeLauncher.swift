// Opens a URL in one profile of a browser (Chrome, or Brave, which works the same way),
// the way `open -na "Google Chrome" --args --profile-directory=<dir> <url>` does: a new
// instance is asked for, which hands the URL to the running browser (a new tab in that
// profile's window, or a new window) or starts it when none runs. Done through NSWorkspace, so no process is spawned. An open
// returns once that new instance has handed the page over and quit, so the next jump's
// script cannot reach the quitting process.

import AppKit
import CapsJumpCore

@MainActor
public enum ChromeLauncher {
    /// The new instance quit 44-87 ms after the open returned in 24 measured opens; an open
    /// looks for up to 2 s, and the next key waits that long at most.
    private static let handoverReads = 40
    private static let handoverPause = Duration.milliseconds(50)

    public static func running(_ browser: Browser = .chrome) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first { !$0.isTerminated }
    }

    public static func open(_ url: URL, in browser: Browser = .chrome, profileDirectory: String) async throws(ChromeError) {
        let before = running(browser)
        let launched = try await launch(browser, arguments: ["--profile-directory=\(profileDirectory)", url.absoluteString], activates: true, newInstance: true)
        await Handover.wait(launched: launched, before: before, isGone: { launched.isTerminated }, reads: handoverReads) {
            try? await Task.sleep(for: handoverPause)
        }
    }

    /// Starts the browser without asking it for any page, and waits until it runs.
    public static func start(_ browser: Browser = .chrome, timeout: Duration = .seconds(20)) async throws(ChromeError) -> NSRunningApplication {
        if let running = running(browser) { return running }
        try await launch(browser, arguments: [], activates: false, newInstance: false)
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let running = running(browser), running.isFinishedLaunching { return running }
            try? await Task.sleep(for: .milliseconds(200))
        }
        throw .launch("\(browser) did not finish starting within \(timeout)")
    }

    @discardableResult
    private static func launch(_ browser: Browser, arguments: [String], activates: Bool, newInstance: Bool) async throws(ChromeError) -> NSRunningApplication {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else {
            throw .notInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = activates
        configuration.createsNewApplicationInstance = newInstance
        do {
            return try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        } catch {
            throw .launch(error.localizedDescription)
        }
    }
}
