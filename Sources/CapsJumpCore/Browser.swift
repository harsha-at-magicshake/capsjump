// The browsers a site can open in. Each keeps its profiles in a `Local State` file of
// Chrome's shape and answers Chrome's scripting, so a site lands on its tab in the right
// profile in either. A browser comes in here once someone who uses it has run CapsJump in
// it (CONTRIBUTING.md): Brave was, on macOS 27. Which one a site opens in is `Placement`'s.

import Foundation

public struct Browser: Sendable, Hashable, CustomStringConvertible {
    /// As `capsjump profiles --json` writes it: `chrome`, `brave`.
    public let id: String
    /// As messages say it: "Chrome", "Brave".
    public let name: String
    /// The app's own name, as System Settings lists it: "Google Chrome", "Brave Browser".
    public let appName: String
    public let bundleID: String
    /// The folder under `~/Library/Application Support` holding `Local State` and a folder
    /// per profile.
    let dataFolder: String

    public var description: String { name }

    public static let chrome = Browser(id: "chrome", name: "Chrome", appName: "Google Chrome", bundleID: "com.google.Chrome", dataFolder: "Google/Chrome")
    public static let brave = Browser(id: "brave", name: "Brave", appName: "Brave Browser", bundleID: "com.brave.Browser", dataFolder: "BraveSoftware/Brave-Browser")

    /// Every browser CapsJump knows, in the order a site's account is looked for in them.
    public static let known: [Browser] = [.chrome, .brave]

    /// The browser's own folder, which holds `Local State` and a folder per profile.
    public func data(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support").appendingPathComponent(dataFolder)
    }

    /// `Local State`, which maps each profile folder to its account.
    public func localState(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        data(home: home).appendingPathComponent("Local State")
    }

    /// One profile's folder, such as `Profile 1`.
    public func profileFolder(_ directory: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        data(home: home).appendingPathComponent(directory)
    }
}
