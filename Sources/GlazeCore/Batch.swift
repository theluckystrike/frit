import Foundation

public enum Batch {
    /// Scales the recipe so that its base (non-addition) lines sum to `totalGrams`. Additions are scaled with
    /// the same factor (an addition of 4 per 100 base becomes 4 % of `totalGrams`). Each amount is rounded to the
    /// nearest multiple of `precision` (no rounding when precision <= 0), so the rounded base sum can differ
    /// from `totalGrams` by up to half a precision step per line.
    /// Lines with zero, negative or non-finite amounts are left out. Lines keep the recipe order.
    /// Returns nothing when `problem(_:totalGrams:precision:)` gives a reason (no base, a bad weight, or a weight
    /// that is not a finite number, W6 F2).
    /// `isAddition` comes from each line, so a material that is in the base and also an addition keeps one
    /// row of each kind (W5 V4: the batch sheet had marked both rows "(addition)").
    public static func scale(_ r: Recipe, totalGrams: Double, precision: Double)
        -> [(materialID: String, grams: Double, isAddition: Bool)] {
        guard let rows = try? scaled(r, totalGrams: totalGrams, precision: precision) else { return [] }
        return rows
    }

    /// Why the recipe cannot be scaled to `totalGrams`, as a sentence for the batch sheet, or nil when it can.
    public static func problem(_ r: Recipe, totalGrams: Double, precision: Double) -> String? {
        do {
            _ = try scaled(r, totalGrams: totalGrams, precision: precision)
            return nil
        } catch let e as BatchProblem {
            return e.message
        } catch {
            return error.localizedDescription
        }
    }

    struct BatchProblem: Error { let message: String }

    /// Ratio first (amount / base, then x total): a tiny base no longer makes the factor infinite (W6 F2).
    /// Every weight and their sum must be finite.
    private static func scaled(_ r: Recipe, totalGrams: Double, precision: Double) throws
        -> [(materialID: String, grams: Double, isAddition: Bool)] {
        let base = r.baseTotal
        guard base.isFinite else { throw BatchProblem(message: "The base total is too large to scale.") }
        guard base > 0 else { throw BatchProblem(message: "Add base materials to the recipe first.") }
        guard totalGrams.isFinite, totalGrams > 0 else { throw BatchProblem(message: "Enter a batch weight above 0 g.") }
        let rows = r.lines
            .filter { $0.amount > 0 && $0.amount.isFinite }
            .map { (materialID: $0.materialID, grams: round(totalGrams * ($0.amount / base), to: precision),
                    isAddition: $0.isAddition) }
        guard rows.allSatisfy({ $0.grams.isFinite }), rows.reduce(0, { $0 + $1.grams }).isFinite else {
            throw BatchProblem(message: "The additions are too large for this base, so a weight would not be a finite number.")
        }
        return rows
    }

    /// Rounds to the nearest multiple of `step`, then removes binary noise (33.300000000000004 -> 33.3).
    static func round(_ x: Double, to step: Double) -> Double {
        guard step > 0, step.isFinite else { return x }
        let v = (x / step).rounded() * step
        var decimals = 0
        var q = step
        while decimals < 10 && abs(q - q.rounded()) > 1e-9 {
            q *= 10
            decimals += 1
        }
        let f = pow(10, Double(decimals))
        return (v * f).rounded() / f
    }
}
