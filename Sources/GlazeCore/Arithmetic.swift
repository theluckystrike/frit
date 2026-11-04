import Foundation

/// A calculation whose result would not be a finite number. W6 F2: finite inputs could still overflow
/// (a tiny base made 100 / base infinite; 1e308 amounts overflowed the oxide sums), and the document then
/// held NaN or infinity, which JSON cannot save.
public enum CalculationError: Error, Equatable, Sendable, LocalizedError {
    case resultOutOfRange

    public var errorDescription: String? {
        "A result is too large or too small to calculate. Check for very large amounts or a very small base."
    }
}

/// Throws `CalculationError.resultOutOfRange` unless every value is finite.
func requireFinite<S: Sequence>(_ values: S, _ more: Double...) throws where S.Element == Double {
    guard values.allSatisfy(\.isFinite), more.allSatisfy(\.isFinite) else { throw CalculationError.resultOutOfRange }
}

public enum Normalize {
    /// The recipe with its base (non-addition) lines scaled to sum to `target`; additions get the same factor.
    /// Full precision: nothing is rounded here (W6 F2: rounding to 2 decimals made 3 equal parts sum to 99.99
    /// and turned trace additions into 0). The views round only for display and weighing.
    /// Lines with zero, negative or non-finite amounts are not changed.
    /// Nil, and nothing changes, when there is no positive finite base, or when a new amount would not be finite
    /// or would be larger than `NumberText.maxMagnitude` (the largest amount a field takes).
    public static func base(of r: Recipe, to target: Double = 100) -> Recipe? {
        let base = r.baseTotal
        guard base.isFinite, base > 0, target.isFinite, target > 0 else { return nil }
        var out = r
        for i in out.lines.indices where out.lines[i].amount > 0 && out.lines[i].amount.isFinite {
            // Ratio first: amount / base is at most 1 for a base line, so a tiny base cannot overflow it.
            let v = out.lines[i].amount / base * target
            guard v.isFinite, v <= NumberText.maxMagnitude else { return nil }
            out.lines[i].amount = v
        }
        return out
    }

    /// Why `base(of:to:)` gives nil, as a sentence for the button's help, or nil when it can normalize.
    public static func problem(_ r: Recipe, to target: Double = 100) -> String? {
        let base = r.baseTotal
        if !base.isFinite { return "The base total is too large to normalize." }
        if base <= 0 { return "Add base materials to the recipe first." }
        if Normalize.base(of: r, to: target) == nil {
            return "The additions are too large for this base. An amount would be above "
                + "\(fmtWarning(NumberText.maxMagnitude))."
        }
        return nil
    }
}
