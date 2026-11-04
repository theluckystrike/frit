## 4. Reference limit sets (`Limits.swift`)

Sections 4 to 6 are kept in `tools/README-sections-limits-stull.md`; `tools/gen_data.py` appends them here.

The bundled sets are **reference ranges** in UMF (flux sum 1.0) from two published tables. The app
uses them for comparison only. They are not a durability or safety rating, and the app labels do not
use the source authors' own words for that purpose.

Sources:
- **Hesselberth & Roy** (sets `hr-cone6`, `hr-cone10`): J. Hesselberth and R. Roy, "Making Stable Glazes
  for Functional Stoneware and Porcelain", *Ceramics Monthly*, September 2000. The values come from the Arbuckle handout below. The cone 6 KNaO reading was checked against the article text. The article gives one cone 6 column
  and one cone 10 column.
- **Val Cushing** (sets `cushing-c5-6-gloss`, `-satin`, `-matt`, `cushing-c9-10-gloss`, `-satin`, `-matt`):
  Val Cushing, *Cushing's Handbook* (limit tables for gloss, satin and matt glazes). I did not check the
  book itself; the numbers come from the reproduction below.
- Both tables as typed in L. Arbuckle (University of Florida), "Molecular Glaze Limit Ranges", handout,
  2012, https://www.lindaarbuckle.com/handouts/glaze-limits.pdf (text extracted with `pdftotext -layout`
  on 22 Oct 2026, lane G8). Digitalfire limits are not used (SPEC rule 6).

Rules used when the tables were typed into `Limits.swift`:
- **KNaO** ((K+Na)2O) is one `LimitRange` on K2O with `combinedWith: [.Na2O]`. `Limits.check` compares
  K2O + Na2O with the range and reports the result under both K2O and Na2O.
- "none" in the source (Hesselberth & Roy: Li2O, PbO, BaO, and ZnO at cone 10) means no range: the
  oxide is not checked. The article has no row for these oxides.
- **PbO** ranges in the Cushing tables are not bundled.
- Handout typos and how they were read: H&R cone 6 KNaO ".01-.03" is 0.1-0.3 (the article text gives
  0.1-0.3, and the cone 10 column has .1-.3); Cushing cone 5-6 satin Al2O3 "20 - .40" is 0.20-0.40;
  Cushing cone 5-6 matt KNaO "..05 - .30" is 0.05-0.30; Cushing cone 9-10 matt ZnO ".0 -50" is 0-0.50.
  Lane G10 checked these three readings against the second source below; all three agree.
- **Second source (G10, 22 Oct 2026):** B. Quinlan, "The Unity Molecular Formula Approach to Glaze
  Development", M.S. thesis in Ceramic Engineering, Alfred University, February 2002, Tables II-2 (cone 5-6)
  and II-3 (cone 9-10), pp. 7-8, citing V. M. Cushing, *Cushing's Handbook*, 3rd ed., Alfred, NY, 1994,
  pp. 47-51. Record: https://aura.alfred.edu/handle/10829/24507 (PDF text read with `pdftotext -layout`).
  All 60 Cushing cells (10 oxides x 6 columns, PbO not bundled) are the same as in the table below; there
  are no mismatches. Quinlan calls the middle column "Semi-Matte" (Arbuckle: "Satin") and gives PbO rows
  (cone 5-6: 0-0.60, 0-0.40, 0-0.20; cone 9-10: 0). The Glazy help page "Limit Formulas"
  (https://help.glazy.org/concepts/limits, read 22 Oct 2026) also shows the same values, but it names no
  source, so it is not counted as independent. The test `cushingMatchesSecondSource` holds the Quinlan table.

| Oxide | H&R cone 6 | H&R cone 10 | Cushing 5-6 gloss | 5-6 satin | 5-6 matt | Cushing 9-10 gloss | 9-10 satin | 9-10 matt |
|---|---|---|---|---|---|---|---|---|
| KNaO | 0.10-0.30 | 0.10-0.30 | 0.05-0.60 | 0.05-0.35 | 0.05-0.30 | 0.05-0.50 | 0.05-0.40 | 0.05-0.30 |
| Li2O | - | - | 0-0.50 | 0-0.15 | 0-0.10 | 0-0.40 | 0-0.20 | 0-0.10 |
| CaO | 0.20-0.60 | 0.30-0.70 | 0.05-0.60 | 0.05-0.70 | 0.05-0.80 | 0.05-0.80 | 0.05-0.80 | 0.05-0.90 |
| MgO | 0-0.30 | 0-0.40 | 0-0.10 | 0-0.35 | 0-0.45 | 0-0.15 | 0-0.50 | 0-0.60 |
| ZnO | 0-0.20 | - | 0-0.15 | 0-0.30 | 0-0.40 | 0-0.15 | 0-0.40 | 0-0.50 |
| BaO | - | - | 0-0.15 | 0-0.35 | 0-0.50 | 0-0.15 | 0-0.50 | 0-0.60 |
| SrO | 0-0.20 | 0-0.30 | 0-0.15 | 0-0.35 | 0-0.50 | 0-0.15 | 0-0.50 | 0-0.60 |
| Al2O3 | 0.25-0.40 | 0.30-0.60 | 0.10-0.30 | 0.20-0.40 | 0.20-0.50 | 0.20-0.50 | 0.25-0.60 | 0.25-0.80 |
| B2O3 | 0.15-0.35 | 0-0.30 | 0-1.0 | 0-0.50 | 0-0.50 | 0-0.50 | 0-0.40 | 0-0.20 |
| SiO2 | 2.5-4.0 | 3.0-5.0 | 1.5-4.0 | 2.0-3.5 | 2.0-3.0 | 2.0-6.0 | 2.0-5.0 | 2.0-5.0 |

`-` = no range in the source (not checked).

`Limits.check(_:against:)` returns, for every oxide in the set, `true` when
`min <= value <= max`, where the value is `umf[oxide]` (missing = 0), or the sum for KNaO.

## 5. Stull chart (`Stull.swift`)

Source chart: R. T. Stull, "Influences of variable silica and alumina on porcelain glazes of
constant RO", *Transactions of the American Ceramic Society* 14 (1912) 62-70, Chart 1 (public domain).
Stull fired a grid of glazes with RO fixed at 0.3 K2O / 0.7 CaO, at cone 11, with SiO2 on the x axis
(0.6 to 7.2) and Al2O3 on the y axis (0.1 to 1.0), and mapped the fired surfaces.

Reproduction used: the image of Chart 1 at https://digitalfire.com/glossary/stull+chart (only the
1912 chart image was read; no Digitalfire data is bundled). Lane G7 read the lines from that image
by eye (about +-0.05 UMF) on 22 Oct 2026; the readings are in `~/glaze-work/G7-REPORT.md`, section 3.
The published boundaries are curves; GlazeCore uses straight lines through the read points.
Cross-checks: Bloomfield, *Special Effect Glazes* (lines 1:4 matt, 1:5 semi-matt, 1:8 bright,
1:12 crazed; "Data from R.T. Stull 1912"); S. McLeod, *Ceramics Monthly*, Summer 2023 (satin at
SiO2:Al2O3 5-6, glossy at 7-10, underfired risk near 12); Marzano, McComb and Coppage,
*Ceramics Monthly*, February 2025 (the lines are curves; no crystallization zone; not valid for
boron glazes).

Limits of use: the chart is for 0.3 K2O / 0.7 CaO at cone 11. At cone 6, and for glazes with B2O3,
the regions are only a rough guide.

Rules, applied in this order (x = SiO2, y = Al2O3, UMF):

1. **unknown**: x or y not finite, x outside 0.6-7.2, or y outside 0.1-1.0 (outside the chart).
2. **unfused**: y > 0.44 + 0.25 (x - 0.6) (line M-J, top left).
3. **matte**: y > 0.10 + 0.25 (x - 0.6) (line N-U, slope about 1:4).
4. **semimatte**: y > 0.10 + 0.20 (x - 0.6) (line N-K, slope about 1:5).
5. For x >= 2.4:
   - **underfired**: y < 0.10 + 0.108 (x - 2.4) (curve O-S through (2.4, 0.10), (4.2, 0.30), (7.2, 0.62); lower right).
   - **crazing** (crazed or devitrified band just above O-S): y < 0.23 + 0.0583 (x - 3.0)
     (through (3.0, 0.23) and (4.2, 0.30)). Above x 4.3 the underfired line is higher, so the band ends there.
6. For x < 2.4: **crazing** when y < 0.25 (the hatched area at the bottom left).
7. Otherwise **gloss**.

Known points in the tests (`LimitsStullTests.swift`, source of each point in the test):

| SiO2 | Al2O3 | Region | Source |
|---|---|---|---|
| 3.5 | 0.40 | gloss | G7 table; Bloomfield 1:8 |
| 2.0 | 0.50 | matte | G7 table |
| 3.0 | 0.52 | gloss | G7 table |
| 5.0 | 0.80 | gloss | G7 table |
| 1.5 | 0.10 | crazing | G7, hatched area |
| 1.0 | 0.15 | crazing | G7, hatched area |
| 1.2 | 0.90 | unfused | G7, above M-J |
| 2.0 | 0.95 | unfused | G7, above M-J |
| 2.0 | 0.60 | matte | G7; Bloomfield 1:4 |
| 3.0 | 0.65 | semimatte | G7; Bloomfield 1:5 |
| 4.0 | 0.50 | gloss | Bloomfield 1:8 |
| 6.0 | 0.40 | underfired | G7, below O-S; McLeod (ratio 15) |
| 6.0 | 0.30 | underfired | G7, below O-S |
| 5.0 | 0.20 | underfired | G7, below O-S |
| 3.6 | 0.25 | crazing | G7, band above O-S |
| 7.0 | 0.70 | gloss | G7, above O-S |

Better data: digitize the original scan (Google Books id 9qwYAQAAIAAJ).

## 6. Verification notes (lanes G7 and G8, 22 Oct 2026)

Full check tables: `~/glaze-work/G7-REPORT.md` and `~/glaze-work/G8-REPORT.md`. Summary:

- **Zr atomic weight** was 91.224 (the pre-2021 value). IUPAC/CIAAW 2021 gives 91.222(3)
  (https://ciaaw.org/atomic-weights.htm, https://ciaaw.org/abridged-atomic-weights.htm). ZrO2 is now 123.220 g/mol;
  zircon is SiO2 32.778 %, ZrO2 67.222 %. `tools/gen_data.py` uses 91.222 (G8), so a new run gives the same JSON.
- **Appen constants.** Source reproduction: A. Fluegel, "Thermal expansion calculation of silicate glasses at 210 C,
  based on the systematic analysis of global databases", glassproperties.com, Dec 2007, Table I
  (https://www.glassproperties.com/expansion/Expansivity_Glass_2006.pdf) and
  https://glassproperties.com/expansion/Old-Thermal-Expansion-Models.htm, which cite A. A. Appen, *Khimiya stekla*,
  2nd ed., Leningrad 1974. The page lists Appen values in 1e-6 per K per mole fraction times 100; this app stores them times 10
  (1e-7 per K). Appen gives composition-dependent values for B2O3 (-5.0 to 0), PbO (13 to 19) and TiO2 (-1.5 to 3.0): nil in
  the table; since W6 F3 (26 Oct 2026) `Appen.swift` computes them from the page's footnotes (section 2).
  `tools/gen_data.py` holds Fe2O3 55, SnO2 -45, P2O5 140 (G8).
- **Limit sets.** G8 replaced the four uncited "Example ranges" sets by the eight cited sets in section 4.
- **Stull.** The original chart (Stull 1912, Chart 1) shows the underfired region at the lower right
  (high SiO2, low Al2O3) and an unfused region at the top left. G8 replaced the earlier approximation
  (underfired at the upper right) by the lines in section 5 and added `StullRegion.unfused`.
