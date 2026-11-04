import Foundation
import Testing
@testable import GlazeCore

@Suite("View menu pages")
struct BookPageTests {
    @Test func everySidebarPageHasAMenuItemAndADigitShortcut() {
        // Sidebar order: the Recipes section, then Tests and Materials in the Book section.
        #expect(BookPage.allCases == [.recipes, .tests, .materials])
        #expect(BookPage.allCases.map(\.menuTitle) == ["Recipes", "Tests", "Materials"])
        #expect(BookPage.allCases.map(\.shortcutKey) == ["1", "2", "3"])
        #expect(Set(BookPage.allCases.map(\.shortcutKey)).count == BookPage.allCases.count)
    }
}
