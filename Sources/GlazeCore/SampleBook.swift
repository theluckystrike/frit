import Foundation

/// Six original cone 6 base recipes and three sample test tiles for Help > Open Sample Book. The app and the tests use this one list.
/// The first recipe is there to try Oxide Nudge and Replace Material on (`Reformulate`); the book opens on it.
/// The names are our own. Amounts are plain starting points for testing, not proven glazes.
/// Names do not claim a Stull region that the chart does not show: where the surface comes from
/// magnesium or titanium (which the Stull chart does not model), the notes say so.
public enum SampleBook {
    public struct Entry: Sendable {
        public let name: String
        public let notes: String
        public let base: [(String, Double)]
        public let additions: [(String, Double)]
    }

    /// Every sample is inside the default reference set (Hesselberth & Roy, cone 6) for every oxide it lists,
    /// with additions off and on (tested). Amounts were fitted to those ranges with small changes from the first
    /// drafts, then reviewed for plausibility (see G9-REPORT.md).
    public static let entries: [Entry] = [
        Entry(name: "Tidewater Feldspar Gloss",
              // Short, so that the whole note shows in the 3-line notes field of a 1024-pt window (L10 render).
              notes: "A potash feldspar gloss base. Untested starting point. Try Recipe > Oxide Nudge and Recipe > Replace Material on it.",
              base: [("potash-feldspar", 28), ("frit-generic-calcium-borate", 20), ("whiting", 6), ("wollastonite", 5),
                     ("talc", 6), ("kaolin", 14), ("silica", 21)],
              additions: []),
        Entry(name: "Millpond Clear",
              notes: "A glossy clear base. Calcium borate frit with soda feldspar and a little talc.",
              base: [("frit-generic-calcium-borate", 24), ("soda-feldspar", 18), ("potash-feldspar", 5), ("talc", 8),
                     ("wollastonite", 8), ("whiting", 3), ("kaolin", 16), ("silica", 18)],
              additions: []),
        Entry(name: "Ashfield Dolomite Satin",
              notes: "A dolomite satin base. The satin surface comes from magnesium as the glaze cools, which the Stull chart does not show, so it plots in the gloss area. More silica moves it toward gloss.",
              base: [("dolomite", 15), ("potash-feldspar", 28), ("whiting", 5),
                     ("kaolin", 18), ("silica", 19), ("frit-generic-calcium-borate", 15)],
              additions: []),
        Entry(name: "Larkspur Gloss",
              notes: "A soda borosilicate frit gloss base with dolomite, for colorant tests.",
              base: [("frit-generic-soda-borosilicate", 31), ("potash-feldspar", 18), ("dolomite", 11),
                     ("wollastonite", 10), ("kaolin", 12), ("silica", 18)],
              additions: []),
        Entry(name: "Quarry Stone",
              notes: "A stony base with talc and a titanium addition for a broken surface. The surface comes from magnesium and titanium, which the Stull chart does not show, so it plots in the gloss area. Part of the kaolin is calcined to reduce crawling.",
              base: [("soda-feldspar", 28), ("whiting", 14), ("talc", 10), ("kaolin", 12), ("calcined-kaolin", 6),
                     ("silica", 14), ("frit-generic-calcium-borate", 16)],
              additions: [("titanium-dioxide", 4)]),
        Entry(name: "Ember Strontium Gloss",
              notes: "A strontium gloss base with an iron addition. The melt is fluid, so test it on a vertical tile first.",
              base: [("strontium-carbonate", 8), ("potash-feldspar", 35), ("frit-generic-calcium-borate", 18),
                     ("wollastonite", 14), ("kaolin", 11), ("silica", 14)],
              additions: [("red-iron-oxide", 3)]),
    ]

    /// The note at the foot of the sample book's sidebar. It shows each time the sample opens (first launch and
    /// Help > Open Sample Book) and names the three tools that other glaze apps do not have, so that a new user
    /// finds them in the first minutes (run 1104 L10 change 2). Whiting to Wollastonite on the first recipe
    /// matches every oxide (tested in ReformulateTests).
    public static func guideNote(appName: String) -> String {
        "Try three tools on this sample. Recipe > Replace Material: replace Whiting with Wollastonite, and \(appName) works out new amounts. Recipe > Oxide Nudge: move one oxide to a target. Tests > Find Test: find a tile by the code on its back. Each has a toolbar button. File > New starts your own book. Help > Open Sample Book opens this sample again."
    }

    public static func recipe(_ e: Entry) -> Recipe {
        let lines = e.base.map { RecipeLine(materialID: $0.0, amount: $0.1, isAddition: false) }
            + e.additions.map { RecipeLine(materialID: $0.0, amount: $0.1, isAddition: true) }
        return Recipe(name: e.name, cone: "6", lines: lines,
                      notes: "Sample recipe. \(e.notes) Test every recipe on tiles before use.")
    }

    /// A sample test tile: the index of its recipe in `entries`, a 3-segment schedule (rate °C/h, target °C,
    /// hold min), the day it was fired, and a note. The notes say "Sample entry" so nobody takes them for results.
    public struct TileEntry: Sendable {
        public let recipeIndex: Int
        public let schedule: [(Double, Double, Double)]
        public let fired: (year: Int, month: Int, day: Int)
        public let notes: String
    }

    /// Three sample tiles, so the Tests page and its firing ramp chart have content in the sample book (I6 C3).
    /// `make()` gives them the tile codes T-001, T-002 and T-003 (F3).
    public static let tileEntries: [TileEntry] = [
        TileEntry(recipeIndex: 1, schedule: [(150, 600, 0), (220, 1100, 0), (60, 1220, 10)], fired: (2026, 9, 14),
                  notes: "Sample entry. Glossy and clear on white stoneware. A few pinholes inside the rim, so the next firing gets a longer hold. T-001 is written on the back in iron oxide."),
        TileEntry(recipeIndex: 2, schedule: [(150, 600, 0), (220, 1100, 0), (60, 1222, 15)], fired: (2026, 9, 21),
                  notes: "Sample entry. Satin where it is thick and glossier where it is thin. Fired with a 15 minute hold at the top."),
        TileEntry(recipeIndex: 5, schedule: [(120, 600, 0), (200, 1100, 0), (50, 1215, 20)], fired: (2026, 10, 5),
                  notes: "Sample entry. Amber where thin and dark brown where it pools. It ran about 3 mm down the vertical tile."),
    ]

    public static func make() -> GlazeBook {
        let recipes = entries.map(recipe)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let tests = tileEntries.map { t in
            TestTile(
                recipeID: recipes[t.recipeIndex].id, cone: "6", atmosphere: "Oxidation",
                schedule: t.schedule.map { FiringSegment(ratePerHour: $0.0, targetC: $0.1, holdMinutes: $0.2) },
                notes: t.notes, photoBookmark: nil,
                date: calendar.date(from: DateComponents(year: t.fired.year, month: t.fired.month, day: t.fired.day, hour: 12))!
            )
        }
        // Codes T-001 to T-003 in this order, so the Tests page shows tile codes and labels (F3).
        var book = GlazeBook(recipes: recipes, customMaterials: [], tests: tests, version: 1)
        TileCode.backfill(&book)
        return book
    }
}
