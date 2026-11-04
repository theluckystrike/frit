import Foundation
import Testing
@testable import GlazeCore

/// F3 checks that use only the file format and the app sources. They compile on main (cb41103) too, where they
/// fail: main drops the tile codes on save, the sample tiles have none, and there is no Tests menu or Help topic.
@Suite("Tile codes: file and menus (F3)")
struct TileCodeFileTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    static func appSource(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/GlazeApp/\(name)"), encoding: .utf8)
    }

    /// A book as Frit 1.3 writes it: tiles with codes and the tile counter.
    static let bookWithCodes = """
    {
      "customMaterials" : [],
      "nextTileNumber" : 9,
      "recipes" : [
        {
          "cone" : "6",
          "id" : "6E1C2A57-0A8B-4F44-9C59-1B3A2A0F0001",
          "lines" : [
            {
              "amount" : 40,
              "id" : "6E1C2A57-0A8B-4F44-9C59-1B3A2A0F0002",
              "isAddition" : false,
              "materialID" : "silica"
            }
          ],
          "name" : "Shino test",
          "notes" : ""
        }
      ],
      "tests" : [
        {
          "atmosphere" : "Reduction",
          "code" : "T-007",
          "cone" : "10",
          "date" : "2026-10-01T12:00:00Z",
          "id" : "6E1C2A57-0A8B-4F44-9C59-1B3A2A0F0003",
          "notes" : "Carbon trap on the rim",
          "recipeID" : "6E1C2A57-0A8B-4F44-9C59-1B3A2A0F0001",
          "schedule" : []
        },
        {
          "atmosphere" : "Oxidation",
          "code" : "Cu-3a",
          "cone" : "6",
          "date" : "2026-10-02T12:00:00Z",
          "id" : "6E1C2A57-0A8B-4F44-9C59-1B3A2A0F0004",
          "notes" : "",
          "recipeID" : "6E1C2A57-0A8B-4F44-9C59-1B3A2A0F0001",
          "schedule" : []
        }
      ],
      "version" : 1
    }
    """

    @Test("tile codes and the tile counter survive decode and encode")
    func codesSurviveSave() throws {
        let data = Data(Self.bookWithCodes.utf8)
        let again = try GlazeBookCodec.encode(GlazeBookCodec.decode(data))
        let text = String(decoding: again, as: UTF8.self)
        #expect(text.contains("\"code\" : \"T-007\""))
        #expect(text.contains("\"code\" : \"Cu-3a\""))
        #expect(text.contains("\"nextTileNumber\" : 9"))
        // A second round trip gives the same bytes (nothing changes on open and save).
        #expect(try GlazeBookCodec.encode(GlazeBookCodec.decode(again)) == again)
    }

    @Test("the sample tiles have the codes T-001, T-002 and T-003")
    func sampleTilesHaveCodes() throws {
        let text = String(decoding: try GlazeBookCodec.encode(SampleBook.make()), as: UTF8.self)
        for code in ["T-001", "T-002", "T-003"] { #expect(text.contains("\"code\" : \"\(code)\""), "\(code)") }
        #expect(text.contains("\"nextTileNumber\" : 4"))
        #expect(SampleBook.make().tests.first?.notes.contains("T-001 is written on the back") == true)
    }

    @Test("the Tests menu has Add Test, Find Test and Print Labels, and the app installs it")
    func testsMenu() throws {
        let commands = try Self.appSource("RecipeCommands.swift")
        #expect(commands.contains("CommandMenu(\"Tests\")"))
        for item in ["Button(\"Add Test\")", "Button(\"Find Test…\")", "Button(\"Print Labels…\")"] {
            #expect(commands.contains(item), "\(item)")
        }
        #expect(try Self.appSource("GlazeMainApp.swift").contains("TestsCommands()"))
    }

    @Test("Help has a topic on tile codes, labels and search that names the menu items")
    func helpTopic() throws {
        let help = try Self.appSource("HelpWindow.swift")
        #expect(help.contains("id: \"tilecodes\""))
        for phrase in ["Tests > Find Test…", "Tests > Print Labels…", "its code is not given to a new tile",
                       "Books from earlier versions get codes"] {
            #expect(help.contains(phrase), "\(phrase)")
        }
    }

    @Test("the Tests page has a code column, a search field and the code editor; blends use the counter")
    func testsPageSources() throws {
        let page = try Self.appSource("TestLogView.swift")
        #expect(page.contains("TableColumn(\"Code\")"))
        #expect(page.contains("TextField(\"Search tests\""))
        #expect(page.contains("TileCode.liveEdit(tileID:"))
        #expect(page.contains("tileLedger.append(test, to: &book)"))
        let blend = try Self.appSource("BlendSheet.swift")
        #expect(blend.contains("tileLedger.append(test, to: &updated)"))
        #expect(!blend.contains("book.tests.append(test)"))
    }
}
