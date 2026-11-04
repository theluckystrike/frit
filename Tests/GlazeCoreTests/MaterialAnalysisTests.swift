import Foundation
import Testing
@testable import GlazeCore

/// W6 C1: custom analysis and LOI fields took values above 100 % and dropped negative values silently.
@Suite("Custom material analysis limits W6 F1")
struct MaterialAnalysisTests {
    let en = Locale(identifier: "en_US")

    private func material(_ analysis: [Oxide: Double], loi: Double = 0) -> Material {
        Material(id: "custom-test", name: "Test", analysis: analysis, loi: loi, source: "")
    }

    @Test func fieldTakesValuesFromZeroToHundred() {
        #expect(MaterialRules.parsePercent("0", locale: en) == .value(0))
        #expect(MaterialRules.parsePercent("", locale: en) == .value(0))
        #expect(MaterialRules.parsePercent("12.345", locale: en) == .value(12.345))
        #expect(MaterialRules.parsePercent("100", locale: en) == .value(100))
    }

    @Test func fieldRefusesNegativeAndAboveHundred() {
        for t in ["-5", "-0.01", "100.01", "250", "1e308"] {
            #expect(MaterialRules.parsePercent(t, locale: en) == .outOfRange, "\(t)")
            #expect(MaterialRules.parsePercent(t, locale: en).error != nil)
        }
        for t in ["abc", "nan", "inf"] {
            #expect(MaterialRules.parsePercent(t, locale: en) == .notANumber, "\(t)")
        }
    }

    @Test func validMaterialHasNoIssues() {
        #expect(MaterialRules.issues(material([.SiO2: 60, .Al2O3: 25], loi: 15)).isEmpty)
        #expect(MaterialRules.isUsable(material([:])))
    }

    @Test func outOfRangeValuesAreIssues() {
        #expect(MaterialRules.issues(material([.SiO2: 250])) == [.oxideOutOfRange(.SiO2, 250)])
        #expect(MaterialRules.issues(material([.CaO: -5])) == [.oxideOutOfRange(.CaO, -5)])
        #expect(MaterialRules.issues(material([.SiO2: 50], loi: -1)) == [.loiOutOfRange(-1)])
        #expect(MaterialRules.issues(material([.SiO2: 50], loi: 120)) == [.loiOutOfRange(120)])
        #expect(!MaterialRules.isUsable(material([.SiO2: .nan])))
        #expect(!MaterialRules.isUsable(material([.SiO2: 50], loi: .infinity)))
    }

    @Test func totalAboveLimitIsAnIssue() {
        #expect(MaterialRules.issues(material([.SiO2: 80, .Al2O3: 30])) == [.totalTooHigh(110)])
        #expect(MaterialRules.isUsable(material([.SiO2: 80, .Al2O3: 21])))  // 101 %: data-sheet rounding
    }

    @Test func everyBundledMaterialIsUsable() {
        for m in lib.all { #expect(MaterialRules.isUsable(m), "\(m.id): \(MaterialRules.issues(m))") }
    }

    @Test func issueMessagesNameTheValue() {
        #expect(MaterialRules.Issue.oxideOutOfRange(.SiO2, 250).message.contains("250"))
        #expect(MaterialRules.Issue.loiOutOfRange(.nan).message.contains("not a number"))
    }
}
