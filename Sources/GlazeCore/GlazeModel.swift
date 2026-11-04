import Foundation

/// The oxides that GlazeCore calculates. The raw value is the id used in JSON files.
public enum Oxide: String, CaseIterable, Codable, Sendable {
    case Li2O, Na2O, K2O, MgO, CaO, SrO, BaO, ZnO, PbO, B2O3, Al2O3, SiO2, TiO2, ZrO2, Fe2O3, MnO, CoO, CuO, Cr2O3, NiO, SnO2, P2O5
}

/// Lets `[Oxide: Double]` encode as a JSON object (`{"SiO2": 60.1}`) instead of a key/value array.
extension Oxide: CodingKeyRepresentable {}

/// Column of the unity molecular formula. Only `.flux` oxides make up the flux unity.
public enum OxideRole: String, Codable, Sendable { case flux, stabilizer, glassFormer, colorant }

public struct OxideInfo: Codable, Sendable {
    public let oxide: Oxide
    /// g/mol, from IUPAC 2021 standard atomic weights.
    public let molarMass: Double
    public let role: OxideRole
    /// Appen partial coefficient of linear expansion, 1e-7 per K per mole percent. nil = not available.
    public let expansionCoefficient: Double?

    public init(oxide: Oxide, molarMass: Double, role: OxideRole, expansionCoefficient: Double?) {
        self.oxide = oxide
        self.molarMass = molarMass
        self.role = role
        self.expansionCoefficient = expansionCoefficient
    }
}

public struct Material: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// Weight percent of each fired oxide per 100 g of raw material. Sum of analysis + loi = 100.
    public var analysis: [Oxide: Double]
    /// Loss on ignition, percent of the raw material.
    public var loi: Double
    /// Where the analysis comes from.
    public var source: String

    public init(id: String, name: String, analysis: [Oxide: Double], loi: Double, source: String) {
        self.id = id
        self.name = name
        self.analysis = analysis
        self.loi = loi
        self.source = source
    }
}

public struct RecipeLine: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var materialID: String
    /// Weight (any unit; usually grams or parts per 100).
    public var amount: Double
    /// Additions (colorants, opacifiers) are kept apart from the base recipe.
    public var isAddition: Bool

    public init(id: UUID = UUID(), materialID: String, amount: Double, isAddition: Bool = false) {
        self.id = id
        self.materialID = materialID
        self.amount = amount
        self.isAddition = isAddition
    }
}

public struct Recipe: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var cone: String
    public var lines: [RecipeLine]
    public var notes: String

    public init(id: UUID = UUID(), name: String, cone: String, lines: [RecipeLine], notes: String = "") {
        self.id = id
        self.name = name
        self.cone = cone
        self.lines = lines
        self.notes = notes
    }

    /// Sum of the positive base (non-addition) amounts.
    public var baseTotal: Double {
        lines.filter { !$0.isAddition && $0.amount > 0 && $0.amount.isFinite }.reduce(0) { $0 + $1.amount }
    }
}

public struct FiringSegment: Codable, Hashable, Sendable {
    public var ratePerHour: Double
    public var targetC: Double
    public var holdMinutes: Double

    public init(ratePerHour: Double, targetC: Double, holdMinutes: Double) {
        self.ratePerHour = ratePerHour
        self.targetC = targetC
        self.holdMinutes = holdMinutes
    }
}

public struct TestTile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var recipeID: UUID
    public var cone: String
    public var atmosphere: String
    public var schedule: [FiringSegment]
    public var notes: String
    /// Security-scoped bookmark to a photo file the user picked.
    public var photoBookmark: Data?
    public var date: Date
    /// The short code that the potter writes on the back of the fired tile (T-001, T-002, ...). The user can change
    /// it. `TileCode` gives new codes and checks that no two tiles share one. Empty only in a book saved before
    /// tile codes existed; `GlazeBookCodec.open` fills those in (F3).
    public var code: String

    public init(id: UUID = UUID(), recipeID: UUID, cone: String, atmosphere: String, schedule: [FiringSegment],
                notes: String, photoBookmark: Data?, date: Date, code: String = "") {
        self.id = id
        self.recipeID = recipeID
        self.cone = cone
        self.atmosphere = atmosphere
        self.schedule = schedule
        self.notes = notes
        self.photoBookmark = photoBookmark
        self.date = date
        self.code = code
    }

    private enum CodingKeys: String, CodingKey {
        case id, recipeID, cone, atmosphere, schedule, notes, photoBookmark, date, code
    }

    /// Books saved before tile codes existed have no "code" key. They decode with an empty code.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        recipeID = try c.decode(UUID.self, forKey: .recipeID)
        cone = try c.decode(String.self, forKey: .cone)
        atmosphere = try c.decode(String.self, forKey: .atmosphere)
        schedule = try c.decode([FiringSegment].self, forKey: .schedule)
        notes = try c.decode(String.self, forKey: .notes)
        photoBookmark = try c.decodeIfPresent(Data.self, forKey: .photoBookmark)
        date = try c.decode(Date.self, forKey: .date)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
    }
}

/// The document (`.glazebook`, JSON).
public struct GlazeBook: Codable, Sendable, Equatable {
    public var recipes: [Recipe]
    public var customMaterials: [Material]
    public var tests: [TestTile]
    public var version: Int
    /// The number of the next tile code that `TileCode` gives (T-001 is 1). It only goes up, so a deleted tile's
    /// code is never given to a new tile. 1 in a book saved before tile codes existed (F3).
    public var nextTileNumber: Int

    public init(recipes: [Recipe], customMaterials: [Material], tests: [TestTile], version: Int, nextTileNumber: Int = 1) {
        self.recipes = recipes
        self.customMaterials = customMaterials
        self.tests = tests
        self.version = version
        self.nextTileNumber = nextTileNumber
    }

    private enum CodingKeys: String, CodingKey {
        case recipes, customMaterials, tests, version, nextTileNumber
    }

    /// The file format stays 1: the new key is optional, so an older book opens without change of meaning.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recipes = try c.decode([Recipe].self, forKey: .recipes)
        customMaterials = try c.decode([Material].self, forKey: .customMaterials)
        tests = try c.decode([TestTile].self, forKey: .tests)
        version = try c.decode(Int.self, forKey: .version)
        nextTileNumber = try c.decodeIfPresent(Int.self, forKey: .nextTileNumber) ?? 1
    }
}

public enum GlazeError: Error, Equatable, Sendable {
    /// A recipe line amount is NaN or infinite.
    case nonFiniteAmount(materialID: String)
    /// A material analysis uses an oxide that has no molar mass in oxides.json.
    case missingOxideData(Oxide)
    /// A bundled resource file is missing from the bundle.
    case resourceMissing(String)
}
