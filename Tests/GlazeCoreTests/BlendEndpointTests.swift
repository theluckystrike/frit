import Foundation
import Testing
@testable import GlazeCore

/// W6 F2 finding 5: every blend endpoint needs a finite base total above 0.
@Suite("Blend endpoints")
struct BlendEndpointTests {
    private let good = recipe("Good", [("silica", 40), ("kaolin", 30), ("whiting", 30)])
    private let empty = recipe("Empty", [])
    private let additionsOnly = recipe("Stain", [], additions: [("red-iron-oxide", 5)])

    @Test func emptyEndpointGivesNoTilesAndAMessage() {
        #expect(Blend.line(good, empty, steps: 5).isEmpty)
        #expect(Blend.endpointProblem(empty)?.contains("Empty") == true)
        #expect(Blend.endpointProblem(empty)?.contains("no base materials") == true)
    }

    @Test func additionsOnlyEndpointIsRefusedInEveryGenerator() {
        #expect(Blend.line(additionsOnly, good, steps: 3).isEmpty)
        #expect(Blend.triaxial(good, good, additionsOnly, divisions: 4).isEmpty)
        #expect(Blend.grid(corners: [good, good, good, additionsOnly], rows: 3, columns: 3).isEmpty)
        #expect(Blend.problem(endpoints: [good, additionsOnly]) == Blend.endpointProblem(additionsOnly))
    }

    @Test func steps1StillChecksBothEndpoints() {
        #expect(Blend.line(good, empty, steps: 1).isEmpty)
    }

    @Test func validEndpointsHaveNoProblem() {
        #expect(Blend.endpointProblem(good) == nil)
        #expect(Blend.problem(endpoints: [good, good, good, good]) == nil)
        #expect(Blend.line(good, good, steps: 4).count == 4)
    }

    @Test func overflowingBaseIsRefused() {
        let huge = recipe("Huge", [("silica", 1e308), ("kaolin", 1e308)])
        #expect(Blend.endpointProblem(huge)?.contains("too large") == true)
        #expect(Blend.line(good, huge, steps: 3).isEmpty)
    }

    @Test func tinyBaseBlendsToFiniteTiles() throws {
        let tiny = recipe("Tiny", [("silica", 1e-310), ("kaolin", 1e-310)])
        let tiles = Blend.line(tiny, good, steps: 3)
        #expect(tiles.count == 3)
        for t in tiles {
            #expect(t.lines.allSatisfy { $0.amount.isFinite })
            #expect(abs(t.baseTotal - 100) < 1e-9)
        }
    }

    @Test func tinyBaseWithLargeAdditionIsRefused() {
        let r = recipe("Speck", [("silica", 1e-310)], additions: [("red-iron-oxide", 1)])
        #expect(Blend.endpointProblem(r)?.contains("additions too large") == true)
        #expect(Blend.line(r, good, steps: 3).isEmpty)
    }
}
