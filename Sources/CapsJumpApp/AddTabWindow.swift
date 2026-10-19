// Add Current Tab: the tab in front of a browser becomes a site with a key, in one small
// window. The page and its account come from that browser, and the site names the browser
// only when it isn't the default one; the name comes from the page's host, and a
// free key is offered; every field is judged by the config's own rules through a
// ConfigDraft, so a problem shows under its field while it's typed. When the page is
// already a site in that account, the window offers that site a key instead. Saving goes
// through ConfigFile, so it applies at once, as saving the file does; a file in a layout of
// its own is rewritten only after a warning.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import CapsJumpSystem
import SwiftUI

@MainActor
final class AddTabModel: ObservableObject {
    enum Subject: Equatable {
        /// A new site, the row with this id.
        case newSite(id: Int)
        /// A site the file already has.
        case existing(name: String)
    }

    @Published private(set) var draft: ConfigDraft
    @Published private(set) var keyRow: Int?
    @Published var profileDirectory: String? {
        didSet { pickProfile() }
    }
    /// The tab's window didn't say which of several profiles it is in: nothing is saved
    /// until the person picks one, None included.
    @Published var mustChoose: Bool
    let subject: Subject
    let catalog: ProfileCatalog?
    /// The browser the tab was read from.
    let browser: Browser
    private let defaultBrowser: Browser
    private let reads: (Browser) -> CatalogRead

    init(draft: ConfigDraft, subject: Subject, catalog: ProfileCatalog?, profile: ChromeProfile?, browser: Browser, defaultBrowser: Browser, reads: @escaping (Browser) -> CatalogRead) {
        self.draft = draft
        self.subject = subject
        self.catalog = catalog
        self.browser = browser
        self.defaultBrowser = defaultBrowser
        self.reads = reads
        mustChoose = TabCapture.needsProfileChoice(catalog: catalog, profile: profile)
        profileDirectory = profile?.directory
        pickProfile()
        key = TabCapture.suggestedKey(for: siteName, free: draft.freeKeys())
    }

    var isExisting: Bool {
        if case .existing = subject { true } else { false }
    }

    var siteName: String {
        switch subject {
        case let .newSite(id): draft.site(id)?.site.name ?? ""
        case let .existing(name): name
        }
    }

    var name: String {
        get { siteName }
        set { if case let .newSite(id) = subject { draft.renameSite(id, to: newValue) } }
    }

    var page: String {
        get { newSite?.open ?? "" }
        set { updateSite { $0.open = newValue } }
    }

    /// Why the browser's profiles can't be listed, when they can't.
    var profilesProblem: String? {
        catalog == nil ? reads(browser).problem(for: browser) : nil
    }

    /// The account typed by hand, when the browser's profile list can't be read.
    var account: String {
        get { newSite?.account ?? "" }
        set { updateSite { $0.account = newValue } }
    }

    var key: String? {
        get { keyRow.flatMap { draft.key($0)?.key.key } }
        set {
            guard let newValue else {
                if let keyRow { draft.removeKey(keyRow) }
                keyRow = nil
                return
            }
            if case let .bound(row) = draft.bind(newValue, to: ActionSource(.site, siteName), row: keyRow) {
                keyRow = row
            }
        }
    }

    /// What a key pressed into the key field means now.
    func pressed(_ trigger: KeyTrigger, _ modifiers: PressedKey.Modifiers, _ typed: String?) -> PressedKey.Outcome {
        PressedKey.decide(trigger, modifiers: modifiers, typed: typed, row: keyRow, clears: false, in: draft)
    }

    /// The keys that already land on the existing site.
    var keysAlready: [String] {
        guard case let .existing(name) = subject else { return [] }
        return draft.keys.filter { $0.key.action == ActionSource(.site, name) && $0.id != keyRow }.map(\.key.key)
    }

    func problems(_ fields: SiteSource.Field...) -> [String] {
        guard case let .newSite(id) = subject else { return [] }
        return draft.issues.compactMap { issue in
            guard case let .site(row, field) = issue.spot, row == id, fields.contains(field) else { return nil }
            return FormWording.text(issue.message)
        }
    }

    var keyProblems: [String] {
        draft.issues.compactMap { issue in
            guard case let .key(row, _) = issue.spot, row == keyRow else { return nil }
            return FormWording.text(issue.message)
        }
    }

    /// Where the site lands, once it is valid: "Profile 1, windows labelled “Alex (acme.dev)”".
    var landing: String? {
        guard let site = draft.config?.site(named: siteName) else { return nil }
        let text = Checkup.site(site, defaultBrowser: defaultBrowser, catalog: reads).text
        return text.components(separatedBy: " → ").dropFirst().joined(separator: " → ")
    }

    var config: Config? {
        keyRow == nil ? nil : draft.config
    }

    private var newSite: SiteSource? {
        guard case let .newSite(id) = subject else { return nil }
        return draft.site(id)?.site
    }

    private func updateSite(_ change: (inout SiteSource) -> Void) {
        guard case let .newSite(id) = subject else { return }
        draft.updateSite(id, change)
    }

    private func pickProfile() {
        guard let catalog else { return }
        guard let directory = profileDirectory, let profile = catalog.profile(directory: directory) else {
            updateSite {
                $0.account = nil
                $0.profile = nil
            }
            return
        }
        let fields = SiteAccount.fields(for: profile, in: catalog)
        updateSite {
            $0.account = fields.account
            $0.profile = fields.profile
        }
    }
}

struct AddTabView: View {
    @ObservedObject var model: AddTabModel
    let onCancel: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.subject {
            case .newSite:
                heading("Give this tab a key", nil)
                Form {
                    FieldRow(
                        label: "Name",
                        text: $model.name,
                        prompt: "github",
                        note: "Also the link capsjump://\(model.siteName.isEmpty ? "<name>" : model.siteName)",
                        problems: model.problems(.name)
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        if let catalog = model.catalog {
                            AccountPicker(
                                selection: Binding(
                                    get: { model.mustChoose ? AccountPicker.unchosen : model.profileDirectory },
                                    set: { directory in
                                        guard directory != AccountPicker.unchosen else { return }
                                        afterUpdate {
                                            model.mustChoose = false
                                            model.profileDirectory = directory
                                        }
                                    }
                                ),
                                profiles: catalog.profiles,
                                browser: model.browser,
                                none: "None (\(model.browser)'s own choice)",
                                asksFirst: model.mustChoose
                            )
                        } else {
                            TextField("Account", text: $model.account, prompt: Text("you@work.com"))
                            if let problem = model.profilesProblem {
                                Text(problem).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        EditorNotes(
                            note: model.mustChoose ? "CapsJump couldn't tell which profile this tab is in; pick one." : model.landing.map { "Lands in \($0)" },
                            problems: model.problems(.browser, .account, .profile)
                        )
                    }
                    FieldRow(label: "Page", text: $model.page, prompt: "https://", problems: model.problems(.open, .match))
                    keyField
                }
                .formStyle(.grouped)
                // A grouped form scrolls, so it has no height of its own; this window fits its content.
                .fixedSize(horizontal: false, vertical: true)
            case let .existing(name):
                heading("That's already your site \(name)", model.keysAlready.isEmpty
                    ? "Choose a key, and Caps Lock with it lands right here."
                    : "Caps Lock + \(model.keysAlready.map(KeyNames.symbol(for:)).joined(separator: " or ")) lands here already. Want another key too?")
                Form { keyField }
                    .formStyle(.grouped)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(model.isExisting ? "Add Key" : "Add", action: onAdd)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.config == nil || model.mustChoose)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
    }

    /// The title and its line, at the form's own margin.
    private func heading(_ title: String, _ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if let text {
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding([.horizontal, .top], 20)
    }

    private var keyField: some View {
        KeyRecorder(
            key: model.key,
            unset: "Choose a key",
            decide: { model.pressed($0, $1, $2) },
            onUse: { model.key = $0 },
            problems: model.keyProblems
        )
    }
}

/// Opens the Add window for the tab a browser showed, after the cases that need no window.
@MainActor
final class AddTab: NSObject, NSWindowDelegate {
    /// How the key field reaches the keys; the app sets it before the window opens.
    var listening = KeyListening.none
    private var window: NSWindow?
    private var expected: String?

    func open(_ tab: FrontTab?, browser: Browser) {
        if let window {
            AppWindows.show(window)
            return
        }
        guard let tab else {
            Alerts.show("\(browser) has no window open", "Open the page you want a key for, then try again.")
            return
        }
        guard let page = TabCapture.page(tab.url) else {
            Alerts.show("CapsJump only jumps to web pages", "The tab in front is \(tab.url). Pick a tab whose address starts with http or https, then try again.")
            return
        }
        let file = ConfigFile()
        let contents: ConfigFile.Contents?
        do {
            contents = try file.read()
        } catch {
            Alerts.show("CapsJump couldn't read its config", error.description)
            return
        }
        var config = Config(sites: [])
        if let contents {
            switch contents.result {
            case let .success(read):
                config = read
            case let .failure(error):
                let count = error.found.count
                let answer = Alerts.ask(
                    "Fix the config first",
                    "It has \(count) \(count == 1 ? "problem" : "problems"), and CapsJump won't add to a file it can't read:\n\n\(error)",
                    buttons: ["Open Config File", "Cancel"]
                )
                if answer == .alertFirstButtonReturn { ConfigFileOpener.open() }
                return
            }
        }
        expected = contents?.text

        let reads = Inputs.catalogs()
        let defaultBrowser = Browsers.defaultBrowser()
        var catalog: ProfileCatalog?
        if case let .read(found) = reads(browser) { catalog = found }
        let profile = catalog?.profile(forTitle: tab.title)
        var draft = ConfigDraft(contents.map { ConfigReader.read($0.text) } ?? ConfigSource())
        let subject: AddTabModel.Subject
        if let site = TabCapture.existingSite(for: tab.url, browser: browser, profile: profile, in: config, defaultBrowser: defaultBrowser, catalog: reads) {
            subject = .existing(name: site.name)
        } else {
            let name = TabCapture.suggestedName(for: page, taken: Set(config.sites.map(\.name)))
            let named = browser == defaultBrowser ? nil : browser.name
            subject = .newSite(id: draft.addSite(SiteSource(index: draft.sites.count, name: name, open: page.absoluteString, browser: named)))
        }
        let model = AddTabModel(draft: draft, subject: subject, catalog: catalog, profile: profile, browser: browser, defaultBrowser: defaultBrowser, reads: reads)
        let view = AddTabView(
            model: model,
            onCancel: { [weak self] in self?.window?.close() },
            onAdd: { [weak self] in self?.save(model) }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view.environment(\.keyListening, listening)))
        window.title = "Add Current Tab"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        AppWindows.show(window)
    }

    private func save(_ model: AddTabModel) {
        guard let config = model.config, let window else { return }
        if let expected, !ConfigWriter.isCanonical(expected) {
            switch Alerts.ask(
                "Rewrite your config?",
                "Saving rewrites \(ConfigFile().url.path) in CapsJump's own layout, so its comments and formatting won't survive. What each key does stays the same.",
                buttons: ["Save", "Cancel", "Open Config File"],
                in: window
            ) {
            case .alertFirstButtonReturn: break
            case .alertThirdButtonReturn:
                ConfigFileOpener.open()
                return
            default: return
            }
        }
        do {
            try ConfigFile().write(config, replacing: expected)
            window.close()
        } catch {
            if case .changedOnDisk = error {
                Alerts.show("The config changed while this window was open", "Nothing was saved. Try Add Current Tab again to start from the new file.", in: window)
                window.close()
            } else {
                Alerts.show("Nothing was saved", error.description, in: window)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        self.window = nil
        expected = nil
        AppWindows.closed(window)
    }
}

/// CapsJump's alerts, brought to the front whether or not a window of its own is.
@MainActor
enum Alerts {
    static func show(_ title: String, _ text: String, in window: NSWindow? = nil) {
        _ = ask(title, text, buttons: ["OK"], in: window)
    }

    static func ask(_ title: String, _ text: String, buttons: [String], in window: NSWindow? = nil) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        buttons.forEach { alert.addButton(withTitle: $0) }
        if window == nil { NSApp.activate(ignoringOtherApps: true) }
        return alert.runModal()
    }
}
