import Foundation

/// Oxide data from the bundled oxides.json (molar masses, roles, expansion coefficients).
public enum OxideTable {
    private static let cached: Result<[Oxide: OxideInfo], any Error> = Result { try decode() }

    /// The oxide table. Throws when oxides.json is missing or invalid.
    public static func load() throws -> [Oxide: OxideInfo] { try cached.get() }

    public static func info(_ oxide: Oxide) -> OxideInfo? { (try? load())?[oxide] }

    public static func role(of oxide: Oxide) -> OxideRole? { info(oxide)?.role }

    private static func decode() throws -> [Oxide: OxideInfo] {
        guard let url = ResourceBundle.url("oxides", "json") else {
            throw GlazeError.resourceMissing("oxides.json")
        }
        let list = try JSONDecoder().decode([OxideInfo].self, from: Data(contentsOf: url))
        return Dictionary(list.map { ($0.oxide, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

public extension Oxide {
    /// Molar mass, role and expansion coefficient from oxides.json (nil only if the resource is broken).
    var info: OxideInfo? { OxideTable.info(self) }
}

public protocol MaterialLibrary: Sendable {
    func material(id: String) -> Material?
    var all: [Material] { get }
}

/// The materials bundled with the app (Resources/materials.json). All are theoretical or generic.
public struct BundledLibrary: MaterialLibrary {
    public let all: [Material]
    private let byID: [String: Material]

    public init() throws {
        guard let url = ResourceBundle.url("materials", "json") else {
            throw GlazeError.resourceMissing("materials.json")
        }
        let list = try JSONDecoder().decode([Material].self, from: Data(contentsOf: url))
        _ = try OxideTable.load()
        all = list
        byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func material(id: String) -> Material? { byID[id] }
}

/// Custom materials first, then a base library. A custom material with the same id replaces the base one.
public struct LayeredLibrary: MaterialLibrary {
    public let custom: [Material]
    public let base: any MaterialLibrary
    private let customByID: [String: Material]

    public init(custom: [Material], base: any MaterialLibrary) {
        self.custom = custom
        self.base = base
        customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func material(id: String) -> Material? { customByID[id] ?? base.material(id: id) }

    public var all: [Material] {
        let ids = Set(customByID.keys)
        return custom + base.all.filter { !ids.contains($0.id) }
    }
}
