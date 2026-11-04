import Foundation
import Testing
@testable import GlazeCore

private func tile(_ recipe: Recipe, cone: String = "6", atmosphere: String = "Oxidation", notes: String = "",
                  day: Int = 14, code: String = "") -> TestTile {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    return TestTile(recipeID: recipe.id, cone: cone, atmosphere: atmosphere, schedule: [], notes: notes,
                    photoBookmark: nil, date: utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!,
                    code: code)
}

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func emptyBook(_ recipes: [Recipe] = []) -> GlazeBook {
    GlazeBook(recipes: recipes, customMaterials: [], tests: [], version: 1)
}

@Suite("Tile codes: generation and editing (F3)")
struct TileCodeGenerationTests {
    let r = recipe("Celadon", [("silica", 30), ("kaolin", 20), ("potash-feldspar", 50)])

    @Test("format pads to 3 digits and clamps")
    func format() {
        #expect(TileCode.format(1) == "T-001")
        #expect(TileCode.format(42) == "T-042")
        #expect(TileCode.format(1234) == "T-1234")
        #expect(TileCode.format(-5) == "T-000")
        #expect(TileCode.format(Int.max) == "T-\(GlazeBookValidation.maxTileNumber)")
        #expect(TileCode.number(of: " t-012 ") == 12)
        #expect(TileCode.number(of: "Cu-3a") == nil)
        #expect(TileCode.number(of: "T-") == nil)
        #expect(TileCode.number(of: "T-99999999999999999999") == nil)
    }

    @Test("codes are unique and increase; a deleted code is not given again")
    func uniqueAndNotReused() {
        var book = emptyBook([r])
        let codes = (0..<5).map { _ in TileCode.append(tile(r), to: &book) }
        #expect(codes == ["T-001", "T-002", "T-003", "T-004", "T-005"])
        #expect(Set(book.tests.map(\.code)).count == 5)
        #expect(book.nextTileNumber == 6)
        // Delete T-003, then the last tile too: the counter does not go back.
        book.tests.removeAll { $0.code == "T-003" || $0.code == "T-005" }
        #expect(TileCode.next(in: book) == "T-006")
        #expect(TileCode.append(tile(r), to: &book) == "T-006")
        #expect(!book.tests.contains { $0.code == "T-003" })
    }

    @Test("next skips a code that a tile already has, and stays bounded with many tiles")
    func skipsTaken() {
        var book = emptyBook([r])
        book.tests = [tile(r, code: "T-001"), tile(r, code: "t-002")]
        book.nextTileNumber = 1
        #expect(TileCode.next(in: book) == "T-003")
        // 2,000 taken codes in a row: the loop ends after them.
        book.tests = (1...2000).map { tile(r, code: TileCode.format($0)) }
        #expect(TileCode.next(in: book) == "T-2001")
    }

    @Test("a blend's tiles get consecutive codes in blend order")
    func blendCodesConsecutive() {
        var book = emptyBook([r])
        TileCode.append(tile(r), to: &book)
        var codes: [String] = []
        for n in 1...5 {
            var t = tile(r)
            t.notes = "Blend tile \(n)"
            codes.append(TileCode.append(t, to: &book))
        }
        #expect(codes == ["T-002", "T-003", "T-004", "T-005", "T-006"])
        #expect(book.tests.suffix(5).map(\.notes) == (1...5).map { "Blend tile \($0)" })
        #expect(TileCode.rangeText(codes) == "T-002 to T-006")
        #expect(TileCode.rangeText(["T-009"]) == "T-009")
        #expect(TileCode.rangeText([]) == "")
    }

    @Test("rename checks empty, length, characters and collisions (case ignored), and changes nothing on a problem")
    func renameChecks() {
        var book = emptyBook([r])
        TileCode.append(tile(r), to: &book)
        TileCode.append(tile(r), to: &book)
        let first = book.tests[0].id
        let before = book
        #expect(TileCode.rename(tileID: first, to: "   ", in: &book) == .empty)
        #expect(TileCode.rename(tileID: first, to: "ABCDEFGHIJKLM", in: &book) == .tooLong)
        #expect(TileCode.rename(tileID: first, to: "T\n1", in: &book) == .invalidCharacters)
        #expect(TileCode.rename(tileID: first, to: "T-1😀", in: &book) == .invalidCharacters)
        #expect(TileCode.rename(tileID: first, to: "t-002", in: &book) == .taken(code: "T-002"))
        #expect(TileCode.rename(tileID: first, to: " T-002 ", in: &book) == .taken(code: "T-002"))
        #expect(book == before)
        #expect(TileCode.message(.taken(code: "T-002")).contains("T-002"))
        #expect(TileCode.message(.tooLong).contains("12"))
    }

    @Test("rename to a free code trims it; the same code writes nothing; an unknown tile changes nothing")
    func renameWrites() {
        var book = emptyBook([r])
        TileCode.append(tile(r), to: &book)
        let id = book.tests[0].id
        #expect(TileCode.rename(tileID: id, to: "  Cu-3a ", in: &book) == nil)
        #expect(book.tests[0].code == "Cu-3a")
        let same = book
        #expect(TileCode.rename(tileID: id, to: "Cu-3a", in: &book) == nil)
        #expect(book == same)
        // Its own code in another case is not a collision with itself.
        #expect(TileCode.rename(tileID: id, to: "CU-3A", in: &book) == nil)
        #expect(book.tests[0].code == "CU-3A")
        let before = book
        #expect(TileCode.rename(tileID: UUID(), to: "X-1", in: &book) == nil)
        #expect(book == before)
    }

    @Test("a typed T-n code moves the next code past it, up to the counted limit")
    func renameMovesCounter() {
        var book = emptyBook([r])
        TileCode.append(tile(r), to: &book)
        TileCode.append(tile(r), to: &book)
        #expect(TileCode.rename(tileID: book.tests[0].id, to: "T-050", in: &book) == nil)
        // Round 3 (R1 F4): the stored counter moves when a code is given or saved, not on a rename.
        #expect(book.nextTileNumber == 3)
        #expect(TileCode.next(in: book) == "T-051")
        #expect(TileCode.append(tile(r), to: &book) == "T-051")
        // A lower typed number does not move it back.
        #expect(TileCode.rename(tileID: book.tests[1].id, to: "T-010", in: &book) == nil)
        #expect(book.nextTileNumber == 52)
        // A huge typed number does not push the counter toward the file limit.
        #expect(TileCode.rename(tileID: book.tests[1].id, to: "T-99999999", in: &book) == nil)
        #expect(book.nextTileNumber == 52)
    }

    @Test("duplicates from a hand-edited file are listed once each")
    func duplicates() {
        let tests = [tile(r, code: "T-001"), tile(r, code: "t-001"), tile(r, code: "T-001"), tile(r, code: "T-002"),
                     tile(r, code: "")]
        #expect(TileCode.duplicates(in: tests) == ["t-001"])
        #expect(TileCode.duplicates(in: [tile(r, code: "A"), tile(r, code: "B")]).isEmpty)
    }
}

@Suite("Tile codes: migration of older books (F3)")
struct TileCodeMigrationTests {
    /// A book as Frit 1.2 (main cb41103) writes it: no "code" and no "nextTileNumber". Three tiles, a custom
    /// material, a photo link and a firing schedule, so every field is checked.
    static let oldBook = """
    {
      "customMaterials" : [
        {
          "analysis" : {
            "CaO" : 40.5,
            "SiO2" : 30.25
          },
          "id" : "custom-1",
          "loi" : 12.5,
          "name" : "Local ash",
          "source" : "Own analysis"
        }
      ],
      "recipes" : [
        {
          "cone" : "6",
          "id" : "0D7D0B76-6A43-4B0C-8F1B-6A0C0E000001",
          "lines" : [
            {
              "amount" : 60,
              "id" : "0D7D0B76-6A43-4B0C-8F1B-6A0C0E000002",
              "isAddition" : false,
              "materialID" : "custom-1"
            },
            {
              "amount" : 40,
              "id" : "0D7D0B76-6A43-4B0C-8F1B-6A0C0E000003",
              "isAddition" : false,
              "materialID" : "kaolin"
            }
          ],
          "name" : "Ash glaze",
          "notes" : "Old book"
        }
      ],
      "tests" : [
        {
          "atmosphere" : "Wood",
          "cone" : "10",
          "date" : "2026-08-01T12:00:00Z",
          "id" : "0D7D0B76-6A43-4B0C-8F1B-6A0C0E000010",
          "notes" : "First",
          "photoBookmark" : "AQID+g==",
          "recipeID" : "0D7D0B76-6A43-4B0C-8F1B-6A0C0E000001",
          "schedule" : [
            {
              "holdMinutes" : 10,
              "ratePerHour" : 60,
              "targetC" : 1220
            }
          ]
        },
        {
          "atmosphere" : "Oxidation",
          "cone" : "6",
          "date" : "2026-08-02T12:00:00Z",
          "id" : "0D7D0B76-6A43-4B0C-8F1B-6A0C0E000011",
          "notes" : "Second",
          "recipeID" : "0D7D0B76-6A43-4B0C-8F1B-6A0C0E000001",
          "schedule" : []
        },
        {
          "atmosphere" : "Reduction",
          "cone" : "10",
          "date" : "2026-08-03T12:00:00Z",
          "id" : "0D7D0B76-6A43-4B0C-8F1B-6A0C0E000012",
          "notes" : "Third",
          "recipeID" : "0D7D0B76-6A43-4B0C-8F1B-6A0C0E000099",
          "schedule" : []
        }
      ],
      "version" : 1
    }
    """

    @Test("an older book decodes with empty codes, and open gives T-001 to T-003 in book order")
    func openBackfills() throws {
        let data = Data(Self.oldBook.utf8)
        let decoded = try GlazeBookCodec.decode(data)
        #expect(decoded.tests.map(\.code) == ["", "", ""])
        #expect(decoded.nextTileNumber == 1)
        let opened = try GlazeBookCodec.open(data)
        #expect(opened.tests.map(\.code) == ["T-001", "T-002", "T-003"])
        #expect(opened.nextTileNumber == 4)
        #expect(opened.version == 1)
        // The same file gives the same codes each time it opens.
        #expect(try GlazeBookCodec.open(data) == opened)
    }

    @Test("no data is lost: every field except the new code is the same as the plain decode")
    func noDataLoss() throws {
        let data = Data(Self.oldBook.utf8)
        let decoded = try GlazeBookCodec.decode(data)
        var opened = try GlazeBookCodec.open(data)
        #expect(opened.recipes == decoded.recipes)
        #expect(opened.customMaterials == decoded.customMaterials)
        #expect(opened.tests[0].photoBookmark == Data([1, 2, 3, 250]))
        #expect(opened.tests[0].schedule == [FiringSegment(ratePerHour: 60, targetC: 1220, holdMinutes: 10)])
        #expect(opened.tests[2].recipeID.uuidString.hasSuffix("0099"))
        for i in opened.tests.indices { opened.tests[i].code = "" }
        opened.nextTileNumber = 1
        #expect(opened == decoded)
    }

    @Test("after open, save and open again the bytes and values are the same")
    func saveAfterOpenIsStable() throws {
        let opened = try GlazeBookCodec.open(Data(Self.oldBook.utf8))
        let saved = try GlazeBookCodec.encode(opened)
        let reopened = try GlazeBookCodec.open(saved)
        #expect(reopened == opened)
        #expect(try GlazeBookCodec.encode(reopened) == saved)
    }

    @Test("a book whose tiles all have codes opens with the same values as a plain decode")
    func openIsIdentityWithCodes() throws {
        let book = SampleBook.make()
        let data = try GlazeBookCodec.encode(book)
        #expect(try GlazeBookCodec.open(data) == book)
        #expect(try GlazeBookCodec.decode(data) == book)
    }

    @Test("a partly coded book keeps its codes and fills the rest after the highest T-n code")
    func mixedBackfill() {
        let r = recipe("A", [("silica", 1)])
        var book = emptyBook([r])
        book.tests = [tile(r, code: ""), tile(r, code: "T-010"), tile(r, code: "Cu-3a"), tile(r, code: " ")]
        TileCode.backfill(&book)
        #expect(book.tests.map(\.code) == ["T-011", "T-010", "Cu-3a", "T-012"])
        #expect(book.nextTileNumber == 13)
        let again = book
        TileCode.backfill(&book)
        #expect(book == again)
    }

    @Test("a tile counter out of range is refused with a message, not a crash")
    func counterValidated() throws {
        var book = SampleBook.make()
        book.nextTileNumber = GlazeBookValidation.maxTileNumber + 1
        let data = try GlazeBookCodec.encode(book)
        #expect(throws: GlazeBookError.self) { try GlazeBookCodec.open(data) }
        book.nextTileNumber = -1
        let negative = try GlazeBookCodec.encode(book)
        #expect(throws: GlazeBookError.self) { try GlazeBookCodec.decode(negative) }
        // The highest allowed counter still gives a code without overflow.
        book.nextTileNumber = GlazeBookValidation.maxTileNumber
        let code = TileCode.append(tile(book.recipes[0]), to: &book)
        #expect(code.hasPrefix("T-"))
        #expect(Set(book.tests.map(\.code)).count == book.tests.count)
    }
}

@Suite("Test search (F3)")
struct TestSearchTests {
    let celadon = recipe("Céladon Blue", [("potash-feldspar", 40), ("whiting", 20), ("kaolin", 20), ("silica", 20)])
    let shino = recipe("Carbon Shino", [("soda-feldspar", 60), ("kaolin", 40)], cone: "10")

    var tests: [TestTile] {
        [tile(celadon, code: "T-001"),
         tile(celadon, cone: "06", notes: "Crawled at the foot", day: 15, code: "T-002"),
         tile(shino, cone: "10", atmosphere: "Reduction", notes: "Carbon trap", day: 20, code: "T-003"),
         tile(celadon, cone: "6", atmosphere: "Reduction", notes: "pinholes", day: 21, code: "Cu-3a")]
    }

    private func codes(_ query: String, cone: String? = nil, atmosphere: String? = nil) -> [String] {
        TestSearch.filter(tests, recipes: [celadon, shino], materialNames: TestSearch.materialNames(lib),
                          query: query, cone: cone, atmosphere: atmosphere, calendar: utc).map(\.code)
    }

    @Test("by code, with or without the hyphen, in any case")
    func byCode() {
        #expect(codes("t-002") == ["T-002"])
        #expect(codes("T002") == ["T-002"])
        #expect(codes("cu-3A") == ["Cu-3a"])
        // Without the leading zeros, as a potter may write it on a tile.
        #expect(codes("T-2") == ["T-002"])
        #expect(codes("t-3 shino") == ["T-003"])
    }

    @Test("by recipe name, ignoring case and accents")
    func byRecipe() {
        #expect(codes("celadon") == ["T-001", "T-002", "Cu-3a"])
        #expect(codes("SHINO") == ["T-003"])
    }

    @Test("by material in the tile's recipe")
    func byMaterial() {
        #expect(codes("soda feldspar") == ["T-003"])
        #expect(codes("whiting") == ["T-001", "T-002", "Cu-3a"])
    }

    @Test("by note text, atmosphere and date; every word must match")
    func byNotesAndMore() {
        #expect(codes("crawled") == ["T-002"])
        #expect(codes("reduction") == ["T-003", "Cu-3a"])
        #expect(codes("reduction pinholes") == ["Cu-3a"])
        #expect(codes("2026-09-20") == ["T-003"])
        #expect(codes("nothing-like-this").isEmpty)
    }

    @Test("\"cone 6\" matches cone 6 only, not 06 or 10")
    func byCone() {
        #expect(codes("cone 6") == ["T-001", "Cu-3a"])
        #expect(codes("Cone 06") == ["T-002"])
        #expect(codes("cone 10 carbon") == ["T-003"])
    }

    @Test("empty query gives all tiles; cone and atmosphere filters are exact")
    func filters() {
        #expect(codes("  ").count == 4)
        #expect(codes("", cone: "10") == ["T-003"])
        #expect(codes("", atmosphere: "reduction") == ["T-003", "Cu-3a"])
        #expect(codes("celadon", cone: "6", atmosphere: "Oxidation") == ["T-001"])
    }

    @Test("a deleted recipe is found as \"Deleted recipe\"")
    func deletedRecipe() {
        let orphan = tile(recipe("Gone", [("silica", 1)]), code: "T-009")
        let hits = TestSearch.filter([orphan], recipes: [], query: "deleted", calendar: utc)
        #expect(hits.map(\.code) == ["T-009"])
    }

    @Test("an exact code selects one tile; a code shared by two selects none")
    func exactCode() {
        #expect(TestSearch.exactCode(" t-003 ", in: tests)?.code == "T-003")
        #expect(TestSearch.exactCode("T-00", in: tests) == nil)
        #expect(TestSearch.exactCode("t-2", in: tests)?.code == "T-002")
        // A code typed as written wins over the number match.
        let both = tests + [tile(celadon, code: "T-2")]
        #expect(TestSearch.exactCode("T-2", in: both)?.code == "T-2")
        #expect(TestSearch.exactCode("", in: tests) == nil)
        let twice = tests + [tile(celadon, code: "t-003")]
        #expect(TestSearch.exactCode("T-003", in: twice) == nil)
    }
}

@Suite("Label layout (F3)")
struct LabelLayoutTests {
    @Test("31 labels at 3 x 10 give two pages of 30 and 1")
    func pages31() {
        let pages = LabelLayout.pages(count: 31, columns: 3, rows: 10)
        #expect(pages.map(\.count) == [30, 1])
        #expect(pages.flatMap { $0 } == Array(0..<31))
    }

    @Test("skip starts the first page later; it is clamped to the page")
    func skip() {
        #expect(LabelLayout.pages(count: 5, columns: 3, rows: 10, skip: 28).map(\.count) == [2, 3])
        #expect(LabelLayout.slot(itemOnPage: 0, page: 0, skip: 28, perPage: 30) == 28)
        #expect(LabelLayout.slot(itemOnPage: 0, page: 1, skip: 28, perPage: 30) == 0)
        #expect(LabelLayout.pages(count: 2, columns: 3, rows: 10, skip: 99).map(\.count) == [1, 1])
        #expect(LabelLayout.pages(count: 2, columns: 3, rows: 10, skip: -4).map(\.count) == [2])
    }

    @Test("no pages for no labels or a bad grid")
    func degenerate() {
        #expect(LabelLayout.pages(count: 0, columns: 3, rows: 10).isEmpty)
        #expect(LabelLayout.pages(count: 5, columns: 0, rows: 10).isEmpty)
        #expect(LabelLayout.pages(count: 5, columns: 3, rows: -1).isEmpty)
        #expect(LabelLayout.slot(itemOnPage: 3, page: 0, skip: 0, perPage: 0) == 0)
    }

    @Test("every label of each sheet is inside the page and no two labels overlap")
    func sheetsFit() {
        for sheet in LabelLayout.sheets {
            let frames = (0..<sheet.perPage).map { sheet.frame(slot: $0) }
            for f in frames {
                #expect(f.x >= 0 && f.y >= 0, "\(sheet.id)")
                #expect(f.x + f.width <= sheet.pageWidth + 1e-9, "\(sheet.id)")
                #expect(f.y + f.height <= sheet.pageHeight + 1e-9, "\(sheet.id)")
                #expect(f.width.isFinite && f.height.isFinite && f.width > 0 && f.height > 0)
            }
            for i in frames.indices {
                for j in frames.indices where j > i {
                    let a = frames[i], b = frames[j]
                    let overlap = a.x < b.x + b.width - 1e-9 && b.x < a.x + a.width - 1e-9
                        && a.y < b.y + b.height - 1e-9 && b.y < a.y + a.height - 1e-9
                    #expect(!overlap, "\(sheet.id) slots \(i) and \(j)")
                }
            }
        }
        #expect(LabelLayout.letter30.perPage == 30)
        #expect(LabelLayout.a4x21.perPage == 21)
        // Letter sheet: 0.5 in top margin, 3 columns 2.75 in apart.
        #expect(LabelLayout.letter30.frame(slot: 4) == (x: 13.5 + 198, y: 36 + 72, width: 189, height: 72))
    }

    @Test("label text has the code, recipe, cone, atmosphere and date")
    func labelText() {
        let r = recipe("Millpond Clear", [("silica", 1)])
        let t = LabelLayout.text(for: tile(r, code: "T-002"), recipes: [r], calendar: utc)
        #expect(t == LabelLayout.Text(code: "T-002", recipe: "Millpond Clear", details: "Cone 6 · Oxidation · 2026-09-14"))
        let orphan = LabelLayout.text(for: tile(r, atmosphere: "", code: ""), recipes: [], calendar: utc)
        #expect(orphan == LabelLayout.Text(code: "No code", recipe: "Deleted recipe", details: "Cone 6 · 2026-09-14"))
    }
}

@Suite("Tile codes: offline and sample (F3)")
struct TileCodeOfflineTests {
    @Test("the new F3 sources make no network calls")
    func noNetwork() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        for rel in ["Sources/GlazeCore/TileCodes.swift", "Sources/GlazeApp/LabelSheet.swift", "Sources/GlazeApp/TestLogView.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            for bad in ["URLSession", "NWConnection", "http://", "https://", "URLRequest"] {
                #expect(!text.contains(bad), "\(rel) contains \(bad)")
            }
        }
    }

    @Test("the sample book's tile counter gives T-004 next")
    func sampleNext() {
        let book = SampleBook.make()
        #expect(book.tests.map(\.code) == ["T-001", "T-002", "T-003"])
        #expect(TileCode.next(in: book) == "T-004")
        #expect(TileCode.duplicates(in: book.tests).isEmpty)
    }
}
