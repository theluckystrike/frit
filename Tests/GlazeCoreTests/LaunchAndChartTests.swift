import Foundation
import Testing
@testable import GlazeCore

@Suite("First launch")
struct FirstLaunchTests {
    static let empty = GlazeBook(recipes: [], customMaterials: [], tests: [], version: 1)

    @Test func opensSampleOnlyForFirstEmptyUntitledBook() {
        #expect(FirstLaunch.shouldOpenSample(firstLaunchDone: false, isUntitled: true, book: Self.empty))
        // Not again after the first launch.
        #expect(!FirstLaunch.shouldOpenSample(firstLaunchDone: true, isUntitled: true, book: Self.empty))
        // Never in place of a file the user opened, even an empty one.
        #expect(!FirstLaunch.shouldOpenSample(firstLaunchDone: false, isUntitled: false, book: Self.empty))
        // Never in place of a book with content (for example Help > Open Sample Book itself).
        #expect(!FirstLaunch.shouldOpenSample(firstLaunchDone: false, isUntitled: true, book: SampleBook.make()))
    }
}

@Suite("Sample test tiles")
struct SampleTileTests {
    @Test func threeTilesForSampleRecipes() {
        let book = SampleBook.make()
        #expect(book.tests.count == 3)
        let ids = Set(book.recipes.map(\.id))
        for t in book.tests {
            #expect(ids.contains(t.recipeID))
            #expect(t.cone == "6")
            #expect(t.atmosphere == "Oxidation")
            #expect(t.schedule.count == 3)
            #expect(t.notes.hasPrefix("Sample entry."))
            #expect(t.photoBookmark == nil)
            // Each schedule climbs to a cone 6 top temperature.
            let targets = t.schedule.map(\.targetC)
            #expect(targets == targets.sorted())
            #expect((1200...1230).contains(targets.last ?? 0))
            #expect(t.schedule.allSatisfy { $0.ratePerHour > 0 && $0.holdMinutes >= 0 })
        }
        #expect(Set(book.tests.map(\.id)).count == 3)
    }

    @Test func tilesSurviveCodec() throws {
        let book = SampleBook.make()
        let decoded = try GlazeBookCodec.decode(try GlazeBookCodec.encode(book))
        #expect(decoded == book)
    }

    @Test func noSafetyWordingInSampleNotes() {
        for t in SampleBook.make().tests {
            let text = t.notes.lowercased()
            for bad in ["food", "lead free", "lead-free", "non-toxic", "safe"] { #expect(!text.contains(bad)) }
        }
    }
}

@Suite("Stull chart shape")
struct StullShapeTests {
    @Test func crazingTopIsContinuousAt2_4() {
        let below = Stull.crazingTop(siO2: 2.4 - 1e-9)
        let above = Stull.crazingTop(siO2: 2.4)
        #expect(abs(below - above) < 1e-6)
        #expect(abs(Stull.crazingTop(siO2: Stull.siO2Range.lowerBound) - 0.25) < 1e-9)
        #expect(abs(Stull.crazingTop(siO2: 3.0) - Stull.crazingBandTop(siO2: 3.0)) < 1e-12)
    }

    /// No rectangular step at SiO2 2.4: just left and just right of it the region is the same at every height.
    @Test func noStairStepAt2_4() {
        var y = Stull.al2O3Range.lowerBound + 0.0005
        var mismatches = 0
        while y < Stull.al2O3Range.upperBound {
            let left = Stull.region(siO2: 2.3999, al2O3: y)
            let right = Stull.region(siO2: 2.4001, al2O3: y)
            // the underfired area starts at 2.4 with zero height, so it can differ only within 0.001 of its line
            if left != right && abs(y - Stull.underfiredLine(siO2: 2.4001)) > 0.001
                && abs(y - Stull.crazingTop(siO2: 2.4)) > 0.001 { mismatches += 1 }
            y += 0.001
        }
        #expect(mismatches == 0)
    }

    @Test func labelAnchorsSitInTheirRegions() {
        #expect(Set(Stull.labelAnchors.map(\.region)) == [.gloss, .semimatte, .matte, .unfused, .underfired, .crazing])
        for a in Stull.labelAnchors {
            #expect(Stull.region(siO2: a.siO2, al2O3: a.al2O3) == a.region, "\(a.region)")
        }
    }
}

@Suite("Orton cones")
struct OrtonConeTests {
    // W6 F3: the cone picker had 15 cones and left out 03, 01, 2, 3 and others.
    @Test func fullSequence022To14() {
        let c = OrtonCones.all
        #expect(c.first == "022")
        #expect(c.last == "14")
        #expect(c.count == 37) // 022..010 (13) + 09..01 (9) + 05½ + 1..14 (14)
        #expect(Set(c).count == c.count)
        for cone in ["021", "019", "015", "011", "09", "07", "05½", "05", "03", "01", "2", "3", "12", "13"] {
            #expect(c.contains(cone), "missing cone \(cone)")
        }
        // Firing order: 06 < 05½ < 05 ... 01 < 1 < 2.
        #expect(c.firstIndex(of: "06")! < c.firstIndex(of: "05½")!)
        #expect(c.firstIndex(of: "05½")! < c.firstIndex(of: "05")!)
        #expect(c.firstIndex(of: "01")! + 1 == c.firstIndex(of: "1")!)
        // The sample book's cones are in the list.
        #expect(c.contains("6") && c.contains("10"))
    }
}
