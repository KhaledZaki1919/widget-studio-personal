import SwiftUI
import WidgetKitCore

/// The States panel (ADR-028): preview each state with a picker or a level slider, choose a built-in
/// set and its colors, and edit each variant. Editing a variant writes the set's variants into the
/// design, so the catalog's own set stays as it is.
struct StatesSettings: View {
    @Binding var states: StatesLayer
    @Bindable var model: EditorModel
    @Environment(DesignsModel.self) private var designs
    @State private var picked = ""
    @State private var level = 0.5

    private var language: String { model.previewLanguage }

    /// The share this layer follows, when it follows one.
    private var levelBinding: String? {
        let names = (states.value.flatMap(Bindings.soleBinding).map { [$0] } ?? []) + (states.set.flatMap { Capabilities.stateSet($0)?.needs } ?? [])
        return names.first { Capabilities.binding($0)?.isShare ?? false }
    }

    private func title(_ variant: StatesLayer.Variant) -> String {
        variant.title?.resolved(language: language) ?? variant.id
    }

    private var pickedBinding: Binding<String> {
        Binding(get: { picked }, set: { id in
            picked = id
            guard let variant = states.expanded.first(where: { $0.id == id }) else {
                model.previewForced = [:]
                model.previewOverrides = [:]
                return
            }
            model.previewForced = [states.key: id]
            model.previewOverrides = BindingResolver.overrides(for: variant, of: states)
        })
    }

    private var setBinding: Binding<String> {
        Binding(get: { states.set ?? "" }, set: { id in
            guard !id.isEmpty else { return }
            let set = Capabilities.stateSet(id)
            states.set = id
            states.variants = nil
            states.box = nil
            states.value = set?.value
            picked = ""
            model.previewForced = [:]
            model.previewOverrides = [:]
        })
    }

    var body: some View {
        Section("editor.states.preview") {
            DesignPreview(design: model.design, image: model.newPhoto ?? designs.image(for: model.design), language: language,
                          forced: model.previewForced, overrides: model.previewOverrides)
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity)
            Picker("editor.states.show", selection: pickedBinding) {
                Text("editor.states.real").tag("")
                ForEach(states.expanded) { Text(verbatim: title($0)).tag($0.id) }
            }
            .accessibilityIdentifier("ax.editor.states.show")
            if let levelBinding {
                VStack(alignment: .leading) {
                    Text(verbatim: "\(Int(level * 100))%").font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { level }, set: { value in
                        level = value
                        picked = ""
                        model.previewForced = [:]
                        model.previewOverrides = [levelBinding: String(value)]
                    }), in: 0...1)
                    .accessibilityIdentifier("ax.editor.states.level")
                }
            }
        }
        Section("editor.states.look") {
            Picker("editor.states.set", selection: setBinding) {
                if states.set == nil { Text("editor.states.custom").tag("") }
                ForEach(Capabilities.stateSets) { Text(verbatim: $0.title.resolved(language: language)).tag($0.id) }
            }
            ColorTokenPicker(title: "editor.layer.color", value: $states.color, model: model)
            ColorTokenPicker(title: "editor.color.accent", value: $states.accent, model: model)
        }
        Section {
            ForEach(states.expanded) { variant in
                NavigationLink {
                    VariantEditor(states: $states, id: variant.id, model: model)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: title(variant))
                        Text(verbatim: variant.when ?? String(localized: "editor.states.default"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("editor.states.variants")
        } footer: {
            Text("editor.states.footer")
        }
        .onDisappear {
            model.previewForced = [:]
            model.previewOverrides = [:]
        }
    }
}

/// One state: its condition and the colors of what it draws.
private struct VariantEditor: View {
    @Binding var states: StatesLayer
    let id: String
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss

    /// The first edit turns a built-in set into variants of this design.
    private func customize() {
        guard states.variants == nil else { return }
        let box = states.set.flatMap { Capabilities.stateSet($0)?.box }
        let variants = states.expanded
        states.box = box
        states.variants = variants
        states.set = nil
    }

    private func change(_ edit: (inout StatesLayer.Variant) -> Void) {
        customize()
        guard var variants = states.variants, let index = variants.firstIndex(where: { $0.id == id }) else { return }
        edit(&variants[index])
        states.variants = variants
    }

    private var variant: StatesLayer.Variant? { states.expanded.first { $0.id == id } }

    var body: some View {
        Form {
            if let variant {
                Section {
                    TextField("editor.states.when", text: Binding(get: { variant.when ?? "" }, set: { text in
                        change { $0.when = text.isEmpty ? nil : text }
                    }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .accessibilityIdentifier("ax.editor.states.when")
                } header: {
                    Text("editor.states.when")
                } footer: {
                    if let when = variant.when, SpecExpression(when) == nil {
                        Text("editor.states.when.invalid").foregroundStyle(.red)
                    } else {
                        Text("editor.states.when.hint")
                    }
                }
                ForEach(Array(variant.layers.enumerated()), id: \.offset) { index, layer in
                    Section {
                        layerControls(layer, index: index)
                    } header: {
                        Text(LayerRow.kind(layer.content))
                    }
                }
                if states.expanded.count > 1 {
                    Section {
                        Button("editor.states.remove", role: .destructive) {
                            customize()
                            states.variants?.removeAll { $0.id == id }
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle(variant?.title?.resolved(language: model.previewLanguage) ?? id)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// What a state's drawing can change: its symbol and colors.
    @ViewBuilder private func layerControls(_ layer: Layer, index: Int) -> some View {
        switch layer.content {
        case .icon(let icon):
            TextField("editor.layer.symbol", text: Binding(get: { icon.symbol }, set: { symbol in
                update(index) { if case .icon(var changed) = $0.content { changed.symbol = symbol; $0.content = .icon(changed) } }
            }))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            ColorTokenPicker(title: "editor.layer.color", value: Binding(get: { icon.color }, set: { color in
                update(index) { if case .icon(var changed) = $0.content { changed.color = color; $0.content = .icon(changed) } }
            }), model: model)
        case .shape(let shape):
            ColorTokenPicker(title: "editor.layer.fill", value: Binding(get: { shape.fill ?? shape.stroke?.color ?? "@fg" }, set: { color in
                update(index) { if case .shape(var changed) = $0.content { changed.fill = color; $0.content = .shape(changed) } }
            }), model: model)
        case .dotGrid(let grid):
            ColorTokenPicker(title: "editor.layer.color", value: Binding(get: { grid.onColor }, set: { color in
                update(index) { if case .dotGrid(var changed) = $0.content { changed.onColor = color; $0.content = .dotGrid(changed) } }
            }), model: model)
        case .text(let text):
            TextField("editor.states.text", text: Binding(get: { text.value.resolved(language: model.previewLanguage) }, set: { value in
                update(index) { if case .text(var changed) = $0.content { changed.value = .plain(value); $0.content = .text(changed) } }
            }))
        default:
            EmptyView()
        }
    }

    private func update(_ index: Int, _ edit: (inout Layer) -> Void) {
        change { variant in
            guard variant.layers.indices.contains(index) else { return }
            edit(&variant.layers[index])
        }
    }
}
