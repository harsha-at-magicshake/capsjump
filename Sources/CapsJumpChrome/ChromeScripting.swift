// A browser with Chrome's scripting, through Apple Events: its windows' ids and names, a
// window's tabs, and focusing a tab. One compiled script per browser holds three handlers;
// only the browser's bundle id is written into the script text, and each call passes its
// values as typed Apple Event parameters, so no value from a page is ever spliced into it.
// Chrome reports window ids as text, and they go back to it as text.

import AppKit
import Carbon
import CapsJumpCore

@MainActor
public final class ChromeScripting {
    private static func source(_ bundleID: String) -> String { """
    on windowlist()
    	tell application id "\(bundleID)"
    		return {id of every window, name of every window}
    	end tell
    end windowlist

    on tablist(wid)
    	tell application id "\(bundleID)"
    		set w to window id wid
    		return {URL of every tab of w, active tab index of w}
    	end tell
    end tablist

    on focustab(wid, tabIdx)
    	tell application id "\(bundleID)"
    		set w to window id wid
    		if minimized of w then set minimized of w to false
    		set active tab index of w to tabIdx
    		set index of w to 1
    		activate
    	end tell
    end focustab
    """ }

    private let script: NSAppleScript
    private let browser: String

    public init(browser: Browser) throws(ChromeError) {
        self.browser = browser.displayName
        guard let script = NSAppleScript(source: Self.source(browser.bundleID)) else {
            throw .script(browser.displayName, code: 0, message: "the script could not be created")
        }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else {
            throw Self.chromeError(error, browser: browser.displayName)
        }
        self.script = script
    }

    /// Chrome's windows, front to back.
    public func windows() throws(ChromeError) -> [ChromeWindow] {
        let result = try call("windowlist")
        guard let ids = result.atIndex(1), let names = result.atIndex(2) else { return [] }
        let count = min(ids.numberOfItems, names.numberOfItems)
        guard count > 0 else { return [] }
        return (1...count).compactMap { i in
            guard let id = ids.atIndex(i)?.stringValue else { return nil }
            return ChromeWindow(id: id, name: names.atIndex(i)?.stringValue ?? "")
        }
    }

    public func tabs(windowID: String) throws(ChromeError) -> WindowTabs {
        let result = try call("tablist", NSAppleEventDescriptor(string: windowID))
        var urls: [String] = []
        if let list = result.atIndex(1), list.numberOfItems > 0 {
            urls = (1...list.numberOfItems).map { list.atIndex($0)?.stringValue ?? "" }
        }
        let active = Int(result.atIndex(2)?.int32Value ?? 0)
        return WindowTabs(windowID: windowID, urls: urls, activeIndex: active)
    }

    /// Activates the tab, brings its window to the browser's front and activates the browser.
    /// The browser's own activate brings every one of its windows forward, but it is the
    /// activation that lands from another app on a signed build; AppKit's alone was refused
    /// there.
    public func focus(windowID: String, tabIndex: Int) throws(ChromeError) {
        _ = try call("focustab", NSAppleEventDescriptor(string: windowID), NSAppleEventDescriptor(int32: Int32(tabIndex)))
    }

    private func call(_ handler: String, _ parameters: NSAppleEventDescriptor...) throws(ChromeError) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: .currentProcess(),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setDescriptor(NSAppleEventDescriptor(string: handler), forKeyword: AEKeyword(keyASSubroutineName))
        let list = NSAppleEventDescriptor.list()
        for (i, parameter) in parameters.enumerated() {
            list.insert(parameter, at: i + 1)
        }
        event.setDescriptor(list, forKeyword: keyDirectObject)

        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if error != nil { throw Self.chromeError(error, browser: browser) }
        return result
    }

    private static func chromeError(_ info: NSDictionary?, browser: String) -> ChromeError {
        let code = (info?[NSAppleScript.errorNumber] as? Int) ?? 0
        let message = (info?[NSAppleScript.errorMessage] as? String) ?? "unknown error"
        switch code {
        case -1743: return .automationDenied(browser)   // errAEEventNotPermitted
        case -1728, -1719, -600: return .windowGone(browser)  // no such object, bad index, the browser quit
        case -10814: return .notInstalled(browser)             // kLSApplicationNotFoundErr
        default: return .script(browser, code: code, message: message)
        }
    }
}
