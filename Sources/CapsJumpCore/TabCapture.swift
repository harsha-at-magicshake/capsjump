// Turning the tab in front of a browser into a site: whether it is a page a site can open,
// a name for it that no site has yet, and the site that already lands on it, if one does.
// The browser is read by the live side; every rule is here.

import Foundation

public enum TabCapture {
    /// Labels too general to name a site by: `app.slack.com` is `slack`, not `app`.
    static let generalLabels: Set<String> = ["www", "app", "apps", "web", "m", "my", "go", "portal", "console", "dashboard", "home", "login", "accounts", "account"]

    /// The tab's URL as a site's `open`, or nil for a page a site can't open (`chrome://`, a file).
    public static func page(_ raw: String) -> URL? {
        ConfigRules.httpURL(raw)
    }

    /// A name no site has: the host's first telling label (`github` for github.com, `mail`
    /// for mail.google.com), then more of the host (`mail-google`), then a number.
    public static func suggestedName(for url: URL, taken: Set<String>) -> String {
        let host = (url.host ?? "").lowercased()
        var labels = host.split(separator: ".").map(String.init)
        if labels.count > 1, labels.last?.allSatisfy(\.isNumber) == false {
            labels.removeLast()
        }
        let telling = labels.filter { !generalLabels.contains($0) }
        let parts = (telling.isEmpty ? labels : telling).map(nameSafe).filter { !$0.isEmpty }
        let candidates = parts.indices.map { parts[...$0].joined(separator: "-") }
        let base = candidates.first ?? "site"
        for name in candidates + [base] where !taken.contains(name) && SiteName.problem(with: name) == nil {
            return name
        }
        var number = 2
        while taken.contains("\(base)-\(number)") { number += 1 }
        return "\(base)-\(number)"
    }

    /// The key to offer first: the name's first letter, else its next letter, else none,
    /// each only while free.
    public static func suggestedKey(for name: String, free: [String]) -> String? {
        let free = Set(free)
        return name.map(String.init).first { $0.first?.isLetter == true && free.contains($0) }
    }

    /// The site a jump would land on this page with, in `browser` and `profile` (nil when
    /// the tab's profile is unknown): one placed in that profile, or one placed in that
    /// browser with no profile while the tab's profile can't be told apart (unknown, or the
    /// browser's only one), since a tab in a known profile can have a site of its own
    /// there; the one whose matching prefix is the most specific, the first in the file on
    /// a tie.
    public static func existingSite(for url: String, browser: Browser, profile: ChromeProfile?, in config: Config, defaultBrowser: Browser, catalog: (Browser) -> CatalogRead) -> Site? {
        var best: (site: Site, length: Int)?
        var several = false
        if case let .read(profiles) = catalog(browser) { several = profiles.profiles.count > 1 }
        let anyProfile = profile == nil || !several
        for site in config.sites {
            guard let destination = try? Placement.place(site, defaultBrowser: defaultBrowser, catalog: catalog),
                  destination.browser == browser,
                  destination.target.map({ $0.profile.directory == profile?.directory }) ?? anyProfile,
                  let prefix = site.match.first(where: { URLPrefix.matches(url, prefix: $0) })
            else { continue }
            if prefix.count > best?.length ?? -1 {
                best = (site, prefix.count)
            }
        }
        return best?.site
    }

    /// Whether the person must pick the tab's profile: the browser has several and the
    /// tab's window didn't say which, so no guess (none included) is made for them.
    public static func needsProfileChoice(catalog: ProfileCatalog?, profile: ChromeProfile?) -> Bool {
        profile == nil && (catalog?.profiles.count ?? 0) > 1
    }

    /// Lower-case letters and digits kept, every other run of characters one hyphen.
    private static func nameSafe(_ label: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        var name = ""
        for character in label {
            if allowed.contains(character) {
                name.append(character)
            } else if !name.isEmpty, name.last != "-" {
                name.append("-")
            }
        }
        while name.last == "-" { name.removeLast() }
        return name
    }
}
