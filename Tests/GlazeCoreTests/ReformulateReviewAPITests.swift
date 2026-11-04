import Foundation
import Testing
@testable import GlazeCore

/// Review fixes (L7) that need API added in the fix: which arrows show, what the sheets say.
@Suite("Reformulate review fixes, new API (L7)")
struct ReformulateReviewAPITests {
    private func sample() throws -> Recipe {
        try #require(SampleBook.make().recipes.first { $0.name == "Tidewater Feldspar Gloss" })
    }

    @Test("C4: no Nudge arrows while the chemistry pane includes additions")
    func arrowsHiddenWithAdditions() throws {
        let r = try sample()
        let c = try chem(r)
        #expect(Reformulate.canNudge(.SiO2, chemistry: c, includeAdditions: false))
        #expect(Reformulate.canNudge(.CaO, chemistry: c, includeAdditions: false))
        for o in Oxide.allCases { #expect(!Reformulate.canNudge(o, chemistry: c, includeAdditions: true)) }
    }

    @Test("C5: no flux arrows on the only flux; its error says why")
    func soleFluxArrows() throws {
        let r = recipe("One flux", [("whiting", 20), ("kaolin", 30), ("silica", 50)])
        let c = try chem(r)
        #expect(!Reformulate.canNudge(.CaO, chemistry: c, includeAdditions: false))
        #expect(Reformulate.canNudge(.SiO2, chemistry: c, includeAdditions: false))
        #expect(Reformulate.canNudge(.Al2O3, chemistry: c, includeAdditions: false))
        #expect(throws: ReformulateError.onlyFlux(.CaO)) {
            try Reformulate.nudge(r, oxide: .CaO, toUMF: 0.95, library: lib)
        }
        // A target of 1 for the only flux changes nothing and is not an error.
        let same = try Reformulate.nudge(r, oxide: .CaO, toUMF: 1, library: lib)
        #expect(same.isExact)
    }

    @Test("C2: Replace reports the oxide with no source left and the flux that takes its place")
    func replaceReportsLostOxide() throws {
        let r = try sample()
        let adj = try Reformulate.replace(r, materialID: "potash-feldspar", with: "soda-feldspar", library: lib)
        #expect(adj.unsupplied == [.K2O])
        #expect(adj.standIn == [.Na2O])
        let k = try #require(adj.residual[.K2O])
        let na = try #require(adj.residual[.Na2O])
        #expect(Reformulate.replaceMissText(.K2O, k, adjustment: adj).contains("No material in the new recipe supplies it"))
        let naText = Reformulate.replaceMissText(.Na2O, na, adjustment: adj)
        #expect(naText.contains("above the original"))
        #expect(naText.contains("K₂O"))
    }

    @Test("S2: the miss line for the other oxides does not say the materials cannot get closer")
    func nudgeMissText() {
        let other = Reformulate.nudgeMissText(.Na2O, 0.009, nudged: .CaO)
        #expect(other.contains("held as close as they can be"))
        #expect(!other.contains("cannot get closer"))
        let own = Reformulate.nudgeMissText(.SiO2, -0.2, nudged: .SiO2)
        #expect(own.contains("below its target"))
    }
}
