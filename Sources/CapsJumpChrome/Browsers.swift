// The browsers on this Mac: the one macOS opens web links with, read afresh each time so a
// change of default needs no reload, and which of the browsers CapsJump knows are
// installed.

import AppKit
import CapsJumpCore

public enum Browsers {
    /// The app that opens https links, as a row of the browser table when it is one;
    /// Chrome when macOS names none.
    public static func defaultBrowser() -> Browser {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
            return .chrome
        }
        let name = (FileManager.default.displayName(atPath: app.path) as NSString).deletingPathExtension
        return Browser.app(bundleID: Bundle(url: app)?.bundleIdentifier, displayName: name)
    }

    /// The browsers in the table that are installed, in the table's order.
    public static func installed() -> [Browser] {
        Browser.known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }
}
