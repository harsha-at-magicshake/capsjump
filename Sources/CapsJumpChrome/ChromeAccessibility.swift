// A browser's windows through Accessibility: the whole window titles, which end in the
// profile's label, raising one exact window, and which window has the focus. Read straight
// from the browser's process, so no second Automation grant (for System Events) is needed.

import AppKit
import ApplicationServices
import CapsJumpCore

public struct AXWindow {
    public let title: String
    public let element: AXUIElement
}

@MainActor
public enum ChromeAccessibility {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// The browser's standard windows (minimized ones included), front to back.
    public static func windows(of app: NSRunningApplication, browser: Browser) throws(ChromeError) -> [AXWindow] {
        guard isTrusted else { throw .accessibilityDenied }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        switch status {
        case .success: break
        case .noValue: return []
        default: throw failure(status, during: .read, browser: browser)
        }
        let windows = value as? [AXUIElement] ?? []
        return windows.compactMap { window in
            guard string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole as String else { return nil }
            return AXWindow(title: string(window, kAXTitleAttribute) ?? "", element: window)
        }
    }

    /// Makes the window the browser's main window and raises it above its others.
    /// Un-minimizing is the script's (`ChromeScripting.focus`).
    public static func raise(_ window: AXUIElement, browser: Browser) throws(ChromeError) {
        let main = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        guard main == .success else { throw failure(main, during: .raise, browser: browser) }
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        guard raised == .success else { throw failure(raised, during: .raise, browser: browser) }
    }

    /// The browser's focused window, or nil when it has none.
    public static func focusedWindow(of app: NSRunningApplication, browser: Browser) throws(ChromeError) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value)
        switch status {
        case .success: break
        case .noValue: return nil
        default: throw failure(status, during: .read, browser: browser)
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// A window's whole title, as its window list reports it.
    public static func title(of window: AXUIElement) -> String? {
        string(window, kAXTitleAttribute)
    }

    enum Step { case read, raise }

    /// What a failed status means for the step that got it.
    static func failure(_ status: AXError, during step: Step, browser: Browser) -> ChromeError {
        switch status {
        case .apiDisabled: .accessibilityDenied
        case .invalidUIElement: .windowGone(browser.displayName)
        default: step == .read ? .accessibility(browser.displayName, code: status.rawValue) : .raise(browser.displayName, code: status.rawValue)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
