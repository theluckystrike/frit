import Foundation

/// The search of the material picker and which material Return or Choose takes.
public enum MaterialSearch {
    /// The materials whose name or id contains `query` (case is ignored). All materials for an empty query.
    public static func filter(_ list: [Material], query: String) -> [Material] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    /// The count under the picker's list: "1 material", "0 materials", "47 materials" (run 1104 L2 BUG-5).
    public static func countText(_ count: Int) -> String {
        count == 1 ? "1 material" : "\(count) materials"
    }

    /// The highlight to keep after the results change: nil when the highlighted material is no longer shown.
    public static func keptHighlight(_ highlighted: String?, resultIDs: [String]) -> String? {
        guard let highlighted, resultIDs.contains(highlighted) else { return nil }
        return highlighted
    }

    /// The material that a pick takes. Only a material in the results can be picked (W6 C1: Return took a
    /// highlighted material that the search had hidden). `fallbackToFirst` is for Return in the search field.
    public static func pick(highlighted: String?, resultIDs: [String], fallbackToFirst: Bool) -> String? {
        if let kept = keptHighlight(highlighted, resultIDs: resultIDs) { return kept }
        return fallbackToFirst ? resultIDs.first : nil
    }
}
