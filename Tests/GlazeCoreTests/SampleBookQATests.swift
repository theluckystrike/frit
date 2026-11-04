import Foundation
import Testing
@testable import GlazeCore

private func sampleBook() -> GlazeBook { SampleBook.make() }

@Suite("Sample book QA")
struct SampleBookQATests {
    @Test("Every sample recipe has a valid chemistry")
    func sampleChemistry() throws {
        for r in sampleBook().recipes {
            let c = try chem(r)
            let fluxSum = c.umf.filter { $0.key.info?.role == .flux }.reduce(0) { $0 + $1.value }
            #expect(near(fluxSum, 1.0, 1e-9), "\(r.name)")
            #expect((c.umf[.SiO2] ?? 0) > 0 && (c.umf[.Al2O3] ?? 0) > 0, "\(r.name)")
        }
    }

    /// With GLAZE_QA_OUT=<dir>, writes Sample.glazebook, Sample-<n>.glazebook (recipe n first, for screenshots)
    /// and umf.txt (the UMF of each recipe, additions excluded and included) to that directory.
    @Test("Write QA files when GLAZE_QA_OUT is set")
    func writeQAFiles() throws {
        guard let dir = ProcessInfo.processInfo.environment["GLAZE_QA_OUT"] else { return }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        let encoder = GlazeBookCodec.encoder()
        let book = sampleBook()
        try encoder.encode(book).write(to: out.appendingPathComponent("Sample.glazebook"))
        for n in 1...book.recipes.count {
            var rotated = book
            rotated.recipes = Array(book.recipes[(n - 1)...] + book.recipes[..<(n - 1)])
            try encoder.encode(rotated).write(to: out.appendingPathComponent("Sample-\(n).glazebook"))
        }
        var text = ""
        for r in book.recipes {
            for additions in [false, true] {
                let c = try chem(r, additions: additions)
                text += "\(r.name) additions=\(additions)\n"
                for o in Oxide.allCases where (c.umf[o] ?? 0) > 0.00005 {
                    text += String(format: "  %-6@ umf %.3f  mol%% %.1f  wt%% %.1f\n", o.rawValue as NSString,
                                   c.umf[o]!, c.molePercent[o] ?? 0, c.weightPercent[o] ?? 0)
                }
                text += String(format: "  Si:Al %.2f  R2O %.2f  expansion %@  region %@\n", c.siAlRatio, c.r2oRatio,
                               (c.expansion.map { String(format: "%.1f", $0) } ?? "nil") as NSString,
                               Stull.region(siO2: c.umf[.SiO2] ?? 0, al2O3: c.umf[.Al2O3] ?? 0).rawValue as NSString)
                text += "  warnings: \(c.warnings)\n"
            }
        }
        try text.write(to: out.appendingPathComponent("umf.txt"), atomically: true, encoding: .utf8)
    }
}
