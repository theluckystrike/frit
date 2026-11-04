import Foundation
import Testing
@testable import GlazeCore

private let leach = recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10)])

@Suite("Chemistry details and edge cases")
struct ChemistryTests {
    // R1 by hand: moles K2O 0.07186, CaO 0.19983, Al2O3 0.11059, SiO2 1.00793, total 1.39021.
    // mole %: K2O 5.169, CaO 14.374, Al2O3 7.955, SiO2 72.502
    @Test func molePercent() throws {
        let c = try chem(leach)
        #expect(near(c.molePercent[.K2O], 5.169, 0.01))
        #expect(near(c.molePercent[.CaO], 14.374, 0.01))
        #expect(near(c.molePercent[.Al2O3], 7.955, 0.01))
        #expect(near(c.molePercent[.SiO2], 72.502, 0.01))
        #expect(abs(c.molePercent.values.reduce(0, +) - 100) < 1e-9)
    }

    // fired weights: K2O 6.769 g, CaO 11.206 g, Al2O3 11.276 g, SiO2 60.559 g, total 89.81 g
    // weight %: K2O 7.537, CaO 12.477, Al2O3 12.556, SiO2 67.431
    @Test func weightPercent() throws {
        let c = try chem(leach)
        #expect(near(c.weightPercent[.K2O], 7.537, 0.01))
        #expect(near(c.weightPercent[.CaO], 12.477, 0.01))
        #expect(near(c.weightPercent[.Al2O3], 12.556, 0.01))
        #expect(near(c.weightPercent[.SiO2], 67.431, 0.01))
        #expect(abs(c.weightPercent.values.reduce(0, +) - 100) < 1e-9)
    }

    // Appen (W6 F3, terms in Appen.swift): SiO2 72.502 mol % is above 67, so k(SiO2) = 105 - 72.502 = 32.498;
    // no Na2O (not above 1 mol %), so k(K2O) = 420.
    // 0.05169 x 420 + 0.14374 x 130 + 0.07955 x (-30) + 0.72502 x 32.498
    //   = 21.709 + 18.686 - 2.387 + 23.562 = 61.57 (x 1e-7 / K). The old fixed-constant sum was 67.89.
    @Test func expansionAppen() throws {
        let c = try chem(leach)
        #expect(near(c.expansion, 61.57, 0.05))
        #expect(c.expansionNotCounted.isEmpty)
        #expect(!c.expansionIsPartial)
        #expect(!c.warnings.contains { $0.lowercased().contains("expansion") })
    }

    // Boron is counted with Appen's F term. potash feldspar 40, boric acid 10, whiting 20, silica 30.
    // mol %: K2O 5.3037, Al2O3 5.3037, SiO2 68.6752, B2O3 5.9685, CaO 14.7489.
    // F = (K2O + 0.7 CaO - Al2O3) / B2O3 = (5.3037 + 10.3242 - 5.3037) / 5.9685 = 1.7298 (<= 4)
    // k(B2O3) = -12.5 x 1.7298 = -21.622; k(SiO2) = 105 - 68.6752 = 36.325; k(K2O) = 420 (no Na2O)
    // 0.053037 x 420 + 0.053037 x (-30) + 0.686752 x 36.325 + 0.059685 x (-21.622) + 0.147489 x 130
    //   = 22.276 - 1.591 + 24.946 - 1.291 + 19.174 = 63.51
    @Test func expansionCountsBoron() throws {
        let c = try chem(recipe([("potash-feldspar", 40), ("boric-acid", 10), ("whiting", 20), ("silica", 30)]))
        #expect(near(c.expansion, 63.51, 0.05))
        #expect(c.expansionNotCounted.isEmpty)
        #expect(!c.warnings.contains { $0.lowercased().contains("expansion") })
    }

    // Cr2O3 has no Appen coefficient: the estimate is partial and says so. Leach + chrome oxide 2 (addition).
    // mol %: K2O 5.1204, Al2O3 7.8806, SiO2 71.8221, CaO 14.2392 (Cr2O3 0.938, not counted)
    // 0.051204 x 420 - 0.078806 x 30 + 0.718221 x (105 - 71.8221) + 0.142392 x 130 = 61.48
    @Test func expansionPartialForCr2O3() throws {
        let r = recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10)],
                       additions: [("chrome-oxide", 2)])
        let c = try chem(r, additions: true)
        #expect(near(c.expansion, 61.48, 0.05))
        #expect(c.expansionNotCounted == [.Cr2O3])
        #expect(c.expansionIsPartial)
        #expect(c.warnings.contains { $0.contains("partial") && $0.contains("Cr2O3") })
        // Additions off: no Cr2O3, so the estimate is complete again.
        #expect(try chem(r).expansionIsPartial == false)
    }

    // TiO2: Appen's term needs 50 <= SiO2 <= 80 mol %. Whiting 50, kaolin 30, silica 10, TiO2 5:
    // SiO2 37.03 mol %, so TiO2 is not counted. 0.463751 x 130 - 0.107876 x 30 + 0.370256 x 38 = 71.12
    @Test func expansionPartialForTiO2OutsideSilicaRange() throws {
        let c = try chem(recipe([("whiting", 50), ("kaolin", 30), ("silica", 10), ("titanium-dioxide", 5)]))
        #expect(near(c.expansion, 71.12, 0.05))
        #expect(c.expansionNotCounted == [.TiO2])
        #expect(c.warnings.contains { $0.contains("partial") && $0.contains("TiO2") && $0.contains("50 to 80") })
    }

    // TiO2 inside the range: leach + TiO2 5. SiO2 69.3777 mol %: k(TiO2) = 105 - 1.5 x 69.3777 = 0.9335.
    // 0.049461 x 420 - 0.076124 x 30 + 0.693777 x 35.6223 + 0.137546 x 130 + 0.043093 x 0.9335 = 61.13
    @Test func expansionCountsTiO2InsideSilicaRange() throws {
        let c = try chem(recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10),
                                 ("titanium-dioxide", 5)]))
        #expect(near(c.expansion, 61.13, 0.05))
        #expect(c.expansionNotCounted.isEmpty)
    }

    // Appen's composition-dependent coefficients at their boundaries (Fluegel's reproduction, footnotes a-f).
    @Test func appenCoefficientTerms() throws {
        let t = try OxideTable.load()
        func k(_ o: Oxide, _ mol: [Oxide: Double]) -> Double? { try? Appen.coefficient(o, molePercent: mol, table: t).get() }
        // SiO2: 38 below 67 mol %, then 105 - [SiO2] (3.8 -> 0.5 in the page's units).
        #expect(k(.SiO2, [.SiO2: 60]) == 38)
        #expect(k(.SiO2, [.SiO2: 67]) == 38)
        #expect(k(.SiO2, [.SiO2: 80]) == 25)
        #expect(k(.SiO2, [.SiO2: 100]) == 5)
        // K2O: 465 only with more than 1 mol % Na2O, otherwise 420.
        #expect(k(.K2O, [.K2O: 5, .Na2O: 1]) == 420)
        #expect(k(.K2O, [.K2O: 5, .Na2O: 1.5]) == 465)
        // B2O3: F = (10 Na2O - 2 Al2O3) / 4 B2O3 = 2 -> -25; F = (30 - 2) / 4 = 7 > 4 -> -50; F < 0 -> not counted.
        #expect(k(.B2O3, [.Na2O: 10, .Al2O3: 2, .B2O3: 4]) == -25)
        #expect(k(.B2O3, [.Na2O: 30, .Al2O3: 2, .B2O3: 4]) == -50)
        #expect(k(.B2O3, [.CaO: 10, .Al2O3: 8, .B2O3: 4]) == nil)
        // PbO: 130 below 3 mol % R2O, 115 + 5 x R2O up to 15 (190), not counted above.
        #expect(k(.PbO, [.PbO: 10, .K2O: 2]) == 130)
        #expect(k(.PbO, [.PbO: 10, .K2O: 4, .Na2O: 6]) == 165)
        #expect(k(.PbO, [.PbO: 10, .Na2O: 16]) == nil)
        // TiO2: 105 - 1.5 [SiO2] for 50 <= SiO2 <= 80, not counted outside.
        #expect(k(.TiO2, [.SiO2: 60]) == 15)
        #expect(k(.TiO2, [.SiO2: 45]) == nil)
        #expect(k(.TiO2, [.SiO2: 81]) == nil)
        // Cr2O3: no coefficient. Constants: CaO 130.
        #expect((try? Appen.coefficient(.Cr2O3, molePercent: [:], table: t).get()) == nil)
        #expect(k(.CaO, [.CaO: 10]) == 130)
    }

    @Test func emptyRecipe() throws {
        let c = try chem(recipe([]))
        #expect(c.umf.isEmpty)
        #expect(c.molePercent.isEmpty)
        #expect(c.weightPercent.isEmpty)
        #expect(c.siAlRatio == 0)
        #expect(c.r2oRatio == 0)
        #expect(c.expansion == nil)
        #expect(!c.warnings.isEmpty)
    }

    @Test func additionsOnlyExcluded() throws {
        let r = recipe([], additions: [("red-iron-oxide", 5), ("cobalt-carbonate", 1)])
        let c = try chem(r, additions: false)
        #expect(c.umf.isEmpty)
        #expect(!c.warnings.isEmpty)
    }

    @Test func additionsOnlyIncludedHasNoFlux() throws {
        let r = recipe([], additions: [("red-iron-oxide", 5)])
        let c = try chem(r, additions: true)
        #expect(c.umf.isEmpty)                       // cannot normalize without flux
        #expect(near(c.molePercent[.Fe2O3], 100))     // still reported
        #expect(c.warnings.contains { $0.lowercased().contains("flux") })
    }

    @Test func unknownMaterialWarnsAndIsSkipped() throws {
        let r = recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10), ("no-such-thing", 50)])
        let c = try chem(r)
        #expect(c.warnings.contains { $0.contains("no-such-thing") })
        #expect(near(c.umf[.SiO2], 3.7099))
    }

    @Test func zeroFlux() throws {
        let c = try chem(recipe([("silica", 60), ("kaolin", 40)]))
        #expect(c.umf.isEmpty)
        #expect(c.r2oRatio == 0)
        #expect(c.siAlRatio > 0)
        #expect(c.warnings.contains { $0.lowercased().contains("flux") })
    }

    @Test func negativeAmountWarnsAndIsIgnored() throws {
        let r = recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10), ("zinc-oxide", -5)])
        let c = try chem(r)
        #expect(c.warnings.contains { $0.lowercased().contains("negative") })
        #expect(c.umf[.ZnO] == nil)
        #expect(near(c.umf[.CaO], 0.7355))
    }

    @Test func nonFiniteAmountThrows() {
        let r = recipe([("silica", .nan)])
        #expect(throws: GlazeError.self) { try chem(r) }
    }

    @Test func colorantNotCountedAsFlux() throws {
        let c = try chem(recipe([("whiting", 20), ("silica", 50), ("kaolin", 20)], additions: [("cobalt-carbonate", 2)]), additions: true)
        #expect(c.umf[.CaO] == 1.0)
        #expect((c.umf[.CoO] ?? 0) > 0)
    }

    @Test func siAlWithoutAluminaIsZeroWithWarning() throws {
        let c = try chem(recipe([("whiting", 20), ("silica", 80)]))
        #expect(c.siAlRatio == 0)
        #expect(c.warnings.contains { $0.contains("Al2O3") })
    }

    @Test func r2oRatioMixed() throws {
        // R5: Na2O 0.2503 of the flux; SrO and ZnO are RO
        let c = try chem(recipe([("soda-feldspar", 35), ("strontium-carbonate", 15), ("zinc-oxide", 8), ("kaolin", 15), ("silica", 27)]))
        #expect(near(c.r2oRatio, 0.2503))
    }

    @Test func customLibraryOverridesBundled() throws {
        let custom = Material(id: "silica", name: "My silica", analysis: [.SiO2: 99.0, .Al2O3: 1.0], loi: 0, source: "user")
        let layered = LayeredLibrary(custom: [custom], base: lib)
        let c = try GlazeCalculator.chemistry(of: recipe([("silica", 50), ("whiting", 50)]), library: layered, includeAdditions: false)
        #expect((c.umf[.Al2O3] ?? 0) > 0)
        #expect(layered.material(id: "whiting") != nil)
    }
}
