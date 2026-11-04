import Foundation
@testable import GlazeCore

/// Shared bundled library for all tests (loaded once).
let lib: BundledLibrary = {
    do { return try BundledLibrary() } catch { fatalError("BundledLibrary failed to load: \(error)") }
}()

func recipe(_ base: [(String, Double)], additions: [(String, Double)] = []) -> Recipe {
    recipe("Test", base, additions: additions)
}

func recipe(_ name: String, _ base: [(String, Double)], additions: [(String, Double)] = [], cone: String = "6") -> Recipe {
    var lines = base.map { RecipeLine(materialID: $0.0, amount: $0.1, isAddition: false) }
    lines += additions.map { RecipeLine(materialID: $0.0, amount: $0.1, isAddition: true) }
    return Recipe(name: name, cone: cone, lines: lines, notes: "")
}

func chem(_ r: Recipe, additions: Bool = false) throws -> Chemistry {
    try GlazeCalculator.chemistry(of: r, library: lib, includeAdditions: additions)
}

func near(_ a: Double?, _ b: Double, _ tol: Double = 0.005) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tol
}

/// Sum of the base amounts of a recipe, per material id (additions kept apart).
func amounts(_ r: Recipe, additions: Bool = false) -> [String: Double] {
    var out: [String: Double] = [:]
    for l in r.lines where l.isAddition == additions { out[l.materialID, default: 0] += l.amount }
    return out
}
