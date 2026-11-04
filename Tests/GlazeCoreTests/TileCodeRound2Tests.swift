import Foundation
import Testing
@testable import GlazeCore

/// F3 fix round 2. Written before the fixes and run against the old behavior first
/// (`F3/logs/round2-failing-first.log`).
@Suite("Tile codes: fix round 2 (F3)")
struct TileCodeRound2Tests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    static func appSource(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/GlazeApp/\(name)"), encoding: .utf8)
    }

    private func bookWithTiles(_ n: Int) -> GlazeBook {
        var book = SampleBook.make()
        book.tests = []
        book.nextTileNumber = 1
        let r = book.recipes[0]
        for _ in 0..<n {
            TileCode.append(TestTile(recipeID: r.id, cone: "6", atmosphere: "Oxidation", schedule: [], notes: "",
                                     photoBookmark: nil, date: Date(timeIntervalSince1970: 1_792_600_000)), to: &book)
        }
        return book
    }

    // Bug 1: a typed code was kept only in the field until Return or focus loss, so a click on another tile
    // or closing the window lost it. Now each keystroke that gives a valid code is in the book at once.

    @Test("bug 1: a valid typed code is in the book after each keystroke, with no Return or focus change")
    func liveEditWritesValidCode() {
        var book = bookWithTiles(3)
        let id = book.tests[2].id
        var problem: TileCode.Problem?
        for draft in ["C", "Cu", "Cu-", "Cu-3", "Cu-3a"] {
            problem = TileCode.liveEdit(tileID: id, draft: draft, original: "T-003", in: &book)
            #expect(problem == nil, "\(draft)")
            #expect(book.tests[2].code == draft, "\(draft)")
        }
        // The user now clicks another tile: nothing more runs, and the book already has the code.
        #expect(book.tests.map(\.code) == ["T-001", "T-002", "Cu-3a"])
    }

    @Test("bug 1: a refused draft puts back the code the tile had when the edit began")
    func liveEditRefusedRestoresOriginal() {
        var book = bookWithTiles(3)
        let id = book.tests[2].id
        TileCode.liveEdit(tileID: id, draft: "T-00", original: "T-003", in: &book)
        #expect(book.tests[2].code == "T-00")
        #expect(TileCode.liveEdit(tileID: id, draft: "T-001", original: "T-003", in: &book) == .taken(code: "T-001"))
        #expect(book.tests[2].code == "T-003")
        #expect(TileCode.liveEdit(tileID: id, draft: "", original: "T-003", in: &book) == .empty)
        #expect(book.tests[2].code == "T-003")
        #expect(Set(book.tests.map { TileCode.key($0.code) }).count == 3)
    }

    @Test("bug 1: the tile editor saves through liveEdit as the user types, not on Return or focus loss")
    func editorSavesWhileTyping() throws {
        let page = try Self.appSource("TestLogView.swift")
        #expect(page.contains("TileCode.liveEdit(tileID:"))
        #expect(page.contains(".onChange(of: codeDraft)"))
        #expect(!page.contains(".onSubmit { saveCode() }"))
        #expect(!page.contains("if !focused { saveCode() }"))
    }

    // Bug 2: Undo after Add Test took back the book's tile counter too, so the next tile got the undone
    // tile's code again. Now the document keeps the highest number issued outside the book.

    @Test("bug 2: Undo of Add Test does not let the next tile reuse the undone code")
    func undoDoesNotReuse() {
        var book = bookWithTiles(3)
        let ledger = TileCodeLedger(book: book)
        let tile = book.tests[0]
        let beforeAdd = book                       // the value that Edit > Undo puts back
        #expect(ledger.append(tile, to: &book) == "T-004")
        book = beforeAdd                           // Edit > Undo
        #expect(book.nextTileNumber == 4)
        #expect(ledger.append(tile, to: &book) == "T-005")
        #expect(book.nextTileNumber == 6)
    }

    @Test("bug 2: the saved file keeps the highest number issued, even after Undo")
    func savedCounterSurvivesUndo() throws {
        var book = bookWithTiles(3)
        let ledger = TileCodeLedger(book: book)
        let beforeAdd = book
        for _ in 0..<4 { ledger.append(book.tests[0], to: &book) }   // T-004 to T-007
        book = beforeAdd                                              // Undo all four
        let saved = try GlazeBookCodec.decode(GlazeBookCodec.save(book, ledger: ledger))
        #expect(saved.nextTileNumber == 8)
        #expect(saved.tests.count == 3)
        // Reopened later, the next tile is T-008, not T-004.
        #expect(TileCode.next(in: saved) == "T-008")
    }

    @Test("bug 2: the app adds tiles and saves through the document's ledger")
    func appUsesLedger() throws {
        let doc = try Self.appSource("GlazeDocument.swift")
        #expect(doc.contains("let tileLedger: TileCodeLedger"))
        #expect(doc.contains("GlazeBookCodec.save(book, ledger: tileLedger)"))
        for file in ["TestLogView.swift", "BookWindow.swift", "BlendSheet.swift"] {
            let text = try Self.appSource(file)
            #expect(text.contains("tileLedger.append("), "\(file)")
            #expect(!text.contains("TileCode.append("), "\(file) bypasses the ledger")
        }
    }

    // Migration: an older book gets its codes on open. They are written on the first save, whatever the edit.

    @Test("migration: the first save of an opened older book writes the codes into the file")
    func firstSaveWritesMigratedCodes() throws {
        let old = Data(TileCodeMigrationTests.oldBook.utf8)
        var opened = try GlazeBookCodec.open(old)
        let ledger = TileCodeLedger(book: opened)
        opened.recipes[0].name = "Ash glaze 2"          // any edit, then File > Save
        let file = try GlazeBookCodec.save(opened, ledger: ledger)
        let plain = try GlazeBookCodec.decode(file)        // decode only: no backfill runs
        #expect(plain.tests.map(\.code) == ["T-001", "T-002", "T-003"])
        #expect(plain.nextTileNumber == 4)
        #expect(String(decoding: file, as: UTF8.self).contains("\"code\" : \"T-002\""))
    }
}
