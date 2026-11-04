import Foundation


/// Helpers for UI bindings. SwiftUI text fields can write back an unchanged value (for example when a
/// field takes focus). A write to the document binding marks the document edited and starts an autosave,
/// so every binding first checks that the value really changed.
public enum Edit {
    /// Sets `target` to `value` only when they differ. Returns true when it wrote.
    @discardableResult
    public static func assign<T: Equatable>(_ value: T, to target: inout T) -> Bool {
        guard target != value else { return false }
        target = value
        return true
    }

    /// The index of the element with `value.id`, or nil when there is no such element or it already equals `value`.
    /// Use the index to write, so that an unchanged value never touches the array (or the binding that holds it).
    public static func indexToReplace<E: Identifiable & Equatable>(_ value: E, in array: [E]) -> Int? {
        guard let i = array.firstIndex(where: { $0.id == value.id }), array[i] != value else { return nil }
        return i
    }
}
