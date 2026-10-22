// The jump log names the browser a jump was in once it isn't Chrome: Brave reuses Chrome's
// folder names, so `opened in Profile 5` alone could be either. Chrome's lines stay as they were.

import CapsJumpCore
import Testing
@testable import CapsJumpChrome

@Suite struct OutcomeTests {
    @Test func chromesLinesStay() {
        #expect(Outcome.opened(site: "mail", browser: .chrome, profileDirectory: "Profile 5", reason: .noMatchingTab).description == "mail: opened in Profile 5 (no open tab matches)")
        #expect(Outcome.focused(site: "mail", browser: .chrome, windowID: "12", tabIndex: 3).description == "mail: focused tab 3 of window 12")
    }

    @Test func bravesLinesNameBrave() {
        let opened = Outcome.opened(site: "mail", browser: .brave, profileDirectory: "Profile 5", reason: .noMatchingTab)
        #expect(opened.description == "mail: opened in Brave's Profile 5 (no open tab matches)")
        #expect(opened.browser == .brave)
        #expect(Outcome.focused(site: "mail", browser: .brave, windowID: "12", tabIndex: 3).description == "mail: focused tab 3 of Brave's window 12")
    }
}
