// Asks for all the permissions at once, attributed to CapsJump itself, registers the app to
// start at login so the keys are there from the moment the Mac starts, then shows one
// alert with each one's state. Automation is granted per browser, and can be asked for
// only while that browser runs: setup starts the default browser when it is one CapsJump
// scripts, and asks for each other browser the config may use only if it is already
// running; the rest are asked for on their first jump. When macOS refuses to let CapsJump
// read a browser's profile list, the alert says so and offers the setting that allows it.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import ServiceManagement

@MainActor
enum Setup {
    /// True when a permission is known to be missing: Accessibility, Automation of the
    /// default browser (unknown while it is closed, which does not count), reading a
    /// profile list some site needs, or notifications.
    static func somethingMissing(notifier: Notifier) async -> Bool {
        if Permissions.accessibility(prompt: false) != .granted { return true }
        let browser = Browsers.defaultBrowser()
        if browser.support == .full, [.denied, .notAsked].contains(await Permissions.automation(of: browser, ask: false)) {
            return true
        }
        let config = (try? Inputs.config()) ?? Config(sites: [])
        for needed in Placement.browsersReadingProfiles(by: config, defaultBrowser: browser) {
            if case .refused = Inputs.catalog(for: needed) { return true }
        }
        return await notifier.state == .notAsked
    }

    /// One browser's line: its Automation state, or why it wasn't asked.
    private struct Automation {
        let browser: Browser
        var state: PermissionState = .unknown
        var problem: String?
        /// Not running, so asked for on its first jump instead.
        var deferred = false
        var refused = false

        var line: String {
            "Automation of \(browser): \(problem ?? state.rawValue)"
        }
    }

    static func run(notifier: Notifier) async {
        let accessibility = Permissions.accessibility(prompt: true)
        let defaultBrowser = Browsers.defaultBrowser()
        let config = try? Inputs.config()
        var automations: [Automation] = []
        let installed = Browsers.installed()
        let reading = Placement.browsersReadingProfiles(by: config ?? Config(sites: []), defaultBrowser: defaultBrowser)
        for browser in Placement.browsersUsed(by: config ?? Config(sites: []), defaultBrowser: defaultBrowser) where installed.contains(browser) {
            var automation = Automation(browser: browser)
            if browser == defaultBrowser {
                do {
                    _ = try await ChromeLauncher.start(browser)
                    automation.state = await Permissions.automation(of: browser, ask: true)
                } catch {
                    automation.problem = error.description
                }
            } else if ChromeLauncher.running(browser) != nil {
                automation.state = await Permissions.automation(of: browser, ask: true)
            } else {
                automation.problem = "asked on the first jump, since it isn't running"
                automation.deferred = true
            }
            if reading.contains(browser), case .refused = Inputs.catalog(for: browser) { automation.refused = true }
            automations.append(automation)
        }
        let notifications = await notifier.request()
        let login = startAtLogin()
        show(accessibility: accessibility, automations: automations, notifications: notifications, login: login)
    }

    /// Registers the app as a login item; turned off again from the menu bar, or in System
    /// Settings › General › Login Items & Extensions.
    private static func startAtLogin() -> SMAppService.Status {
        LoginItem.set(true)
        return SMAppService.mainApp.status
    }

    private static func show(
        accessibility: PermissionState,
        automations: [Automation],
        notifications: PermissionState,
        login: SMAppService.Status
    ) {
        let alert = NSAlert()
        let denied = automations.filter { $0.state == .denied }
        let refused = automations.filter(\.refused)
        let ready = accessibility == .granted && denied.isEmpty && refused.isEmpty
            && automations.allSatisfy { $0.state == .granted || $0.deferred }
        alert.messageText = ready ? "CapsJump is ready" : "CapsJump needs a permission"
        var lines = ["Accessibility: \(accessibility.rawValue)"]
        lines += automations.map(\.line)
        lines += refused.map { "Reading \($0.browser)'s profiles: refused by macOS" }
        lines += [
            "Notifications: \(notifications.rawValue)",
            "Starts at login: \(login == .enabled ? "yes" : login == .requiresApproval ? "waiting for approval" : "no")",
        ]
        if accessibility != .granted {
            lines.append("\nTurn CapsJump on under Privacy & Security › Accessibility.")
        }
        if !denied.isEmpty {
            let names = denied.map(\.browser.displayName).joined(separator: " and ")
            lines.append("\nTurn on \(names) under CapsJump in Privacy & Security › Automation.")
        }
        if !refused.isEmpty {
            lines.append("\nTurn CapsJump on under Privacy & Security › Full Disk Access, so it can read which profiles your browsers have.")
        }
        if login == .requiresApproval {
            lines.append("\nTurn CapsJump on under General › Login Items & Extensions.")
        }
        if !ready {
            lines.append("\nThen run `capsjump setup` again to confirm.")
        }
        alert.informativeText = lines.joined(separator: "\n")

        var settings: [String] = []
        if accessibility != .granted {
            alert.addButton(withTitle: "Open Accessibility Settings")
            settings.append("Privacy_Accessibility")
        }
        if !denied.isEmpty {
            alert.addButton(withTitle: "Open Automation Settings")
            settings.append("Privacy_Automation")
        }
        if !refused.isEmpty {
            alert.addButton(withTitle: "Open Full Disk Access Settings")
            settings.append("Privacy_AllFiles")
        }
        alert.addButton(withTitle: "Done")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if settings.indices.contains(response),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settings[response])") {
            NSWorkspace.shared.open(url)
        }
    }
}
