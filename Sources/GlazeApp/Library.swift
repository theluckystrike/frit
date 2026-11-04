import Foundation
import GlazeCore

/// SwiftUI also has a `Material` type (background blur). In this app, `Material` is a glaze material.
typealias Material = GlazeCore.Material

/// The bundled material library, loaded once.
enum AppLibrary {
    static let loadResult: Result<BundledLibrary, Error> = Result { try BundledLibrary() }

    static var bundledMaterials: [Material] {
        (try? loadResult.get())?.all ?? []
    }

    static var loadErrorMessage: String? {
        if case .failure(let error) = loadResult {
            return "The bundled material list did not load: \(error.localizedDescription)"
        }
        return nil
    }
}

/// Bundled materials plus the custom materials of one book. Custom materials win on an id clash.
/// `material(id:)`, which the calculator uses, leaves out a custom material whose analysis is not valid
/// (`MaterialRules.issues`), so that it adds nothing to the chemistry (W6 F1). Names still show it.
struct BookLibrary: MaterialLibrary {
    let bundled: [Material]
    let custom: [Material]
    private let index: [String: Material]

    init(custom: [Material]) {
        self.bundled = AppLibrary.bundledMaterials
        self.custom = custom
        var index: [String: Material] = [:]
        for material in bundled { index[material.id] = material }
        for material in custom { index[material.id] = material }
        self.index = index
    }

    func material(id: String) -> Material? {
        guard let m = index[id], MaterialRules.isUsable(m) else { return nil }
        return m
    }

    var all: [Material] { custom + bundled.filter { b in !custom.contains { $0.id == b.id } } }

    func isCustom(_ id: String) -> Bool { custom.contains { $0.id == id } }

    func name(for id: String) -> String {
        if id.isEmpty { return "Choose material" }
        return index[id]?.name ?? "Unknown material (\(id))"
    }
}

// MARK: - Oxide presentation

enum OxideGroup: String, CaseIterable, Identifiable {
    case flux = "Fluxes (RO / R₂O)"
    case stabilizer = "Stabilizers (R₂O₃)"
    case glassFormer = "Glass formers (RO₂)"
    case colorant = "Colorants"
    var id: String { rawValue }
}

extension Oxide {
    /// Formula with subscript digits, for display.
    var display: String { formula }

    /// Formula spelled for VoiceOver, for example "S i O 2".
    var spoken: String {
        rawValue.map(String.init).joined(separator: " ")
    }

    /// Group used for the UMF table. Uses the role from GlazeCore's oxide table, so the groups match the flux unity.
    var group: OxideGroup {
        switch info?.role {
        case .flux: return .flux
        case .stabilizer: return .stabilizer
        case .glassFormer: return .glassFormer
        case .colorant: return .colorant
        case nil:
            switch self {
            case .Li2O, .Na2O, .K2O, .MgO, .CaO, .SrO, .BaO, .ZnO, .PbO: return .flux
            case .Al2O3, .B2O3: return .stabilizer
            case .SiO2, .TiO2, .ZrO2, .SnO2, .P2O5: return .glassFormer
            case .Fe2O3, .MnO, .CoO, .CuO, .Cr2O3, .NiO: return .colorant
            }
        }
    }

    var isR2O: Bool { self == .Li2O || self == .Na2O || self == .K2O }
}

// MARK: - Number formatting

func fmt(_ value: Double, _ digits: Int = 2) -> String {
    value.formatted(.number.precision(.fractionLength(digits)))
}

func fmtAmount(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
}
