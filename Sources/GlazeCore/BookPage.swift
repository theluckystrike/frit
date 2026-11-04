import Foundation

/// The pages of a book window's sidebar, in sidebar order, for the View menu (W5 V2).
/// Every page must be reachable from the menu bar and the keyboard, not only by a click in the sidebar
/// (HIG, Menus and Keyboard). Before this, the Tests and Materials pages had no menu item and no shortcut.
public enum BookPage: String, CaseIterable, Sendable {
    case recipes
    case tests
    case materials

    /// The View menu item. Same words as the sidebar.
    public var menuTitle: String {
        switch self {
        case .recipes: return "Recipes"
        case .tests: return "Tests"
        case .materials: return "Materials"
        }
    }

    /// The key of the Command shortcut: Command-1, Command-2, Command-3, in sidebar order.
    public var shortcutKey: Character {
        Character(String((BookPage.allCases.firstIndex(of: self) ?? 0) + 1))
    }
}
