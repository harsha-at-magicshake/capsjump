// Which browser a site opens in, and in which of its profiles. A site that names its
// browser uses only that one. Otherwise a site with no account or folder goes to the
// Mac's default browser and whatever profile it picks. A site with an account goes to
// the default browser when that browser has the account, else to Chrome, so a config
// written when CapsJump knew only Chrome keeps working whatever the default is. A site
// that names only a folder tries Chrome first: every Chromium browser has `Default` and
// `Profile 1`, so a folder doesn't say which browser was meant, and such sites were
// Chrome's before. Every browser's profile list is read through `catalog`, so the rules
// here never touch the disk.

import Foundation

/// A browser's profile list as read from disk, or why it couldn't be.
public enum CatalogRead: Sendable, Equatable {
    case read(ProfileCatalog)
    case missing(path: String)
    /// macOS refused to let CapsJump read it.
    case refused(path: String)
    case unreadable(String)

    /// Why the list can't be used, worded for the person; nil when it was read.
    public func problem(for browser: Browser) -> String? {
        switch self {
        case .read:
            nil
        case let .missing(path):
            "\(browser)'s profile list is missing at \(path); has \(browser) been opened on this Mac?"
        case let .refused(path):
            "macOS won't let CapsJump read \(browser)'s profile list at \(path); turn CapsJump on under System Settings › Privacy & Security › Full Disk Access"
        case let .unreadable(reason):
            reason
        }
    }
}

/// Where one site lands.
public struct Destination: Sendable, Equatable {
    public let site: Site
    public let browser: Browser
    /// The profile, for a site that names an account or folder; nil to use the browser's
    /// own choice of profile and any of its windows.
    public let target: Target?
    /// Whether the browser is not the default one a site without `browser:` starts from.
    public let fellBack: Bool
    /// Whether the browser is the Mac's default, reached without falling back.
    public let isDefault: Bool
    /// The label the profile's window titles end with; nil when any window will do: no
    /// profile, or a browser with only one, whose titles carry no label.
    public let windowLabel: String?

    public init(site: Site, browser: Browser, target: Target?, fellBack: Bool, isDefault: Bool, windowLabel: String?) {
        self.site = site
        self.browser = browser
        self.target = target
        self.fellBack = fellBack
        self.isDefault = isDefault
        self.windowLabel = windowLabel
    }
}

/// Every browser a site was tried in, and why it couldn't land there.
public struct PlaceError: Error, Equatable, CustomStringConvertible {
    public struct Attempt: Error, Sendable, Equatable {
        public let browser: Browser
        /// Names the browser itself.
        public let reason: String
    }

    public let attempts: [Attempt]

    public var description: String {
        attempts.map(\.reason).joined(separator: "; ")
    }
}

public enum Placement {
    public static func place(_ site: Site, defaultBrowser: Browser, catalog: (Browser) -> CatalogRead) throws(PlaceError) -> Destination {
        let order = tries(named: site.browser, account: site.account, profile: site.profile, defaultBrowser: defaultBrowser)
        let fellBack = { (browser: Browser) in site.browser == nil && browser != defaultBrowser }
        guard site.account != nil || site.profile != nil else {
            let browser = order[0]
            return Destination(site: site, browser: browser, target: nil, fellBack: false, isDefault: site.browser == nil, windowLabel: nil)
        }
        var attempts: [PlaceError.Attempt] = []
        for browser in order {
            switch landing(account: site.account, profile: site.profile, in: browser, catalog: catalog) {
            case let .success((profile, catalog)):
                let target = Target(site: site, profile: profile, sharedLabelWith: catalog.sharingLabel(with: profile))
                return Destination(
                    site: site, browser: browser, target: target,
                    fellBack: fellBack(browser), isDefault: site.browser == nil && !fellBack(browser),
                    windowLabel: catalog.profiles.count == 1 ? nil : target.label
                )
            case let .failure(attempt):
                attempts.append(attempt)
            }
        }
        throw PlaceError(attempts: attempts)
    }

    /// The browsers with full support a jump may script: the default, each one a site
    /// names, and Chrome when a site with an account or folder may fall back to it. The
    /// default first, then in the table's order.
    public static func browsersUsed(by config: Config, defaultBrowser: Browser) -> [Browser] {
        var used = Set(config.sites.compactMap(\.browser))
        if config.sites.contains(where: { $0.browser == nil && ($0.account != nil || $0.profile != nil) }) {
            used.insert(.chrome)
        }
        let rest = Browser.known.filter { used.contains($0) && $0 != defaultBrowser }
        return ([defaultBrowser] + rest).filter { $0.support == .full }
    }

    /// The browser `place` would choose for a row as written, which may not be valid yet;
    /// the first one tried when none would take it.
    public static func browser(for site: SiteSource, defaultBrowser: Browser, catalog: (Browser) -> CatalogRead) -> (browser: Browser, fellBack: Bool) {
        let named = site.browser.flatMap(Browser.named)
        let account = given(site.account), profile = given(site.profile)
        let order = tries(named: named, account: account, profile: profile, defaultBrowser: defaultBrowser)
        let found = account == nil && profile == nil ? nil : order.first { browser in
            if case .success = landing(account: account, profile: profile, in: browser, catalog: catalog) { return true }
            return false
        }
        let browser = found ?? (named ?? defaultBrowser)
        return (browser, named == nil && browser != defaultBrowser)
    }

    /// The browsers to try, in order.
    private static func tries(named: Browser?, account: String?, profile: String?, defaultBrowser: Browser) -> [Browser] {
        if let named { return [named] }
        guard account != nil || profile != nil else { return [defaultBrowser] }
        let usable = defaultBrowser.support == .full ? [defaultBrowser] : []
        let order = account == nil ? [.chrome] + usable : usable + [.chrome]
        return order.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    private static func landing(account: String?, profile: String?, in browser: Browser, catalog: (Browser) -> CatalogRead) -> Result<(ChromeProfile, ProfileCatalog), PlaceError.Attempt> {
        guard browser.support == .full else {
            return .failure(.init(browser: browser, reason: "\(browser) has no profiles CapsJump can read"))
        }
        let read = catalog(browser)
        guard case let .read(profiles) = read else {
            return .failure(.init(browser: browser, reason: read.problem(for: browser) ?? ""))
        }
        do {
            return .success((try Resolver.profile(account: account, directory: profile, in: profiles), profiles))
        } catch {
            return .failure(.init(browser: browser, reason: "\(browser): \(error)"))
        }
    }

    private static func given(_ text: String?) -> String? {
        text.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }
}
