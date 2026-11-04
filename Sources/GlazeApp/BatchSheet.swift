import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import GlazeCore

struct BatchRow: Identifiable {
    let id: Int
    let materialID: String
    let name: String
    let grams: Double
    let isAddition: Bool
}

struct BatchSheet: View {
    let recipe: Recipe
    let library: BookLibrary
    @Environment(\.dismiss) private var dismiss

    @AppStorage("batchTotalGrams") private var totalGrams = 1000.0
    @AppStorage("batchPrecision") private var precision = 0.1
    @State private var exporting = false
    @State private var pdfData = Data()
    @State private var message: String?

    private static let precisions: [Double] = [1, 0.5, 0.1, 0.01]

    private var rows: [BatchRow] {
        BatchPrinter.rows(recipe: recipe, library: library, totalGrams: totalGrams, precision: precision)
    }

    /// Set when a row has an amount but no material: Print and Export PDF are off until it is resolved (W6 F3).
    private var blockReason: String? { RecipeCheck.batchBlockReason(recipe) }

    var body: some View {
        let rows = self.rows
        let blockReason = self.blockReason
        VStack(alignment: .leading, spacing: 12) {
            Text("Batch Sheet – \(recipe.name)").font(.title2.weight(.semibold))
            HStack(spacing: 20) {
                LabeledContent("Total batch (g)") {
                    LiveNumberField(title: "Total grams", value: $totalGrams, fractionDigits: 0...1)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Total batch weight in grams")
                }
                Picker("Precision", selection: $precision) {
                    ForEach(Self.precisions, id: \.self) { p in
                        Text("\(fmtAmount(p)) g").tag(p)
                    }
                }
                .frame(maxWidth: 180)
                .accessibilityLabel("Weighing precision")
            }

            Table(rows) {
                TableColumn("Material") { row in
                    Text(row.name + (row.isAddition ? " (addition)" : ""))
                }
                TableColumn("Grams") { row in
                    Text(gramsText(row.grams))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 100, max: 140)
            }
            .frame(minHeight: 220)
            .accessibilityLabel("Batch weights")

            HStack {
                Text("Total").font(.headline)
                Spacer()
                Text("\(gramsText(rows.reduce(0) { $0 + $1.grams })) g").monospacedDigit().font(.headline)
            }
            .accessibilityElement(children: .combine)

            if rows.isEmpty {
                // Say why the table is empty and Print is off (W5 V4: a 0 or negative weight showed nothing).
                // W6 F2: also says when the weights would not be finite numbers (a tiny base with large additions).
                Text(Batch.problem(recipe, totalGrams: totalGrams, precision: precision)
                     ?? (recipe.baseTotal > 0 ? "Enter a batch weight above 0 g." : "Add base materials to the recipe first."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let blockReason {
                Label(blockReason, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                Button("Print…") { printSheet(rows) }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(rows.isEmpty || blockReason != nil)
                Button("Export PDF…") {
                    pdfData = makePDF(rows)
                    exporting = true
                }
                .disabled(rows.isEmpty || blockReason != nil)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480)
        .fileExporter(isPresented: $exporting, document: PDFFile(data: pdfData), contentType: .pdf,
                      defaultFilename: "\(recipe.name) batch.pdf") { result in
            switch result {
            case .success(let url): message = "Saved \(url.lastPathComponent)."
            case .failure(let error): message = "The PDF was not saved: \(error.localizedDescription)"
            }
        }
    }

    private func gramsText(_ g: Double) -> String {
        BatchPrinter.gramsText(g, precision: precision)
    }

    private func makePDF(_ rows: [BatchRow]) -> Data {
        BatchPrinter.pdf(recipe: recipe, rows: rows, totalGrams: totalGrams, precision: precision)
    }

    private func printSheet(_ rows: [BatchRow]) {
        if !BatchPrinter.print(recipe: recipe, rows: rows, totalGrams: totalGrams, precision: precision) {
            message = "Printing is not available."
        }
    }
}

/// Builds and prints the batch sheet. Used by the Batch Sheet and by File > Print Batch Sheet… (I6 C7).
@MainActor
enum BatchPrinter {
    /// The same keys as the Batch Sheet's stored settings.
    static let totalKey = "batchTotalGrams"
    static let precisionKey = "batchPrecision"

    static func rows(recipe: Recipe, library: BookLibrary, totalGrams: Double, precision: Double) -> [BatchRow] {
        Batch.scale(recipe, totalGrams: totalGrams, precision: precision).enumerated().map { i, item in
            BatchRow(id: i, materialID: item.materialID, name: library.name(for: item.materialID),
                     grams: item.grams, isAddition: item.isAddition)
        }
    }

    static func gramsText(_ g: Double, precision: Double) -> String {
        let digits = precision >= 1 ? 0 : (precision >= 0.1 ? 1 : 2)
        return fmt(g, digits)
    }

    static func pdf(recipe: Recipe, rows: [BatchRow], totalGrams: Double, precision: Double) -> Data {
        PDFMaker.render(BatchPrintPage(recipe: recipe, rows: rows, totalGrams: totalGrams,
                                       gramsText: { gramsText($0, precision: precision) }))
    }

    /// Shows the print panel for the sheet. False when printing is not available.
    @discardableResult
    static func print(recipe: Recipe, rows: [BatchRow], totalGrams: Double, precision: Double) -> Bool {
        guard let document = PDFDocument(data: pdf(recipe: recipe, rows: rows, totalGrams: totalGrams, precision: precision)),
              let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleDownToFit, autoRotate: false)
        else { return false }
        operation.jobTitle = "\(recipe.name) batch"
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
        return true
    }

    /// File > Print Batch Sheet…: the batch weight and precision last used in the Batch Sheet (1000 g, 0.1 g at first).
    static func printWithSavedSettings(recipe: Recipe, library: BookLibrary) {
        let defaults = UserDefaults.standard
        let total = defaults.object(forKey: totalKey) as? Double ?? 1000
        let precision = defaults.object(forKey: precisionKey) as? Double ?? 0.1
        // A row with an amount and no material blocks printing; say why (W6 F3).
        if let reason = RecipeCheck.batchBlockReason(recipe) {
            let alert = NSAlert()
            alert.messageText = "The batch sheet cannot be printed"
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        let rows = rows(recipe: recipe, library: library, totalGrams: total, precision: precision)
        guard !rows.isEmpty else { NSSound.beep(); return }
        if !print(recipe: recipe, rows: rows, totalGrams: total, precision: precision) { NSSound.beep() }
    }
}

/// The printed batch sheet. Always light, for paper.
struct BatchPrintPage: View {
    let recipe: Recipe
    let rows: [BatchRow]
    let totalGrams: Double
    let gramsText: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recipe.name).font(.system(size: 20, weight: .semibold))
            Text("Cone \(recipe.cone) · batch \(gramsText(totalGrams)) g · \(Date().formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("Material").font(.system(size: 11, weight: .semibold))
                    Text("Grams").font(.system(size: 11, weight: .semibold)).gridColumnAlignment(.trailing)
                    Text("Weighed").font(.system(size: 11, weight: .semibold))
                }
                ForEach(rows) { row in
                    GridRow {
                        Text(row.name + (row.isAddition ? " (addition)" : "")).font(.system(size: 12))
                        Text(gramsText(row.grams)).font(.system(size: 12).monospacedDigit())
                        Text("☐").font(.system(size: 12))
                    }
                }
                GridRow {
                    Text("Total").font(.system(size: 12, weight: .semibold))
                    Text(gramsText(rows.reduce(0) { $0 + $1.grams })).font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Text("")
                }
            }
            if !recipe.notes.isEmpty {
                Divider()
                Text(recipe.notes).font(.system(size: 11))
            }
            Spacer(minLength: 0)
        }
        .padding(48)
        .frame(width: PDFMaker.pageSize.width, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

@MainActor
enum PDFMaker {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter in points

    /// Renders a view onto one PDF page, scaled down if it is taller than the page.
    static func render<V: View>(_ view: V) -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: nil)
        let data = NSMutableData()
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: pageSize)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            let scale = min(1, pageSize.width / max(size.width, 1), pageSize.height / max(size.height, 1))
            context.translateBy(x: 0, y: pageSize.height - size.height * scale)
            context.scaleBy(x: scale, y: scale)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        return data as Data
    }

    /// Renders each view onto its own page of one PDF, at 100%, from the top left (F3 label sheets). A page view
    /// should have the page's size; a larger one is scaled down to fit.
    static func renderPages<V: View>(_ pages: [V], pageSize: CGSize) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard !pages.isEmpty, pageSize.width > 0, pageSize.height > 0,
              let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for page in pages {
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            context.beginPDFPage(nil)
            renderer.render { size, draw in
                let scale = min(1, pageSize.width / max(size.width, 1), pageSize.height / max(size.height, 1))
                context.saveGState()
                context.translateBy(x: 0, y: pageSize.height - size.height * scale)
                context.scaleBy(x: scale, y: scale)
                draw(context)
                context.restoreGState()
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
