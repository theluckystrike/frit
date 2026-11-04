import Foundation
import Testing
@testable import GlazeCore

@Suite("Bundled data")
struct DataTests {
    @Test func allOxidesHaveInfo() throws {
        let t = try OxideTable.load()
        for o in Oxide.allCases { #expect(t[o] != nil, "missing \(o)") }
    }

    @Test func molarMassesFromAtomicWeights() throws {
        // SiO2 = 28.085 + 2 x 15.999 = 60.083; Al2O3 = 2 x 26.982 + 3 x 15.999 = 101.961
        // K2O = 2 x 39.098 + 15.999 = 94.195; B2O3 = 2 x 10.81 + 3 x 15.999 = 69.617
        let t = try OxideTable.load()
        #expect(abs(t[.SiO2]!.molarMass - 60.083) < 1e-6)
        #expect(abs(t[.Al2O3]!.molarMass - 101.961) < 1e-6)
        #expect(abs(t[.K2O]!.molarMass - 94.195) < 1e-6)
        #expect(abs(t[.B2O3]!.molarMass - 69.617) < 1e-6)
    }

    @Test func roles() throws {
        let t = try OxideTable.load()
        for o in [Oxide.Li2O, .Na2O, .K2O, .MgO, .CaO, .SrO, .BaO, .ZnO, .PbO] { #expect(t[o]!.role == .flux) }
        #expect(t[.Al2O3]!.role == .stabilizer)
        #expect(t[.B2O3]!.role == .stabilizer)
        #expect(t[.SiO2]!.role == .glassFormer)
        #expect(t[.Fe2O3]!.role == .colorant)
        #expect(t[.CoO]!.role == .colorant)
    }

    @Test func libraryHasEnoughMaterials() {
        #expect(lib.all.count >= 40)
        #expect(lib.all.count <= 60)
        #expect(Set(lib.all.map(\.id)).count == lib.all.count)
    }

    @Test func analysisPlusLOIIsHundred() {
        for m in lib.all {
            let s = m.analysis.values.reduce(0, +) + m.loi
            #expect(abs(s - 100) < 0.01, "\(m.id) sums to \(s)")
            #expect(m.loi >= 0)
        }
    }

    @Test func everyMaterialHasSourceAndNoForbiddenData() {
        for m in lib.all {
            #expect(!m.source.isEmpty, "\(m.id) has no source")
            let s = m.source.lowercased()
            #expect(!s.contains("glazy") && !s.contains("digitalfire"))
        }
    }

    @Test func theoreticalWhitingAndKaolin() {
        // whiting CaCO3: 56.077 / 100.086 = 56.03 % CaO, LOI 43.97 %
        let w = lib.material(id: "whiting")!
        #expect(abs(w.analysis[.CaO]! - 56.029) < 0.01)
        #expect(abs(w.loi - 43.971) < 0.01)
        // kaolin Al2Si2O5(OH)4: 101.961 / 258.157 = 39.50 % Al2O3, 120.166 / 258.157 = 46.55 % SiO2
        let k = lib.material(id: "kaolin")!
        #expect(abs(k.analysis[.Al2O3]! - 39.496) < 0.01)
        #expect(abs(k.analysis[.SiO2]! - 46.548) < 0.01)
        #expect(abs(k.loi - 13.957) < 0.01)
    }

    @Test func requestedMaterialsPresent() {
        for id in ["silica", "whiting", "wollastonite", "talc", "dolomite", "kaolin", "potash-feldspar", "soda-feldspar",
                   "zinc-oxide", "strontium-carbonate", "lithium-carbonate", "magnesium-carbonate", "titanium-dioxide",
                   "tin-oxide", "zircon", "red-iron-oxide", "cobalt-carbonate", "copper-carbonate", "chrome-oxide",
                   "manganese-dioxide", "bone-ash"] {
            #expect(lib.material(id: id) != nil, "missing \(id)")
        }
    }

    @Test func materialJSONUsesOxideKeys() throws {
        let m = lib.material(id: "talc")!
        let data = try JSONEncoder().encode(m)
        let s = String(decoding: data, as: UTF8.self)
        #expect(s.contains("\"MgO\""))
        #expect(try JSONDecoder().decode(Material.self, from: data) == m)
    }
}
