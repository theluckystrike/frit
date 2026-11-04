import Foundation

/// The result of Oxide Nudge or Replace Material: the new recipe, the chemistry before and after (base only,
/// additions not counted), the UMF the solver aimed for, and what it could not reach.
public struct Adjustment: Sendable {
    /// The changed recipe. It keeps the id, name and notes of the original; the caller decides whether it
    /// replaces the original or becomes a new recipe.
    public let recipe: Recipe
    public let before: Chemistry
    public let after: Chemistry
    /// The UMF the solver aimed for.
    public let target: [Oxide: Double]
    /// After minus target, in UMF, for each oxide that missed its target by more than `Reformulate.tolerance`.
    /// Negative = below the target ("short"). Empty when every target was reached.
    public let residual: [Oxide: Double]
    /// Replace Material: oxides of the original that no material in the new recipe supplies. Empty for Oxide Nudge.
    public let unsupplied: [Oxide]
    /// Replace Material: the flux oxides of the new material that take the share of the unsupplied flux oxides
    /// (for example Na2O for K2O when Soda feldspar replaces Potash feldspar). Empty when no flux was lost.
    public let standIn: [Oxide]

    /// True when every oxide reached its target.
    public var isExact: Bool { residual.isEmpty }
}

public enum ReformulateError: Error, Equatable, Sendable, LocalizedError {
    /// No base material in the recipe (or in the extra materials) contains this oxide, so its amount cannot
    /// change. An addition may contain it; Oxide Nudge does not change additions.
    case noSource(Oxide)
    /// The oxide is the only flux in the recipe, so its UMF is always 1.
    case onlyFlux(Oxide)
    /// The recipe's base has no flux oxides, so it has no UMF to work from.
    case noFlux
    /// The target is not a possible UMF value (negative, not a number, or above 1 for a flux oxide), or the
    /// recipe has nothing the solver can change.
    case infeasible
    /// The material to replace is not a base line of the recipe.
    case notInRecipe(String)
    /// The replacement material is not in the library (or its analysis is not valid).
    case unknownMaterial(String)

    public var errorDescription: String? {
        switch self {
        case .noSource(let oxide):
            return "No base material in this recipe contains \(oxide.formula). Oxide Nudge changes only base materials, not additions. Add a base material that supplies it."
        case .onlyFlux(let oxide):
            return "\(oxide.formula) is the only flux in this recipe, so its unity value is always 1. Add a material with another flux to change it."
        case .noFlux:
            return "The recipe has no flux oxides, so it has no unity formula to adjust."
        case .infeasible:
            return "This target cannot be reached. A flux oxide must be between 0 and 1, and other oxides 0 or more."
        case .notInRecipe:
            return "That material is not in the base of this recipe."
        case .unknownMaterial:
            return "The replacement material has no valid analysis."
        }
    }
}

/// Oxide Nudge and Replace Material: change a recipe's amounts so that its unity formula reaches a target.
///
/// Method. Each material is one unknown (its amount). Each oxide is one equation: the sum of
/// amount x (oxide % / 100 / molar mass) over the materials, divided by the flux moles of the original recipe,
/// should equal the target UMF value. One more equation keeps the flux sum at 1, so that the result is a true
/// unity formula. `Solver.nnls` solves the system with every amount 0 or more, in two stages:
/// 1. Best fit. The flux-sum equation and, for Oxide Nudge, the nudged oxide have a large weight
///    (`hardWeight`), so the nudged oxide reaches its target whenever some recipe of these materials reaches it.
///    The other oxides then come as close to their targets as they can.
/// 2. Stay near. Among the recipes with that best fit, the one nearest the current amounts wins: the stage-1
///    oxide values are kept (weight `fitWeight`) and each amount is pulled toward its current value with
///    weight 1 (lambda = 1 / `fitWeight`, in fractions of the base). Then a small correction on the materials
///    in use restores the stage-1 oxide values exactly. So when the materials depend on each other (for
///    example Wollastonite = Whiting + Silica in oxide space), the result does not jump to a far vertex.
/// When the materials cannot reach the target, `Adjustment.residual` says by how much each oxide missed.
/// Additions (colorants, opacifiers) are not changed and do not count, the same as the chemistry pane with
/// "Include additions" off.
public enum Reformulate {
    /// A residual smaller than this is treated as 0.
    public static let tolerance = 1e-6
    /// The change in UMF of one click on a Nudge arrow in the chemistry pane.
    public static let step = 0.05
    /// Weight of the flux-sum equation and of the nudged oxide in stage 1.
    static let hardWeight = 1e3
    /// Weight of the stage-1 oxide values in stage 2, against weight 1 for "stay near the current amounts".
    static let fitWeight = 1e4

    // MARK: Oxide Nudge

    /// Changes the amounts of the base materials so that `oxide` reaches `target` in the UMF and the other
    /// oxides stay as close as possible to their current UMF values.
    /// For a flux oxide, the other flux oxides keep their ratios to each other and share the rest of the unity.
    /// `extraMaterialIDs` are materials that may be added to the recipe (for example Silica when no line
    /// supplies SiO2). The new base is scaled to 100; additions keep their percent of the base.
    public static func nudge(_ r: Recipe, oxide: Oxide, toUMF target: Double, library: any MaterialLibrary,
                             extraMaterialIDs: [String] = []) throws -> Adjustment {
        let table = try OxideTable.load()
        let before = try baseChemistry(r, library: library)
        guard !before.umf.isEmpty else { throw ReformulateError.noFlux }
        guard target.isFinite, target >= 0 else { throw ReformulateError.infeasible }

        var goal = before.umf
        if table[oxide]?.role == .flux {
            let current = before.umf[oxide] ?? 0
            let others = 1 - current
            guard target <= 1 + 1e-12 else { throw ReformulateError.infeasible }
            if others <= 1e-12 {
                // The only flux: its UMF is 1 by definition.
                guard abs(target - 1) <= 1e-9 else { throw ReformulateError.onlyFlux(oxide) }
            } else {
                let k = (1 - target) / others
                for (o, v) in before.umf where o != oxide && table[o]?.role == .flux { goal[o] = v * k }
            }
        }
        goal[oxide] = target
        goal = goal.filter { $0.value > 0 || $0.key == oxide }

        let ids = variableIDs(r, library: library, extra: extraMaterialIDs)
        let supplies = ids.contains { (library.material(id: $0)?.analysis[oxide] ?? 0) > 0 }
        if !supplies && target > tolerance { throw ReformulateError.noSource(oxide) }

        var working = r
        let amounts = try solve(working, ids: ids, goal: goal, library: library, table: table, hard: [oxide])
        working = apply(amounts, to: working, ids: ids)
        working = scaleBase(working, originalBase: r.baseTotal, to: 100)
        return try finish(working, before: before, goal: goal, library: library)
    }

    /// Bundled or custom materials that supply `oxide`, best first: materials with fewer oxides first, then a
    /// higher percent of the oxide. For the "No material in this recipe contains ..." message.
    public static func suggestedSources(for oxide: Oxide, library: any MaterialLibrary, limit: Int = 4) -> [Material] {
        let list = library.all.filter { m in
            (m.analysis[oxide] ?? 0) > 0 && library.material(id: m.id) != nil
        }
        let sorted = list.sorted { a, b in
            let na = a.analysis.filter { $0.value > 0 }.count, nb = b.analysis.filter { $0.value > 0 }.count
            if na != nb { return na < nb }
            let pa = a.analysis[oxide] ?? 0, pb = b.analysis[oxide] ?? 0
            if pa != pb { return pa > pb }
            return a.name < b.name
        }
        return Array(sorted.prefix(max(0, limit)))
    }

    // MARK: Replace Material

    /// Replaces the base material `old` with `new` and solves the amounts of `new` and the other base
    /// materials so that the UMF matches the original as closely as possible. Among the closest matches, the
    /// one nearest the current amounts wins (the new material starts from the old one's amount), so the base
    /// total can change (Normalize Base to 100 scales it back).
    /// When a flux oxide of the original has no source left (Potash feldspar to Soda feldspar removes K2O), its
    /// share of the flux goes to the new material's flux oxides, not to the other fluxes. So the new material
    /// gets about the flux of the old one, and the other amounts stay near their current values.
    /// `Adjustment.unsupplied` and `standIn` name the oxides. Additions are not changed. Replacing a material
    /// with itself gives the recipe unchanged.
    public static func replace(_ r: Recipe, materialID old: String, with new: String,
                               library: any MaterialLibrary) throws -> Adjustment {
        let table = try OxideTable.load()
        guard r.lines.contains(where: { !$0.isAddition && $0.materialID == old }) else {
            throw ReformulateError.notInRecipe(old)
        }
        guard library.material(id: new) != nil else { throw ReformulateError.unknownMaterial(new) }
        let before = try baseChemistry(r, library: library)
        guard !before.umf.isEmpty else { throw ReformulateError.noFlux }
        if new == old {
            return Adjustment(recipe: r, before: before, after: before, target: before.umf, residual: [:],
                              unsupplied: [], standIn: [])
        }

        // The first line of the old material becomes the new material (same row, same line id). Other lines of
        // the old material go. When the new material is already in the base, every old line goes.
        var working = r
        let newInBase = r.lines.contains { !$0.isAddition && $0.materialID == new }
        var replacedFirst = newInBase
        working.lines = r.lines.compactMap { line in
            guard !line.isAddition, line.materialID == old else { return line }
            if replacedFirst { return nil }
            replacedFirst = true
            var l = line
            l.materialID = new
            return l
        }

        let ids = variableIDs(working, library: library, extra: [])
        var supplied: Set<Oxide> = []
        for id in ids { for (o, pct) in library.material(id: id)?.analysis ?? [:] where pct > 0 { supplied.insert(o) } }
        let unsupplied = before.umf.keys.filter { !supplied.contains($0) && (before.umf[$0] ?? 0) > 0 }
            .sorted { $0.order < $1.order }
        let lostFlux = unsupplied.filter { table[$0]?.role == .flux }.reduce(0) { $0 + (before.umf[$1] ?? 0) }

        // Goal: the original UMF. A lost flux share goes to the new material's flux oxides, in the molar ratio
        // they have in the new material. Without that, the flux-sum equation spreads the lost share over every
        // other flux, and the other amounts move far from their current values (L7 C2).
        var goal = before.umf
        var standIn: [Oxide] = []
        var keepFluxSum = true
        if lostFlux > 0 {
            for o in unsupplied { goal[o] = nil }
            var newFlux: [Oxide: Double] = [:]
            for (o, pct) in library.material(id: new)?.analysis ?? [:] where pct > 0 && table[o]?.role == .flux {
                if let mass = table[o]?.molarMass, mass > 0 { newFlux[o] = pct / mass }
            }
            let sum = newFlux.values.reduce(0, +)
            if sum > 0 {
                for (o, v) in newFlux { goal[o, default: 0] += lostFlux * v / sum }
                standIn = newFlux.keys.sorted { $0.order < $1.order }
            } else {
                // The new material has no flux: keep the other materials' oxide amounts and let the flux sum fall.
                // The UMF then rescales the remaining fluxes; nothing else can give the lost flux back.
                keepFluxSum = false
            }
        }

        let amounts = try solve(working, ids: ids, goal: goal, library: library, table: table,
                                scaleFrom: r, fluxSum: keepFluxSum)
        working = apply(amounts, to: working, ids: ids)
        return try finish(working, before: before, goal: before.umf, library: library,
                          unsupplied: unsupplied, standIn: standIn)
    }

    // MARK: Chemistry pane and sheet text

    /// True when the chemistry pane shows Nudge arrows for `oxide`. There are none while the pane includes
    /// additions (Oxide Nudge works on the base only, so "Now" would differ from the value clicked, L7 C4), none
    /// without a UMF, and none on the only flux of a recipe (its UMF is always 1, L7 C5).
    public static func canNudge(_ oxide: Oxide, chemistry: Chemistry, includeAdditions: Bool) -> Bool {
        guard !includeAdditions, !chemistry.umf.isEmpty else { return false }
        guard OxideTable.info(oxide)?.role == .flux else { return true }
        return chemistry.umf.contains { $0.key != oxide && OxideTable.info($0.key)?.role == .flux && $0.value > 1e-12 }
    }

    /// The Oxide Nudge line for an oxide that missed its target by `d` (after minus target).
    public static func nudgeMissText(_ oxide: Oxide, _ d: Double, nudged: Oxide) -> String {
        let head = "\(oxide.formula) ends \(NumberText.format(abs(d), fractionDigits: 3...3)) \(d < 0 ? "below" : "above") its target"
        if oxide == nudged { return head + ". These materials cannot bring it closer." }
        return head + ", with the other oxides held as close as they can be."
    }

    /// The Replace Material line for an oxide that ends `d` away from the original (after minus original).
    public static func replaceMissText(_ oxide: Oxide, _ d: Double, adjustment: Adjustment) -> String {
        let head = "\(oxide.formula) ends \(NumberText.format(abs(d), fractionDigits: 3...3)) \(d < 0 ? "below" : "above") the original"
        if adjustment.unsupplied.contains(oxide) { return head + ". No material in the new recipe supplies it." }
        let lostFlux = adjustment.unsupplied.filter { OxideTable.info($0)?.role == .flux }
        if d > 0, adjustment.standIn.contains(oxide), !lostFlux.isEmpty {
            let names = lostFlux.map(\.formula).joined(separator: " and ")
            return head + ". The new material's \(oxide.formula) takes the place of the missing \(names) as a flux."
        }
        return head + ", with the other oxides held as close as they can be."
    }

    // MARK: Shared steps

    /// Chemistry of the base, lines without a material left out (as the chemistry pane does).
    public static func baseChemistry(_ r: Recipe, library: any MaterialLibrary) throws -> Chemistry {
        var filled = r
        filled.lines = r.lines.filter { !$0.materialID.isEmpty }
        return try GlazeCalculator.chemistry(of: filled, library: library, includeAdditions: false)
    }

    /// The base materials the solver may change, in recipe order, then the extra ones. Each id once.
    static func variableIDs(_ r: Recipe, library: any MaterialLibrary, extra: [String]) -> [String] {
        var ids: [String] = []
        for line in r.lines where !line.isAddition && line.amount.isFinite && line.amount >= 0 {
            if library.material(id: line.materialID) != nil, !ids.contains(line.materialID) { ids.append(line.materialID) }
        }
        for id in extra where library.material(id: id) != nil && !ids.contains(id) { ids.append(id) }
        return ids
    }

    /// Solves the amounts of `ids`, one amount per material, in the units of the recipe's amounts.
    /// The UMF is measured against the flux moles of `scaleFrom` (default: the recipe itself).
    /// `hard` oxides (the nudged one) get `hardWeight` in stage 1. `fluxSum` false drops the flux-sum equation.
    /// Stage 2 pulls each amount toward its current amount in `r` (0 for a material not in `r`).
    static func solve(_ r: Recipe, ids: [String], goal: [Oxide: Double], library: any MaterialLibrary,
                      table: [Oxide: OxideInfo], scaleFrom: Recipe? = nil, hard: Set<Oxide> = [],
                      fluxSum: Bool = true) throws -> [String: Double] {
        let reference = scaleFrom ?? r
        let base = reference.baseTotal
        guard base > 0, base.isFinite, !ids.isEmpty else { throw ReformulateError.infeasible }

        // Moles of each oxide per unit amount of each material.
        func perUnit(_ id: String) throws -> [Oxide: Double] {
            guard let m = library.material(id: id) else { return [:] }
            var out: [Oxide: Double] = [:]
            for (o, pct) in m.analysis where pct > 0 {
                guard let info = table[o], info.molarMass > 0 else { throw GlazeError.missingOxideData(o) }
                out[o] = pct / 100 / info.molarMass
            }
            return out
        }
        // Flux moles of the reference recipe's base.
        var fluxMoles = 0.0
        for line in reference.lines where !line.isAddition && line.amount > 0 && line.amount.isFinite {
            for (o, v) in try perUnit(line.materialID) where table[o]?.role == .flux { fluxMoles += line.amount * v }
        }
        guard fluxMoles > 0, fluxMoles.isFinite else { throw ReformulateError.noFlux }

        let units = try ids.map(perUnit)
        var oxides = Set(goal.keys)
        for u in units { oxides.formUnion(u.keys) }
        let rows = oxides.sorted { $0.order < $1.order }

        // Unknown j is the amount of material j as a fraction of the base, so the numbers are near 1.
        var a: [[Double]] = rows.map { o in units.map { ($0[o] ?? 0) * base / fluxMoles } }
        var b: [Double] = rows.map { goal[$0] ?? 0 }
        var w: [Double] = rows.map { hard.contains($0) ? hardWeight : 1 }
        if fluxSum {
            a.append(ids.indices.map { j in
                rows.enumerated().reduce(0) { sum, item in table[item.element]?.role == .flux ? sum + a[item.offset][j] : sum }
            })
            b.append(1)
            w.append(hardWeight)
        }

        // Stage 1: best fit.
        let n = ids.count
        let x1 = Solver.nnls(a, b, weights: w)
        let fit = a.map { row in (0..<n).reduce(0) { $0 + row[$1] * x1[$1] } }

        // Stage 2: keep the stage-1 oxide values, and stay near the current amounts (fractions of the base).
        var current = [Double](repeating: 0, count: n)
        for line in r.lines where !line.isAddition && line.amount > 0 && line.amount.isFinite {
            if let j = ids.firstIndex(of: line.materialID) { current[j] += line.amount / base }
        }
        let a2 = a + (0..<n).map { j in (0..<n).map { $0 == j ? 1.0 : 0.0 } }
        let b2 = fit + current
        let w2 = a.map { _ in fitWeight } + current.map { _ in 1.0 }
        var x = Solver.nnls(a2, b2, weights: w2)

        // Stage 2 keeps the fit only to about 1 / fitWeight². Restore it on the materials in use.
        let support = (0..<n).filter { x[$0] > 0 }
        if !support.isEmpty {
            let miss = a.indices.map { i in fit[i] - (0..<n).reduce(0) { $0 + a[i][$1] * x[$1] } }
            let d = Solver.leastSquares(columns: support.map { j in a.map { $0[j] } }, rhs: miss)
            for (k, j) in support.enumerated() where d[k].isFinite { x[j] = max(0, x[j] + d[k]) }
        }
        var out: [String: Double] = [:]
        for (j, id) in ids.enumerated() {
            let v = x[j] * base
            guard v.isFinite, v <= NumberText.maxMagnitude else { throw CalculationError.resultOutOfRange }
            out[id] = v < base * 1e-9 ? 0 : v
        }
        return out
    }

    /// Writes the solved amounts into the base lines. A material on several lines keeps the split between
    /// its lines. A solved material that is not in the recipe gets a new base line after the last base line.
    static func apply(_ amounts: [String: Double], to r: Recipe, ids: [String]) -> Recipe {
        var out = r
        var groupTotal: [String: Double] = [:]
        var groupCount: [String: Int] = [:]
        for line in r.lines where !line.isAddition && amounts[line.materialID] != nil {
            groupTotal[line.materialID, default: 0] += max(0, line.amount)
            groupCount[line.materialID, default: 0] += 1
        }
        var seen: Set<String> = []
        for i in out.lines.indices {
            let line = out.lines[i]
            guard !line.isAddition, line.amount.isFinite, line.amount >= 0, let total = amounts[line.materialID] else { continue }
            let old = groupTotal[line.materialID] ?? 0
            if old > 0 {
                out.lines[i].amount = total * (line.amount / old)
            } else {
                // All lines of the material were 0: the first one takes the whole amount.
                out.lines[i].amount = seen.contains(line.materialID) ? 0 : total
            }
            seen.insert(line.materialID)
        }
        let insertAt = (out.lines.lastIndex { !$0.isAddition }).map { $0 + 1 } ?? 0
        var newLines: [RecipeLine] = []
        for id in ids where !seen.contains(id) {
            if let v = amounts[id], v > 0 { newLines.append(RecipeLine(materialID: id, amount: v, isAddition: false)) }
        }
        out.lines.insert(contentsOf: newLines, at: insertAt)
        return out
    }

    /// Scales the base to `target`; additions keep their percent of the original base.
    static func scaleBase(_ r: Recipe, originalBase: Double, to target: Double) -> Recipe {
        let newBase = r.baseTotal
        guard newBase > 0, newBase.isFinite, originalBase > 0 else { return r }
        var out = r
        for i in out.lines.indices where out.lines[i].amount > 0 && out.lines[i].amount.isFinite {
            out.lines[i].amount *= out.lines[i].isAddition ? target / originalBase : target / newBase
        }
        return out
    }

    static func finish(_ recipe: Recipe, before: Chemistry, goal: [Oxide: Double],
                       library: any MaterialLibrary, unsupplied: [Oxide] = [],
                       standIn: [Oxide] = []) throws -> Adjustment {
        let after = try baseChemistry(recipe, library: library)
        var residual: [Oxide: Double] = [:]
        for o in Set(goal.keys).union(after.umf.keys) {
            let d = (after.umf[o] ?? 0) - (goal[o] ?? 0)
            if abs(d) > tolerance { residual[o] = d }
        }
        return Adjustment(recipe: recipe, before: before, after: after, target: goal, residual: residual,
                          unsupplied: unsupplied, standIn: standIn)
    }
}
