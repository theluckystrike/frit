import Foundation

/// Rules for custom materials: new ids and deletion (W6 F1).
public enum MaterialRules {
    /// The prefix of every custom material id.
    public static let customPrefix = "custom-"

    /// A new custom material id that no material, no recipe line and no earlier id uses.
    ///
    /// W6 C1: the old ids were "custom-1", "custom-2"… and the lowest free number was used again. A deleted
    /// material that recipes still named gave its number to the next new material, and those recipes silently
    /// took the new chemistry. The id now holds a UUID, so it is never used again. `taken` must hold every
    /// material id and every id that a recipe line names (`idsInUse`). `makeUUID` is for tests.
    public static func newCustomID(taken: Set<String>, makeUUID: () -> UUID = { UUID() }) -> String {
        for _ in 0..<16 {
            let id = customPrefix + makeUUID().uuidString.lowercased()
            if !taken.contains(id) { return id }
        }
        // 16 clashes in a row cannot happen with real UUIDs. Add a counter so that the result is still unique.
        var n = 1
        while taken.contains("\(customPrefix)x\(n)") { n += 1 }
        return "\(customPrefix)x\(n)"
    }

    /// Every material id of the book's custom materials and of its recipe lines (also ids with no material).
    public static func idsInUse(_ book: GlazeBook) -> Set<String> {
        var ids = Set(book.customMaterials.map(\.id))
        for recipe in book.recipes {
            for line in recipe.lines where !line.materialID.isEmpty { ids.insert(line.materialID) }
        }
        return ids
    }

    /// The default name of a new custom material: "New material N" with the lowest N that no material has.
    public static func newCustomName(existingNames: Set<String>) -> String {
        var n = 1
        while existingNames.contains("New material \(n)") { n += 1 }
        return "New material \(n)"
    }

    /// The names of the recipes that use `materialID` in a line, in book order, each name once.
    /// A material that a recipe uses must not be deleted: the recipe would keep a dangling id.
    public static func recipesUsing(_ materialID: String, in book: GlazeBook) -> [String] {
        var names: [String] = []
        for recipe in book.recipes where recipe.lines.contains(where: { $0.materialID == materialID }) {
            let name = recipe.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled recipe" : recipe.name
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// The text that tells why a material cannot be deleted, or nil when no recipe uses it.
    public static func deleteBlockedMessage(materialName: String, recipeNames: [String]) -> String? {
        guard !recipeNames.isEmpty else { return nil }
        let shown = recipeNames.prefix(10).map { "“\($0)”" }.joined(separator: ", ")
        let more = recipeNames.count > 10 ? " and \(recipeNames.count - 10) more" : ""
        let count = recipeNames.count == 1 ? "1 recipe uses" : "\(recipeNames.count) recipes use"
        return "\(count) “\(materialName)” (\(shown)\(more)). Choose a different material in "
            + (recipeNames.count == 1 ? "that recipe" : "these recipes") + ", then delete this material."
    }
}
