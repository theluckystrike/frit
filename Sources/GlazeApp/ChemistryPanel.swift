import SwiftUI
import GlazeCore

enum LimitStatus {
    case noRange, inRange, below, above

    var symbol: String {
        switch self {
        case .noRange: return "minus"
        case .inRange: return "checkmark.circle"
        case .below: return "arrow.down.circle.fill"
        case .above: return "arrow.up.circle.fill"
        }
    }

    var text: String {
        switch self {
        case .noRange: return ""
        case .inRange: return "In range"
        case .below: return "Below range"
        case .above: return "Above range"
        }
    }

    var isOut: Bool { self == .below || self == .above }
}

struct ChemistryPanel: View {
    let chemistry: Chemistry
    @Binding var includeAdditions: Bool
    /// Set when some recipe rows are not in the calculation (a row with an amount but no material, W6 F3).
    var incompleteNote: String? = nil
    /// Oxide Nudge: called with the oxide and +1 or -1 when an arrow next to a UMF value is clicked.
    /// Nil hides the arrows.
    var onNudge: ((Oxide, Int) -> Void)? = nil
    @AppStorage("limitSetID") private var limitSetID = ""

    private var limitSet: LimitSet? {
        Limits.bundled.first { $0.id == limitSetID } ?? Limits.bundled.first
    }

    private var inRangeMap: [Oxide: Bool] {
        guard let limitSet else { return [:] }
        return Limits.check(chemistry, against: limitSet)
    }

    private func range(for oxide: Oxide) -> LimitRange? {
        limitSet?.ranges.first { $0.covers(oxide) }
    }

    /// False when the recipe has no flux oxides: then there is no unity to divide by, so the UMF, the R2O : RO
    /// ratio and the UMF reference ranges are not defined (W6 F2). Weight % and mole % still are.
    private var umfAvailable: Bool { !chemistry.umf.isEmpty }

    private func status(for oxide: Oxide) -> LimitStatus {
        guard umfAvailable, let r = range(for: oxide) else { return .noRange }
        let value = r.value(in: chemistry.umf)
        let inRange = inRangeMap[oxide] ?? (value >= r.min && value <= r.max)
        if inRange { return .inRange }
        return value < r.min ? .below : .above
    }

    /// Without a UMF the rows come from the mole percentages, so the oxides stay listed (W6 F2).
    private func isPresent(_ oxide: Oxide) -> Bool {
        umfAvailable ? (chemistry.umf[oxide] ?? 0) > 0.00005 : (chemistry.molePercent[oxide] ?? 0) > 0.005
    }

    /// Oxides to show: the ones present, plus absent ones that are outside their reference range
    /// (for example no Al2O3 when the range asks for some). Absent oxides that are in range are left out (G5 defect 8).
    private func oxides(in group: OxideGroup) -> [Oxide] {
        Oxide.allCases.filter { oxide in
            oxide.group == group && (isPresent(oxide) || status(for: oxide).isOut)
        }
    }

    /// Oxides with a range that are absent and in range, so not listed.
    private var hiddenInRange: [Oxide] {
        guard umfAvailable, let limitSet else { return [] }
        let covered = Set(limitSet.ranges.flatMap(\.oxides))
        return Oxide.allCases.filter { covered.contains($0) && !isPresent($0) && !status(for: $0).isOut }
    }

    private var outOfRangeCount: Int {
        Oxide.allCases.filter { status(for: $0).isOut }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chemistry").font(.title3.weight(.semibold))
            if let incompleteNote {
                Label(incompleteNote, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Reference ranges", selection: Binding(
                get: { limitSet?.id ?? "" },
                set: { if $0 != limitSetID { limitSetID = $0 } }
            )) {
                ForEach(Limits.bundled) { set in
                    Text(set.name).tag(set.id)
                }
            }
            .help(limitSet.map { "\($0.name). Source: \($0.source)" } ?? "")
            .accessibilityLabel("Reference range set")
            // Under the heading, next to the reference ranges (I6 C6). It was above the heading.
            Toggle("Include additions in chemistry", isOn: $includeAdditions)
                .toggleStyle(.checkbox)
                .accessibilityHint("When on, colorant and opacifier additions count in the UMF")
            if includeAdditions && onNudge != nil && umfAvailable {
                Text("Oxide Nudge arrows show when additions are not included, because Oxide Nudge works on the base.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let limitSet {
                VStack(alignment: .leading, spacing: 2) {
                    Text("These are reference ranges for comparison, not a safety rating.")
                    DisclosureGroup("Source") {
                        Text(limitSet.source)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ratios

            if !umfAvailable && !chemistry.molePercent.isEmpty {
                Text("UMF not available. The recipe has no flux oxides, so no oxide sum can be set to 1. "
                     + "The table shows weight % and mole % only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The full table where the inspector is wide; without the Mol % column, then with the status
            // as a symbol only, where it is narrow (G11). VoiceOver reads the same row text in each form.
            ViewThatFits(in: .horizontal) {
                umfTable(.full)
                umfTable(.noMolePercent)
                umfTable(.compact)
            }

            if !hiddenInRange.isEmpty {
                Text("Not listed (0, within range): \(hiddenInRange.map(\.display).joined(separator: ", ")).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if outOfRangeCount > 0 {
                Label("\(outOfRangeCount) oxide\(outOfRangeCount == 1 ? "" : "s") outside the reference range",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
            }

            if !chemistry.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warnings").font(.headline)
                    ForEach(chemistry.warnings, id: \.self) { warning in
                        Label(OxideText.subscripted(warning), systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Warnings")
            }
        }
    }

    private var ratios: some View {
        let r2o = chemistry.r2oRatio
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            // One VoiceOver element per row (label on the first cell, value cell hidden), as in the UMF table.
            GridRow {
                Text("SiO₂ : Al₂O₃").foregroundStyle(.secondary)
                    .accessibilityLabel("Silica to alumina ratio \(fmt(chemistry.siAlRatio, 2))")
                Text(fmt(chemistry.siAlRatio, 2)).monospacedDigit().accessibilityHidden(true)
            }
            GridRow {
                Text("R₂O : RO").foregroundStyle(.secondary)
                    .accessibilityLabel(umfAvailable ? "R 2 O to R O ratio \(fmt(r2o, 2)) to \(fmt(1 - r2o, 2))"
                                                     : "R 2 O to R O ratio not available, no flux oxides")
                Text(umfAvailable ? "\(fmt(r2o, 2)) : \(fmt(1 - r2o, 2))" : "—").monospacedDigit()
                    .help(umfAvailable ? "" : "Not available. The recipe has no flux oxides.")
                    .accessibilityHidden(true)
            }
            GridRow {
                Text("Expansion (Appen estimate)").foregroundStyle(.secondary)
                    .accessibilityLabel("Expansion, Appen estimate, " + expansionSpoken)
                Text(chemistry.expansion.map { "\(fmt($0, 1)) × 10⁻⁷/K" + (chemistry.expansionIsPartial ? ", partial" : "") }
                     ?? "Not available").monospacedDigit()
                    .accessibilityHidden(true)
            }
            if chemistry.expansionIsPartial {
                // A partial sum is never shown as complete (W6 F3): name the oxides the estimate leaves out.
                GridRow {
                    Text("Partial: does not count \(expansionNotCountedNames). See Warnings.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .gridCellColumns(2)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var expansionNotCountedNames: String {
        chemistry.expansionNotCounted.map { OxideText.subscripted($0.rawValue) }.joined(separator: ", ")
    }

    private var expansionSpoken: String {
        guard let e = chemistry.expansion else { return "not available" }
        let value = "\(fmt(e, 1)) times 10 to the minus 7 per kelvin"
        guard chemistry.expansionIsPartial else { return value }
        return value + ", partial, does not count "
            + chemistry.expansionNotCounted.map(\.rawValue).joined(separator: ", ")
    }

    enum TableStyle {
        case full, noMolePercent, compact
        var showsMolePercent: Bool { self == .full }
        var showsStatusText: Bool { self != .compact }
        var columns: Int { showsMolePercent ? 6 : 5 }
    }

    /// The Nudge column shows only where there is a UMF to change, and not while additions are included:
    /// Oxide Nudge works on the base only, so the sheet's "Now" would differ from the value clicked (L7 C4).
    private var showsNudge: Bool { onNudge != nil && umfAvailable && !includeAdditions }

    private func columnCount(_ style: TableStyle) -> Int { style.columns + (showsNudge ? 1 : 0) }

    private func umfTable(_ style: TableStyle) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: style == .compact ? 10 : 12, verticalSpacing: 3) {
            GridRow {
                Text("Oxide").gridColumnAlignment(.leading)
                Text("UMF")
                if showsNudge { Text("") }
                if style.showsMolePercent { Text("Mol %") }
                Text("Wt %")
                Text("Ref. range")
                Text("Status").gridColumnAlignment(.leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            ForEach(OxideGroup.allCases) { group in
                let list = oxides(in: group)
                if !list.isEmpty {
                    GridRow {
                        Text(group.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .gridCellColumns(columnCount(style))
                            .gridCellAnchor(.leading)
                            .padding(.top, 6)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if group == .flux {
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                    ForEach(list, id: \.self) { oxide in
                        oxideRow(oxide, style: style)
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unity molecular formula")
    }

    /// For a range that covers two oxides (KNaO), the rows after the first one listed do not repeat it (I6 C16).
    private func repeatsSharedRange(_ oxide: Oxide, _ r: LimitRange?) -> Bool {
        guard let r, r.combinedWith != nil else { return false }
        let shown = oxides(in: oxide.group).filter { r.covers($0) }
        return shown.first != oxide
    }

    private func oxideRow(_ oxide: Oxide, style: TableStyle) -> some View {
        let umf = chemistry.umf[oxide] ?? 0
        let st = status(for: oxide)
        let r = range(for: oxide)
        let shared = repeatsSharedRange(oxide, r)
        // VoiceOver reads one element per row: the first cell carries the row's text and the other cells are
        // hidden. (Accessibility modifiers on a GridRow go to each cell, so VoiceOver read every row 5 or 6 times.)
        return GridRow {
            Text(oxide.display).gridColumnAlignment(.leading)
                .accessibilityLabel(rowAccessibility(oxide, umf: umf, status: st, range: r))
            Text(umfAvailable ? fmt(umf, 3) : "—").monospacedDigit().fontWeight(st.isOut ? .bold : .regular)
                .help(umfAvailable ? "" : "UMF not available. The recipe has no flux oxides.")
                .accessibilityHidden(true)
            if showsNudge {
                if let onNudge, Reformulate.canNudge(oxide, chemistry: chemistry, includeAdditions: includeAdditions) {
                    // Oxide Nudge (Recipe > Oxide Nudge…): each arrow opens the sheet with a target 0.05 up or down.
                    Stepper("Nudge \(oxide.display)", onIncrement: { onNudge(oxide, 1) }, onDecrement: { onNudge(oxide, -1) })
                        .labelsHidden()
                        .controlSize(.small)
                        .help("Oxide Nudge: change the amounts so that \(oxide.display) goes up or down by \(fmt(Reformulate.step, 2)) in the UMF")
                        .accessibilityLabel("Oxide Nudge for \(oxide.spoken)")
                        .accessibilityHint("Opens a sheet that changes the amounts so this oxide goes up or down by 0.05")
                } else {
                    // The only flux (UMF always 1): no arrows, but the cell keeps the grid's columns.
                    Text("").accessibilityHidden(true)
                }
            }
            Group {
            if style.showsMolePercent {
                Text(fmt(chemistry.molePercent[oxide] ?? 0, 1)).monospacedDigit()
            }
            Text(fmt(chemistry.weightPercent[oxide] ?? 0, 1)).monospacedDigit()
            Text(shared ? "↑ shared" : r.map { ($0.combinedWith == nil ? "" : "\($0.label) ") + "\(fmt($0.min, 2))–\(fmt($0.max, 2))" } ?? "–")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help(shared ? "One range for \(r?.label ?? "") covers this oxide and the one above it" : "")
            HStack(spacing: 3) {
                if st != .noRange {
                    Image(systemName: st.symbol)
                        .foregroundStyle(st.isOut ? Color.orange : Color.secondary)
                    if style.showsStatusText {
                        Text(st.text)
                            .foregroundStyle(st.isOut ? .primary : .secondary)
                    }
                }
            }
            .font(.callout)
            .gridColumnAlignment(.leading)
            .help(st.text)
            }
            .accessibilityHidden(true)
        }
    }

    private func rowAccessibility(_ oxide: Oxide, umf: Double, status: LimitStatus, range: LimitRange?) -> String {
        let umfText = umfAvailable ? "UMF \(fmt(umf, 3))" : "UMF not available"
        var s = "\(oxide.spoken), \(umfText), \(fmt(chemistry.weightPercent[oxide] ?? 0, 1)) weight percent"
        if let range {
            let what = range.combinedWith == nil ? "" : " for \(range.label)"
            s += ", reference range\(what) \(fmt(range.min, 2)) to \(fmt(range.max, 2)), \(status.text)"
        }
        return s
    }
}
