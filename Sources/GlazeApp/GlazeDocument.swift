import SwiftUI
import UniformTypeIdentifiers
import GlazeCore

extension UTType {
    /// The glaze book document type. The identifier is under the developer's own reverse-DNS prefix (G11; it was com.glazeapp.*, a domain we do not own).
    static let glazeBook = UTType(exportedAs: "com.michaellip.frit.glazebook", conformingTo: .json)
}

/// A glaze book on disk: the JSON encoding of `GlazeBook`.
struct GlazeDocument: FileDocument, Equatable {
    var book: GlazeBook
    /// True for the sample book, both on the first launch and from Help > Open Sample Book. Its window then shows
    /// a note that names the tools to try and how to start a book of your own (run 1104 L10 change 2: before,
    /// the note showed only on the first launch). Not saved in the file.
    var isSample = false
    /// The highest tile number issued in this document. A reference, so Edit > Undo (which puts back an earlier
    /// document value) does not take it back and a new tile never gets an undone tile's code (F3 fix round 2).
    let tileLedger: TileCodeLedger
    /// Set when tiles got codes on open (an older book, or codes lost outside Frit). The window shows it once.
    /// Not saved in the file (R1 F1).
    var backfillNotice: TileCode.BackfillNotice?

    static func == (a: GlazeDocument, b: GlazeDocument) -> Bool {
        a.book == b.book && a.isSample == b.isSample
    }

    static var readableContentTypes: [UTType] { [.glazeBook] }
    static var writableContentTypes: [UTType] { [.glazeBook] }

    init(book: GlazeBook = BookFactory.emptyBook(), isSample: Bool = false) {
        self.book = book
        self.isSample = isSample
        self.tileLedger = TileCodeLedger(book: book)
    }

    /// A new untitled sample book with its note. Every way to open the sample uses this (first launch,
    /// Help > Open Sample Book, the button of an empty book).
    static func sample() -> GlazeDocument {
        GlazeDocument(book: SampleBook.make(), isSample: true)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // `open` also gives tile codes to the tiles of an older book (F3). The file itself is not changed.
        let (book, notice) = try GlazeBookCodec.openReport(data)
        self.book = book
        self.backfillNotice = notice
        self.tileLedger = TileCodeLedger(book: book)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // The tile counter is raised to the highest number issued; migrated codes are in `book` (F3 fix round 2).
        let data = try GlazeBookCodec.save(book, ledger: tileLedger)
        return FileWrapper(regularFileWithContents: data)
    }
}

/// The tile ledger of the window's document, for the views that add tiles (Tests page, Tests menu, blends).
private struct TileLedgerKey: EnvironmentKey {
    /// Only for a view outside a book window. Each book window sets its document's ledger.
    static let defaultValue = TileCodeLedger(book: GlazeBook(recipes: [], customMaterials: [], tests: [], version: 1))
}

extension EnvironmentValues {
    var tileLedger: TileCodeLedger {
        get { self[TileLedgerKey.self] }
        set { self[TileLedgerKey.self] = newValue }
    }
}
