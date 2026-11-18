import Foundation

/// The AI schema as a short, readable reference for "Use another AI" (ADR-029). The JSON Schema goes
/// to providers through structured output / tool definitions; pasted into a chat, its 30 000-character
/// single line was unreadable for models (PDF: "the schema inside the text"), so the copied
/// instructions carry this rendering of the same schema instead: one line per layer type, `?` for
/// optional properties, limits written out. Built from `AIWidgetSchema`, never by hand.
public enum AISchemaReference {
    public static func text(_ schema: JSONValue) -> String {
        guard case .object(let root) = schema, case .object(let properties)? = root["properties"] else { return "" }
        var lines = ["Widget object (\"?\" marks a property you may leave out or set to null):", "{"]
        for key in order(properties.keys) where key != "layers" {
            guard let value = properties[key] else { continue }
            lines.append("  \(key)\(isNullable(value) ? "?" : ""): \(render(value, depth: 1))")
        }
        lines.append("  layers: Layer[] (1 to \(SpecValidator.maxLayers) drawn layers plus buttons; the first is drawn at the bottom)")
        lines.append("}")
        if case .object(let layers)? = properties["layers"], case .object(let items)? = layers["items"],
           case .array(let shapes)? = items["anyOf"] {
            lines.append("")
            lines.append("Layer, one of (every top-level layer also has frame {x, y, w, h}, opacity?, mirror?, when?, rotation?):")
            for shape in shapes { lines.append("- " + layerLine(shape)) }
            // Stack children, once (they have no frame, an optional width and height).
            if let stack = shapes.first(where: { layerType($0) == "stack" }), case .object(let object) = stack,
               case .object(let properties)? = object["properties"], case .object(let children)? = properties["children"],
               case .object(let items)? = children["items"], case .array(let kinds)? = items["anyOf"] {
                lines.append("")
                lines.append("Child, one of (inside a stack: no frame; width?, height?, when?, rotation?):")
                for kind in kinds { lines.append("- " + layerLine(kind, skip: ["type", "width", "height", "when", "rotation"])) }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func layerType(_ shape: JSONValue) -> String? {
        guard case .object(let object) = shape, case .object(let properties)? = object["properties"] else { return nil }
        return properties["type"].flatMap(enumValues)?.first
    }

    /// Keys in a reading order: what the model writes first comes first.
    static func order(_ keys: Dictionary<String, JSONValue>.Keys) -> [String] {
        let first = ["specVersion", "inventory", "wiring", "name", "family", "theme", "card", "palette", "background", "fields"]
        return first.filter(keys.contains) + keys.filter { !first.contains($0) }.sorted()
    }

    static func layerLine(_ shape: JSONValue, skip: Set<String> = ["type", "frame", "opacity", "mirror", "when", "rotation"]) -> String {
        guard case .object(let object) = shape, case .object(let properties)? = object["properties"] else { return render(shape, depth: 0) }
        let type = layerType(shape) ?? "?"
        let fields = order(properties.keys).filter { !skip.contains($0) }.compactMap { key -> String? in
            guard let value = properties[key] else { return nil }
            if key == "children" { return "children: Child[] (1–\(SpecValidator.maxChildren))" }
            return "\(key)\(isNullable(value) ? "?" : ""): \(render(value, depth: 1))"
        }
        return "\(type) { \(fields.joined(separator: ", ")) }"
    }

    static func isNullable(_ value: JSONValue) -> Bool {
        guard case .object(let object) = value else { return false }
        if case .array(let types)? = object["type"], types.contains(.string("null")) { return true }
        if case .array(let options)? = object["anyOf"], options.contains(["type": "null"]) { return true }
        return false
    }

    static func enumValues(_ value: JSONValue) -> [String]? {
        guard case .object(let object) = value, case .array(let values)? = object["enum"] else { return nil }
        return values.compactMap(\.stringValue)
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func render(_ value: JSONValue, depth: Int) -> String {
        guard case .object(let object) = value else { return "any" }
        if let values = enumValues(value) {
            if values.count > 14 { return "string (an id from the catalog)" }
            return values.map { "\"\($0)\"" }.joined(separator: " | ")
        }
        if case .array(let options)? = object["anyOf"] {
            let parts = options.filter { $0 != ["type": "null"] }.map { render($0, depth: depth) }
            return parts.joined(separator: " | ")
        }
        let types: [String] = {
            switch object["type"] {
            case .string(let type)?: return [type]
            case .array(let list)?: return list.compactMap(\.stringValue).filter { $0 != "null" }
            default: return []
            }
        }()
        let range = bounds(object)
        switch types.first {
        case "object":
            guard case .object(let properties)? = object["properties"] else { return "{}" }
            if depth > 5 { return "{…}" }
            let fields = order(properties.keys).compactMap { key -> String? in
                guard let item = properties[key] else { return nil }
                return "\(key)\(isNullable(item) ? "?" : ""): \(render(item, depth: depth + 1))"
            }
            return "{ " + fields.joined(separator: ", ") + " }"
        case "array":
            let item = object["items"].map { render($0, depth: depth + 1) } ?? "any"
            let wrapped = item.contains(" ") && !item.hasPrefix("{") ? "(\(item))" : item
            var counts = ""
            switch (object["minItems"], object["maxItems"]) {
            case (.int(let low)?, .int(let high)?): counts = low == high ? " (\(low))" : " (\(low)–\(high))"
            case (nil, .int(let high)?): counts = " (up to \(high))"
            default: break
            }
            return wrapped + "[]" + counts
        case "string":
            if case .string(let pattern)? = object["pattern"] { return "string matching \(pattern)" }
            return "string"
        case "integer", "number":
            return (types.first ?? "number") + range
        case "boolean":
            return "boolean"
        default:
            return types.first ?? "any"
        }
    }

    static func bounds(_ object: [String: JSONValue]) -> String {
        func text(_ value: JSONValue?) -> String? {
            switch value {
            case .int(let number)?: return String(number)
            case .number(let number)?: return number.rounded() == number ? String(Int(number)) : String(number)
            default: return nil
            }
        }
        guard let low = text(object["minimum"]), let high = text(object["maximum"]) else { return "" }
        return " \(low)–\(high)"
    }
}
