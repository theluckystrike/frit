import Foundation
import GlazeCore

/// All construction of GlazeCore values in the app goes through here.
enum BookFactory {
    static func emptyBook() -> GlazeBook {
        GlazeBook(recipes: [], customMaterials: [], tests: [], version: 1)
    }

    static func line(_ materialID: String = "", amount: Double = 0, isAddition: Bool = false) -> RecipeLine {
        RecipeLine(id: UUID(), materialID: materialID, amount: amount, isAddition: isAddition)
    }

    static func recipe(name: String, cone: String = "6", lines: [RecipeLine] = [], notes: String = "") -> Recipe {
        Recipe(id: UUID(), name: name, cone: cone, lines: lines, notes: notes)
    }

    /// A copy with new ids for the recipe and every line.
    static func duplicate(_ recipe: Recipe, name: String? = nil) -> Recipe {
        var copy = recipe
        copy.id = UUID()
        copy.name = name ?? "\(recipe.name) copy"
        copy.lines = recipe.lines.map { line in
            var l = line
            l.id = UUID()
            return l
        }
        return copy
    }

    /// A new, empty custom material. `book` gives the ids and names in use: the new id is never one that a
    /// material or a recipe line has used (`MaterialRules.newCustomID`, W6 F1).
    static func customMaterial(in book: GlazeBook) -> Material {
        let taken = MaterialRules.idsInUse(book).union(AppLibrary.bundledMaterials.map(\.id))
        let name = MaterialRules.newCustomName(existingNames: Set(book.customMaterials.map(\.name)))
        return Material(id: MaterialRules.newCustomID(taken: taken), name: name, analysis: [:], loi: 0, source: "")
    }

    static func test(recipeID: UUID, cone: String) -> TestTile {
        TestTile(
            id: UUID(), recipeID: recipeID, cone: cone, atmosphere: Atmosphere.oxidation.rawValue,
            schedule: defaultSchedule(), notes: "", photoBookmark: nil, date: Date()
        )
    }

    static func segment(rate: Double, target: Double, hold: Double) -> FiringSegment {
        FiringSegment(ratePerHour: rate, targetC: target, holdMinutes: hold)
    }

    /// A plain medium-speed cone 6 glaze firing, in degrees Celsius.
    static func defaultSchedule() -> [FiringSegment] {
        [
            segment(rate: 150, target: 600, hold: 0),
            segment(rate: 220, target: 1100, hold: 0),
            segment(rate: 60, target: 1220, hold: 10),
        ]
    }
}

enum Atmosphere: String, CaseIterable, Identifiable {
    case oxidation = "Oxidation"
    case reduction = "Reduction"
    case neutral = "Neutral"
    case soda = "Soda"
    case salt = "Salt"
    case wood = "Wood"
    var id: String { rawValue }
}
