// Which browser a site lands in: a name only Brave has lands in Brave; a name both have,
// an email, and a folder alone land in Chrome; `profile:` picks inside the browser the
// name chose; a browser not installed or never opened is passed over, and a refused or
// broken list stops the site.

import Foundation
import Testing
@testable import CapsJumpCore

/// Chrome with a signed-in Work and a signed-out Home.
private let chrome = read("""
{"profile": {"profiles_order": ["Default", "Profile 3"], "info_cache": {
  "Default": {"name": "Work", "user_name": "alex@acme.dev", "gaia_given_name": "Alex"},
  "Profile 3": {"name": "Home"}}}}
""")

/// Brave, whose profiles have names only, reusing Chrome's folder names.
private let brave = read("""
{"profile": {"profiles_order": ["Default", "Profile 5", "Profile 6"], "info_cache": {
  "Default": {"name": "Work"}, "Profile 5": {"name": "Parents"}, "Profile 6": {"name": "Kids"}}}}
""", .brave)

private let both = lists([.chrome: chrome, .brave: brave])

private func place(_ site: Site, _ lists: ProfileLists = both) throws(PlaceError) -> Target {
    try Placement.resolve(site, in: lists)
}

@Suite struct PlacementTests {
    @Test func aNameOnlyBraveHasLandsInBrave() throws {
        let target = try place(site(account: "parents"))
        #expect(target.browser == .brave)
        #expect(target.profile.directory == "Profile 5")
        #expect(Placement.sameName(as: target, in: both).isEmpty)
    }

    @Test func aNameBothHaveLandsInChromeAndSaysSo() throws {
        let target = try place(site(account: "Work"))
        #expect(target.browser == .chrome)
        #expect(target.profile.directory == "Default")
        #expect(Placement.sameName(as: target, in: both) == [.brave])
    }

    @Test func anEmailIsChromesAlone() throws {
        let refusedBrave = lists([.chrome: chrome, .brave: .refused(path: "/b")])
        #expect(try place(site(account: "alex@acme.dev"), refusedBrave).browser == .chrome)
        let error = #expect(throws: PlaceError.self) { try place(site(account: "kim@initech.com")) }
        #expect(error?.description == "no Chrome profile has the account `kim@initech.com`; this Mac has: alex@acme.dev, Home")
    }

    @Test func aFolderAloneIsChromes() throws {
        #expect(try place(site(profile: "Profile 3")).browser == .chrome)
        let error = #expect(throws: PlaceError.self) { try place(site(profile: "Profile 5")) }
        #expect(error == .resolve(.unknownProfile(directory: "Profile 5", known: ["Default", "Profile 3"], browser: "Chrome")))
    }

    @Test func theFolderIsLookedForInTheBrowserTheNameChose() throws {
        let twoParents = read(#"{"profile": {"info_cache": {"Profile 5": {"name": "Parents"}, "Profile 7": {"name": "Parents"}}}}"#, .brave)
        let lists = lists([.chrome: chrome, .brave: twoParents])
        let target = try place(site(account: "Parents", profile: "Profile 7"), lists)
        #expect(target.browser == .brave)
        #expect(target.profile.directory == "Profile 7")
        let error = #expect(throws: PlaceError.self) { try place(site(account: "Parents"), lists) }
        #expect(error == .resolve(.account(.ambiguous(account: "Parents", directories: ["Profile 5", "Profile 7"]))))
    }

    @Test func twoChromeProfilesOfANameStopTheSite() {
        let twoWork = read(#"{"profile": {"info_cache": {"Default": {"name": "Work"}, "Profile 2": {"name": "Work"}}}}"#)
        let error = #expect(throws: PlaceError.self) { try place(site(account: "Work"), lists([.chrome: twoWork, .brave: brave])) }
        #expect(error == .resolve(.account(.ambiguous(account: "Work", directories: ["Default", "Profile 2"]))))
    }

    @Test func aRefusedOrBrokenListStopsTheSite() {
        for chrome in [CatalogRead.refused(path: "/c/Local State"), .unreadable("Chrome's Local State is not readable JSON")] {
            let error = #expect(throws: PlaceError.self) { try place(site(account: "Parents"), lists([.chrome: chrome, .brave: brave])) }
            #expect(error == .lists([chrome.problem(for: .chrome) ?? ""]))
        }
        let error = #expect(throws: PlaceError.self) {
            try place(site(account: "Parents"), lists([.chrome: chrome, .brave: .refused(path: "/b/Local State")]))
        }
        #expect(error?.description == "macOS won't let CapsJump read Brave's profile list at /b/Local State")
    }

    @Test func aBrowserNotInstalledOrNeverOpenedIsPassedOver() throws {
        for chrome in [CatalogRead.notInstalled, .missing(path: "/c/Local State")] {
            #expect(try place(site(account: "Work"), lists([.chrome: chrome, .brave: brave])).browser == .brave)
        }
    }

    @Test func noBrowserHasTheName() {
        let error = #expect(throws: PlaceError.self) { try place(site(account: "Nope")) }
        #expect(error?.description == "no Chrome or Brave profile has the account `Nope`; Chrome has: alex@acme.dev, Home; Brave has: Work, Parents, Kids")
    }

    @Test func noListToLookIn() {
        let missing = #expect(throws: PlaceError.self) {
            try place(site(account: "Work"), lists([.chrome: .missing(path: "/c/Local State")]))
        }
        #expect(missing?.description == "Chrome's profile list is missing at /c/Local State; has Chrome been opened on this Mac?")
        let none = #expect(throws: PlaceError.self) { try place(site(account: "Work"), lists([:])) }
        #expect(none?.description == "Chrome is not installed")
    }

    @Test func aBraveProfileChromeHasTheNameOfOpensInChrome() throws {
        let braveList = try #require(brave.catalog)
        let chromeList = try #require(chrome.catalog)
        #expect(Placement.openingElsewhere(try #require(braveList.profile(directory: "Default")), in: braveList, lists: both) == .chrome)
        #expect(Placement.openingElsewhere(try #require(braveList.profile(directory: "Profile 5")), in: braveList, lists: both) == nil)
        #expect(Placement.openingElsewhere(try #require(chromeList.profile(directory: "Default")), in: chromeList, lists: both) == nil)
    }
}
