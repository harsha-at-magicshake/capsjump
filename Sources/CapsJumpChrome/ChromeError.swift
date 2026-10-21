// What can go wrong talking to a browser, each case worded for the person who has to fix
// it, in the words of the browser the jump was in (Chrome's unless said). Only the app
// talks to a browser, so these reach people as its notifications; the two permission cases
// open the Welcome window when clicked.

import CapsJumpCore
import Foundation

public enum ChromeError: Error, Equatable, CustomStringConvertible {
    case notInstalled
    case automationDenied
    case accessibilityDenied
    case windowGone
    case script(code: Int, message: String)
    case accessibility(code: Int32)
    case raise(code: Int32)
    case notInFront(NotInFront)
    case launch(String)

    public var description: String {
        description(in: .chrome)
    }

    /// The message for a jump in `browser`.
    public func description(in browser: Browser) -> String {
        switch self {
        case .notInstalled:
            "\(browser.appName) is not installed"
        case .automationDenied:
            "CapsJump may not control \(browser); click to allow it, or turn on \(browser.appName) under CapsJump in System Settings › Privacy & Security › Automation"
        case .accessibilityDenied:
            "CapsJump has no Accessibility permission; click to finish setting up"
        case .windowGone:
            "\(browser), or the window, closed during the jump"
        case let .script(code, message):
            "\(browser) refused a script command (\(code)): \(message)"
        case let .accessibility(code):
            "Accessibility could not read \(browser)'s windows (error \(code))"
        case let .raise(code):
            "Accessibility could not bring \(browser)'s window forward (error \(code))"
        case .notInFront(.otherApp(let app)):
            "the window didn't come to the front; \(app ?? "another app") stayed in front"
        case .notInFront(.otherWindow):
            "\(browser) kept another of its windows in front"
        case let .launch(message):
            "could not open \(browser): \(message)"
        }
    }
}
