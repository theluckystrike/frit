import Foundation

public struct LimitRange: Codable, Sendable {
    public let oxide: Oxide
    public let min: Double
    public let max: Double
    /// Other oxides whose UMF values are added to `oxide` before the check. For example
    /// `oxide: .K2O, combinedWith: [.Na2O]` is a KNaO ((K+Na)2O) range. Nil for a single oxide.
    public let combinedWith: [Oxide]?

    public init(oxide: Oxide, min: Double, max: Double, combinedWith: [Oxide]? = nil) {
        self.oxide = oxide
        self.min = min
        self.max = max
        self.combinedWith = combinedWith
    }

    /// All oxides that this range covers (`oxide` first).
    public var oxides: [Oxide] { [oxide] + (combinedWith ?? []) }

    /// True when the range covers `o`, alone or as part of a sum.
    public func covers(_ o: Oxide) -> Bool { oxides.contains(o) }

    /// Display label: "KNaO" for K2O + Na2O, otherwise the oxide ids joined with "+".
    public var label: String {
        if Set(oxides) == [.K2O, .Na2O] { return "KNaO" }
        return oxides.map(\.rawValue).joined(separator: "+")
    }

    /// The UMF value that is compared with `min` and `max` (a missing oxide counts as 0).
    public func value(in umf: [Oxide: Double]) -> Double {
        oxides.reduce(0) { $0 + (umf[$1] ?? 0) }
    }
}

/// A set of UMF reference ranges for one cone and surface.
public struct LimitSet: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let cone: String
    public let ranges: [LimitRange]
    public let source: String

    public init(id: String, name: String, cone: String, ranges: [LimitRange], source: String) {
        self.id = id
        self.name = name
        self.cone = cone
        self.ranges = ranges
        self.source = source
    }
}

public enum Limits {
    static let arbuckle = "as reproduced in L. Arbuckle, \"Molecular Glaze Limit Ranges\", "
        + "University of Florida handout, 2012 (https://www.lindaarbuckle.com/handouts/glaze-limits.pdf)"
    static let hrSource = "J. Hesselberth and R. Roy, Ceramics Monthly, September 2000, "
        + arbuckle + "; KNaO 0.1-0.3 at cone 6 from the article (the handout shows .01-.03). "
        + "KNaO is checked as K2O + Na2O. Oxides without a range in the source are not checked."
    static let cushingSource = "Val Cushing, Cushing's Handbook, " + arbuckle
        + ". Checked cell by cell against B. Quinlan, M.S. thesis, Alfred University, 2002, Tables II-2 and II-3 "
        + "(from Cushing's Handbook, 3rd ed., 1994, pp. 47-51): no differences. "
        + "KNaO is checked as K2O + Na2O. The PbO ranges of the source are not bundled."

    private typealias Row = (Oxide, Double, Double)

    private static func set(_ id: String, _ name: String, _ cone: String, knao: (Double, Double),
                            _ rows: [Row], source: String) -> LimitSet {
        let k = LimitRange(oxide: .K2O, min: knao.0, max: knao.1, combinedWith: [.Na2O])
        return LimitSet(id: id, name: name, cone: cone,
                        ranges: [k] + rows.map { LimitRange(oxide: $0.0, min: $0.1, max: $0.2) }, source: source)
    }

    /// UMF reference ranges (flux sum 1.0) from published tables. They are for comparison only.
    /// Values and typo notes: Resources/README-data.md section 4.
    public static let bundled: [LimitSet] = [
        set("hr-cone6", "Hesselberth & Roy, cone 6", "6", knao: (0.10, 0.30), [
            (.CaO, 0.20, 0.60), (.MgO, 0, 0.30), (.ZnO, 0, 0.20), (.SrO, 0, 0.20),
            (.Al2O3, 0.25, 0.40), (.B2O3, 0.15, 0.35), (.SiO2, 2.5, 4.0),
        ], source: hrSource),
        set("hr-cone10", "Hesselberth & Roy, cone 10", "10", knao: (0.10, 0.30), [
            (.CaO, 0.30, 0.70), (.MgO, 0, 0.40), (.SrO, 0, 0.30),
            (.Al2O3, 0.30, 0.60), (.B2O3, 0, 0.30), (.SiO2, 3.0, 5.0),
        ], source: hrSource),
        set("cushing-c5-6-gloss", "Cushing, cone 5-6 gloss", "5-6", knao: (0.05, 0.60), [
            (.Li2O, 0, 0.50), (.ZnO, 0, 0.15), (.CaO, 0.05, 0.60), (.MgO, 0, 0.10), (.BaO, 0, 0.15), (.SrO, 0, 0.15),
            (.Al2O3, 0.10, 0.30), (.B2O3, 0, 1.0), (.SiO2, 1.5, 4.0),
        ], source: cushingSource),
        set("cushing-c5-6-satin", "Cushing, cone 5-6 satin", "5-6", knao: (0.05, 0.35), [
            (.Li2O, 0, 0.15), (.ZnO, 0, 0.30), (.CaO, 0.05, 0.70), (.MgO, 0, 0.35), (.BaO, 0, 0.35), (.SrO, 0, 0.35),
            (.Al2O3, 0.20, 0.40), (.B2O3, 0, 0.50), (.SiO2, 2.0, 3.5),
        ], source: cushingSource),
        set("cushing-c5-6-matt", "Cushing, cone 5-6 matt", "5-6", knao: (0.05, 0.30), [
            (.Li2O, 0, 0.10), (.ZnO, 0, 0.40), (.CaO, 0.05, 0.80), (.MgO, 0, 0.45), (.BaO, 0, 0.50), (.SrO, 0, 0.50),
            (.Al2O3, 0.20, 0.50), (.B2O3, 0, 0.50), (.SiO2, 2.0, 3.0),
        ], source: cushingSource),
        set("cushing-c9-10-gloss", "Cushing, cone 9-10 gloss", "9-10", knao: (0.05, 0.50), [
            (.Li2O, 0, 0.40), (.ZnO, 0, 0.15), (.CaO, 0.05, 0.80), (.MgO, 0, 0.15), (.BaO, 0, 0.15), (.SrO, 0, 0.15),
            (.Al2O3, 0.20, 0.50), (.B2O3, 0, 0.50), (.SiO2, 2.0, 6.0),
        ], source: cushingSource),
        set("cushing-c9-10-satin", "Cushing, cone 9-10 satin", "9-10", knao: (0.05, 0.40), [
            (.Li2O, 0, 0.20), (.ZnO, 0, 0.40), (.CaO, 0.05, 0.80), (.MgO, 0, 0.50), (.BaO, 0, 0.50), (.SrO, 0, 0.50),
            (.Al2O3, 0.25, 0.60), (.B2O3, 0, 0.40), (.SiO2, 2.0, 5.0),
        ], source: cushingSource),
        set("cushing-c9-10-matt", "Cushing, cone 9-10 matt", "9-10", knao: (0.05, 0.30), [
            (.Li2O, 0, 0.10), (.ZnO, 0, 0.50), (.CaO, 0.05, 0.90), (.MgO, 0, 0.60), (.BaO, 0, 0.60), (.SrO, 0, 0.60),
            (.Al2O3, 0.25, 0.80), (.B2O3, 0, 0.20), (.SiO2, 2.0, 5.0),
        ], source: cushingSource),
    ]

    /// For each range in the set: true when min <= value <= max, where the value is the UMF value of the oxide
    /// (or the sum for a combined range such as KNaO; a missing oxide counts as 0). A combined range gives the
    /// same result under each oxide it covers.
    public static func check(_ c: Chemistry, against set: LimitSet) -> [Oxide: Bool] {
        var out: [Oxide: Bool] = [:]
        let eps = 1e-9
        for r in set.ranges {
            let v = r.value(in: c.umf)
            let ok = v >= r.min - eps && v <= r.max + eps
            for o in r.oxides { out[o] = (out[o] ?? true) && ok }
        }
        return out
    }
}
