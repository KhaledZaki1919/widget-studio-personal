import EventKit
import MediaPlayer
import SwiftUI
import WidgetKitCore

/// The result screen's "Interactive" summary (ADR-027): what is live, what a tap does, and what only
/// looks like a control. Each item has Change, which opens that layer in the layer editor.
struct InteractiveSection: View {
    @Bindable var model: EditorModel
    private let language = RenderContext.preferredLanguage

    var body: some View {
        let summary = InteractiveSummary.build(model.design.spec, language: language)
        Section {
            if summary.isEmpty {
                Text("interactive.empty").font(.footnote).foregroundStyle(.secondary)
            }
            group("interactive.live", symbol: "waveform.path.ecg", items: summary.live)
            group("interactive.tap", symbol: "hand.tap.fill", items: summary.tappable)
            group("interactive.decorative", symbol: "paintbrush", items: summary.decorative)
        } header: {
            Text("interactive.title")
        } footer: {
            Text("interactive.footer")
        }
        .accessibilityIdentifier("ax.editor.interactive")
    }

    @ViewBuilder private func group(_ title: LocalizedStringKey, symbol: String, items: [InteractiveSummary.Item]) -> some View {
        if !items.isEmpty {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
            ForEach(items) { item in row(item) }
        }
    }

    @ViewBuilder private func row(_ item: InteractiveSummary.Item) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: item.title)
            if let detail = item.detail {
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        if item.path.isEmpty {
            label
        } else {
            NavigationLink {
                LayerDetailView(model: model, path: item.path)
            } label: {
                LabeledContent {
                    Text("interactive.change").font(.caption)
                } label: {
                    label
                }
            }
            .accessibilityIdentifier("ax.editor.interactive.change")
        }
    }
}

/// Picks a catalog capability, by group, with search. The lists come from the catalog, so a new
/// capability shows up here by itself.
struct CapabilityPicker: View {
    @Environment(\.dismiss) private var dismiss
    let capabilities: [Capability]
    let selected: String?
    let onPick: (Capability?) -> Void
    @State private var query = ""
    private let language = RenderContext.preferredLanguage

    private var shown: [Capability] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return capabilities }
        return capabilities.filter { capability in
            capability.id.lowercased().contains(text) || capability.title.resolved(language: language).lowercased().contains(text)
                || capability.keywords.contains { $0.lowercased().contains(text) }
        }
    }

    var body: some View {
        List {
            Section {
                Button("editor.layer.none") {
                    onPick(nil)
                    dismiss()
                }
                .accessibilityIdentifier("ax.editor.capability.none")
            }
            ForEach(Capabilities.groups) { group in
                let items = shown.filter { $0.group == group.id }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { row($0) }
                    } header: {
                        Text(verbatim: group.title.resolved(language: language))
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("editor.layer.pick")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ capability: Capability) -> some View {
        Button {
            onPick(capability)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: capability.title.resolved(language: language)).foregroundStyle(.primary)
                    if let note = capability.note(on: .ios) {
                        Text(verbatim: note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                switch capability.support(on: .ios) {
                case .shortcut: Image(systemName: "square.on.square").foregroundStyle(.secondary)
                case .unsupported: Image(systemName: "nosign").foregroundStyle(.orange)
                default: EmptyView()
                }
                if capability.id == selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
        .accessibilityIdentifier("ax.editor.capability.\(capability.id)")
    }
}

/// The layer editor's Live data and On tap sections (ADR-027).
struct WiringSections: View {
    @Bindable var model: EditorModel
    let path: LayerEditing.Path
    private let language = RenderContext.preferredLanguage

    private var layer: Layer? { LayerEditing.layer(at: path, in: model.design.spec.layers) }

    @ViewBuilder private func title(_ capability: Capability?) -> some View {
        if let capability {
            Text(verbatim: capability.title.resolved(language: language))
        } else {
            Text("editor.layer.none")
        }
    }

    var body: some View {
        if let layer, let kind = Wiring.bindableKind(layer) {
            let current = Wiring.binding(of: layer)
            Section {
                NavigationLink {
                    CapabilityPicker(capabilities: Wiring.bindings(for: kind), selected: current) { picked in
                        guard let binding = model.layer(path) else { return }
                        var changed = binding.wrappedValue
                        Wiring.setBinding(picked?.id, on: &changed)
                        binding.wrappedValue = changed
                    }
                } label: {
                    LabeledContent {
                        title(current.flatMap { Capabilities.binding($0) })
                    } label: {
                        Text("editor.layer.liveData")
                    }
                }
                .accessibilityIdentifier("ax.editor.layer.liveData")
            }
        }
        let existing = Wiring.button(over: path, in: model.design.spec)
        Section {
            NavigationLink {
                CapabilityPicker(capabilities: Capabilities.actions, selected: existing?.button.action.rawValue) { picked in
                    Wiring.setAction(picked?.id, over: path, in: &model.design.spec)
                }
            } label: {
                LabeledContent {
                    title(existing.flatMap { Capabilities.action($0.button.action.rawValue) })
                } label: {
                    Text("editor.layer.onTap")
                }
            }
            .accessibilityIdentifier("ax.editor.layer.onTap")
            if let existing, Capabilities.action(existing.button.action.rawValue)?.arg == "optional" {
                TextField("editor.layer.arg", text: Binding(get: {
                    Wiring.button(over: path, in: model.design.spec)?.button.arg ?? ""
                }, set: { value in
                    guard let current = Wiring.button(over: path, in: model.design.spec) else { return }
                    var button = current.button
                    button.arg = value.isEmpty ? nil : value
                    model.design.spec.layers[current.index].content = .button(button)
                }))
                .accessibilityIdentifier("ax.editor.layer.arg")
            }
        } footer: {
            if let existing, Capabilities.action(existing.button.action.rawValue)?.argFieldKind != nil {
                Text("editor.layer.onTap.field")
            }
        }
    }
}

/// Asks for what a saved design needs, right after saving it (ADR-027). Shortcuts are set up on
/// their first tap, not here.
@MainActor
enum WidgetPermissions {
    static func request(for specs: [WidgetSpec], live: LiveDataModel) async {
        var asked = Set<String>()
        for spec in specs {
            for permission in Capabilities.permissions(for: spec, on: .ios) where asked.insert(permission.id).inserted {
                switch permission.id {
                case "location":
                    if live.authorization == .notDetermined { live.requestLocation() }
                case "health":
                    if !live.healthAsked { await live.requestHealth() }
                case "calendar":
                    if EKEventStore.authorizationStatus(for: .event) == .notDetermined { _ = try? await EKEventStore().requestFullAccessToEvents() }
                case "reminders":
                    if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined { _ = try? await EKEventStore().requestFullAccessToReminders() }
                case "mediaLibrary":
                    if MPMediaLibrary.authorizationStatus() == .notDetermined {
                        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                            MPMediaLibrary.requestAuthorization { _ in continuation.resume() }
                        }
                    }
                default:
                    break
                }
            }
        }
    }
}
