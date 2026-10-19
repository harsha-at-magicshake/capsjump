// The permissions CapsJump uses, read so the Welcome window can tick each the moment it is
// granted. The browser's and the notifications' are asked on their own when the person
// presses their buttons, attributed to CapsJump itself; the browser starts only for its
// button, since Automation can be asked for only while it runs. The browser is the one sites
// open in: the default browser when CapsJump scripts it, else Chrome, where sites with an
// account fall back. Accessibility is never asked here: macOS shows its own request whenever
// CapsJump reads it without access (see Permissions), and that one request is the only ask.
// When macOS won't let CapsJump read the browser's profile list, the window says so and
// links Full Disk Access. The login item is the Welcome window's switch.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import ServiceManagement

@MainActor
enum Setup {
    /// The System Settings panes the window links to.
    enum Pane: String {
        case accessibility = "com.apple.preference.security?Privacy_Accessibility"
        case automation = "com.apple.preference.security?Privacy_Automation"
        case fullDiskAccess = "com.apple.preference.security?Privacy_AllFiles"
        case notifications = "com.apple.preference.notifications"
        case loginItems = "com.apple.LoginItems-Settings.extension"
    }

    static var hasAccessibility: Bool {
        Permissions.accessibility == .granted
    }

    /// The browser the window asks about; nil when neither the default browser (one CapsJump
    /// scripts) nor Chrome is installed.
    static var browser: Browser? {
        let installed = Browsers.installed()
        let preferred = Browsers.defaultBrowser()
        if preferred.support == .full, installed.contains(preferred) { return preferred }
        return installed.contains(.chrome) ? .chrome : nil
    }

    /// Automation of the browser as it stands; unknown while it is closed.
    static func access(of browser: Browser) async -> PermissionState {
        guard ChromeLauncher.running(browser) != nil else { return .unknown }
        return await Permissions.automation(of: browser, ask: false)
    }

    /// Starts the browser when it is closed, then asks for Automation of it.
    static func ask(for browser: Browser) async throws(ChromeError) -> PermissionState {
        _ = try await ChromeLauncher.start(browser)
        return await Permissions.automation(of: browser, ask: true)
    }

    /// Whether macOS refuses CapsJump the browser's profile list.
    static func profilesRefused(_ browser: Browser) -> Bool {
        if case .refused = Inputs.catalog(for: browser) { true } else { false }
    }

    /// The browser's profiles, for the starter file's example site; nil when unreadable.
    static func catalog(_ browser: Browser) -> ProfileCatalog? {
        if case let .read(catalog) = Inputs.catalog(for: browser) { catalog } else { nil }
    }

    static func open(_ pane: Pane) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane.rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }
}
