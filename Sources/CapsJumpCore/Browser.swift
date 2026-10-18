// The browsers a site can open in. Chrome and the browsers built on it the same way
// (Brave, Edge, Vivaldi, Chromium) keep their profiles in a `Local State` file of
// Chrome's shape and answer Chrome's scripting, so CapsJump can pick a profile and find a
// site's open tab in them: full support. Any other browser, the Mac's default included
// when it is one CapsJump doesn't know, only opens the page: plain support.

import Foundation

public struct Browser: Sendable, Hashable, CustomStringConvertible {
    public enum Support: Sendable {
        /// Profiles, tab search and focusing, as in Chrome.
        case full
        /// The page is opened in it; nothing more.
        case plain
    }

    /// The name a config writes in `browser:`; nil for a default browser outside the table.
    public let name: String?
    public let bundleID: String
    /// As messages say it: "Google Chrome", "Brave".
    public let displayName: String
    /// The folder under `~/Library/Application Support` holding `Local State` and a folder
    /// per profile; nil for a browser with plain support.
    public let dataFolder: String?

    init(name: String?, bundleID: String, displayName: String, dataFolder: String?) {
        self.name = name
        self.bundleID = bundleID
        self.displayName = displayName
        self.dataFolder = dataFolder
    }

    public var support: Support {
        dataFolder == nil ? .plain : .full
    }

    public var description: String {
        displayName
    }

    public static let chrome = Browser(name: "chrome", bundleID: "com.google.Chrome", displayName: "Google Chrome", dataFolder: "Google/Chrome")
    public static let brave = Browser(name: "brave", bundleID: "com.brave.Browser", displayName: "Brave", dataFolder: "BraveSoftware/Brave-Browser")
    public static let edge = Browser(name: "edge", bundleID: "com.microsoft.edgemac", displayName: "Microsoft Edge", dataFolder: "Microsoft Edge")
    public static let vivaldi = Browser(name: "vivaldi", bundleID: "com.vivaldi.Vivaldi", displayName: "Vivaldi", dataFolder: "Vivaldi")
    public static let chromium = Browser(name: "chromium", bundleID: "org.chromium.Chromium", displayName: "Chromium", dataFolder: "Chromium")
    public static let arc = Browser(name: "arc", bundleID: "company.thebrowser.Browser", displayName: "Arc", dataFolder: nil)
    public static let safari = Browser(name: "safari", bundleID: "com.apple.Safari", displayName: "Safari", dataFolder: nil)
    public static let firefox = Browser(name: "firefox", bundleID: "org.mozilla.firefox", displayName: "Firefox", dataFolder: nil)

    /// Every browser a config may name, in the order messages list them.
    public static let known: [Browser] = [.chrome, .brave, .edge, .vivaldi, .chromium, .arc, .safari, .firefox]

    /// The browser a config's `browser:` names, ignoring case.
    public static func named(_ name: String) -> Browser? {
        let wanted = name.lowercased()
        return known.first { $0.name == wanted }
    }

    /// The browser for the app that opens web links: its row in the table, else a browser
    /// with plain support; Chrome when the Mac records no app at all.
    public static func app(bundleID: String?, displayName: String?) -> Browser {
        guard let bundleID else { return .chrome }
        if let row = known.first(where: { $0.bundleID == bundleID }) { return row }
        return Browser(name: nil, bundleID: bundleID, displayName: displayName ?? bundleID, dataFolder: nil)
    }

    /// The browser's own folder, which holds `Local State` and a folder per profile.
    public func data(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        dataFolder.map { home.appendingPathComponent("Library/Application Support").appendingPathComponent($0) }
    }

    /// `Local State`, which maps each profile folder to its account.
    public func localState(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        data(home: home)?.appendingPathComponent("Local State")
    }

    /// One profile's folder, such as `Profile 1`.
    public func profileFolder(_ directory: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        data(home: home)?.appendingPathComponent(directory)
    }
}
