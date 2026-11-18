import Foundation

/// `{{name}}` placeholders (brief §4.5). Only the names in `Bindings.isKnown` are allowed;
/// anything else is a validation error.
public enum Bindings {
    /// What a binding yields, which decides where it may be used.
    public enum Kind: Sendable, Equatable {
        case text
        /// A number; `ring` uses it as progress 0…1.
        case number
        /// An array of levels 0…1 (`dotGrid`, `dotBars`).
        case levels
        case date
        /// An SF Symbol name (`icon`).
        case symbol
        /// A picture (`image` layers, `{{media.artwork}}`).
        case image
    }

    public enum Group: String, Sendable, CaseIterable {
        case time, weather, health, app, prayer, location, device, field, calendar, reminders, tasks, media, audio, system
    }

    /// Built from `capabilities.json` (ADR-027); never list bindings by hand. Parametric entries
    /// (`field.<key>`, `days.<key>`, `tz.<key>.time`) are parsed by `Name` instead.
    static let catalog: [String: (Kind, Group)] = Dictionary(uniqueKeysWithValues: Capabilities.bindings
        .filter { !$0.parametric }
        .map { ($0.id, ($0.bindingKind, Group(rawValue: $0.group) ?? .app)) })

    /// A parsed binding name.
    public enum Name: Sendable, Equatable {
        case builtin(String)
        /// `field.<key>`
        case field(String)
        /// `tz.<fieldKey>.time`: the current time in a timezone field.
        case timezoneTime(String)
        /// `days.<dateFieldKey>`: whole days from today to a date field (ADR-011).
        case daysUntil(String)
        /// `app.<appFieldKey>.icon`: the icon of an app the user picks (ADR-029).
        case appIcon(String)
        /// `stock.<tickerFieldKey>.<part>`: price, change, changePct or series of a ticker field (ADR-029).
        case stock(String, String)

        public static let stockParts = ["price", "change", "changePct", "series"]

        public init?(_ raw: String) {
            let name = raw.trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("field.") {
                let key = String(name.dropFirst("field.".count))
                guard Bindings.isValidKey(key) else { return nil }
                self = .field(key)
            } else if name.hasPrefix("days.") {
                let key = String(name.dropFirst("days.".count))
                guard Bindings.isValidKey(key) else { return nil }
                self = .daysUntil(key)
            } else if name.hasPrefix("tz."), name.hasSuffix(".time"), name.count > "tz..time".count {
                let key = String(name.dropFirst(3).dropLast(5))
                guard Bindings.isValidKey(key) else { return nil }
                self = .timezoneTime(key)
            } else if name.hasPrefix("app."), name.hasSuffix(".icon"), name.count > "app..icon".count {
                let key = String(name.dropFirst(4).dropLast(5))
                guard Bindings.isValidKey(key) else { return nil }
                self = .appIcon(key)
            } else if name.hasPrefix("stock."), case let parts = name.split(separator: ".").map(String.init), parts.count == 3,
                      Bindings.isValidKey(parts[1]), Name.stockParts.contains(parts[2]) {
                self = .stock(parts[1], parts[2])
            } else if Bindings.catalog[name] != nil {
                self = .builtin(name)
            } else {
                return nil
            }
        }

        public var group: Group {
            switch self {
            case .builtin(let name): Bindings.catalog[name]?.1 ?? .field
            case .field: .field
            case .timezoneTime, .daysUntil: .time
            case .appIcon: .media
            case .stock: .app
            }
        }

        /// Field bindings take their kind from the field type; see `SpecValidator`.
        public var builtinKind: Kind? {
            switch self {
            case .builtin(let name): Bindings.catalog[name]?.0
            case .timezoneTime: .text
            case .daysUntil: .number
            case .appIcon: .image
            case .stock(_, let part): part == "series" ? Kind.levels : Kind.number
            case .field: nil
            }
        }
    }

    /// Field keys: letters, digits and underscores, starting with a letter.
    public static func isValidKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, CharacterSet.letters.contains(first) else { return false }
        return key.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") }
    }

    /// One piece of a template string.
    public enum Token: Equatable, Sendable {
        case literal(String)
        /// The raw text between `{{` and `}}`.
        case binding(String)
    }

    /// Splits `"{{weather.temp}}°"` into tokens. An unclosed `{{` stays literal text.
    public static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var rest = Substring(text)
        while let open = rest.range(of: "{{") {
            guard let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) else { break }
            if open.lowerBound > rest.startIndex { tokens.append(.literal(String(rest[..<open.lowerBound]))) }
            tokens.append(.binding(String(rest[open.upperBound..<close.lowerBound])))
            rest = rest[close.upperBound...]
        }
        if !rest.isEmpty { tokens.append(.literal(String(rest))) }
        return tokens
    }

    /// The raw names of all bindings in `text`.
    public static func names(in text: String) -> [String] {
        tokenize(text).compactMap { token in
            if case .binding(let name) = token { return name }
            return nil
        }
    }

    /// The single binding when `text` is exactly `{{name}}`.
    public static func soleBinding(_ text: String) -> String? {
        let tokens = tokenize(text.trimmingCharacters(in: .whitespaces))
        guard tokens.count == 1, case .binding(let name) = tokens[0] else { return nil }
        return name
    }
}
