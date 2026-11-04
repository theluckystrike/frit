import Foundation

public struct Chemistry: Sendable {
    /// Unity molecular formula: moles of each oxide divided by the sum of the flux moles (flux sum = 1.0).
    /// Empty when the recipe has no flux.
    public let umf: [Oxide: Double]
    /// Moles of each oxide / moles of all oxides x 100.
    public let molePercent: [Oxide: Double]
    /// Fired weight of each oxide / fired weight of all oxides x 100 (LOI removed).
    public let weightPercent: [Oxide: Double]
    /// SiO2 : Al2O3 molar ratio. 0 when there is no Al2O3.
    public let siAlRatio: Double
    /// (Li2O + Na2O + K2O) / flux sum. 0 when there is no flux.
    public let r2oRatio: Double
    /// Sum of (mole fraction x Appen coefficient), units 1e-7 per K, with Appen's composition-dependent terms
    /// (see `Appen`). nil when there are no oxides. Partial when `expansionNotCounted` is not empty.
    public let expansion: Double?
    /// Oxides present in the calculation that the expansion estimate does not count (no Appen coefficient, or
    /// the glass is outside the range of Appen's formula for that oxide). Empty = the estimate is complete.
    public let expansionNotCounted: [Oxide]
    public let warnings: [String]

    /// True when the expansion estimate leaves out at least one oxide that is in the recipe.
    public var expansionIsPartial: Bool { expansion != nil && !expansionNotCounted.isEmpty }

    public init(umf: [Oxide: Double], molePercent: [Oxide: Double], weightPercent: [Oxide: Double], siAlRatio: Double,
                r2oRatio: Double, expansion: Double?, expansionNotCounted: [Oxide] = [], warnings: [String]) {
        self.umf = umf
        self.molePercent = molePercent
        self.weightPercent = weightPercent
        self.siAlRatio = siAlRatio
        self.r2oRatio = r2oRatio
        self.expansion = expansion
        self.expansionNotCounted = expansionNotCounted
        self.warnings = warnings
    }
}

public enum GlazeCalculator {
    static let r2o: Set<Oxide> = [.Li2O, .Na2O, .K2O]

    /// Method:
    /// 1. For each line (additions only when `includeAdditions`): moles of oxide =
    ///    amount x analysis% / 100 / molar mass. The analysis is fired-oxide weight percent per 100 g of raw
    ///    material, so the LOI is already outside it.
    /// 2. Sum the moles per oxide over all lines.
    /// 3. UMF = moles / sum of moles of the `.flux` oxides. Colorants, stabilizers and glass formers are not in the sum.
    /// 4. Mole %, weight % (moles x molar mass), Si:Al, R2O share and the Appen expansion estimate (`Appen`).
    ///
    /// Lines with an unknown material id, a negative amount or a zero amount are skipped
    /// (the first two with a warning). Throws `GlazeError.nonFiniteAmount` for NaN or infinite amounts and
    /// `GlazeError.missingOxideData` when the oxide table cannot be used.
    public static func chemistry(of recipe: Recipe, library: any MaterialLibrary, includeAdditions: Bool) throws -> Chemistry {
        let table = try OxideTable.load()
        var warnings: [String] = []
        var moles: [Oxide: Double] = [:]

        for line in recipe.lines {
            if line.isAddition && !includeAdditions { continue }
            guard line.amount.isFinite else { throw GlazeError.nonFiniteAmount(materialID: line.materialID) }
            if line.amount < 0 {
                // Name the material as the recipe table shows it, not by its internal id (W5 V4).
                let name = library.material(id: line.materialID)?.name ?? line.materialID
                warnings.append("Negative amount for \(name) (\(fmtWarning(line.amount))): line ignored.")
                continue
            }
            if line.amount == 0 { continue }
            guard let material = library.material(id: line.materialID) else {
                warnings.append("Unknown material \"\(line.materialID)\" (not in the library or the book): line ignored.")
                continue
            }
            for (oxide, percent) in material.analysis where percent > 0 {
                guard let info = table[oxide], info.molarMass > 0 else { throw GlazeError.missingOxideData(oxide) }
                // Ratio first, so a large amount does not overflow before the division (W6 F2).
                moles[oxide, default: 0] += line.amount * (percent / 100 / info.molarMass)
            }
        }
        moles = moles.filter { $0.value > 0 }

        let totalMoles = moles.values.reduce(0, +)
        try requireFinite(moles.values, totalMoles)
        if totalMoles == 0 {
            warnings.append("The recipe has no materials to calculate.")
            return Chemistry(umf: [:], molePercent: [:], weightPercent: [:], siAlRatio: 0, r2oRatio: 0,
                             expansion: nil, warnings: warnings)
        }

        let fluxSum = moles.filter { table[$0.key]?.role == .flux }.values.reduce(0, +)
        var umf: [Oxide: Double] = [:]
        var r2oRatio = 0.0
        if fluxSum > 0 {
            umf = moles.mapValues { $0 / fluxSum }
            r2oRatio = umf.filter { r2o.contains($0.key) }.values.reduce(0, +)
            try requireFinite(umf.values, r2oRatio)
        } else {
            warnings.append("No flux oxides: the UMF cannot be normalized (flux sum is 0).")
        }

        let molePercent = moles.mapValues { $0 / totalMoles * 100 }
        let grams = Dictionary(uniqueKeysWithValues: moles.map { ($0.key, $0.value * table[$0.key]!.molarMass) })
        let totalGrams = grams.values.reduce(0, +)
        let weightPercent = grams.mapValues { $0 / totalGrams * 100 }
        try requireFinite(weightPercent.values, totalGrams)

        var siAl = 0.0
        if let al = moles[.Al2O3], al > 0 {
            siAl = (moles[.SiO2] ?? 0) / al
            try requireFinite([], siAl)
        } else {
            warnings.append("No Al2O3: the SiO2:Al2O3 ratio is not defined (shown as 0).")
        }

        // Appen's estimate with its composition-dependent terms (SiO2 above 67 mol %, K2O, B2O3, PbO, TiO2).
        let appen = Appen.estimate(molePercent: molePercent, table: table)
        if let warning = appen.warning { warnings.append(warning) }

        return Chemistry(umf: umf, molePercent: molePercent, weightPercent: weightPercent, siAlRatio: siAl,
                         r2oRatio: r2oRatio, expansion: appen.value, expansionNotCounted: appen.notCounted,
                         warnings: warnings)
    }
}

/// A number for a warning: no binary noise, no trailing zeros (-10, -2.5).
func fmtWarning(_ v: Double) -> String {
    v.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
}

extension Oxide {
    /// Position in `allCases` (declaration order), used to sort oxide names in messages.
    var order: Int { Oxide.allCases.firstIndex(of: self) ?? 0 }
}
