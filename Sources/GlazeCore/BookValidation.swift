import Foundation

/// Why a `.glazebook` file was not opened. The text is what the open-file alert shows.
/// W6 F2: decoding had no semantic checks, so duplicate ids, a newer format and extreme numbers entered the model.
public enum GlazeBookError: Error, Equatable, Sendable, LocalizedError {
    /// The file comes from a newer version of the app. It is not opened, so it is never saved back without its new data.
    case unsupportedVersion(found: Int, supported: Int)
    /// The version number is below 1.
    case invalidVersion(Int)
    /// Two items of one kind share an id ("recipe", "material", "test tile" or "line in recipe <name>").
    case duplicateID(kind: String, id: String)
    /// A number is NaN, infinite or outside the range that the app can store and calculate.
    case numberOutOfRange(field: String, value: Double, limit: Double)
    /// A list has more items than the app takes.
    case tooManyItems(kind: String, count: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(found, supported):
            return "This glaze book uses file format \(found). This version of Frit reads format \(supported) or older. "
                + "Update Frit to open it. The file was not changed."
        case let .invalidVersion(v):
            return "This glaze book has an invalid file format number (\(v)). The file was not changed."
        case let .duplicateID(kind, id):
            return "This glaze book has two items with the same id (\(kind) \(id)). "
                + "Frit cannot tell them apart, so it did not open the file. The file was not changed."
        case let .numberOutOfRange(field, value, limit):
            return "This glaze book has a number that Frit cannot use (\(field) is \(fmtLarge(value)); "
                + "the limit is \(fmtLarge(limit))). The file was not changed."
        case let .tooManyItems(kind, count, limit):
            return "This glaze book has \(count) \(kind), more than the limit of \(limit). The file was not changed."
        }
    }
}

/// A number for a message. Very large or non-finite values in a short form (1e+308, infinite), not 309 digits.
func fmtLarge(_ v: Double) -> String {
    if v.isNaN { return "not a number" }
    if v.isInfinite { return v < 0 ? "minus infinite" : "infinite" }
    return abs(v) >= 1e7 ? String(format: "%.3g", v) : fmtWarning(v)
}

/// The semantic checks that `GlazeBookCodec.decode` applies after the JSON decode. They only read the book,
/// so a valid file decodes to the same values and encodes to the same bytes as before.
public enum GlazeBookValidation {
    /// The file format that this build writes and reads.
    /// 2 since tile codes (F3): `GlazeBookCodec.save` writes 2 for a book with codes, 1 for one without.
    public static let supportedVersion = 2
    /// Largest stored recipe amount. Higher than `NumberText.maxMagnitude` (the entry limit) so that a file is not
    /// locked out by a small excess, but low enough that no sum or product in the calculator overflows.
    public static let maxStoredAmount = 1e9
    /// Oxide percent and LOI limit (percent of the raw material).
    public static let maxPercent = 100.0
    /// Firing rate, temperature and hold limit.
    public static let maxFiringValue = 1e6
    public static let maxItems = 100_000
    public static let maxLinesPerRecipe = 10_000
    public static let maxSegmentsPerTest = 1_000
    /// Highest stored next tile number (`GlazeBook.nextTileNumber`). Far above any real book, low enough that
    /// `TileCode` arithmetic never overflows.
    public static let maxTileNumber = 10_000_000

    public static func validate(_ book: GlazeBook) throws {
        if book.version > supportedVersion {
            throw GlazeBookError.unsupportedVersion(found: book.version, supported: supportedVersion)
        }
        if book.version < 1 { throw GlazeBookError.invalidVersion(book.version) }
        try count(book.recipes.count, "recipes", maxItems)
        try count(book.customMaterials.count, "custom materials", maxItems)
        try count(book.tests.count, "test tiles", maxItems)
        guard (0...maxTileNumber).contains(book.nextTileNumber) else {
            throw GlazeBookError.numberOutOfRange(field: "the next tile number", value: Double(book.nextTileNumber),
                                                  limit: Double(maxTileNumber))
        }
        try unique(book.recipes.map(\.id.uuidString), kind: "recipe")
        try unique(book.customMaterials.map(\.id), kind: "material")
        try unique(book.tests.map(\.id.uuidString), kind: "test tile")
        for r in book.recipes { try validate(r) }
        for m in book.customMaterials { try validate(m) }
        for t in book.tests { try validate(t) }
    }

    private static func validate(_ r: Recipe) throws {
        let name = r.name.isEmpty ? "Untitled recipe" : r.name
        try count(r.lines.count, "lines in recipe \(name)", maxLinesPerRecipe)
        try unique(r.lines.map(\.id.uuidString), kind: "line in recipe \(name)")
        for line in r.lines {
            try bounded(line.amount, maxStoredAmount, "an amount in recipe \(name)")
        }
    }

    private static func validate(_ m: Material) throws {
        for (oxide, percent) in m.analysis {
            try bounded(percent, maxPercent, "\(oxide.rawValue) in material \(m.name)")
        }
        try bounded(m.loi, maxPercent, "the LOI of material \(m.name)")
    }

    private static func validate(_ t: TestTile) throws {
        try count(t.schedule.count, "firing segments in a test tile", maxSegmentsPerTest)
        for s in t.schedule {
            try bounded(s.ratePerHour, maxFiringValue, "a firing rate")
            try bounded(s.targetC, maxFiringValue, "a firing temperature")
            try bounded(s.holdMinutes, maxFiringValue, "a firing hold")
        }
    }

    private static func bounded(_ v: Double, _ limit: Double, _ field: String) throws {
        guard v.isFinite, abs(v) <= limit else {
            throw GlazeBookError.numberOutOfRange(field: field, value: v, limit: limit)
        }
    }

    private static func count(_ n: Int, _ kind: String, _ limit: Int) throws {
        guard n <= limit else { throw GlazeBookError.tooManyItems(kind: kind, count: n, limit: limit) }
    }

    private static func unique(_ ids: [String], kind: String) throws {
        var seen = Set<String>()
        for id in ids where !seen.insert(id).inserted {
            throw GlazeBookError.duplicateID(kind: kind, id: id)
        }
    }
}
