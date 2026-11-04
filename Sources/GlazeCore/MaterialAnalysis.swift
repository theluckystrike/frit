import Foundation

/// The limits of a custom material's analysis (W6 F1).
public extension MaterialRules {
    /// The range of one oxide weight percent and of the loss on ignition.
    static let percentRange: ClosedRange<Double> = 0...100
    /// The largest sum of oxides + LOI that a material can have. A little above 100 for rounding in data sheets.
    static let maxTotal = 102.0

    enum Issue: Equatable, Sendable {
        case oxideOutOfRange(Oxide, Double)
        case loiOutOfRange(Double)
        case totalTooHigh(Double)

        public var message: String {
            switch self {
            case .oxideOutOfRange(let oxide, let v):
                return "\(oxide.rawValue) is \(Self.text(v)) %. Enter a value from 0 to 100."
            case .loiOutOfRange(let v):
                return "The loss on ignition is \(Self.text(v)) %. Enter a value from 0 to 100."
            case .totalTooHigh(let v):
                return "Oxides + LOI = \(Self.text(v)) %. The total must not be more than 102 %."
            }
        }

        private static func text(_ v: Double) -> String {
            v.isFinite ? v.formatted(.number.precision(.fractionLength(0...3)).grouping(.never)) : "not a number"
        }
    }

    /// The problems of a material's analysis. Empty when the material can be used in the chemistry.
    static func issues(_ m: Material) -> [Issue] {
        var out: [Issue] = []
        for oxide in Oxide.allCases {
            guard let v = m.analysis[oxide] else { continue }
            if !v.isFinite || !percentRange.contains(v) { out.append(.oxideOutOfRange(oxide, v)) }
        }
        if !m.loi.isFinite || !percentRange.contains(m.loi) { out.append(.loiOutOfRange(m.loi)) }
        let total = m.analysis.values.reduce(0, +) + m.loi
        if out.isEmpty && total > maxTotal { out.append(.totalTooHigh(total)) }
        return out
    }

    static func isUsable(_ m: Material) -> Bool { issues(m).isEmpty }

    /// The value that a percent field takes from its text, or the reason it does not.
    enum PercentEntry: Equatable, Sendable {
        case value(Double)
        case notANumber
        case outOfRange

        public var error: String? {
            switch self {
            case .value: return nil
            case .notANumber: return "Enter a number from 0 to 100."
            case .outOfRange: return "Enter a value from 0 to 100."
            }
        }
    }

    /// Parses a percent field. Empty text is 0 (no oxide). Negative values, values above 100,
    /// NaN and infinity are refused (W6 C1: "-5" silently removed the oxide and "250" was taken).
    static func parsePercent(_ text: String, locale: Locale = .current) -> PercentEntry {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .value(0) }
        guard let v = try? Double(trimmed, format: .number.locale(locale)) else { return .notANumber }
        guard v.isFinite else { return .notANumber }
        guard percentRange.contains(v) else { return .outOfRange }
        return .value(v)
    }
}
