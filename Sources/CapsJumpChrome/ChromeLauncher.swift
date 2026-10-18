// Opens a URL in a browser. In one profile, the way `open -na "Google Chrome" --args
// --profile-directory=<dir> <url>` does: a new instance is asked for, which hands the URL
// to the running browser (a new tab in that profile's window, or a new window) or starts
// it when none runs. With no profile, as a clicked link opens: the browser picks its own
// profile, the last one used. Done through NSWorkspace, so no process is spawned.

import AppKit
import CapsJumpCore

@MainActor
public enum ChromeLauncher {
    public static func running(_ browser: Browser) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first { !$0.isTerminated }
    }

    public static func open(_ url: URL, in browser: Browser, profileDirectory: String?) async throws(ChromeError) {
        let app = try location(of: browser)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            if let profileDirectory {
                configuration.arguments = ["--profile-directory=\(profileDirectory)", url.absoluteString]
                configuration.createsNewApplicationInstance = true
                _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            } else {
                _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
            }
        } catch {
            throw .launch(browser.displayName, error.localizedDescription)
        }
    }

    /// Starts the browser without asking it for any page, and waits until it runs.
    public static func start(_ browser: Browser, timeout: Duration = .seconds(20)) async throws(ChromeError) -> NSRunningApplication {
        if let running = running(browser) { return running }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: try location(of: browser), configuration: configuration)
        } catch let error as ChromeError {
            throw error
        } catch {
            throw .launch(browser.displayName, error.localizedDescription)
        }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let running = running(browser), running.isFinishedLaunching { return running }
            try? await Task.sleep(for: .milliseconds(200))
        }
        throw .launch(browser.displayName, "it did not finish starting within \(timeout)")
    }

    private static func location(of browser: Browser) throws(ChromeError) -> URL {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else {
            throw .notInstalled(browser.displayName)
        }
        return app
    }
}
