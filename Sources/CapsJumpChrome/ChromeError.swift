// What can go wrong talking to a browser, each case worded for the person who has to fix
// it and naming the browser. Only the app talks to a browser, so these reach people as its
// notifications; the two permission cases open the Welcome window when clicked.

import Foundation

public enum ChromeError: Error, Equatable, CustomStringConvertible {
    case notInstalled(String)
    case automationDenied(String)
    case accessibilityDenied
    case windowGone(String)
    case script(String, code: Int, message: String)
    case accessibility(String, code: Int32)
    case launch(String, String)

    public var description: String {
        switch self {
        case let .notInstalled(browser):
            "\(browser) is not installed"
        case let .automationDenied(browser):
            "CapsJump may not control \(browser); click to allow it, or turn on \(browser) under CapsJump in System Settings › Privacy & Security › Automation"
        case .accessibilityDenied:
            "CapsJump has no Accessibility permission; click to finish setting up"
        case let .windowGone(browser):
            "\(browser), or the window, closed during the jump"
        case let .script(browser, code, message):
            "\(browser) refused a script command (\(code)): \(message)"
        case let .accessibility(browser, code):
            "Accessibility could not read \(browser)'s windows (error \(code))"
        case let .launch(browser, message):
            "could not open \(browser): \(message)"
        }
    }

    /// A permission the person can grant, as opposed to a browser that quit or failed.
    public var isMissingPermission: Bool {
        switch self {
        case .accessibilityDenied, .automationDenied: true
        default: false
        }
    }
}
