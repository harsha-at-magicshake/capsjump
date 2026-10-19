// What `capsjump check` reports for a missing file, a bad config, good sites (the browser
// each lands in, and why one can't), and each key.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct CheckupTests {
    private static let disk: Set<String> = ["/Applications/iTerm.app", "/Users/kim/Applications/Notes Plus.app"]
    private static let lookup = Lookup(
        home: "/Users/kim",
        exists: { disk.contains($0) },
        linkHandler: { ["https": "Safari", "slack": "Slack"][$0.scheme ?? ""] }
    )

    /// Chrome's profile list is `state`; every other browser's is missing.
    private func run(_ config: String?, _ state: String? = localState, default browser: Browser = .chrome, reads: [Browser: CatalogRead] = [:]) -> [Finding] {
        Checkup.run(configText: config, configPath: "~/.capsjump.yaml", defaultBrowser: browser, catalog: { Self.read($0, chrome: state, reads) }, lookup: Self.lookup)
    }

    private static func read(_ browser: Browser, chrome state: String?, _ reads: [Browser: CatalogRead]) -> CatalogRead {
        if let given = reads[browser] { return given }
        guard browser == .chrome, let state else { return .missing(path: "\(browser.displayName)/Local State") }
        do {
            return .read(try ProfileCatalog.parse(localState: Data(state.utf8)))
        } catch {
            return .unreadable(error.description)
        }
    }

    private static let oneSite = "sites:\n  - name: github\n    account: alex@globex.io\n    open: https://github.com\n"

    @Test func missingFilesAreProblems() {
        #expect(run(nil).map(\.level) == [.problem])
        #expect(run(nil).first?.text.contains("capsjump init") == true)
        #expect(run(Self.oneSite, nil)[1] == Finding(.problem, "github: Google Chrome's profile list is missing at Google Chrome/Local State; has Google Chrome been opened on this Mac?"))
        #expect(run(Self.oneSite, "{}")[1].level == .problem)
        #expect(run("sites: []").map(\.level) == [.note])
    }

    @Test func keysNeedNoChrome() {
        #expect(run("keys:\n  f: { window: maximize }\n", nil) == [
            Finding(.ok, "`f` → window maximize"),
        ])
    }

    @Test func noKeysLeavesCapsLockAlone() {
        #expect(run(Self.oneSite).last == Finding(.ok, "no keys, so Caps Lock is left alone"))
    }

    @Test func eachKeySaysWhatItDoes() {
        let findings = run(Self.oneSite + """
        keys:
          s: { app: iTerm }
          n: { app: Notes Plus }
          z: { app: Zed }
          o: { app: ~/Apps/Obsidian.app }
          g: { site: github }
          left: { window: left-half }
          w: { url: "slack://channel?id=C1" }
          e: { url: https://example.com }
          m: { url: "zoommtg://join" }
        """)
        #expect(Array(findings.dropFirst(2)) == [
            Finding(.ok, "`s` → app /Applications/iTerm.app"),
            Finding(.ok, "`n` → app /Users/kim/Applications/Notes Plus.app"),
            Finding(.problem, "`z` → app Zed: no Zed.app in /Applications, /Applications/Utilities, /System/Applications, /System/Applications/Utilities, ~/Applications, /System/Library/CoreServices; give its path instead"),
            Finding(.problem, "`o` → app ~/Apps/Obsidian.app: nothing at /Users/kim/Apps/Obsidian.app"),
            Finding(.ok, "`g` → site github"),
            Finding(.ok, "`left` → window left-half"),
            Finding(.ok, "`w` → url slack://channel?id=C1 (opens in Slack)"),
            Finding(.ok, "`e` → url https://example.com (opens in Safari)"),
            Finding(.note, "`m` → url zoommtg://join: no installed app opens zoommtg links"),
        ])
    }

    @Test func configProblemsAreListedWithThePath() {
        let findings = run("sites:\n  - name: X\n")
        #expect(findings.allSatisfy { $0.level == .problem && $0.text.hasPrefix("~/.capsjump.yaml: ") })
        #expect(findings.count == 2)
    }

    @Test func eachSiteResolvesOrSaysWhy() {
        let findings = run("""
        sites:
          - name: github
            account: alex@globex.io
            open: https://github.com
          - name: shared
            account: globex.io
            open: https://x.com
        """)
        #expect(findings == [
            Finding(.ok, "default browser: Google Chrome"),
            Finding(.ok, "github → Google Chrome (default), Profile 15, windows labelled “Alex (globex.io)”"),
            Finding(.problem, "shared: Google Chrome: `globex.io` matches the profiles `Profile 15` and `Profile 17`; name one with `profile:`"),
            Finding(.ok, "no keys, so Caps Lock is left alone"),
        ])
    }

    @Test func sharedLabelIsANote() {
        let state = #"{"profile": {"info_cache": {"A": {"name": "Work"}, "B": {"name": "Work"}}}}"#
        let findings = run("sites:\n  - name: a\n    profile: A\n    open: https://x.com\n", state)
        #expect(findings.map(\.level) == [.ok, .note, .ok])
        #expect(findings[1].text.contains("always opens a new tab, because B carries the same label") == true)
    }

    @Test func eachSiteSaysItsBrowser() {
        let brave = #"{"profile": {"info_cache": {"Default": {"name": "Work"}, "Profile 1": {"name": "Home"}}}}"#
        let findings = run("""
        sites:
          - name: any
            open: https://a.com
          - name: work
            account: Work
            open: https://b.com
          - name: kim
            account: kim@initech.com
            open: https://c.com
          - name: plain
            browser: safari
            open: https://d.com
        keys:
          f: { window: maximize }
        """, default: .brave, reads: [.brave: .read(try! ProfileCatalog.parse(localState: Data(brave.utf8)))])
        #expect(findings == [
            Finding(.ok, "default browser: Brave"),
            Finding(.ok, "any → Brave (default), its own choice of profile, any window"),
            Finding(.ok, "work → Brave (default), Default, windows labelled “Work”"),
            Finding(.ok, "kim → Google Chrome (fell back to Chrome), Profile 26, windows labelled “kim@initech.com”"),
            Finding(.ok, "plain → Safari, opens the page; no tab search"),
            Finding(.ok, "`f` → window maximize"),
        ])
    }

    @Test func aPlainDefaultSaysSo() {
        let findings = run("sites:\n  - name: a\n    open: https://a.com\n", default: .safari)
        #expect(findings[0] == Finding(.ok, "default browser: Safari (opens pages only; no tab search)"))
        #expect(findings[1] == Finding(.ok, "a → Safari (default), opens the page; no tab search"))
    }

    @Test func withOneProfileAnyWindowWillDo() {
        let one = #"{"profile": {"info_cache": {"Default": {"name": "Person 1"}}}}"#
        let findings = run("sites:\n  - name: a\n    account: Person 1\n    open: https://a.com\n", one)
        #expect(findings[1] == Finding(.ok, "a → Google Chrome (default), Default, any window"))
    }

    @Test func eachBrowsersListIsReadOnce() {
        nonisolated(unsafe) var asked: [Browser] = []
        _ = Checkup.run(configText: Self.twoSites, configPath: "c", defaultBrowser: .brave, catalog: { asked.append($0); return .missing(path: "x") }, lookup: Self.lookup)
        #expect(asked == [.brave, .chrome])
    }

    private static let twoSites = "sites:\n  - name: a\n    account: x\n    open: https://a.com\n  - name: b\n    account: y\n    open: https://b.com\n"
}
