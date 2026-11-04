import Foundation
import Testing
@testable import GlazeCore

/// Silica, Whiting, Kaolin and Potash feldspar: every oxide has its own main source.
private func fourPart() -> Recipe {
    recipe("Four part", [("silica", 30), ("whiting", 20), ("kaolin", 20), ("potash-feldspar", 30)])
}

private func total(_ r: Recipe, _ id: String) -> Double {
    r.lines.filter { !$0.isAddition && $0.materialID == id }.reduce(0) { $0 + $1.amount }
}

@Suite("Solver.nnls")
struct SolverTests {
    @Test("matches a hand-solved 3x2 least-squares case")
    func handSolvedUnconstrained() {
        // A = [[1,0],[0,1],[1,1]], b = [1,2,2]. AᵀA = [[2,1],[1,2]], Aᵀb = [3,4], x = [2/3, 5/3].
        let x = Solver.nnls([[1, 0], [0, 1], [1, 1]], [1, 2, 2], weights: [])
        #expect(abs(x[0] - 2.0 / 3) < 1e-12)
        #expect(abs(x[1] - 5.0 / 3) < 1e-12)
    }

    @Test("a negative least-squares value is held at 0")
    func handSolvedConstrained() {
        // b = [-1,2,1]: the free solution is [-1, 2]. With x >= 0: x1 = 0, x2 = (2 + 1) / 2 = 1.5.
        let x = Solver.nnls([[1, 0], [0, 1], [1, 1]], [-1, 2, 1], weights: [1, 1, 1])
        #expect(x[0] == 0)
        #expect(abs(x[1] - 1.5) < 1e-12)
    }

    @Test("row weights pull the fit toward the heavy row")
    func weights() {
        // One unknown, two rows x = 1 and x = 3. Equal weights give 2; weight 3 on the second row gives
        // (1 + 9 x 3) / (1 + 9) = 2.8.
        #expect(abs(Solver.nnls([[1], [1]], [1, 3], weights: [])[0] - 2) < 1e-12)
        #expect(abs(Solver.nnls([[1], [1]], [1, 3], weights: [1, 3])[0] - 2.8) < 1e-12)
    }

    @Test("identical columns and bad input do not crash")
    func degenerate() {
        let x = Solver.nnls([[1, 1], [2, 2]], [1, 2], weights: [])
        #expect(abs((x[0] + x[1]) - 1) < 1e-9)
        #expect(x.allSatisfy { $0 >= 0 })
        #expect(Solver.nnls([[1, .nan]], [1], weights: []) == [0, 0])
        #expect(Solver.nnls([], [], weights: []).isEmpty)
    }
}

@Suite("Oxide Nudge")
struct OxideNudgeTests {
    @Test("SiO2 +0.5: SiO2 rises by 0.5, the other oxides stay, only Silica grows")
    func silicaUp() throws {
        let r = fourPart()
        let before = try chem(r)
        let target = (before.umf[.SiO2] ?? 0) + 0.5
        let adj = try Reformulate.nudge(r, oxide: .SiO2, toUMF: target, library: lib)
        #expect(adj.isExact)
        #expect(abs((adj.after.umf[.SiO2] ?? 0) - target) < 1e-6)
        for o in Oxide.allCases where o != .SiO2 {
            #expect(abs((adj.after.umf[o] ?? 0) - (before.umf[o] ?? 0)) < 1e-6, "\(o)")
        }
        #expect(total(adj.recipe, "silica") > 30)
        for id in ["whiting", "kaolin", "potash-feldspar"] {
            #expect(total(adj.recipe, id) < total(r, id), "\(id)")
        }
        // The other lines keep their ratios to each other (only Silica moved before the scaling to 100).
        #expect(abs(total(adj.recipe, "whiting") / total(adj.recipe, "kaolin") - 1) < 1e-9)
        #expect(abs(total(adj.recipe, "potash-feldspar") / total(adj.recipe, "kaolin") - 1.5) < 1e-9)
        #expect(adj.recipe.id == r.id && adj.recipe.name == r.name)
        #expect(adj.recipe.lines.map(\.id) == r.lines.map(\.id))
    }

    @Test("B2O3 with no boron source throws noSource; with Boric acid as an extra it reaches the target")
    func noSource() throws {
        let r = fourPart()
        #expect(throws: ReformulateError.noSource(.B2O3)) {
            try Reformulate.nudge(r, oxide: .B2O3, toUMF: 0.2, library: lib)
        }
        let adj = try Reformulate.nudge(r, oxide: .B2O3, toUMF: 0.2, library: lib, extraMaterialIDs: ["boric-acid"])
        #expect(adj.isExact)
        #expect(abs((adj.after.umf[.B2O3] ?? 0) - 0.2) < 1e-6)
        #expect(adj.recipe.lines.count == r.lines.count + 1)
        #expect(adj.recipe.lines.last?.materialID == "boric-acid")
        #expect(adj.recipe.lines.last?.isAddition == false)
    }

    @Test("no amount is negative, the base sums to 100, additions keep their percent of base")
    func amountsAndBase() throws {
        // Quarry Stone has a 4 % titanium addition. A flux nudge: CaO +0.05.
        let r = try #require(SampleBook.make().recipes.first { $0.name == "Quarry Stone" })
        let before = try chem(r)
        let target = (before.umf[.CaO] ?? 0) + 0.05
        let adj = try Reformulate.nudge(r, oxide: .CaO, toUMF: target, library: lib)
        #expect(adj.recipe.lines.allSatisfy { $0.amount >= 0 })
        #expect(abs(adj.recipe.baseTotal - 100) < 1e-9)
        let addBefore = r.lines.filter(\.isAddition).reduce(0) { $0 + $1.amount } / r.baseTotal
        let addAfter = adj.recipe.lines.filter(\.isAddition).reduce(0) { $0 + $1.amount } / adj.recipe.baseTotal
        #expect(abs(addBefore - addAfter) < 1e-12)
        // CaO reaches the target, the flux sum stays 1, and the other fluxes keep their ratios.
        #expect(adj.isExact, "\(adj.residual)")
        #expect(abs((adj.after.umf[.CaO] ?? 0) - target) < 1e-6)
        let fluxSum = adj.after.umf.filter { $0.key.info?.role == .flux }.values.reduce(0, +)
        #expect(abs(fluxSum - 1) < 1e-9)
        let ratioBefore = (before.umf[.Na2O] ?? 0) / (before.umf[.MgO] ?? 1)
        let ratioAfter = (adj.after.umf[.Na2O] ?? 0) / (adj.after.umf[.MgO] ?? 1)
        #expect(abs(ratioBefore - ratioAfter) < 1e-5)
    }

    @Test("a target the materials cannot reach gives the residual, and the recipe's real chemistry")
    func infeasibleGivesResidual() throws {
        // Whiting and Wollastonite only: SiO2 comes only with CaO, 1 mole each in Wollastonite, so the SiO2
        // UMF is at most 1 (all Wollastonite). A target of 1.5 cannot be reached by any recipe of these materials.
        // (L8: the old case, SiO2 0.5 from Whiting, Kaolin and Potash feldspar, is reachable with about
        // 61 Whiting and 39 Kaolin. Since the L7 C3 fix the nudged oxide reaches such a target.)
        let r = recipe("Calcium only", [("whiting", 20), ("wollastonite", 30)])
        let adj = try Reformulate.nudge(r, oxide: .SiO2, toUMF: 1.5, library: lib)
        #expect(!adj.isExact)
        let miss = try #require(adj.residual[.SiO2])
        #expect(miss < -0.01)
        #expect(abs((adj.after.umf[.SiO2] ?? 0) - 1.5 - miss) < 1e-12)
        // The closest it can get: all Wollastonite, SiO2 UMF 1 (to the 2-decimal analysis rounding).
        #expect(abs((adj.after.umf[.SiO2] ?? 0) - 1) < 0.01)
        #expect(adj.recipe.lines.allSatisfy { $0.amount >= 0 })
        // `after` is the chemistry of the returned recipe, not of a wished-for one.
        let real = try chem(adj.recipe)
        for o in Oxide.allCases { #expect(abs((real.umf[o] ?? 0) - (adj.after.umf[o] ?? 0)) < 1e-12) }
    }

    @Test("targets that are not a UMF value, and recipes without flux, throw")
    func errors() {
        let r = fourPart()
        #expect(throws: ReformulateError.infeasible) { try Reformulate.nudge(r, oxide: .SiO2, toUMF: -0.1, library: lib) }
        #expect(throws: ReformulateError.infeasible) { try Reformulate.nudge(r, oxide: .SiO2, toUMF: .nan, library: lib) }
        #expect(throws: ReformulateError.infeasible) { try Reformulate.nudge(r, oxide: .CaO, toUMF: 1.5, library: lib) }
        let noFlux = recipe("No flux", [("silica", 50), ("kaolin", 50)])
        #expect(throws: ReformulateError.noFlux) { try Reformulate.nudge(noFlux, oxide: .SiO2, toUMF: 3, library: lib) }
    }

    @Test("suggested sources put single-oxide materials first")
    func suggestions() {
        #expect(Reformulate.suggestedSources(for: .SiO2, library: lib).first?.id == "silica")
        #expect(Reformulate.suggestedSources(for: .B2O3, library: lib).first?.id == "boric-acid")
        #expect(Reformulate.suggestedSources(for: .Al2O3, library: lib).first?.id == "alumina")
        let ca = Reformulate.suggestedSources(for: .CaO, library: lib).map(\.id)
        #expect(ca.contains("whiting"))
        #expect(ca.count == 4)
    }
}

@Suite("Replace Material")
struct ReplaceMaterialTests {
    @Test("Kaolin to Calcined kaolin: no residual, the amount is about the old amount x (1 - LOI)")
    func kaolinToCalcined() throws {
        let r = fourPart()
        let adj = try Reformulate.replace(r, materialID: "kaolin", with: "calcined-kaolin", library: lib)
        #expect(adj.isExact, "\(adj.residual)")
        let kaolin = try #require(lib.material(id: "kaolin"))
        let expected = 20 * (1 - kaolin.loi / 100)
        // The bundled rows are rounded to 2 decimals, so the two Al2O3:SiO2 ratios differ by about 2e-4.
        // Silica takes up that difference; the calcined amount agrees with the LOI rule to 1 part in 1000.
        #expect(abs(total(adj.recipe, "calcined-kaolin") / expected - 1) < 1e-3)
        #expect(abs(total(adj.recipe, "whiting") - 20) < 1e-6)
        #expect(abs(total(adj.recipe, "potash-feldspar") - 30) < 1e-6)
        #expect(total(adj.recipe, "kaolin") == 0)
    }

    @Test("Whiting to Wollastonite: no residual, Silica falls")
    func whitingToWollastonite() throws {
        let r = fourPart()
        let adj = try Reformulate.replace(r, materialID: "whiting", with: "wollastonite", library: lib)
        #expect(adj.isExact, "\(adj.residual)")
        #expect(total(adj.recipe, "silica") < 30 - 5)
        #expect(total(adj.recipe, "wollastonite") > 20)
        #expect(abs(total(adj.recipe, "kaolin") - 20) < 1e-6)
    }

    @Test("Potash to Soda feldspar with no other K2O source: the K2O residual is the whole original K2O")
    func potashToSoda() throws {
        let r = fourPart()
        let before = try chem(r)
        let adj = try Reformulate.replace(r, materialID: "potash-feldspar", with: "soda-feldspar", library: lib)
        #expect(!adj.isExact)
        let k = try #require(adj.residual[.K2O])
        #expect(abs(k + (before.umf[.K2O] ?? 0)) < 1e-9)
        #expect((adj.after.umf[.K2O] ?? 0) == 0)
        let fluxSum = adj.after.umf.filter { $0.key.info?.role == .flux }.values.reduce(0, +)
        #expect(abs(fluxSum - 1) < 1e-9)
    }

    @Test("the original recipe is not changed, and the new line keeps the old line's place and id")
    func originalUnchanged() throws {
        let r = recipe("With addition", [("silica", 30), ("whiting", 20), ("kaolin", 20), ("potash-feldspar", 30)],
                       additions: [("red-iron-oxide", 2)])
        let copy = r
        let adj = try Reformulate.replace(r, materialID: "whiting", with: "wollastonite", library: lib)
        #expect(r == copy)
        #expect(adj.recipe.lines[1].id == r.lines[1].id)
        #expect(adj.recipe.lines[1].materialID == "wollastonite")
        #expect(adj.recipe.lines.count == r.lines.count)
        #expect(adj.recipe.lines.last == r.lines.last) // the addition is not changed
    }

    @Test("replacing a material with itself changes nothing")
    func sameMaterial() throws {
        let r = fourPart()
        let adj = try Reformulate.replace(r, materialID: "kaolin", with: "kaolin", library: lib)
        #expect(adj.recipe == r)
        #expect(adj.isExact)
    }

    @Test("the new material already in the recipe takes the old one's share")
    func newAlreadyPresent() throws {
        let r = recipe("Two clays", [("silica", 30), ("whiting", 20), ("kaolin", 10), ("calcined-kaolin", 10),
                                    ("potash-feldspar", 30)])
        let adj = try Reformulate.replace(r, materialID: "kaolin", with: "calcined-kaolin", library: lib)
        #expect(adj.isExact, "\(adj.residual)")
        #expect(!adj.recipe.lines.contains { $0.materialID == "kaolin" })
        #expect(adj.recipe.lines.filter { $0.materialID == "calcined-kaolin" }.count == 1)
        #expect(total(adj.recipe, "calcined-kaolin") > 10)
    }

    @Test("errors: material not in the base, unknown replacement")
    func errors() {
        let r = fourPart()
        #expect(throws: ReformulateError.notInRecipe("talc")) {
            try Reformulate.replace(r, materialID: "talc", with: "silica", library: lib)
        }
        #expect(throws: ReformulateError.unknownMaterial("no-such-material")) {
            try Reformulate.replace(r, materialID: "kaolin", with: "no-such-material", library: lib)
        }
    }
}

@Suite("Sample recipe for Oxide Nudge and Replace Material")
struct ReformulateSampleTests {
    private func sample() throws -> Recipe {
        try #require(SampleBook.make().recipes.first)
    }

    @Test("the first sample recipe says where to find both tools")
    func notesNameTheTools() throws {
        let r = try sample()
        #expect(r.notes.contains("Recipe > Oxide Nudge"))
        #expect(r.notes.contains("Recipe > Replace Material"))
        #expect(r.lines.contains { $0.materialID == "potash-feldspar" && !$0.isAddition })
    }

    @Test("the steps the notes suggest work on it")
    func suggestedStepsWork() throws {
        let r = try sample()
        let before = try chem(r)
        let nudge = try Reformulate.nudge(r, oxide: .SiO2, toUMF: (before.umf[.SiO2] ?? 0) + 0.05, library: lib)
        #expect(nudge.isExact, "\(nudge.residual)")
        let swap = try Reformulate.replace(r, materialID: "potash-feldspar", with: "soda-feldspar", library: lib)
        // No other line supplies K2O, so K2O is reported as missing, and the swap still gives a recipe.
        #expect(swap.residual[.K2O] != nil)
        #expect(swap.recipe.lines.allSatisfy { $0.amount >= 0 })
    }

    @Test("run 1104 L10 change 2: the sample note names all three tools and the clean first step")
    func guideNoteNamesThreeTools() {
        let note = SampleBook.guideNote(appName: "Frit")
        for phrase in ["Recipe > Replace Material", "Recipe > Oxide Nudge", "Tests > Find Test",
                       "replace Whiting with Wollastonite", "File > New", "Help > Open Sample Book"] {
            #expect(note.contains(phrase), "\(phrase)")
        }
        // About 12 lines in the sidebar (estimate: 31 characters a line, lineLimit 16 in BookWindow).
        #expect(note.count <= 360, "\(note.count) characters")
    }

    @Test("run 1104 L10 change 2: every way to open the sample shows the note")
    func everySampleOpenShowsTheNote() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/GlazeApp")
        let doc = try String(contentsOf: root.appendingPathComponent("GlazeDocument.swift"), encoding: .utf8)
        #expect(doc.contains("GlazeDocument(book: SampleBook.make(), isSample: true)"))
        #expect(!doc.contains("isFirstLaunchSample"))
        let window = try String(contentsOf: root.appendingPathComponent("BookWindow.swift"), encoding: .utf8)
        #expect(window.contains("if document.isSample && !sampleNoteClosed"))
        #expect(window.contains("Text(SampleBook.guideNote(appName: AppInfo.name))"))
        // First launch and the empty book's button (BookWindow), Help > Open Sample Book (GlazeMainApp).
        #expect(window.components(separatedBy: "newDocument(GlazeDocument.sample())").count - 1 == 2)
        let main = try String(contentsOf: root.appendingPathComponent("GlazeMainApp.swift"), encoding: .utf8)
        #expect(main.contains("newDocument(GlazeDocument.sample())"))
        // No other path makes a sample document without the note.
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" && file.lastPathComponent != "GlazeDocument.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("SampleBook.make()"), "\(file.lastPathComponent) opens the sample without the note")
        }
    }

    /// Run 1104 L10 change 3: the clean first step for the review notes. In the real app (L2, macOS 26.6.2) the
    /// sheet showed "Every oxide reaches its original value", Whiting 6 -> 0, Wollastonite 5 -> 11.96,
    /// Silica 21 -> 17.4 and a base total of 97.36. The test prints the unrounded numbers (TIDEWATER-W2W lines).
    @Test("run 1104: Tidewater Feldspar Gloss, Whiting to Wollastonite: every oxide matches, Silica falls")
    func tidewaterWhitingToWollastonite() throws {
        let r = try #require(SampleBook.make().recipes.first { $0.name == "Tidewater Feldspar Gloss" })
        let adj = try Reformulate.replace(r, materialID: "whiting", with: "wollastonite", library: lib)
        #expect(adj.isExact, "\(adj.residual)")
        #expect(adj.residual.isEmpty)
        #expect(adj.unsupplied.isEmpty)
        let now = amounts(r), new = amounts(adj.recipe)
        for id in ["potash-feldspar", "frit-generic-calcium-borate", "whiting", "wollastonite", "talc", "kaolin", "silica"] {
            print("TIDEWATER-W2W material \(id) now=\(now[id] ?? 0) new=\(new[id] ?? 0)")
        }
        print("TIDEWATER-W2W baseTotal now=\(r.baseTotal) new=\(adj.recipe.baseTotal)")
        for o in Oxide.allCases where (adj.before.umf[o] ?? 0) > 0 || (adj.after.umf[o] ?? 0) > 0 {
            print("TIDEWATER-W2W umf \(o.formula) before=\(adj.before.umf[o] ?? 0) after=\(adj.after.umf[o] ?? 0)")
            #expect(abs((adj.after.umf[o] ?? 0) - (adj.before.umf[o] ?? 0)) < 0.0005, "\(o.formula)")
        }
        // The numbers the sheet shows (2 decimals), as L2 read them in the real window.
        #expect(new["whiting"] == nil || (new["whiting"] ?? 0) < 0.005)
        #expect(abs((new["wollastonite"] ?? 0) - 11.96) < 0.005)
        #expect(abs((new["silica"] ?? 0) - 17.4) < 0.005)
        #expect(abs(adj.recipe.baseTotal - 97.36) < 0.005)
        for id in ["potash-feldspar", "frit-generic-calcium-borate", "talc", "kaolin"] {
            #expect(abs((new[id] ?? 0) - (now[id] ?? 0)) < 0.005, "\(id)")
        }
    }
}

/// Fixes for the L7 review (run 2026-11-01, L7/RESULT.md section 5). Each test names its finding.
@Suite("Reformulate review fixes (L7)")
struct ReformulateReviewFixTests {
    private func sample() throws -> Recipe {
        try #require(SampleBook.make().recipes.first { $0.name == "Tidewater Feldspar Gloss" })
    }

    @Test("C1 S1: on the sample, SiO2 +0.05 keeps Wollastonite and mainly raises Silica")
    func nudgeStaysNearCurrentAmounts() throws {
        let r = try sample()
        let before = try chem(r)
        let target = (before.umf[.SiO2] ?? 0) + Reformulate.step
        let adj = try Reformulate.nudge(r, oxide: .SiO2, toUMF: target, library: lib)
        #expect(adj.isExact, "\(adj.residual)")
        #expect(total(adj.recipe, "wollastonite") > 4)
        let silicaRise = total(adj.recipe, "silica") - total(r, "silica")
        #expect(silicaRise > 0.3)
        for id in ["potash-feldspar", "frit-generic-calcium-borate", "whiting", "wollastonite", "talc", "kaolin"] {
            let change = abs(total(adj.recipe, id) - total(r, id))
            #expect(change < silicaRise / 2, "\(id) changed by \(change)")
        }
    }

    @Test("C1: when the solution is not unique, the amounts nearest the current ones win")
    func dependentMaterialsStayNear() throws {
        // Wollastonite = Whiting + Silica in oxide space. Nudging Al2O3 must not swap one for the other.
        let r = recipe("Dependent", [("whiting", 10), ("wollastonite", 10), ("silica", 30), ("kaolin", 20),
                                     ("potash-feldspar", 30)])
        let before = try chem(r)
        let adj = try Reformulate.nudge(r, oxide: .Al2O3, toUMF: (before.umf[.Al2O3] ?? 0) + Reformulate.step, library: lib)
        #expect(adj.isExact, "\(adj.residual)")
        #expect(abs(total(adj.recipe, "wollastonite") - 10) < 1.5)
        #expect(abs(total(adj.recipe, "whiting") - 10) < 1.5)
    }

    @Test("C3 S2: on the sample, CaO +0.05 reaches its target; the other oxides take the miss")
    func nudgedOxideReachesTarget() throws {
        let r = try sample()
        let before = try chem(r)
        let target = (before.umf[.CaO] ?? 0) + Reformulate.step
        let adj = try Reformulate.nudge(r, oxide: .CaO, toUMF: target, library: lib)
        #expect(abs((adj.after.umf[.CaO] ?? 0) - target) < 1e-6)
        #expect(adj.residual[.CaO] == nil)
        let fluxSum = adj.after.umf.filter { $0.key.info?.role == .flux }.values.reduce(0, +)
        #expect(abs(fluxSum - 1) < 1e-9)
        // Na2O comes only with B2O3 (in the frit), so the other oxides cannot all be exact.
        #expect(!adj.isExact)
        #expect(adj.recipe.lines.allSatisfy { $0.amount >= 0 })
    }

    @Test("C2: sample, Potash to Soda feldspar: about the same flux, other fluxes unchanged, K2O reported")
    func replaceLostFluxKeepsOthers() throws {
        let r = try sample()
        let before = try chem(r)
        let adj = try Reformulate.replace(r, materialID: "potash-feldspar", with: "soda-feldspar", library: lib)
        let soda = total(adj.recipe, "soda-feldspar")
        #expect(soda >= 20 && soda <= 32, "Soda feldspar \(soda)")
        for o in [Oxide.CaO, .MgO, .Li2O, .SrO, .BaO, .ZnO] {
            #expect(abs((adj.after.umf[o] ?? 0) - (before.umf[o] ?? 0)) <= 0.02, "\(o)")
        }
        for id in ["frit-generic-calcium-borate", "whiting", "wollastonite", "talc", "kaolin", "silica"] {
            #expect(abs(total(adj.recipe, id) - total(r, id)) < 0.5, "\(id)")
        }
        let k = try #require(adj.residual[.K2O])
        #expect(abs(k + (before.umf[.K2O] ?? 0)) < 1e-9)
        #expect((adj.after.umf[.K2O] ?? 0) == 0)
    }

    @Test("C4 S4: the noSource text is true when an addition holds the oxide")
    func noSourceTextWithAddition() throws {
        let r = recipe("Iron addition", [("silica", 30), ("whiting", 20), ("kaolin", 20), ("potash-feldspar", 30)],
                       additions: [("red-iron-oxide", 2)])
        do {
            _ = try Reformulate.nudge(r, oxide: .Fe2O3, toUMF: 0.05, library: lib)
            Issue.record("expected noSource")
        } catch {
            #expect(error as? ReformulateError == .noSource(.Fe2O3))
            let text = error.localizedDescription
            #expect(!text.contains("No material in this recipe"))
            #expect(text.contains("No base material"))
            #expect(text.contains("addition"))
        }
    }

    @Test("C5 S5: a sole flux gets a true message, not 'must be between 0 and 1'")
    func soleFluxMessage() throws {
        let r = recipe("One flux", [("whiting", 20), ("kaolin", 30), ("silica", 50)])
        do {
            _ = try Reformulate.nudge(r, oxide: .CaO, toUMF: 0.95, library: lib)
            Issue.record("expected an error")
        } catch {
            let text = error.localizedDescription
            #expect(!text.contains("between 0 and 1"))
            #expect(text.contains("only flux"))
        }
    }

    @Test("S6: the Tidewater notes say it is an untested starting point")
    func tidewaterNotesUntested() throws {
        #expect(try sample().notes.contains("Untested starting point."))
    }

    @Test("C6: least squares with a dependent column keeps the later independent column")
    func leastSquaresDependentColumn() {
        // L7 hand case: columns [1,0,0], [2,0,0], [0,1,0]. The third column must not be lost.
        let s = Solver.leastSquares(columns: [[1, 0, 0], [2, 0, 0], [0, 1, 0]], rhs: [3, 5, 0])
        #expect(abs(s[2] - 5) < 1e-12)
        #expect(abs(s[0] + 2 * s[1] - 3) < 1e-12)
    }
}
