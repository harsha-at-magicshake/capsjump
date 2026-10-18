// The browser table: names as a config writes them, which browsers CapsJump can read
// profiles and tabs from, the row a default browser's bundle id maps to, and where each
// browser keeps its profile list.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct BrowserTests {
    @Test func namesAreCaseInsensitive() {
        #expect(Browser.named("Brave") == .brave)
        #expect(Browser.named("chrome") == .chrome)
        #expect(Browser.named("opera") == nil)
    }

    @Test func profilesAndTabsOnlyWhereThereIsADataFolder() {
        #expect([Browser.chrome, .brave, .edge, .vivaldi, .chromium].allSatisfy { $0.support == .full })
        #expect([Browser.arc, .safari, .firefox].allSatisfy { $0.support == .plain })
    }

    @Test func aDefaultBrowserIsItsRowOrAPlainOne() {
        #expect(Browser.app(bundleID: "com.brave.Browser", displayName: "Brave Browser") == .brave)
        #expect(Browser.app(bundleID: nil, displayName: nil) == .chrome)
        let other = Browser.app(bundleID: "com.example.Web", displayName: "Web")
        #expect(other.name == nil)
        #expect(other.support == .plain)
        #expect(other.description == "Web")
    }

    @Test func eachBrowserKeepsItsOwnProfileList() {
        let home = URL(fileURLWithPath: "/Users/kim")
        #expect(Browser.brave.localState(home: home)?.path == "/Users/kim/Library/Application Support/BraveSoftware/Brave-Browser/Local State")
        #expect(Browser.chrome.profileFolder("Profile 1", home: home)?.path == "/Users/kim/Library/Application Support/Google/Chrome/Profile 1")
        #expect(Browser.safari.localState(home: home) == nil)
    }
}
