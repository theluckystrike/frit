import SwiftUI
import PDFKit
import GlazeCore

/// Tests > Print Labels… and Print Label… in the tile editor (F3): a sheet of labels with each tile's code, recipe,
/// cone, atmosphere and date. It prints or saves a PDF through the same path as the batch sheet (`PDFMaker`).
struct LabelSheet: View {
    let book: GlazeBook
    /// The tiles that the Tests page shows (the search and filters applied).
    let shown: [TestTile]
    let selectedID: TestTile.ID?
    let filterActive: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var scope: LabelScope
    @AppStorage("labelSheetID") private var sheetID = LabelLayout.letter30.id
    @State private var startAt = 1
    @State private var exporting = false
    @State private var pdfData = Data()
    @State private var message: String?

    init(book: GlazeBook, shown: [TestTile], selectedID: TestTile.ID?, filterActive: Bool, initialScope: LabelScope) {
        self.book = book
        self.shown = shown
        self.selectedID = selectedID
        self.filterActive = filterActive
        let selectedExists = selectedID.map { id in book.tests.contains { $0.id == id } } ?? false
        var scope = initialScope
        if scope == .selected && !selectedExists { scope = .all }
        if scope == .shown && !filterActive { scope = .all }
        self._scope = State(initialValue: scope)
    }

    private var sheet: LabelLayout.Sheet {
        LabelLayout.sheets.first { $0.id == sheetID } ?? LabelLayout.letter30
    }

    private var tiles: [TestTile] {
        switch scope {
        case .all: return book.tests
        case .shown: return shown
        case .selected: return book.tests.filter { $0.id == selectedID }
        }
    }

    private var skip: Int { min(max(startAt - 1, 0), sheet.perPage - 1) }

    var body: some View {
        let tiles = self.tiles
        let sheet = self.sheet
        let pages = LabelLayout.pages(count: tiles.count, columns: sheet.columns, rows: sheet.rows, skip: skip)
        VStack(alignment: .leading, spacing: 12) {
            Text("Print Labels").font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 20) {
                Form {
                    Picker("Tiles", selection: $scope) {
                        Text("All tiles (\(book.tests.count))").tag(LabelScope.all)
                        if filterActive { Text("Tiles shown by the search (\(shown.count))").tag(LabelScope.shown) }
                        if selectedID.map({ id in book.tests.contains { $0.id == id } }) == true {
                            Text("Selected tile").tag(LabelScope.selected)
                        }
                    }
                    Picker("Label sheet", selection: $sheetID) {
                        ForEach(LabelLayout.sheets) { Text($0.title).tag($0.id) }
                    }
                    // A menu, so the row lines up with the two above it (a Stepper did not, F3 render).
                    Picker("Start at label", selection: $startAt) {
                        ForEach(1...sheet.perPage, id: \.self) { Text("\($0) of \(sheet.perPage)").tag($0) }
                    }
                    .help("On a sheet that is partly used, skip the labels that are gone. Labels count across, then down.")
                }
                .formStyle(.columns)
                .frame(maxWidth: 360, alignment: .topLeading)
                .onChange(of: sheetID) { _, _ in startAt = min(startAt, self.sheet.perPage) }

                VStack(alignment: .leading, spacing: 6) {
                    LabelPreview(sheet: sheet, tiles: tiles, recipes: book.recipes, page: pages.first ?? [], skip: skip)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(summary(count: tiles.count, pages: pages.count))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Print at 100% (no scaling). Print one page on plain paper first and hold it against a label sheet to check the fit.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Export PDF…") {
                    pdfData = LabelPrinter.pdf(tiles: tiles, recipes: book.recipes, sheet: sheet, skip: skip)
                    exporting = true
                }
                .disabled(tiles.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Print…") {
                    if !LabelPrinter.print(tiles: tiles, recipes: book.recipes, sheet: sheet, skip: skip) {
                        message = "Printing is not available."
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tiles.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 640, idealWidth: 720, minHeight: 520, idealHeight: 600)
        .fileExporter(isPresented: $exporting, document: PDFFile(data: pdfData), contentType: .pdf,
                      defaultFilename: "Tile labels.pdf") { result in
            switch result {
            case .success(let url): message = "Saved \(url.lastPathComponent)."
            case .failure(let error): message = "The PDF was not saved: \(error.localizedDescription)"
            }
        }
    }

    private func summary(count: Int, pages: Int) -> String {
        if count == 0 { return "No tiles to print." }
        let labels = count == 1 ? "1 label" : "\(count) labels"
        let pageText = pages == 1 ? "1 page" : "\(pages) pages"
        return "\(labels) on \(pageText). The preview shows page 1."
    }
}

/// The first page, scaled to fit, with the label outlines that the printed page does not have.
private struct LabelPreview: View {
    let sheet: LabelLayout.Sheet
    let tiles: [TestTile]
    let recipes: [Recipe]
    let page: [Int]
    let skip: Int

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / sheet.pageWidth, geo.size.height / sheet.pageHeight)
            LabelPage(sheet: sheet, tiles: tiles, recipes: recipes, items: page, pageIndex: 0, skip: skip, outlines: true)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: sheet.pageWidth * scale, height: sheet.pageHeight * scale, alignment: .topLeading)
                .shadow(color: .black.opacity(0.25), radius: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the first page of labels")
        .accessibilityValue(previewText)
    }

    private var previewText: String {
        let first = page.first.flatMap { tiles.indices.contains($0) ? tiles[$0].code : nil }
        let last = page.last.flatMap { tiles.indices.contains($0) ? tiles[$0].code : nil }
        guard let first, let last else { return "No labels." }
        return "\(page.count) labels, \(first == last ? first : "\(first) to \(last)"), starting at label \(skip + 1)."
    }
}

/// One printed page of labels. Always light, for paper. Positions come from `LabelLayout`.
struct LabelPage: View {
    let sheet: LabelLayout.Sheet
    let tiles: [TestTile]
    let recipes: [Recipe]
    /// Indices into `tiles` on this page.
    let items: [Int]
    let pageIndex: Int
    let skip: Int
    var outlines = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            if outlines {
                ForEach(0..<sheet.perPage, id: \.self) { slot in
                    let f = sheet.frame(slot: slot)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.gray.opacity(0.45), lineWidth: 0.75)
                        .frame(width: f.width, height: f.height)
                        .offset(x: f.x, y: f.y)
                }
            }
            ForEach(Array(items.enumerated()), id: \.offset) { n, item in
                if tiles.indices.contains(item) {
                    let slot = LabelLayout.slot(itemOnPage: n, page: pageIndex, skip: skip, perPage: sheet.perPage)
                    let f = sheet.frame(slot: slot)
                    TileLabel(text: LabelLayout.text(for: tiles[item], recipes: recipes), height: f.height)
                        .frame(width: f.width, height: f.height, alignment: .topLeading)
                        .offset(x: f.x, y: f.y)
                }
            }
        }
        .frame(width: sheet.pageWidth, height: sheet.pageHeight, alignment: .topLeading)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }
}

/// One label: the code large, then the recipe (up to 2 lines), then cone, atmosphere and date.
private struct TileLabel: View {
    let text: LabelLayout.Text
    let height: Double

    var body: some View {
        // Taller A4 labels get larger type.
        let big = height >= 100
        VStack(alignment: .leading, spacing: big ? 4 : 2) {
            Text(text.code)
                .font(.system(size: big ? 20 : 16, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(text.recipe)
                .font(.system(size: big ? 11 : 9.5))
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
            Text(text.details)
                .font(.system(size: big ? 9.5 : 8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, big ? 9 : 6)
    }
}

/// Builds, prints and exports the label PDF (F3). Same path as `BatchPrinter`: a PDF made by `PDFMaker`,
/// printed through PDFKit. Labels print at 100%, so they line up with the sheet.
@MainActor
enum LabelPrinter {
    static func pdf(tiles: [TestTile], recipes: [Recipe], sheet: LabelLayout.Sheet, skip: Int) -> Data {
        let pages = LabelLayout.pages(count: tiles.count, columns: sheet.columns, rows: sheet.rows, skip: skip)
        let views = pages.enumerated().map { i, items in
            LabelPage(sheet: sheet, tiles: tiles, recipes: recipes, items: items, pageIndex: i, skip: skip)
        }
        return PDFMaker.renderPages(views, pageSize: CGSize(width: sheet.pageWidth, height: sheet.pageHeight))
    }

    @discardableResult
    static func print(tiles: [TestTile], recipes: [Recipe], sheet: LabelLayout.Sheet, skip: Int) -> Bool {
        guard !tiles.isEmpty, let document = PDFDocument(data: pdf(tiles: tiles, recipes: recipes, sheet: sheet, skip: skip))
        else { return false }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = NSSize(width: sheet.pageWidth, height: sheet.pageHeight)
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.orientation = .portrait
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false)
        else { return false }
        operation.jobTitle = "Tile labels"
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
        return true
    }
}
