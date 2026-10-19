// Window pairing and the jump decision, on the window lists measured on a real Mac:
// Chrome shortens names with "…", two profiles show the same page, and a window
// Accessibility can't see must cost only its own pairing.

import Foundation
import Testing
@testable import CapsJumpCore

private func title(_ page: String, _ label: String) -> String {
    "\(page) - Google Chrome \u{2013} \(label)"
}

private let acme = "Alex (acme.dev)"
private let kim = "kim@initech.com"
private let lee = "lee@initech.com"

@Suite struct WindowPairingTests {
    @Test func namePrefixStopsAtEllipsisAndCaps() {
        #expect(WindowPairing.namePrefix("Login | 1Password \u{2014} Password M\u{2026}ams, \u{2026}") == "Login | 1Password \u{2014} ")
        #expect(WindowPairing.namePrefix("Short\u{2026}") == "Short")
        #expect(WindowPairing.namePrefix("New chat - Claude") == "New chat - Claude")
        #expect(WindowPairing.namePrefix("") == "")
    }

    @Test func pairsTheMeasuredFiveWindows() {
        let chrome = [
            ChromeWindow(id: "1", name: "1Password for Acme"),
            ChromeWindow(id: "2", name: "Inbox - alex@umbrella.co - Umbrella Mail"),
            ChromeWindow(id: "3", name: "New chat - Claude"),
            ChromeWindow(id: "4", name: "New chat - Claude"),
            ChromeWindow(id: "5", name: "Inbox - alex@globex.io - Globex Mail"),
        ]
        let titles = [
            title("1Password for Acme", acme),
            title("Inbox - alex@umbrella.co - Umbrella Mail - High memory usage - 1.0 GB", "Alex (alex@umbrella.co)"),
            title("New chat - Claude", kim),
            title("New chat - Claude", lee),
            title("Inbox - alex@globex.io - Globex Mail", "Alex (globex.io)"),
        ]
        let pairing = WindowPairing.pair(chrome: chrome, titles: titles)
        #expect(pairing == ["1": 0, "2": 1, "3": 2, "4": 3, "5": 4])
        #expect(WindowPairing.windows(labelled: lee, chrome: chrome, titles: titles, pairing: pairing).map(\.window.id) == ["4"])
    }

    @Test func shortenedNamePairsWithItsWholeTitle() {
        let chrome = [ChromeWindow(id: "7", name: "Login | 1Password \u{2014} Password M\u{2026}ams, \u{2026}")]
        let titles = [title("Login | 1Password \u{2014} Password Manager for Teams, Businesses", acme)]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["7": 0])
    }

    @Test func windowMissingFromAccessibilityCostsOnlyItsGroup() {
        // Window 2 is on another Space: Accessibility lists four titles for five windows.
        let chrome = [
            ChromeWindow(id: "1", name: "GitHub"),
            ChromeWindow(id: "2", name: "Gmail"),
            ChromeWindow(id: "3", name: "New chat - Claude"),
            ChromeWindow(id: "4", name: "New chat - Claude"),
            ChromeWindow(id: "5", name: "Docs"),
        ]
        let titles = [
            title("GitHub", acme),
            title("New chat - Claude", kim),
            title("New chat - Claude", lee),
            title("Docs", acme),
        ]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["1": 0, "3": 1, "4": 2, "5": 3])
    }

    @Test func identicalWindowsWithOneMissingStayUnpaired() {
        // Two windows on the same page, one invisible: no title can say which is which.
        let chrome = [
            ChromeWindow(id: "1", name: "New chat - Claude"),
            ChromeWindow(id: "2", name: "New chat - Claude"),
            ChromeWindow(id: "3", name: "GitHub"),
        ]
        let titles = [title("New chat - Claude", lee), title("GitHub", acme)]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["3": 1])
    }

    @Test func orderBreaksTiesBetweenIdenticalWindows() {
        let chrome = [ChromeWindow(id: "10", name: "New Tab"), ChromeWindow(id: "20", name: "New Tab")]
        let titles = [title("New Tab", lee), title("New Tab", kim)]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["10": 0, "20": 1])
    }

    @Test func singleCompletePairingWinsWhenOrderDisagrees() {
        // "New" is compatible with both titles, "New chat - Claude" only with the first;
        // front-to-back order would pair "New" with the chat, leaving the other stranded.
        let chrome = [ChromeWindow(id: "1", name: "New"), ChromeWindow(id: "2", name: "New chat - Claude")]
        let titles = [title("New chat - Claude", kim), title("New Tab", lee)]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["1": 1, "2": 0])
    }

    @Test func labelMustBeTheWholeEnding() {
        let chrome = [ChromeWindow(id: "1", name: "X")]
        let titles = [title("X", "Alex (globex.io)")]
        let pairing = WindowPairing.pair(chrome: chrome, titles: titles)
        #expect(WindowPairing.windows(labelled: "globex.io", chrome: chrome, titles: titles, pairing: pairing).isEmpty)
        #expect(WindowPairing.windows(labelled: "Alex (globex.io)", chrome: chrome, titles: titles, pairing: pairing).count == 1)
    }

    @Test func braveEndsItsTitlesWithAHyphenAndTheLabel() {
        // As measured in Brave: "<page> - Brave - <profile>", a plain hyphen where Chrome has "–".
        let brave = [ChromeWindow(id: "1", name: "Inbox - Gmail"), ChromeWindow(id: "2", name: "Sign in")]
        let titles = ["Inbox - Gmail - Brave - Parents", "Sign in - Brave - Work"]
        let pairing = WindowPairing.pair(chrome: brave, titles: titles)
        #expect(WindowPairing.windows(labelled: "Parents", chrome: brave, titles: titles, pairing: pairing).map(\.window.id) == ["1"])
        #expect(WindowPairing.windows(labelled: "Work", chrome: brave, titles: titles, pairing: pairing).map(\.window.id) == ["2"])
        #expect(WindowPairing.windows(labelled: "Brave", chrome: brave, titles: titles, pairing: pairing).isEmpty)
    }

    @Test func aTitleFitsTheWindowWhoseNameItStartsWith() {
        // How a jump knows it landed on a window Accessibility couldn't pair: the browser's
        // focused title, measured in Brave, against the name its scripting gave the window.
        let title = "Inbox (925) - manjulagurram123@gmail.com - Gmail - Brave - Parents"
        #expect(WindowPairing.title(title, fits: ChromeWindow(id: "1", name: "Inbox (925) - manjulagurram123@gmail.com - Gmail")))
        #expect(WindowPairing.title(title, fits: ChromeWindow(id: "1", name: "Inbox (925) - manjul…gmail.com - Gmail")))
        #expect(!WindowPairing.title(title, fits: ChromeWindow(id: "2", name: "Sign in is not complete")))
        #expect(!WindowPairing.title(title, fits: ChromeWindow(id: "3", name: "")))
    }

    @Test func namelessWindowPairsWithNothingAndHarmsNoOne() {
        let chrome = [ChromeWindow(id: "1", name: ""), ChromeWindow(id: "2", name: "GitHub")]
        let titles = [title("Untitled", kim), title("GitHub", acme)]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["2": 1])
    }

    @Test func noWindowsPairsNothing() {
        #expect(WindowPairing.pair(chrome: [], titles: []).isEmpty)
        #expect(WindowPairing.pair(chrome: [], titles: [title("X", acme)]).isEmpty)
    }
}

@Suite struct JumpTests {
    private let profile = ChromeProfile(directory: "Profile 26", name: kim, email: "", givenName: "")
    private let url = URL(string: "https://claude.ai/new")!

    private func site(match: [String] = ["claude.ai/"]) -> Site {
        Site(name: "claude-kim", account: kim, profile: nil, open: url, match: match)
    }

    /// In kim's profile of Chrome, as the site names it.
    private func destination(match: [String] = ["claude.ai/"], shared: Bool = false, label: String? = kim) -> Destination {
        let target = Target(
            site: site(match: match),
            profile: profile,
            sharedLabelWith: shared ? [ChromeProfile(directory: "Profile 27", name: kim, email: "", givenName: "")] : []
        )
        return Destination(site: target.site, browser: .chrome, target: target, fellBack: false, isDefault: true, windowLabel: label)
    }

    /// No account: any window of the browser, and its own choice of profile.
    private func anyProfile(_ browser: Browser = .brave, match: [String] = ["claude.ai/"]) -> Destination {
        Destination(site: site(match: match), browser: browser, target: nil, fellBack: false, isDefault: true, windowLabel: nil)
    }

    private let chrome = [
        ChromeWindow(id: "1", name: "GitHub"),
        ChromeWindow(id: "2", name: "New chat - Claude"),
        ChromeWindow(id: "3", name: "Docs"),
    ]
    private let titles = [
        title("GitHub", kim),
        title("New chat - Claude", lee),
        title("Docs", kim),
    ]

    private func tabs(_ table: [String: WindowTabs]) -> (String) throws(TabsError) -> WindowTabs {
        { id throws(TabsError) in
            guard let tabs = table[id] else { throw TabsError.unexpectedWindow(id) }
            return tabs
        }
    }

    enum TabsError: Error, Equatable { case unexpectedWindow(String), denied }

    @Test func activeTabWinsThenFirstMatchFrontToBack() {
        let windows = [
            WindowTabs(windowID: "1", urls: ["https://claude.ai/a", "https://claude.ai/b"], activeIndex: 2),
            WindowTabs(windowID: "3", urls: ["https://claude.ai/c"], activeIndex: 1),
        ]
        #expect(Jump.chooseTab(prefixes: ["claude.ai/"], windows: windows)! == ("1", 2))
        #expect(Jump.chooseTab(prefixes: ["claude.ai/c", "claude.ai/"], windows: windows)! == ("3", 1))
        let inactive = [WindowTabs(windowID: "1", urls: ["https://x.com", "https://www.claude.ai/z"], activeIndex: 1)]
        #expect(Jump.chooseTab(prefixes: ["claude.ai/"], windows: inactive)! == ("1", 2))
        #expect(Jump.chooseTab(prefixes: ["github.com/"], windows: windows) == nil)
        #expect(Jump.chooseTab(prefixes: ["x.com/"], windows: [WindowTabs(windowID: "9", urls: [], activeIndex: 0)]) == nil)
    }

    @Test func focusesOnlyTheProfilesWindows() throws {
        // Window 2 shows Claude but belongs to lee; it is never read.
        let action = try Jump.decide(destination: destination(), running: true, windows: chrome, titles: titles, tabs: tabs([
            "1": WindowTabs(windowID: "1", urls: ["https://github.com"], activeIndex: 1),
            "3": WindowTabs(windowID: "3", urls: ["https://docs.x", "https://claude.ai/chat/1"], activeIndex: 1),
        ]))
        #expect(action == .focus(windowID: "3", tabIndex: 2, titleIndex: 2))
    }

    @Test func opensWhenNothingMatches() throws {
        let action = try Jump.decide(destination: destination(match: ["mail.google.com/"]), running: true, windows: chrome, titles: titles, tabs: tabs([
            "1": WindowTabs(windowID: "1", urls: ["https://github.com"], activeIndex: 1),
            "3": WindowTabs(windowID: "3", urls: ["https://docs.x"], activeIndex: 1),
        ]))
        #expect(action == .open(profileDirectory: "Profile 26", url: url, reason: .noMatchingTab))
    }

    @Test func opensWithoutReadingWhenClosedOrLabelShared() throws {
        let none = tabs([:])
        #expect(try Jump.decide(destination: destination(), running: false, windows: chrome, titles: titles, tabs: none)
            == .open(profileDirectory: "Profile 26", url: url, reason: .notRunning))
        #expect(try Jump.decide(destination: destination(shared: true), running: true, windows: chrome, titles: titles, tabs: none)
            == .open(profileDirectory: "Profile 26", url: url, reason: .sharedLabel))
    }

    @Test func readErrorIsThrownNeverOpened() {
        #expect(throws: TabsError.denied) {
            try Jump.decide(destination: destination(), running: true, windows: chrome, titles: titles) { (_: String) throws(TabsError) -> WindowTabs in
                throw TabsError.denied
            }
        }
    }

    private let everyWindow: [String: WindowTabs] = [
        "1": WindowTabs(windowID: "1", urls: ["https://github.com"], activeIndex: 1),
        "2": WindowTabs(windowID: "2", urls: ["https://docs.x", "https://claude.ai/chat/1"], activeIndex: 1),
        "3": WindowTabs(windowID: "3", urls: ["https://docs.x"], activeIndex: 1),
    ]

    @Test func noProfileSearchesEveryPairedWindow() throws {
        let action = try Jump.decide(destination: anyProfile(), running: true, windows: chrome, titles: titles, tabs: tabs(everyWindow))
        #expect(action == .focus(windowID: "2", tabIndex: 2, titleIndex: 1))
    }

    @Test func noProfileOpensWithNoFolder() throws {
        let action = try Jump.decide(destination: anyProfile(match: ["mail.google.com/"]), running: true, windows: chrome, titles: titles, tabs: tabs(everyWindow))
        #expect(action == .open(profileDirectory: nil, url: url, reason: .noMatchingTab))
    }

    @Test func aPlainBrowserAlwaysOpens() throws {
        let action = try Jump.decide(destination: anyProfile(.safari), running: true, windows: chrome, titles: titles, tabs: tabs([:]))
        #expect(action == .open(profileDirectory: nil, url: url, reason: .plain))
    }

    @Test func withOneProfileTitlesNeedNoLabel() throws {
        let one = [ChromeWindow(id: "5", name: "Claude")]
        let action = try Jump.decide(destination: destination(label: nil), running: true, windows: one, titles: ["Claude - Brave"], tabs: tabs([
            "5": WindowTabs(windowID: "5", urls: ["https://claude.ai/chat/2"], activeIndex: 1),
        ]))
        #expect(action == .focus(windowID: "5", tabIndex: 1, titleIndex: 0))
    }

    @Test func noProfileFindsATabAccessibilityCantSee() throws {
        // Window 9 is on another desktop: scripting lists it, Accessibility doesn't, so it
        // has no title to pair with; it is focused through scripting alone.
        let windows = chrome + [ChromeWindow(id: "9", name: "Claude")]
        let action = try Jump.decide(destination: anyProfile(), running: true, windows: windows, titles: titles, tabs: tabs(everyWindow.merging([
            "2": WindowTabs(windowID: "2", urls: ["https://docs.x"], activeIndex: 1),
            "9": WindowTabs(windowID: "9", urls: ["https://claude.ai/chat/9"], activeIndex: 1),
        ]) { $1 }))
        #expect(action == .focus(windowID: "9", tabIndex: 1, titleIndex: nil))
    }

    @Test func aWebAppWindowIsNeverFocused() throws {
        // Brave lists a web app's window with no name, as measured; its tab is the site's.
        let windows = [ChromeWindow(id: "7", name: ""), ChromeWindow(id: "8", name: "Docs")]
        let action = try Jump.decide(destination: anyProfile(), running: true, windows: windows, titles: [title("Docs", kim)], tabs: tabs([
            "7": WindowTabs(windowID: "7", urls: ["https://claude.ai/chat/3"], activeIndex: 1),
            "8": WindowTabs(windowID: "8", urls: ["https://docs.x"], activeIndex: 1),
        ]))
        #expect(action == .open(profileDirectory: nil, url: url, reason: .noMatchingTab))
    }
}
