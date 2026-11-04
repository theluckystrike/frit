import Foundation
import Testing
@testable import GlazeCore

/// W6 F2 findings 2 and 3: every computed result is finite, and Normalize keeps full precision.
@Suite("Finite arithmetic and normalize")
struct ArithmeticTests {
    private static let custom = [
        Material(id: "pure-si", name: "Pure silica", analysis: [.SiO2: 100], loi: 0, source: "test"),
        Material(id: "pure-al", name: "Pure alumina", analysis: [.Al2O3: 100], loi: 0, source: "test"),
        Material(id: "pure-ca", name: "Pure lime", analysis: [.CaO: 100], loi: 0, source: "test"),
    ]
    private let layered = LayeredLibrary(custom: custom, base: lib)

    private func allFinite(_ c: Chemistry) -> Bool {
        let values = Array(c.umf.values) + Array(c.molePercent.values) + Array(c.weightPercent.values)
            + [c.siAlRatio, c.r2oRatio, c.expansion ?? 0]
        return values.allSatisfy(\.isFinite)
    }

    // MARK: Chemistry

    @Test func largeSingleAmountNoLongerOverflows() throws {
        // amount x percent was 1e308 x 99 = infinite before the division by 100 and the molar mass.
        let c = try chem(recipe([("silica", 1e308), ("whiting", 1e307)]))
        #expect(allFinite(c))
        #expect(!c.umf.isEmpty)
    }

    @Test func overflowingSumsThrowInsteadOfInfinity() {
        let r = recipe([("silica", 1e308), ("whiting", 1e308), ("kaolin", 1e308)])
        #expect(throws: CalculationError.resultOutOfRange) { try chem(r) }
    }

    @Test func tinyFluxWithLargeSilicaThrows() {
        let r = recipe([("pure-si", 1e6), ("pure-ca", 1e-310)])
        #expect(throws: CalculationError.resultOutOfRange) {
            try GlazeCalculator.chemistry(of: r, library: layered, includeAdditions: false)
        }
    }

    @Test func tinyAluminaWithLargeSilicaThrows() {
        let r = recipe([("pure-si", 1e6), ("pure-ca", 1), ("pure-al", 1e-310)])
        #expect(throws: CalculationError.resultOutOfRange) {
            try GlazeCalculator.chemistry(of: r, library: layered, includeAdditions: false)
        }
    }

    @Test func errorHasAUserMessage() {
        #expect(CalculationError.resultOutOfRange.errorDescription?.isEmpty == false)
    }

    // MARK: Batch

    @Test func tinyBaseScalesWithoutInfinity() {
        let rows = Batch.scale(recipe([("silica", 1e-300), ("kaolin", 1e-300)]), totalGrams: 1000, precision: 0.1)
        #expect(rows.map(\.grams) == [500, 500])
        #expect(Batch.problem(recipe([("silica", 1e-300)]), totalGrams: 1000, precision: 0.1) == nil)
    }

    @Test func tinyBaseWithAdditionIsRefused() {
        let r = recipe([("silica", 1e-310)], additions: [("red-iron-oxide", 1e6)])
        #expect(Batch.scale(r, totalGrams: 1e6, precision: 0).isEmpty)
        #expect(Batch.problem(r, totalGrams: 1e6, precision: 0)?.contains("finite") == true)
    }

    @Test func overflowingBaseIsRefused() {
        let r = recipe([("silica", 1e308), ("kaolin", 1e308)])
        #expect(r.baseTotal.isInfinite)
        #expect(Batch.scale(r, totalGrams: 1000, precision: 1).isEmpty)
        #expect(Batch.problem(r, totalGrams: 1000, precision: 1) == "The base total is too large to scale.")
    }

    @Test func batchProblemsForEmptyBaseAndBadWeight() {
        #expect(Batch.problem(recipe([], additions: [("red-iron-oxide", 2)]), totalGrams: 1000, precision: 1)
                == "Add base materials to the recipe first.")
        #expect(Batch.problem(recipe([("silica", 10)]), totalGrams: 0, precision: 1) == "Enter a batch weight above 0 g.")
    }

    // MARK: Normalize

    @Test func tinyBaseNormalizesToFiniteHundred() throws {
        let r = recipe([("silica", 1e-300), ("kaolin", 3e-300)])
        let n = try #require(Normalize.base(of: r))
        #expect(abs(n.baseTotal - 100) < 1e-9)
        #expect(n.lines.allSatisfy { $0.amount.isFinite })
    }

    @Test func unrepresentableNormalizeIsRefusedBeforeAnyChange() {
        let r = recipe([("silica", 1e-300)], additions: [("red-iron-oxide", 1)])
        #expect(Normalize.base(of: r) == nil)
        #expect(Normalize.problem(r)?.contains("additions") == true)
        #expect(Normalize.base(of: recipe([], additions: [("red-iron-oxide", 1)])) == nil)
        #expect(Normalize.problem(recipe([("silica", 1e308), ("kaolin", 1e308)])) == "The base total is too large to normalize.")
    }

    @Test func normalizeKeepsFullPrecision() throws {
        let n = try #require(Normalize.base(of: recipe([("silica", 1), ("kaolin", 1), ("whiting", 1)])))
        #expect(abs(n.baseTotal - 100) < 1e-12)
        #expect(n.lines.allSatisfy { abs($0.amount - 100.0 / 3) < 1e-12 })
    }

    @Test func normalizeKeepsTraceAdditions() throws {
        let r = recipe([("silica", 600), ("kaolin", 400)], additions: [("cobalt-carbonate", 0.02)])
        let n = try #require(Normalize.base(of: r))
        let trace = try #require(n.lines.first { $0.isAddition })
        #expect(abs(trace.amount - 0.002) < 1e-15)
        #expect(n.lines.map(\.id) == r.lines.map(\.id))
    }

    @Test func normalizedBookSavesAndOpens() throws {
        let n = try #require(Normalize.base(of: recipe([("silica", 1), ("kaolin", 2)], additions: [("red-iron-oxide", 1e-9)])))
        let book = GlazeBook(recipes: [n], customMaterials: [], tests: [], version: 1)
        #expect(try GlazeBookCodec.decode(try GlazeBookCodec.encode(book)) == book)
    }
}
