import Foundation

/// The Orton pyrometric cone sequence from cone 022 (coolest) to cone 14 (W6 F3: the picker had left out
/// 03, 01, 2, 3 and others). Source: Edward Orton Jr. Ceramic Foundation, "Pyrometric Cone Temperature
/// Equivalent Chart" (self-supporting and large cones), which lists 022 to 01, then 1 to 14, with 05½ between
/// 06 and 05.
public enum OrtonCones {
    public static let all: [String] =
        ["022", "021", "020", "019", "018", "017", "016", "015", "014", "013", "012", "011", "010",
         "09", "08", "07", "06", "05½", "05", "04", "03", "02", "01"]
        + (1...14).map(String.init)
}
