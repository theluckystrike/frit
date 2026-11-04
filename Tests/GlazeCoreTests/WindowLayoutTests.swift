import Foundation
import Testing
@testable import GlazeCore

/// G10: the default window fits the screen's visible frame, and the recipe table scrolls before the window grows.
@Suite("Window layout")
struct WindowLayoutTests {
    @Test("a big screen gets the preferred size")
    func bigScreen() {
        #expect(WindowLayout.defaultSize(visible: LayoutSize(width: 1512, height: 944)) == WindowLayout.preferred)
        #expect(WindowLayout.defaultSize(visible: nil) == WindowLayout.preferred)
    }

    @Test("1440 x 900 with the Dock (visible about 1440 x 800) fits")
    func laptopWithDock() {
        let visible = LayoutSize(width: 1440, height: 800)
        let size = WindowLayout.defaultSize(visible: visible)
        #expect(size.width <= visible.width && size.height <= visible.height)
        #expect(size == LayoutSize(width: 1320, height: 780))
    }

    @Test("a smaller visible frame caps the size")
    func smallScreen() {
        let size = WindowLayout.defaultSize(visible: LayoutSize(width: 1280, height: 700))
        #expect(size == LayoutSize(width: 1264, height: 692))
        // Never below the layout minimum.
        #expect(WindowLayout.defaultSize(visible: LayoutSize(width: 800, height: 500)) == WindowLayout.minimum)
    }

    @Test("G11: a 1024 x 768 screen (visible 1024 x 700) gets a window that fits it")
    func smallestScreen() {
        let visible = LayoutSize(width: 1024, height: 700)
        let size = WindowLayout.defaultSize(visible: visible)
        #expect(size == LayoutSize(width: 1008, height: 692))
        #expect(size.width <= visible.width && size.height <= visible.height)
        // The panes at their minimum widths fit inside that window, so the content does not widen it.
        #expect(WindowLayout.minimum.width <= size.width)
        #expect(WindowLayout.minimum.height <= size.height)
    }

    @Test("G11: the default width follows the visible width between the minimum and the preferred width")
    func widthFollowsScreen() {
        for w in stride(from: 1024.0, through: 1600.0, by: 16) {
            let size = WindowLayout.defaultSize(visible: LayoutSize(width: w, height: 900))
            #expect(size.width <= w - 2 * WindowLayout.margin || size.width == WindowLayout.minimum.width)
            #expect(size.width <= WindowLayout.preferred.width)
            #expect(size.width >= WindowLayout.minimum.width)
        }
    }

    @Test("G11: the chemistry pane takes about 40 % between its limits, and the recipe keeps its minimum")
    func chemistryPane() {
        // 1008-pt window, 220-pt sidebar: 788 pt for the recipe view.
        #expect(WindowLayout.chemistryWidth(detailWidth: 788) == WindowLayout.chemistryMinWidth)
        // 1320-pt window: 1100 pt -> 440.
        #expect(WindowLayout.chemistryWidth(detailWidth: 1100) == 440)
        // Wide windows stop at the maximum.
        #expect(WindowLayout.chemistryWidth(detailWidth: 2000) == WindowLayout.chemistryMaxWidth)
        for w in stride(from: 741.0, through: 2400, by: 7) {
            let c = WindowLayout.chemistryWidth(detailWidth: w)
            #expect(c >= WindowLayout.chemistryMinWidth && c <= WindowLayout.chemistryMaxWidth)
            #expect(w - 1 - c >= WindowLayout.recipeMinWidth)
        }
    }

    @Test("parse the QA size argument")
    func parse() {
        #expect(WindowLayout.parseSize("1440x800") == LayoutSize(width: 1440, height: 800))
        #expect(WindowLayout.parseSize("1440X800") == LayoutSize(width: 1440, height: 800))
        #expect(WindowLayout.parseSize("big") == nil)
        #expect(WindowLayout.parseSize(nil) == nil)
    }

    @Test("the table is as tall as its lines up to 8, and shrinks to 3 rows before the window grows")
    func table() {
        #expect(WindowLayout.tableIdealHeight(lines: 8) == WindowLayout.tableIdealHeight(lines: 12))
        #expect(WindowLayout.tableIdealHeight(lines: 1) == WindowLayout.tableIdealHeight(lines: 2))
        #expect(WindowLayout.tableIdealHeight(lines: 6) < WindowLayout.tableIdealHeight(lines: 8))
        #expect(WindowLayout.tableMinHeight(lines: 8) == WindowLayout.tableChrome + 3 * WindowLayout.tableRow)
        #expect(WindowLayout.tableMinHeight(lines: 2) == WindowLayout.tableIdealHeight(lines: 2))
        for n in 0...12 { #expect(WindowLayout.tableMinHeight(lines: n) <= WindowLayout.tableIdealHeight(lines: n)) }
    }
}

/// Run 1104 L2 BUG-1: on macOS 26.6.2 the Oxide Nudge and Replace Material sheets opened at their 780-pt minimum
/// width. The content needed 812 pt, so the title touched the left edge and the Stull chart was cut at the right.
@Suite("Oxide Nudge and Replace Material sheet size")
struct ReformulateSheetSizeTests {
    static let appSources: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/GlazeApp")

    @Test("the content's minimum width is the sum of its parts: 812 pt")
    func contentMinimum() {
        #expect(WindowLayout.reformulateSheetMinWidth == 16 + 400 + 20 + 360 + 16)
        // The sheet that L2 measured (780 pt) is too narrow for this content.
        #expect(WindowLayout.reformulateSheetMinWidth > 780)
    }

    @Test("1024 x 700, 1440 x 900 and larger visible frames: the sheet fits the content and the screen")
    func sizes() {
        let small = WindowLayout.reformulateSheetSize(visible: LayoutSize(width: 1024, height: 700))
        #expect(small == LayoutSize(width: 900, height: 640))
        // A 1440 x 900 screen: about 1440 x 875 visible without the Dock, 1440 x 800 with it.
        #expect(WindowLayout.reformulateSheetSize(visible: LayoutSize(width: 1440, height: 875)) == WindowLayout.reformulateSheetPreferred)
        #expect(WindowLayout.reformulateSheetSize(visible: LayoutSize(width: 1440, height: 800)) == WindowLayout.reformulateSheetPreferred)
        #expect(WindowLayout.reformulateSheetSize(visible: nil) == WindowLayout.reformulateSheetPreferred)
        for w in stride(from: 800.0, through: 2560, by: 16) {
            for h in stride(from: 600.0, through: 1440, by: 40) {
                let s = WindowLayout.reformulateSheetSize(visible: LayoutSize(width: w, height: h))
                #expect(s.width >= WindowLayout.reformulateSheetMinWidth, "\(w) x \(h)")
                #expect(s.width <= WindowLayout.reformulateSheetPreferred.width)
                #expect(s.height >= WindowLayout.reformulateSheetMinHeight && s.height <= WindowLayout.reformulateSheetPreferred.height)
                // A screen of 1024 pt or wider holds the sheet with the margins; a 700-pt-tall one holds it under the toolbar.
                if w >= 1024 { #expect(s.width <= w - 2 * WindowLayout.margin) }
                if h >= 700 { #expect(s.height + WindowLayout.sheetTopInset + WindowLayout.margin <= h) }
            }
        }
    }

    @Test("both sheets use the one fixed size and the shared column widths, not a minimum and an ideal width")
    func sheetsUseFixedSize() throws {
        let text = try String(contentsOf: Self.appSources.appendingPathComponent("ReformulateSheets.swift"), encoding: .utf8)
        #expect(!text.contains("idealWidth"))
        #expect(!text.contains("minWidth: 780"))
        #expect(text.components(separatedBy: ".frame(width: sheetSize.width, height: sheetSize.height)").count - 1 == 2)
        #expect(text.components(separatedBy: ".padding(WindowLayout.sheetPadding)").count - 1 == 2)
        #expect(text.contains(".frame(minWidth: WindowLayout.reformulateListMinWidth)"))
        #expect(text.contains("maxWidth: WindowLayout.reformulateChartMaxWidth"))
        #expect(text.contains("spacing: WindowLayout.reformulateColumnSpacing"))
    }
}
