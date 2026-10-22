// Which browser a site opens in: the one where its account names a profile. A name only
// Brave has lands in Brave. Chrome takes everything else: a name both have, an email
// (Brave's profiles carry none), and a site naming only a folder, since Brave reuses
// Chrome's folder names. `profile:` then picks the folder inside the browser the account
// chose. So a config needs no browser line, and whoever uses both browsers gives their
// profiles different names. A browser that isn't installed, or has never been opened (no
// profile list yet), is passed over; a list macOS refuses (#58) or one that can't be read
// stops the site, so a site never moves browser because a list couldn't be read. The live
// side reads every list once into `ProfileLists`, so the rules here never touch the disk.

import Foundation

/// A browser's profile list as read from disk, or why it couldn't be.
public enum CatalogRead: Sendable, Equatable {
    case read(ProfileCatalog)
    /// The browser hasn't been opened on this Mac yet.
    case missing(path: String)
    /// macOS refused to let CapsJump read it.
    case refused(path: String)
    case unreadable(String)
    /// The browser's folder may outlive it; its app is gone.
    case notInstalled

    public var catalog: ProfileCatalog? {
        if case let .read(catalog) = self { catalog } else { nil }
    }

    /// Why the list can't be used, worded for the person; nil when it was read.
    public func problem(for browser: Browser) -> String? {
        switch self {
        case .read:
            nil
        case let .missing(path):
            "\(browser)'s profile list is missing at \(path); has \(browser) been opened on this Mac?"
        case let .refused(path):
            "macOS won't let CapsJump read \(browser)'s profile list at \(path)"
        case let .unreadable(reason):
            reason
        case .notInstalled:
            "\(browser) is not installed"
        }
    }
}

/// Every browser's profile list, read once for a jump, a check or a window.
public struct ProfileLists: Sendable, Equatable {
    private let reads: [Browser: CatalogRead]

    public init(_ read: (Browser) -> CatalogRead) {
        reads = Dictionary(uniqueKeysWithValues: Browser.known.map { ($0, read($0)) })
    }

    public subscript(browser: Browser) -> CatalogRead {
        reads[browser] ?? .notInstalled
    }

    /// The lists that could be read, in `Browser.known` order.
    public var catalogs: [ProfileCatalog] {
        Browser.known.compactMap { self[$0].catalog }
    }

    public func profile(_ id: ProfileID) -> (profile: ChromeProfile, catalog: ProfileCatalog)? {
        guard let catalog = self[id.browser].catalog, let profile = catalog.profile(directory: id.directory) else { return nil }
        return (profile, catalog)
    }
}

/// One profile among every browser's: Brave reuses Chrome's folder names, so a folder alone
/// doesn't say whose it is.
public struct ProfileID: Sendable, Hashable {
    public let browser: Browser
    public let directory: String

    public init(_ browser: Browser, _ directory: String) {
        self.browser = browser
        self.directory = directory
    }
}

public enum PlaceError: Error, Equatable, CustomStringConvertible {
    /// The lists that stop the site, each worded for the person.
    case lists([String])
    /// No browser has the account; one per list looked in, when more than one was.
    case notFound(account: String, in: [ProfileCatalog])
    case resolve(ResolveError)

    public var description: String {
        switch self {
        case let .lists(problems):
            problems.joined(separator: "; ")
        case let .notFound(account, catalogs):
            "no \(catalogs.map(\.browser.name).joined(separator: " or ")) profile has the account `\(account)`; "
                + catalogs.map { "\($0.browser) has: \($0.accounts.joined(separator: ", "))" }.joined(separator: "; ")
        case let .resolve(error):
            error.description
        }
    }
}

public enum Placement {
    /// The profile a site lands in, in the browser its account picks.
    public static func resolve(_ site: Site, in lists: ProfileLists) throws(PlaceError) -> Target {
        let catalog = try catalog(account: site.account, in: lists)
        do {
            return try Resolver.resolve(site, in: catalog)
        } catch {
            throw .resolve(error)
        }
    }

    /// The list of the browser an account picks: the first, in `Browser.known` order, with
    /// a profile of that email or name, even two of them, which `profile:` then tells apart.
    public static func catalog(account: String?, in lists: ProfileLists) throws(PlaceError) -> ProfileCatalog {
        var lacking: [ProfileCatalog] = []
        var passed: [Browser] = []
        for browser in browsers(for: account) {
            switch lists[browser] {
            case let .read(catalog):
                guard let account, !catalog.has(account: account) else { return catalog }
                lacking.append(catalog)
            case .missing, .notInstalled:
                passed.append(browser)
            case .refused, .unreadable:
                throw .lists([lists[browser].problem(for: browser) ?? ""])
            }
        }
        if let account, let only = lacking.first {
            guard lacking.count == 1 else { throw .notFound(account: account, in: lacking) }
            throw .resolve(.account(.notFound(account: account, known: only.accounts, browser: only.browser.name)))
        }
        // No list to look in. A browser that isn't installed goes unmentioned while another
        // says why its list is missing.
        let told = passed.filter { lists[$0] != .notInstalled }
        throw .lists((told.isEmpty ? Array(passed.prefix(1)) : told).compactMap { lists[$0].problem(for: $0) })
    }

    /// The other browsers with a profile of the site's account name: a name both have opens
    /// in Chrome, and the person is told so.
    public static func sameName(as target: Target, in lists: ProfileLists) -> [Browser] {
        guard let account = target.site.account, !isEmail(account) else { return [] }
        return lists.catalogs.filter { $0.browser != target.browser && $0.has(account: account) }.map(\.browser)
    }

    /// The browser a site written for `profile` (`SiteAccount.fields`) would open in instead,
    /// because Chrome has the same name; nil when it lands in the profile's own browser.
    public static func openingElsewhere(_ profile: ChromeProfile, in catalog: ProfileCatalog, lists: ProfileLists) -> Browser? {
        let account = SiteAccount.fields(for: profile, in: catalog).account
        guard let landed = try? self.catalog(account: account, in: lists), landed.browser != catalog.browser else { return nil }
        return landed.browser
    }

    private static func browsers(for account: String?) -> [Browser] {
        guard let account, !isEmail(account) else { return [.chrome] }
        return Browser.known
    }

    private static func isEmail(_ account: String) -> Bool {
        account.contains("@")
    }
}
