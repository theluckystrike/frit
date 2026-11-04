import SwiftUI
import Charts
import GlazeCore

extension StullRegion {
    var title: String {
        switch self {
        case .matte: return "Matte"
        case .gloss: return "Gloss"
        case .semimatte: return "Semi-matte"
        case .underfired: return "Underfired"
        case .crazing: return "Crazing likely"
        case .unfused: return "Unfused"
        case .unknown: return "Outside chart"
        }
    }

    /// Fill colour as sRGB components (also used for the region image).
    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .matte: return (0.72, 0.55, 0.36)
        case .gloss: return (0.30, 0.55, 0.85)
        case .semimatte: return (0.40, 0.68, 0.60)
        case .underfired: return (0.55, 0.55, 0.58)
        case .crazing: return (0.75, 0.40, 0.65)
        case .unfused: return (0.82, 0.74, 0.48)
        case .unknown: return (0, 0, 0)
        }
    }

    var color: Color { Color(red: rgb.r, green: rgb.g, blue: rgb.b) }

    static let shown: [StullRegion] = [.gloss, .semimatte, .matte, .unfused, .underfired, .crazing]
}

/// The Stull regions drawn as a fine bitmap (one sample per cell of about 0.02 SiO2 x 0.005 Al2O3),
/// so that the region boundaries are smooth lines, not the stairs of a coarse grid (G5 defect 9).
enum StullRegionImage {
    /// The fill opacity of the regions. The legend swatches use the same value, so they match the plot (I6 C4).
    /// Higher in dark mode, where the regions went muddy at 0.35, and with Increase Contrast.
    static func opacity(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> Double {
        switch (scheme, contrast) {
        case (_, .increased): return 0.6
        case (.dark, _): return 0.45
        default: return 0.35
        }
    }

    static func make(x: ClosedRange<Double>, y: ClosedRange<Double>, opacity: Double,
                     width: Int = 360, height: Int = 200) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let dx = (x.upperBound - x.lowerBound) / Double(width)
        let dy = (y.upperBound - y.lowerBound) / Double(height)
        for row in 0..<height {
            // Row 0 is the top of the image, which is the largest Al2O3 value.
            let al = y.upperBound - (Double(row) + 0.5) * dy
            for col in 0..<width {
                let si = x.lowerBound + (Double(col) + 0.5) * dx
                let region = Stull.region(siO2: si, al2O3: al)
                guard region != .unknown else { continue }
                let c = region.rgb
                let k = (row * width + col) * 4
                pixels[k] = UInt8(c.r * opacity * 255)       // premultiplied alpha
                pixels[k + 1] = UInt8(c.g * opacity * 255)
                pixels[k + 2] = UInt8(c.b * opacity * 255)
                pixels[k + 3] = UInt8(opacity * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

struct StullChartView: View {
    let current: StullPoint?
    /// Oldest first; the last item is the current position.
    let trail: [StullPoint]
    /// The glaze has B2O3, which Stull's chart does not model.
    var hasBoron = false
    /// True in the Oxide Nudge and Replace Material sheets: the trail is the current recipe, and `current` is the
    /// new one. The caption and the VoiceOver text then say so in place of "edits".
    var isComparison = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var regionOpacity: Double { StullRegionImage.opacity(scheme, contrast) }

    /// The axes start at the corner of Stull's chart, so there is no empty strip at the left (G5 defect 9).
    private var xMin: Double {
        let lo = min(Stull.siO2Range.lowerBound, (current?.siO2 ?? .infinity) - 0.3)
        return max(0, (lo * 10).rounded(.down) / 10)
    }
    private var yMin: Double {
        let lo = min(Stull.al2O3Range.lowerBound, (current?.al2O3 ?? .infinity) - 0.05)
        return max(0, (lo * 20).rounded(.down) / 20)
    }
    private var xMax: Double { max(Stull.siO2Range.upperBound, ((current?.siO2 ?? 0) + 0.5).rounded(.up)) }
    private var yMax: Double { max(Stull.al2O3Range.upperBound, (((current?.al2O3 ?? 0) + 0.1) * 10).rounded(.up) / 10) }

    private var previous: [StullPoint] { Array(trail.dropLast().suffix(5)) }

    private var trailLine: [StullPoint] { previous + (current.map { [$0] } ?? []) }

    private var currentRegion: StullRegion? {
        current.map { Stull.region(siO2: $0.siO2, al2O3: $0.al2O3) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // One line where there is room; the glaze position goes under the title in a narrow window (G11).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Stull chart").font(.title3.weight(.semibold))
                    Spacer()
                    position
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stull chart").font(.title3.weight(.semibold))
                    position
                }
            }
            chart
                .frame(minHeight: 140, idealHeight: 200, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stull chart")
                .accessibilityValue(summary)
                .accessibilityChartDescriptor(StullChartDescriptor(
                    current: current, previous: previous, region: currentRegion,
                    xRange: xMin...xMax, yRange: yMin...yMax))
            legend
            // No colons in the caption (I6 C5). The boron note keeps the chart honest for boron glazes.
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caption: String {
        var text = "Regions from Stull's 1912 chart, fired to cone 11, glazes without boron. Use it as a rough guide."
        if current != nil && hasBoron { text += " This glaze has boron, so its position is approximate." }
        if isComparison, let current, let last = previous.last {
            // A small change leaves both points under the diamond, with no line to see (L10 render).
            text += Stull.pointsApart(siO2: last.siO2, al2O3: last.al2O3, siO2: current.siO2, al2O3: current.al2O3)
                ? " The dashed line runs from the current recipe to the new one."
                : " On this chart the new recipe is at about the same place as the current one."
        } else if !previous.isEmpty {
            text += " The dashed line shows the last 5 edits."
        }
        return text
    }

    @ViewBuilder
    private var position: some View {
        if let current, let currentRegion {
            Text("This glaze: SiO₂ \(fmt(current.siO2, 2)), Al₂O₃ \(fmt(current.al2O3, 2)), \(currentRegion.title)")
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityHidden(true)
        } else {
            Text("Add materials to place the glaze on the chart.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// One row of six where there is room, else two rows of three. A plain Grid, not a lazy grid, so that the
    /// legend reports its real height and the caption under it is not cut off in a short window (G11).
    private var legend: some View {
        let regions = StullRegion.shown
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                ForEach(regions, id: \.self) { legendItem($0) }
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow { ForEach(regions.prefix(3), id: \.self) { legendItem($0) } }
                GridRow { ForEach(regions.suffix(from: 3), id: \.self) { legendItem($0) } }
            }
        }
        .accessibilityHidden(true)
    }

    private func legendItem(_ region: StullRegion) -> some View {
        HStack(spacing: 4) {
            // The same color and opacity as the plotted region, over the same background (I6 C4).
            RoundedRectangle(cornerRadius: 2)
                .fill(region.color.opacity(regionOpacity))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                .frame(width: 12, height: 10)
            Text(region.title).font(.caption).fixedSize()
        }
    }

    private var chart: some View {
        let xDomain = xMin...xMax
        let yDomain = yMin...yMax
        let regions = StullRegionImage.make(x: xDomain, y: yDomain, opacity: regionOpacity)
        let labels = Stull.labelAnchors.filter { xDomain.contains($0.siO2) && yDomain.contains($0.al2O3) }
        return Chart {
            // Region names inside the plot, so the regions are not told apart by color alone (HIG Charts, I6 C4).
            ForEach(labels, id: \.region) { anchor in
                PointMark(x: .value("SiO₂", anchor.siO2), y: .value("Al₂O₃", anchor.al2O3))
                    .symbolSize(0)
                    .annotation(position: .overlay) {
                        Text(anchor.region.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .accessibilityHidden(true)
            }
            ForEach(Array(trailLine.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("SiO₂", p.siO2), y: .value("Al₂O₃", p.al2O3), series: .value("Series", "Trail"))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            ForEach(Array(previous.enumerated()), id: \.offset) { index, p in
                PointMark(x: .value("SiO₂", p.siO2), y: .value("Al₂O₃", p.al2O3))
                    .symbol(.circle)
                    .symbolSize(30)
                    .foregroundStyle(Color.primary.opacity(0.25 + 0.12 * Double(index)))
            }
            if let current {
                PointMark(x: .value("SiO₂", current.siO2), y: .value("Al₂O₃", current.al2O3))
                    .symbol(.diamond)
                    .symbolSize(140)
                    .foregroundStyle(Color.primary)
                    .annotation(position: .top, alignment: .center) {
                        Text("This glaze")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 4)
                            .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                    }
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame, let regions {
                    let frame = geo[plot]
                    Image(decorative: regions, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        // Y axis on the leading edge, the same solid gridlines on both axes, X label centered (I6 C5).
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .chartXAxisLabel("SiO₂ (UMF)", position: .bottom, alignment: .center)
        .chartYAxisLabel("Al₂O₃ (UMF)", position: .leading)
    }

    private var summary: String {
        guard let current, let currentRegion else { return "No glaze point yet." }
        var s = "Glaze point at silica \(fmt(current.siO2, 2)), alumina \(fmt(current.al2O3, 2)), in the \(currentRegion.title) region."
        if let last = previous.last {
            let dSi = current.siO2 - last.siO2
            let dAl = current.al2O3 - last.al2O3
            if isComparison {
                s += " Compared with the current recipe, silica changes by \(fmt(dSi, 2)) and alumina by \(fmt(dAl, 2))."
                return s
            }
            s += " Since the last edit, silica changed by \(fmt(dSi, 2)) and alumina by \(fmt(dAl, 2))."
            s += " The trail has \(previous.count) earlier point\(previous.count == 1 ? "" : "s")."
        }
        return s
    }
}

struct StullChartDescriptor: AXChartDescriptorRepresentable {
    let current: StullPoint?
    let previous: [StullPoint]
    let region: StullRegion?
    /// The displayed axis domains, so VoiceOver and Audio Graphs report the bounds the chart shows (I6 C15).
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>

    func makeChartDescriptor() -> AXChartDescriptor {
        let points = previous + (current.map { [$0] } ?? [])
        let xAxis = AXNumericDataAxisDescriptor(title: "SiO2 UMF", range: xRange, gridlinePositions: []) { "Silica \(fmt($0, 2))" }
        let yAxis = AXNumericDataAxisDescriptor(title: "Al2O3 UMF", range: yRange, gridlinePositions: []) { "Alumina \(fmt($0, 2))" }
        let series = AXDataSeriesDescriptor(
            name: "Glaze position, oldest first",
            isContinuous: true,
            dataPoints: points.enumerated().map { index, p in
                AXDataPoint(x: p.siO2, y: p.al2O3, additionalValues: [],
                            label: (index == points.count - 1 ? "Current" : "Edit \(index + 1)")
                                + ", \(Stull.region(siO2: p.siO2, al2O3: p.al2O3).title)")
            }
        )
        return AXChartDescriptor(
            title: "Stull chart",
            summary: region.map { "Current glaze in the \($0.title) region" },
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }
}
