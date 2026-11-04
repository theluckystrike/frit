import SwiftUI
import GlazeCore

/// A number field that writes its value on each keystroke, so that the chemistry and the Stull chart follow
/// the typing. (A `TextField(value:format:)` on macOS writes only on Return, Tab or loss of focus.)
/// Text that does not parse as a number leaves the value as it is. When editing ends, the text is
/// formatted again. Only typing writes: setting up or reformatting the text never writes the value, so
/// showing a recipe does not edit the book (`NumberText.valueToWrite`, W5 V4).
struct LiveNumberField: View {
    let title: String
    @Binding var value: Double
    var fractionDigits: ClosedRange<Int> = 0...2
    /// False for amounts and weights: a negative entry is not taken (the text stays until editing ends).
    var allowsNegative = false

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .focused($focused)
            .onAppear { text = format(value) }
            .onChange(of: value) { _, new in
                // An outside change (Normalize, Undo) shows at once; the user's own typing is left alone.
                if !focused || NumberText.parse(text, allowsNegative: allowsNegative) != new { text = format(new) }
            }
            .onChange(of: text) { _, new in
                guard let v = NumberText.valueToWrite(text: new, current: value, isEditing: focused,
                                                      fractionDigits: fractionDigits, allowsNegative: allowsNegative)
                else { return }
                value = v
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = format(value) }
            }
            .onSubmit { text = format(value) }
    }

    private func format(_ v: Double) -> String {
        NumberText.format(v, fractionDigits: fractionDigits)
    }
}
