import SwiftUI
import GlazeCore

struct MaterialsView: View {
    @Binding var book: GlazeBook

    enum Scope: String, CaseIterable, Identifiable {
        // Short labels (I6 C8). The detail pane says that bundled materials are read-only.
        case bundled = "Bundled"
        case custom = "Custom"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .bundled
    @State private var query = ""
    @State private var bundledSelection: String?
    @State private var customSelection: String?
    /// Set when Delete Material is refused because recipes use the material.
    @State private var deleteBlocked: String?

    private var bundled: [Material] {
        filter(AppLibrary.bundledMaterials)
    }

    private func filter(_ list: [Material]) -> [Material] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q) || $0.source.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Materials", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
                .accessibilityLabel("Material list")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            Divider()
            switch scope {
            case .bundled: bundledView
            case .custom: customView
            }
        }
        .navigationTitle("Materials")
        // The system search field in the toolbar, in place of a text field in the content (I6 C8).
        .searchable(text: $query, placement: .toolbar, prompt: "Search materials")
    }

    // MARK: Bundled

    // HStacks, not split views: AppKit split views widened the window to the sum of the panes' first widths (G11).
    private var bundledView: some View {
        HStack(spacing: 0) {
            Table(bundled, selection: $bundledSelection) {
                // No Source column: it truncated in every row. The detail pane shows the source (I6 C8).
                TableColumn("Name") { m in Text(m.name).lineLimit(1).truncationMode(.middle).help(m.name) }
                    .width(min: 180, ideal: 260)
                TableColumn("LOI %") { m in
                    Text(fmt(m.loi, 1)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 45, ideal: 55, max: 70)
            }
            .frame(minWidth: 360, maxWidth: .infinity)
            .layoutPriority(1)
            .accessibilityLabel("Bundled materials")
            Divider()
            Group {
                if let id = bundledSelection, let m = AppLibrary.bundledMaterials.first(where: { $0.id == id }) {
                    ScrollView { MaterialAnalysisView(material: m, readOnly: true).padding() }
                } else {
                    ContentUnavailableView("Select a Material", systemImage: "shippingbox",
                                           description: Text("Bundled materials are read-only. To change one, duplicate it as a custom material."))
                }
            }
            .frame(minWidth: 300, idealWidth: 380, maxWidth: 460, maxHeight: .infinity)
        }
        .overlay(alignment: .bottomLeading) {
            if let id = bundledSelection, let m = AppLibrary.bundledMaterials.first(where: { $0.id == id }) {
                Button("Duplicate as Custom Material") { duplicate(m) }
                    .padding()
            }
        }
    }

    // MARK: Custom

    private var customView: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(filter(book.customMaterials), selection: $customSelection) { m in
                    VStack(alignment: .leading) {
                        Text(m.name)
                        Text(m.id).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    .tag(m.id)
                    .accessibilityElement(children: .combine)
                }
                .onDeleteCommand { deleteSelectedCustom() }
                .overlay {
                    if book.customMaterials.isEmpty {
                        Text("No custom materials").foregroundStyle(.secondary)
                    }
                }
                Divider()
                ListFootButtons(addLabel: "Add Material", removeLabel: "Delete Material",
                                add: addCustom, remove: deleteSelectedCustom, canRemove: customSelection != nil)
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            Divider()

            Group {
                if let id = customSelection, book.customMaterials.contains(where: { $0.id == id }) {
                    CustomMaterialEditor(material: customBinding(id), inUse: isInUse(id))
                        .id(id)
                } else {
                    ContentUnavailableView("No Custom Material Selected", systemImage: "shippingbox",
                                           description: Text("Add a material with your own oxide analysis, LOI and source."))
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("This Material Is in Use", isPresented: Binding(get: { deleteBlocked != nil },
                                                              set: { if !$0 { deleteBlocked = nil } })) {
            Button("OK", role: .cancel) { deleteBlocked = nil }
        } message: {
            Text(deleteBlocked ?? "")
        }
    }

    private func isInUse(_ id: String) -> Bool {
        book.recipes.contains { r in r.lines.contains { $0.materialID == id } }
    }

    private func customBinding(_ id: String) -> Binding<Material> {
        let fallback = Material(id: id, name: "", analysis: [:], loi: 0, source: "")
        return Binding(
            get: { book.customMaterials.first { $0.id == id } ?? fallback },
            set: { newValue in
                // Unchanged write-backs must not touch the book (they would mark it edited).
                if let i = Edit.indexToReplace(newValue, in: book.customMaterials) { book.customMaterials[i] = newValue }
            }
        )
    }

    private func addCustom() {
        let m = BookFactory.customMaterial(in: book)
        book.customMaterials.append(m)
        scope = .custom
        customSelection = m.id
    }

    private func duplicate(_ m: Material) {
        var copy = BookFactory.customMaterial(in: book)
        copy.name = "\(m.name) (custom)"
        copy.analysis = m.analysis
        copy.loi = m.loi
        copy.source = "Copied from bundled \(m.id): \(m.source)"
        book.customMaterials.append(copy)
        scope = .custom
        customSelection = copy.id
    }

    /// A material that recipes use is not deleted (W6 C1: the recipes kept a dangling id, and a later new
    /// material could take it over). An alert names the recipes.
    private func deleteSelectedCustom() {
        guard let id = customSelection else { return }
        let name = book.customMaterials.first { $0.id == id }?.name ?? id
        if let message = MaterialRules.deleteBlockedMessage(materialName: name,
                                                            recipeNames: MaterialRules.recipesUsing(id, in: book)) {
            deleteBlocked = message
            return
        }
        book.customMaterials.removeAll { $0.id == id }
        customSelection = nil
    }
}

struct MaterialAnalysisView: View {
    let material: Material
    var readOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(material.name).font(.title3.weight(.semibold))
            if readOnly {
                Label("Bundled material, read-only. To change it, duplicate it as a custom material.", systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Id: \(material.id)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            LabeledContent("Loss on ignition", value: "\(fmt(material.loi, 2)) %")
            VStack(alignment: .leading, spacing: 2) {
                Text("Source").font(.headline)
                Text(material.source)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Text("Oxide analysis (weight %)").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                ForEach(Oxide.allCases.filter { (material.analysis[$0] ?? 0) > 0 }, id: \.self) { oxide in
                    GridRow {
                        Text(oxide.display)
                        Text(fmt(material.analysis[oxide] ?? 0, 2)).monospacedDigit().gridColumnAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(oxide.spoken) \(fmt(material.analysis[oxide] ?? 0, 2)) percent")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomMaterialEditor: View {
    @Binding var material: Material
    let inUse: Bool

    private var total: Double {
        material.analysis.values.reduce(0, +) + material.loi
    }

    private var issues: [MaterialRules.Issue] { MaterialRules.issues(material) }

    var body: some View {
        Form {
            Section("Material") {
                TextField("Name", text: $material.name)
                LabeledContent("Id") { Text(material.id).textSelection(.enabled) }
                PercentField(title: "Loss on ignition (%)", value: $material.loi, fractionDigits: 0...2)
                TextField("Source", text: $material.source, prompt: Text("Data sheet, supplier or lab analysis"))
                if inUse {
                    Text("Recipes in this book use this material. Changes update their chemistry.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !issues.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("This analysis is not valid. The chemistry leaves this material out until you correct it.",
                              systemImage: "exclamationmark.octagon")
                            .foregroundStyle(.red)
                        ForEach(issues.indices, id: \.self) { i in
                            Text(issues[i].message).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                ForEach(Oxide.allCases, id: \.self) { oxide in
                    PercentField(title: oxide.display, value: oxideBinding(oxide), fractionDigits: 0...3,
                                 spokenName: "\(oxide.spoken) weight percent")
                }
            } header: {
                Text("Oxide analysis (weight %)")
            } footer: {
                HStack(spacing: 4) {
                    let ok = abs(total - 100) <= 1
                    Image(systemName: ok ? "checkmark.circle" : "exclamationmark.triangle")
                    Text("Oxides + LOI = \(fmt(total, 2)) %\(ok ? "" : " (expected about 100 %)")")
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
        .formStyle(.grouped)
    }

    private func oxideBinding(_ oxide: Oxide) -> Binding<Double> {
        Binding(
            get: { material.analysis[oxide] ?? 0 },
            set: { newValue in
                // The field only writes values from 0 to 100. A 0 removes the oxide from the analysis.
                let stored: Double? = newValue > 0 ? newValue : nil
                if material.analysis[oxide] != stored { material.analysis[oxide] = stored }
            }
        )
    }
}

/// A percent field (0 to 100) for a custom material. A negative value, a value above 100 or text that is not a
/// number is not taken: the field shows an error under it and the stored value stays as it was (W6 C1:
/// "250" was taken and "-5" silently removed the oxide). A stored value out of range (from an older or
/// edited file) also shows the error. Only typing writes, as in `LiveNumberField`.
struct PercentField: View {
    let title: String
    @Binding var value: Double
    var fractionDigits: ClosedRange<Int> = 0...2
    var spokenName: String?

    @State private var text = ""
    @FocusState private var focused: Bool

    private var entry: MaterialRules.PercentEntry { MaterialRules.parsePercent(text) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            TextField(title, text: $text)
                .focused($focused)
                .accessibilityLabel(spokenName ?? title)
                .accessibilityValue(entry.error.map { "\(text), \($0)" } ?? text)
                .onAppear { text = format(value) }
                .onChange(of: value) { _, new in
                    if !focused || entry != .value(new) { text = format(new) }
                }
                .onChange(of: text) { _, _ in
                    guard focused, case .value(let v) = entry, v != value else { return }
                    value = v
                }
                .onChange(of: focused) { _, isFocused in
                    // A valid entry is shown formatted again. An invalid one stays, with its error, until corrected.
                    if !isFocused, entry.error == nil { text = format(value) }
                }
            if let error = entry.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            }
        }
    }

    private func format(_ v: Double) -> String {
        v.isFinite ? NumberText.format(v, fractionDigits: fractionDigits) : String(v)
    }
}
