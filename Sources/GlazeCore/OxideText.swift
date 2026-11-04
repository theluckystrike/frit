import Foundation

extension Oxide {
    /// Formula with subscript digits, for display (for example "B₂O₃").
    public var formula: String { OxideText.subscriptDigits(rawValue) }
}

public enum OxideText {
    private static let digits: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
    ]

    static func subscriptDigits(_ s: String) -> String { String(s.map { digits[$0] ?? $0 }) }

    /// Replaces every oxide formula in `text` (as a whole word, for example "B2O3" in a warning) with its subscript form.
    public static func subscripted(_ text: String) -> String {
        let names = Oxide.allCases.map(\.rawValue).sorted { $0.count > $1.count }
        let pattern = "\\b(" + names.joined(separator: "|") + ")\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += subscriptDigits(ns.substring(with: m.range))
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
