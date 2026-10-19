// How Accessibility's statuses become the errors people read: a refused permission is a
// refused permission whichever step met it, a window that went away is said so, and any
// other status names the step that failed, each naming the browser. No browser needed.

import ApplicationServices
import CapsJumpCore
import Testing
@testable import CapsJumpChrome

@MainActor
@Suite struct ChromeAccessibilityTests {
    @Test func aRefusedPermissionIsTheSameForEveryStep() {
        #expect(ChromeAccessibility.failure(.apiDisabled, during: .read, browser: .chrome) == .accessibilityDenied)
        #expect(ChromeAccessibility.failure(.apiDisabled, during: .raise, browser: .brave) == .accessibilityDenied)
    }

    @Test func aWindowThatWentAwayIsWindowGone() {
        #expect(ChromeAccessibility.failure(.invalidUIElement, during: .read, browser: .chrome) == .windowGone("Google Chrome"))
        #expect(ChromeAccessibility.failure(.invalidUIElement, during: .raise, browser: .brave) == .windowGone("Brave"))
    }

    @Test func anyOtherStatusNamesTheStep() {
        #expect(ChromeAccessibility.failure(.cannotComplete, during: .read, browser: .chrome) == .accessibility("Google Chrome", code: AXError.cannotComplete.rawValue))
        #expect(ChromeAccessibility.failure(.cannotComplete, during: .raise, browser: .chrome) == .raise("Google Chrome", code: AXError.cannotComplete.rawValue))
        #expect(ChromeError.raise("Brave", code: -25204).description == "Accessibility could not bring Brave's window forward (error -25204)")
    }

    @Test func notInFrontNamesTheAppNeverAPage() {
        #expect(ChromeError.notInFront("Brave", .otherApp("iTerm2")).description == "the window didn't come to the front; iTerm2 stayed in front")
        #expect(ChromeError.notInFront("Brave", .otherApp(nil)).description == "the window didn't come to the front; another app stayed in front")
        #expect(ChromeError.notInFront("Brave", .otherWindow).description == "Brave kept another of its windows in front")
    }
}
