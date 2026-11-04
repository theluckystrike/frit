import SwiftUI
import AppKit
import GlazeCore

enum SidebarItem: Hashable {
    case recipe(UUID)
    case tests
    case materials
}

struct StullPoint: Hashable {
    var siO2: Double
    var al2O3: Double
}

/// State that belongs to one window, not to the document.
@MainActor
@Observable
final class WindowModel {
    var selection: SidebarItem?
    /// The last positions of each recipe on the Stull chart, oldest first. The last item is the current one.
    var trails: [UUID: [StullPoint]] = [:]
    /// The blend sheet to show for the selected recipe (toolbar Blend menu, Recipe menu).
    var blendMode: BlendMode?
    /// Whether the batch sheet of the selected recipe is shown (toolbar, Recipe menu).
    var showBatch = false
    /// Whether the Rename Recipe alert or the Delete Recipe dialog is shown.
    var dialogShown = false
    /// The Oxide Nudge sheet to show for the selected recipe (Recipe menu, chemistry pane arrows).
    var nudge: NudgeRequest?
    /// The Replace Material sheet to show for the selected recipe (Recipe menu, table row context menu).
    var replace: ReplaceRequest?
    /// The Tests page: search text, cone and atmosphere filters and the selected tile (F3). Kept with the window,
    /// so that they stay when the reader looks at a recipe and comes back, and so the menus can use them.
    var testQuery = ""
    var testCone: String?
    var testAtmosphere: String?
    var testSelection: TestTile.ID?
    /// Set by Tests > Find Test; the Tests page puts the focus in its search field and clears it.
    var wantsTestSearchFocus = false
    /// Whether the Print Labels sheet is shown, and which tiles it starts with (F3).
    var showLabels = false
    var labelScope: LabelScope = .all

    /// True when the search field or a filter limits the tiles that the Tests page shows.
    var testFilterActive: Bool {
        !testQuery.trimmingCharacters(in: .whitespaces).isEmpty || testCone != nil || testAtmosphere != nil
    }

    /// The tiles that the Tests page shows, in book order.
    func shownTests(_ book: GlazeBook, library: BookLibrary) -> [TestTile] {
        guard testFilterActive else { return book.tests }
        return TestSearch.filter(book.tests, recipes: book.recipes, materialNames: TestSearch.materialNames(library),
                                 query: testQuery, cone: testCone, atmosphere: testAtmosphere)
    }

    /// True while a sheet, alert or dialog covers the window. The Recipe, View and File menu actions are off
    /// then (W6 X4: with Rename Recipe open, Duplicate Recipe, Add Material and View > Materials still
    /// changed the book behind the alert).
    var isModal: Bool { blendMode != nil || showBatch || dialogShown || nudge != nil || replace != nil || showLabels }

    func record(_ point: StullPoint, for recipeID: UUID) {
        var trail = trails[recipeID] ?? []
        if let last = trail.last, abs(last.siO2 - point.siO2) < 1e-6, abs(last.al2O3 - point.al2O3) < 1e-6 {
            return
        }
        trail.append(point)
        if trail.count > 6 { trail.removeFirst(trail.count - 6) }
        trails[recipeID] = trail
    }
}

struct BookWindow: View {
    @Binding var document: GlazeDocument
    /// True for a new book that has no file yet.
    let isUntitled: Bool
    @State private var model = WindowModel()
    /// The note in the sample book's sidebar. The reader can close it.
    @State private var sampleNoteClosed = false
    /// The note about tile codes given on open (R1 F1). Shown once per window until closed.
    @State private var codeNoteClosed = false
    /// Goes up when the document must be marked changed outside Undo (R1 F5).
    @State private var changeMark = 0
    @AppStorage(FirstLaunch.defaultsKey) private var firstLaunchDone = false
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var pendingDelete: UUID?
    /// The selected sidebar item, kept with the window so that window restoration reopens it (G11).
    /// "tests", "materials" or a recipe UUID.
    @SceneStorage("sidebarSelection") private var savedSelection = ""
    @Environment(\.newDocument) private var newDocument
    /// Whether the chemistry pane of a recipe is shown. Kept per window and restored with the window.
    @SceneStorage("showChemistry") private var showChemistry = true

    private var library: BookLibrary { BookLibrary(custom: document.book.customMaterials) }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: WindowLayout.sidebarMinWidth, ideal: 220, max: 360)
        } detail: {
            detail
        }
        // AppKit gives the first text field (the recipe name) the focus with its text selected.
        // Clear that once when the window opens, so no field starts in edit mode (G5 defect 2).
        .background(NoInitialTextFocus())
        // A window from File > New or Help > Open Sample Book does not always get the scene's default size, and
        // the sample book's window opened 1862 pt tall, taller than the screen (G12). Fit it to the default size.
        .background(FitWindowToScreen())
        .background(DocumentChangeMarker(token: changeMark))
        // Undo of Add Test or a blend can bring the undo count back to the saved state, so the document looks
        // unchanged and the issued tile number would be lost on close. Mark it changed, outside Undo, so the save
        // writes the counter and a reopened book never gives the undone code again (R1 F5).
        .onChange(of: document.book.nextTileNumber) { _, _ in
            if document.tileLedger.needsSave(document.book) { changeMark += 1 }
        }
        #if DEBUG
        .background(QALayoutLogger())
        #endif
        // The views that add tiles (Tests page, blends) take codes from this document's ledger (F3 fix round 2).
        .environment(\.tileLedger, document.tileLedger)
        .toolbarRole(.editor)
        .toolbar(id: ToolbarIDs.book) { recipeToolbar }
        .onAppear {
            // The first launch shows the sample book in place of the empty untitled book (I6 C2, FirstLaunch).
            if !firstLaunchDone {
                let openSample = FirstLaunch.shouldOpenSample(firstLaunchDone: firstLaunchDone, isUntitled: isUntitled,
                                                              book: document.book)
                firstLaunchDone = true
                if openSample {
                    newDocument(GlazeDocument.sample())
                    dismiss()
                    return
                }
            }
            // Open a book on its first recipe, so that the chemistry shows without a click.
            if model.selection == nil {
                model.selection = restoredSelection() ?? document.book.recipes.first.map { .recipe($0.id) }
            }
            #if DEBUG
            // QA only (debug builds): `-FritQASelect tests|materials|none` opens the window on that page.
            switch UserDefaults.standard.string(forKey: "FritQASelect") {
            case "tests": model.selection = .tests
            case "materials": model.selection = .materials
            case "none": model.selection = nil
            default: break
            }
            #endif
        }
        .focusedSceneValue(\.bookActions, model.isModal ? nil : BookActions(
            addRecipe: { addRecipe() },
            selected: selectedRecipeID.map { id in
                SelectedRecipeActions(rename: { beginRename(id) }, duplicate: { duplicate(id) },
                                      delete: { pendingDelete = id })
            },
            showPage: { showPage($0) },
            addTest: document.book.recipes.isEmpty ? nil : { addTest() },
            findTest: { findTest() },
            printLabels: document.book.tests.isEmpty ? nil : { printLabels() }
        ))
        .sheet(isPresented: $model.showLabels) {
            LabelSheet(book: document.book, shown: model.shownTests(document.book, library: library),
                       selectedID: model.testSelection, filterActive: model.testFilterActive,
                       initialScope: model.labelScope)
        }
        .onChange(of: renaming != nil || pendingDelete != nil, initial: true) { _, shown in
            model.dialogShown = shown
        }
        // Undo, Redo or Delete can remove the selected recipe. Show the recipe now in its place, not an empty pane.
        .onChange(of: document.book.recipes.map(\.id)) { before, after in
            guard case .recipe(let id) = model.selection, !after.contains(id) else { return }
            model.selection = RecipeSelection.afterChange(selected: id, before: before, after: after).map { .recipe($0) }
        }
        .onChange(of: model.selection) { _, item in
            switch item {
            case .recipe(let id): savedSelection = id.uuidString
            case .tests: savedSelection = "tests"
            case .materials: savedSelection = "materials"
            case nil: savedSelection = ""
            }
        }
        .alert("Rename Recipe", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
                .accessibilityLabel("New recipe name")
            Button("Rename") { commitRename() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete this recipe?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete Recipe", role: .destructive) {
                if let id = pendingDelete { delete(id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Test log entries for this recipe stay in the book. You can undo this with Edit > Undo.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section("Recipes") {
                ForEach(document.book.recipes) { recipe in
                    let name = recipe.name.isEmpty ? "Untitled recipe" : recipe.name
                    let region = stullRegion(of: recipe)
                    // A dot in the color of the recipe's Stull region, so the list carries information (I6 C12).
                    // The region name is in the tooltip and in the VoiceOver label, so color is not the only cue.
                    Label { Text(name).lineLimit(1).truncationMode(.middle) } icon: { RegionDot(region: region) }
                        .help(region.map { "\(name). Stull chart: \($0.title)" } ?? name)
                        .tag(SidebarItem.recipe(recipe.id))
                        .contextMenu {
                            Button("Rename…") { beginRename(recipe.id) }
                            Button("Duplicate") { duplicate(recipe.id) }
                            Divider()
                            Button("Delete…", role: .destructive) { pendingDelete = recipe.id }
                        }
                        .accessibilityLabel("Recipe \(name), cone \(recipe.cone)" + (region.map { ", \($0.title) on the Stull chart" } ?? ""))
                }
                .onMove { from, to in document.book.recipes.move(fromOffsets: from, toOffset: to) }
                if document.book.recipes.isEmpty {
                    Text("No recipes yet")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                        .accessibilityLabel("No recipes yet. Use Add Recipe.")
                }
            }
            Section("Book") {
                Label("Tests", systemImage: "square.grid.3x3")
                    .tag(SidebarItem.tests)
                    .badge(document.book.tests.count)
                    .help(testsHelp)
                    .accessibilityLabel("Test log, \(document.book.tests.count) tiles")
                Label("Materials", systemImage: "shippingbox")
                    .tag(SidebarItem.materials)
                    .accessibilityLabel("Materials")
            }
        }
        .onDeleteCommand {
            if case .recipe(let id) = model.selection { pendingDelete = id }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let notice = document.backfillNotice, !codeNoteClosed {
                    TileCodeNote(text: TileCode.noticeText(notice)) { codeNoteClosed = true }
                }
                if document.isSample && !sampleNoteClosed {
                    SampleNote { sampleNoteClosed = true }
                }
            }
        }
        // Only Add Recipe sits over the sidebar. Rename, Duplicate and Delete are in the Recipe menu and in the
        // row's context menu. A second item here did not fit the sidebar's toolbar area and pushed an overflow
        // chevron into the toolbar at every window width (I6 C1). The toolbar is customizable (C14). Every item is
        // on the window for its whole life (see recipeToolbar), so opening a second book while a window shows
        // Tests no longer crashes (W5 V4 repro, ~/barframe-orch-work/W5/V4/evidence/Frit-2026-10-25-074509.ips).
        .toolbar(id: ToolbarIDs.book) {
            ToolbarItem(id: ToolbarIDs.addRecipe) {
                Button { addRecipe() } label: { Label("Add Recipe", systemImage: "plus") }
                    .help("Add a recipe (Option-Command-N)")
            }
        }
    }

    // MARK: Toolbar

    /// The items of the customizable toolbar: Replace Material, Oxide Nudge, Find Test, Blend, Batch Sheet and
    /// Show/Hide Chemistry.
    ///
    /// Replace Material, Oxide Nudge and Find Test are the tools that other glaze apps do not have, so they come
    /// first (run 1104 L10 change 4: before, they were only in the menus). They show an icon only, as Show/Hide
    /// Chemistry does: with their titles the toolbar would not fit a 1024-pt window and AppKit would put items
    /// behind an overflow chevron (ToolbarFamilyTests.widthBudget, measured on macOS 26.6.2).
    ///
    /// They are on the window for its whole life. The recipe items are disabled when no recipe is selected;
    /// their sheets belong to RecipeDetailView and open through the window model. Do not move them
    /// into a view that comes and goes (such as RecipeDetailView). All Frit windows share one NSToolbar
    /// identifier (ToolbarIDs.book), so AppKit keeps their toolbars in one family: an item that SwiftUI inserts
    /// into one window's toolbar after the window opens is inserted into every other window's toolbar too.
    /// When the other window already had that item, AppKit raised NSInternalInconsistencyException ("NSToolbar
    /// already contains an item with the identifier blend") and the app quit. Repro on 375ea86, macOS 26.6.2,
    /// arm64 and x86_64: open a book on a recipe, then Help > Open Sample Book; or File > New, then
    /// Recipe > Add Recipe (W5 V5).
    @ToolbarContentBuilder
    private var recipeToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: ToolbarIDs.replaceMaterial, placement: .primaryAction) {
            Button { model.replace = ReplaceRequest(materialID: nil) } label: {
                Label("Replace Material", systemImage: "arrow.triangle.swap")
            }
            .help("Replace Material: put another material in place of one and work out new amounts")
            .accessibilityLabel("Replace Material")
            .disabled(selectedRecipeID == nil)
        }
        ToolbarItem(id: ToolbarIDs.oxideNudge, placement: .primaryAction) {
            Button { model.nudge = .fromMenu } label: {
                Label("Oxide Nudge", systemImage: "scope")
            }
            .help("Oxide Nudge: move one oxide to a target value")
            .accessibilityLabel("Oxide Nudge")
            .disabled(selectedRecipeID == nil)
        }
        ToolbarItem(id: ToolbarIDs.findTest, placement: .primaryAction) {
            Button { findTest() } label: {
                Label("Find Test", systemImage: "magnifyingglass")
            }
            .help("Find Test: find a test tile by its code, recipe, material or notes (Option-Command-F)")
            .accessibilityLabel("Find Test")
        }
        ToolbarItem(id: ToolbarIDs.blend, placement: .primaryAction) {
            Menu {
                Button("Line Blend…") { model.blendMode = .line }
                Button("Triaxial Blend…") { model.blendMode = .triaxial }
                Button("Four-Corner Grid…") { model.blendMode = .grid }
            } label: {
                Label("Blend", systemImage: "triangle")
            }
            .labelStyle(.titleAndIcon)
            .help("Make a line, triaxial or four-corner blend")
            .disabled(selectedRecipeID == nil)
        }
        ToolbarItem(id: ToolbarIDs.batchSheet, placement: .primaryAction) {
            Button { model.showBatch = true } label: {
                Label("Batch Sheet", systemImage: "scalemass")
            }
            .labelStyle(.titleAndIcon)
            .help("Scale this recipe to a batch weight and print it (Shift-Command-B)")
            .disabled(selectedRecipeID == nil)
        }
        ToolbarItem(id: ToolbarIDs.chemistry, placement: .primaryAction) {
            Button { withAnimation { showChemistry.toggle() } } label: {
                Label(showChemistry ? "Hide Chemistry" : "Show Chemistry", systemImage: "sidebar.trailing")
            }
            .help(showChemistry ? "Hide the chemistry panel (Option-Command-I)" : "Show the chemistry panel (Option-Command-I)")
            .accessibilityLabel(showChemistry ? "Hide chemistry" : "Show chemistry")
            .disabled(selectedRecipeID == nil)
        }
    }

    private func stullRegion(of recipe: Recipe) -> StullRegion? {
        var filled = recipe
        filled.lines = recipe.lines.filter { !$0.materialID.isEmpty }
        guard !filled.lines.isEmpty,
              let c = try? GlazeCalculator.chemistry(of: filled, library: library, includeAdditions: false) else { return nil }
        let region = Stull.region(siO2: c.umf[.SiO2] ?? 0, al2O3: c.umf[.Al2O3] ?? 0)
        return region == .unknown ? nil : region
    }

    /// View > Recipes, Tests, Materials. Recipes keeps the selected recipe, or else selects the first one.
    private func showPage(_ page: BookPage) {
        switch page {
        case .recipes:
            if selectedRecipeID == nil { model.selection = document.book.recipes.first.map { .recipe($0.id) } }
        case .tests: model.selection = .tests
        case .materials: model.selection = .materials
        }
    }

    private func restoredSelection() -> SidebarItem? {
        switch savedSelection {
        case "tests": return .tests
        case "materials": return .materials
        default:
            guard let id = UUID(uuidString: savedSelection), document.book.recipes.contains(where: { $0.id == id }) else { return nil }
            return .recipe(id)
        }
    }

    private var selectedRecipeID: UUID? {
        if case .recipe(let id) = model.selection { return id }
        return nil
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .recipe(let id):
            if document.book.recipes.contains(where: { $0.id == id }) {
                RecipeDetailView(recipe: recipeBinding(id), book: $document.book, library: library, model: model,
                                 showChemistry: $showChemistry)
                    .id(id)
            } else {
                ContentUnavailableView("No Recipe Selected", systemImage: "flask")
            }
        case .tests:
            TestLogView(book: $document.book, model: model, library: library)
        case .materials:
            MaterialsView(book: $document.book)
        case nil:
            emptyState
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if document.book.recipes.isEmpty {
            ContentUnavailableView {
                Label("Add a Recipe", systemImage: "flask")
            } description: {
                Text("This book has no recipes yet. Add a recipe, then choose its materials and amounts. The chemistry and the Stull chart update as you type.\n\nTo look around first, open the sample book with six cone 6 base recipes. It is also in Help > Open Sample Book.")
            } actions: {
                HStack(spacing: 12) {
                    Button("Add Recipe") { addRecipe() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Button("Open Sample Book") { newDocument(GlazeDocument.sample()) }
                }
                .fixedSize()
            }
        } else {
            ContentUnavailableView("Select a Recipe", systemImage: "flask",
                                   description: Text("Choose a recipe in the sidebar to see its chemistry."))
        }
    }

    // MARK: Actions

    private func recipeBinding(_ id: UUID) -> Binding<Recipe> {
        let fallback = BookFactory.recipe(name: "")
        return Binding(
            get: { document.book.recipes.first { $0.id == id } ?? fallback },
            set: { newValue in
                // Text fields write back unchanged text when they take focus. Skip those writes,
                // so that opening a book does not mark it edited (G5 defect 1).
                if newValue.id == id, let i = Edit.indexToReplace(newValue, in: document.book.recipes) {
                    document.book.recipes[i] = newValue
                }
            }
        )
    }

    private func addRecipe() {
        let n = document.book.recipes.count + 1
        let recipe = BookFactory.recipe(name: "New recipe \(n)", lines: [BookFactory.line()])
        document.book.recipes.append(recipe)
        model.selection = .recipe(recipe.id)
    }

    private func duplicate(_ id: UUID) {
        guard let i = document.book.recipes.firstIndex(where: { $0.id == id }) else { return }
        let copy = BookFactory.duplicate(document.book.recipes[i])
        document.book.recipes.insert(copy, at: i + 1)
        model.selection = .recipe(copy.id)
    }

    private func delete(_ id: UUID) {
        // The selection moves to the recipe now in its place (onChange of the recipe ids, RecipeSelection).
        document.book.recipes.removeAll { $0.id == id }
    }

    /// The tooltip of the Tests item in the sidebar: the count and the code of the last tile added (F3).
    private var testsHelp: String {
        let tests = document.book.tests
        guard let last = tests.last else { return "Test log. No test tiles yet." }
        let count = tests.count == 1 ? "1 test tile" : "\(tests.count) test tiles"
        return "Test log: \(count). Last added: \(last.code.isEmpty ? "no code" : last.code)."
    }

    /// Tests > Add Test: a tile for the selected recipe (or the first one) with the next tile code.
    private func addTest() {
        let recipe = selectedRecipeID.flatMap { id in document.book.recipes.first { $0.id == id } }
            ?? document.book.recipes.first
        guard let recipe else { return }
        let test = BookFactory.test(recipeID: recipe.id, cone: recipe.cone)
        // Through the document's ledger, so Undo of an add never lets a later tile reuse the code (round 2).
        let tileLedger = document.tileLedger
        tileLedger.append(test, to: &document.book)
        model.testQuery = ""
        model.testCone = nil
        model.testAtmosphere = nil
        model.testSelection = test.id
        model.selection = .tests
    }

    /// Tests > Find Test: show the Tests page with the focus in its search field.
    private func findTest() {
        model.wantsTestSearchFocus = true
        model.selection = .tests
    }

    /// Tests > Print Labels: the label sheet for the tiles that the Tests page shows, or all tiles.
    private func printLabels() {
        model.labelScope = model.testFilterActive && model.selection == .tests ? .shown : .all
        model.showLabels = true
    }

    private func beginRename(_ id: UUID) {
        renameText = document.book.recipes.first { $0.id == id }?.name ?? ""
        renaming = id
    }

    private func commitRename() {
        guard let id = renaming, let i = document.book.recipes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { document.book.recipes[i].name = trimmed }
        renaming = nil
    }
}

/// Gives a new window the default size when it opens larger than the screen's visible frame. Runs once per window.
private struct FitWindowToScreen: NSViewRepresentable {
    final class Probe: NSView {
        private var done = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !done, window != nil else { return }
            done = true
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window, let screen = window.screen ?? NSScreen.main else { return }
                let visible = screen.visibleFrame
                guard window.frame.width > visible.width || window.frame.height > visible.height else { return }
                let size = WindowLayout.defaultSize(visible: LayoutSize(width: Double(visible.width), height: Double(visible.height)))
                let frame = NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - WindowLayout.margin,
                                   width: size.width, height: size.height)
                window.setFrame(frame, display: true)
            }
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}

/// Ends the text editing that AppKit starts in the first text field of a new window. Runs once per window.
private struct NoInitialTextFocus: NSViewRepresentable {
    final class Probe: NSView {
        private var done = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !done, window != nil else { return }
            done = true
            for delay in [0.0, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let window = self?.window, window.firstResponder is NSText else { return }
                    window.makeFirstResponder(nil)
                }
            }
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}

#if DEBUG
/// QA only (debug builds): with `-FritQALogLayout YES`, writes the window frame and minimum sizes to
/// <container>/tmp/frit-qa-layout.txt two seconds after the window opens. Not compiled into the release build.
struct QALayoutLogger: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard UserDefaults.standard.bool(forKey: "FritQALogLayout"), window != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let w = self?.window else { return }
                let line = "frame=\(w.frame.size) minSize=\(w.minSize) contentMinSize=\(w.contentMinSize)\n"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("frit-qa-layout.txt")
                if let h = try? FileHandle(forWritingTo: url) {
                    h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
                } else {
                    try? line.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}
#endif

/// The sidebar icon of a recipe: a dot in its Stull region color, or an empty ring when it has no point yet.
private struct RegionDot: View {
    let region: StullRegion?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if let region {
                Circle()
                    .fill(region.color)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.8 : 0.25), lineWidth: 0.5))
            } else {
                Circle().strokeBorder(Color.secondary, lineWidth: 1)
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

/// Marks the window's document changed without an Undo step, each time `token` goes up (R1 F5). AppKit's
/// `updateChangeCount(.changeDone)` is not on the undo stack, so Undo cannot make the document clean again, and
/// autosave then writes the tile counter.
private struct DocumentChangeMarker: NSViewRepresentable {
    let token: Int

    final class Probe: NSView {
        var lastToken = 0
    }

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        guard token != probe.lastToken else { return }
        probe.lastToken = token
        DispatchQueue.main.async { [weak probe] in
            guard let document = probe?.window?.windowController?.document as? NSDocument else { return }
            document.updateChangeCount(.changeDone)
        }
    }
}

/// The note at the foot of the sidebar when tiles got codes on open (R1 F1). The reader can close it.
struct TileCodeNote: View {
    let text: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Tile codes", systemImage: "number").font(.callout.weight(.semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close this note")
                    .accessibilityLabel("Close the tile code note")
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
        .accessibilityElement(children: .contain)
    }
}

/// Shown at the foot of the sidebar each time the sample book opens: on the first launch (I6 C2) and from
/// Help > Open Sample Book. It names the three tools to try and how to start a book of your own (run 1104 L10).
private struct SampleNote: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Sample book", systemImage: "info.circle").font(.callout.weight(.semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close this note")
                    .accessibilityLabel("Close the sample book note")
            }
            Text(SampleBook.guideNote(appName: AppInfo.name))
                .font(.callout)
                .foregroundStyle(.secondary)
                // No fixedSize here: when AppKit asks for the window's minimum size it offers a width of 0,
                // and a fixed-height text then wraps one letter per line (the window was 1862 pt tall, G12).
                // About 12 lines at the sidebar's 220-pt ideal width (estimate: 31 characters a line).
                .lineLimit(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
        .accessibilityElement(children: .contain)
    }
}
