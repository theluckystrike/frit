import SwiftUI
import GlazeCore

/// A button that shows the chosen material and opens a searchable list.
struct MaterialPickerButton: View {
    @Binding var materialID: String
    let library: BookLibrary
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            HStack(spacing: 4) {
                Text(library.name(for: materialID))
                    .foregroundStyle(materialID.isEmpty || library.material(id: materialID) == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(library.name(for: materialID))
        .accessibilityLabel("Material: \(library.name(for: materialID))")
        .accessibilityHint("Opens a searchable list of materials")
        .popover(isPresented: $isOpen, arrowEdge: .trailing) {
            MaterialSearchList(library: library, selectedID: materialID) { id in
                materialID = id
                isOpen = false
            }
        }
    }
}

struct MaterialSearchList: View {
    let library: BookLibrary
    let selectedID: String
    let onPick: (String) -> Void

    @State private var query = ""
    @State private var highlighted: String?
    @FocusState private var searchFocused: Bool

    private var results: [Material] { MaterialSearch.filter(library.all, query: query) }

    /// The material that Return or Choose takes: only one that the list shows (W6 C1).
    private func pickable(fallbackToFirst: Bool) -> String? {
        MaterialSearch.pick(highlighted: highlighted, resultIDs: results.map(\.id), fallbackToFirst: fallbackToFirst)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search materials", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityLabel("Search materials")
                .onSubmit {
                    if let id = pickable(fallbackToFirst: true) { onPick(id) }
                }
                .onChange(of: query) { _, _ in
                    // A highlight that the new search hides is cleared, so that Return cannot take it.
                    let kept = MaterialSearch.keptHighlight(highlighted, resultIDs: results.map(\.id))
                    if kept != highlighted { highlighted = kept }
                }
            List(results, selection: $highlighted) { material in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(material.name)
                        if library.isCustom(material.id) {
                            Text("custom").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(summary(material))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(material.id)
                .accessibilityElement(children: .combine)
                .onTapGesture(count: 2) { onPick(material.id) }
            }
            .frame(minHeight: 260)
            .onKeyPress(.return) {
                if let id = pickable(fallbackToFirst: false) { onPick(id); return .handled }
                return .ignored
            }
            .accessibilityLabel("Materials")
            HStack {
                Text(MaterialSearch.countText(results.count)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Choose") { if let id = pickable(fallbackToFirst: false) { onPick(id) } }
                    .disabled(pickable(fallbackToFirst: false) == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 340, height: 400)
        .onAppear {
            highlighted = MaterialSearch.keptHighlight(selectedID.isEmpty ? nil : selectedID,
                                                       resultIDs: results.map(\.id))
            searchFocused = true
        }
    }

    private func summary(_ m: Material) -> String {
        let top = m.analysis.sorted { $0.value > $1.value }.prefix(3)
        return top.map { "\($0.key.display) \(fmt($0.value, 1))" }.joined(separator: ", ")
    }
}
