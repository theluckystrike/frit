import Foundation

/// The text rules of the live number fields (recipe amounts, batch weight).
public enum NumberText {
    public static func format(_ v: Double, fractionDigits: ClosedRange<Int>, locale: Locale = .current) -> String {
        v.formatted(.number.precision(.fractionLength(fractionDigits)).grouping(.never).locale(locale))
    }

    /// The largest amount or batch weight that a field takes: 1,000,000 (grams or parts).
    /// W6 X4: an entry of 1e308 was taken, two of them made the base total infinite and every chemistry
    /// value showed "NaN". No glaze batch comes near this limit.
    public static let maxMagnitude = 1_000_000.0

    /// A finite number not larger than `maxMagnitude`, or nil. `allowsNegative: false` also gives nil for a value below 0.
    public static func parse(_ s: String, allowsNegative: Bool = true, locale: Locale = .current) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let v = try? Double(trimmed, format: .number.locale(locale)), v.isFinite,
              abs(v) <= maxMagnitude else { return nil }
        if !allowsNegative && v < 0 { return nil }
        return v
    }

    /// The value that a change of the field's text writes to the document, or nil for no write.
    ///
    /// Only typing writes (`isEditing`). The field's own display text never writes: it is the stored value
    /// rounded to `fractionDigits`, so writing it back would change the book although nobody edited it
    /// (W5 V4: a line of 1e-9 g, or a blend tile of 19.200000000000003 g, was rewritten and autosaved when the
    /// recipe was shown).
    public static func valueToWrite(text: String, current: Double, isEditing: Bool,
                                    fractionDigits: ClosedRange<Int>, allowsNegative: Bool = true,
                                    locale: Locale = .current) -> Double? {
        guard isEditing, text != format(current, fractionDigits: fractionDigits, locale: locale),
              let v = parse(text, allowsNegative: allowsNegative, locale: locale), v != current else { return nil }
        return v
    }
}

/// Which recipe the sidebar shows after the book's recipe list changes.
public enum RecipeSelection {
    /// `selected` when it is still in the book. When an Undo, Redo or Delete removed it, the recipe now at its old
    /// position (or the last one). Nil when the book has no recipes or nothing was selected.
    /// W5 V4: Undo of Duplicate Recipe left the window on "No Recipe Selected".
    public static func afterChange(selected: UUID?, before: [UUID], after: [UUID]) -> UUID? {
        guard let selected else { return nil }
        if after.contains(selected) { return selected }
        guard !after.isEmpty else { return nil }
        let oldIndex = before.firstIndex(of: selected) ?? 0
        return after[min(oldIndex, after.count - 1)]
    }
}
