import Foundation
import Testing
@testable import GlazeCore

/// Defects found in the W5 V4 reviewer pass (25 Oct 2026) on main 375ea86. Each test covers one fix.
@Suite("Reviewer pass W5 V4")
struct ReviewerPassTests {
    let en = Locale(identifier: "en_US")

    // Showing a recipe must not write its amounts back. Before: a field showed 1e-9 as "0" and wrote 0,
    // and a blend tile amount of 19.200000000000003 was written back as 19.2, so the book became "Edited"
    // and was autosaved with no user edit.
    @Test func displayTextNeverWritesTheValue() {
        for v in [1e-9, 19.200000000000003, 2.6666666666666665, 1e9, 18] {
            let shown = NumberText.format(v, fractionDigits: 0...2, locale: en)
            #expect(NumberText.valueToWrite(text: shown, current: v, isEditing: false, fractionDigits: 0...2, locale: en) == nil)
            #expect(NumberText.valueToWrite(text: shown, current: v, isEditing: true, fractionDigits: 0...2, locale: en) == nil)
        }
    }

    @Test func typingWritesTheValue() {
        #expect(NumberText.valueToWrite(text: "28", current: 18, isEditing: true, fractionDigits: 0...2, locale: en) == 28)
        #expect(NumberText.valueToWrite(text: "2.5", current: 18, isEditing: true, fractionDigits: 0...2, locale: en) == 2.5)
        // Not while the field is only being set up.
        #expect(NumberText.valueToWrite(text: "28", current: 18, isEditing: false, fractionDigits: 0...2, locale: en) == nil)
    }

    @Test func badEntriesAreNotTaken() {
        for t in ["", "abc", "-5", "inf", "nan", "1e999"] {
            #expect(NumberText.valueToWrite(text: t, current: 18, isEditing: true, fractionDigits: 0...2,
                                            allowsNegative: false, locale: en) == nil, "\(t)")
        }
        #expect(NumberText.parse("-5", allowsNegative: true, locale: en) == -5)
    }

    // W6 X4: a huge entry (1e308) was taken, and two of them showed NaN in every chemistry value.
    @Test func hugeEntriesAreNotTaken() {
        for t in ["1e308", "99999999999999999999", "1000001", "-1e308"] {
            #expect(NumberText.parse(t, allowsNegative: true, locale: en) == nil, "\(t)")
            #expect(NumberText.valueToWrite(text: t, current: 18, isEditing: true, fractionDigits: 0...2,
                                            locale: en) == nil, "\(t)")
        }
        #expect(NumberText.parse("1000000", allowsNegative: false, locale: en) == 1_000_000)
    }

    // The batch sheet marked a base line "(addition)" when the same material was also an addition.
    @Test func batchKeepsEachLinesAdditionFlag() {
        let r = recipe([("silica", 30), ("whiting", 20), ("kaolin", 20), ("potash-feldspar", 30), ("red-iron-oxide", 2)],
                       additions: [("red-iron-oxide", 4)])
        let out = Batch.scale(r, totalGrams: 1000, precision: 0.1)
        let iron = out.filter { $0.materialID == "red-iron-oxide" }
        #expect(iron.count == 2)
        #expect(iron.map(\.isAddition) == [false, true])
        #expect(out.filter { $0.materialID == "silica" }.allSatisfy { !$0.isAddition })
    }

    // Warnings named the material by its internal id ("silica").
    @Test func negativeAmountWarningUsesTheMaterialName() throws {
        let c = try chem(recipe([("silica", -10), ("whiting", 20), ("kaolin", 20), ("potash-feldspar", 40)]))
        let w = try #require(c.warnings.first { $0.lowercased().contains("negative") })
        #expect(w.contains(lib.material(id: "silica")!.name))
        #expect(w.contains("(-10)"))
        #expect(!w.contains("\"silica\""))
    }

    // Undo of Duplicate Recipe (or Delete) left the window on "No Recipe Selected".
    @Test func selectionMovesToTheRecipeInItsPlace() {
        let ids = (0..<4).map { _ in UUID() }
        #expect(RecipeSelection.afterChange(selected: ids[1], before: ids, after: ids) == ids[1])
        var removed = ids; removed.remove(at: 1)
        #expect(RecipeSelection.afterChange(selected: ids[1], before: ids, after: removed) == ids[2])
        var last = ids; last.removeLast()
        #expect(RecipeSelection.afterChange(selected: ids[3], before: ids, after: last) == ids[2])
        #expect(RecipeSelection.afterChange(selected: ids[0], before: [ids[0]], after: []) == nil)
        #expect(RecipeSelection.afterChange(selected: nil, before: ids, after: ids) == nil)
    }

    // The material detail showed a developer path, "(tools/gen_data.py)", as part of each source.
    @Test func bundledSourcesHaveNoDeveloperPaths() {
        for m in lib.all {
            #expect(!m.source.contains("tools/") && !m.source.contains(".py"), "\(m.id)")
        }
    }
}
