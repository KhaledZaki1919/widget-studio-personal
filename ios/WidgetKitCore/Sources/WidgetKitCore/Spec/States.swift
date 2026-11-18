import Foundation

/// A layer with "soul" (ADR-028): one look per state, chosen by real data. `set` takes its variants
/// from the catalog's built-in state sets; `variants` writes them out, or customizes a set. The
/// first variant whose `when` holds is drawn, and one without `when` is the default. Coordinates
/// inside a variant are relative to `box`, which is fitted into the layer's frame.
public struct StatesLayer: Codable, Sendable, Equatable {
    public struct Variant: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var title: LocalizedText?
        /// A `SpecExpression`; nil = the default.
        public var when: String?
        public var layers: [Layer]
        /// Binding values that put the widget in this state, for the editor's preview and the
        /// renders; in a set, `$value` stands for the layer's `value`.
        public var sample: [String: String]?

        public init(id: String, title: LocalizedText? = nil, when: String? = nil, layers: [Layer], sample: [String: String]? = nil) {
            self.id = id
            self.title = title
            self.when = when
            self.layers = layers
            self.sample = sample
        }
    }

    /// A built-in set's id (`battery.mood`).
    public var set: String?
    /// The binding a set follows, for sets that take one (`{{tasks.1.done}}`).
    public var value: String?
    /// Colors the set's art uses.
    public var color: String
    public var accent: String
    public var dim: String
    /// Width and height of the variants' coordinate space; nil = the frame itself.
    public var box: [Double]?
    public var variants: [Variant]?

    public init(set: String? = nil, value: String? = nil, color: String = "@fg", accent: String = "@accent", dim: String = "@dim",
                box: [Double]? = nil, variants: [Variant]? = nil) {
        self.set = set
        self.value = value
        self.color = color
        self.accent = accent
        self.dim = dim
        self.box = box
        self.variants = variants
    }

    enum CodingKeys: String, CodingKey { case set, value, color, accent, dim, box, variants }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        set = try values.decodeIfPresent(String.self, forKey: .set)
        value = try values.decodeIfPresent(String.self, forKey: .value)
        color = try values.decodeIfPresent(String.self, forKey: .color) ?? "@fg"
        accent = try values.decodeIfPresent(String.self, forKey: .accent) ?? "@accent"
        dim = try values.decodeIfPresent(String.self, forKey: .dim) ?? "@dim"
        box = try values.decodeIfPresent([Double].self, forKey: .box)
        variants = try values.decodeIfPresent([Variant].self, forKey: .variants)
    }

    /// The variants to choose from: written out, or the set's with this layer's colors and value.
    public var expanded: [Variant] {
        if let variants { return variants }
        guard let set else { return [] }
        return StateSets.variants(of: set, value: value ?? "", color: color, accent: accent, dim: dim)
    }

    /// The coordinate space of the variants.
    public func boxSize(frame: Frame) -> (w: Double, h: Double) {
        let own = box ?? set.flatMap { Capabilities.stateSet($0)?.box }
        if let own, own.count == 2, own[0] > 0, own[1] > 0 { return (own[0], own[1]) }
        return (max(frame.w, 1), max(frame.h, 1))
    }

    /// Names this layer's states in a render's forced states (the editor's preview).
    public var key: String { self.set ?? variants?.first?.id ?? "states" }
}

/// One built-in state set of `capabilities.json` (ADR-028).
public struct StateSet: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: LocalizedText
    public let description: String
    public let box: [Double]
    /// An example of the binding the set follows; nil for a set with its own bindings.
    public let value: String?
    /// The capability prefix the set belongs to (`battery`, `weather`).
    public let topic: String?
    public let needs: [String]
    public let keywords: [String]
    /// Text glyphs that show one frozen look of this set (an emoji face).
    public let glyphs: [String]
    public let variants: [StatesLayer.Variant]

    enum CodingKeys: String, CodingKey { case id, title, description, box, value, topic, needs, keywords, glyphs, variants }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(LocalizedText.self, forKey: .title)
        description = try values.decode(String.self, forKey: .description)
        box = try values.decode([Double].self, forKey: .box)
        value = try values.decodeIfPresent(String.self, forKey: .value)
        topic = try values.decodeIfPresent(String.self, forKey: .topic)
        needs = try values.decodeIfPresent([String].self, forKey: .needs) ?? []
        keywords = try values.decodeIfPresent([String].self, forKey: .keywords) ?? []
        glyphs = try values.decodeIfPresent([String].self, forKey: .glyphs) ?? []
        variants = try values.decode([StatesLayer.Variant].self, forKey: .variants)
    }
}

public enum StateSets {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: [StatesLayer.Variant]] = [:]

    /// A set's variants with its placeholders filled in. A spec's tokens are already resolved by
    /// the time this runs, so colors arrive as hex (or as tokens in the editor's copy). Cached,
    /// because a timeline renders the same layer up to 60 times.
    static func variants(of id: String, value: String, color: String, accent: String, dim: String) -> [StatesLayer.Variant] {
        let key = [id, value, color, accent, dim].joined(separator: "|")
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        guard let set = Capabilities.stateSet(id), let data = try? JSONEncoder().encode(set.variants),
              var json = String(data: data, encoding: .utf8) else { return [] }
        // `value` is a binding like {{a.b}}: inside JSON strings it needs no escaping.
        json = json.replacingOccurrences(of: "\"$color\"", with: "\"\(color)\"")
            .replacingOccurrences(of: "\"$accent\"", with: "\"\(accent)\"")
            .replacingOccurrences(of: "\"$dim\"", with: "\"\(dim)\"")
            .replacingOccurrences(of: "$value", with: value)
        let variants = (try? JSONDecoder().decode([StatesLayer.Variant].self, from: Data(json.utf8))) ?? []
        cache[key] = variants
        return variants
    }
}

/// What kind of weather a condition icon shows (`{{weather.kind}}`), so conditions never compare
/// translated text.
public enum WeatherKind {
    public static func of(symbol: String) -> String {
        switch symbol {
        case "sun.max.fill", "moon.fill", "moon.stars.fill": "clear"
        case "cloud.sun.fill", "cloud.moon.fill": "partlyCloudy"
        case "cloud.fog.fill": "fog"
        case "cloud.drizzle.fill", "cloud.rain.fill", "cloud.heavyrain.fill": "rain"
        case "cloud.snow.fill": "snow"
        case "cloud.bolt.rain.fill": "storm"
        default: "cloudy"
        }
    }
}

extension BindingResolver {
    /// The variant to draw now: the one the render forces, else the first whose `when` holds.
    public func variant(of states: StatesLayer) -> StatesLayer.Variant? {
        let variants = states.expanded
        if let forced = context.forcedStates[states.key], let variant = variants.first(where: { $0.id == forced }) { return variant }
        return variants.first { variant in variant.when.map(isSatisfied) ?? true }
    }

    /// The overrides that put a layer's widget in `variant`.
    public static func overrides(for variant: StatesLayer.Variant, of states: StatesLayer) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in variant.sample ?? [:] {
            // A set's `$value` key arrives as the layer's own binding.
            result[(Bindings.soleBinding(key) ?? key).trimmingCharacters(in: .whitespaces)] = value
        }
        return result
    }

    /// A value forced by `RenderContext.overrides`, typed by the catalog.
    func overridden(_ name: String) -> Value? {
        guard let raw = context.overrides[name] else { return nil }
        guard let capability = Capabilities.binding(name), capability.type == "number", let number = Double(raw) else { return .text(raw) }
        return .number(number, display: capability.isShare ? String(Int((number * 100).rounded())) : raw)
    }
}
