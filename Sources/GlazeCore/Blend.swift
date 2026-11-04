import Foundation

/// Blend generators. Before mixing, each source recipe is scaled so that its base (non-addition) total is 100;
/// additions are scaled with the same factor. A tile is the weighted sum of the scaled sources, so a tile also
/// has a base total of 100. Each tile gets a new id; lines are merged per material and addition flag.
/// The generators give nothing when an endpoint has a problem (`endpointProblem`, W6 F2).
public enum Blend {
    /// `steps` tiles from a to b, both ends included (steps 1 gives only a; steps < 1 gives nothing).
    public static func line(_ a: Recipe, _ b: Recipe, steps: Int) -> [Recipe] {
        guard steps >= 1, problem(endpoints: [a, b]) == nil else { return [] }
        if steps == 1 { return [mix([(a, 1)], name: "\(a.name) 100%", base: a)] }
        return (0..<steps).map { i in
            let t = Double(i) / Double(steps - 1)
            return mix([(a, 1 - t), (b, t)], name: "Line \(i + 1)/\(steps): " + label([(a, 1 - t), (b, t)]), base: a)
        }
    }

    /// Triaxial blend. `divisions` d gives (d + 1)(d + 2) / 2 tiles (4 -> 15, 5 -> 21).
    /// Order: row 0 is corner a; row k has k + 1 tiles moving from b toward c.
    public static func triaxial(_ a: Recipe, _ b: Recipe, _ c: Recipe, divisions: Int) -> [Recipe] {
        guard divisions >= 0, problem(endpoints: [a, b, c]) == nil else { return [] }
        if divisions == 0 { return [mix([(a, 1)], name: "\(a.name) 100%", base: a)] }
        let d = Double(divisions)
        var out: [Recipe] = []
        var n = 0
        for row in 0...divisions {
            for col in 0...row {
                n += 1
                let parts = [(a, Double(divisions - row) / d), (b, Double(row - col) / d), (c, Double(col) / d)]
                out.append(mix(parts, name: "Tri \(n): " + label(parts), base: a))
            }
        }
        return out
    }

    /// Currie-style grid with bilinear weights. `corners` = [top left, top right, bottom left, bottom right].
    /// Output is row by row (rows x columns tiles). Gives nothing unless there are exactly 4 corners.
    public static func grid(corners: [Recipe], rows: Int, columns: Int) -> [Recipe] {
        guard corners.count == 4, rows >= 1, columns >= 1, problem(endpoints: corners) == nil else { return [] }
        var out: [Recipe] = []
        for r in 0..<rows {
            let v = rows == 1 ? 0 : Double(r) / Double(rows - 1)
            for c in 0..<columns {
                let u = columns == 1 ? 0 : Double(c) / Double(columns - 1)
                let parts = [(corners[0], (1 - u) * (1 - v)), (corners[1], u * (1 - v)),
                             (corners[2], (1 - u) * v), (corners[3], u * v)]
                out.append(mix(parts, name: "Grid r\(r + 1) c\(c + 1): " + label(parts),
                               base: corners[0]))
            }
        }
        return out
    }

    // MARK: - Endpoints

    /// Why this recipe cannot be a blend endpoint, as a sentence for the blend sheet, or nil when it can.
    /// W6 F2: an empty or additions-only endpoint was taken and gave underweight bases or empty tiles.
    /// An endpoint needs a finite base total above 0, and every line scaled to a base of 100 must stay finite
    /// and not above `NumberText.maxMagnitude` (the largest amount a field takes).
    public static func endpointProblem(_ r: Recipe) -> String? {
        let name = r.name.isEmpty ? "Untitled recipe" : r.name
        let total = r.baseTotal
        if !total.isFinite { return "\u{201C}\(name)\u{201D} has a base total too large to blend." }
        if total <= 0 {
            return "\u{201C}\(name)\u{201D} has no base materials. Each recipe in a blend needs a base total above 0."
        }
        let tooLarge = r.lines.contains { line in
            guard line.amount.isFinite else { return true }
            let v = abs(line.amount) / total * 100
            return !v.isFinite || v > NumberText.maxMagnitude
        }
        if tooLarge { return "\u{201C}\(name)\u{201D} has additions too large for its base to blend." }
        return nil
    }

    /// The first endpoint problem, or nil when every endpoint can be blended.
    public static func problem(endpoints: [Recipe]) -> String? {
        endpoints.lazy.compactMap(endpointProblem).first
    }

    // MARK: - Mixing

    private struct Key: Hashable { let materialID: String; let isAddition: Bool }

    static func mix(_ parts: [(Recipe, Double)], name: String, base: Recipe) -> Recipe {
        var order: [Key] = []
        var sums: [Key: Double] = [:]
        for (recipe, weight) in parts where weight > 0 {
            // The generators check the endpoints first, so total is finite and above 0 here. When 100 / total
            // overflows (a tiny base), scale ratio first (amount / total, then x 100) instead (W6 F2).
            let total = recipe.baseTotal
            let factor = 100 / total
            for line in recipe.lines {
                let key = Key(materialID: line.materialID, isAddition: line.isAddition)
                if sums[key] == nil { order.append(key) }
                let scaled = factor.isFinite ? line.amount * factor : line.amount / total * 100
                sums[key, default: 0] += scaled * weight
            }
        }
        let lines = order.compactMap { key -> RecipeLine? in
            let amount = sums[key]!
            return amount == 0 ? nil : RecipeLine(materialID: key.materialID, amount: amount, isAddition: key.isAddition)
        }
        return Recipe(name: name, cone: base.cone, lines: lines, notes: "")
    }

    private static func label(_ parts: [(Recipe, Double)]) -> String {
        parts.filter { $0.1 > 0 }
            .map { "\(Int(($0.1 * 100).rounded()))% \($0.0.name)" }
            .joined(separator: ", ")
    }
}
