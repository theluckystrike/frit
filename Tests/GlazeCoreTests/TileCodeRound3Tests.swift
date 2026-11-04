import Foundation
import Testing
@testable import GlazeCore

/// F3 fix round 3, from the R1 review (F1 to F5). Written before the fixes and run against the old behavior first
/// (`F3/logs/round3-failing-first.log`).
@Suite("Tile codes: fix round 3 (F3)")
struct TileCodeRound3Tests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func tileFor(_ book: GlazeBook, code: String = "", notes: String = "") -> TestTile {
        TestTile(recipeID: book.recipes[0].id, cone: "6", atmosphere: "Oxidation", schedule: [], notes: notes,
                 photoBookmark: nil, date: Date(timeIntervalSince1970: 1_792_600_000), code: code)
    }

    private func coded(_ n: Int) -> GlazeBook {
        var book = SampleBook.make()
        book.tests = []
        book.nextTileNumber = 1
        for _ in 0..<n { TileCode.append(tileFor(book), to: &book) }
        return book
    }

    private func savedJSON(_ book: GlazeBook) throws -> String {
        String(decoding: try GlazeBookCodec.save(book, ledger: TileCodeLedger(book: book)), as: UTF8.self)
    }

    // R1 F1 (Medium): Frit 1.0 to 1.2 read format 1 and drop the new keys on save. They refuse a higher format
    // ("This version of Frit reads format 1 ... The file was not changed."), so a book with codes is format 2.

    @Test("1: a book with tile codes is saved as format 2, which Frit 1.0 to 1.2 refuse without a rewrite")
    func codedBookIsFormat2() throws {
        let text = try savedJSON(coded(3))
        #expect(text.contains("\"version\" : 2"))
        let back = try GlazeBookCodec.decode(Data(text.utf8))
        #expect(back.version == 2)
        #expect(back.tests.map(\.code) == ["T-001", "T-002", "T-003"])
        // What Frit 1.0 to 1.2 do with it: their check is "version > 1 is refused".
        #expect(back.version > 1)
    }

    @Test("1: a book whose tiles were all deleted keeps its counter, so it is format 2 too; a book never coded stays 1")
    func formatFollowsCodeData() throws {
        var book = coded(3)
        book.tests = []
        let text = try savedJSON(book)
        #expect(text.contains("\"version\" : 2"))
        #expect(text.contains("\"nextTileNumber\" : 4"))
        let plain = GlazeBook(recipes: SampleBook.make().recipes, customMaterials: [], tests: [], version: 1)
        #expect(try savedJSON(plain).contains("\"version\" : 1"))
    }

    @Test("1: format 1 and 2 open; format 3 is refused with the update message")
    func formatRange() throws {
        #expect(GlazeBookValidation.supportedVersion == 2)
        var b = SampleBook.make()
        b.version = 3
        #expect(throws: GlazeBookError.unsupportedVersion(found: 3, supported: 2)) {
            try GlazeBookCodec.decode(GlazeBookCodec.encode(b))
        }
    }

    @Test("1: a format-2 book that comes back with tiles missing their codes keeps the others and says so once")
    func missingCodesAreReported() throws {
        var book = coded(4)
        try #require(TileCode.rename(tileID: book.tests[1].id, to: "BLUE-1", in: &book) == nil)
        book.tests[2].code = ""                 // lost outside Frit
        book.version = 2
        let (opened, notice) = try GlazeBookCodec.openReport(GlazeBookCodec.encode(book))
        #expect(opened.tests.map(\.code) == ["T-001", "BLUE-1", "T-005", "T-004"])
        #expect(notice == TileCode.BackfillNotice(kind: .missingCodes, codes: ["T-005"]))
        #expect(notice.map(TileCode.noticeText)?.contains("Frit gave it a new code (T-005)") == true)
        let two = TileCode.noticeText(TileCode.BackfillNotice(kind: .missingCodes, codes: ["T-005", "T-006"]))
        #expect(two.hasPrefix("2 test tiles in this book had lost their codes"))
        #expect(two.contains("(T-005 to T-006)"))
    }

    @Test("1: an older format-1 book gets codes in tile order and a one-time note; a coded book gets none")
    func olderBookNotice() throws {
        let (_, notice) = try GlazeBookCodec.openReport(Data(TileCodeMigrationTests.oldBook.utf8))
        #expect(notice == TileCode.BackfillNotice(kind: .olderBook, codes: ["T-001", "T-002", "T-003"]))
        let (_, none) = try GlazeBookCodec.openReport(GlazeBookCodec.encode(coded(2)))
        #expect(none == nil)
    }

    // R1 F2: "cone <word>" took any word as a cone.

    @Test("2: \"cone pack\" searches the words, because pack is not a cone; \"cone 6\" is still a cone")
    func coneWordOnlyForCones() {
        var book = coded(0)
        TileCode.append(tileFor(book, notes: "Slumped the witness cone pack"), to: &book)
        TileCode.append(tileFor(book, notes: "Glossy"), to: &book)
        let hits = TestSearch.filter(book.tests, recipes: book.recipes, query: "cone pack").map(\.code)
        #expect(hits == ["T-001"])
        #expect(TestSearch.filter(book.tests, recipes: book.recipes, query: "cone 6").count == 2)
        #expect(TestSearch.filter(book.tests, recipes: book.recipes, query: "cone 10").isEmpty)
        #expect(TestSearch.filter(book.tests, recipes: book.recipes, query: "CONE glossy").map(\.code) == ["T-002"])
    }

    // R1 F3: "T-5" and "T-005" are the same tile number.

    @Test("3: a code with the same tile number as another tile is refused (T-5 against T-005)")
    func sameNumberRefused() {
        var book = coded(5)
        #expect(TileCode.problem(with: "T-5", forTile: book.tests[0].id, in: book) == .taken(code: "T-005"))
        #expect(TileCode.problem(with: "t-0005", forTile: book.tests[0].id, in: book) == .taken(code: "T-005"))
        // Its own number in another form is fine.
        #expect(TileCode.problem(with: "T-5", forTile: book.tests[4].id, in: book) == nil)
        book.tests[0].code = "T-5"              // a file edited outside Frit
        #expect(TileCode.duplicates(in: book.tests) == ["T-005"])
    }

    @Test("3: a new code skips a number that a tile has in another form")
    func nextSkipsSameNumber() {
        var book = coded(4)
        book.tests[3].code = "T-5"
        book.nextTileNumber = 5
        #expect(TileCode.next(in: book) == "T-006")
    }

    // R1 F4: half-typed codes raised the counter for good.

    @Test("4: typing T-0500 and then fixing it to T-050 leaves no gap: the next code is T-051")
    func halfTypedDoesNotMoveCounter() throws {
        var book = coded(3)
        let id = book.tests[2].id
        for draft in ["T-0", "T-05", "T-050", "T-0500", "T-050"] {
            TileCode.liveEdit(tileID: id, draft: draft, original: "T-003", in: &book)
        }
        #expect(book.tests[2].code == "T-050")
        #expect(TileCode.next(in: book) == "T-051")
        let saved = try GlazeBookCodec.decode(GlazeBookCodec.save(book, ledger: TileCodeLedger(book: coded(3))))
        #expect(saved.nextTileNumber == 51)
    }

    // R1 F5: Add Test, Undo, close (no save: the undo count is back at the saved state), reopen gave T-004 again.

    @Test("5: after Add Test and Undo the document asks to be saved, and the reopened book does not reuse T-004")
    func undoneAddIsSaved() throws {
        var book = coded(3)
        let ledger = TileCodeLedger(book: book)
        #expect(!ledger.needsSave(book))
        let saved = book
        #expect(ledger.append(tileFor(book), to: &book) == "T-004")
        book = saved                                       // Edit > Undo: back to the saved state
        #expect(ledger.needsSave(book))                    // the app marks the document changed (not undoable)
        let file = try GlazeBookCodec.save(book, ledger: ledger)   // the autosave that follows
        var reopened = try GlazeBookCodec.open(file)
        let fresh = TileCodeLedger(book: reopened)
        #expect(!fresh.needsSave(reopened))
        #expect(fresh.append(tileFor(reopened), to: &reopened) == "T-005")
    }

    // R1 F6 and F7 (no failing-first required).

    @Test("6: the tile editor posts a VoiceOver announcement when a code is refused")
    func refusedCodeIsAnnounced() throws {
        let text = try String(contentsOf: Self.root.appendingPathComponent("Sources/GlazeApp/TestLogView.swift"), encoding: .utf8)
        #expect(text.contains("AccessibilityNotification.Announcement(TileCode.message(problem)).post()"))
    }

    @Test("7: the date also matches in the local format")
    func localDate() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var book = coded(0)
        TileCode.append(tileFor(book), to: &book)
        let pl = Locale(identifier: "pl_PL")
        let shown = book.tests[0].date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: pl,
                                                                  calendar: utc, timeZone: utc.timeZone))
        let hits = TestSearch.filter(book.tests, recipes: book.recipes, query: String(shown.prefix(5)),
                                     calendar: utc, locale: pl)
        #expect(hits.count == 1, "\(shown)")
        #expect(TestSearch.filter(book.tests, recipes: book.recipes, query: LabelLayout.dateText(book.tests[0].date, calendar: utc), calendar: utc, locale: pl).count == 1)
    }

    @Test("5: the window marks the document changed, outside Undo, when Undo took back an issued number")
    func windowMarksChanged() throws {
        let text = try String(contentsOf: Self.root.appendingPathComponent("Sources/GlazeApp/BookWindow.swift"), encoding: .utf8)
        #expect(text.contains("tileLedger.needsSave(document.book)"))
        #expect(text.contains("updateChangeCount(.changeDone)"))
    }
}
