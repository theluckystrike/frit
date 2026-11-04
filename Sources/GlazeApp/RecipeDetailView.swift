import SwiftUI
import GlazeCore

struct RecipeDetailView: View {
    @Binding var recipe: Recipe
    @Binding var book: GlazeBook
    let library: BookLibrary
    /// The window's state. The blend and batch sheets are requested through it, because their toolbar
    /// items belong to the window (BookWindow), not to this view (W5 V5).
    @Bindable var model: WindowModel
    /// Whether the chemistry inspector is shown. Kept per window by BookWindow and restored with the window.
    @Binding var showChemistry: Bool

    @AppStorage("includeAdditions") private var includeAdditions = false

    private var chemistry: Result<Chemistry, Error> {
        // Lines without a material yet are not errors; leave them out of the calculation.
        var filled = recipe
        filled.lines = recipe.lines.filter { !$0.materialID.isEmpty }
        return Result { try GlazeCalculator.chemistry(of: filled, library: library, includeAdditions: includeAdditions) }
    }

    private var hasBoron: Bool {
        guard case .success(let c) = chemistry else { return false }
        return (c.umf[.B2O3] ?? 0) > 0.00005
    }

    private var currentPoint: StullPoint? {
        guard case .success(let c) = chemistry else { return nil }
        let si = c.umf[.SiO2] ?? 0
        let al = c.umf[.Al2O3] ?? 0
        guard si.isFinite, al.isFinite, si > 0 || al > 0 else { return nil }
        return StullPoint(siO2: si, al2O3: al)
    }

    var body: some View {
        // Main area: the recipe table and, under it, the Stull chart. Trailing inspector: the chemistry.
        // The inspector can be hidden (toolbar button or View > Hide Inspector) so that a narrow window
        // gives the recipe the full width. With the inspector shown, the window fits a 1024-pt-wide screen (G11).
        // An HStack, not a split view: AppKit split views made the window's minimum width the sum of the panes'
        // first widths, so the window could not get narrower than about 1340 pt (G11, measured in the debug build).
        // The chemistry pane gets about 40 % of the width, between its minimum and maximum; the recipe the rest.
        GeometryReader { geo in
            let chemistryWidth = WindowLayout.chemistryWidth(detailWidth: Double(geo.size.width))
            HStack(spacing: 0) {
                recipePane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if showChemistry {
                    Divider()
                    chemistryInspector
                        .frame(width: chemistryWidth)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        // A GeometryReader has no minimum of its own, so give the window the panes' minimums here.
        .frame(minWidth: showChemistry ? WindowLayout.recipeMinWidth + 1 + WindowLayout.chemistryMinWidth
                                       : WindowLayout.recipeMinWidth,
               minHeight: WindowLayout.recipeMinHeight)
        .focusedSceneValue(\.chemistryShown, $showChemistry)
        .focusedSceneValue(\.recipeActions, model.isModal ? nil : RecipeActions(
            addMaterial: { recipe.lines.append(BookFactory.line()) },
            blend: { model.blendMode = $0 },
            batchSheet: { model.showBatch = true },
            printBatchSheet: { BatchPrinter.printWithSavedSettings(recipe: recipe, library: library) },
            nudge: { model.nudge = .fromMenu },
            replaceMaterial: { model.replace = ReplaceRequest(materialID: nil) }
        ))
        // In a document window the title is the file name; the subtitle names the recipe (G5 defect 6).
        .navigationSubtitle("\(recipe.name.isEmpty ? "Untitled recipe" : recipe.name) · Cone \(recipe.cone)")
        .onChange(of: currentPoint, initial: true) { _, point in
            if let point { model.record(point, for: recipe.id) }
        }
        #if DEBUG
        // QA only (debug builds): `-FritQASheet triaxial|batch` opens that sheet, for screenshots without clicks.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "FritQASheet") {
            case "triaxial": model.blendMode = .triaxial
            case "batch": model.showBatch = true
            default: break
            }
        }
        #endif
        // The Replace Material, Oxide Nudge, Blend, Batch Sheet and Chemistry toolbar items are in BookWindow,
        // not here (W5 V5): see BookWindow.recipeToolbar for why. Their sheets are here.
        .sheet(item: $model.blendMode) { mode in
            BlendSheet(book: $book, library: library, startRecipeID: recipe.id, initialMode: mode)
        }
        .sheet(isPresented: $model.showBatch) {
            BatchSheet(recipe: recipe, library: library)
        }
        .sheet(item: $model.nudge) { request in
            OxideNudgeSheet(recipe: $recipe, book: $book, library: library, request: request,
                            select: { model.selection = .recipe($0) })
        }
        .sheet(item: $model.replace) { request in
            ReplaceMaterialSheet(recipe: $recipe, book: $book, library: library, request: request,
                                 select: { model.selection = .recipe($0) })
        }
    }

    private var chemistryInspector: some View {
        ScrollView {
            // The Chemistry heading is the first item of the pane, and its baseline lines up with the
            // recipe name's (I6 C6). The settings come under the heading.
            VStack(alignment: .leading, spacing: 14) {
                if !recipe.lines.contains(where: { !$0.materialID.isEmpty }) {
                    // A new recipe: say what to do, not that the calculation failed.
                    Text("Chemistry").font(.title3.weight(.semibold))
                    Label("Choose a material in the table, then enter its amount. The unity formula, the reference ranges and the Stull chart appear here as you type.",
                          systemImage: "arrow.left")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    switch chemistry {
                    case .success(let c):
                        ChemistryPanel(chemistry: c, includeAdditions: $includeAdditions,
                                       incompleteNote: RecipeCheck.chemistryNote(recipe),
                                       onNudge: { oxide, direction in
                                           model.nudge = NudgeRequest(oxide: oxide, direction: direction)
                                       })
                    case .failure(let error):
                        Text("Chemistry").font(.title3.weight(.semibold))
                        Label("The chemistry could not be calculated. \(error.localizedDescription)",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                if let message = AppLibrary.loadErrorMessage {
                    Label(message, systemImage: "exclamationmark.octagon")
                }
            }
            .padding(.horizontal)
            .padding(.top, RecipeLayout.chemistryHeadingTopInset)
            .padding(.bottom)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Chemistry")
    }

    /// The recipe table and, under it, the Stull chart.
    private var recipePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding([.horizontal, .top])
                .padding(.bottom, 8)
            RecipeLinesTable(recipe: $recipe, library: library,
                             onReplace: { model.replace = ReplaceRequest(materialID: $0) })
                // The table takes its full height first; the chart gets what is left (at least its minimum).
                .layoutPriority(1)
            Divider()
            chartSection
                .padding(.horizontal)
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if case .success = chemistry {
            StullChartView(current: currentPoint, trail: model.trails[recipe.id] ?? [], hasBoron: hasBoron)
        } else {
            StullChartView(current: nil, trail: [])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Recipe name", text: $recipe.name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .accessibilityLabel("Recipe name")
                Picker("Cone", selection: $recipe.cone) {
                    ForEach(Cones.all, id: \.self) { Text("Cone \($0)").tag($0) }
                    if !Cones.all.contains(recipe.cone) { Text("Cone \(recipe.cone)").tag(recipe.cone) }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Firing cone")
            }
            TextField("Notes", text: $recipe.notes, axis: .vertical)
                .lineLimit(1...3)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Recipe notes")
        }
    }
}

enum RecipeLayout {
    /// The chemistry pane's top inset. The heading (title3) then sits on the same baseline as the recipe
    /// name (title2 in a plain text field, 16 pt from the top). Checked on a capture (I6 C6).
    static let chemistryHeadingTopInset: CGFloat = 18
}

/// Widths of the recipe table's foot, so that its totals sit under the Amount and % of base columns (I6 C13).
/// The column widths are the ones the table sets; the insets were measured on a capture.
enum TableFoot {
    static let leadingInset: CGFloat = 14
    static let amountWidth: CGFloat = 70
    static let percentWidth: CGFloat = 70
    static let columnGap: CGFloat = 16.5
    static let trailingWidth: CGFloat = 91
}

enum Cones {
    /// Every Orton cone from 022 to 14, in firing order (W6 F3).
    static let all = OrtonCones.all
}

// MARK: - Materials table

struct RecipeLinesTable: View {
    @Binding var recipe: Recipe
    let library: BookLibrary
    /// Opens Replace Material for a base material (row context menu).
    var onReplace: ((String) -> Void)? = nil
    @State private var selection: Set<RecipeLine.ID> = []


    private var baseTotal: Double {
        recipe.lines.filter { !$0.isAddition }.reduce(0) { $0 + $1.amount }
    }

    private var additionTotal: Double {
        recipe.lines.filter { $0.isAddition }.reduce(0) { $0 + $1.amount }
    }

    private func percent(_ line: RecipeLine) -> String {
        guard baseTotal > 0 else { return "–" }
        return fmt(line.amount / baseTotal * 100, 1) + " %"
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(recipe.lines, selection: $selection) {
                TableColumn("Material") { line in
                    HStack(spacing: 4) {
                        MaterialPickerButton(materialID: lineBinding(line.id).materialID, library: library)
                        if RecipeCheck.isMissingMaterial(line) {
                            // An amount without a material: not in the chemistry, and the batch sheet is blocked (W6 F3).
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("This row has an amount but no material. Choose a material or remove the row.")
                                .accessibilityLabel("Row not valid: amount without a material")
                        }
                    }
                }
                .width(min: 130, ideal: 160)
                TableColumn("Amount") { line in
                    LiveNumberField(title: "Amount", value: lineBinding(line.id).amount)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Amount of \(library.name(for: line.materialID))")
                }
                .width(70)
                TableColumn("% of base") { line in
                    Text(percent(line))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel("\(percent(line)) of base")
                }
                .width(70)
                TableColumn("Addition") { line in
                    Toggle("Addition", isOn: lineBinding(line.id).isAddition)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityLabel("\(library.name(for: line.materialID)) is an addition")
                }
                .width(58)
            }
            // As tall as the lines (up to 8 rows), so there is no block of empty rows. When the window is short,
            // the table shrinks to 3 rows and scrolls inside itself; the window does not grow for it (G10).
            .frame(minHeight: WindowLayout.tableMinHeight(lines: recipe.lines.count),
                   idealHeight: WindowLayout.tableIdealHeight(lines: recipe.lines.count),
                   maxHeight: WindowLayout.tableIdealHeight(lines: recipe.lines.count))
            .onDeleteCommand { removeSelected() }
            .contextMenu(forSelectionType: RecipeLine.ID.self) { ids in
                if let onReplace, ids.count == 1, let line = recipe.lines.first(where: { ids.contains($0.id) }),
                   !line.isAddition, library.material(id: line.materialID) != nil {
                    Button("Replace Material…") { onReplace(line.materialID) }
                }
            }
            .accessibilityLabel("Recipe materials")

            // The table foot (I6 C13): the totals in the Amount and % columns, then the small + and − pair.
            Divider()
            totals
            Divider()
            ListFootButtons(addLabel: "Add Material", removeLabel: "Remove Material",
                            add: addLine, remove: removeSelected,
                            canRemove: !selection.isEmpty, addHelp: "Add a material line (Shift-Command-L)") {
                let normalizeProblem = Normalize.problem(recipe)
                Button("Normalize Base to 100") { normalize() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(normalizeProblem != nil)
                    .help(normalizeProblem ?? "Scale every line so that the base adds to 100")
            }
        }
    }

    /// Rows under the table whose numbers sit in the Amount and % of base columns.
    private var totals: some View {
        VStack(spacing: 2) {
            footRow("Base total", amount: fmtAmount(baseTotal), percent: baseTotal > 0 ? "100.0 %" : "–", emphasis: true)
                .accessibilityLabel("Base total \(fmtAmount(baseTotal))")
            if additionTotal > 0 {
                footRow("Additions", amount: fmtAmount(additionTotal),
                        percent: baseTotal > 0 ? fmt(additionTotal / baseTotal * 100, 1) + " %" : "–", emphasis: false)
                    .accessibilityLabel("Additions \(fmtAmount(additionTotal))" + (baseTotal > 0 ? ", \(fmt(additionTotal / baseTotal * 100, 1)) percent of base" : ""))
            }
        }
        .padding(.vertical, 5)
    }

    private func footRow(_ title: String, amount: String, percent: String, emphasis: Bool) -> some View {
        HStack(spacing: 0) {
            Text(title).font(emphasis ? .headline : .body)
                .padding(.leading, TableFoot.leadingInset)
            Spacer(minLength: 8)
            Text(amount).monospacedDigit().fontWeight(emphasis ? .semibold : .regular)
                .frame(width: TableFoot.amountWidth, alignment: .trailing)
            Text(percent).monospacedDigit()
                .frame(width: TableFoot.percentWidth, alignment: .trailing)
                .padding(.leading, TableFoot.columnGap)
            Spacer().frame(width: TableFoot.trailingWidth, height: 0)
        }
        .foregroundStyle(emphasis ? .primary : .secondary)
        .accessibilityElement(children: .ignore)
    }

    private func lineBinding(_ id: UUID) -> Binding<RecipeLine> {
        let fallback = BookFactory.line()
        return Binding(
            get: { recipe.lines.first { $0.id == id } ?? fallback },
            set: { newValue in
                // Skip unchanged write-backs (a number field rewrites its value when it loses focus).
                if newValue.id == id, let i = Edit.indexToReplace(newValue, in: recipe.lines) { recipe.lines[i] = newValue }
            }
        )
    }

    private func addLine() {
        let line = BookFactory.line()
        recipe.lines.append(line)
        selection = [line.id]
    }

    private func removeSelected() {
        recipe.lines.removeAll { selection.contains($0.id) }
        selection = []
    }

    /// Full precision in the book; the table rounds only for display (W6 F2). Nothing changes when the result
    /// would not be finite or would be out of range (`Normalize.base` gives nil).
    private func normalize() {
        guard let scaled = Normalize.base(of: recipe), scaled != recipe else { return }
        recipe.lines = scaled.lines
    }
}


// MARK: - View > Show/Hide Chemistry

struct ChemistryShownKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var chemistryShown: Binding<Bool>? {
        get { self[ChemistryShownKey.self] }
        set { self[ChemistryShownKey.self] = newValue }
    }
}

/// The View menu item that shows or hides the chemistry panel of the front window's recipe.
struct ChemistryCommands: Commands {
    @FocusedValue(\.chemistryShown) private var shown

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(shown?.wrappedValue == false ? "Show Chemistry" : "Hide Chemistry") {
                withAnimation { shown?.wrappedValue.toggle() }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(shown == nil)
        }
    }
}
