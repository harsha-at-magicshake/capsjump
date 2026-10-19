# Sites in any browser (CapsJump 0.10.0)

This document goes with the pull request that takes CapsJump's sites beyond Google Chrome.
It is written so the maintainer, or an agent reviewing on the maintainer's behalf, can
review the whole change from this file and the diff, without the conversation behind it.
It covers what changed for people using CapsJump, what changed in the code, every
decision taken and why, what was and wasn't verified, the known open items, and ideas for
later.

- Branch: `feat/sites-in-any-browser` on the fork `harsha-at-magicshake/capsjump`
- Base: upstream `main` at `8399825` (CapsJump 0.9.2, #47), merged into the branch. The
  work started from `a64c93a` (0.7.1); §10 lists how each conflict with upstream was
  resolved.
- Version bumped to `0.10.0`
- Tests: 249 Swift Testing tests (13 + 216 + 20 across the three test targets), all green
  on macOS 27.0.1 with Swift 6.4

---

## Thank you

First, thank you, **Suresh Attaluri**, for CapsJump. It is rare to find a tool this small
that is this carefully made. The pure Core module with nearly every rule under test, the
config read as a YAML tree so a typo is refused rather than dropped, the window pairing
measured on a real Mac, the comments that say *why* and not only *what*, and the
attention to wording in every message made this change possible to do well. Almost every
part of the work below was a matter of following the patterns already there. The aim
throughout was to make the change read as if it had always belonged to CapsJump. Where
it doesn't, that is ours to fix, and we'd welcome the review.

---

## 1. Summary

Before this change, a site (`sites:` in `~/.capsjump.yaml`, reachable as
`capsjump://<name>` or a Caps Lock key) only worked in Google Chrome, and it had to name
a Chrome account.

After it:

- **A site opens in the Mac's default browser**, unless it names one with the new
  `browser:` line.
- **`account:` and `profile:` are optional.** A site with neither opens the way a clicked
  link does (the browser's own choice of profile) and finds its tab in any of that
  browser's windows.
- **Chrome, Brave, Edge, Vivaldi and Chromium get the whole jump:** the right profile,
  and the tab you already have open is focused instead of a duplicate being opened.
- **Arc, Safari, Firefox and any other default browser only open the page.**
- **Existing configs keep working, whatever the default browser is.** A site with an
  account and no `browser:` tries the default browser and then Chrome (the "Chrome
  fallback").
- Add Current Tab, the editor, `capsjump check`, `capsjump profiles`, `capsjump init`
  the Welcome window and the coding-agent skill all understand browsers.

The person who asked for this uses Brave as their main browser, with several Brave
profiles and Brave web apps. Everything was verified live in Brave on macOS 27. Chrome,
Edge, Vivaldi and Chromium were not installed on the test Mac (see §7).

---

## 2. What's new and improved (for people using CapsJump)

### 2.1 The config

```yaml
sites:
- name: github                 # default browser, its own choice of profile
  open: https://github.com
- name: mail                   # default browser, the profile named Parents
  account: Parents
  open: https://mail.google.com/mail/u/0/#inbox
- name: client-docs            # always Chrome, this account
  browser: chrome
  account: client@example.com
  open: https://docs.google.com
keys:
  b: {site: github}
  m: {site: mail}
```

- `browser:` takes `chrome`, `brave`, `edge`, `vivaldi`, `chromium`, `arc`, `safari` or
  `firefox`, in any case (`Brave` is read as `brave`, and CapsJump writes it back in lower
  case). Any other value is refused with the list of valid names.
- `account:` is an email, or a profile's name (Brave's profiles only have names, since
  Brave has no Google sign-in). `profile:` is still a folder such as `Profile 5`.
- Leave out both `account:` and `profile:` and the site opens wherever the browser opens a
  link, finding its tab in any window.
- A site that names a browser CapsJump can't read profiles from (Arc, Safari, Firefox)
  and also sets `account:` or `profile:` is a config problem, worded for the person:
  "Safari has no profiles CapsJump can read; remove `account` and `profile`, or pick a
  browser that has them".
- A file that uses `browser:`, or has a site with no account, needs CapsJump 0.10.0. An
  older CapsJump refuses the file and keeps its last keys (documented in the README).

### 2.2 Which browser and profile a site lands in

| The site has | Browsers tried, in order | Notes |
|---|---|---|
| `browser: X` | X only | Never falls back. |
| no `account:`/`profile:` | the default browser | Its own choice of profile, any window. |
| `account:` | the default browser (if it has full support), then Chrome | The Chrome fallback. When both have it, the default wins. |
| only `profile:` | Chrome, then the default browser | Every Chromium browser has `Default` and `Profile 1`, so a folder doesn't say which browser was meant; such sites were Chrome's before. |

A browser counts only when it is **installed**, its profile list **can be read**, and the
account or folder **resolves** there. When nothing resolves, the error names every
browser tried and why each failed, for example:

```
mail: macOS won't let CapsJump read Brave's profile list at …/Local State; turn CapsJump on
under System Settings › Privacy & Security › Full Disk Access; Google Chrome is not installed
```

### 2.3 Jumping

- **Full-support browser, site with a profile:** as before, but in any Chromium browser.
  CapsJump finds that profile's windows by their Accessibility titles, focuses a matching
  tab, or opens the page in that profile.
- **Full-support browser, site with no profile:** CapsJump searches every window the
  browser's scripting lists **with a name**, front to back. It raises a window that
  Accessibility can see through Accessibility, and one it can't (another desktop, full
  screen) through scripting alone. If no tab matches, it opens the page the way a link
  would.
- **Web-app windows are never focused.** Brave lists a web app's window (installed with
  "Install page as app") with an **empty name** in scripting. A window with no name is
  never searched, so a site never lands inside your Outlook or Speed app; a normal window
  gets a new tab instead. The person asked for this explicitly: "duplicate tab is fine,
  open a new one".
- **A browser with one profile:** its titles carry no profile label, so any window counts.
- **Plain browsers** just open the page.
- A refused permission is still an error, **never** a reason to open a duplicate tab.
- As upstream 0.9.1 added, a jump says `focused` only once it has seen the window in front,
  in any of these browsers; otherwise a notification names the app that stayed in front.

### 2.4 Add Current Tab

- Reads the tab in front of the browser you're using: the front app if it's a
  full-support browser, else the one you used last, else the default browser.
- Fills in the account from that browser's profiles, by the window title.
- Writes `browser:` on the new site **only when that browser isn't your default**, so the
  file stays short and the default stays meaningful.
- If the tab's window doesn't say which of several profiles it is in, the Account menu
  starts on **Choose…** and Add stays disabled until you pick one, None included.
- A site with no account no longer stands in for a tab in a **known** profile. You can
  make a separate "GitHub in Work" site from a tab even while a site with no account
  opens the same page.
- When the profile list can't be read, the window says why under the Account field.

### 2.5 The editor (Edit Config…, Sites)

- A **Browser** menu: "Default (Brave)" first, then the installed browsers CapsJump knows.
  A browser the file names stays listed even if it isn't installed on this Mac.
- The **Account** menu lists the profiles of the browser the site actually opens in (as a
  jump would choose it, Chrome fallback included). Its first item is **None (Brave's own
  choice)**, which removes both `account:` and `profile:`.
- For a browser CapsJump can't read profiles from, the account control is replaced by a
  short note. If the row still has an `account:`, the field stays visible so it can be
  fixed.
- Site icons and account pictures come from the site's browser's own saved files.
- When a profile list can't be read, the reason shows under the field.

### 2.6 Commands

- `capsjump check` now starts its site lines with the default browser and says where each
  site lands:
  ```
  ok      default browser: Brave
  ok      github → Brave (default), its own choice of profile, any window
  ok      mail → Brave (default), Profile 5, windows labelled “Parents”
  ok      old → Google Chrome (fell back to Chrome), Profile 1, windows labelled “Alex (acme.dev)”
  ok      plain → Safari, opens the page; no tab search
  ```
- `capsjump profiles [browser]` lists a browser's profiles: the default browser's, or
  the one named (`capsjump profiles brave`). It refuses an unknown name, a browser with
  no profiles, or a list macOS refuses, each with its reason.
- `capsjump init` writes the starter for the default browser's first profile. When it
  can't read profiles, the file has the window keys and no example site (upstream 0.9.0's
  rule, kept).

### 2.7 The Welcome window and permissions

- Upstream 0.9.0's Welcome window had an optional **Chrome accounts** row. It is now a row
  for the browser sites open in, named after it (**Brave accounts** on the test Mac). That
  is the default browser when CapsJump scripts it, else Chrome, where sites with an
  account fall back. The row is shown when that browser is installed. **Allow…** starts
  the browser and asks for Automation of it.
- Any other browser a site names (`browser: chrome` with Brave as default, say) is asked
  for by macOS the first time a jump scripts it.
- When macOS refuses CapsJump that browser's profile list, the row says so ("macOS won't
  let CapsJump read which profiles Brave has; turn CapsJump on under Full Disk Access")
  and offers **Open Full Disk Access Settings**. Like every optional row, it never blocks
  setting up, and sites with no account never need the list.
- The Automation usage string now reads "CapsJump reads your browser's tabs to bring
  forward the one a link names."

---

## 3. What changed technically

### 3.1 Architecture in one picture

```
~/.capsjump.yaml ──ConfigReader──▶ ConfigSource ──ConfigRules──▶ Config (Site.browser: Browser?)
                                                                   │
default browser (NSWorkspace, https:) ─┐                           ▼
each browser's Local State (Inputs) ───┴──▶ Placement.place ──▶ Destination
                                                                   │  browser, target?(profile), windowLabel?,
                                                                   │  fellBack, isDefault
                                                                   ▼
browser scripting windows + Accessibility titles ──▶ Jump.decide ──▶ Action (.focus / .open)
                                                                   │
                                                                   ▼
                                     Jumper carries it out in that browser (CapsJumpChrome)
```

The design goal was to keep **every rule in Core** (pure, testable) and have the live side
only gather facts and carry out decisions, as CapsJump already did for Chrome.

### 3.2 Core (`Sources/CapsJumpCore`)

| File | Change |
|---|---|
| `Browser.swift` (new) | The browser table: `name` (config name, nil for an unknown default), `bundleID`, `displayName`, `dataFolder` (under `~/Library/Application Support`; nil = plain). `support` is `.full` exactly when there is a data folder, so a browser can't be "full" without a profile list. `named(_:)` is case-insensitive. `app(bundleID:displayName:)` maps the default browser to its row, an unknown one to a plain browser, and nil to Chrome. `localState(home:)`, `profileFolder(_:home:)` and `data(home:)` give the paths. |
| `Placement.swift` (new) | `CatalogRead` (`.read`, `.missing`, `.refused`, `.unreadable`, `.notInstalled`), each with its wording through `problem(for:)`. `Destination` (site, browser, optional `Target`, `windowLabel`, `fellBack`, `isDefault`). `PlaceError` with one `Attempt` per browser tried. `Placement.place(_:defaultBrowser:catalog:)` implements §2.2. `Placement.browser(for: SiteSource …)` gives the editor the browser for a row that may not be valid yet. Every profile list comes in through a `catalog` closure, so Core never touches the disk. |
| `Jump.swift` | `decide(destination:running:windows:titles:tabs:)` replaces `decide(target:chromeRunning:…)`. `Action.open(profileDirectory: String?, …)`, and `Action.focus(… titleIndex: Int?)` (nil = raise through scripting alone). `OpenReason` gains `.plain`; `.chromeNotRunning` became `.notRunning` ("the browser is not running"). |
| `WindowPairing.swift` | `windows(labelled: String?)`: nil means every paired window. `title(_:endsWithLabel:)` replaces `labelSuffix` and accepts both Chrome's `– <label>` (en dash) and Brave's ` - <label>` (hyphen). See §4, D12. |
| `Resolution.swift` | `Resolver.profile(account:directory:in:)` is extracted from `resolve`, so Placement can resolve a row that isn't a `Site` yet. Wording no longer says "Chrome". |
| `ChromeProfiles.swift` | `profile(forTitle:)` uses `title(_:endsWithLabel:)`. `LookupError` and `ParseError` wording no longer says "Chrome". The file and type names are unchanged; see D3. |
| `Config.swift`, `ConfigSource.swift`, `ConfigRules.swift`, `ConfigWriter.swift`, `ConfigDraft.swift` | `browser` is read, validated, written (right after `name`, lower case) and carried through the editing draft. `SiteSource.Field.browser` is new and `.accountOrProfile` is gone, along with its rule. The writer's header says "the right browser and account". |
| `Checkup.swift` | `run(configText:configPath:defaultBrowser:catalog:lookup:)` and `site(_:defaultBrowser:catalog:)`. It reads each browser's list once per run and produces the lines in §2.6. |
| `TabCapture.swift` | `existingSite(for:browser:profile:in:defaultBrowser:catalog:)`, with the "known profile" rule from §2.4. `needsProfileChoice(catalog:profile:)` is new. |
| `StarterConfig.swift` | Writes no account when there is no catalog. |
| `FormWording.swift` | Sentences for the two browser problems, replacing the removed account rule's. |
| `Identity.swift` | `chromeBundleID`, `Paths.chromeData` and `Paths.chromeLocalState` are removed; they moved onto `Browser`. |

### 3.3 Live side (`Sources/CapsJumpChrome`)

Every Chrome constant became a `Browser` parameter. The module keeps its name (D3).

| File | Change |
|---|---|
| `Browsers.swift` (new) | `defaultBrowser()` (the app macOS opens `https://` links with, read afresh each time) and `installed()`. |
| `Jumper.swift` | `Inputs.catalog(for:home:installed:)` reads a browser's `Local State` and maps `CocoaError.fileReadNoSuchFile` to `.missing` and `.fileReadNoPermission` to `.refused`; a browser that isn't installed gives `.notInstalled`. `Inputs.catalogs()` reads each list once per jump. `JumpError.place` replaces `.profiles` and `.resolve`. `Outcome` names the browser ("mail: focused tab 3 of Brave window 792337432"). `Jumper` places, decides and acts, with one compiled script cached per browser. |
| `ChromeScripting.swift` | `init(browser:)`. Only the bundle ID is written into the script text, and only for full-support rows from the fixed table; every value still goes in as a typed Apple Event parameter. |
| `ChromeLauncher.swift` | `running(_:)`, `start(_:timeout:)`, `open(_:in:profileDirectory:)`. With a folder: the existing new-instance `--profile-directory=` launch. Without one: `NSWorkspace.open(_:withApplicationAt:)`, as a clicked link. |
| `ChromeAccessibility.swift`, `FrontTab.swift`, `Permissions.swift`, `ChromeFavicons.swift`, `ChromeProfilePicture.swift` | Take the browser; the file paths come back nil for a plain browser. |
| `ChromeError.swift` | Cases that named Chrome carry the browser's display name. `isMissingPermission` moved here from the app, because the cases now carry values. |

### 3.4 App (`Sources/CapsJumpApp`)

- `BrowserTracker.swift` (new): remembers the last full-support browser activated, for
  Add Current Tab.
- `AppDelegate.swift`, `AddTabWindow.swift`: Add Current Tab, per §2.4.
- `EditorModel.swift`, `SitesPane.swift`, `SiteIcons.swift`, `ProfilePictures.swift`: the
  Browser menu, per-browser profile lists (read once per opening of the window), None,
  Choose…, and the reason shown when a list can't be read.
- `Setup.swift`, `WelcomeWindow.swift`: upstream's Welcome window helpers take a browser
  (`Setup.browser`, `access(of:)`, `ask(for:)`, `profilesRefused(_:)`, `catalog(_:)`, and a
  `fullDiskAccess` pane). The row and the starter keys use them, per §2.7.
- `StatusMenu.swift`: Check Config uses the new Checkup; Add Current Tab is enabled while
  any full-support browser runs.

### 3.5 CLI, packaging, docs

- `Sources/capsjump/CapsJump.swift`: `init`, `profiles [browser]`, `check`, and the help
  text.
- `packaging/Info.plist`: the Automation usage string. `packaging/capsjump.rb.in`: the
  cask description.
- `README.md`, `site/index.html`: the config example, a `browser:` reference, the fallback
  rule, permissions, and the jump description. `Package.swift`: header comment.
- `skills/capsjump/SKILL.md` (upstream's coding-agent skill): it describes sites in any
  browser, makes `account`/`profile` optional, documents `browser`, and says how to list
  another browser's profiles (`capsjump profiles <browser> --json`).
  `SkillReferenceTests.knowsEveryBrowser` pins every `browser:` name in it, in the same
  way upstream pins window moves and actions.
- `VERSION`: `0.10.0` (upstream is at 0.9.0), as #26 bumped inside its feature PR.

### 3.6 Tests

New suites: `BrowserTests`, `PlacementTests`, `InputsTests` (a temp home folder: missing,
good, not a profile list, refused through `chmod 000`, not installed, plain). Extended:
`ConfigRulesTests`, `ConfigWriterTests`, `CheckupTests`, `TabCaptureTests`,
`WindowPairingTests` (now with `JumpTests` built around `Destination`), and
`ProfileTests`. Tests that pinned the removed "give `account` or `profile`" rule were
updated to keep their intent, for example by breaking a site with `browser: opera`
instead of a missing account.

Every rule change was written test-first and watched failing before the code was
written. The app-side SwiftUI/AppKit code has no tests, as before. It was checked by hand
(§7).

### 3.7 The commits, in order

| Commit | What it does |
|---|---|
| `9c28d1b` | **Unrelated, needed to build:** `KeyTests.knownKeys`'s untyped `@Test(arguments:)` tuple list times out Swift 6.4's type checker. Naming its type fixes it. This could go upstream on its own. |
| `437a2f9` | `Browser` table, `browser:` field, account/profile optional. |
| `64d377b` | `Placement` and the Chrome fallback. |
| `513c759` | `Jump.decide(destination:)`: no-profile path, plain browsers, one-profile browsers. |
| `10bbf06` | `check`, the starter file, Add Current Tab's rule. |
| `3a88e48` | The live side takes a browser. |
| `bbdd6ce` | CLI: `profiles [browser]`, `init`, `check`. |
| `7f58e3e` | Add Current Tab reads the browser you used last. |
| `d02d5d8` | Editor: Browser menu, None. |
| `0193740` | Setup per browser; Info.plist. |
| `3e0303c` | Docs; version 0.8.0 (now 0.10.0, see the merge). |
| `47036aa` | **Fix from live testing:** Brave's titles use a hyphen before the profile (D12). |
| `7282ceb` | Fix: a browser whose folder outlives the app counts as not installed. |
| `5561c9c` | Fix: the editor keeps a site's account when no browser takes it. |
| `45666a1` | Fix: Add Current Tab asks for a profile it can't tell, and makes per-profile sites. |
| `c9c8cc6` | Fix: a site with no profile finds its tab in any named window. |
| `5d959ef` | Fix: Setup asks for Full Disk Access only when a site needs a profile list. Superseded by the merge, where upstream's Welcome window replaced that Setup. |
| `4399fc6` | Fix: the editor and Add Current Tab say why profiles can't be listed. |
| `53c4ee3` | This document. |
| merge | Merge of upstream `main` (0.9.0): conflicts resolved per §10; the Welcome window, `profiles --json`, the skill and the README/site follow browsers; version 0.10.0; Setup's now-unused `browsersUsed`/`browsersReadingProfiles` removed with their tests. |

The last seven commits came out of live testing and an independent review of the branch.
They could be folded into the feature commits before merging if you prefer a shorter
history.

---

## 4. Decisions taken

Each decision says who made it, why, and what it costs if it's wrong. "The person" is the
contributor who asked for the change; "implementer" means a call made while building it.

**D1. A site opens in the Mac's default browser unless it names one** (the person). An
alternative was a top-level `browser:` defaulting to Chrome. The person preferred that
the browser you actually use is the default, with a per-site override. Risk: if someone
changes their default browser, sites without `browser:` move with it. `check` shows where
each site lands, and an account that doesn't exist in the new browser is an error with a
clear message, never a silent guess.

**D2. The Chrome fallback** (the person). A site with `account:` and no `browser:` tries
the default browser, then Chrome, so an upstream user whose default is Safari or Firefox
keeps every existing Chrome site with no edit. When both browsers have the account, the
default wins. Alternatives were to accept the break, or to rewrite configs once. Both
were turned down.

**D3. Keep the `CapsJumpChrome` module and the `Chrome*` type names** (implementer).
Renaming would have doubled the diff and made review harder. Their header comments now
say they serve any Chromium browser, and the README notes the module is "named for
Chrome, the first browser it drove". A rename can follow as its own PR if you want it.

**D4. A fixed list of `browser:` names** (implementer). An unknown name is an error, the
same way `acount:` is caught today, rather than accepting any bundle ID. The unknown
*default* browser case is still handled, as a plain browser.

**D5. Arc, Safari and Firefox get plain support only** (spec). Arc's scripting has spaces
instead of profiles and a different dictionary. Safari and Firefox have no Chromium
profile list.

**D6. A site with only `profile:` tries Chrome first** (implementer, in the plan).
`Default` and `Profile 1` exist in every Chromium browser, so a folder alone doesn't say
which browser was meant, and before this change such sites were Chrome's.

**D7. Name-only accounts are left as they are** (the person, after the review raised it).
Chrome and Chromium name the first profile "Person 1". An old config with
`account: Person 1` would move to Brave if Brave also has a profile named "Person 1". The
alternative was to treat name-only accounts like folder-only ones (Chrome first). That
was declined, because it would make the person's own Brave sites (which only have names)
depend on Chrome having no profile of the same name. **Flagged for your review.**

**D8. Duplicate tabs over landing in a web-app window** (the person). Brave lists
web-app windows with an empty name, and they are excluded from every search.

**D9. Add Current Tab writes `browser:` only when it isn't the default** (implementer).
This keeps files short and the default meaningful.

**D10. The editor gets a Browser menu and a "None" account choice** (implementer). None
is the explicit way to say "the browser's own choice of profile". Add Current Tab starts
on **Choose…** when it can't tell the profile, so None is never picked silently.

**D11. Profile lists are reported as `refused`, not missing** (implementer). On macOS 27
a process can be refused reading another app's `~/Library/Application Support` folder.
That is now its own state, with a hint to the setting that allows it (Full Disk Access).
It only matters for sites with an account or folder; D16 makes Setup respect that.

**D12. A profile label follows either an en dash or a hyphen** (implementer, from live
testing). Chrome writes `<page> - Google Chrome – <profile>`; Brave writes
`<page> - Brave - <profile>` (U+002D, measured). Requiring Chrome's en dash meant no Brave
window ever counted as its profile's, so every site with an account opened a new tab. The
label must still be the whole ending (`labelMustBeTheWholeEnding` still holds).
Considered: requiring the browser's own name before the label. That's stricter, but the
title formats of Edge, Vivaldi and Chromium aren't verified.

**D13. A site with no profile searches every named scripted window** (spec; the first
implementation was stricter). The first version searched only windows paired with an
Accessibility title, which also kept web apps out. Review pointed out that this gives
duplicates for tabs on other desktops. Web apps are now kept out by their empty name, and
a window Accessibility can't see is raised through scripting alone (`titleIndex: nil`).
Since upstream 0.9.1's landing check (#43), a jump says `focused` only once it has seen
the target in front. For such a window there is no Accessibility element to compare, so
the check asks whether the browser's focused window title fits the scripted window's
name, by the same rule that pairs windows (`WindowPairing.title(_:fits:)`, which pairing
now also uses). See §10.

**D14. A browser whose app is gone counts as not installed** (implementer, from the
review). A browser's data folder outlives the app. The test Mac had Chrome's folder but no
Chrome, so the fallback "found" profiles in an uninstalled Chrome, and `check` called a
failing site fine.

**D15. The Welcome window asks about one browser** (implementer, at the merge). That is
the one sites open in: the default browser when CapsJump scripts it, else Chrome. Other
browsers are asked for by macOS on their first jump. Before the merge, a Setup alert
asked for each browser the config uses; upstream's one-row-per-permission design is
simpler, and starting several browsers during setup seemed unkind.

**D16. Full Disk Access is a hint, never a blocker** (implementer, from the review, kept
through the merge). Sites with no account never read a profile list. The Welcome
window's browser row shows the Full Disk Access hint only when the list is refused, and
like every optional row it doesn't count towards "set up". Before the merge, the same
aim was met by counting a refused list only when a site needed it.

**D17. A no-account site stands in for a tab only when the tab's profile can't be told
apart** (implementer, from the review; this reverses the plan). When the tab's profile is
known and the browser has several, Add Current Tab offers a new site in that profile
instead of "That's already your site github".

**D18. The editor's browser for a row that doesn't resolve is the first browser tried,
not the default** (implementer, from the review). With Safari as default, this keeps an
`account:` row visible and fixable instead of hidden.

**D19. Smaller wording calls.** All reasons in a `PlaceError` name their browser and are
joined with "; ". Profile-list parse errors say "Brave's profile list at … can't be used:
it lists no profiles". The reader's "must be a mapping with name and open" no longer
mentions account. The refused-list hint says "turn CapsJump on under … Full Disk Access",
even when the CLI (running as the terminal) prints it.

**D20. Version 0.10.0 inside this PR**, following #26. It was 0.8.0 until upstream
reached 0.9.0.

**D21. At the merge, upstream's starter rule wins** (implementer). Upstream 0.9.0 writes
no example site when accounts can't be read ("never a made-up one"); the branch had
written a site with no account. That is the maintainer's recent call, so it stays.

---

## 5. Compatibility

- **Existing configs:** unchanged behaviour when Chrome is the default. With another
  default, sites with an account keep landing in Chrome through the fallback (D2), and
  folder-only sites stay Chrome's (D6). The one known way an old site can move is D7.
- **Old CapsJump reading a 0.10.0 file:** `browser:` is an unknown key, and a site with no
  account breaks the old rule, so 0.7.x refuses the file and keeps its last keys. The
  README says a file using either needs 0.10.0.
- **Bundle ID:** unchanged (`ai.stigmer.capsjump`). Releases keep their grants as before.

---

## 6. How it was verified

### 6.1 Automated

`swift test`: 249 tests, all passing on macOS 27.0.1 / Swift 6.4 (Xcode with the
macOS 27 SDK). Every Core rule in §2 has a test with hand-written expectations: literal
JSON profile lists, literal window titles as measured, and exact message strings where
the wording matters.

### 6.2 Live, in Brave (the default browser), macOS 27.0.1

| Check | Result |
|---|---|
| Brave answers Chrome's scripting (`id`, `name`, `URL of tabs`, `active tab index`, `index`, `visible`) | Yes. |
| Web-app windows in scripting | Listed, with an **empty name** and `visible` false; never focused. |
| Accessibility titles | `Inbox (925) - … - Gmail - Brave - Parents`: hyphen before the label (D12). |
| `--profile-directory=Profile 5` with Brave running, Work window in front | New tab lands in the Parents window. Correct. |
| Site with no account, Caps Lock + B | First press "opened in Brave (no open tab matches)", next presses "focused tab 1 of Brave window …". |
| Site with `account: Parents`, Caps Lock + M, from the Parents and from the Work window | Before D12: always reopened. After: "focused tab 3 of Brave window 792337432", confirmed by the person. |
| Add Current Tab | Lists Brave's profiles (CapsJump.app had Full Disk Access). The saved site opens in the chosen profile. |
| `capsjump check` / `profiles` / `profiles opera` / `profiles safari` | Lines and errors as in §2.6. |

### 6.3 Not verified

- **Chrome, Edge, Vivaldi and Chromium were not installed on the test Mac.** Chrome's
  behaviour is the old code path with Chrome's constants, so the risk is low. Edge,
  Vivaldi and Chromium are assumed to share Chrome's scripting dictionary and title
  format (with either separator). **Edge's titles may put the profile in a different
  place**, in which case Edge sites with an account would always open a new tab. That is
  safe, but no better than before.
- **Whether macOS 27 needs Full Disk Access, or a narrower setting.** The terminal was
  refused reading `~/Library/Application Support/BraveSoftware`, `Google/Chrome` and
  `Microsoft Edge`. CapsJump.app could read Brave's list once it had Full Disk Access. It
  wasn't established whether a narrower "App Data" style permission suffices.
- **Arc** was not tried.
- **The app UI** (editor, Add Current Tab) was only checked by hand in Brave, before the
  merge. **The Welcome window's browser row was written at the merge and has not been run
  live.** It builds and its helpers are the tested ones, but please open it once.

### 6.4 A testing gotcha worth knowing (not part of the change)

A local build and an installed release share the bundle ID `ai.stigmer.capsjump`, and
macOS keeps one permission entry per bundle ID, tied to the signature last granted.
Running both (or letting the release relaunch as a login item) makes them take the grant
from each other, so Accessibility "keeps asking". Also, System Settings resolves the
bundle ID to the copy in `/Applications` first. What made live testing reliable:

1. Sign the local build with a stable identity (`scripts/bundle.sh --identity <Apple
   Development identity>`), so grants survive rebuilds.
2. Have only one copy on disk: the release was zipped away during testing. Renaming it
   wasn't enough, because its login item followed the rename.
3. Run `tccutil reset Accessibility ai.stigmer.capsjump` and
   `tccutil reset AppleEvents ai.stigmer.capsjump`, then grant once.

`make install-local` already resets these, which also wipes the release app's grants.
That may be worth a note in the Makefile.

---

## 7. Open items and known issues

From the independent review, graded minor and deferred, not fixed in this PR:

1. The editor's Account menu shows **None** for an `account:` that doesn't resolve in the
   site's browser (for example, after switching a site's browser). It should say
   "not in <browser>".
2. `check` tags every non-default landing "(fell back to Chrome)", including folder-only
   sites, where Chrome was the first choice. It reads "Google Chrome (fell back to Chrome)".
3. `FormWording` says "pick None" for the plain-browser problem, where no picker is shown.
4. `PlaceError` joins reasons with "; ", but the reasons themselves contain "; ", so two
   attempts are hard to tell apart in one line. ". " or a line break would read better.
5. `capsjump init` with a plain default prints a redundant note ("Safari's profiles could
   not be read (Safari has no profiles CapsJump can read)").
6. Sites with no account always show the globe icon in the editor, because no profile
   folder is known. `Local State`'s `profile.last_used` could choose one.
7. `FrontTabReader` takes `windows.first`, which can be a nameless web-app window. It
   should skip nameless windows. In practice Add Current Tab reads the front browser
   window, but it can misread when a web app was the last window in front.
8. `ChromeScripting.init(browser:)` accepts any `Browser`. No call path passes a plain
   one today, but guarding `support == .full` would ensure an arbitrary bundle ID never
   reaches script source.
9. Some header comment lines now run past the repo's ~90-column wrap (`Package.swift`,
   `ChromeFavicons.swift`, `ChromeProfilePicture.swift`, `ProfilePictures.swift`,
   `Config.swift`, `ConfigRules.swift`).
10. The README and site describe Edge, Vivaldi and Chromium as working like Brave; that
    was only verified in Brave (§6.3).

Other open items:

- **D7** (name-only accounts and the default browser) needs your call.
- EditorModel has six `weak self` compiler warnings (around lines 246–258) that
  **predate** this branch.

---

## 8. What could be improved later

- **Verify and, if needed, special-case Edge, Vivaldi and Chromium** title formats. If a
  browser's titles don't end in the label, the cleanest fix is a per-browser "label
  match" in `Browser`, tested against measured titles.
- **Arc support:** Arc has its own scripting dictionary, built around windows, spaces
  and tabs (not checked here). Spaces could map to `account:`. It needs its own decision
  code path, but the `Destination` / `Jump.decide` split makes that a contained change.
- **Safari tab search:** Safari's scripting lists windows and tabs, though it has no
  Chromium-style profile list. Finding an open tab there would remove the most common
  "duplicate tab" case for Safari users.
- **Pick the folder for no-account sites** from `profile.last_used`, for icons and
  pictures in the editor (open item 6).
- **A `capsjump doctor` style check for privacy settings**, saying exactly which setting
  blocks which file, ideally without asking for Full Disk Access when a narrower
  permission is enough.
- **A Makefile target for live testing** that signs with a local identity and warns
  about a second installed copy (§6.4).
- **Rename `CapsJumpChrome`** to something like `CapsJumpBrowser` in a follow-up, if
  wanted (D3).
- **Fold the review fixes into the feature commits** before merging, for a tidier
  history.

---

## 9. Reviewing this PR: a guide

Suggested order (each step depends only on the ones before it):

1. **The table and the field:** `Browser.swift`, then `ConfigSource.swift` /
   `ConfigRules.swift` / `ConfigWriter.swift` with `BrowserTests` and `ConfigRulesTests`.
2. **The rule that matters most:** `Placement.swift` with `PlacementTests`. Check §2.2
   against `tries(named:account:profile:defaultBrowser:)` and D2, D6, D7 and D14.
3. **The decision:** `Jump.swift` and `WindowPairing.swift` with `JumpTests` (in
   `WindowPairingTests.swift`). Check D8, D12 and D13. In particular, a window with an
   empty name must never be searched.
4. **The live side:** `Jumper.swift` (`Inputs.catalog`, `Jumper.perform`),
   `ChromeScripting.swift` (only the bundle ID goes into source), `ChromeLauncher.swift`.
5. **The app:** `AddTabWindow.swift`, `BrowserTracker.swift`, `EditorModel.swift`,
   `SitesPane.swift`, `Setup.swift`, `WelcomeWindow.swift`. These have no tests; read them
   against §2.4–§2.7.
6. **Docs:** README, site, this file.

Useful commands:

```sh
git log --oneline a64c93a..feat/sites-in-any-browser
git diff a64c93a..feat/sites-in-any-browser --stat
swift test
swift run capsjump profiles brave        # needs the terminal to be allowed to read Brave's folder
swift run capsjump check
grep -rn "chromeOnly\|runningChrome\|chromeBundleID\|Inputs.profiles" Sources   # should find nothing
```

Questions worth an agent's attention:

- Can any path still open a duplicate tab when a permission is refused? (Intended: no.
  See `readErrorIsThrownNeverOpened`.)
- Can a plain or unknown browser's bundle ID reach `ChromeScripting`'s source? (Intended:
  no; open item 8 hardens it.)
- Does every message still name the right browser? (`ChromeError`, `PlaceError`,
  `CatalogRead.problem(for:)`, `OpenReason`.)
- Does a config written by 0.7.x behave the same on a Chrome-default Mac? (Intended: yes,
  line for line, apart from `check` now printing the browser.)

---

## 10. Merging with upstream 0.9.0

The branch started from 0.7.1. Upstream reached 0.9.0 meanwhile (#30–#41: the Welcome
window, the coding-agent skill, `profiles --json` / `check --json` / `tidy`, the site at
capsjump.com, the new site design). It was merged in, not rebased, since upstream
squash-merges PRs. Twelve files conflicted. Each was resolved by keeping upstream's
change and applying the browser change on top:

| File | Resolution |
|---|---|
| `VERSION` | `0.10.0`. |
| `ChromeError.swift` | Upstream's click-to-fix wording, with the browser's name ("CapsJump may not control Brave; click to allow it, or turn on Brave under CapsJump in …"). |
| `Permissions.swift` | Upstream's header (Accessibility is only read, since macOS 26) plus "each browser". |
| `StarterConfig.swift` | Upstream's rule (D21), with "the default browser's" first profile. |
| `ConfigTests.swift` | Upstream's starter test. |
| `capsjump.rb.in` | Upstream's homepage (capsjump.com), with "browser profiles". |
| `CapsJump.swift` (CLI) | Upstream's `tidy`, `check --json` and `profiles --json`, with `profiles [browser]`, and `check` reading every browser. |
| `AppDelegate.swift` | Upstream's Welcome-window header comment, with Add Current Tab's browser. Upstream's `ChromeError.missingPermission` names the browser ("access to Brave"); `isMissingPermission` stays in `ChromeError`. |
| `StatusMenu.swift` | Upstream's `layout` finding, with the browser-aware check. |
| `Setup.swift` | Upstream's helper design, generalised to a browser (§3.4). |
| `README.md`, `site/index.html` | Upstream's new copy and structure throughout; "Chrome" becomes "browser" where it now means any browser, plus the `browser:` reference, the fallback rule, `profiles [browser] [--json]` and the Full Disk Access hint. The site's demo illustration still shows Chrome, which is accurate. |

Files upstream added that needed browser changes without conflicting:
`WelcomeWindow.swift` (the row, §2.7), `skills/capsjump/SKILL.md` (§3.5) and the README's
new "Give GitHub a key" steps.

### Second merge: upstream 0.9.1 and 0.9.2 (#43, #47)

These change how a focus is carried out, not which window or tab is chosen, so they sit
under #44's browser choice without changing it:

- **#43** made the raise report its statuses, added `ChromeAccessibility.focusedWindow`,
  and added the Core rule `Landing.land`. That rule reads the screen every 50 ms for up to
  500 ms and reports `focused` only once the target is in front; otherwise the jump fails
  with `.notInFront`.
- **#47** put the browser's own `activate` back into the focus script (AppKit's activation
  alone was refused on the signed release), while keeping #43's check.

Resolutions:

| File | Resolution |
|---|---|
| `ChromeScripting.swift` | Only the comment conflicted: the per-browser script never dropped `activate`. Upstream's reason is kept, worded for any browser. |
| `ChromeError.swift` | Upstream's `.raise` and `.notInFront` carry the browser's name like every other case ("Accessibility could not bring Brave's window forward", "Brave kept another of its windows in front"). |
| `ChromeAccessibility.swift` | `raise`, `focusedWindow` and `failure(_:during:)` take the browser; `.invalidUIElement` gives `windowGone(<browser>)`. Adds `title(of:)`. |
| `Jumper.swift` | Upstream's order (script with activate, AppKit activate, raise) and landing check, per browser. A window Accessibility can't see (D13) skips the raise, and its landing is checked by title (`WindowPairing.title(_:fits:)`, tested). |
| `ChromeAccessibilityTests.swift` (upstream's) | Same expectations through the browser-carrying API, plus a Brave case. |
| `Package.swift`, `VERSION` | Both comments kept; `0.10.0`. |

