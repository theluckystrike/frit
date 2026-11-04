import SwiftUI

/// The small + and − pair at the foot of a list or table, as in macOS lists (I6 C13). `trailing` holds
/// other controls of the foot, such as Normalize Base to 100.
struct ListFootButtons<Trailing: View>: View {
    let addLabel: String
    let removeLabel: String
    let add: () -> Void
    let remove: () -> Void
    var canAdd = true
    var canRemove = true
    var addHelp: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) {
                Image(systemName: "plus").frame(width: 24, height: 20).contentShape(Rectangle())
            }
            .disabled(!canAdd)
            .help(addHelp ?? addLabel)
            .accessibilityLabel(addLabel)
            Divider().frame(height: 14)
            Button(action: remove) {
                Image(systemName: "minus").frame(width: 24, height: 20).contentShape(Rectangle())
            }
            .disabled(!canRemove)
            .help(removeLabel)
            .accessibilityLabel(removeLabel)
            Spacer()
            trailing()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

extension ListFootButtons where Trailing == EmptyView {
    init(addLabel: String, removeLabel: String, add: @escaping () -> Void, remove: @escaping () -> Void,
         canAdd: Bool = true, canRemove: Bool = true, addHelp: String? = nil) {
        self.init(addLabel: addLabel, removeLabel: removeLabel, add: add, remove: remove,
                  canAdd: canAdd, canRemove: canRemove, addHelp: addHelp) { EmptyView() }
    }
}
