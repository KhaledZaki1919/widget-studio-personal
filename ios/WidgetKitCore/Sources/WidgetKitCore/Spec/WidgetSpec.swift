import Foundation

/// Widget Spec v1 (brief §4): one widget = this JSON + an optional user image, drawn by
/// `SpecRenderer`. Decoding ignores unknown keys. Unknown layer types decode as `.unknown`
/// and unknown enum values fail decoding; `SpecValidator` turns both into issues, never a crash.
public struct WidgetSpec: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var name: LocalizedText
    public var family: SpecFamily
    public var theme: SpecTheme
    public var refresh: RefreshPolicy
    public var background: Background
    public var fields: [FieldSpec]
    public var layers: [Layer]
    /// Library section (ADR-011); optional for specs that aren't templates.
    public var category: SpecCategory?
    /// Elements that look live but aren't, with why (prompt v5's wiring list, ADR-027).
    public var decorative: [DecorativeNote]?
    /// The card inside the widget (ADR-029); layer frames are in its canvas.
    public var card: CardSpec?

    /// The newest spec version this app reads (ADR-029). Version 1 files still open unchanged.
    public static let currentVersion = 2

    public init(schemaVersion: Int = 1, id: String, name: LocalizedText, family: SpecFamily,
                theme: SpecTheme = .dark, refresh: RefreshPolicy = .none, background: Background,
                fields: [FieldSpec] = [], layers: [Layer], category: SpecCategory? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.family = family
        self.theme = theme
        self.refresh = refresh
        self.background = background
        self.fields = fields
        self.layers = layers
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, specVersion, id, name, family, theme, refresh, background, fields, layers, category, decorative, card
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // ADR-029: AI replies write `specVersion`; saved designs and templates `schemaVersion`.
        if let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) {
            schemaVersion = version
        } else if let version = try container.decodeIfPresent(Int.self, forKey: .specVersion) {
            schemaVersion = version
        } else {
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        }
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(LocalizedText.self, forKey: .name)
        family = try container.decode(SpecFamily.self, forKey: .family)
        theme = try container.decodeIfPresent(SpecTheme.self, forKey: .theme) ?? .dark
        refresh = try container.decodeIfPresent(RefreshPolicy.self, forKey: .refresh) ?? .none
        background = try container.decode(Background.self, forKey: .background)
        fields = try container.decodeIfPresent([FieldSpec].self, forKey: .fields) ?? []
        layers = try container.decode([Layer].self, forKey: .layers)
        category = try container.decodeIfPresent(SpecCategory.self, forKey: .category)
        decorative = try container.decodeIfPresent([DecorativeNote].self, forKey: .decorative)
        card = try container.decodeIfPresent(CardSpec.self, forKey: .card)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(family, forKey: .family)
        try container.encode(theme, forKey: .theme)
        try container.encode(refresh, forKey: .refresh)
        try container.encode(background, forKey: .background)
        try container.encode(fields, forKey: .fields)
        try container.encode(layers, forKey: .layers)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(decorative, forKey: .decorative)
        try container.encodeIfPresent(card, forKey: .card)
    }

    public func field(_ key: String) -> FieldSpec? {
        fields.first { $0.key == key }
    }
}

/// Canvas units per family (brief §4.2).
public enum SpecFamily: String, Codable, Sendable, CaseIterable {
    /// `xlarge` (ADR-030): the 4 × 6 portrait widget of iOS 27 (systemExtraLargePortrait) and Android's XL size.
    case small, medium, large, xlarge

    public var canvas: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        case .xlarge: CGSize(width: 364, height: 570)
        }
    }

    /// Widget sizes a spec can fill (ADR-011): its own and every larger one. A spec drawn in a
    /// larger widget is scaled uniformly and centered on its background.
    public var supportedFamilies: [SpecFamily] {
        SpecFamily.allCases.filter { $0.rank >= rank }
    }

    /// small 0, medium 1, large 2, xlarge 3.
    public var rank: Int {
        switch self {
        case .small: 0
        case .medium: 1
        case .large: 2
        case .xlarge: 3
        }
    }
}

/// Template library sections (brief §6), in display order.
public enum SpecCategory: String, Codable, Sendable, CaseIterable {
    case time, weather, health, prayer, countdown, photo, tiles, counters, tasks

    public var title: LocalizedText {
        switch self {
        case .time: .localized(en: "Time", ar: "الوقت")
        case .weather: .localized(en: "Weather", ar: "الطقس")
        case .health: .localized(en: "Health", ar: "الصحة")
        case .prayer: .localized(en: "Prayer", ar: "الصلاة")
        case .countdown: .localized(en: "Countdown", ar: "العد التنازلي")
        case .photo: .localized(en: "Photo", ar: "صور")
        case .tiles: .localized(en: "Tiles", ar: "أزرار")
        case .counters: .localized(en: "Counters", ar: "عدّادات")
        case .tasks: .localized(en: "Tasks", ar: "المهام")
        }
    }
}

public enum SpecTheme: String, Codable, Sendable, CaseIterable {
    case light, dark
}

public enum RefreshPolicy: String, Codable, Sendable, CaseIterable {
    case none, minute, hourly, daily
}

/// A string, or `{ "en": …, "ar": … }`.
public enum LocalizedText: Codable, Sendable, Equatable, ExpressibleByStringLiteral {
    case plain(String)
    case localized(en: String, ar: String)

    public init(stringLiteral value: String) {
        self = .plain(value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .plain(text)
            return
        }
        let pair = try container.decode([String: String].self)
        guard let en = pair["en"], let ar = pair["ar"] else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "needs both \"en\" and \"ar\"")
        }
        self = .localized(en: en, ar: ar)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .plain(let text): try container.encode(text)
        case .localized(let en, let ar): try container.encode(["en": en, "ar": ar])
        }
    }

    /// Arabic for `ar*` language codes, English otherwise.
    public func resolved(language: String) -> String {
        switch self {
        case .plain(let text): text
        case .localized(let en, let ar): language.hasPrefix("ar") ? ar : en
        }
    }

    public var allValues: [String] {
        switch self {
        case .plain(let text): [text]
        case .localized(let en, let ar): [en, ar]
        }
    }
}

public struct Background: Codable, Sendable, Equatable {
    /// `glass` (eval 2026-11-02): a frosted panel, a translucent tint (`color`, default white at
    /// 18 %) with a sheen and a thin light border, for designs drawn as frosted cards.
    public enum Kind: String, Codable, Sendable, CaseIterable { case solid, gradient, glass }

    public var type: Kind
    public var color: String?
    public var colors: [String]?
    /// Degrees, 0 = left to right, 90 = top to bottom.
    public var angle: Double?
    /// Drawn behind circle templates, because a widget is always a rounded square (brief §2).
    public var outerColor: String?
    /// With `outerColor`: the card drawn inside the widget, `circle` (default, the largest
    /// centered circle) or `capsule` (ADR-024: circular and pill-shaped widgets from images).
    public var cardShape: CardShape?

    public enum CardShape: String, Codable, Sendable, CaseIterable { case circle, capsule }

    public init(type: Kind, color: String? = nil, colors: [String]? = nil, angle: Double? = nil, outerColor: String? = nil,
                cardShape: CardShape? = nil) {
        self.cardShape = cardShape
        self.type = type
        self.color = color
        self.colors = colors
        self.angle = angle
        self.outerColor = outerColor
    }

    public static func solid(_ color: String) -> Background { Background(type: .solid, color: color) }
}

/// A user-editable value (brief §4.3), referenced as `{{field.<key>}}`.
public struct FieldSpec: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case text, number, date, color, image, timezone, city, shortcut, url
        /// An SF Symbol from `Icons.whitelist` (tile icons, ADR-011).
        case icon
        /// ADR-029: an installed app the user picks (`{{app.<key>.icon}}`, `app.launch`), and a market
        /// ticker or coin (`{{stock.<key>.price}}`).
        case app, ticker
    }

    public var key: String
    public var type: Kind
    public var label: LocalizedText
    /// A string or `{en, ar}`. Dates are ISO 8601 (`2026-12-31` or `2026-12-31T20:00:00Z`).
    public var `default`: LocalizedText?

    public init(key: String, type: Kind, label: LocalizedText, default: LocalizedText? = nil) {
        self.key = key
        self.type = type
        self.label = label
        self.default = `default`
    }
}

public struct Frame: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    /// Clamped so the frame lies inside the canvas (brief §4.6).
    public func clamped(to canvas: CGSize) -> Frame {
        let width = min(max(w, 0), canvas.width)
        let height = min(max(h, 0), canvas.height)
        return Frame(
            x: min(max(x, 0), canvas.width - width),
            y: min(max(y, 0), canvas.height - height),
            w: width,
            h: height
        )
    }

    /// The same frame on the other side of the canvas (RTL `mirror`).
    public func mirrored(canvasWidth: Double) -> Frame {
        Frame(x: canvasWidth - x - w, y: y, w: w, h: h)
    }
}
