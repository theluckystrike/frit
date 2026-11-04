import Foundation

/// Rows that are not complete enough to calculate or weigh (W6 F3: an unnamed row with an amount was left out of
/// the chemistry without a word, but the batch sheet printed it as "Choose material").
public extension Recipe {
    /// Lines with a non-zero amount and no material. The chemistry leaves them out; the batch sheet is blocked.
    var linesWithoutMaterial: [RecipeLine] {
        lines.filter { $0.materialID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.amount != 0 }
    }
}

public enum RecipeCheck {
    /// True when the line has an amount but no material.
    public static func isMissingMaterial(_ line: RecipeLine) -> Bool {
        line.materialID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && line.amount != 0
    }

    /// The note for the chemistry pane, or nil when every line with an amount has a material.
    public static func chemistryNote(_ recipe: Recipe) -> String? {
        let n = recipe.linesWithoutMaterial.count
        guard n > 0 else { return nil }
        return "\(rows(n)) an amount but no material. The chemistry leaves \(n == 1 ? "it" : "them") out. "
            + "Choose a material or remove the row."
    }

    /// Why the batch sheet cannot be printed or exported, or nil when it can.
    public static func batchBlockReason(_ recipe: Recipe) -> String? {
        let n = recipe.linesWithoutMaterial.count
        guard n > 0 else { return nil }
        return "\(rows(n)) an amount but no material. Choose a material or remove the row "
            + "before you print or export the batch sheet."
    }

    private static func rows(_ n: Int) -> String { n == 1 ? "1 row has" : "\(n) rows have" }
}
