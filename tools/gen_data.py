#!/usr/bin/env python3
"""Generate Sources/GlazeCore/Resources/oxides.json, materials.json and README-data.md.

Run from the repository root:  python3 tools/gen_data.py

Every number in the JSON files comes from this script:
  * oxide molar masses  = sum of IUPAC standard atomic weights
  * material analysis   = fired-oxide weight percent per 100 g of raw material,
                          computed from the chemical formula of the material
  * LOI                 = (raw formula mass - fired oxide mass) / raw formula mass * 100
No third-party material database is used.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Sources", "GlazeCore", "Resources")

# IUPAC/CIAAW abridged standard atomic weights (2021 table).
# Source: T. Prohaska et al., "Standard atomic weights of the elements 2021
# (IUPAC Technical Report)", Pure Appl. Chem. 94 (2022) 573-600; abridged values
# from https://iupac.qmul.ac.uk/AtWt/ . Interval elements (H, Li, B, C, O, Mg, Si)
# use the conventional values.
ATOMIC_WEIGHT = {
    "H": 1.008, "Li": 6.94, "B": 10.81, "C": 12.011, "N": 14.007, "O": 15.999,
    "F": 18.998, "Na": 22.990, "Mg": 24.305, "Al": 26.982, "Si": 28.085,
    "P": 30.974, "S": 32.06, "K": 39.098, "Ca": 40.078, "Ti": 47.867,
    "Cr": 51.996, "Mn": 54.938, "Fe": 55.845, "Co": 58.933, "Ni": 58.693,
    "Cu": 63.546, "Zn": 65.38, "Sr": 87.62, "Zr": 91.222, "Sn": 118.71,
    "Ba": 137.33, "Pb": 207.2,
}

# Oxide -> (cation, cations per formula unit, oxygens per formula unit, role, Appen coefficient)
# Roles follow the Seger / unity-formula column convention used in ceramic practice:
#   flux        = R2O and RO columns (alkali and alkaline-earth oxides, ZnO, PbO)
#   stabilizer  = R2O3 column (Al2O3, and B2O3 by convention - see README-data.md)
#   glassFormer = RO2 / R2O5 column (SiO2, TiO2, ZrO2, SnO2, P2O5)
#   colorant    = transition-metal oxides (not counted in the flux unity)
# Appen coefficients: partial linear expansion coefficients, units 1e-7 per K per
# mole percent, A. A. Appen, "Khimiya stekla" (Chemistry of Glass), 2nd ed.,
# Leningrad: Khimiya, 1974, as reproduced by A. Fluegel (glassproperties.com, 2007,
# Table I), checked by lane G7 on 22 Oct 2026. None = not given as a constant in that
# set (composition-dependent: B2O3, PbO, TiO2; no value: Cr2O3). The composition-dependent
# terms (and the SiO2 > 67 mol % and K2O rules) are in Sources/GlazeCore/Appen.swift.
OXIDES = [
    ("Li2O",  "Li", 2, 1, "flux", 270),
    ("Na2O",  "Na", 2, 1, "flux", 395),
    ("K2O",   "K",  2, 1, "flux", 465),
    ("MgO",   "Mg", 1, 1, "flux", 60),
    ("CaO",   "Ca", 1, 1, "flux", 130),
    ("SrO",   "Sr", 1, 1, "flux", 160),
    ("BaO",   "Ba", 1, 1, "flux", 200),
    ("ZnO",   "Zn", 1, 1, "flux", 50),
    ("PbO",   "Pb", 1, 1, "flux", None),
    ("B2O3",  "B",  2, 3, "stabilizer", None),
    ("Al2O3", "Al", 2, 3, "stabilizer", -30),
    ("SiO2",  "Si", 1, 2, "glassFormer", 38),
    ("TiO2",  "Ti", 1, 2, "glassFormer", None),
    ("ZrO2",  "Zr", 1, 2, "glassFormer", -60),
    ("Fe2O3", "Fe", 2, 3, "colorant", 55),
    ("MnO",   "Mn", 1, 1, "colorant", 105),
    ("CoO",   "Co", 1, 1, "colorant", 50),
    ("CuO",   "Cu", 1, 1, "colorant", 30),
    ("Cr2O3", "Cr", 2, 3, "colorant", None),
    ("NiO",   "Ni", 1, 1, "colorant", 50),
    ("SnO2",  "Sn", 1, 2, "glassFormer", -45),
    ("P2O5",  "P",  2, 5, "glassFormer", 140),
]
CATION_TO_OXIDE = {c: (ox, n) for (ox, c, n, _o, _r, _a) in OXIDES}
VOLATILE = {"H", "C", "O", "N", "S", "F"}


def molar_mass(ox):
    for (o, c, n, nO, _r, _a) in OXIDES:
        if o == ox:
            return n * ATOMIC_WEIGHT[c] + nO * ATOMIC_WEIGHT["O"]
    raise KeyError(ox)


TOKEN = re.compile(r"([A-Z][a-z]?|\(|\)|\d+(?:\.\d+)?)")


def parse_part(s):
    """Parse a formula without hydrate dots, e.g. 'Cu2(OH)2CO3' -> {Cu:2, O:5, H:2, C:1}."""
    tokens = TOKEN.findall(s)
    if "".join(tokens) != s:
        raise ValueError("cannot parse formula part %r" % s)
    stack = [{}]
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "(":
            stack.append({})
            i += 1
            continue
        mult = 1.0
        if i + 1 < len(tokens) and re.fullmatch(r"\d+(?:\.\d+)?", tokens[i + 1]):
            mult = float(tokens[i + 1])
            step = 2
        else:
            step = 1
        if t == ")":
            group = stack.pop()
            for el, k in group.items():
                stack[-1][el] = stack[-1].get(el, 0) + k * mult
        elif re.fullmatch(r"[A-Z][a-z]?", t):
            if t not in ATOMIC_WEIGHT:
                raise ValueError("unknown element %s" % t)
            stack[-1][t] = stack[-1].get(t, 0) + mult
        else:
            raise ValueError("unexpected token %r in %r" % (t, s))
        i += step
    assert len(stack) == 1, s
    return stack[0]


def parse_formula(f):
    """'Ca2B6O11·5H2O' -> element counts. Parts are joined by '·' or '.'."""
    total = {}
    for part in re.split(r"[·]", f):
        m = re.fullmatch(r"(\d+(?:\.\d+)?)?(.+)", part)
        k = float(m.group(1)) if m.group(1) else 1.0
        for el, n in parse_part(m.group(2)).items():
            total[el] = total.get(el, 0) + n * k
    return total


def from_formula(formula):
    """Return (analysis{oxide: wt% of raw}, loi%, raw_mass, oxide_moles, steps_text)."""
    els = parse_formula(formula)
    raw = sum(ATOMIC_WEIGHT[e] * n for e, n in els.items())
    moles = {}
    for e, n in els.items():
        if e in VOLATILE:
            continue
        if e not in CATION_TO_OXIDE:
            raise ValueError("no oxide for element %s in %s" % (e, formula))
        ox, per = CATION_TO_OXIDE[e]
        moles[ox] = moles.get(ox, 0) + n / per
    fired = sum(molar_mass(o) * m for o, m in moles.items())
    loi = (raw - fired) / raw * 100.0
    if loi < -1e-9:
        raise ValueError("negative LOI for %s" % formula)
    analysis = {o: molar_mass(o) * m / raw * 100.0 for o, m in moles.items()}
    return analysis, loi, raw, moles


def from_oxide_formula(oxmoles):
    """Frit defined directly by oxide moles; nothing volatile, LOI 0."""
    fired = sum(molar_mass(o) * m for o, m in oxmoles.items())
    analysis = {o: molar_mass(o) * m / fired * 100.0 for o, m in oxmoles.items()}
    return analysis, 0.0, fired, dict(oxmoles)


THEO = "Theoretical: computed from the chemical formula {f} with IUPAC 2021 atomic weights. Real material lots differ."
FRIT = ("Generic theoretical frit defined in this app by its oxide formula {f}; "
        "computed with IUPAC 2021 atomic weights. Not a commercial product.")

# (id, name, formula)
MATERIALS = [
    ("silica", "Silica (quartz, flint)", "SiO2"),
    ("whiting", "Whiting (calcium carbonate)", "CaCO3"),
    ("wollastonite", "Wollastonite", "CaSiO3"),
    ("talc", "Talc", "Mg3Si4O10(OH)2"),
    ("dolomite", "Dolomite", "CaMg(CO3)2"),
    ("kaolin", "Kaolin (kaolinite)", "Al2Si2O5(OH)4"),
    ("calcined-kaolin", "Calcined kaolin (metakaolin)", "Al2Si2O7"),
    ("pyrophyllite", "Pyrophyllite", "Al2Si4O10(OH)2"),
    ("kyanite", "Kyanite", "Al2SiO5"),
    ("potash-feldspar", "Potash feldspar (orthoclase)", "KAlSi3O8"),
    ("soda-feldspar", "Soda feldspar (albite)", "NaAlSi3O8"),
    ("calcium-feldspar", "Calcium feldspar (anorthite)", "CaAl2Si2O8"),
    ("nepheline", "Nepheline (mineral; not nepheline syenite)", "NaAlSiO4"),
    ("spodumene", "Spodumene", "LiAlSi2O6"),
    ("petalite", "Petalite", "LiAlSi4O10"),
    ("diopside", "Diopside", "CaMgSi2O6"),
    ("lithium-carbonate", "Lithium carbonate", "Li2CO3"),
    ("soda-ash", "Soda ash (sodium carbonate)", "Na2CO3"),
    ("pearl-ash", "Pearl ash (potassium carbonate)", "K2CO3"),
    ("magnesium-carbonate", "Magnesium carbonate (magnesite)", "MgCO3"),
    ("magnesium-oxide", "Magnesium oxide", "MgO"),
    ("strontium-carbonate", "Strontium carbonate", "SrCO3"),
    ("barium-carbonate", "Barium carbonate", "BaCO3"),
    ("zinc-oxide", "Zinc oxide", "ZnO"),
    ("alumina", "Alumina (calcined)", "Al2O3"),
    ("alumina-hydrate", "Alumina hydrate", "Al(OH)3"),
    ("boric-acid", "Boric acid", "H3BO3"),
    ("borax", "Borax (decahydrate)", "Na2B4O7·10H2O"),
    ("colemanite", "Colemanite (mineral)", "Ca2B6O11·5H2O"),
    ("ulexite", "Ulexite (mineral)", "NaCaB5O9·8H2O"),
    ("bone-ash", "Bone ash (tricalcium phosphate)", "Ca3(PO4)2"),
    ("titanium-dioxide", "Titanium dioxide", "TiO2"),
    ("tin-oxide", "Tin oxide", "SnO2"),
    ("zircon", "Zircon (zirconium silicate)", "ZrSiO4"),
    ("zirconium-oxide", "Zirconium oxide", "ZrO2"),
    ("red-iron-oxide", "Red iron oxide", "Fe2O3"),
    ("yellow-iron-oxide", "Yellow iron oxide (goethite)", "FeO(OH)"),
    ("cobalt-carbonate", "Cobalt carbonate", "CoCO3"),
    ("cobalt-oxide", "Cobalt oxide, black", "Co3O4"),
    ("copper-carbonate", "Copper carbonate (basic)", "Cu2(OH)2CO3"),
    ("copper-oxide", "Copper oxide, black", "CuO"),
    ("chrome-oxide", "Chrome oxide", "Cr2O3"),
    ("manganese-dioxide", "Manganese dioxide", "MnO2"),
    ("manganese-carbonate", "Manganese carbonate", "MnCO3"),
    ("nickel-oxide", "Nickel oxide, green", "NiO"),
]

# Generic frits: (id, name, oxide moles)
FRITS = [
    ("frit-generic-calcium-borate", "Generic calcium borate frit (theoretical)",
     {"CaO": 0.7, "Na2O": 0.3, "B2O3": 1.0, "SiO2": 2.0}),
    ("frit-generic-soda-borosilicate", "Generic soda borosilicate frit (theoretical)",
     {"Na2O": 0.6, "CaO": 0.4, "B2O3": 0.6, "Al2O3": 0.3, "SiO2": 3.0}),
]

ORDER = [o[0] for o in OXIDES]


def oxide_formula_text(m):
    return " · ".join("%g %s" % (v, k) for k, v in sorted(m.items(), key=lambda kv: ORDER.index(kv[0])))


def main():
    oxides = []
    for (ox, c, n, nO, role, appen) in OXIDES:
        oxides.append({
            "oxide": ox,
            "molarMass": round(molar_mass(ox), 4),
            "role": role,
            "expansionCoefficient": appen,
        })
    materials = []
    details = []
    for (mid, name, f) in MATERIALS:
        a, loi, raw, moles = from_formula(f)
        materials.append({
            "id": mid, "name": name, "formula": f,
            "analysis": {k: round(v, 4) for k, v in sorted(a.items(), key=lambda kv: ORDER.index(kv[0]))},
            "loi": round(loi, 4),
            "source": THEO.format(f=f),
        })
        details.append((mid, f, raw, moles, a, loi))
    for (mid, name, m) in FRITS:
        a, loi, raw, moles = from_oxide_formula(m)
        ft = oxide_formula_text(m)
        materials.append({
            "id": mid, "name": name, "formula": ft,
            "analysis": {k: round(v, 4) for k, v in sorted(a.items(), key=lambda kv: ORDER.index(kv[0]))},
            "loi": 0.0,
            "source": FRIT.format(f=ft),
        })
        details.append((mid, ft, raw, moles, a, loi))

    ids = [m["id"] for m in materials]
    assert len(ids) == len(set(ids)), "duplicate ids"
    for m in materials:
        s = sum(m["analysis"].values()) + m["loi"]
        assert abs(s - 100) < 0.01, (m["id"], s)

    with open(os.path.join(RES, "oxides.json"), "w") as fh:
        json.dump(oxides, fh, indent=2)
        fh.write("\n")
    with open(os.path.join(RES, "materials.json"), "w") as fh:
        json.dump(materials, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    write_readme(oxides, details)
    print("wrote %d oxides, %d materials" % (len(oxides), len(materials)))


def write_readme(oxides, details):
    L = []
    w = L.append
    w("# GlazeCore bundled data")
    w("")
    w("Generated by `tools/gen_data.py` (do not edit the JSON by hand; edit the script and run it again).")
    w("This file shows the arithmetic and the sources for `oxides.json`, `materials.json`,")
    w("the reference limit sets in `Limits.swift` and the Stull approximation in `Stull.swift`.")
    w("")
    w("## 1. Atomic weights")
    w("")
    w("IUPAC/CIAAW standard atomic weights 2021, abridged/conventional values:")
    w("T. Prohaska et al., *Standard atomic weights of the elements 2021 (IUPAC Technical Report)*,")
    w("Pure Appl. Chem. 94 (2022) 573-600. Table at https://iupac.qmul.ac.uk/AtWt/ .")
    w("")
    w("| Element | Atomic weight |")
    w("|---|---|")
    for e in sorted(ATOMIC_WEIGHT):
        w("| %s | %s |" % (e, ATOMIC_WEIGHT[e]))
    w("")
    w("## 2. Oxide molar masses (g/mol)")
    w("")
    w("| Oxide | Arithmetic | Molar mass | Role | Appen coefficient |")
    w("|---|---|---|---|---|")
    for (ox, c, n, nO, role, appen) in OXIDES:
        ar = "%d x %s + %d x %s" % (n, ATOMIC_WEIGHT[c], nO, ATOMIC_WEIGHT["O"])
        w("| %s | %s | %.4f | %s | %s |" % (ox, ar, molar_mass(ox), role,
                                             "nil" if appen is None else appen))
    w("")
    w("### Roles")
    w("")
    w("Roles follow the column convention of the Seger / unity molecular formula (UMF):")
    w("- **flux** (R2O and RO): Li2O, Na2O, K2O, MgO, CaO, SrO, BaO, ZnO, PbO. The flux sum is set to 1.0 in the UMF.")
    w("- **stabilizer** (R2O3): Al2O3 and B2O3.")
    w("- **glassFormer** (RO2, R2O5): SiO2, TiO2, ZrO2, SnO2, P2O5.")
    w("- **colorant**: Fe2O3, MnO, CoO, CuO, Cr2O3, NiO. Colorants are reported in the UMF but are")
    w("  **not** counted in the flux unity, so a colorant addition does not change the flux ratios.")
    w("")
    w("**B2O3 choice.** Chemically B2O3 is a glass former. In glaze practice it is written in the R2O3")
    w("column next to Al2O3 (it is amphoteric in the melt and it is usually compared with Al2O3 in")
    w("limit tables). GlazeCore uses role `stabilizer` for B2O3. The role only controls the flux unity:")
    w("B2O3 is never counted as a flux, so this choice does not change any UMF number.")
    w("")
    w("### Expansion coefficients")
    w("")
    w("Source: A. A. Appen, *Khimiya stekla* (Chemistry of Glass), 2nd ed., Leningrad: Khimiya, 1974")
    w("(the additive partial coefficients for linear thermal expansion, units 1e-7 per K per mole percent).")
    w("The constants were checked on 22 Oct 2026 against two public reproductions of Appen's table")
    w("(see section 6): all 15 constants that were already stored match. Fe2O3 (5.5), SnO2 (-4.5) and P2O5 (14.0)")
    w("were added from the same table (stored here times 10).")
    w("")
    w("The table above holds the constants. Appen's composition-dependent terms are computed in")
    w("`Sources/GlazeCore/Appen.swift` (W6 F3, 26 Oct 2026) from the footnotes of the Appen column at")
    w("https://www.glassproperties.com/expansion/Old-Thermal-Expansion-Models.htm (A. Fluegel, citing Appen 1974).")
    w("Values times 10 (1e-7 per K); brackets are mole percent of the glass:")
    w("")
    w("- **SiO2** (footnote a): 38 when [SiO2] < 67, otherwise 105 - [SiO2] (the table value 38 is the low-silica one).")
    w("- **K2O** (footnote d): 465 when [Na2O] > 1, otherwise 420.")
    w("- **B2O3** (footnote c): F = ([Na2O] + [K2O] + [BaO] + 0.7 ([CaO] + [SrO] + [PbO]) + 0.3 ([Li2O] + [MgO] + [ZnO])")
    w("  - [Al2O3]) / [B2O3]; coefficient -12.5 F for F <= 4, otherwise -50. The published range is -50 to 0, so")
    w("  F < 0 is outside the method and B2O3 is then not counted. (CdO is in Appen's F; GlazeCore has no CdO.)")
    w("- **PbO** (footnote e): 130 when [Li2O] + [Na2O] + [K2O] < 3, otherwise 115 + 5 x that sum. The published range")
    w("  is 130 to 190, so a sum above 15 is outside the method and PbO is then not counted.")
    w("- **TiO2** (footnote f): 105 - 1.5 [SiO2] for 50 <= [SiO2] <= 80. Outside that range TiO2 is not counted.")
    w("- **Cr2O3**: Appen's table has no value. Not counted.")
    w("- The Fe2O3 and MnO constants are valid for the normally occurring oxidation states only (footnote g),")
    w("  so a reduction firing can differ.")
    w("")
    w("**Partial estimates.** When an oxide in the recipe is not counted, the estimate is partial:")
    w("`Chemistry.expansionNotCounted` lists the oxides, the calculator adds a warning that names each one and")
    w("the reason, and the chemistry pane labels the value \"partial\" and names the oxides. A partial sum is never")
    w("shown as a complete estimate.")
    w("")
    w("**Convention (GlazeCalculator).** expansion = sum over oxides of (mole fraction x coefficient),")
    w("where mole fraction = moles of the oxide / moles of all oxides in the calculation (colorants")
    w("included; additions included only when `includeAdditions` is true). The result is in units of")
    w("1e-7 per K (for example 65 means 6.5e-6 per K). It is an estimate for comparing glazes, not a")
    w("measured value.")
    w("")
    w("## 3. Materials")
    w("")
    w("All bundled materials are theoretical (computed from a chemical formula) or generic frits defined")
    w("in this app. No commercial material is bundled: I could not fetch a manufacturer data sheet with")
    w("clear reuse terms in this session (the 3M nepheline syenite sheet returned HTTP 403), so named")
    w("commercial materials (nepheline syenite, EPK, Custer feldspar, commercial frits) are left out.")
    w("Users add them as custom materials from their supplier's sheet. No Glazy or Digitalfire data is used.")
    w("")
    w("Method: parse the formula into element counts. Raw mass = sum(count x atomic weight).")
    w("Each non-volatile element becomes its oxide (Mn -> MnO, Fe -> Fe2O3, Co -> CoO, Cu -> CuO, ...).")
    w("H, C, N, S, F and the excess O leave as water, CO2 or O2. Analysis (wt% per 100 g raw material)")
    w("= oxide moles x oxide molar mass / raw mass x 100. LOI = (raw mass - fired mass) / raw mass x 100.")
    w("")
    w("### Worked examples")
    w("")
    for mid in ("whiting", "kaolin", "potash-feldspar", "manganese-dioxide"):
        for (i, f, raw, moles, a, loi) in details:
            if i != mid:
                continue
            els = parse_formula(f)
            terms = " + ".join("%g x %s" % (n, ATOMIC_WEIGHT[e]) for e, n in els.items())
            w("**%s** (%s): raw mass = %s = %.4f g/mol." % (mid, f, terms, raw))
            for o, m in moles.items():
                w("- %s: %g mol x %.4f g/mol = %.4f g -> %.4f / %.4f x 100 = %.4f %%" %
                  (o, m, molar_mass(o), m * molar_mass(o), m * molar_mass(o), raw, a[o]))
            w("- LOI = (%.4f - %.4f) / %.4f x 100 = %.4f %%" %
              (raw, raw - raw * loi / 100, raw, loi))
            w("")
    w("### Table")
    w("")
    w("| id | formula | raw g/mol | analysis (wt% of raw) | LOI % |")
    w("|---|---|---|---|---|")
    for (i, f, raw, moles, a, loi) in details:
        an = ", ".join("%s %.2f" % (k, v) for k, v in sorted(a.items(), key=lambda kv: ORDER.index(kv[0])))
        w("| %s | %s | %.3f | %s | %.2f |" % (i, f, raw, an, loi))
    w("")
    w("Notes: magnesium carbonate is the theoretical MgCO3; commercial \"light\" magnesium carbonate is a")
    w("basic hydrate with a higher LOI. Bone ash is theoretical tricalcium phosphate. Cobalt oxide black")
    w("(Co3O4) is reported as CoO with the oxygen loss in LOI.")
    w("")
    with open(os.path.join(ROOT, "tools", "README-sections-limits-stull.md")) as fh:
        L.append(fh.read().rstrip("\n"))
    with open(os.path.join(RES, "README-data.md"), "w") as fh:
        fh.write("\n".join(L) + "\n")


if __name__ == "__main__":
    sys.exit(main())
