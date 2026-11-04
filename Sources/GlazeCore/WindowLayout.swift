import Foundation

/// A width and a height in points. GlazeCore does not use CGSize: with the Command Line Tools
/// toolchain, cross-module optimisation of a CGSize function in this module crashed the compiler.
public struct LayoutSize: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// Size rules for the book window. Pure numbers, so that they can be tested without a screen.
/// The app passes the main screen's visible frame (the part of the screen that windows can use).
public enum WindowLayout {
    /// The window size when the screen has room for it.
    public static let preferred = LayoutSize(width: 1320, height: 780)
    /// Space kept free between the window and the edges of the visible frame.
    public static let margin: Double = 8

    // MARK: Pane widths (G11)
    // The smallest screen the layout is made for has a visible frame of 1024 x 700. The sum of the pane minimums
    // (plus the dividers) must fit that frame less the margins, so that the window is never wider than the screen.

    /// The sidebar with the recipe list.
    public static let sidebarMinWidth: Double = 200
    /// The recipe table and the Stull chart.
    public static let recipeMinWidth: Double = 400
    /// The chemistry panel. It can also be hidden (View > Hide Chemistry), which gives the recipe the full width.
    public static let chemistryMinWidth: Double = 340
    /// The recipe view's shortest height: header, 3 table rows, totals and the Stull chart at its minimum.
    public static let recipeMinHeight: Double = 548
    /// The chemistry panel grows up to this width; the recipe pane takes the rest.
    public static let chemistryMaxWidth: Double = 480
    /// The chemistry pane's width for a given width of the recipe view (recipe + divider + chemistry):
    /// about 40 % of it, at least `chemistryMinWidth`, at most `chemistryMaxWidth`, and never so wide that
    /// the recipe pane drops below `recipeMinWidth` (unless the whole view is narrower than both minimums).
    public static func chemistryWidth(detailWidth: Double) -> Double {
        let share = (detailWidth * 0.4).rounded()
        let roomLeft = detailWidth - 1 - recipeMinWidth
        return max(chemistryMinWidth, min(chemistryMaxWidth, share, roomLeft))
    }

    /// Dividers and borders between the panes.
    public static let paneChrome: Double = 4

    /// The smallest window: every pane at its minimum width, and the shortest height the recipe view is made for.
    public static var minimum: LayoutSize {
        LayoutSize(width: sidebarMinWidth + recipeMinWidth + chemistryMinWidth + paneChrome, height: 652)
    }

    /// The default window size: the preferred size, capped to the visible frame less the margins.
    /// A 1440 x 900 screen with the Dock showing has a visible frame of about 1440 x 800, so the window
    /// opens at 1320 x 780 there; a 1024 x 768 screen (visible about 1024 x 700) gets 1008 x 692.
    /// The size never goes below `minimum` (the content cannot be smaller than that).
    public static func defaultSize(visible: LayoutSize?) -> LayoutSize {
        guard let visible, visible.width > 0, visible.height > 0 else { return preferred }
        let width = min(preferred.width, max(minimum.width, visible.width - 2 * margin))
        let height = min(preferred.height, max(minimum.height, visible.height - margin))
        return LayoutSize(width: width, height: height)
    }

    /// Parses "WIDTHxHEIGHT" (for example "1440x800"). Used only by the debug build's QA launch argument
    /// `-FritQAVisibleSize`, which stands in for a smaller screen. The release build has no such argument.
    public static func parseSize(_ text: String?) -> LayoutSize? {
        guard let parts = text?.lowercased().split(separator: "x"), parts.count == 2,
              let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else { return nil }
        return LayoutSize(width: w, height: h)
    }

    // MARK: Oxide Nudge and Replace Material sheets (run 1104 L2 BUG-1)
    // On macOS 26.6.2 these sheets opened at their minimum width (780 pt), not at their ideal width (860 pt).
    // The content needed 812 pt (16 + 400 + 20 + 360 + 16), so it was 32 pt too wide: the title touched the left
    // edge and the Stull chart was cut at the right. The sheets now have one fixed size that the content fits.

    /// The padding around the sheet content (the macOS value of SwiftUI `.padding()`).
    public static let sheetPadding: Double = 16
    /// The status, materials and oxide tables of a sheet. They scroll inside themselves.
    public static let reformulateListMinWidth: Double = 400
    /// The Stull chart of a sheet.
    public static let reformulateChartMinWidth: Double = 300
    public static let reformulateChartMaxWidth: Double = 360
    /// The space between the tables and the chart.
    public static let reformulateColumnSpacing: Double = 20
    /// The narrowest sheet that holds the tables at their minimum and the chart at its maximum width.
    public static var reformulateSheetMinWidth: Double {
        2 * sheetPadding + reformulateListMinWidth + reformulateColumnSpacing + reformulateChartMaxWidth
    }
    /// The sheet size when the screen has room for it. 900 pt gives a material name such as "Generic calcium
    /// borate frit (theoretical)" room in the materials table; 740 pt shows every row of the tables for the
    /// sample recipe (in a 680-pt sheet the oxide table was cut at SiO2).
    public static let reformulateSheetPreferred = LayoutSize(width: 900, height: 740)
    /// The shortest sheet. The tables scroll inside it.
    public static let reformulateSheetMinHeight: Double = 560
    /// The window's title bar and toolbar, above the top of a sheet.
    public static let sheetTopInset: Double = 52

    /// The size of the Oxide Nudge and Replace Material sheets for a screen's visible frame: the preferred size,
    /// made smaller to fit the screen, but never narrower than the content (`reformulateSheetMinWidth`).
    /// A 1024 x 700 visible frame gives 900 x 640; a 1440 x 900 screen gives 900 x 740.
    public static func reformulateSheetSize(visible: LayoutSize?) -> LayoutSize {
        let preferred = reformulateSheetPreferred
        guard let visible, visible.width > 0, visible.height > 0 else { return preferred }
        let width = min(preferred.width, max(reformulateSheetMinWidth, visible.width - 2 * margin))
        let height = min(preferred.height, max(reformulateSheetMinHeight, visible.height - sheetTopInset - margin))
        return LayoutSize(width: width, height: height)
    }

    // MARK: Recipe table

    /// Height of the table header plus its insets.
    public static let tableChrome: Double = 42
    /// Height of one table row.
    public static let tableRow: Double = 24.5
    /// The table never shows fewer rows than this; with more lines it scrolls.
    public static let tableMinRows = 3
    /// The table grows up to this many rows when the window has room; with more lines it scrolls.
    public static let tableMaxRows = 8

    /// The height that shows `lines` rows (at least 2, at most `tableMaxRows`), so there are no empty rows.
    public static func tableIdealHeight(lines: Int) -> Double {
        tableChrome + Double(min(max(lines, 2), tableMaxRows)) * tableRow
    }

    /// The smallest height the table takes before it scrolls inside itself (the window does not grow for it).
    public static func tableMinHeight(lines: Int) -> Double {
        tableChrome + Double(min(max(lines, 2), tableMinRows)) * tableRow
    }
}
