// Each error is worded for the browser the jump was in: Chrome's words stay as they were,
// and Brave's name Brave, and "Brave Browser" where System Settings lists the app.

import CapsJumpCore
import Testing
@testable import CapsJumpChrome

@Suite struct ChromeErrorTests {
    @Test func chromesWordsStay() {
        #expect(ChromeError.notInstalled.description == "Google Chrome is not installed")
        #expect(ChromeError.windowGone.description == "Chrome, or the window, closed during the jump")
    }

    @Test func braveIsNamedWhereTheJumpWasInBrave() {
        #expect(ChromeError.notInstalled.description(in: .brave) == "Brave Browser is not installed")
        #expect(ChromeError.automationDenied.description(in: .brave) == "CapsJump may not control Brave; click to allow it, or turn on Brave Browser under CapsJump in System Settings › Privacy & Security › Automation")
        #expect(ChromeError.notInFront(.otherWindow).description(in: .brave) == "Brave kept another of its windows in front")
        #expect(JumpError.chrome(site: "mail", browser: .brave, .windowGone).description == "mail: Brave, or the window, closed during the jump")
    }
}
