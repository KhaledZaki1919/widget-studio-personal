import SwiftUI
import WidgetKitCore

/// The control for one template field, by type (brief §4.3). Text and city fields get an
/// Arabic and an English value; the others one value.
struct FieldEditor: View {
    let field: FieldSpec
    @Bindable var model: EditorModel
    private let language = RenderContext.preferredLanguage

    var body: some View {
        let title = field.label.resolved(language: language)
        switch field.type {
        case .text, .city:
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: title).font(.subheadline.weight(.medium))
                TextField(text: model.text(field, language: "ar")) { Text("editor.arabic") }
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("ax.editor.field.\(field.key).ar")
                TextField(text: model.text(field, language: "en")) { Text("editor.english") }
                    .environment(\.layoutDirection, .leftToRight)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("ax.editor.field.\(field.key).en")
            }
        case .app, .ticker:
            labeled(title) {
                TextField(text: model.plain(field)) { Text(verbatim: field.type == .app ? "com.spotify.music" : "TSLA") }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
            }
        case .shortcut:
            labeled(title) {
                TextField(text: model.plain(field)) { Text("editor.shortcut.placeholder") }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        case .url:
            labeled(title) {
                TextField(text: model.plain(field)) { Text(verbatim: "https://") }
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
            }
        case .number:
            labeled(title) {
                TextField(text: model.plain(field)) { Text(verbatim: "0") }
                    .keyboardType(.numberPad)
            }
        case .date:
            DatePicker(selection: model.date(field),
                       displayedComponents: model.dateHasTime(field) ? [.date, .hourAndMinute] : [.date]) {
                Text(verbatim: title)
            }
            .accessibilityIdentifier("ax.editor.field.\(field.key)")
        case .timezone:
            NavigationLink {
                TimeZonePicker(selection: model.plain(field))
            } label: {
                LabeledContent {
                    Text(verbatim: model.plain(field).wrappedValue.isEmpty ? "—" : model.plain(field).wrappedValue)
                } label: {
                    Text(verbatim: title)
                }
            }
            .accessibilityIdentifier("ax.editor.field.\(field.key)")
        case .icon:
            NavigationLink {
                IconPicker(selection: model.plain(field))
            } label: {
                LabeledContent {
                    Image(systemName: model.plain(field).wrappedValue.isEmpty ? "questionmark" : model.plain(field).wrappedValue)
                        .accessibilityLabel(Text(verbatim: IconPicker.spokenName(model.plain(field).wrappedValue)))
                } label: {
                    Text(verbatim: title)
                }
            }
            .accessibilityIdentifier("ax.editor.field.\(field.key)")
        case .color:
            ColorPicker(selection: Binding(
                get: { Color(hex: model.plain(field).wrappedValue.isEmpty ? "#000000" : model.plain(field).wrappedValue) },
                set: { model.plain(field).wrappedValue = EditorModel.hex($0) }
            ), supportsOpacity: false) {
                Text(verbatim: title)
            }
            .accessibilityIdentifier("ax.editor.field.\(field.key)")
        case .image:
            EmptyView()
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title).font(.subheadline.weight(.medium))
            content()
        }
        .accessibilityIdentifier("ax.editor.field.\(field.key)")
    }
}

/// Searchable list of time zones, with "not set" first (Day & Zone shows the device zone then).
struct TimeZonePicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            Button { pick("") } label: { row(title: Text("editor.timezone.none"), id: "") }
            ForEach(zones, id: \.self) { zone in
                Button { pick(zone) } label: { row(title: Text(verbatim: zone.replacingOccurrences(of: "_", with: " ")), id: zone) }
            }
        }
        .searchable(text: $query)
        .navigationTitle("editor.timezone")
    }

    private var zones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query.replacingOccurrences(of: " ", with: "_")) }
    }

    private func row(title: Text, id: String) -> some View {
        HStack {
            title.foregroundStyle(.primary)
            Spacer()
            if selection == id { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
    }

    private func pick(_ zone: String) {
        selection = zone
        dismiss()
    }
}

/// The icon whitelist as a grid.
struct IconPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    private let icons = Icons.whitelist.keys.sorted()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        selection = icon
                        dismiss()
                    } label: {
                        Image(systemName: icon)
                            .font(.title2)
                            .frame(width: 56, height: 56)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(selection == icon ? Color.accentColor.opacity(0.25) : Color(uiColor: .secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: Self.spokenName(icon)))
                    .accessibilityAddTraits(selection == icon ? .isSelected : [])
                }
            }
            .padding(16)
        }
        .navigationTitle("editor.icon")
    }

    /// "flashlight.on.fill" → "flashlight on", so VoiceOver reads a word, not a symbol ID.
    static func spokenName(_ symbol: String) -> String {
        let words = symbol.split(separator: ".").filter { !["fill", "circle", "square"].contains($0) }
        return words.isEmpty ? symbol : words.joined(separator: " ")
    }
}
