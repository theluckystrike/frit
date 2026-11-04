import SwiftUI
import AppKit
import GlazeCore

/// A request to open the Oxide Nudge sheet: the oxide, and the arrow that was clicked in the chemistry pane
/// (+1 up, -1 down, 0 from the Recipe menu).
struct NudgeRequest: Identifiable {
    let id = UUID()
    var oxide: Oxide
    var direction: Int

    /// From Recipe > Oxide Nudge… and the toolbar: SiO2, the oxide most often adjusted, at its current value.
    static var fromMenu: NudgeRequest { NudgeRequest(oxide: .SiO2, direction: 0) }
}

/// A request to open the Replace Material sheet, with the material to replace when it came from a table row.
struct ReplaceRequest: Identifiable {
    let id = UUID()
    var materialID: String?
}

/// The size of the Oxide Nudge and Replace Material sheets for the screen of the key window. One fixed size: on
/// macOS 26 a sheet with a minimum and an ideal width opened at the minimum, which cut the content (L2 BUG-1).
@MainActor
private var sheetSize: CGSize {
    let size = WindowLayout.reformulateSheetSize(visible: GlazeMainApp.visibleScreen(NSApp.keyWindow?.screen ?? NSScreen.main))
    return CGSize(width: size.width, height: size.height)
}

// MARK: - Oxide Nudge

/// Recipe > Oxide Nudge… and the arrows next to each UMF value. Changes the amounts of the recipe's materials so
/// that one oxide reaches a target UMF and the other oxides stay as close as they can (`Reformulate.nudge`).
struct OxideNudgeSheet: View {
    @Binding var recipe: Recipe
    @Binding var book: GlazeBook
    let library: BookLibrary
    /// Selects a recipe in the window (for Apply as Copy).
    let select: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var oxide: Oxide
    @State private var target: Double
    /// Materials the user chose to add because no line supplies the oxide.
    @State private var extras: [String] = []

    init(recipe: Binding<Recipe>, book: Binding<GlazeBook>, library: BookLibrary, request: NudgeRequest,
         select: @escaping (UUID) -> Void) {
        self._recipe = recipe
        self._book = book
        self.library = library
        self.select = select
        let before = try? Reformulate.baseChemistry(recipe.wrappedValue, library: library)
        let current = before?.umf[request.oxide] ?? 0
        self._oxide = State(initialValue: request.oxide)
        // From the menu (direction 0) the target starts at the current value, so nothing changes until the user
        // sets one. From an arrow it starts one step up or down, rounded to 3 decimals.
        let start = request.direction == 0 ? current : Self.rounded(max(0, current + Double(request.direction) * Reformulate.step))
        self._target = State(initialValue: start)
    }

    private static func rounded(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    private var before: Chemistry? { try? Reformulate.baseChemistry(recipe, library: library) }

    private var current: Double { before?.umf[oxide] ?? 0 }

    private var result: Result<Adjustment, Error> {
        Result { try Reformulate.nudge(recipe, oxide: oxide, toUMF: target, library: library, extraMaterialIDs: extras) }
    }

    /// Oxides in the recipe first, then the others.
    private var oxideChoices: (present: [Oxide], other: [Oxide]) {
        let present = Oxide.allCases.filter { (before?.umf[$0] ?? 0) > 0.00005 }
        return (present, Oxide.allCases.filter { !present.contains($0) })
    }

    var body: some View {
        let result = self.result
        VStack(alignment: .leading, spacing: 12) {
            Text("Oxide Nudge").font(.title2.weight(.semibold))
            Text("\(AppInfo.name) changes the amounts of the materials in this recipe so that one oxide reaches the target in the unity formula, when these materials can reach it. The other oxides stay as close to their current values as these materials allow, and the amounts stay as near their current values as they can. The new base is scaled to 100. Additions are not changed and are not counted here.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            controls
            Divider()
            switch result {
            case .success(let adjustment):
                AdjustmentSummary(original: recipe, adjustment: adjustment, library: library,
                                  targetTitle: "Target", missText: missText)
            case .failure(let error):
                failure(error)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply as Copy") { if case .success(let a) = result { applyAsCopy(a) } }
                    .disabled(!canApply(result))
                    .help("Add the changed recipe to the book as a new recipe. This recipe stays as it is.")
                Button("Apply") { if case .success(let a) = result { apply(a) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canApply(result))
                    .help("Change this recipe. Edit > Undo takes it back.")
            }
        }
        .padding(WindowLayout.sheetPadding)
        .frame(width: sheetSize.width, height: sheetSize.height)
    }

    private var controls: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Picker("Oxide", selection: $oxide) {
                ForEach(oxideChoices.present, id: \.self) { Text($0.formula).tag($0) }
                Divider()
                ForEach(oxideChoices.other, id: \.self) { Text($0.formula).tag($0) }
            }
            .fixedSize()
            .onChange(of: oxide) { _, _ in
                target = current
                extras = []
            }
            Text("Now \(fmt(current, 3))").monospacedDigit().foregroundStyle(.secondary)
                .accessibilityLabel("Current UMF \(fmt(current, 3))")
            HStack(spacing: 4) {
                Text("Target UMF")
                LiveNumberField(title: "Target UMF", value: $target, fractionDigits: 0...3)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Target UMF for \(oxide.spoken)")
                Stepper("Target UMF", value: $target, in: 0...50, step: Reformulate.step)
                    .labelsHidden()
                    .accessibilityLabel("Change the target by \(fmt(Reformulate.step, 2))")
            }
            Text("Change \(signed(target - current))").monospacedDigit().foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func failure(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .fixedSize(horizontal: false, vertical: true)
            if case ReformulateError.noSource(let o) = error {
                let sources = Reformulate.suggestedSources(for: o, library: library)
                if !sources.isEmpty {
                    Text("Add one of these materials to the calculation:").foregroundStyle(.secondary)
                    HStack {
                        ForEach(sources) { m in
                            Button("Add \(m.name)") { extras.append(m.id) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func missText(_ o: Oxide, _ d: Double, _ adjustment: Adjustment) -> String {
        Reformulate.nudgeMissText(o, d, nudged: oxide)
    }

    private func canApply(_ result: Result<Adjustment, Error>) -> Bool {
        guard case .success(let a) = result else { return false }
        return linesDiffer(a.recipe, recipe)
    }

    private func apply(_ a: Adjustment) {
        recipe.lines = a.recipe.lines
        dismiss()
    }

    private func applyAsCopy(_ a: Adjustment) {
        let name = "\(recipe.name.isEmpty ? "Untitled recipe" : recipe.name) – \(oxide.formula) \(fmt(target, 2))"
        let copy = BookFactory.duplicate(a.recipe, name: name)
        let index = (book.recipes.firstIndex { $0.id == recipe.id }).map { $0 + 1 } ?? book.recipes.count
        book.recipes.insert(copy, at: index)
        dismiss()
        select(copy.id)
    }
}

// MARK: - Replace Material

/// Recipe > Replace Material… and the row context menu. Puts another material in place of one base material and
/// solves the new amounts so that the unity formula matches the original as closely as it can
/// (`Reformulate.replace`).
struct ReplaceMaterialSheet: View {
    @Binding var recipe: Recipe
    @Binding var book: GlazeBook
    let library: BookLibrary
    let select: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var oldID: String
    @State private var newID = ""

    init(recipe: Binding<Recipe>, book: Binding<GlazeBook>, library: BookLibrary, request: ReplaceRequest,
         select: @escaping (UUID) -> Void) {
        self._recipe = recipe
        self._book = book
        self.library = library
        self.select = select
        let ids = Self.baseMaterialIDs(recipe.wrappedValue, library: library)
        let start = request.materialID.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first ?? ""
        self._oldID = State(initialValue: start)
    }

    static func baseMaterialIDs(_ r: Recipe, library: BookLibrary) -> [String] {
        var ids: [String] = []
        for line in r.lines where !line.isAddition && !line.materialID.isEmpty && library.material(id: line.materialID) != nil {
            if !ids.contains(line.materialID) { ids.append(line.materialID) }
        }
        return ids
    }

    private var result: Result<Adjustment, Error>? {
        guard !oldID.isEmpty, !newID.isEmpty else { return nil }
        return Result { try Reformulate.replace(recipe, materialID: oldID, with: newID, library: library) }
    }

    var body: some View {
        let result = self.result
        VStack(alignment: .leading, spacing: 12) {
            Text("Replace Material").font(.title2.weight(.semibold))
            Text("Choose a base material and the material to use in its place. \(AppInfo.name) works out new amounts for the new material and the other base materials, so that the unity formula stays as close to the original as these materials allow, and the other amounts stay as near their current values as they can. Additions are not changed.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Picker("Replace", selection: $oldID) {
                    ForEach(Self.baseMaterialIDs(recipe, library: library), id: \.self) { id in
                        Text(library.name(for: id)).tag(id)
                    }
                }
                .frame(maxWidth: 300)
                HStack(spacing: 6) {
                    Text("With")
                    MaterialPickerButton(materialID: $newID, library: library)
                        .frame(width: 260)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            Divider()
            switch result {
            case nil where Self.baseMaterialIDs(recipe, library: library).isEmpty:
                Text("This recipe has no base materials to replace. Choose materials in the recipe table first.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case nil:
                Text("Choose the material to use in its place.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .success(let adjustment):
                AdjustmentSummary(original: recipe, adjustment: adjustment, library: library,
                                  targetTitle: "Original", missText: missText)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Text("A matching unity formula does not promise the same glaze. Particle size, impurities and the real analysis of your materials also matter. Test the new recipe on tiles.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Replace in This Recipe") { if case .success(let a)? = result { apply(a) } }
                    .disabled(!canApply(result))
                    .help("Change this recipe. Edit > Undo takes it back.")
                Button("Save as New Recipe") { if case .success(let a)? = result { saveAsNew(a) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canApply(result))
                    .help("Add the new recipe to the book. This recipe and its test log entries stay as they are.")
            }
        }
        .padding(WindowLayout.sheetPadding)
        .frame(width: sheetSize.width, height: sheetSize.height)
    }

    private func missText(_ o: Oxide, _ d: Double, _ adjustment: Adjustment) -> String {
        Reformulate.replaceMissText(o, d, adjustment: adjustment)
    }

    private func canApply(_ result: Result<Adjustment, Error>?) -> Bool {
        guard case .success(let a)? = result else { return false }
        return a.recipe.lines != recipe.lines
    }

    private func apply(_ a: Adjustment) {
        recipe.lines = a.recipe.lines
        dismiss()
    }

    private func saveAsNew(_ a: Adjustment) {
        let name = "\(recipe.name.isEmpty ? "Untitled recipe" : recipe.name) with \(library.name(for: newID))"
        let copy = BookFactory.duplicate(a.recipe, name: name)
        let index = (book.recipes.firstIndex { $0.id == recipe.id }).map { $0 + 1 } ?? book.recipes.count
        book.recipes.insert(copy, at: index)
        dismiss()
        select(copy.id)
    }
}

// MARK: - Before and after

/// The result of a nudge or a replacement: the materials before and after, the UMF before, aimed for and after,
/// the oxides that missed, and both points on the Stull chart.
private struct AdjustmentSummary: View {
    let original: Recipe
    let adjustment: Adjustment
    let library: BookLibrary
    /// Title of the column with the UMF the solver aimed for ("Target" or "Original").
    let targetTitle: String
    let missText: (Oxide, Double, Adjustment) -> String

    private struct MaterialRow: Identifiable {
        var id: String
        var before: Double
        var after: Double
    }

    private var materialRows: [MaterialRow] {
        var order: [String] = []
        var before: [String: Double] = [:], after: [String: Double] = [:]
        for l in original.lines where !l.isAddition && !l.materialID.isEmpty {
            if !order.contains(l.materialID) { order.append(l.materialID) }
            before[l.materialID, default: 0] += max(0, l.amount)
        }
        for l in adjustment.recipe.lines where !l.isAddition && !l.materialID.isEmpty {
            if !order.contains(l.materialID) { order.append(l.materialID) }
            after[l.materialID, default: 0] += max(0, l.amount)
        }
        return order.map { MaterialRow(id: $0, before: before[$0] ?? 0, after: after[$0] ?? 0) }
    }

    private var oxides: [Oxide] {
        Oxide.allCases.filter { o in
            [adjustment.before.umf[o], adjustment.after.umf[o], adjustment.target[o]].contains { ($0 ?? 0) > 0.00005 }
                || adjustment.residual[o] != nil
        }
    }

    private func point(_ c: Chemistry) -> StullPoint? {
        let si = c.umf[.SiO2] ?? 0, al = c.umf[.Al2O3] ?? 0
        guard si.isFinite, al.isFinite, si > 0 || al > 0 else { return nil }
        return StullPoint(siO2: si, al2O3: al)
    }

    var body: some View {
        HStack(alignment: .top, spacing: WindowLayout.reformulateColumnSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    status
                    materialsTable
                    oxideTable
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: WindowLayout.reformulateListMinWidth)
            StullChartView(current: point(adjustment.after),
                           trail: [point(adjustment.before), point(adjustment.after)].compactMap { $0 },
                           hasBoron: (adjustment.after.umf[.B2O3] ?? 0) > 0.00005,
                           isComparison: true)
                .frame(minWidth: WindowLayout.reformulateChartMinWidth, maxWidth: WindowLayout.reformulateChartMaxWidth)
        }
    }

    @ViewBuilder
    private var status: some View {
        if adjustment.isExact {
            Label("Every oxide reaches its \(targetTitle.lowercased()) value.", systemImage: "checkmark.circle")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(oxides.filter { adjustment.residual[$0] != nil }, id: \.self) { o in
                    Label(missText(o, adjustment.residual[o] ?? 0, adjustment), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var materialsTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 3) {
            GridRow {
                Text("Material").gridColumnAlignment(.leading)
                Text("Now")
                Text("New")
                Text("Change")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            ForEach(materialRows) { row in
                GridRow {
                    Text(library.name(for: row.id)).lineLimit(1).truncationMode(.middle)
                        .gridColumnAlignment(.leading)
                        .accessibilityLabel("\(library.name(for: row.id)), now \(fmtAmount(row.before)), new \(fmtAmount(row.after))")
                    Group {
                        Text(fmtAmount(row.before))
                        Text(fmtAmount(row.after)).fontWeight(abs(row.after - row.before) > 0.005 ? .semibold : .regular)
                        Text(signedAmount(row.after - row.before)).foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                    .accessibilityHidden(true)
                }
            }
            GridRow {
                Text("Base total").fontWeight(.semibold).gridColumnAlignment(.leading)
                Text(fmtAmount(original.baseTotal)).monospacedDigit()
                Text(fmtAmount(adjustment.recipe.baseTotal)).monospacedDigit()
                Text("")
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Materials, now and new")
    }

    private var oxideTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 3) {
            GridRow {
                Text("Oxide (UMF)").gridColumnAlignment(.leading)
                Text("Now")
                Text(targetTitle)
                Text("New")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            ForEach(oxides, id: \.self) { o in
                let missed = adjustment.residual[o] != nil
                GridRow {
                    Text(o.formula).gridColumnAlignment(.leading)
                        .accessibilityLabel("\(o.spoken), now \(fmt(adjustment.before.umf[o] ?? 0, 3)), \(targetTitle.lowercased()) \(fmt(adjustment.target[o] ?? 0, 3)), new \(fmt(adjustment.after.umf[o] ?? 0, 3))" + (missed ? ", missed" : ""))
                    Group {
                        Text(fmt(adjustment.before.umf[o] ?? 0, 3))
                        Text(fmt(adjustment.target[o] ?? 0, 3)).foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            if missed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            Text(fmt(adjustment.after.umf[o] ?? 0, 3)).fontWeight(missed ? .bold : .regular)
                        }
                    }
                    .monospacedDigit()
                    .accessibilityHidden(true)
                }
            }
            GridRow {
                Text("SiO₂ : Al₂O₃").gridColumnAlignment(.leading)
                Text(fmt(adjustment.before.siAlRatio, 2))
                Text("")
                Text(fmt(adjustment.after.siAlRatio, 2))
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unity formula, now and new")
    }
}

/// True when the recipes differ in a material or in an amount by more than rounding noise.
private func linesDiffer(_ a: Recipe, _ b: Recipe) -> Bool {
    guard a.lines.count == b.lines.count else { return true }
    let tol = 1e-9 * max(1, b.baseTotal)
    return zip(a.lines, b.lines).contains { x, y in
        x.materialID != y.materialID || x.isAddition != y.isAddition || abs(x.amount - y.amount) > tol
    }
}

/// "+1.25" or "−0.40"; "0" when the change rounds to 0.
private func signedAmount(_ v: Double) -> String {
    if abs(v) < 0.005 { return "0" }
    return (v > 0 ? "+" : "−") + fmtAmount(abs(v))
}

private func signed(_ v: Double) -> String {
    if abs(v) < 0.0005 { return "0" }
    return (v > 0 ? "+" : "−") + fmt(abs(v), 3)
}
