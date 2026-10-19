// Which browser and profile a site lands in: the default browser for a site with no
// account; for one with an account, the default browser when it has that account, else
// Chrome; Chrome first for a site that names only a folder, since every Chromium browser
// has `Default`; a named browser only ever itself; and one error naming every browser
// tried and why each failed.

import Foundation
import Testing
@testable import CapsJumpCore

private func catalog(_ json: String) -> CatalogRead {
    .read(try! ProfileCatalog.parse(localState: Data(json.utf8)))
}

/// Brave with two profiles, the person's own shape: no Google sign-in, so names only.
private let brave = catalog("""
{"profile": {"profiles_order": ["Default", "Profile 1"], "info_cache": {
  "Default": {"name": "Work"}, "Profile 1": {"name": "Home"}}}}
""")

/// Chrome with two signed-in accounts and a profile named Work.
private let chrome = catalog("""
{"profile": {"profiles_order": ["Default", "Profile 3"], "info_cache": {
  "Default": {"name": "Work", "user_name": "alex@acme.dev", "gaia_given_name": "Alex"},
  "Profile 3": {"name": "Client", "user_name": "kim@initech.com", "gaia_given_name": "Kim"}}}}
""")

private func lists(_ reads: [Browser: CatalogRead]) -> (Browser) -> CatalogRead {
    { reads[$0] ?? .missing(path: "/\($0.displayName)/Local State") }
}

private func place(_ site: Site, default browser: Browser, _ reads: [Browser: CatalogRead]) throws(PlaceError) -> Destination {
    try Placement.place(site, defaultBrowser: browser, catalog: lists(reads))
}

@Suite struct PlacementTests {
    @Test func noAccountGoesToTheDefaultWithNoProfile() throws {
        let landed = try place(site(), default: .brave, [.brave: brave, .chrome: chrome])
        #expect(landed.browser == .brave)
        #expect(landed.target == nil)
        #expect(landed.windowLabel == nil)
        #expect(!landed.fellBack)
        #expect(landed.isDefault)
    }

    @Test func anAccountTheDefaultHasStaysThere() throws {
        let landed = try place(site(account: "Work"), default: .brave, [.brave: brave, .chrome: chrome])
        #expect(landed.browser == .brave)
        #expect(landed.target?.profile.directory == "Default")
        #expect(landed.windowLabel == "Work")
        #expect(!landed.fellBack)
    }

    @Test func anAccountOnlyChromeHasFallsBackToChrome() throws {
        let landed = try place(site(account: "alex@acme.dev"), default: .safari, [.chrome: chrome])
        #expect(landed.browser == .chrome)
        #expect(landed.target?.profile.directory == "Default")
        #expect(landed.fellBack)
        #expect(!landed.isDefault)
    }

    @Test func aRefusedDefaultFallsBackToChrome() throws {
        let landed = try place(site(account: "kim@initech.com"), default: .brave, [.brave: .refused(path: "/b/Local State"), .chrome: chrome])
        #expect(landed.browser == .chrome)
        #expect(landed.fellBack)
    }

    @Test func whenNeitherHasItBothAreNamed() {
        let error = #expect(throws: PlaceError.self) {
            try place(site(account: "Work"), default: .brave, [.brave: .refused(path: "/b/Local State")])
        }
        #expect(error?.attempts.map(\.browser) == [.brave, .chrome])
        #expect(error?.description == "macOS won't let CapsJump read Brave's profile list at /b/Local State; turn CapsJump on under System Settings › Privacy & Security › Full Disk Access; Google Chrome's profile list is missing at /Google Chrome/Local State; has Google Chrome been opened on this Mac?")
    }

    @Test func aFolderAloneTriesChromeFirst() throws {
        let landed = try place(site(profile: "Default"), default: .brave, [.brave: brave, .chrome: chrome])
        #expect(landed.browser == .chrome)
        let noChrome = try place(site(profile: "Default"), default: .brave, [.brave: brave])
        #expect(noChrome.browser == .brave)
        #expect(!noChrome.fellBack)
    }

    @Test func aFolderAloneSkipsAChromeThatIsntInstalled() throws {
        // Chrome's folder outlives Chrome: its list may still be on disk with the app gone.
        let landed = try place(site(profile: "Default"), default: .brave, [.brave: brave, .chrome: .notInstalled])
        #expect(landed.browser == .brave)
    }

    @Test func aChromeThatIsntInstalledSaysSo() {
        let error = #expect(throws: PlaceError.self) {
            try place(site(account: "kim@initech.com"), default: .brave, [.brave: brave, .chrome: .notInstalled])
        }
        #expect(error?.attempts.map(\.reason) == [
            "Brave: no profile has the account `kim@initech.com`; this Mac has: Work, Home",
            "Google Chrome is not installed",
        ])
    }

    @Test func aNamedBrowserNeverFallsBack() {
        let error = #expect(throws: PlaceError.self) {
            try place(site(account: "alex@acme.dev", browser: .brave), default: .brave, [.brave: brave, .chrome: chrome])
        }
        #expect(error?.attempts.map(\.browser) == [.brave])
        #expect(error?.description == "Brave: no profile has the account `alex@acme.dev`; this Mac has: Work, Home")
    }

    @Test func aNamedBrowserIsNotTheDefault() throws {
        let landed = try place(site(browser: .safari), default: .brave, [:])
        #expect(landed.browser == .safari)
        #expect(landed.target == nil)
        #expect(!landed.isDefault)
        #expect(!landed.fellBack)
    }

    @Test func withOneProfileAnyWindowIsItsWindow() throws {
        let one = catalog(#"{"profile": {"info_cache": {"Default": {"name": "Person 1"}}}}"#)
        let landed = try place(site(account: "Person 1"), default: .brave, [.brave: one])
        #expect(landed.target?.profile.directory == "Default")
        #expect(landed.windowLabel == nil)
    }

    @Test func chromeAsTheDefaultIsTriedOnce() {
        let error = #expect(throws: PlaceError.self) {
            try place(site(account: "nobody@x.com"), default: .chrome, [.chrome: chrome])
        }
        #expect(error?.attempts.map(\.browser) == [.chrome])
    }

    @Test func theEditorAsksWhichBrowserARowUses() {
        let reads = lists([.brave: brave, .chrome: chrome])
        #expect(Placement.browser(for: SiteSource(index: 0, name: "a", account: "kim@initech.com", open: nil), defaultBrowser: .brave, catalog: reads) == (.chrome, true))
        #expect(Placement.browser(for: SiteSource(index: 0, name: "a", account: "Home", open: nil), defaultBrowser: .brave, catalog: reads) == (.brave, false))
        #expect(Placement.browser(for: SiteSource(index: 0, name: "a", account: "nobody", open: nil), defaultBrowser: .brave, catalog: reads) == (.brave, false))
        #expect(Placement.browser(for: SiteSource(index: 0, name: "a", open: nil, browser: "Safari"), defaultBrowser: .brave, catalog: reads) == (.safari, false))
    }
}
