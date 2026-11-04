import Foundation
import Testing
@testable import GlazeCore

/// G5 defect 1: opening a book must not change it. These tests cover the model side:
/// the file round-trips byte for byte, and the binding helpers do not write unchanged values.
@Suite("Open without edit")
struct OpenWithoutEditTests {
    private func bookWithEverything() -> GlazeBook {
        var book = SampleBook.make()
        let tile = TestTile(recipeID: book.recipes[0].id, cone: "6", atmosphere: "Oxidation",
                            schedule: [FiringSegment(ratePerHour: 150, targetC: 600, holdMinutes: 0),
                                       FiringSegment(ratePerHour: 60, targetC: 1220, holdMinutes: 10)],
                            notes: "Tile 1 – glossy, ½ dip", photoBookmark: Data([1, 2, 3, 250]),
                            date: Date(timeIntervalSince1970: 1_792_600_000))
        book.tests = [tile]
        book.customMaterials = [Material(id: "custom-1", name: "Local ash", analysis: [.CaO: 40.5, .SiO2: 30.25, .K2O: 8],
                                         loi: 12.5, source: "Own analysis")]
        return book
    }

    @Test("decode then encode gives the same bytes")
    func roundTripBytes() throws {
        let data = try GlazeBookCodec.encode(bookWithEverything())
        let again = try GlazeBookCodec.encode(GlazeBookCodec.decode(data))
        #expect(again == data)
    }

    @Test("decoded book equals the original, so an unchanged write-back is detected")
    func roundTripValue() throws {
        let book = bookWithEverything()
        let decoded = try GlazeBookCodec.decode(GlazeBookCodec.encode(book))
        #expect(decoded == book)
    }

    @Test("a sample file written by the QA generator round-trips byte for byte")
    func fileRoundTrip() throws {
        // Files are written with GlazeBookCodec; a book read from disk and saved again must not change.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("g9-roundtrip-\(UUID().uuidString).glazebook")
        defer { try? FileManager.default.removeItem(at: url) }
        try GlazeBookCodec.encode(bookWithEverything()).write(to: url)
        let onDisk = try Data(contentsOf: url)
        #expect(try GlazeBookCodec.encode(GlazeBookCodec.decode(onDisk)) == onDisk)
    }

    @Test("assign does not write an equal value")
    func assignEqual() {
        var book = bookWithEverything()
        let same = book
        #expect(Edit.assign(same, to: &book) == false)
        var changed = same
        changed.recipes[0].name = "Renamed"
        #expect(Edit.assign(changed, to: &book) == true)
        #expect(book.recipes[0].name == "Renamed")
    }

    @Test("indexToReplace is nil for an unchanged or unknown element")
    func indexToReplace() {
        let recipes = SampleBook.make().recipes
        #expect(Edit.indexToReplace(recipes[2], in: recipes) == nil)
        var edited = recipes[2]
        edited.lines[0].amount += 1
        #expect(Edit.indexToReplace(edited, in: recipes) == 2)
        let unknown = Recipe(name: "x", cone: "6", lines: [])
        #expect(Edit.indexToReplace(unknown, in: recipes) == nil)
    }
}

@Suite("Oxide text")
struct OxideTextTests {
    @Test("formulas in warnings get subscripts, other words stay")
    func subscripted() {
        #expect(OxideText.subscripted("Expansion estimate excludes B2O3 (no constant Appen coefficient).")
                == "Expansion estimate excludes B₂O₃ (no constant Appen coefficient).")
        #expect(OxideText.subscripted("No Al2O3: the SiO2:Al2O3 ratio is not defined (shown as 0).")
                == "No Al₂O₃: the SiO₂:Al₂O₃ ratio is not defined (shown as 0).")
        #expect(OxideText.subscripted("Unknown material id \"custom-2\": line ignored.")
                == "Unknown material id \"custom-2\": line ignored.")
        #expect(Oxide.Fe2O3.formula == "Fe₂O₃")
    }
}

@Suite("Sample names")
struct SampleNameTests {
    @Test("sample names agree with the Stull chart, or the notes explain why not")
    func namesMatchChart() throws {
        let book = SampleBook.make()
        #expect(book.recipes.count == 6)
        for r in book.recipes {
            let c = try chem(r)
            let region = Stull.region(siO2: c.umf[.SiO2] ?? 0, al2O3: c.umf[.Al2O3] ?? 0)
            let name = r.name.lowercased()
            if name.contains("gloss") || name.contains("clear") { #expect(region == .gloss, "\(r.name): \(region)") }
            if name.contains("matte") { #expect(region == .matte || region == .semimatte, "\(r.name): \(region)") }
            if region == .gloss && (name.contains("satin") || r.notes.lowercased().contains("stony")) {
                #expect(r.notes.contains("Stull chart does not show"), "\(r.name)")
            }
            #expect(!r.name.contains("(sample)"))
            #expect(r.notes.hasPrefix("Sample recipe."))
        }
    }

    @Test("every sample is inside the default reference set for every listed oxide")
    func samplesInDefaultRange() throws {
        // The app shows Limits.bundled.first when no set is chosen (ChemistryPanel).
        let defaultSet = try #require(Limits.bundled.first)
        #expect(defaultSet.id == "hr-cone6")
        for r in SampleBook.make().recipes {
            #expect(r.cone == "6")
            for additions in [false, true] {
                let c = try chem(r, additions: additions)
                let out = Limits.check(c, against: defaultSet).filter { !$0.value }.map(\.key.rawValue).sorted()
                #expect(out.isEmpty, "\(r.name) additions=\(additions): out of range \(out)")
            }
        }
    }

    @Test("no food-safety wording in the sample book")
    func noSafetyWording() {
        for r in SampleBook.make().recipes {
            let text = (r.name + " " + r.notes).lowercased()
            for bad in ["food safe", "food-safe", "lead free", "lead-free", "non-toxic", "nontoxic", "dinnerware safe"] {
                #expect(!text.contains(bad), "\(r.name)")
            }
        }
    }
}
