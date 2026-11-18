import Foundation

/// A JSON value for provider request bodies, JSON Schemas and AI replies (ported from Lakhas).
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// The same value without `null` object members (array items stay), so optional spec
    /// properties a strict schema forced the model to write as `null` disappear.
    public func removingNulls() -> JSONValue {
        switch self {
        case .object(let object):
            return .object(object.filter { $0.value != .null }.mapValues { $0.removingNulls() })
        case .array(let items):
            return .array(items.map { $0.removingNulls() })
        default:
            return self
        }
    }

    /// Compact JSON with sorted keys (stable for prompts and tests).
    public func jsonString() -> String {
        String(bytes: jsonData(), encoding: .utf8) ?? "{}"
    }

    public func jsonData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("{}".utf8)
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

/// Helpers for strict JSON Schemas: every object lists all properties as required and sets
/// `additionalProperties: false` (OpenAI strict mode, Anthropic strict tools). Optional values
/// are nullable instead of missing.
public enum JSONSchema {
    public static func object(_ properties: [String: JSONValue]) -> JSONValue {
        [
            "type": "object",
            "properties": .object(properties),
            "required": .array(properties.keys.sorted().map { .string($0) }),
            "additionalProperties": false,
        ]
    }

    /// ADR-029: the validator's limits are mirrored in the schema (`minItems`, `maxItems`, `minimum`, `maximum`, `pattern`).
    public static func array(_ items: JSONValue, minItems: Int? = nil, maxItems: Int? = nil) -> JSONValue {
        var schema: [String: JSONValue] = ["type": "array", "items": items]
        if let minItems { schema["minItems"] = .int(minItems) }
        if let maxItems { schema["maxItems"] = .int(maxItems) }
        return .object(schema)
    }

    public static let string: JSONValue = ["type": "string"]
    public static let number: JSONValue = ["type": "number"]
    public static let integer: JSONValue = ["type": "integer"]
    public static let boolean: JSONValue = ["type": "boolean"]

    public static func number(minimum: Double, maximum: Double) -> JSONValue {
        ["type": "number", "minimum": .number(minimum), "maximum": .number(maximum)]
    }

    public static func integer(minimum: Int, maximum: Int) -> JSONValue {
        ["type": "integer", "minimum": .int(minimum), "maximum": .int(maximum)]
    }

    public static func string(pattern: String) -> JSONValue {
        ["type": "string", "pattern": .string(pattern)]
    }

    public static func enumeration(_ values: [String]) -> JSONValue {
        ["type": "string", "enum": .array(values.map { .string($0) })]
    }

    /// The same schema, also accepting `null` (a type union; Gemini gets `nullable: true`).
    public static func nullable(_ schema: JSONValue) -> JSONValue {
        guard case .object(var fields) = schema else { return schema }
        // A union (ADR-029: a string or {en, ar}, a color or a gradient) takes null as one more option.
        if case .array(let options)? = fields["anyOf"] {
            if !options.contains(["type": "null"]) { fields["anyOf"] = .array(options + [["type": "null"]]) }
            return .object(fields)
        }
        switch fields["type"] {
        case .string(let type)?:
            fields["type"] = [.string(type), "null"]
        case .array(let types)? where !types.contains("null"):
            fields["type"] = .array(types + ["null"])
        default:
            break
        }
        if case .array(let values)? = fields["enum"], !values.contains(.null) {
            fields["enum"] = .array(values + [.null])
        }
        return .object(fields)
    }

    /// One of several object shapes.
    public static func anyOf(_ schemas: [JSONValue]) -> JSONValue {
        ["anyOf": .array(schemas)]
    }
}
