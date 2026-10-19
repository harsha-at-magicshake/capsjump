// Add Current Tab's rules: which profile a window title belongs to, which tabs can become
// a site, the name suggested for one, and the site that already lands on a page.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct TabCaptureTests {
    @Test func aTitleNamesItsProfile() throws {
        let c = try catalog()
        func directory(_ title: String) -> String? { c.profile(forTitle: title)?.directory }
        #expect(directory("Pull requests - Google Chrome – Alex (acme.dev)") == "Profile 1")
        #expect(directory("Inbox - Google Chrome – Alex (globex.io)") == "Profile 15")
        #expect(directory("Inbox - Google Chrome – Sam (globex.io)") == "Profile 17")
        // Signed out: the label is the profile's name.
        #expect(directory("New Tab - Google Chrome – kim@initech.com") == "Profile 26")
        #expect(directory("New Tab - Google Chrome") == nil)
        #expect(directory("New Tab - Google Chrome – Someone Else") == nil)
    }

    @Test func aSharedLabelNamesNoProfile() {
        let c = ProfileCatalog(profiles: [
            ChromeProfile(directory: "A", name: "Work", email: "", givenName: ""),
            ChromeProfile(directory: "B", name: "Work", email: "", givenName: ""),
            ChromeProfile(directory: "C", name: "Home", email: "", givenName: ""),
        ])
        #expect(c.profile(forTitle: "x - Google Chrome – Work") == nil)
        #expect(c.profile(forTitle: "x - Google Chrome – Home")?.directory == "C")
    }

    @Test func theLongestLabelWinsWhenOneEndsAnother() {
        let c = ProfileCatalog(profiles: [
            ChromeProfile(directory: "A", name: "B", email: "", givenName: ""),
            ChromeProfile(directory: "C", name: "A – B", email: "", givenName: ""),
        ])
        #expect(c.profile(forTitle: "x - Google Chrome – A – B")?.directory == "C")
        #expect(c.profile(forTitle: "x - Google Chrome – B")?.directory == "A")
    }

    @Test func oneProfileNeedsNoTitle() throws {
        let c = ProfileCatalog(profiles: [ChromeProfile(directory: "Default", name: "Person 1", email: "", givenName: "")])
        #expect(c.profile(forTitle: "x - Google Chrome")?.directory == "Default")
        #expect(c.profile(forTitle: "")?.directory == "Default")
        #expect(c.profile(forTitle: nil)?.directory == "Default")
        #expect(try catalog().profile(forTitle: nil) == nil)
    }

    @Test func keysShowAsTheirKeycaps() {
        #expect(["g", "5", "f1", "f12", "left", "right", "up", "down"].map(KeyNames.symbol(for:)) == ["G", "5", "F1", "F12", "←", "→", "↑", "↓"])
    }

    @Test func theKeyOfferedFirstIsAFreeLetterOfTheName() {
        let letters = KeyNames.all
        #expect(TabCapture.suggestedKey(for: "github", free: letters) == "g")
        #expect(TabCapture.suggestedKey(for: "github", free: letters.filter { $0 != "g" }) == "i")
        #expect(TabCapture.suggestedKey(for: "mail-google", free: ["l", "e", "5"]) == "l")
        #expect(TabCapture.suggestedKey(for: "127", free: letters) == nil)
        #expect(TabCapture.suggestedKey(for: "abc", free: []) == nil)
    }

    @Test(arguments: [
        ("https://github.com/stigmer/capsjump/pulls", true),
        ("http://localhost:8080/", true),
        ("chrome://settings/", false),
        ("chrome-extension://abc/page.html", false),
        ("file:///Users/kim/a.html", false),
        ("about:blank", false),
        ("", false),
    ])
    func onlyWebPagesBecomeSites(url: String, page: Bool) {
        #expect((TabCapture.page(url) != nil) == page)
    }

    @Test(arguments: [
        ("https://github.com/a/b", [], "github"),
        ("https://www.github.com/", [], "github"),
        ("https://github.com/", ["github"], "github-2"),
        ("https://github.com/", ["github", "github-2"], "github-3"),
        ("https://mail.google.com/mail/u/0/", [], "mail"),
        ("https://mail.google.com/mail/u/0/", ["mail"], "mail-google"),
        ("https://mail.google.com/mail/u/0/", ["mail", "mail-google"], "mail-2"),
        ("https://app.slack.com/client/T1", [], "slack"),
        ("https://news.bbc.co.uk/", [], "news"),
        ("https://my_site.example.org/", [], "my-site"),
        ("http://localhost:3000/", [], "localhost"),
        ("http://127.0.0.1:8000/", [], "127"),
        ("https://www.com/", [], "www"),
        ("https://_x.dev/", [], "x"),
    ] as [(String, [String], String)])
    func namesAreSuggestedFromTheHost(url: String, taken: [String], name: String) throws {
        let suggested = TabCapture.suggestedName(for: try #require(URL(string: url)), taken: Set(taken))
        #expect(suggested == name)
        #expect(SiteName.problem(with: suggested) == nil)
    }

    @Test func thePageMayAlreadyBeASite() throws {
        let c = try catalog()
        let config = try ConfigParser.parse("""
        sites:
          - name: github
            account: alex@acme.dev
            profile: Profile 1
            open: https://github.com/
          - name: prs
            account: alex@acme.dev
            profile: Profile 1
            open: https://github.com/stigmer/capsjump/pulls
            match: [github.com/stigmer/capsjump/pulls]
          - name: github-globex
            account: alex@globex.io
            open: https://github.com/
          - name: broken
            account: nobody@x.com
            open: https://github.com/
        """)
        let acme = try #require(c.profile(directory: "Profile 1"))
        let globex = try #require(c.profile(directory: "Profile 15"))
        let sam = try #require(c.profile(directory: "Profile 17"))
        func existing(_ url: String, _ profile: ChromeProfile) -> String? {
            TabCapture.existingSite(for: url, browser: .chrome, profile: profile, in: config, defaultBrowser: .chrome, catalog: { $0 == .chrome ? .read(c) : .missing(path: "x") })?.name
        }
        #expect(existing("https://github.com/stigmer/capsjump/pulls/15", acme) == "prs")
        #expect(existing("https://www.github.com/settings", acme) == "github")
        #expect(existing("https://github.com/stigmer/capsjump/pulls", globex) == "github-globex")
        #expect(existing("https://github.com/", sam) == nil)
        #expect(existing("https://gitlab.com/", acme) == nil)
    }

    @Test func aSiteWithNoProfileIsTheTabOnlyWhenNoProfileIsKnown() throws {
        let c = try catalog()
        let config = try ConfigParser.parse("sites:\n  - name: docs\n    open: https://docs.x.com/\n")
        let acme = try #require(c.profile(directory: "Profile 1"))
        let reads = { (b: Browser) -> CatalogRead in .read(c) }
        // The tab is in a known profile of a browser with several: a site of its own in
        // that profile can be made, so the site with no account doesn't stand in for it.
        #expect(TabCapture.existingSite(for: "https://docs.x.com/a", browser: .brave, profile: acme, in: config, defaultBrowser: .brave, catalog: reads) == nil)
        #expect(TabCapture.existingSite(for: "https://docs.x.com/a", browser: .brave, profile: nil, in: config, defaultBrowser: .brave, catalog: reads)?.name == "docs")
        #expect(TabCapture.existingSite(for: "https://docs.x.com/a", browser: .chrome, profile: nil, in: config, defaultBrowser: .brave, catalog: reads) == nil)
        let one = try ProfileCatalog.parse(localState: Data(#"{"profile": {"info_cache": {"Default": {"name": "Work"}}}}"#.utf8))
        #expect(TabCapture.existingSite(for: "https://docs.x.com/a", browser: .brave, profile: one.profiles[0], in: config, defaultBrowser: .brave, catalog: { _ in .read(one) })?.name == "docs")
    }

    @Test func aTabInAnUnknownProfileNeedsAChoice() throws {
        let c = try catalog()
        #expect(TabCapture.needsProfileChoice(catalog: c, profile: nil))
        #expect(!TabCapture.needsProfileChoice(catalog: c, profile: c.profiles[0]))
        #expect(!TabCapture.needsProfileChoice(catalog: nil, profile: nil))
        let one = ProfileCatalog(profiles: [c.profiles[0]])
        #expect(!TabCapture.needsProfileChoice(catalog: one, profile: nil))
    }
}
