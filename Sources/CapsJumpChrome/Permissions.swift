// The two permissions a jump needs, read and asked for on CapsJump's own behalf:
// Accessibility (window titles, raising a window) and Automation of each browser (tabs).

import AppKit
import ApplicationServices
import Carbon
import CapsJumpCore

public enum PermissionState: String, Sendable {
    case granted
    case denied = "not granted"
    case notAsked = "not asked yet"
    /// Automation can be read only while the browser runs.
    case unknown = "unknown (the browser is not running)"
}

public enum Permissions {
    /// Whether Accessibility is granted; with `prompt`, macOS shows its request when not.
    @MainActor
    public static func accessibility(prompt: Bool) -> PermissionState {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
    }

    /// Whether CapsJump may send the browser Apple Events; with `ask`, macOS shows its
    /// request without any command reaching the browser. Blocks while the request is up, so
    /// it runs off the main thread.
    public static func automation(of browser: Browser, ask: Bool) async -> PermissionState {
        let bundleID = browser.bundleID
        return await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
            switch status {
            case noErr: return PermissionState.granted
            case OSStatus(errAEEventNotPermitted): return .denied
            case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
            default: return .unknown
            }
        }.value
    }
}
