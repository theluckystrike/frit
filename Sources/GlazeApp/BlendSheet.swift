import SwiftUI
import GlazeCore

enum BlendMode: String, CaseIterable, Identifiable {
    case line = "Line"
    case triaxial = "Triaxial"
    case grid = "Four-corner grid"
    var id: String { rawValue }

    var cornerCount: Int {
        switch self {
        case .line: return 2
        case .triaxial: return 3
        case .grid: return 4
        }
    }
}

private struct BlendTile: Identifiable {
    var id: Int { number }
    let number: Int
    let recipe: Recipe
    let chemistry: Chemistry?
}

struct BlendSheet: View {
    @Binding var book: GlazeBook
    let library: BookLibrary
    let startRecipeID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tileLedger) private var tileLedger

    @State private var mode: BlendMode
    @State private var corners: [UUID]
    @State private var steps = 5
    @State private var divisions = 5
    @State private var rows = 5
    @State private var columns = 5
    @State private var namePrefix = "Blend"
    @State private var addTestEntries = true
    @State private var addedMessage: String?

    init(book: Binding<GlazeBook>, library: BookLibrary, startRecipeID: UUID, initialMode: BlendMode) {
        self._book = book
        self.library = library
        self.startRecipeID = startRecipeID
        self._mode = State(initialValue: initialMode)
        var ids = [startRecipeID]
        ids += book.wrappedValue.recipes.map(\.id).filter { $0 != startRecipeID }
        while ids.count < 4 { ids.append(ids.last ?? startRecipeID) }
        self._corners = State(initialValue: Array(ids.prefix(4)))
        let name = book.wrappedValue.recipes.first { $0.id == startRecipeID }?.name ?? "Blend"
        self._namePrefix = State(initialValue: name)
    }

    private func recipe(_ id: UUID) -> Recipe? { book.recipes.first { $0.id == id } }

    private var cornerRecipes: [Recipe] {
        corners.prefix(mode.cornerCount).compactMap { recipe($0) }
    }

    /// Why the chosen recipes cannot be blended (for example a recipe with only additions), or nil.
    private var endpointProblem: String? {
        let c = cornerRecipes
        guard c.count == mode.cornerCount else { return nil }
        return Blend.problem(endpoints: c)
    }

    private var tiles: [BlendTile] {
        let c = cornerRecipes
        guard c.count == mode.cornerCount else { return [] }
        let recipes: [Recipe]
        switch mode {
        case .line: recipes = Blend.line(c[0], c[1], steps: steps)
        case .triaxial: recipes = Blend.triaxial(c[0], c[1], c[2], divisions: divisions)
        case .grid: recipes = Blend.grid(corners: c, rows: rows, columns: columns)
        }
        return recipes.enumerated().map { index, r in
            BlendTile(number: index + 1, recipe: r,
                      chemistry: try? GlazeCalculator.chemistry(of: r, library: library, includeAdditions: false))
        }
    }

    private var gridColumns: [GridItem] {
        switch mode {
        case .grid: return Array(repeating: GridItem(.flexible(minimum: 120), spacing: 8, alignment: .top), count: columns)
        // Top alignment: cards with fewer lines sat lower than their neighbours (W5 V4).
        default: return [GridItem(.adaptive(minimum: 170), spacing: 8, alignment: .top)]
        }
    }

    var body: some View {
        let tiles = self.tiles
        VStack(alignment: .leading, spacing: 12) {
            Text("Blend").font(.title2.weight(.semibold))
            controls
            Divider()
            if tiles.isEmpty {
                // W6 F2: an empty or additions-only endpoint gives no tiles; say which recipe and why.
                ContentUnavailableView("No Tiles", systemImage: "square.grid.3x3",
                                       description: Text(endpointProblem ?? "Choose \(mode.cornerCount) recipes to blend."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("\(tiles.count) tiles")
                    .font(.headline)
                ScrollView(.vertical) {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                        ForEach(tiles) { tile in
                            TileCard(tile: tile, library: library, title: tileName(tile))
                        }
                    }
                    .padding(2)
                }
                .accessibilityLabel("Blend tiles")
            }
            Divider()
            HStack {
                TextField("Tile name prefix", text: $namePrefix)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Name prefix for new tiles")
                Toggle("Also add test log entries", isOn: $addTestEntries)
                    .toggleStyle(.checkbox)
                if let addedMessage {
                    Text(addedMessage).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Tiles to Book") { add(tiles) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(tiles.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 760, idealWidth: 920, minHeight: 560, idealHeight: 680)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Blend type", selection: $mode) {
                ForEach(BlendMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .accessibilityLabel("Blend type")

            HStack(alignment: .top, spacing: 16) {
                ForEach(0..<mode.cornerCount, id: \.self) { i in
                    Picker(cornerLabel(i), selection: $corners[i]) {
                        ForEach(book.recipes) { r in Text(r.name).tag(r.id) }
                    }
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Recipe \(cornerLabel(i))")
                }
            }

            switch mode {
            case .line:
                Stepper("Steps: \(steps)", value: $steps, in: 2...21)
                    .accessibilityLabel("Steps")
                    .accessibilityValue("\(steps) steps")
            case .triaxial:
                Stepper("Divisions: \(divisions) (\((divisions + 1) * (divisions + 2) / 2) tiles)", value: $divisions, in: 1...10)
                    .accessibilityLabel("Divisions")
                    .accessibilityValue("\(divisions) divisions, \((divisions + 1) * (divisions + 2) / 2) tiles")
            case .grid:
                HStack(spacing: 24) {
                    Stepper("Rows: \(rows)", value: $rows, in: 2...10)
                        .accessibilityLabel("Rows").accessibilityValue("\(rows)")
                    Stepper("Columns: \(columns)", value: $columns, in: 2...10)
                        .accessibilityLabel("Columns").accessibilityValue("\(columns)")
                }
            }
        }
    }

    private func cornerLabel(_ i: Int) -> String {
        switch mode {
        case .line: return ["A", "B"][i]
        case .triaxial: return ["A", "B", "C"][i]
        case .grid: return ["Top left", "Top right", "Bottom left", "Bottom right"][i]
        }
    }

    private func tileName(_ tile: BlendTile) -> String {
        "\(namePrefix.isEmpty ? "Blend" : namePrefix) – \(tile.recipe.name)"
    }

    private func add(_ tiles: [BlendTile]) {
        // One write to the book, so that Edit > Undo takes back the whole blend in one step.
        var updated = book
        var codes: [String] = []
        for tile in tiles {
            let recipe = BookFactory.duplicate(tile.recipe, name: tileName(tile))
            updated.recipes.append(recipe)
            if addTestEntries {
                var test = BookFactory.test(recipeID: recipe.id, cone: recipe.cone)
                test.notes = "Blend tile \(tile.number)"
                // Codes in blend order: tile 1 gets the first new code (F3).
                codes.append(tileLedger.append(test, to: &updated))
            }
        }
        book = updated
        addedMessage = codes.isEmpty
            ? "Added \(tiles.count) recipes."
            : "Added \(tiles.count) recipes and test tiles \(TileCode.rangeText(codes))."
    }
}

private struct TileCard: View {
    let tile: BlendTile
    let library: BookLibrary
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tile \(tile.number)").font(.headline)
            Text(tile.recipe.name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            ForEach(tile.recipe.lines) { line in
                HStack {
                    Text(library.name(for: line.materialID) + (line.isAddition ? " (add.)" : ""))
                        .lineLimit(1)
                    Spacer()
                    Text(fmtAmount(line.amount)).monospacedDigit()
                }
                .font(.caption)
            }
            Divider()
            if let c = tile.chemistry {
                let si = c.umf[.SiO2] ?? 0, al = c.umf[.Al2O3] ?? 0
                Text("SiO₂ \(fmt(si, 2))  Al₂O₃ \(fmt(al, 2))").font(.caption).monospacedDigit()
                Text("Si:Al \(fmt(c.siAlRatio, 1))  \(Stull.region(siO2: si, al2O3: al).title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No chemistry").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .accessibilityElement(children: .combine)
    }
}
