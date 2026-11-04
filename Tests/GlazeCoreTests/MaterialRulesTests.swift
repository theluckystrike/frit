import Foundation
import Testing
@testable import GlazeCore

/// Fixes for the W6 C1 review of custom materials. Each test covers one finding.
@Suite("Custom material rules W6 F1")
struct MaterialRulesTests {
    private func book(customIDs: [String], recipeIDs: [[String]]) -> GlazeBook {
        let materials = customIDs.map { Material(id: $0, name: "M \($0)", analysis: [.SiO2: 100], loi: 0, source: "") }
        let recipes = recipeIDs.enumerated().map { i, ids in recipe("R\(i + 1)", ids.map { ($0, 10.0) }) }
        return GlazeBook(recipes: recipes, customMaterials: materials, tests: [], version: 1)
    }

    // Before: the lowest free "custom-N" was used again, so a new material took over the recipes that still
    // named a deleted one. Now an id that a recipe line names is never given to a new material.
    @Test func newIDIsNotAnIDThatARecipeStillNames() {
        let b = book(customIDs: [], recipeIDs: [["custom-1", "silica"]])
        let taken = MaterialRules.idsInUse(b)
        #expect(taken.contains("custom-1"))
        let id = MaterialRules.newCustomID(taken: taken)
        #expect(id != "custom-1")
        #expect(id.hasPrefix("custom-"))
        #expect(!taken.contains(id))
    }

    @Test func newIDsAreUnique() {
        var taken: Set<String> = []
        for _ in 0..<200 { taken.insert(MaterialRules.newCustomID(taken: taken)) }
        #expect(taken.count == 200)
    }

    @Test func newIDSkipsAClashingUUID() {
        let fixed = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let clash = "custom-" + fixed.uuidString.lowercased()
        let id = MaterialRules.newCustomID(taken: [clash], makeUUID: { fixed })
        #expect(id != clash)
        #expect(id.hasPrefix("custom-"))
    }

    @Test func newNameUsesTheLowestFreeNumber() {
        #expect(MaterialRules.newCustomName(existingNames: []) == "New material 1")
        #expect(MaterialRules.newCustomName(existingNames: ["New material 1", "New material 3"]) == "New material 2")
    }

    // Before: Delete Material removed a material that recipes used. Now the recipes are named and the delete stops.
    @Test func deleteIsBlockedForAMaterialThatRecipesUse() {
        let b = book(customIDs: ["custom-1", "custom-2"], recipeIDs: [["custom-1"], ["silica"], ["custom-1", "custom-1"]])
        let users = MaterialRules.recipesUsing("custom-1", in: b)
        #expect(users == ["R1", "R3"])
        let message = MaterialRules.deleteBlockedMessage(materialName: "Local ash", recipeNames: users)
        #expect(message?.contains("“R1”") == true)
        #expect(message?.contains("“R3”") == true)
        #expect(message?.contains("2 recipes use “Local ash”") == true)
    }

    @Test func deleteIsAllowedForAnUnusedMaterial() {
        let b = book(customIDs: ["custom-1", "custom-2"], recipeIDs: [["custom-1"]])
        #expect(MaterialRules.recipesUsing("custom-2", in: b).isEmpty)
        #expect(MaterialRules.deleteBlockedMessage(materialName: "X", recipeNames: []) == nil)
    }

    // Old documents keep their ids ("custom-1" and so on). Nothing renames them.
    @Test func oldCustomIDsStillResolve() {
        let b = book(customIDs: ["custom-1"], recipeIDs: [["custom-1"]])
        let layered = LayeredLibrary(custom: b.customMaterials, base: lib)
        #expect(layered.material(id: "custom-1") != nil)
    }
}

/// W6 C1: Return and Choose in the material picker took a highlighted material that the search had hidden.
@Suite("Material picker W6 F1")
struct MaterialSearchTests {
    private let list = [
        Material(id: "silica", name: "Silica", analysis: [.SiO2: 100], loi: 0, source: ""),
        Material(id: "whiting", name: "Whiting", analysis: [.CaO: 56], loi: 44, source: ""),
        Material(id: "custom-1", name: "Local ash", analysis: [.CaO: 40], loi: 0, source: ""),
    ]

    @Test func filterMatchesNameOrID() {
        #expect(MaterialSearch.filter(list, query: "  ").map(\.id) == ["silica", "whiting", "custom-1"])
        #expect(MaterialSearch.filter(list, query: "WHIT").map(\.id) == ["whiting"])
        #expect(MaterialSearch.filter(list, query: "custom").map(\.id) == ["custom-1"])
    }

    @Test func hiddenHighlightIsCleared() {
        let shown = MaterialSearch.filter(list, query: "sil").map(\.id)
        #expect(MaterialSearch.keptHighlight("whiting", resultIDs: shown) == nil)
        #expect(MaterialSearch.keptHighlight("silica", resultIDs: shown) == "silica")
        #expect(MaterialSearch.keptHighlight(nil, resultIDs: shown) == nil)
    }

    @Test("run 1104 L2 BUG-5: the count says 1 material, not 1 materials")
    func countText() {
        #expect(MaterialSearch.countText(1) == "1 material")
        #expect(MaterialSearch.countText(0) == "0 materials")
        #expect(MaterialSearch.countText(47) == "47 materials")
        let picker = try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GlazeApp/MaterialPicker.swift"), encoding: .utf8)
        #expect(picker?.contains("MaterialSearch.countText(results.count)") == true)
    }

    @Test func pickTakesOnlyAShownMaterial() {
        let shown = MaterialSearch.filter(list, query: "ash").map(\.id)
        // Choose and Return in the list: the hidden highlight is not taken, and there is no fallback.
        #expect(MaterialSearch.pick(highlighted: "whiting", resultIDs: shown, fallbackToFirst: false) == nil)
        // Return in the search field: the first shown material.
        #expect(MaterialSearch.pick(highlighted: "whiting", resultIDs: shown, fallbackToFirst: true) == "custom-1")
        #expect(MaterialSearch.pick(highlighted: "custom-1", resultIDs: shown, fallbackToFirst: false) == "custom-1")
        #expect(MaterialSearch.pick(highlighted: nil, resultIDs: [], fallbackToFirst: true) == nil)
    }
}
