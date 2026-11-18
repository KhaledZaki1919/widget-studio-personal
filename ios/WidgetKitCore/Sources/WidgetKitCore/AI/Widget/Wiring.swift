import Foundation

/// What the layer editor changes (ADR-027): a layer's live value and what a tap on it does.
public enum Wiring {
    /// The catalog `layers` word for a layer that can show a live value; nil when it can't.
    public static func bindableKind(_ layer: Layer) -> String? {
        switch layer.content {
        case .text: "text"
        case .ring: "ring"
        case .progressBar: "progressBar"
        case .dotGrid: "dotGrid"
        case .icon: "icon"
        default: nil
        }
    }

    /// Bindings a layer of this kind can show, by catalog group.
    public static func bindings(for kind: String) -> [Capability] {
        Capabilities.bindings.filter { !$0.parametric && $0.layers.contains(kind) && ($0.ai || kind == "when") }
    }

    /// The id a layer shows now, when it is exactly one binding.
    public static func binding(of layer: Layer) -> String? {
        let text: String?
        switch layer.content {
        case .text(let content): text = content.value.resolved(language: "en")
        case .ring(let content): text = content.progress
        case .progressBar(let content): text = content.progress
        case .dotGrid(let content): text = content.values
        case .icon(let content): text = content.symbol
        default: text = nil
        }
        return text.flatMap(Bindings.soleBinding)?.trimmingCharacters(in: .whitespaces)
    }

    /// Shows `id` on `layer`; progress on a nil id falls back to 0.
    public static func setBinding(_ id: String?, on layer: inout Layer) {
        let template = id.map { "{{\($0)}}" }
        switch layer.content {
        case .text(var content):
            content.value = template.map { .localized(en: $0, ar: $0) } ?? content.value
            layer.content = .text(content)
        case .ring(var content):
            content.progress = template ?? "0"
            layer.content = .ring(content)
        case .progressBar(var content):
            content.progress = template ?? "0"
            layer.content = .progressBar(content)
        case .dotGrid(var content):
            content.values = template ?? String(repeating: "0", count: max(content.rows * content.cols, 1))
            layer.content = .dotGrid(content)
        case .icon(var content):
            content.symbol = template ?? content.symbol
            layer.content = .icon(content)
        default:
            break
        }
    }

    /// The layer's frame on the canvas: stack children by estimate.
    public static func frame(at path: LayerEditing.Path, in spec: WidgetSpec) -> Frame? {
        AutoWire.walk(spec.layers).first { $0.path == path }?.frame
    }

    /// The top-level button over a layer (its own, when the layer is a button).
    public static func button(over path: LayerEditing.Path, in spec: WidgetSpec) -> (index: Int, button: ButtonLayer)? {
        if path.count == 1, case .button(let button)? = LayerEditing.layer(at: path, in: spec.layers)?.content { return (path[0], button) }
        guard let frame = frame(at: path, in: spec) else { return nil }
        for (index, layer) in spec.layers.enumerated().reversed() {
            if case .button(let button) = layer.content, AutoWire.Run.inside(frame, layer.frame) { return (index, button) }
        }
        return nil
    }

    /// What a tap on the layer does: the action id, or nil to remove it. A value-taking action gets
    /// a field for its value, which the editor's Fields section then edits.
    public static func setAction(_ id: String?, arg: String? = nil, over path: LayerEditing.Path, in spec: inout WidgetSpec) {
        let existing = button(over: path, in: spec)
        guard let id, let capability = Capabilities.action(id) else {
            if let existing { spec.layers.remove(at: existing.index) }
            return
        }
        var value = arg
        if let kind = capability.argFieldKind {
            let base = kind == .shortcut ? "shortcut" : kind == .url ? "link" : "value"
            var number = 1
            while spec.field("\(base)\(number)") != nil { number += 1 }
            let key = "\(base)\(number)"
            spec.fields.append(FieldSpec(key: key, type: kind, label: capability.title, default: kind == .url ? nil : .plain("")))
            value = "{{field.\(key)}}"
        }
        let button = ButtonLayer(action: ButtonLayer.Action(rawValue: id), arg: value)
        if let existing {
            spec.layers[existing.index].content = .button(button)
        } else if let frame = frame(at: path, in: spec) {
            spec.layers.append(Layer(frame: AutoWire.Run.padded(frame), content: .button(button)))
        }
    }
}
