import Foundation

/// Appen's additive estimate of the linear thermal expansion of a silicate glass (W6 F3).
///
/// Source: A. A. Appen, *Khimiya stekla* (Chemistry of Glass), 2nd ed., Leningrad: Khimiya, 1974, as reproduced by
/// A. Fluegel, "Old thermal expansion models", glassproperties.com,
/// https://www.glassproperties.com/expansion/Old-Thermal-Expansion-Models.htm (read 26 Oct 2026), Appen column and its
/// footnotes a, c, d, e, f. The page gives the partial coefficients in 1e-6 per K per (mole fraction x 100); GlazeCore
/// works in 1e-7 per K, so every number below is the page's number times 10. Brackets are mole percent of the glass.
///
/// - SiO2 (footnote a): 38 when [SiO2] < 67, otherwise 105 - [SiO2].
/// - K2O (footnote d): 465 when the glass has more than 1 mol % Na2O, otherwise 420.
/// - B2O3 (footnote c): F = ([Na2O] + [K2O] + [BaO] + 0.7 ([CaO] + [SrO] + [PbO]) + 0.3 ([Li2O] + [MgO] + [ZnO])
///   - [Al2O3]) / [B2O3]. Coefficient -12.5 F when F <= 4, otherwise -50. The table gives the range -50 to 0, so
///   F < 0 (more Al2O3 than the weighted modifiers) is outside the published method: B2O3 is then not counted.
///   CdO is in Appen's F but not in GlazeCore's oxide list.
/// - PbO (footnote e): 130 when the sum of [R2O] (Li2O, Na2O, K2O) is below 3, otherwise 115 + 5 x sum [R2O].
///   The table gives the range 130 to 190, so a sum of [R2O] above 15 is outside it: PbO is then not counted.
/// - TiO2 (footnote f): 105 - 1.5 [SiO2], valid only for 50 <= [SiO2] <= 80. Outside that, TiO2 is not counted.
/// - Cr2O3: Appen gives no value. Not counted.
/// - All other oxides: the constant in oxides.json (Appen's table, checked by lanes G7 and G8).
///
/// "Not counted" oxides make the estimate partial. `Chemistry.expansionNotCounted` lists them and the calculator
/// adds a warning, so the app never shows a partial sum as a complete estimate.
public enum Appen {
    /// The partial coefficient of `oxide` (1e-7 per K per mole percent) in a glass with the mole percents `mol`,
    /// or the reason why Appen's method gives no value for it here.
    public static func coefficient(_ oxide: Oxide, molePercent mol: [Oxide: Double],
                                   table: [Oxide: OxideInfo]) -> Result<Double, NotCounted> {
        func p(_ o: Oxide) -> Double { mol[o] ?? 0 }
        switch oxide {
        case .SiO2:
            return .success(p(.SiO2) < 67 ? 38 : 105 - p(.SiO2))
        case .K2O:
            return .success(p(.Na2O) > 1 ? 465 : 420)
        case .B2O3:
            let b = p(.B2O3)
            guard b > 0 else { return .success(0) }
            let modifiers = p(.Na2O) + p(.K2O) + p(.BaO) + 0.7 * (p(.CaO) + p(.SrO) + p(.PbO))
                + 0.3 * (p(.Li2O) + p(.MgO) + p(.ZnO))
            let f = (modifiers - p(.Al2O3)) / b
            guard f >= 0 else { return .failure(.outsideRange("Al2O3 is higher than the fluxes that Appen's B2O3 term uses")) }
            return .success(f <= 4 ? -12.5 * f : -50)
        case .PbO:
            let r2o = p(.Li2O) + p(.Na2O) + p(.K2O)
            if r2o < 3 { return .success(130) }
            guard r2o <= 15 else { return .failure(.outsideRange("Li2O + Na2O + K2O is above 15 mol %")) }
            return .success(115 + 5 * r2o)
        case .TiO2:
            let s = p(.SiO2)
            guard s >= 50, s <= 80 else { return .failure(.outsideRange("SiO2 is outside 50 to 80 mol %")) }
            return .success(105 - 1.5 * s)
        default:
            guard let k = table[oxide]?.expansionCoefficient else { return .failure(.noCoefficient) }
            return .success(k)
        }
    }

    /// Why an oxide is not in the estimate.
    public enum NotCounted: Error, Equatable, Sendable {
        /// Appen gives no coefficient for this oxide (Cr2O3).
        case noCoefficient
        /// The glass is outside the composition range of Appen's formula for this oxide.
        case outsideRange(String)

        var text: String {
            switch self {
            case .noCoefficient: return "no Appen coefficient"
            case .outsideRange(let why): return why
            }
        }
    }

    /// Sum of (mole fraction x coefficient) over the oxides that have a coefficient, and the oxides left out
    /// (in oxide order) with a warning that names each one and its reason. `nil` warning when nothing is left out.
    static func estimate(molePercent mol: [Oxide: Double], table: [Oxide: OxideInfo])
        -> (value: Double, notCounted: [Oxide], warning: String?) {
        var value = 0.0
        var left: [(Oxide, NotCounted)] = []
        for oxide in Oxide.allCases {
            guard let m = mol[oxide], m > 0 else { continue }
            switch coefficient(oxide, molePercent: mol, table: table) {
            case .success(let k): value += m / 100 * k
            case .failure(let why): left.append((oxide, why))
            }
        }
        guard !left.isEmpty else { return (value, [], nil) }
        let parts = left.map { "\($0.0.rawValue) (\($0.1.text))" }.joined(separator: "; ")
        return (value, left.map(\.0),
                "Expansion estimate is partial: it does not count \(parts).")
    }
}
