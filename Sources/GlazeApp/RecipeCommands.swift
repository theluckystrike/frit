import SwiftUI
import AppKit
import GlazeCore

/// Actions of the front book window, for the Recipe menu. Set by the window with `focusedSceneValue`.
struct BookActions {
    var addRecipe: () -> Void
    /// Nil when no recipe is selected.
    var selected: SelectedRecipeActions?
    /// Shows a sidebar page: View > Recipes, Tests, Materials (W5 V2).
    var showPage: (BookPage) -> Void
    /// Tests menu (F3). Nil when the command cannot run: Add Test needs a recipe, Print Labels needs a tile.
    var addTest: (() -> Void)?
    var findTest: () -> Void
    var printLabels: (() -> Void)?
}

struct SelectedRecipeActions {
    var rename: () -> Void
    var duplicate: () -> Void
    var delete: () -> Void
}

/// Actions of the recipe shown in the front window.
struct RecipeActions {
    var addMaterial: () -> Void
    var blend: (BlendMode) -> Void
    var batchSheet: () -> Void
    /// Prints the batch sheet with the batch weight and precision last used in the Batch Sheet.
    var printBatchSheet: () -> Void
    /// Opens Oxide Nudge: change the amounts so that one oxide reaches a target UMF.
    var nudge: () -> Void
    /// Opens Replace Material: put another material in place of a base material and solve the new amounts.
    var replaceMaterial: () -> Void
}

/// Identifiers of the customizable toolbar and its items (I6 C14). Keep them stable: macOS saves the
/// user's toolbar arrangement under them.
enum ToolbarIDs {
    static let book = "frit.book.toolbar"
    static let addRecipe = "addRecipe"
    static let blend = "blend"
    static let batchSheet = "batchSheet"
    static let chemistry = "chemistry"
    /// The three tools that other glaze apps do not have (run 1104 L10 change 4). Icon only, so that the toolbar
    /// fits a 1024-pt window (ToolbarFamilyTests has the width budget).
    static let replaceMaterial = "replaceMaterial"
    static let oxideNudge = "oxideNudge"
    static let findTest = "findTest"
}

struct BookActionsKey: FocusedValueKey { typealias Value = BookActions }
struct RecipeActionsKey: FocusedValueKey { typealias Value = RecipeActions }

extension FocusedValues {
    var bookActions: BookActions? {
        get { self[BookActionsKey.self] }
        set { self[BookActionsKey.self] = newValue }
    }
    var recipeActions: RecipeActions? {
        get { self[RecipeActionsKey.self] }
        set { self[RecipeActionsKey.self] = newValue }
    }
}

/// The Recipe menu: every recipe action of the toolbar and the context menus, with its keyboard shortcut,
/// so that each can be found in the menus and used from the keyboard (G11).
struct RecipeCommands: Commands {
    @FocusedValue(\.bookActions) private var book
    @FocusedValue(\.recipeActions) private var recipe

    var body: some Commands {
        CommandMenu("Recipe") {
            Button("Add Recipe") { book?.addRecipe() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(book == nil)
            // "Rename Recipe…", because File > Rename… renames the book (I6 C7).
            Button("Rename Recipe…") { book?.selected?.rename() }
                .disabled(book?.selected == nil)
            Button("Duplicate Recipe") { book?.selected?.duplicate() }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(book?.selected == nil)
            Button("Delete Recipe…") { book?.selected?.delete() }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(book?.selected == nil)
            Divider()
            Button("Add Material") { recipe?.addMaterial() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(recipe == nil)
            Divider()
            Button("Oxide Nudge…") { recipe?.nudge() }
                .disabled(recipe == nil)
            Button("Replace Material…") { recipe?.replaceMaterial() }
                .disabled(recipe == nil)
            Divider()
            Button("Line Blend…") { recipe?.blend(.line) }
                .disabled(recipe == nil)
            Button("Triaxial Blend…") { recipe?.blend(.triaxial) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(recipe == nil)
            Button("Four-Corner Grid…") { recipe?.blend(.grid) }
                .disabled(recipe == nil)
            Divider()
            Button("Batch Sheet…") { recipe?.batchSheet() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(recipe == nil)
        }
    }
}

/// The Tests menu (F3): add a tile, find a tile by code or text, and print tile labels. Each is also on the
/// Tests page, so that every feature has a menu path (HIG) and nothing is hidden (Guideline 2.5.19).
struct TestsCommands: Commands {
    @FocusedValue(\.bookActions) private var book

    var body: some Commands {
        CommandMenu("Tests") {
            Button("Add Test") { book?.addTest?() }
                .disabled(book?.addTest == nil)
            Button("Find Test…") { book?.findTest() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(book == nil)
            Divider()
            Button("Print Labels…") { book?.printLabels?() }
                .disabled(book?.printLabels == nil)
        }
    }
}

/// View > Recipes (Command-1), Tests (Command-2) and Materials (Command-3): each sidebar page from the menu
/// bar and the keyboard (W5 V2, HIG). Before this, the Tests and Materials pages needed a click.
struct PageCommands: Commands {
    @FocusedValue(\.bookActions) private var book

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(BookPage.allCases, id: \.self) { page in
                Button(page.menuTitle) { book?.showPage(page) }
                    .keyboardShortcut(KeyEquivalent(page.shortcutKey), modifiers: [.command])
                    .disabled(book == nil)
            }
        }
    }
}

/// File > Print… (Command-P): prints the batch sheet of the recipe in the front window (I6 C7).
struct PrintCommands: Commands {
    @FocusedValue(\.recipeActions) private var recipe

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            // Page Setup… sets the paper size and orientation of NSPrintInfo.shared, which the batch sheet
            // prints with (W6 X4: replacing .printItem had removed it from the File menu).
            Button("Page Setup…") { NSApp.runPageLayout(nil) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Print Batch Sheet…") { recipe?.printBatchSheet() }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(recipe == nil)
        }
    }
}
