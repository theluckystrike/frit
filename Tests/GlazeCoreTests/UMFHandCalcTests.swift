import Testing
@testable import GlazeCore

// Ten recipes with UMF values computed by hand (calculator), independently of materials.json:
// each material is written in oxide notation, its formula weight is the sum of oxide molar masses
// (IUPAC 2021 atomic weights), and moles of oxide = grams / formula weight x oxides per formula.
//
// Molar masses used: K2O 94.195, Na2O 61.979, Li2O 29.879, CaO 56.077, MgO 40.304, SrO 103.619,
// BaO 153.329, ZnO 81.379, B2O3 69.617, Al2O3 101.961, SiO2 60.083, Fe2O3 159.687,
// H2O 18.015, CO2 44.009.
//
// ---------------------------------------------------------------------------------------------
// Worked example 1: R1 "Leach 4321" (cone 10): potash feldspar 40, silica 30, whiting 20, kaolin 10
//   potash feldspar K2O.Al2O3.6SiO2  FW = 94.195 + 101.961 + 6 x 60.083 = 556.654
//       40 / 556.654 = 0.07186 -> K2O 0.07186, Al2O3 0.07186, SiO2 6 x 0.07186 = 0.43115
//   silica SiO2  FW 60.083:      30 / 60.083  = 0.49931 -> SiO2 0.49931
//   whiting CaO.CO2  FW = 56.077 + 44.009 = 100.086:  20 / 100.086 = 0.19983 -> CaO 0.19983
//   kaolin Al2O3.2SiO2.2H2O  FW = 101.961 + 2 x 60.083 + 2 x 18.015 = 258.157
//       10 / 258.157 = 0.03874 -> Al2O3 0.03874, SiO2 0.07747
//   Totals: K2O 0.07186, CaO 0.19983, Al2O3 0.11059, SiO2 1.00793
//   Flux sum = K2O + CaO = 0.27169
//   UMF: K2O 0.07186/0.27169 = 0.2645, CaO 0.7355, Al2O3 0.11059/0.27169 = 0.4071,
//        SiO2 1.00793/0.27169 = 3.7099.  Si:Al = 1.00793/0.11059 = 9.114.  R2O share = 0.2645.
//
// Worked example 2: R2 (cone 6, boron): wollastonite 20, generic calcium borate frit 25,
//   potash feldspar 25, kaolin 15, silica 15
//   wollastonite CaO.SiO2  FW = 116.160:  20 / 116.160 = 0.17218 -> CaO 0.17218, SiO2 0.17218
//   frit 0.7CaO.0.3Na2O.1.0B2O3.2.0SiO2  FW = 0.7 x 56.077 + 0.3 x 61.979 + 69.617 + 2 x 60.083
//       = 247.631;  25 / 247.631 = 0.10096 -> CaO 0.07067, Na2O 0.03029, B2O3 0.10096, SiO2 0.20191
//   potash feldspar 25 / 556.654 = 0.04491 -> K2O 0.04491, Al2O3 0.04491, SiO2 0.26947
//   kaolin 15 / 258.157 = 0.05810 -> Al2O3 0.05810, SiO2 0.11621
//   silica 15 / 60.083 = 0.24965 -> SiO2 0.24965
//   Totals: CaO 0.24285, Na2O 0.03029, K2O 0.04491, B2O3 0.10096, Al2O3 0.10302, SiO2 1.00942
//   Flux sum = 0.24285 + 0.03029 + 0.04491 = 0.31804
//   UMF: CaO 0.7636, Na2O 0.0952, K2O 0.1412, B2O3 0.3174, Al2O3 0.3239, SiO2 3.1738
//   Si:Al = 1.00942 / 0.10302 = 9.798. All moles 1.53145. (Both worked examples were re-checked by a
//   second reviewer, Hermes, 22 Oct 2026: no errors.)
//   Appen expansion with the B2O3 term (W6 F3, Appen.swift): mol % B2O3 6.5923, Na2O 1.9777 (> 1, so K2O 465),
//   SiO2 65.913 (< 67, so SiO2 38). F = (Na2O + K2O + 0.7 CaO - Al2O3) / B2O3
//   = (1.9777 + 2.9326 + 11.1002 - 6.7267) / 6.5923 = 1.4083, k(B2O3) = -12.5 x 1.4083 = -17.603.
//   0.15857 x 130 + 0.01978 x 395 + 0.02933 x 465 + 0.06727 x (-30) + 0.65913 x 38 + 0.06592 x (-17.603)
//   = 20.615 + 7.812 + 13.637 - 2.018 + 25.047 - 1.160 = 63.93 (B2O3 left out, the old value was 65.09)
// ---------------------------------------------------------------------------------------------
// R3..R10 were done the same way; only the results are listed at each test.

private func check(_ r: Recipe, _ expected: [Oxide: Double], additions: Bool = false) throws {
    let c = try chem(r, additions: additions)
    for (o, v) in expected {
        #expect(near(c.umf[o], v), "\(o): got \(c.umf[o] ?? -1), expected \(v)")
    }
    let fluxSum = c.umf.filter { OxideTable.role(of: $0.key) == .flux }.values.reduce(0, +)
    #expect(abs(fluxSum - 1.0) < 1e-9)
}

@Suite("UMF against hand calculations")
struct UMFHandCalcTests {
    @Test func r1_leach4321() throws {
        let r = recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10)])
        try check(r, [.K2O: 0.2645, .CaO: 0.7355, .Al2O3: 0.4071, .SiO2: 3.7099])
        let c = try chem(r)
        #expect(near(c.siAlRatio, 9.114))
        #expect(near(c.r2oRatio, 0.2645))
    }

    @Test func r2_boronFrit() throws {
        let r = recipe([("wollastonite", 20), ("frit-generic-calcium-borate", 25), ("potash-feldspar", 25),
                        ("kaolin", 15), ("silica", 15)])
        try check(r, [.CaO: 0.7636, .Na2O: 0.0952, .K2O: 0.1412, .B2O3: 0.3174, .Al2O3: 0.3239, .SiO2: 3.1738])
        let c = try chem(r)
        #expect(near(c.siAlRatio, 9.798))
        #expect(near(c.expansion, 63.93, 0.05))
        #expect(c.expansionNotCounted.isEmpty)
    }

    // R3: potash feldspar 30, dolomite 25, kaolin 25, silica 15, whiting 5
    // moles K2O 0.05389, CaO 0.18553, MgO 0.13558, Al2O3 0.15073, SiO2 0.76670; flux 0.37500
    @Test func r3_dolomiteMatte() throws {
        let r = recipe([("potash-feldspar", 30), ("dolomite", 25), ("kaolin", 25), ("silica", 15), ("whiting", 5)])
        try check(r, [.K2O: 0.1437, .CaO: 0.4948, .MgO: 0.3615, .Al2O3: 0.4020, .SiO2: 2.0445])
    }

    // R4: spodumene 30, lithium carbonate 5, whiting 20, kaolin 20, silica 25
    // moles Li2O 0.14828, CaO 0.19983, Al2O3 0.15808, SiO2 0.89347; flux 0.34811
    @Test func r4_lithium() throws {
        let r = recipe([("spodumene", 30), ("lithium-carbonate", 5), ("whiting", 20), ("kaolin", 20), ("silica", 25)])
        try check(r, [.Li2O: 0.4260, .CaO: 0.5740, .Al2O3: 0.4541, .SiO2: 2.5667])
    }

    // R5: soda feldspar 35, strontium carbonate 15, zinc oxide 8, kaolin 15, silica 27
    // moles Na2O 0.06674, SrO 0.10161, ZnO 0.09831, Al2O3 0.12484, SiO2 0.96602; flux 0.26665
    @Test func r5_strontiumZinc() throws {
        let r = recipe([("soda-feldspar", 35), ("strontium-carbonate", 15), ("zinc-oxide", 8), ("kaolin", 15), ("silica", 27)])
        try check(r, [.Na2O: 0.2503, .SrO: 0.3810, .ZnO: 0.3687, .Al2O3: 0.4682, .SiO2: 3.6228])
    }

    // R6: boric acid 10, borax 10, whiting 20, soda feldspar 30, kaolin 15, silica 15
    // moles B2O3 0.13331, Na2O 0.08343, CaO 0.19983, Al2O3 0.11531, SiO2 0.70909; flux 0.28325
    @Test func r6_boronSources() throws {
        let r = recipe([("boric-acid", 10), ("borax", 10), ("whiting", 20), ("soda-feldspar", 30), ("kaolin", 15), ("silica", 15)])
        try check(r, [.B2O3: 0.4706, .Na2O: 0.2945, .CaO: 0.7055, .Al2O3: 0.4071, .SiO2: 2.5034])
    }

    // R7: R1 + 5 red iron oxide as an addition. Fe2O3 0.03131 mol / 0.27169 = 0.1152.
    @Test func r7_ironAdditionIncluded() throws {
        let r = recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10)],
                       additions: [("red-iron-oxide", 5)])
        try check(r, [.K2O: 0.2645, .CaO: 0.7355, .Al2O3: 0.4071, .SiO2: 3.7099, .Fe2O3: 0.1152], additions: true)
    }

    @Test func r7_ironAdditionExcluded() throws {
        let r = recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10)],
                       additions: [("red-iron-oxide", 5)])
        try check(r, [.K2O: 0.2645, .CaO: 0.7355, .Al2O3: 0.4071, .SiO2: 3.7099])
        #expect(try chem(r).umf[.Fe2O3] == nil)
    }

    // R8: potash feldspar 50, barium carbonate 25, kaolin 10, silica 15
    // moles K2O 0.08982, BaO 0.12669, Al2O3 0.12856, SiO2 0.86606; flux 0.21651
    @Test func r8_barium() throws {
        let r = recipe([("potash-feldspar", 50), ("barium-carbonate", 25), ("kaolin", 10), ("silica", 15)])
        try check(r, [.K2O: 0.4149, .BaO: 0.5851, .Al2O3: 0.5938, .SiO2: 4.0001])
    }

    // R9: wollastonite 25, nepheline (mineral) 30, kaolin 20, silica 25
    // moles CaO 0.21522, Na2O 0.10559, Al2O3 0.18307, SiO2 0.99744; flux 0.32081
    @Test func r9_nepheline() throws {
        let r = recipe([("wollastonite", 25), ("nepheline", 30), ("kaolin", 20), ("silica", 25)])
        try check(r, [.CaO: 0.6709, .Na2O: 0.3291, .Al2O3: 0.5706, .SiO2: 3.1091])
    }

    // R10: generic soda borosilicate frit 60, kaolin 20, silica 15, magnesium carbonate 5
    // moles Na2O 0.11530, CaO 0.07687, MgO 0.05930, B2O3 0.11530, Al2O3 0.13512, SiO2 0.98111; flux 0.25147
    @Test func r10_sodaFrit() throws {
        let r = recipe([("frit-generic-soda-borosilicate", 60), ("kaolin", 20), ("silica", 15), ("magnesium-carbonate", 5)])
        try check(r, [.Na2O: 0.4585, .CaO: 0.3057, .MgO: 0.2358, .B2O3: 0.4585, .Al2O3: 0.5373, .SiO2: 3.9015])
    }

    @Test func scalingRecipeDoesNotChangeUMF() throws {
        let a = try chem(recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10)]))
        let b = try chem(recipe([("potash-feldspar", 400), ("silica", 300), ("whiting", 200), ("kaolin", 100)]))
        for o in a.umf.keys { #expect(abs(a.umf[o]! - b.umf[o]!) < 1e-9) }
    }
}
