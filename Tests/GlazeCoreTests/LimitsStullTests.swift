import Testing
@testable import GlazeCore

@Suite("Limits")
struct LimitsTests {
    static let ids: Set<String> = ["hr-cone6", "hr-cone10",
                                   "cushing-c5-6-gloss", "cushing-c5-6-satin", "cushing-c5-6-matt",
                                   "cushing-c9-10-gloss", "cushing-c9-10-satin", "cushing-c9-10-matt"]

    static func bundled(_ id: String) -> LimitSet { Limits.bundled.first { $0.id == id }! }

    static func chemistry(_ umf: [Oxide: Double]) -> Chemistry {
        Chemistry(umf: umf, molePercent: [:], weightPercent: [:], siAlRatio: 0, r2oRatio: 0, expansion: nil, warnings: [])
    }

    @Test func bundledSets() {
        #expect(Set(Limits.bundled.map(\.id)) == Self.ids)
        #expect(Limits.bundled.count == Self.ids.count)
        for s in Limits.bundled {
            #expect(!s.source.isEmpty)
            #expect(!s.ranges.isEmpty)
            #expect(!s.ranges.contains { $0.covers(.PbO) }, "\(s.id): PbO ranges are not bundled")
            for r in s.ranges { #expect(r.min <= r.max) }
            // one KNaO range, no separate K2O or Na2O range
            #expect(s.ranges.filter { $0.covers(.K2O) || $0.covers(.Na2O) }.count == 1)
            #expect(s.ranges.first { $0.covers(.K2O) }?.label == "KNaO")
        }
    }

    @Test func citedSources() {
        for s in Limits.bundled {
            #expect(s.source.contains("Arbuckle"), "\(s.id)")
            #expect(s.source.contains(s.id.hasPrefix("hr-") ? "Hesselberth and R. Roy, Ceramics Monthly, September 2000"
                                                             : "Cushing's Handbook"), "\(s.id)")
        }
    }

    /// Spot values from the source tables (README-data.md section 4).
    @Test func publishedValues() {
        func r(_ id: String, _ o: Oxide) -> (Double, Double)? {
            Self.bundled(id).ranges.first { $0.covers(o) }.map { ($0.min, $0.max) }
        }
        #expect(r("hr-cone6", .K2O)! == (0.10, 0.30))        // article value; handout typo .01-.03
        #expect(r("hr-cone6", .B2O3)! == (0.15, 0.35))
        #expect(r("hr-cone6", .Al2O3)! == (0.25, 0.40))
        #expect(r("hr-cone10", .CaO)! == (0.30, 0.70))
        #expect(r("hr-cone10", .ZnO) == nil)                  // "none" in the source: not checked
        #expect(r("hr-cone6", .Li2O) == nil)
        #expect(r("hr-cone6", .BaO) == nil)
        #expect(r("cushing-c5-6-gloss", .B2O3)! == (0, 1.0))
        #expect(r("cushing-c5-6-satin", .Al2O3)! == (0.20, 0.40))  // handout "20 - .40"
        #expect(r("cushing-c5-6-matt", .Na2O)! == (0.05, 0.30))    // handout "..05 - .30"
        #expect(r("cushing-c9-10-gloss", .SiO2)! == (2.0, 6.0))
        #expect(r("cushing-c9-10-matt", .ZnO)! == (0, 0.50))       // handout ".0 -50"
        #expect(r("cushing-c9-10-matt", .Al2O3)! == (0.25, 0.80))
    }

    /// Every Cushing cell compared with a second reproduction (G10): B. Quinlan, "The Unity Molecular Formula
    /// Approach to Glaze Development", M.S. thesis, Alfred University, 2002, Tables II-2 and II-3, which cite
    /// Cushing's Handbook, 3rd ed., pp. 47-51 (https://aura.alfred.edu/handle/10829/24507). All 60 cells agree
    /// with the Arbuckle handout as read by G8, including the three handout typos.
    @Test func cushingMatchesSecondSource() {
        let oxides: [Oxide] = [.K2O, .CaO, .MgO, .BaO, .ZnO, .Li2O, .SrO, .Al2O3, .B2O3, .SiO2]  // K2O = KNaO
        // Quinlan's row order: KNaO, CaO, MgO, BaO, ZnO, Li2O, SrO, Al2O3, B2O3, SiO2 (PbO is not bundled).
        let table: [String: [(Double, Double)]] = [
            "cushing-c5-6-gloss": [(0.05, 0.60), (0.05, 0.60), (0, 0.10), (0, 0.15), (0, 0.15), (0, 0.50), (0, 0.15), (0.10, 0.30), (0, 1.00), (1.5, 4.0)],
            "cushing-c5-6-satin": [(0.05, 0.35), (0.05, 0.70), (0, 0.35), (0, 0.35), (0, 0.30), (0, 0.15), (0, 0.35), (0.20, 0.40), (0, 0.50), (2.0, 3.5)],
            "cushing-c5-6-matt":  [(0.05, 0.30), (0.05, 0.80), (0, 0.45), (0, 0.50), (0, 0.40), (0, 0.10), (0, 0.50), (0.20, 0.50), (0, 0.50), (2.0, 3.0)],
            "cushing-c9-10-gloss": [(0.05, 0.50), (0.05, 0.80), (0, 0.15), (0, 0.15), (0, 0.15), (0, 0.40), (0, 0.15), (0.20, 0.50), (0, 0.50), (2.0, 6.0)],
            "cushing-c9-10-satin": [(0.05, 0.40), (0.05, 0.80), (0, 0.50), (0, 0.50), (0, 0.40), (0, 0.20), (0, 0.50), (0.25, 0.60), (0, 0.40), (2.0, 5.0)],
            "cushing-c9-10-matt":  [(0.05, 0.30), (0.05, 0.90), (0, 0.60), (0, 0.60), (0, 0.50), (0, 0.10), (0, 0.60), (0.25, 0.80), (0, 0.20), (2.0, 5.0)],
        ]
        for (id, rows) in table {
            let set = Self.bundled(id)
            #expect(set.ranges.count == oxides.count, "\(id)")
            for (o, expected) in zip(oxides, rows) {
                let r = set.ranges.first { $0.covers(o) }
                #expect(r?.min == expected.0 && r?.max == expected.1, "\(id) \(o.rawValue)")
            }
        }
    }

    @Test func noSafetyWording() {
        for s in Limits.bundled {
            let text = (s.name + " " + s.source).lowercased()
            for bad in ["food", "lead free", "lead-free", "non-toxic", "safe", "stable", "durable"] {
                #expect(!text.contains(bad), "\(s.id) contains \(bad)")
            }
        }
    }

    @Test func leachInsideCushingCone10Gloss() throws {
        // R1 UMF: K2O 0.264, CaO 0.736, Al2O3 0.407, SiO2 3.71
        let c = try chem(recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10)]))
        let set = Self.bundled("cushing-c9-10-gloss")
        let res = Limits.check(c, against: set)
        #expect(res.count == set.ranges.count + 1)   // the KNaO range reports under K2O and Na2O
        #expect(res.values.allSatisfy { $0 })
    }

    @Test func outOfRangeDetected() throws {
        let c = try chem(recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10)]))
        // R1 has no B2O3; Hesselberth & Roy cone 6 needs at least 0.15
        #expect(Limits.check(c, against: Self.bundled("hr-cone6"))[.B2O3] == false)
        // CaO 0.736 is above 0.70 at cone 10; the rest is inside
        let r10 = Limits.check(c, against: Self.bundled("hr-cone10"))
        #expect(r10[.CaO] == false)
        #expect(r10[.K2O] == true && r10[.Na2O] == true && r10[.Al2O3] == true && r10[.SiO2] == true)
    }

    @Test func knaoIsTheSum() {
        let set = Self.bundled("hr-cone6")
        // each alkali alone is inside 0.1-0.3, the sum 0.4 is not
        let high = Limits.check(Self.chemistry([.K2O: 0.2, .Na2O: 0.2]), against: set)
        #expect(high[.K2O] == false && high[.Na2O] == false)
        // each alkali alone is below 0.1, the sum 0.12 is inside
        let ok = Limits.check(Self.chemistry([.K2O: 0.06, .Na2O: 0.06]), against: set)
        #expect(ok[.K2O] == true && ok[.Na2O] == true)
        let k = set.ranges.first { $0.covers(.Na2O) }!
        #expect(abs(k.value(in: [.K2O: 0.06, .Na2O: 0.06]) - 0.12) < 1e-12)
    }

    @Test func customSet() throws {
        let c = try chem(recipe([("whiting", 20), ("silica", 50), ("kaolin", 20)]))
        let set = LimitSet(id: "x", name: "x", cone: "6", ranges: [LimitRange(oxide: .CaO, min: 0.9, max: 1.0),
                                                                   LimitRange(oxide: .MgO, min: 0.1, max: 0.2)], source: "test")
        let r = Limits.check(c, against: set)
        #expect(r[.CaO] == true)
        #expect(r[.MgO] == false)
        #expect(set.ranges[0].label == "CaO")
    }
}

/// Known points on the Stull (1912) chart. x = SiO2, y = Al2O3 (UMF).
/// "G7" = lane G7's reading of Stull 1912, Chart 1 (reproduction at https://digitalfire.com/glossary/stull+chart),
/// about +-0.05 UMF; see ~/glaze-work/G7-REPORT.md section 3 and README-data.md section 5.
struct StullKnownPoint: Sendable, CustomTestStringConvertible {
    let x: Double, y: Double, expected: StullRegion, source: String
    init(_ x: Double, _ y: Double, _ expected: StullRegion, _ source: String) {
        self.x = x; self.y = y; self.expected = expected; self.source = source
    }
    var testDescription: String { "(\(x), \(y)) \(expected.rawValue)" }
}

@Suite("Stull")
struct StullTests {
    static let known: [StullKnownPoint] = [
        // (SiO2, Al2O3, expected region, source)
        .init(3.5, 0.40, .gloss, "G7 table: stays gloss (ratio 8.75, Bloomfield 1:8 bright)"),
        .init(2.0, 0.50, .matte, "G7 table: stays matte (ratio 4)"),
        .init(3.0, 0.52, .gloss, "G7 table: becomes gloss (G1 had semimatte)"),
        .init(5.0, 0.80, .gloss, "G7 table: lies in the bright region (G1 had underfired)"),
        .init(1.5, 0.10, .crazing, "G7: hatched crazed area, lower left"),
        .init(1.0, 0.15, .crazing, "G7: hatched crazed area, lower left"),
        .init(1.2, 0.90, .unfused, "G7: above line M-J (top left)"),
        .init(2.0, 0.95, .unfused, "G7: above line M-J (top left)"),
        .init(2.0, 0.60, .matte, "G7: between M-J and N-U; Bloomfield 1:4 matt"),
        .init(3.0, 0.65, .semimatte, "G7: between N-U and N-K; Bloomfield 1:5 semi-matt"),
        .init(4.0, 0.50, .gloss, "Bloomfield: 1:8 bright, shiny glaze"),
        .init(6.0, 0.40, .underfired, "G7: below curve O-S; McLeod: ratio near 12 and above is underfired (ratio 15)"),
        .init(6.0, 0.30, .underfired, "G7: below curve O-S (lower right)"),
        .init(5.0, 0.20, .underfired, "G7: below curve O-S (lower right)"),
        .init(3.6, 0.25, .crazing, "G7: crazed band just above curve O-S"),
        .init(7.0, 0.70, .gloss, "G7: above curve O-S at the right edge (0.60 at x 7.0)"),
    ]

    @Test(arguments: known)
    func knownPoints(_ p: StullKnownPoint) {
        #expect(Stull.region(siO2: p.x, al2O3: p.y) == p.expected, "\(p.source)")
    }

    @Test func knownPointsCoverEveryRegion() {
        let regions = Set(Self.known.map(\.expected.rawValue))
        #expect(regions == ["gloss", "matte", "semimatte", "crazing", "unfused", "underfired"])
        #expect(Self.known.count >= 8)
    }

    @Test func outsideChartIsUnknown() {
        #expect(Stull.region(siO2: 0, al2O3: 0.3) == .unknown)
        #expect(Stull.region(siO2: 0.5, al2O3: 0.3) == .unknown)
        #expect(Stull.region(siO2: 7.3, al2O3: 0.3) == .unknown)
        #expect(Stull.region(siO2: 9, al2O3: 0.3) == .unknown)
        #expect(Stull.region(siO2: 3, al2O3: 0) == .unknown)
        #expect(Stull.region(siO2: 3, al2O3: 0.05) == .unknown)
        #expect(Stull.region(siO2: 3, al2O3: 1.05) == .unknown)
        #expect(Stull.region(siO2: .nan, al2O3: 0.3) == .unknown)
        #expect(Stull.region(siO2: 3, al2O3: .infinity) == .unknown)
    }

    @Test func lineEquations() {
        // points from G7's reading of the chart
        #expect(abs(Stull.underfiredLine(siO2: 2.4) - 0.10) < 1e-9)
        #expect(abs(Stull.underfiredLine(siO2: 4.2) - 0.30) < 0.01)
        #expect(abs(Stull.underfiredLine(siO2: 7.2) - 0.62) < 0.01)
        #expect(abs(Stull.crazingBandTop(siO2: 3.0) - 0.23) < 1e-9)
        #expect(abs(Stull.crazingBandTop(siO2: 4.2) - 0.30) < 1e-9)
        #expect(abs(Stull.matteLine(siO2: 0.6) - 0.10) < 1e-9)
        #expect(abs(Stull.semimatteLine(siO2: 0.6) - 0.10) < 1e-9)
        #expect(abs(Stull.unfusedLine(siO2: 0.6) - 0.44) < 1e-9)
    }

    @Test func boundariesAreSharp() {
        // just above / below each line at x = 3.0
        let x = 3.0
        // the unfused line leaves the chart (y 1.0) at x 2.84, so test it at x 1.5
        #expect(Stull.region(siO2: 1.5, al2O3: Stull.unfusedLine(siO2: 1.5) + 0.001) == .unfused)
        #expect(Stull.region(siO2: 1.5, al2O3: Stull.unfusedLine(siO2: 1.5) - 0.001) == .matte)
        #expect(Stull.region(siO2: x, al2O3: Stull.matteLine(siO2: x) + 0.001) == .matte)
        #expect(Stull.region(siO2: x, al2O3: Stull.matteLine(siO2: x) - 0.001) == .semimatte)
        #expect(Stull.region(siO2: x, al2O3: Stull.semimatteLine(siO2: x) - 0.001) == .gloss)
        #expect(Stull.region(siO2: x, al2O3: Stull.crazingBandTop(siO2: x) + 0.001) == .gloss)
        #expect(Stull.region(siO2: x, al2O3: Stull.crazingBandTop(siO2: x) - 0.001) == .crazing)
        #expect(Stull.region(siO2: x, al2O3: Stull.underfiredLine(siO2: x) - 0.001) == .underfired)
        // above x 4.3 the underfired curve is higher than the band: no crazing there
        #expect(Stull.region(siO2: 5.0, al2O3: Stull.underfiredLine(siO2: 5.0) + 0.001) == .gloss)
    }

    @Test func leachIsGloss() throws {
        let c = try chem(recipe([("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10)]))
        #expect(Stull.region(siO2: c.umf[.SiO2]!, al2O3: c.umf[.Al2O3]!) == .gloss)
    }
}
