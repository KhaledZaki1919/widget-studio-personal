import SwiftUI
import WidgetKitCore

/// The tasbeeh's dhikr list (M4 feedback): add, edit, reorder, delete, or go back to the default
/// four. The widget sees the list only with an App Group (developer mode); otherwise it keeps
/// the default list.
struct DhikrListView: View {
    @Environment(LiveDataModel.self) private var live
    /// Rows with stable ids, so editing a row while another is deleted can't index out of range.
    struct Item: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    @State private var items: [Item] = []
    @State private var newItem = ""

    var body: some View {
        List {
            Section {
                ForEach($items) { $item in
                    TextField("tasbeeh.placeholder", text: $item.text)
                        .multilineTextAlignment(.leading)
                }
                .onDelete { items.remove(atOffsets: $0) }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    TextField("tasbeeh.add", text: $newItem)
                        .onSubmit(add)
                        .accessibilityIdentifier("ax.dhikr.new")
                    Button(action: add) { Image(systemName: "plus.circle.fill") }
                        .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel(Text("tasbeeh.add"))
                }
            } footer: {
                Text("tasbeeh.list.footer")
            }
            Section {
                Button("tasbeeh.restore") { items = CounterState.defaultDhikrs.map { Item(text: $0) } }
            }
        }
        .m3List()
        .navigationTitle("tasbeeh.list")
        .toolbar { EditButton() }
        .onAppear { items = live.settings.dhikrList.map { Item(text: $0) } }
        .onChange(of: items) { _, list in save(list.map(\.text)) }
    }

    private func add() {
        let text = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        items.append(Item(text: text))
        newItem = ""
    }

    /// nil (the default list) when the list equals the defaults or is empty.
    private func save(_ list: [String]) {
        let usable = CounterState.usable(list)
        live.update { $0.dhikrs = usable == CounterState.defaultDhikrs ? nil : usable }
    }
}
