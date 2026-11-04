import Foundation
import Testing
@testable import GlazeCore

/// W6 F2 finding 1: the decode checks the book before the app takes it.
@Suite("Book validation on open")
struct BookValidationTests {
    private func book(version: Int = 1, recipes: [Recipe]? = nil, materials: [Material] = [],
                      tests: [TestTile] = []) -> GlazeBook {
        let r = recipes ?? [recipe("A", [("silica", 30), ("kaolin", 20)], additions: [("red-iron-oxide", 2)])]
        return GlazeBook(recipes: r, customMaterials: materials, tests: tests, version: version)
    }

    private func roundTrip(_ b: GlazeBook) throws -> GlazeBook {
        try GlazeBookCodec.decode(try GlazeBookCodec.encode(b))
    }

    private func decodeError(_ b: GlazeBook) throws -> GlazeBookError? {
        let data = try GlazeBookCodec.encoder().encode(b)
        do {
            _ = try GlazeBookCodec.decode(data)
            return nil
        } catch let e as GlazeBookError {
            return e
        }
    }

    @Test func validBookDecodesByteCompatible() throws {
        let b = SampleBook.make()
        let data = try GlazeBookCodec.encode(b)
        let back = try GlazeBookCodec.decode(data)
        #expect(back == b)
        #expect(try GlazeBookCodec.encode(back) == data)
    }

    @Test func newerVersionIsRejectedWithMessage() throws {
        // F3 round 3: format 2 is read now (tile codes), so the newer format is 3.
        let e = try decodeError(book(version: 3))
        #expect(e == .unsupportedVersion(found: 3, supported: 2))
        #expect(e?.errorDescription?.contains("Update Frit") == true)
        #expect(e?.errorDescription?.contains("not changed") == true)
    }

    @Test func newerVersionWithUnknownFieldsIsNotRewritten() throws {
        let json = #"{"customMaterials":[],"futureField":{"x":1},"recipes":[],"tests":[],"version":7}"#
        #expect(throws: GlazeBookError.unsupportedVersion(found: 7, supported: 2)) {
            try GlazeBookCodec.decode(Data(json.utf8))
        }
    }

    @Test func versionZeroIsRejected() throws {
        #expect(try decodeError(book(version: 0)) == .invalidVersion(0))
    }

    @Test func duplicateRecipeIDIsRejected() throws {
        let a = recipe("A", [("silica", 30)])
        var b = recipe("B", [("kaolin", 30)])
        b.id = a.id
        let e = try decodeError(book(recipes: [a, b]))
        #expect(e == .duplicateID(kind: "recipe", id: a.id.uuidString))
        #expect(e?.errorDescription?.contains(a.id.uuidString) == true)
    }

    @Test func duplicateLineIDInOneRecipeIsRejected() throws {
        var a = recipe("A", [("silica", 30), ("kaolin", 20)])
        a.lines[1].id = a.lines[0].id
        #expect(try decodeError(book(recipes: [a])) == .duplicateID(kind: "line in recipe A", id: a.lines[0].id.uuidString))
    }

    @Test func duplicateMaterialAndTestIDsAreRejected() throws {
        let m = Material(id: "custom-1", name: "Mine", analysis: [.SiO2: 50], loi: 0, source: "")
        var m2 = m
        m2.name = "Other"
        #expect(try decodeError(book(materials: [m, m2])) == .duplicateID(kind: "material", id: "custom-1"))
        let t = TestTile(recipeID: UUID(), cone: "6", atmosphere: "Oxidation", schedule: [], notes: "",
                         photoBookmark: nil, date: Date(timeIntervalSince1970: 0))
        #expect(try decodeError(book(tests: [t, t])) == .duplicateID(kind: "test tile", id: t.id.uuidString))
    }

    @Test func absurdAmountIsRejected() throws {
        let r = recipe("Big", [("silica", 1e308)])
        let e = try decodeError(book(recipes: [r]))
        #expect(e == .numberOutOfRange(field: "an amount in recipe Big", value: 1e308, limit: 1e9))
        #expect(e?.errorDescription?.contains("1e+308") == true)
    }

    @Test func overflowingJSONNumberIsNotTaken() throws {
        let json = #"{"customMaterials":[],"recipes":[{"cone":"6","id":"\#(UUID().uuidString)","lines":[{"amount":1e400,"id":"\#(UUID().uuidString)","isAddition":false,"materialID":"silica"}],"name":"X","notes":""}],"tests":[],"version":1}"#
        #expect(throws: (any Error).self) { try GlazeBookCodec.decode(Data(json.utf8)) }
    }

    @Test func absurdAnalysisAndFiringAreRejected() throws {
        let m = Material(id: "custom-1", name: "Mine", analysis: [.SiO2: 250], loi: 0, source: "")
        #expect(try decodeError(book(materials: [m])) == .numberOutOfRange(field: "SiO2 in material Mine", value: 250, limit: 100))
        let t = TestTile(recipeID: UUID(), cone: "6", atmosphere: "Oxidation",
                         schedule: [FiringSegment(ratePerHour: 100, targetC: 1e300, holdMinutes: 0)], notes: "",
                         photoBookmark: nil, date: Date(timeIntervalSince1970: 0))
        #expect(try decodeError(book(tests: [t])) == .numberOutOfRange(field: "a firing temperature", value: 1e300, limit: 1e6))
    }

    @Test func boundaryValuesStillOpen() throws {
        let r = recipe("Edge", [("silica", 1e9), ("kaolin", -5), ("whiting", 1e-9)])
        let m = Material(id: "custom-1", name: "Mine", analysis: [.SiO2: 100], loi: 0, source: "")
        let b = book(recipes: [r], materials: [m])
        #expect(try roundTrip(b) == b)
    }
}
