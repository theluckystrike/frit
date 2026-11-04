import Foundation

/// F3: the short code on each test tile (T-001, T-002, ...). The potter writes it on the back of the tile, prints
/// it on a label, and types it in the Tests search to find the tile again.
///
/// Rules: a new tile gets the next number of `GlazeBook.nextTileNumber`, which only goes up, so a deleted tile's
/// code is never given to a new tile (the same lesson as `MaterialRules.newCustomID`, W6 F1). The user can change a
/// code. No two tiles may share one; the check ignores case and the spaces at the ends ("t-002" is "T-002").
public enum TileCode {
    public static let prefix = "T-"
    /// Longest code that the editor takes, so that a code fits on one label line.
    public static let maxLength = 12
    /// A typed code in the T-n form moves the counter past n only up to this number. A larger typed number
    /// (T-9999999) cannot push the counter near `GlazeBookValidation.maxTileNumber`.
    public static let maxCountedNumber = 999_999
    /// Characters a code may have besides letters and digits.
    public static let extraCharacters = " -_./#+"

    /// T-001 for 1, T-1234 for 1234. Numbers are clamped to 0...maxTileNumber.
    public static func format(_ number: Int) -> String {
        let n = min(max(number, 0), GlazeBookValidation.maxTileNumber)
        return prefix + String(format: "%03ld", n)
    }

    /// The comparison form of a code: no spaces at the ends, case, accents and width ignored.
    public static func key(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// What makes two codes the same tile: the tile number for a T-n code ("T-5" and "T-005" are both tile 5,
    /// R1 F3), else the comparison form of the text.
    public static func identity(_ code: String) -> String {
        if let n = number(of: code) { return "#\(n)" }
        return key(code)
    }

    /// The highest T-n number in use that counts for the counter (at most `maxCountedNumber`), or 0.
    public static func highestNumber(in tests: [TestTile]) -> Int {
        tests.compactMap { number(of: $0.code) }.filter { $0 <= maxCountedNumber }.max() ?? 0
    }

    /// Where the next code starts: above the counter and above every T-n code in use. A typed code moves this only
    /// while it is in the book, so a half-typed "T-0500" that the user fixes leaves no gap (R1 F4).
    static func start(_ book: GlazeBook) -> Int {
        max(book.nextTileNumber, highestNumber(in: book.tests) + 1, 1)
    }

    /// The number of a code in the T-n form ("T-012" is 12, "t-7" is 7). nil for any other code.
    public static func number(of code: String) -> Int? {
        let k = key(code)
        guard k.hasPrefix("t-") else { return nil }
        let digits = k.dropFirst(2)
        guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }

    /// The code that the next new tile gets. It is never a code in use and never below the counter.
    public static func next(in book: GlazeBook) -> String {
        var used = usedKeys(book.tests)
        return take(&used, from: start(book)).code
    }

    /// Gives `tile` the next code, appends it to the book and moves the counter on. Returns the code.
    /// Blends call this once per tile, in blend order, so their tiles get consecutive codes.
    @discardableResult
    public static func append(_ tile: TestTile, to book: inout GlazeBook) -> String {
        var used = usedKeys(book.tests)
        let next = take(&used, from: start(book))
        var t = tile
        t.code = next.code
        book.tests.append(t)
        book.nextTileNumber = next.number + 1
        return next.code
    }

    /// Gives a code to each tile that has none, in book order (a book saved before tile codes existed). The counter
    /// first moves past the highest T-n code in the book. A book in which every tile has a code is not changed.
    public static func backfill(_ book: inout GlazeBook) {
        guard book.tests.contains(where: { key($0.code).isEmpty }) else { return }
        var counter = start(book)
        var used = usedKeys(book.tests)
        for i in book.tests.indices where key(book.tests[i].code).isEmpty {
            let next = take(&used, from: counter)
            book.tests[i].code = next.code
            counter = next.number + 1
        }
        book.nextTileNumber = min(counter, GlazeBookValidation.maxTileNumber)
    }

    /// Why a typed code cannot be used.
    public enum Problem: Equatable, Sendable {
        case empty
        case tooLong
        case invalidCharacters
        /// Another tile has this code already.
        case taken(code: String)
    }

    /// The text that the tile editor shows under the code field.
    public static func message(_ problem: Problem) -> String {
        switch problem {
        case .empty:
            return "A tile code cannot be empty. The code was not changed."
        case .tooLong:
            return "A tile code can have up to \(maxLength) characters, so that it fits on a label. The code was not changed."
        case .invalidCharacters:
            return "Use letters, digits, spaces and - _ . / # + in a tile code. The code was not changed."
        case let .taken(code):
            return "Another tile already has the code \(code). Each tile needs its own code. The code was not changed."
        }
    }

    /// Checks a typed code for the tile with id `tileID`.
    public static func problem(with code: String, forTile tileID: UUID, in book: GlazeBook) -> Problem? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > maxLength { return .tooLong }
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: extraCharacters))
        if !trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) { return .invalidCharacters }
        let k = identity(trimmed)
        if let other = book.tests.first(where: { $0.id != tileID && identity($0.code) == k }) {
            return .taken(code: other.code)
        }
        return nil
    }

    /// Sets the code of a tile after the checks. With a problem, or an unknown tile, nothing changes. A code that
    /// is the same as the current one does not write to the book (so it adds no Undo step). The counter does not
    /// move here (R1 F4): new codes start above every T-n code in use (`start`), and the save stores that.
    @discardableResult
    public static func rename(tileID: UUID, to code: String, in book: inout GlazeBook) -> Problem? {
        if let problem = problem(with: code, forTile: tileID, in: book) { return problem }
        guard let i = book.tests.firstIndex(where: { $0.id == tileID }) else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if book.tests[i].code != trimmed { book.tests[i].code = trimmed }
        return nil
    }

    /// The tile editor calls this on each keystroke (F3 fix round 2). When the typed code passes the checks, it is
    /// in the book at once (as `rename`), so a click on another tile or closing the window cannot lose it. When it
    /// does not, the tile gets back `original`, the code it had when the edit began, so a refused or half-typed
    /// code never stays in the book. Returns the problem to show, if any.
    @discardableResult
    public static func liveEdit(tileID: UUID, draft: String, original: String, in book: inout GlazeBook) -> Problem? {
        guard let i = book.tests.firstIndex(where: { $0.id == tileID }) else { return nil }
        if let problem = problem(with: draft, forTile: tileID, in: book) {
            if book.tests[i].code != original { book.tests[i].code = original }
            return problem
        }
        return rename(tileID: tileID, to: draft, in: &book)
    }

    /// Codes that two or more tiles share, in book order, by `identity` ("T-5" and "T-005" are the same). The app
    /// never makes these; a file edited outside the app can have them. The Tests page then says which to change.
    public static func duplicates(in tests: [TestTile]) -> [String] {
        var seen: [String: Int] = [:]
        var out: [String] = []
        for t in tests where !key(t.code).isEmpty {
            let k = identity(t.code)
            seen[k, default: 0] += 1
            if seen[k] == 2 { out.append(t.code) }
        }
        return out
    }

    /// What the window tells the user once after `GlazeBookCodec.openReport` gave codes on open (R1 F1).
    public struct BackfillNotice: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// A format-1 book from Frit 1.2 or older: its tiles never had codes.
            case olderBook
            /// A format-2 book in which some tiles have no code: they were lost outside this version of Frit.
            case missingCodes
        }
        public let kind: Kind
        /// The codes given, in book order.
        public let codes: [String]

        public init(kind: Kind, codes: [String]) {
            self.kind = kind
            self.codes = codes
        }
    }

    public static func noticeText(_ notice: BackfillNotice) -> String {
        let n = notice.codes.count
        let tiles = n == 1 ? "1 test tile" : "\(n) test tiles"
        let range = rangeText(notice.codes)
        switch notice.kind {
        case .olderBook:
            return "This book comes from an earlier version of Frit, so its \(tiles) had no codes. Frit gave them "
                + "\(range) in the order of the tiles. Save the book to keep these codes."
        case .missingCodes:
            if n == 1 {
                return "1 test tile in this book had lost its code, for example in another app. Frit gave it a new code "
                    + "(\(range)) and kept every other code. Check this tile against the code on your fired tile."
            }
            return "\(tiles) in this book had lost their codes, for example in another app. Frit gave them new codes "
                + "(\(range)) and kept every other code. Check these tiles against the codes on your fired tiles."
        }
    }

    /// "T-004" for one code, "T-004 to T-008" for several (first and last), "" for none.
    public static func rangeText(_ codes: [String]) -> String {
        guard let first = codes.first, let last = codes.last else { return "" }
        return codes.count == 1 ? first : "\(first) to \(last)"
    }

    private static func usedKeys(_ tests: [TestTile]) -> Set<String> {
        Set(tests.filter { !key($0.code).isEmpty }.map { identity($0.code) })
    }

    /// The first free T-n code at or above `start`. The loop is bounded: at most `used.count` codes are taken.
    private static func take(_ used: inout Set<String>, from start: Int) -> (number: Int, code: String) {
        let limit = GlazeBookValidation.maxTileNumber
        var n = min(max(start, 1), max(1, limit - used.count - 1))
        for _ in 0...used.count {
            let code = format(n)
            if used.insert(identity(code)).inserted { return (n, code) }
            n += 1
        }
        let code = format(n)
        used.insert(identity(code))
        return (n, code)
    }
}

/// F3: the search field and the cone and atmosphere filters of the Tests page.
public enum TestSearch {
    /// Material id to name, for matching the materials of a tile's recipe.
    public static func materialNames(_ library: any MaterialLibrary) -> [String: String] {
        Dictionary(library.all.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// The tiles that match, in book order. Every word of the query must be found in the tile's code, recipe name,
    /// cone, atmosphere, notes, the names of its recipe's materials, or its date (yyyy-mm-dd). Case and accents
    /// are ignored. "cone 6" (or "cone 06") matches that cone exactly, so "cone 6" does not find cone 06 or 10.
    /// A code also matches without its hyphen ("t002") and without its leading zeros ("T-2" finds T-002).
    /// "cone" takes the next word as a cone only when it is a cone (an Orton cone, or a cone that a tile has), so
    /// "cone pack" searches both words (R1 F2). The date also matches in the local format ("14.09.2026", R1 F7).
    /// `cone` and `atmosphere` are exact filters; nil is any.
    public static func filter(_ tests: [TestTile], recipes: [Recipe], materialNames: [String: String] = [:],
                              query: String, cone: String? = nil, atmosphere: String? = nil,
                              calendar: Calendar = .current, locale: Locale = .current) -> [TestTile] {
        let cones = Set(OrtonCones.all.map(fold)).union(tests.map { fold($0.cone) })
        let parsed = parse(query, cones: cones)
        let byID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return tests.filter { t in
            if let cone, t.cone != cone { return false }
            if let atmosphere, fold(t.atmosphere) != fold(atmosphere) { return false }
            if let c = parsed.cone, fold(t.cone) != c { return false }
            if parsed.words.isEmpty { return true }
            let text = haystack(t, recipe: byID[t.recipeID], materialNames: materialNames, calendar: calendar,
                                locale: locale)
            let tileNumber = TileCode.number(of: t.code)
            return parsed.words.allSatisfy { word in
                text.contains(word) || (tileNumber != nil && TileCode.number(of: word) == tileNumber)
            }
        }
    }

    /// The tile whose code is exactly the query (case and end spaces ignored), when one tile has it. A T-n query
    /// also matches its number without the leading zeros ("T-2" is T-002), when no code matches it as typed.
    /// Typing the code from the back of a fired tile selects that tile.
    public static func exactCode(_ query: String, in tests: [TestTile]) -> TestTile? {
        let k = TileCode.key(query)
        guard !k.isEmpty else { return nil }
        let hits = tests.filter { TileCode.key($0.code) == k }
        if !hits.isEmpty { return hits.count == 1 ? hits[0] : nil }
        guard let n = TileCode.number(of: k) else { return nil }
        let byNumber = tests.filter { TileCode.number(of: $0.code) == n }
        return byNumber.count == 1 ? byNumber[0] : nil
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func parse(_ query: String, cones: Set<String>) -> (words: [String], cone: String?) {
        let tokens = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var words: [String] = []
        var cone: String?
        var i = 0
        while i < tokens.count {
            if tokens[i] == "cone", i + 1 < tokens.count, cones.contains(tokens[i + 1]) {
                cone = tokens[i + 1]
                i += 2
            } else {
                words.append(tokens[i])
                i += 1
            }
        }
        return (words, cone)
    }

    static func haystack(_ t: TestTile, recipe: Recipe?, materialNames: [String: String], calendar: Calendar,
                         locale: Locale) -> String {
        let local = t.date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale,
                                                      calendar: calendar, timeZone: calendar.timeZone))
        var parts = [t.code, t.code.replacingOccurrences(of: "-", with: ""), recipe?.name ?? "Deleted recipe",
                     "cone", t.cone, t.atmosphere, t.notes, LabelLayout.dateText(t.date, calendar: calendar), local]
        for line in recipe?.lines ?? [] where !line.materialID.isEmpty {
            parts.append(materialNames[line.materialID] ?? line.materialID)
        }
        return fold(parts.joined(separator: "\n"))
    }
}

/// F3: the label sheet. Positions are in points from the top left of the page.
public enum LabelLayout {
    /// A sheet of labels: the page size, the grid, and the size and pitch of each label.
    public struct Sheet: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let pageWidth: Double
        public let pageHeight: Double
        public let columns: Int
        public let rows: Int
        public let labelWidth: Double
        public let labelHeight: Double
        public let left: Double
        public let top: Double
        /// Distance from the left edge of one label to the left edge of the next one.
        public let columnPitch: Double
        /// Distance from the top edge of one label to the top edge of the next one.
        public let rowPitch: Double

        public var perPage: Int { columns * rows }

        /// The rectangle of a slot (0 is top left, then across, then down).
        public func frame(slot: Int) -> (x: Double, y: Double, width: Double, height: Double) {
            let s = min(max(slot, 0), max(perPage - 1, 0))
            let column = columns > 0 ? s % columns : 0
            let row = columns > 0 ? s / columns : 0
            return (left + Double(column) * columnPitch, top + Double(row) * rowPitch, labelWidth, labelHeight)
        }
    }

    private static let inch = 72.0
    private static let mm = 72.0 / 25.4

    /// US Letter, 30 labels of 2 5/8 x 1 in (3 across, 10 down), the common address label size.
    public static let letter30 = Sheet(id: "letter-30", title: "Letter, 30 labels, 2⅝ × 1 in",
                                       pageWidth: 8.5 * inch, pageHeight: 11 * inch, columns: 3, rows: 10,
                                       labelWidth: 2.625 * inch, labelHeight: 1 * inch,
                                       left: 0.1875 * inch, top: 0.5 * inch,
                                       columnPitch: 2.75 * inch, rowPitch: 1 * inch)
    /// A4, 21 labels of 63.5 x 38.1 mm (3 across, 7 down).
    public static let a4x21 = Sheet(id: "a4-21", title: "A4, 21 labels, 63.5 × 38.1 mm",
                                    pageWidth: 210 * mm, pageHeight: 297 * mm, columns: 3, rows: 7,
                                    labelWidth: 63.5 * mm, labelHeight: 38.1 * mm,
                                    left: 7.25 * mm, top: 15.15 * mm,
                                    columnPitch: 66 * mm, rowPitch: 38.1 * mm)
    public static let sheets = [letter30, a4x21]

    /// The item indices on each page. `skip` leaves the first labels of the first page empty, for a sheet that is
    /// partly used; it is clamped to 0...(perPage - 1). 31 labels at 3 x 10 give two pages: 30 and 1.
    public static func pages(count: Int, columns: Int, rows: Int, skip: Int = 0) -> [[Int]] {
        guard count > 0, columns > 0, rows > 0, columns <= 1_000, rows <= 1_000 else { return [] }
        let perPage = columns * rows
        let first = min(max(skip, 0), perPage - 1)
        var pages: [[Int]] = []
        var item = 0
        var free = perPage - first
        while item < count {
            let n = min(free, count - item)
            pages.append(Array(item..<(item + n)))
            item += n
            free = perPage
        }
        return pages
    }

    /// The slot of the n-th item on its page (the first page starts at `skip`).
    public static func slot(itemOnPage n: Int, page: Int, skip: Int, perPage: Int) -> Int {
        guard perPage > 0 else { return 0 }
        return page == 0 ? min(max(skip, 0), perPage - 1) + n : n
    }

    /// The three lines of one label.
    public struct Text: Equatable, Sendable {
        public let code: String
        public let recipe: String
        /// "Cone 6 · Oxidation · 2026-09-14"
        public let details: String
    }

    public static func text(for tile: TestTile, recipes: [Recipe], calendar: Calendar = .current) -> Text {
        let name = recipes.first { $0.id == tile.recipeID }.map { $0.name.isEmpty ? "Untitled recipe" : $0.name }
        let details = ["Cone \(tile.cone)", tile.atmosphere, dateText(tile.date, calendar: calendar)]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " · ")
        return Text(code: tile.code.isEmpty ? "No code" : tile.code, recipe: name ?? "Deleted recipe", details: details)
    }

    /// yyyy-mm-dd in the given calendar. The same in every language, so it reads the same on every label.
    public static func dateText(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// The tile counter of an open document, kept outside the book value (F3 fix round 2).
///
/// Edit > Undo puts back an earlier `GlazeBook`, with its lower `nextTileNumber`. If new codes came only from the
/// book, Undo of Add Test would let the next tile get the undone tile's code again, which may already be written on
/// a fired tile. The app's document holds one ledger (a reference, so Undo does not replace it). New codes start at
/// the higher of the ledger and the book, and the save writes the higher counter into the file
/// (`GlazeBookCodec.save`). The lock makes it safe to read from the background save.
public final class TileCodeLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var floor: Int

    public init(book: GlazeBook) {
        floor = min(max(book.nextTileNumber, 1), GlazeBookValidation.maxTileNumber)
    }

    /// The lowest number that the next new code may have.
    public var nextNumber: Int { lock.withLock { floor } }

    /// Gives `tile` the next code (see `TileCode.append`), never below a number issued before in this document,
    /// and remembers the new number. Returns the code.
    @discardableResult
    public func append(_ tile: TestTile, to book: inout GlazeBook) -> String {
        lock.withLock {
            if book.nextTileNumber < floor { book.nextTileNumber = floor }
            let code = TileCode.append(tile, to: &book)
            floor = max(floor, min(book.nextTileNumber, GlazeBookValidation.maxTileNumber))
            return code
        }
    }

    /// True when the book's counter is below a number this document has issued, which happens after Edit > Undo of
    /// Add Test or a blend. Undo can bring the undo count back to the saved state, so the document looks unchanged
    /// and the issued number would be lost on close (R1 F5). The window then marks the document changed, outside
    /// Undo, so the save writes the counter.
    public func needsSave(_ book: GlazeBook) -> Bool { book.nextTileNumber < nextNumber }

    /// The book as it is saved: its counter raised to the highest number issued, and above every T-n code in use
    /// (R1 F4). Other values are unchanged.
    public func forSaving(_ book: GlazeBook) -> GlazeBook {
        let f = min(max(nextNumber, TileCode.start(book)), GlazeBookValidation.maxTileNumber)
        guard book.nextTileNumber < f else { return book }
        var out = book
        out.nextTileNumber = f
        return out
    }
}
