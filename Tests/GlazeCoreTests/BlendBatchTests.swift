import Foundation
import Testing
@testable import GlazeCore

private let A = recipe("A", [("potash-feldspar", 40), ("silica", 30), ("whiting", 20), ("kaolin", 10)])
private let B = recipe("B", [("soda-feldspar", 50), ("silica", 25), ("wollastonite", 25)], additions: [("red-iron-oxide", 4)])
private let C = recipe("C", [("talc", 20), ("kaolin", 30), ("silica", 50)])
private let D = recipe("D", [("dolomite", 25), ("kaolin", 25), ("silica", 50)])

@Suite("Blend")
struct BlendTests {
    @Test func lineEndpointsAndCount() {
        let tiles = Blend.line(A, B, steps: 5)
        #expect(tiles.count == 5)
        #expect(amounts(tiles[0]) == amounts(A))
        let last = amounts(tiles[4])
        for (k, v) in amounts(B) { #expect(abs((last[k] ?? 0) - v) < 1e-9) }
        #expect(last["potash-feldspar"] == nil)
    }

    @Test func lineMidpoint() {
        let mid = amounts(Blend.line(A, B, steps: 3)[1])
        #expect(abs(mid["silica"]! - 27.5) < 1e-9)
        #expect(abs(mid["potash-feldspar"]! - 20) < 1e-9)
        #expect(abs(mid["soda-feldspar"]! - 25) < 1e-9)
        let add = amounts(Blend.line(A, B, steps: 3)[1], additions: true)
        #expect(abs(add["red-iron-oxide"]! - 2) < 1e-9)
    }

    @Test func lineDegenerateSteps() {
        #expect(Blend.line(A, B, steps: 0).isEmpty)
        #expect(Blend.line(A, B, steps: 1).count == 1)
    }

    @Test func lineNormalizesBaseTo100() {
        let big = recipe("big", [("silica", 300), ("whiting", 700)])
        let t = Blend.line(big, A, steps: 2)
        #expect(abs(amounts(t[0]).values.reduce(0, +) - 100) < 1e-9)
    }

    @Test(arguments: [(1, 3), (2, 6), (3, 10), (4, 15), (5, 21), (6, 28)])
    func triaxialCounts(divisions: Int, expected: Int) {
        #expect(Blend.triaxial(A, B, C, divisions: divisions).count == expected)
    }

    @Test func triaxialCornersAndCentroid() {
        let tiles = Blend.triaxial(A, B, C, divisions: 3)
        let all = tiles.map { amounts($0) }
        #expect(all.contains { $0 == amounts(A) })
        #expect(all.contains { $0 == amounts(C) })
        // centroid (1/3 each): silica = (30 + 25 + 50) / 3 = 35
        #expect(all.contains { abs(($0["silica"] ?? 0) - 35) < 1e-9 && abs(($0["talc"] ?? 0) - 20.0 / 3) < 1e-9 })
        #expect(Set(tiles.map(\.id)).count == tiles.count)
    }

    @Test func triaxialNegativeIsEmpty() {
        #expect(Blend.triaxial(A, B, C, divisions: -1).isEmpty)
    }

    @Test func gridCountAndCorners() {
        let tiles = Blend.grid(corners: [A, B, C, D], rows: 5, columns: 7)
        #expect(tiles.count == 35)
        #expect(amounts(tiles[0]) == amounts(A))          // top left
        #expect(amounts(tiles[6]).keys.sorted() == amounts(B).keys.sorted())    // top right
        #expect(amounts(tiles[28]) == amounts(C))         // bottom left
        #expect(amounts(tiles[34]) == amounts(D))         // bottom right
    }

    @Test func gridCenterIsBilinear() {
        let tiles = Blend.grid(corners: [A, B, C, D], rows: 3, columns: 3)
        let center = amounts(tiles[4])
        // silica: (30 + 25 + 50 + 50) / 4 = 38.75; kaolin (10 + 0 + 30 + 25) / 4 = 16.25
        #expect(abs(center["silica"]! - 38.75) < 1e-9)
        #expect(abs(center["kaolin"]! - 16.25) < 1e-9)
    }

    @Test func gridNeedsFourCorners() {
        #expect(Blend.grid(corners: [A, B, C], rows: 3, columns: 3).isEmpty)
        #expect(Blend.grid(corners: [A, B, C, D], rows: 0, columns: 3).isEmpty)
    }
}

@Suite("Batch")
struct BatchTests {
    @Test func scaleBaseToTotal() {
        let out = Batch.scale(A, totalGrams: 2500, precision: 0.1)
        #expect(out.map(\.materialID) == ["potash-feldspar", "silica", "whiting", "kaolin"])
        #expect(out.map(\.grams) == [1000, 750, 500, 250])
    }

    @Test func additionsScaleProportionally() {
        let out = Batch.scale(B, totalGrams: 500, precision: 0.1)
        #expect(out.map(\.grams).prefix(3).reduce(0, +) == 500)
        #expect(out.last!.materialID == "red-iron-oxide")
        #expect(out.last!.grams == 20)      // 4 % of 500
    }

    @Test func precisionRounding() {
        let r = recipe([("silica", 33.333), ("whiting", 33.333), ("kaolin", 33.334)])
        let out = Batch.scale(r, totalGrams: 1000, precision: 0.5)
        for p in out { #expect(abs(p.grams * 2 - (p.grams * 2).rounded()) < 1e-9) }
        #expect(out[0].grams == 333.5)
        let tenth = Batch.scale(recipe([("silica", 1), ("whiting", 2)]), totalGrams: 100, precision: 0.1)
        #expect(tenth.map(\.grams) == [33.3, 66.7])
        let whole = Batch.scale(recipe([("silica", 1), ("whiting", 2)]), totalGrams: 100, precision: 1)
        #expect(whole.map(\.grams) == [33, 67])
    }

    @Test func zeroPrecisionMeansNoRounding() {
        let out = Batch.scale(recipe([("silica", 1), ("whiting", 2)]), totalGrams: 100, precision: 0)
        #expect(abs(out[0].grams - 100.0 / 3) < 1e-9)
    }

    @Test func emptyOrAdditionsOnlyGivesNothing() {
        #expect(Batch.scale(recipe([]), totalGrams: 100, precision: 0.1).isEmpty)
        #expect(Batch.scale(recipe([], additions: [("red-iron-oxide", 2)]), totalGrams: 100, precision: 0.1).isEmpty)
    }
}

@Suite("Documents")
struct DocumentTests {
    @Test func glazeBookRoundTrip() throws {
        let tile = TestTile(recipeID: A.id, cone: "6", atmosphere: "Oxidation",
                            schedule: [FiringSegment(ratePerHour: 150, targetC: 1220, holdMinutes: 10)],
                            notes: "n", photoBookmark: nil, date: Date(timeIntervalSince1970: 1_000_000))
        let book = GlazeBook(recipes: [A, B], customMaterials: [lib.material(id: "talc")!], tests: [tile], version: 1)
        let data = try JSONEncoder().encode(book)
        let back = try JSONDecoder().decode(GlazeBook.self, from: data)
        #expect(back.recipes == book.recipes)
        #expect(back.customMaterials == book.customMaterials)
        #expect(back.tests == book.tests)
        #expect(back.version == 1)
    }
}

@Suite("Rows without a material")
struct RowsWithoutMaterialTests {
    // W6 F3: an unnamed row with an amount was silently left out of the chemistry but printed in the batch.
    @Test func unnamedRowWithAmountIsFlagged() {
        var r = recipe([("whiting", 20), ("silica", 30)])
        #expect(r.linesWithoutMaterial.isEmpty)
        #expect(RecipeCheck.chemistryNote(r) == nil)
        #expect(RecipeCheck.batchBlockReason(r) == nil)

        r.lines.append(RecipeLine(materialID: "", amount: 0, isAddition: false)) // a new empty row is fine
        #expect(r.linesWithoutMaterial.isEmpty)
        #expect(RecipeCheck.batchBlockReason(r) == nil)

        r.lines.append(RecipeLine(materialID: "", amount: 15, isAddition: false))
        #expect(r.linesWithoutMaterial.count == 1)
        #expect(RecipeCheck.isMissingMaterial(r.lines[3]))
        #expect(!RecipeCheck.isMissingMaterial(r.lines[0]))
        #expect(RecipeCheck.chemistryNote(r)?.contains("1 row has an amount but no material") == true)
        #expect(RecipeCheck.chemistryNote(r)?.contains("leaves it out") == true)
        #expect(RecipeCheck.batchBlockReason(r)?.contains("print or export") == true)

        r.lines.append(RecipeLine(materialID: "  ", amount: 2, isAddition: true))
        #expect(RecipeCheck.chemistryNote(r)?.hasPrefix("2 rows have") == true)
    }

    // The batch sheet's source code blocks Print and Export PDF while a row has no material.
    @Test func batchSheetBlocksPrintAndExport() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/GlazeApp/BatchSheet.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("RecipeCheck.batchBlockReason(recipe)"))
        #expect(text.components(separatedBy: ".disabled(rows.isEmpty || blockReason != nil)").count == 3)
    }
}
