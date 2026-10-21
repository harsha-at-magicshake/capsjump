// Where each browser keeps its profile list.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct BrowserTests {
    @Test func eachBrowserKeepsItsOwnProfileList() {
        let home = URL(fileURLWithPath: "/Users/kim")
        #expect(Browser.brave.localState(home: home).path == "/Users/kim/Library/Application Support/BraveSoftware/Brave-Browser/Local State")
        #expect(Browser.chrome.localState(home: home).path == "/Users/kim/Library/Application Support/Google/Chrome/Local State")
        #expect(Browser.brave.profileFolder("Default", home: home).path == "/Users/kim/Library/Application Support/BraveSoftware/Brave-Browser/Default")
    }
}
