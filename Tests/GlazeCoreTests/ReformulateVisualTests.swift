import Foundation
import Testing
@testable import GlazeCore

/// Fixes from the L10 offscreen renders of the recipe window and the Oxide Nudge and Replace Material sheets.
@Suite("Reformulate visual check fixes (L10)")
struct ReformulateVisualTests {
    private func sample() throws -> Recipe {
        try #require(SampleBook.make().recipes.first { $0.name == "Tidewater Feldspar Gloss" })
    }

    @Test("the Tidewater note fits the 3-line notes field of a 1024-pt window")
    func tidewaterNoteFits() throws {
        let notes = try sample().notes
        // The L10 render at a recipe pane of 804 pt (1024-pt window, 220-pt sidebar) fits about 62 characters
        // per line; the old 365-character note was cut after "so that one oxide".
        #expect(notes.count <= 180, "\(notes.count) characters")
        #expect(notes.contains("Recipe > Oxide Nudge"))
        #expect(notes.contains("Recipe > Replace Material"))
        #expect(notes.contains("Untested starting point."))
    }

    @Test("the sheets mention a dashed line only when the two points are apart on the chart")
    func comparisonLineVisible() throws {
        // The sample's SiO2 +0.05 nudge: both points sit under the diamond.
        #expect(!Stull.pointsApart(siO2: 3.650, al2O3: 0.371, siO2: 3.700, al2O3: 0.371))
        // Potash to Soda feldspar on the sample: SiO2 and Al2O3 do not change.
        #expect(!Stull.pointsApart(siO2: 3.650, al2O3: 0.371, siO2: 3.650, al2O3: 0.371))
        // An Al2O3 +0.05 nudge, and a SiO2 +0.5 nudge, show a line.
        #expect(Stull.pointsApart(siO2: 3.650, al2O3: 0.371, siO2: 3.650, al2O3: 0.421))
        #expect(Stull.pointsApart(siO2: 3.650, al2O3: 0.371, siO2: 4.150, al2O3: 0.371))
    }
}
