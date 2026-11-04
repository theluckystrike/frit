import Foundation
import Testing
@testable import GlazeCore

// Independent reference check (lane W5-V6, 25 Oct 2026).
//
// Reference: the Glazy public data export, https://github.com/derekphilipau/glazy-data (CC BY-NC-SA 4.0,
// commit aa81811). Each recipe cites its page https://glazy.org/recipes/<id> and each material
// https://glazy.org/materials/<id>.
// - Recipes and material analyses: glazy_20260531.yaml.gz.
// - Expected UMF and SiO2:Al2O3: glazy-data-all-20211130.csv, columns <oxide>_umf and SiO2_Al2O3_ratio_umf,
//   computed by Glazy's own code. A recipe is used only when its 2021 and 2026 percent analyses agree within
//   0.01 for every oxide, so the 2021 UMF belongs to the same material data as the 2026 ingredients.
// - Glazy's UMF has the same unity convention as GlazeCore: R2O + RO = 1, colorants (Fe2O3, CoO, CuO) and
//   additions are listed but are not in the unity. Additions are included (Glazy analyses include them).
//
// The fixture (Fixtures/glazy-reference.json) is test data only. It is not in the app bundle (SPEC rule 6).
// The materials are entered as custom materials with Glazy's analyses, so a difference is a calculation
// difference, not a material-data difference. `bundledMaterialsVsGlazy` shows the material-data effect.

struct RefLine: Decodable { let material: String; let name: String; let amount: Double; let addition: Bool }
struct RefRecipe: Decodable {
    let glazyID: Int; let name: String; let author: String?; let cone: String?; let url: String
    let lines: [RefLine]; let glazyUMF: [String: Double]; let glazySiAl: Double; let glazyPercent: [String: Double]
}
struct RefMaterial: Decodable { let id: String; let name: String; let url: String; let analysis: [String: Double]; let loi: Double }
struct RefFile: Decodable { let source: String; let recipes: [RefRecipe]; let materials: [RefMaterial] }

let reference: RefFile = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/glazy-reference.json")
    do { return try JSONDecoder().decode(RefFile.self, from: Data(contentsOf: url)) } catch {
        fatalError("glazy-reference.json: \(error)")
    }
}()

let referenceLibrary: LayeredLibrary = {
    let mats = reference.materials.map { m in
        Material(id: m.id, name: m.name,
                 analysis: Dictionary(uniqueKeysWithValues: m.analysis.compactMap { k, v in Oxide(rawValue: k).map { ($0, v) } }),
                 loi: m.loi, source: m.url)
    }
    return LayeredLibrary(custom: mats, base: lib)
}()

func refRecipe(_ r: RefRecipe, map: (String) -> String? = { $0 }) -> Recipe? {
    var lines: [RecipeLine] = []
    for l in r.lines {
        guard let id = map(l.material) else { return nil }
        lines.append(RecipeLine(materialID: id, amount: l.amount, isAddition: l.addition))
    }
    return Recipe(name: r.name, cone: r.cone ?? "", lines: lines)
}

/// Glazy material id -> Frit bundled (theoretical) material id. Real commercial materials have no entry.
let glazyToBundled: [String: String] = [
    "glazy-15020": "alumina-hydrate", "glazy-15062": "barium-carbonate", "glazy-15114": "cobalt-carbonate",
    "glazy-15117": "cobalt-oxide", "glazy-15119": "colemanite", "glazy-15120": "copper-carbonate",
    "glazy-15135": "dolomite", "glazy-15142": "potash-feldspar", "glazy-15288": "kaolin",
    "glazy-15323": "lithium-carbonate", "glazy-15371": "potash-feldspar", "glazy-15387": "red-iron-oxide",
    "glazy-15400": "silica", "glazy-15431": "strontium-carbonate", "glazy-15433": "talc",
    "glazy-15442": "tin-oxide", "glazy-15443": "titanium-dioxide", "glazy-15457": "whiting",
    "glazy-15458": "wollastonite", "glazy-15467": "zinc-oxide", "glazy-15469": "zircon",
]

struct OxideDeviation: Encodable { let oxide: String; let frit: Double; let glazy: Double; let abs: Double; let rel: Double?; let flagged: Bool }
struct RecipeResult: Encodable {
    let glazyID: Int; let name: String; let url: String; let mode: String
    let umf: [OxideDeviation]; let siAlFrit: Double; let siAlGlazy: Double; let siAlRel: Double
    let weightPercentMaxAbs: Double; let expansionFrit: Double?; let flagged: Bool
}

/// Rule from the lane brief: flag |d| > 0.02 UMF, or relative > 3 %. Relative is only taken when the
/// Glazy value is >= 0.01: Glazy rounds to 4 decimals, so smaller values carry > 1 % rounding noise.
func compare(_ r: RefRecipe, _ c: Chemistry, mode: String) -> RecipeResult {
    var rows: [OxideDeviation] = []
    let keys = Set(r.glazyUMF.keys).union(c.umf.keys.map(\.rawValue))
    for k in keys.sorted() {
        let f = Oxide(rawValue: k).flatMap { c.umf[$0] } ?? 0
        let g = r.glazyUMF[k] ?? 0
        if f < 0.00005 && g == 0 { continue } // below Glazy's 4-decimal rounding
        let d = abs(f - g)
        let rel: Double? = g >= 0.01 ? d / g : nil
        rows.append(OxideDeviation(oxide: k, frit: f, glazy: g, abs: d, rel: rel, flagged: d > 0.02 || (rel ?? 0) > 0.03))
    }
    // Weight percent: Glazy gives raw-basis percent (with LOI); normalize the oxides to 100 for fired weight %.
    let gSum = r.glazyPercent.filter { $0.key != "LOI" }.values.reduce(0, +)
    var wMax = 0.0
    for (k, v) in r.glazyPercent where k != "LOI" {
        let f = Oxide(rawValue: k).flatMap { c.weightPercent[$0] } ?? 0
        wMax = max(wMax, abs(f - v / gSum * 100))
    }
    let siRel = r.glazySiAl > 0 ? abs(c.siAlRatio - r.glazySiAl) / r.glazySiAl : 0
    return RecipeResult(glazyID: r.glazyID, name: r.name, url: r.url, mode: mode, umf: rows, siAlFrit: c.siAlRatio,
                        siAlGlazy: r.glazySiAl, siAlRel: siRel, weightPercentMaxAbs: wMax, expansionFrit: c.expansion,
                        flagged: rows.contains { $0.flagged } || siRel > 0.03)
}

func writeReportIfAsked(_ results: [RecipeResult], name: String) throws {
    guard let dir = ProcessInfo.processInfo.environment["GLAZE_REF_OUT"] else { return }
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(results).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
}

@Suite("UMF against Glazy reference data")
struct GlazyReferenceTests {
    @Test func fixtureHasEnoughCases() {
        #expect(reference.recipes.count >= 25)
        for r in reference.recipes { #expect(r.url.hasPrefix("https://glazy.org/recipes/")) }
    }

    /// Same material analyses as Glazy: every UMF oxide within 0.001 and SiO2:Al2O3 within 0.1 %.
    /// The 0.001 bound covers Glazy's 4-decimal rounding and its slightly different molar masses.
    @Test(arguments: reference.recipes.map(\.glazyID))
    func umfMatchesGlazy(_ id: Int) throws {
        let r = try #require(reference.recipes.first { $0.glazyID == id })
        let recipe = try #require(refRecipe(r))
        let c = try GlazeCalculator.chemistry(of: recipe, library: referenceLibrary, includeAdditions: true)
        #expect(!c.warnings.contains { $0.contains("Unknown material") }, "\(r.url)")
        let res = compare(r, c, mode: "glazy-materials")
        for row in res.umf {
            #expect(row.abs <= 0.001, "\(r.url) \(r.name) \(row.oxide): Frit \(row.frit), Glazy \(row.glazy)")
        }
        #expect(res.siAlRel <= 0.001, "\(r.url) Si:Al Frit \(res.siAlFrit), Glazy \(r.glazySiAl)")
        #expect(res.weightPercentMaxAbs <= 0.01, "\(r.url) weight % max deviation \(res.weightPercentMaxAbs)")
    }

    @Test func writeReport() throws {
        var out: [RecipeResult] = []
        for r in reference.recipes {
            guard let recipe = refRecipe(r) else { continue }
            let c = try GlazeCalculator.chemistry(of: recipe, library: referenceLibrary, includeAdditions: true)
            out.append(compare(r, c, mode: "glazy-materials"))
            if let b = refRecipe(r, map: { glazyToBundled[$0] }) {
                let cb = try GlazeCalculator.chemistry(of: b, library: lib, includeAdditions: true)
                out.append(compare(r, cb, mode: "frit-bundled-materials"))
            }
        }
        #expect(out.count >= reference.recipes.count)
        try writeReportIfAsked(out, name: "harness-results.json")
    }

    /// Leach 4321 (https://glazy.org/recipes/240) with Frit's bundled theoretical materials.
    /// The only difference from Glazy is the kaolin analysis: Glazy "Kaolin" (https://glazy.org/materials/15288)
    /// is Al2O3 40.21 / SiO2 47.29 / LOI 12.5; Frit uses the exact formula, Al2O3 39.50 / SiO2 46.55 / LOI 13.96.
    /// Fluxes agree within 0.001; Al2O3 is 0.0022 lower (0.5 %).
    /// Red iron oxide: Glazy https://glazy.org/materials/15387 is Fe2O3 95 / LOI 5; Frit's is pure Fe2O3 (100),
    /// so Frit's Fe2O3 is 100 / 95 = 1.053 times Glazy's (0.0922 vs 0.0875, 5.4 %). Material data, not a code bug.
    @Test func bundledMaterialsVsGlazy() throws {
        let r = try #require(reference.recipes.first { $0.glazyID == 240 })
        let b = try #require(refRecipe(r, map: { glazyToBundled[$0] }))
        let c = try GlazeCalculator.chemistry(of: b, library: lib, includeAdditions: true)
        let res = compare(r, c, mode: "frit-bundled-materials")
        for row in res.umf where row.oxide != "Fe2O3" {
            #expect(row.abs <= 0.003 && (row.rel ?? 0) <= 0.006, "\(row.oxide) \(row.frit) vs \(row.glazy)")
        }
        #expect(near(c.umf[.K2O], 0.2643, 0.001))
        #expect(near(c.umf[.CaO], 0.7357, 0.001))
        #expect(near(c.umf[.Fe2O3], 0.0875 * 100 / 95, 0.0005))
    }
}
