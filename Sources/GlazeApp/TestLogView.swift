import SwiftUI
import Charts
import UniformTypeIdentifiers
import GlazeCore

struct TestLogView: View {
    @Binding var book: GlazeBook
    /// The search text, filters and selection live in the window model, so the Tests menu can use them (F3).
    @Bindable var model: WindowModel
    let library: BookLibrary
    @Environment(\.tileLedger) private var tileLedger
    @FocusState private var searchFocused: Bool

    private func recipeName(_ id: UUID) -> String {
        book.recipes.first { $0.id == id }?.name ?? "Deleted recipe"
    }

    var body: some View {
        Group {
            if book.tests.isEmpty {
                // One empty state, not an empty striped table beside a "No Test Selected" pane (I6 C11).
                ContentUnavailableView {
                    Label("No Test Tiles", systemImage: "square.grid.3x3")
                } description: {
                    Text(book.recipes.isEmpty
                         ? "Add a recipe first. Then log each test tile with its cone, atmosphere, firing schedule, notes and a photo. Each tile gets a short code for its back and its label."
                         : "Log each test tile with its cone, atmosphere, firing schedule, notes and a photo. Each tile gets a short code for its back and its label.")
                } actions: {
                    Button("Add Test") { addTest() }
                        .buttonStyle(.borderedProminent)
                        .disabled(book.recipes.isEmpty)
                }
            } else {
                testList
            }
        }
        .navigationTitle("Test Log")
        // Open the page on the newest tile, so its schedule and firing ramp show without a click.
        .onAppear {
            if model.testSelection == nil { model.testSelection = book.tests.max(by: { $0.date < $1.date })?.id }
            focusSearchIfAsked()
        }
        .onChange(of: model.wantsTestSearchFocus) { _, _ in focusSearchIfAsked() }
    }

    private func focusSearchIfAsked() {
        guard model.wantsTestSearchFocus else { return }
        model.wantsTestSearchFocus = false
        // After the page is on screen, or the field does not take the focus.
        DispatchQueue.main.async { searchFocused = true }
    }

    private var testList: some View {
        let shown = model.shownTests(book, library: library)
        let duplicates = TileCode.duplicates(in: book.tests)
        // An HStack, not a split view: AppKit split views widened the window to the panes' first widths (G11).
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchBar(shownCount: shown.count)
                if !duplicates.isEmpty {
                    Label("Two or more tiles share the code \(duplicates.joined(separator: ", ")). Give each tile its own code.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .symbolRenderingMode(.multicolor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
                Divider()
                Table(shown, selection: $model.testSelection) {
                    TableColumn("Code") { t in
                        Text(t.code.isEmpty ? "–" : t.code).monospacedDigit().fontWeight(.medium).lineLimit(1)
                            .accessibilityLabel(t.code.isEmpty ? "No code" : "Code \(t.code)")
                    }
                    .width(min: 48, ideal: 56)
                    TableColumn("Date") { t in Text(t.date.formatted(date: .numeric, time: .omitted)) }
                        .width(min: 64, ideal: 72)
                    // Cone and atmosphere share one column. With the Code column, five columns did not fit the
                    // list in a 1024-pt window: the Atmosphere column was cut to its first letter (F3 render).
                    TableColumn("Firing") { t in
                        Text("\(t.cone) · \(t.atmosphere)").lineLimit(1).truncationMode(.tail)
                            .help("Cone \(t.cone), \(t.atmosphere)")
                            .accessibilityLabel("Cone \(t.cone), \(t.atmosphere)")
                    }
                    .width(min: 70, ideal: 90)
                    // The table shares spare width by ideal width, so Recipe has the largest ideal: at 1440 pt a
                    // name such as "Ashfield Dolomite Satin" shows in full. The four ideals still fit the list in a
                    // 1024-pt window, so nothing runs past its edge there (round 3 renders).
                    TableColumn("Recipe") { t in Text(recipeName(t.recipeID)).lineLimit(1).truncationMode(.middle) }
                        .width(min: 60, ideal: 100)
                }
                .onDeleteCommand { deleteSelected() }
                .accessibilityLabel("Test tiles")
                .overlay {
                    if shown.isEmpty {
                        ContentUnavailableView("No Matching Tiles", systemImage: "magnifyingglass",
                                               description: Text("No tile matches the search and filters. Check the code, or clear the search."))
                    }
                }
                Divider()
                ListFootButtons(addLabel: "Add Test", removeLabel: "Delete Test",
                                add: addTest, remove: deleteSelected,
                                canAdd: !book.recipes.isEmpty, canRemove: model.testSelection != nil)
            }
            .frame(minWidth: 320, idealWidth: 420, maxWidth: 600)
            Divider()

            Group {
                if let id = model.testSelection, book.tests.contains(where: { $0.id == id }) {
                    TestTileEditor(test: testBinding(id), recipes: book.recipes,
                                   editCode: { draft, original in
                                       let problem = TileCode.liveEdit(tileID: id, draft: draft, original: original, in: &book)
                                       return (problem, book.tests.first { $0.id == id }?.code ?? original)
                                   },
                                   printLabel: {
                                       model.labelScope = .selected
                                       model.showLabels = true
                                   })
                        .id(id)
                } else {
                    ContentUnavailableView("No Test Selected", systemImage: "square.grid.3x3",
                                           description: Text("Add a test tile, or select one in the list."))
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The search field and the cone and atmosphere filters (F3).
    private func searchBar(shownCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search tests", text: $model.testQuery, prompt: Text("Code, recipe, material or note"))
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { selectSearchHit(onlyMatch: true) }
                    .onChange(of: model.testQuery) { _, _ in selectSearchHit(onlyMatch: false) }
                    .accessibilityLabel("Search tests")
                    .accessibilityHint("Type a tile code, a recipe, a material or a word from the notes")
                if !model.testQuery.isEmpty {
                    Button { model.testQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Clear the search")
                        .accessibilityLabel("Clear the search")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack(spacing: 8) {
                Picker("Cone", selection: $model.testCone) {
                    Text("Any cone").tag(String?.none)
                    ForEach(conesInBook, id: \.self) { Text("Cone \($0)").tag(String?.some($0)) }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Cone filter")
                Picker("Atmosphere", selection: $model.testAtmosphere) {
                    Text("Any atmosphere").tag(String?.none)
                    ForEach(atmospheresInBook, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Atmosphere filter")
                Spacer(minLength: 0)
                Text(model.testFilterActive ? "\(shownCount) of \(book.tests.count)" : "\(book.tests.count) tiles")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel(model.testFilterActive ? "\(shownCount) of \(book.tests.count) tiles shown" : "\(book.tests.count) tiles")
            }
        }
        .padding(10)
    }

    /// Cones used by tiles in this book, in kiln order (the Orton list), then any others. A filter on a cone that
    /// no tile has any more (after a delete) stays in the list, so the picker always shows its selection.
    private var conesInBook: [String] {
        var used = Set(book.tests.map(\.cone))
        if let c = model.testCone { used.insert(c) }
        return Cones.all.filter { used.contains($0) } + used.subtracting(Cones.all).sorted()
    }

    private var atmospheresInBook: [String] {
        var used = Set(book.tests.map(\.atmosphere))
        if let a = model.testAtmosphere { used.insert(a) }
        let known = Atmosphere.allCases.map(\.rawValue)
        return known.filter { used.contains($0) } + used.subtracting(known).sorted()
    }

    /// Typing a code from the back of a tile selects that tile. Return also selects the only match.
    private func selectSearchHit(onlyMatch: Bool) {
        if let hit = TestSearch.exactCode(model.testQuery, in: book.tests) {
            model.testSelection = hit.id
            return
        }
        guard onlyMatch else { return }
        let shown = model.shownTests(book, library: library)
        if shown.count == 1 { model.testSelection = shown[0].id }
    }

    private func testBinding(_ id: UUID) -> Binding<TestTile> {
        let fallback = BookFactory.test(recipeID: UUID(), cone: "6")
        return Binding(
            get: { book.tests.first { $0.id == id } ?? fallback },
            set: { newValue in
                // Unchanged write-backs must not touch the book (they would mark it edited).
                if let i = Edit.indexToReplace(newValue, in: book.tests) { book.tests[i] = newValue }
            }
        )
    }

    private func addTest() {
        // The recipe of the selected tile, so a second tile of the same glaze is one click. Else the first recipe.
        let current = model.testSelection.flatMap { id in book.tests.first { $0.id == id } }
        let recipe = current.flatMap { t in book.recipes.first { $0.id == t.recipeID } } ?? book.recipes.first
        guard let recipe else { return }
        let test = BookFactory.test(recipeID: recipe.id, cone: recipe.cone)
        tileLedger.append(test, to: &book)
        // Clear the search, so the new tile is in the list.
        model.testQuery = ""
        model.testCone = nil
        model.testAtmosphere = nil
        model.testSelection = test.id
    }

    private func deleteSelected() {
        guard let id = model.testSelection else { return }
        // The code is not given again: the book's tile counter does not go back (F3).
        book.tests.removeAll { $0.id == id }
        model.testSelection = nil
    }
}

/// Which tiles the Print Labels sheet prints.
enum LabelScope: String, CaseIterable, Identifiable {
    case all, shown, selected
    var id: String { rawValue }
}

struct TestTileEditor: View {
    @Binding var test: TestTile
    let recipes: [Recipe]
    /// Writes a typed code to the book as the user types (`TileCode.liveEdit`, F3 fix round 2). Takes the draft
    /// and the code at the start of the edit. Returns the problem, if any, and the code the book now has.
    let editCode: (String, String) -> (TileCode.Problem?, String)
    let printLabel: () -> Void
    @State private var choosingPhoto = false
    @State private var photo: NSImage?
    @State private var photoMessage: String?
    @State private var codeDraft = ""
    @State private var codeProblem: TileCode.Problem?
    /// The code when this edit began: the book gets it back while the draft is refused.
    @State private var originalCode = ""
    /// The code that this field last wrote, so its own writes are not taken for Undo or Redo.
    @State private var lastWritten = ""

    var body: some View {
        Form {
            Section("Tile") {
                LabeledContent("Code") {
                    HStack(spacing: 8) {
                        TextField("Code", text: $codeDraft)
                            .labelsHidden()
                            // A bordered field, so the code reads as editable in the grouped form (F3 render).
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .frame(width: 110)
                            // Saved as the user types, so a click on another tile or closing the window does
                            // not lose it (F3 fix round 2: it was saved only on Return or focus loss).
                            .onChange(of: codeDraft) { _, draft in saveCode(draft) }
                            .accessibilityLabel("Tile code")
                            .accessibilityHint("Write this code on the back of the tile. Up to \(TileCode.maxLength) characters.")
                        Button("Print Label…", action: printLabel)
                            .help("Print a label for this tile")
                        Spacer(minLength: 0)
                    }
                }
                if let codeProblem {
                    Label(TileCode.message(codeProblem), systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Write the code on the back of the tile. Type it in the search field to find the tile again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("Recipe", selection: $test.recipeID) {
                    ForEach(recipes) { Text($0.name).tag($0.id) }
                    if !recipes.contains(where: { $0.id == test.recipeID }) {
                        Text("Deleted recipe").tag(test.recipeID)
                    }
                }
                Picker("Cone", selection: $test.cone) {
                    ForEach(Cones.all, id: \.self) { Text("Cone \($0)").tag($0) }
                    if !Cones.all.contains(test.cone) { Text("Cone \(test.cone)").tag(test.cone) }
                }
                Picker("Atmosphere", selection: $test.atmosphere) {
                    ForEach(Atmosphere.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    if Atmosphere(rawValue: test.atmosphere) == nil { Text(test.atmosphere).tag(test.atmosphere) }
                }
                DatePicker("Fired on", selection: $test.date, displayedComponents: .date)
            }

            Section("Firing schedule (°C)") {
                FiringScheduleEditor(schedule: $test.schedule)
                FiringRampChart(schedule: test.schedule)
                    .frame(height: 180)
            }

            Section("Notes") {
                TextEditor(text: $test.notes)
                    .frame(minHeight: 80)
                    .accessibilityLabel("Test notes")
            }

            Section("Photo") {
                if let photo {
                    Image(nsImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .accessibilityLabel("Photo of the test tile")
                }
                if let photoMessage {
                    Text(photoMessage).font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button(test.photoBookmark == nil ? "Choose Photo…" : "Replace Photo…") { choosingPhoto = true }
                    if test.photoBookmark != nil {
                        Button("Remove Photo") {
                            test.photoBookmark = nil
                            photo = nil
                            photoMessage = nil
                        }
                    }
                }
                Text("The book keeps a link to the photo file. The photo itself stays where it is.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingPhoto, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): attachPhoto(url)
            case .failure(let error): photoMessage = "The photo was not added: \(error.localizedDescription)"
            }
        }
        .task(id: test.photoBookmark) { loadPhoto() }
        .onAppear {
            originalCode = test.code
            lastWritten = test.code
            codeDraft = test.code
        }
        // Undo and Redo change the code from outside the field: start a new edit from that code.
        .onChange(of: test.code) { _, code in
            guard code != lastWritten else { return }
            originalCode = code
            lastWritten = code
            codeDraft = code
            codeProblem = nil
        }
    }

    /// Puts the typed code in the book when it passes the checks. Otherwise the book has the code from the start
    /// of the edit, and the field keeps the typed text and says why it was not used.
    private func saveCode(_ draft: String) {
        let (problem, code) = editCode(draft, originalCode)
        lastWritten = code
        // VoiceOver says why a code was refused, once per new reason (R1 F6). The text under the field is not read
        // out by itself.
        if let problem, problem != codeProblem {
            AccessibilityNotification.Announcement(TileCode.message(problem)).post()
        }
        codeProblem = problem
    }

    private func attachPhoto(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            test.photoBookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                      includingResourceValuesForKeys: nil, relativeTo: nil)
            photoMessage = nil
        } catch {
            photoMessage = "The photo link could not be saved: \(error.localizedDescription)"
        }
    }

    private func loadPhoto() {
        guard let bookmark = test.photoBookmark else { photo = nil; return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            photo = NSImage(contentsOf: url)
            if photo == nil { photoMessage = "The photo file could not be read. Choose it again." }
            if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                        includingResourceValuesForKeys: nil, relativeTo: nil) {
                test.photoBookmark = fresh
            }
        } catch {
            photo = nil
            photoMessage = "The photo was moved or is not available. Choose it again."
        }
    }
}

// MARK: - Firing schedule

struct FiringScheduleEditor: View {
    @Binding var schedule: [FiringSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Segment")
                    Text("Rate °C/h")
                    Text("Target °C")
                    Text("Hold min")
                    Text("")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                ForEach(schedule.indices, id: \.self) { i in
                    GridRow {
                        Text("\(i + 1)").monospacedDigit()
                        numberField("Rate", value: segmentBinding(i, \.ratePerHour), label: "Segment \(i + 1) rate in degrees per hour")
                        numberField("Target", value: segmentBinding(i, \.targetC), label: "Segment \(i + 1) target temperature in degrees Celsius")
                        numberField("Hold", value: segmentBinding(i, \.holdMinutes), label: "Segment \(i + 1) hold in minutes")
                        Button {
                            schedule.remove(at: i)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove segment \(i + 1)")
                    }
                }
            }
            HStack {
                Button("Add Segment") {
                    let last = schedule.last
                    schedule.append(BookFactory.segment(rate: last?.ratePerHour ?? 100, target: (last?.targetC ?? 600) + 100, hold: 0))
                }
                Button("Cone 6 Default") { schedule = BookFactory.defaultSchedule() }
                    .help("Replace the schedule with a plain cone 6 glaze firing")
                Spacer()
                Text("Total: \(fmt(FiringMath.totalHours(schedule), 1)) h")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func numberField(_ title: String, value: Binding<Double>, label: String) -> some View {
        // Labels hidden: the column heads name the fields. In a grouped form the titles showed as "Tar…" (G12).
        TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
            .labelsHidden()
            .frame(width: 80)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(label)
    }

    private func segmentBinding(_ i: Int, _ key: WritableKeyPath<FiringSegment, Double>) -> Binding<Double> {
        Binding(
            get: { schedule.indices.contains(i) ? schedule[i][keyPath: key] : 0 },
            set: { newValue in if schedule.indices.contains(i) { schedule[i][keyPath: key] = newValue } }
        )
    }
}

struct RampPoint: Identifiable {
    let id: Int
    let hours: Double
    let celsius: Double
}

enum FiringMath {
    static let roomC = 20.0

    /// Time and temperature points of a schedule. A rate of 0 or less is treated as "as fast as possible".
    static func points(_ schedule: [FiringSegment]) -> [RampPoint] {
        var points = [RampPoint(id: 0, hours: 0, celsius: roomC)]
        var t = 0.0, temp = roomC
        for segment in schedule {
            let rate = abs(segment.ratePerHour)
            if rate > 0 { t += abs(segment.targetC - temp) / rate }
            temp = segment.targetC
            points.append(RampPoint(id: points.count, hours: t, celsius: temp))
            if segment.holdMinutes > 0 {
                t += segment.holdMinutes / 60
                points.append(RampPoint(id: points.count, hours: t, celsius: temp))
            }
        }
        return points
    }

    static func totalHours(_ schedule: [FiringSegment]) -> Double {
        points(schedule).last?.hours ?? 0
    }
}

struct FiringRampChart: View {
    let schedule: [FiringSegment]

    var body: some View {
        let points = FiringMath.points(schedule)
        Chart(points) { p in
            LineMark(x: .value("Hours", p.hours), y: .value("°C", p.celsius))
                .interpolationMethod(.linear)
            PointMark(x: .value("Hours", p.hours), y: .value("°C", p.celsius))
                .symbolSize(20)
        }
        .chartXAxisLabel("Hours")
        .chartYAxisLabel("°C")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Firing ramp chart")
        .accessibilityValue(summary(points))
    }

    private func summary(_ points: [RampPoint]) -> String {
        guard let peak = points.max(by: { $0.celsius < $1.celsius }) else { return "No schedule." }
        return "\(schedule.count) segments. Peak \(fmt(peak.celsius, 0)) degrees Celsius at \(fmt(peak.hours, 1)) hours. Total \(fmt(points.last?.hours ?? 0, 1)) hours."
    }
}
