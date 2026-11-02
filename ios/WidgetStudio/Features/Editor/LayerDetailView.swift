import SwiftUI
import WidgetKitCore

/// One layer in the layer editor (M6.1, ADR-022): position and size (a stack's items only
/// width and height, 0 = natural), opacity, and the settings of its kind (text, icon, shape,
/// stack). Other kinds show only their frame. Saving still validates the whole design.
struct LayerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: EditorModel
    let path: LayerEditing.Path

    private var isTopLevel: Bool { path.count == 1 }

    var body: some View {
        Group {
            if let layer = model.layer(path) {
                form(layer)
            } else {
                ContentUnavailableView("editor.layer.gone", systemImage: "square.dashed")
            }
        }
        .navigationTitle(model.layer(path).map { LayerRow.kind($0.wrappedValue.content) } ?? "editor.layers")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func form(_ layer: Binding<Layer>) -> some View {
        Form {
            Section(isTopLevel ? LocalizedStringKey("editor.layer.frame") : "editor.layer.size") {
                if isTopLevel {
                    NumberRow(title: "editor.layer.x", value: layer.frame.x, range: -50...400)
                    NumberRow(title: "editor.layer.y", value: layer.frame.y, range: -50...400)
                }
                NumberRow(title: "editor.layer.width", value: layer.frame.w, range: isTopLevel ? 1...400 : 0...400)
                NumberRow(title: "editor.layer.height", value: layer.frame.h, range: isTopLevel ? 1...400 : 0...400)
            }
            .accessibilityIdentifier("ax.editor.layer.frame")
            Section {
                LabeledContent {
                    Slider(value: Binding(get: { layer.wrappedValue.opacity ?? 1 }, set: { layer.wrappedValue.opacity = $0 >= 0.99 ? nil : $0 }),
                           in: 0.1...1)
                } label: {
                    Text("editor.layer.opacity")
                }
                if isTopLevel {
                    Toggle("editor.layer.mirror", isOn: Binding(get: { layer.wrappedValue.mirror == true },
                                                                set: { layer.wrappedValue.mirror = $0 ? true : nil }))
                }
            } footer: {
                if isTopLevel { Text("editor.layer.mirror.footer") }
            }
            kindSection(layer)
            Section {
                Button {
                    model.duplicateLayer(path)
                } label: {
                    Label("editor.layer.duplicate", systemImage: "plus.square.on.square")
                }
                if isTopLevel, case .stack = layer.wrappedValue.content, let index = path.first {
                    Button {
                        model.ungroupLayer(index)
                        dismiss()
                    } label: {
                        Label("editor.layer.ungroup", systemImage: "square.stack.3d.down.right")
                    }
                    .accessibilityIdentifier("ax.editor.layer.ungroup")
                }
                Button(role: .destructive) {
                    model.removeLayer(path)
                    dismiss()
                } label: {
                    Label("editor.layer.delete", systemImage: "trash")
                }
                .accessibilityIdentifier("ax.editor.layer.delete")
            }
        }
    }

    @ViewBuilder private func kindSection(_ layer: Binding<Layer>) -> some View {
        switch layer.wrappedValue.content {
        case .text(let text):
            TextSettings(text: Binding(get: { text }, set: { layer.wrappedValue.content = .text($0) }), model: model)
        case .icon(let icon):
            Section("editor.layer.kind.icon") {
                LabeledContent {
                    Text(verbatim: icon.symbol).foregroundStyle(.secondary)
                } label: {
                    Text("editor.layer.symbol")
                }
                NumberRow(title: "editor.layer.iconSize", value: Binding(get: { icon.size }, set: {
                    var changed = icon
                    changed.size = $0
                    layer.wrappedValue.content = .icon(changed)
                }), range: 4...200)
                ColorTokenPicker(title: "editor.layer.color", value: Binding(get: { icon.color }, set: {
                    var changed = icon
                    changed.color = $0
                    layer.wrappedValue.content = .icon(changed)
                }), model: model)
            }
        case .shape(let shape):
            Section("editor.layer.kind.shape") {
                Picker("editor.layer.shape", selection: Binding(get: { shape.kind }, set: {
                    var changed = shape
                    changed.kind = $0
                    layer.wrappedValue.content = .shape(changed)
                })) {
                    Text("editor.layer.shape.rect").tag(ShapeLayer.Kind.rect)
                    Text("editor.layer.shape.roundedRect").tag(ShapeLayer.Kind.roundedRect)
                    Text("editor.layer.shape.circle").tag(ShapeLayer.Kind.circle)
                    Text("editor.layer.shape.capsule").tag(ShapeLayer.Kind.capsule)
                }
                ColorTokenPicker(title: "editor.layer.fill", value: Binding(get: { shape.fill ?? "@accent" }, set: {
                    var changed = shape
                    changed.fill = $0
                    layer.wrappedValue.content = .shape(changed)
                }), model: model)
            }
        case .stack(let stack):
            StackSettings(stack: Binding(get: { stack }, set: { layer.wrappedValue.content = .stack($0) }))
            Section {
                NavigationLink {
                    LayersView(model: model, parent: path)
                } label: {
                    LabeledContent {
                        Text(verbatim: "\(stack.children.count)")
                    } label: {
                        Text("editor.layer.stack.items")
                    }
                }
                .accessibilityIdentifier("ax.editor.layer.items")
            }
        default:
            EmptyView()
        }
    }
}

/// A number with a stepper and a text field (canvas units).
private struct NumberRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                TextField(title, value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                          format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 70)
                Stepper(title, value: $value, in: range, step: 1)
                    .labelsHidden()
            }
        } label: {
            Text(title)
        }
    }
}

/// A text layer: both languages, size, weight, alignment, lines and color.
private struct TextSettings: View {
    @Binding var text: TextLayer
    let model: EditorModel

    var body: some View {
        Section {
            TextField(text: Binding(get: { text.value.resolved(language: "ar") }, set: { setValue(ar: $0) })) { Text("editor.arabic") }
                .environment(\.layoutDirection, .rightToLeft)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("ax.editor.layer.text.ar")
            TextField(text: Binding(get: { text.value.resolved(language: "en") }, set: { setValue(en: $0) })) { Text("editor.english") }
                .environment(\.layoutDirection, .leftToRight)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("ax.editor.layer.text.en")
            NumberRow(title: "editor.layer.fontSize", value: $text.font.size, range: SpecValidator.fontSizes)
            Picker("editor.layer.weight", selection: Binding(get: { text.font.weight ?? .regular }, set: { text.font.weight = $0 })) {
                ForEach(FontWeightName.allCases, id: \.self) { weight in
                    Text(verbatim: weight.rawValue).tag(weight)
                }
            }
            Picker("editor.layer.align", selection: Binding(get: { text.align ?? .leading }, set: { text.align = $0 })) {
                Text("editor.layer.align.leading").tag(TextAlign.leading)
                Text("editor.layer.align.center").tag(TextAlign.center)
                Text("editor.layer.align.trailing").tag(TextAlign.trailing)
            }
            Stepper(value: Binding(get: { text.maxLines ?? 1 }, set: { text.maxLines = $0 }), in: 1...6) {
                LabeledContent {
                    Text(verbatim: "\(text.maxLines ?? 1)")
                } label: {
                    Text("editor.layer.lines")
                }
            }
            ColorTokenPicker(title: "editor.layer.color", value: $text.color, model: model)
        } header: {
            Text("editor.layer.kind.text")
        } footer: {
            Text("editor.layer.text.footer")
        }
    }

    private func setValue(en: String? = nil, ar: String? = nil) {
        text.value = .localized(en: en ?? text.value.resolved(language: "en"), ar: ar ?? text.value.resolved(language: "ar"))
    }
}

/// A stack: direction, spacing, padding, alignment and grid columns.
private struct StackSettings: View {
    @Binding var stack: StackLayer

    var body: some View {
        Section("editor.layer.stack") {
            Picker("editor.layer.stack.axis", selection: $stack.axis) {
                Text("editor.layer.kind.column").tag(StackLayer.Axis.vertical)
                Text("editor.layer.kind.row").tag(StackLayer.Axis.horizontal)
                Text("editor.layer.kind.grid").tag(StackLayer.Axis.grid)
            }
            .onChange(of: stack.axis) { _, axis in
                stack.columns = axis == .grid ? (stack.columns ?? 2) : nil
                if axis == .grid { stack.children.removeAll { if case .spacer = $0.content { true } else { false } } }
            }
            NumberRow(title: "editor.layer.stack.spacing",
                      value: Binding(get: { stack.spacing ?? StackLayer.defaultSpacing }, set: { stack.spacing = $0 }), range: 0...100)
            NumberRow(title: "editor.layer.stack.padding", value: Binding(get: { stack.padding ?? 0 }, set: { stack.padding = $0 }),
                      range: 0...100)
            alignPicker("editor.layer.stack.alignItems", selection: Binding(
                get: { stack.alignItems ?? (stack.axis == .horizontal ? .center : .start) }, set: { stack.alignItems = $0 }))
            alignPicker("editor.layer.stack.justify", selection: Binding(get: { stack.justify ?? .start }, set: { stack.justify = $0 }))
            if stack.axis == .grid {
                Stepper(value: Binding(get: { stack.columns ?? 2 }, set: { stack.columns = $0 }), in: 1...8) {
                    LabeledContent {
                        Text(verbatim: "\(stack.columns ?? 2)")
                    } label: {
                        Text("editor.layer.stack.columns")
                    }
                }
            }
        }
    }

    private func alignPicker(_ title: LocalizedStringKey, selection: Binding<StackLayer.Align>) -> some View {
        Picker(title, selection: selection) {
            Text("editor.layer.stack.start").tag(StackLayer.Align.start)
            Text("editor.layer.stack.center").tag(StackLayer.Align.center)
            Text("editor.layer.stack.end").tag(StackLayer.Align.end)
        }
    }
}

/// A theme color (so the design's color pickers keep reaching it) or a custom one.
private struct ColorTokenPicker: View {
    let title: LocalizedStringKey
    @Binding var value: String
    let model: EditorModel
    static let tokens = ["fg", "muted", "accent", "bg", "onAccent"]

    var body: some View {
        Picker(title, selection: $value) {
            Text("editor.color.fg").tag("@fg")
            Text("editor.color.muted").tag("@muted")
            Text("editor.color.accent").tag("@accent")
            Text("editor.color.bg").tag("@bg")
            Text("editor.layer.color.onAccent").tag("@onAccent")
            if !Self.tokens.contains(String(value.dropFirst())) {
                Text("editor.layer.color.custom").tag(value)
            }
        }
        if !value.hasPrefix("@") {
            ColorPicker("editor.layer.color.custom", selection: Binding(
                get: { Color(hex: value) },
                set: { value = EditorModel.hex($0) }
            ), supportsOpacity: false)
        } else {
            Button("editor.layer.color.makeCustom") {
                value = SpecTokens.hex(String(value.dropFirst()), theme: model.design.effectiveTheme) ?? "#FFFFFF"
            }
        }
    }
}
