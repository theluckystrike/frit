import Foundation

/// The one JSON encoding of a `.glazebook` file. The app document and the tests use it,
/// so a decode followed by an encode gives the same bytes (no change on open).
public enum GlazeBookCodec {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ book: GlazeBook) throws -> Data { try encoder().encode(book) }

    /// Decodes and then checks the book (`GlazeBookValidation`): a newer format, duplicate ids and numbers out of
    /// range throw a `GlazeBookError` with a message for the user. The checks only read, so a valid file gives
    /// the same values as before.
    public static func decode(_ data: Data) throws -> GlazeBook {
        let book = try decoder().decode(GlazeBook.self, from: data)
        try GlazeBookValidation.validate(book)
        return book
    }

    /// What the app writes on File > Save and autosave (F3 fix round 2): the book with its tile counter raised to
    /// the highest number the document has issued (`TileCodeLedger`), so Undo of Add Test cannot bring an issued
    /// code back. The codes that `open` gave an older book are in `book`, so the first save writes them.
    /// The file format is 2 when the book has tile code data (a code, or a counter above 1), else 1 (R1 F1).
    /// Frit 1.0 to 1.2 read format 1 only. They refuse format 2 with "Update Frit to open it. The file was not
    /// changed.", so they cannot open a book with codes and save it back without them.
    public static func save(_ book: GlazeBook, ledger: TileCodeLedger) throws -> Data {
        var out = ledger.forSaving(book)
        out.version = formatVersion(for: out)
        return try encode(out)
    }

    /// 2 when the book has a tile code or a tile counter above 1, else 1, so a book without tile codes still opens
    /// in Frit 1.0 to 1.2.
    public static func formatVersion(for book: GlazeBook) -> Int {
        let hasCodes = book.nextTileNumber > 1 || book.tests.contains { !TileCode.key($0.code).isEmpty }
        return hasCodes ? 2 : 1
    }

    /// `open`, and what to tell the user when tiles got codes on open (R1 F1). The order of the tiles is kept and
    /// every code that is there is kept; only tiles without a code get one. A format-1 book never had codes (an
    /// older Frit), so the note says that. A format-2 book had codes, so a tile without one lost it outside this
    /// version, and the note names the new codes so the user can check them against the fired tiles.
    public static func openReport(_ data: Data) throws -> (book: GlazeBook, notice: TileCode.BackfillNotice?) {
        var book = try decode(data)
        let missing = book.tests.indices.filter { TileCode.key(book.tests[$0].code).isEmpty }
        guard !missing.isEmpty else { return (book, nil) }
        TileCode.backfill(&book)
        let codes = missing.map { book.tests[$0].code }
        return (book, TileCode.BackfillNotice(kind: book.version >= 2 ? .missingCodes : .olderBook, codes: codes))
    }

    /// What the app uses to open a file: `decode`, then `TileCode.backfill` gives a code to each tile of a book
    /// saved before tile codes existed (F3). Nothing is written to the file on open. The codes come from the
    /// order of the tiles in the file, so the same old file gets the same codes each time it opens, and they are
    /// stored at the next save. A book that already has codes opens with the same values as `decode`.
    public static func open(_ data: Data) throws -> GlazeBook {
        var book = try decode(data)
        TileCode.backfill(&book)
        return book
    }
}
