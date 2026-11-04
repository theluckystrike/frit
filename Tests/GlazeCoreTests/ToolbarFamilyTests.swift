import Foundation
import Testing
import GlazeCore

/// Source guard for the toolbar crash found in W5 V5 (375ea86, macOS 26.6.2, arm64 and x86_64 under Rosetta).
///
/// All Frit windows share one NSToolbar identifier, so AppKit keeps their toolbars in one family. When a view
/// that comes and goes (RecipeDetailView) added customizable toolbar items, SwiftUI inserted them after the
/// window opened, AppKit inserted them into the other windows' toolbars too, and a window that already had the
/// item raised NSInternalInconsistencyException ("NSToolbar already contains an item with the identifier
/// blend"). Repro: open a book on a recipe, then Help > Open Sample Book.
///
/// The app target cannot be imported by the tests, so this suite reads the app sources: customizable toolbar
/// content must be declared only in BookWindow.swift, on views that live as long as the window.
@Suite("Toolbar family")
struct ToolbarFamilyTests {
    static let appSources: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/GlazeApp")

    static func swiftFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: appSources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
    }

    @Test func customizableToolbarOnlyInBookWindow() throws {
        let files = try Self.swiftFiles()
        #expect(files.count > 5, "app sources not found at \(Self.appSources.path)")
        for file in files where file.lastPathComponent != "BookWindow.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains(".toolbar(id:"), "\(file.lastPathComponent) declares a customizable toolbar")
            #expect(!text.contains("ToolbarItem(id:"), "\(file.lastPathComponent) declares a customizable toolbar item")
        }
    }

    @Test func recipeItemsAreDeclaredOnce() throws {
        let text = try String(contentsOf: Self.appSources.appendingPathComponent("BookWindow.swift"), encoding: .utf8)
        for id in ["ToolbarIDs.addRecipe", "ToolbarIDs.blend", "ToolbarIDs.batchSheet", "ToolbarIDs.chemistry",
                   "ToolbarIDs.replaceMaterial", "ToolbarIDs.oxideNudge", "ToolbarIDs.findTest"] {
            #expect(text.components(separatedBy: "ToolbarItem(id: \(id)").count - 1 == 1, "\(id) must be declared once")
        }
    }

    /// The items of `recipeToolbar` in BookWindow.swift, in order: the id, the title of its Label, whether it
    /// shows the title (`.labelStyle(.titleAndIcon)`), and whether it is a menu (a chevron after the title).
    struct Item: Equatable {
        var id: String
        var title: String
        var titled: Bool
        var menu: Bool
    }

    static func recipeToolbarItems() throws -> [Item] {
        let text = try String(contentsOf: appSources.appendingPathComponent("BookWindow.swift"), encoding: .utf8)
        let start = try #require(text.range(of: "private var recipeToolbar: some CustomizableToolbarContent {"))
        let end = try #require(text.range(of: "private func stullRegion", range: start.upperBound..<text.endIndex))
        let block = String(text[start.upperBound..<end.lowerBound])
        return block.components(separatedBy: "ToolbarItem(id: ToolbarIDs.").dropFirst().map { (chunk: String) -> Item in
            let id = String(chunk.prefix { $0.isLetter })
            var title = ""
            if let label = chunk.range(of: "Label(") {
                let rest = chunk[label.upperBound...]
                if let q1 = rest.firstIndex(of: "\""), let q2 = rest[rest.index(after: q1)...].firstIndex(of: "\"") {
                    title = String(rest[rest.index(after: q1)..<q2])
                }
            }
            return Item(id: id, title: title, titled: chunk.contains(".labelStyle(.titleAndIcon)"),
                        menu: chunk.contains("Menu {"))
        }
    }

    @Test("run 1104: Replace Material, Oxide Nudge and Find Test are in the toolbar, first, with their actions")
    func differentiatorItems() throws {
        let items = try Self.recipeToolbarItems()
        #expect(items.map(\.id) == ["replaceMaterial", "oxideNudge", "findTest", "blend", "batchSheet", "chemistry"])
        #expect(items.prefix(3).map(\.title) == ["Replace Material", "Oxide Nudge", "Find Test"])
        let text = try String(contentsOf: Self.appSources.appendingPathComponent("BookWindow.swift"), encoding: .utf8)
        // The same actions as Recipe > Replace Material…, Recipe > Oxide Nudge… and Tests > Find Test….
        #expect(text.contains("Button { model.replace = ReplaceRequest(materialID: nil) }"))
        #expect(text.contains("Button { model.nudge = .fromMenu }"))
        #expect(text.contains("Button { findTest() }"))
        let detail = try String(contentsOf: Self.appSources.appendingPathComponent("RecipeDetailView.swift"), encoding: .utf8)
        #expect(detail.contains("nudge: { model.nudge = .fromMenu }"))
        #expect(detail.contains("replaceMaterial: { model.replace = ReplaceRequest(materialID: nil) }"))
    }

    /// Width budget for the toolbar of a 1024-pt screen (run 1104). An item that does not fit goes behind an
    /// overflow chevron (I6 C1). The widths are measured in a real window on macOS 26.6.2 at 1320 pt
    /// (~/barframe-approval-work/run-20261104/L2/qa/raw/05-recipe-edit.png, 2x): the Blend capsule is 82.5 pt,
    /// Batch Sheet 121 pt, the icon-only Chemistry item 33 pt, the space between capsules 13 pt, the space after
    /// the last item 16 pt. The sidebar column ends at 226 pt and the title starts 21 pt after it. The subtitle
    /// "Tidewater Feldspar Gloss · Cone 6 — Edited" is 230 pt wide (5.48 pt a character).
    /// A titled item is 7.3 pt a character plus 41 pt (icon and capsule), plus 5 pt for a menu chevron; this gives
    /// Batch Sheet 121.3 and Blend 82.5. An estimate for other titles, not a measurement.
    @Test("run 1104: at a 1024-pt screen the toolbar items fit beside the title, with 24 pt to spare")
    func widthBudget() throws {
        let items = try Self.recipeToolbarItems()
        func width(_ item: Item) -> Double {
            item.titled ? 7.3 * Double(item.title.count) + 41 + (item.menu ? 5 : 0) : 33
        }
        // Every item in a capsule of its own: the widest case.
        let itemsWidth = items.map(width).reduce(0, +) + 13 * Double(max(0, items.count - 1)) + 16
        let window = WindowLayout.defaultSize(visible: LayoutSize(width: 1024, height: 700)).width
        #expect(window == 1008)
        // The longest subtitle of the sample book, with " — Edited".
        let longestName = SampleBook.entries.map(\.name.count).max() ?? 0
        let subtitle = 5.48 * Double(longestName + " · Cone 6 — Edited".count)
        let room = window - 226 - 21 - subtitle
        #expect(itemsWidth + 24 <= room, "items \(itemsWidth) pt, room \(room) pt")
        // With their titles, the three new items would not fit (this is why they show an icon only).
        let titled = items.map { item in
            ["replaceMaterial", "oxideNudge", "findTest"].contains(item.id) ? Item(id: item.id, title: item.title, titled: true, menu: false) : item
        }
        let titledWidth = titled.map(width).reduce(0, +) + 13 * Double(max(0, items.count - 1)) + 16
        #expect(titledWidth > room, "titled \(titledWidth) pt, room \(room) pt")
        print("TOOLBAR-BUDGET window=\(window) room=\(room) items=\(itemsWidth) titled=\(titledWidth)")
    }
}
