import Foundation

public enum StullRegion: String, Sendable { case matte, gloss, semimatte, underfired, crazing, unfused, unknown }

/// Stull chart regions, read from the original 1912 chart.
///
/// Source chart: R. T. Stull, "Influences of variable silica and alumina on porcelain glazes of constant RO",
/// Transactions of the American Ceramic Society 14 (1912) 62-70, Chart 1 (public domain). Stull fired
/// 0.3 K2O / 0.7 CaO glazes at cone 11. The lines below were read by eye from a reproduction of that chart
/// (about +-0.05 UMF) and are straight-line fits of the published curves. See Resources/README-data.md
/// section 5. The chart is not valid for boron glazes; use the result as a guide only.
public enum Stull {
    /// Area of the original chart (UMF). Points outside it are `.unknown`.
    public static let siO2Range: ClosedRange<Double> = 0.6...7.2
    public static let al2O3Range: ClosedRange<Double> = 0.1...1.0

    /// True when a line between two points shows beside their marks on the chart: they are more than 4 % of
    /// the chart's range apart on either axis (about 12 pt on the 300-pt chart of the Oxide Nudge sheet).
    /// Closer points sit under the "This glaze" diamond, so the sheets do not mention a line (L10).
    public static func pointsApart(siO2 x1: Double, al2O3 y1: Double, siO2 x2: Double, al2O3 y2: Double) -> Bool {
        let dx = abs(x2 - x1) / (siO2Range.upperBound - siO2Range.lowerBound)
        let dy = abs(y2 - y1) / (al2O3Range.upperBound - al2O3Range.lowerBound)
        return dx > 0.04 || dy > 0.04
    }

    /// `siO2` and `al2O3` are UMF values. The rules are tested in this order.
    public static func region(siO2 x: Double, al2O3 y: Double) -> StullRegion {
        guard x.isFinite, y.isFinite, siO2Range.contains(x), al2O3Range.contains(y) else { return .unknown }
        if y > unfusedLine(siO2: x) { return .unfused }
        if y > matteLine(siO2: x) { return .matte }
        if y > semimatteLine(siO2: x) { return .semimatte }
        if x >= 2.4, y < underfiredLine(siO2: x) { return .underfired }
        if y < crazingTop(siO2: x) { return .crazing }
        return .gloss
    }

    /// Top of the crazed area along the whole chart, one continuous line (I6 C4). Left of SiO2 2.4 it falls
    /// from 0.25 at the chart's edge to the band top at 2.4; right of 2.4 it is `crazingBandTop`.
    /// It used to be a flat 0.25 left of 2.4, which drew a rectangular step at 2.4 that Stull's chart does not have.
    public static func crazingTop(siO2 x: Double) -> Double {
        let joint = 2.4
        guard x < joint else { return crazingBandTop(siO2: x) }
        let left = 0.25, start = siO2Range.lowerBound
        let t = (x - start) / (joint - start)
        return left + (crazingBandTop(siO2: joint) - left) * t
    }

    /// Where the chart writes each region's name: one point well inside each region, in UMF (SiO2, Al2O3).
    /// The chart shows these labels so that the regions are told apart by text, not by color alone (HIG Charts).
    public static let labelAnchors: [StullLabelAnchor] = [
        StullLabelAnchor(.unfused, 1.3, 0.86),
        StullLabelAnchor(.matte, 2.3, 0.70),
        StullLabelAnchor(.semimatte, 4.4, 0.93),
        StullLabelAnchor(.gloss, 4.6, 0.52),
        StullLabelAnchor(.underfired, 6.3, 0.30),
        StullLabelAnchor(.crazing, 1.5, 0.15),
    ]

    /// Line M-J of the chart: above it the glaze is unfused (top left).
    public static func unfusedLine(siO2 x: Double) -> Double { 0.44 + 0.25 * (x - 0.6) }
    /// Line N-U (slope about 1:4): matte above it.
    public static func matteLine(siO2 x: Double) -> Double { 0.10 + 0.25 * (x - 0.6) }
    /// Line N-K (slope about 1:5): semi-matte between this line and the matte line, gloss below it.
    public static func semimatteLine(siO2 x: Double) -> Double { 0.10 + 0.20 * (x - 0.6) }
    /// Curve O-S as a line through (2.4, 0.10), (4.2, 0.30), (7.2, 0.62): underfired below it (lower right, x >= 2.4).
    public static func underfiredLine(siO2 x: Double) -> Double { 0.10 + 0.108 * (x - 2.4) }
    /// Top of the crazed / devitrified band just above the underfired curve: through (3.0, 0.23) and (4.2, 0.30).
    public static func crazingBandTop(siO2 x: Double) -> Double { 0.23 + (0.07 / 1.2) * (x - 3.0) }
}

/// A point where the chart writes a region's name.
public struct StullLabelAnchor: Sendable, Hashable {
    public let region: StullRegion
    public let siO2: Double
    public let al2O3: Double
    public init(_ region: StullRegion, _ siO2: Double, _ al2O3: Double) {
        self.region = region
        self.siO2 = siO2
        self.al2O3 = al2O3
    }
}
