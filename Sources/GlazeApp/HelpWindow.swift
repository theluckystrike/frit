import SwiftUI
import GlazeCore

/// Help > Frit Help (Command-?). Short help that ships with the app, so it works offline (I6 C7).
/// It also documents the first-launch sample book (I6 C2).
struct HelpWindow: View {
    static let id = "help"

    private struct Topic: Identifiable {
        let id: String
        let title: String
        let text: String
    }

    private var topics: [Topic] {
        let app = AppInfo.name
        return [
            Topic(id: "start", title: "Getting started",
                  text: "The first time \(app) starts, it opens a sample book with six cone 6 base recipes and three test tiles (codes T-001 to T-003), so you can look around before you type anything. Each time the sample opens, a note at the foot of its sidebar names three tools to try: Recipe > Replace Material, Recipe > Oxide Nudge and Tests > Find Test. After the first launch, \(app) opens a new untitled book when it starts. Choose File > New for another book, or Help > Open Sample Book to see the sample again. A book is one file that you save where you like."),
            Topic(id: "recipes", title: "Recipes and chemistry",
                  text: "Add a recipe with the + button or Recipe > Add Recipe. Choose a material in each row and type its amount. Mark colorants and opacifiers as additions. The chemistry pane shows the unity molecular formula, the mole and weight percent, the silica to alumina ratio, the expansion estimate and a check against the reference range set you choose. The ranges are for comparison. They are not a safety rating."),
            Topic(id: "nudge", title: "Oxide Nudge",
                  text: "Choose Recipe > Oxide Nudge… or the Oxide Nudge button in the toolbar, or click the small up and down arrows next to a UMF value in the chemistry pane. Pick an oxide, then type its target UMF or step it by 0.05. \(app) changes the amounts of the materials already in the recipe so that the oxide reaches the target, when some recipe of those materials can reach it. The other oxides stay as close to their current values as those materials allow. When there is more than one way to do that, \(app) picks the one with the smallest change to the current amounts. No amount goes below 0. For a flux oxide, the other fluxes keep their ratios to each other and share the rest of the unity. The sheet shows the old and new amounts, each oxide before and after, and both points on the Stull chart. If an oxide cannot reach its target, the sheet says by how much it misses. If no base material in the recipe contains the oxide, the sheet offers materials that do. The arrows do not show while \"Include additions in chemistry\" is on, because Oxide Nudge works on the base without additions. A recipe with only one flux oxide has no arrows on that oxide, because its unity value is always 1. Apply changes the recipe, and Edit > Undo takes it back. Apply as Copy adds a new recipe and leaves this one as it is. The new base is scaled to 100. Additions are not changed and are not counted."),
            Topic(id: "replace", title: "Replace Material",
                  text: "Choose Recipe > Replace Material… or the Replace Material button in the toolbar, or Control-click a material row for the same command. Pick the base material to replace and the material to use in its place, for example a different feldspar. \(app) works out the amount of the new material and new amounts for the other base materials, so that the unity formula stays as close to the original as those materials allow. Among the matches, \(app) picks the one with the smallest change to the other amounts, so the base total can change. Normalize Base to 100 scales it back. If an oxide cannot be matched, the sheet says by how much. When no material left in the recipe supplies a flux oxide (for example K₂O when Soda feldspar replaces Potash feldspar), the new material takes about the same share of the flux as the old one, the other amounts stay near their current values, and the sheet names the missing oxide. Save as New Recipe keeps the original recipe and its test log entries as they are. To use your supplier's analysis, add it as a custom material first. A matching unity formula does not promise the same glaze, so test the new recipe on tiles."),
            Topic(id: "stull", title: "The Stull chart",
                  text: "The chart plots the glaze's silica against its alumina, both in UMF, over the regions of Stull's 1912 chart. Each region has its name in the plot. Stull fired at cone 11 without boron, so use the chart as a rough guide, and more so for glazes with boron. The dashed line shows where the glaze was in your last five edits."),
            Topic(id: "blends", title: "Blends",
                  text: "Recipe > Line Blend, Triaxial Blend and Four-Corner Grid make a set of tiles between two, three or four recipes. Each tile has its own recipe and chemistry. You can add the tiles to the book as recipes and as entries in the test log. Test log entries get tile codes in blend order, so tile 1 of the blend has the first new code."),
            Topic(id: "batch", title: "Batch sheets and printing",
                  text: "Recipe > Batch Sheet scales a recipe to the batch weight you type and rounds each weight to your scale's precision. Print it or save it as a PDF from the sheet. File > Print Batch Sheet prints it with the weight and precision you used last."),
            Topic(id: "tests", title: "The test log",
                  text: "Choose Tests in the sidebar, or View > Tests (Command-2), to log each tile with its recipe, cone, atmosphere, firing schedule, notes and a photo. Tests > Add Test adds a tile. The ramp chart draws the schedule. The book keeps a link to the photo file, not a copy of it."),
            Topic(id: "tilecodes", title: "Tile codes, labels and search",
                  text: "Each test tile gets a short code: T-001, T-002 and so on. Write it on the back of the tile before you fire it. The code shows in the first column of the test log. To change a code, select the tile and type in the Code field. The new code is used as you type. If it cannot be used, the field says why and the tile keeps its old code. A code can have up to \(TileCode.maxLength) letters, digits, spaces and - _ . / # +. Two tiles cannot have the same code. Upper and lower case count as the same. When you delete a tile, or undo Add Test, its code is not given to a new tile, so the code on a fired tile always points to one entry. Books from earlier versions get codes in the order of their tiles when they open, a note in the sidebar says so, and the codes are saved with the next save. A book with tile codes is saved in a newer file format, so Frit 1.2 and earlier do not open it and cannot remove its codes. To find a tile, choose Tests > Find Test… (Option-Command-F) or the Find Test button in the toolbar, and type its code, its recipe, a material in the recipe, a word from its notes or its date (for example 2026-09, or the date as the list shows it). Type the full code from the back of a tile and \(app) selects that tile. \"cone 6\" finds tiles fired to cone 6 only. The cone and atmosphere menus under the search field narrow the list. Tests > Print Labels… prints a label for each tile with its code, recipe, cone, atmosphere and date, for a Letter sheet of 30 labels (2⅝ × 1 in) or an A4 sheet of 21 labels (63.5 × 38.1 mm). You can print all tiles, the tiles that the search shows, or the selected tile, and start at any label of a sheet that is partly used. Print at 100%, and try one page on plain paper first. Export PDF… saves the labels as a PDF file."),
            Topic(id: "materials", title: "Materials",
                  text: "Choose Materials in the sidebar, or View > Materials (Command-3). The bundled materials are read-only and each one names its source. Duplicate one as a custom material to change it, or add your own with its oxide analysis, loss on ignition and source. Custom materials are saved in the book."),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(AppInfo.name) Help").font(.title.weight(.semibold))
                // The link is the only control in the window, so it takes the first key focus. At the foot of
                // the text it scrolled the window to the bottom when Help opened (W6 X4). At the top it doesn't.
                HStack {
                    Text("More answers are on the support page.").foregroundStyle(.secondary)
                    Link("Open the Support Page", destination: HelpLinks.support)
                }
                .font(.callout)
                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(topic.title).font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(topic.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}
