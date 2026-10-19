// Reading a browser's profile list from a home folder built here: missing, refused by the
// file's permissions (as macOS refuses a browser's folder), not a profile list, good, and
// a browser that keeps none CapsJump can read.

import CapsJumpCore
import Foundation
import Testing
@testable import CapsJumpChrome

@Suite struct InputsTests {
    /// Every browser counts as installed, whatever this Mac has.
    private static func everyBrowser(_: Browser) -> Bool { true }

    private static func home() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("inputs-\(UUID().uuidString)")
    }

    private static func write(_ text: String, for browser: Browser, home: URL) throws -> URL {
        let file = try #require(browser.localState(home: home))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }

    @Test func aMissingListSaysWhere() {
        let home = Self.home()
        #expect(Inputs.catalog(for: .brave, home: home, installed: Self.everyBrowser) == .missing(path: home.path + "/Library/Application Support/BraveSoftware/Brave-Browser/Local State"))
    }

    @Test func aGoodListIsRead() throws {
        let home = Self.home()
        _ = try Self.write(#"{"profile": {"info_cache": {"Default": {"name": "Work"}}}}"#, for: .brave, home: home)
        guard case let .read(catalog) = Inputs.catalog(for: .brave, home: home, installed: Self.everyBrowser) else {
            Issue.record("not read")
            return
        }
        #expect(catalog.profiles.map(\.name) == ["Work"])
    }

    @Test func aListThatIsNoProfileListIsUnreadable() throws {
        let home = Self.home()
        let file = try Self.write("{}", for: .brave, home: home)
        #expect(Inputs.catalog(for: .brave, home: home, installed: Self.everyBrowser) == .unreadable("Brave's profile list at \(file.path) can't be used: it lists no profiles"))
    }

    @Test func aRefusedListSaysSo() throws {
        let home = Self.home()
        let file = try Self.write("{}", for: .chrome, home: home)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        #expect(Inputs.catalog(for: .chrome, home: home, installed: Self.everyBrowser) == .refused(path: file.path))
    }

    @Test func aBrowserThatIsntInstalledHasNoList() throws {
        let home = Self.home()
        _ = try Self.write(#"{"profile": {"info_cache": {"Default": {"name": "Work"}}}}"#, for: .chrome, home: home)
        #expect(Inputs.catalog(for: .chrome, home: home, installed: { _ in false }) == .notInstalled)
    }

    @Test func aPlainBrowserHasNoList() {
        #expect(Inputs.catalog(for: .safari, home: Self.home()) == .unreadable("Safari has no profiles CapsJump can read"))
    }
}
