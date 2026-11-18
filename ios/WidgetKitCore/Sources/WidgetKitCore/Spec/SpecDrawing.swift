import Foundation

// ADR-029: the drawing tools image-to-widget needed (docs/feedback/image-to-widget-issues.pdf).
// Every type here has a twin in android/.../spec/Spec.kt; both renderers draw it.

/// `upper` or `lower`, applied to a text after its bindings resolve.
public enum TextCase: String, Codable, Sendable, CaseIterable { case upper, lower }

/// Filled or outlined symbols (`cloud.fill` or `cloud`).
public enum IconStyle: String, Codable, Sendable, CaseIterable { case fill, outline }

/// One run of a text with its own look. Unset properties take the layer's.
public struct TextSpan: Codable, Sendable, Equatable {
    public var text: LocalizedText
    public var font: FontSpec?
    public var color: String?
    /// Canvas units up (a raised "AM", a superscript °).
    public var baselineOffset: Double?
    public var textCase: TextCase?
    public var tracking: Double?

    enum CodingKeys: String, CodingKey {
        case text, font, color, baselineOffset, tracking
        case textCase = "case"
    }

    public init(text: LocalizedText, font: FontSpec? = nil, color: String? = nil, baselineOffset: Double? = nil) {
        self.text = text
        self.font = font
        self.color = color
        self.baselineOffset = baselineOffset
    }

    /// The runs' text, joined per language.
    public static func joined(_ spans: [TextSpan]) -> LocalizedText {
        let en = spans.map { $0.text.resolved(language: "en") }.joined()
        let ar = spans.map { $0.text.resolved(language: "ar") }.joined()
        return en == ar ? .plain(en) : .localized(en: en, ar: ar)
    }
}

/// Text along a circle centered in the frame: `radius` in canvas units (default: half the smaller side
/// minus the font size), `start` the angle of the text's middle in degrees clockwise from 12 o'clock
/// (default 0, the top), `inside` true reads along the inside (text at the bottom stays upright).
public struct TextPath: Codable, Sendable, Equatable {
    public var arc: Double?
    public var start: Double?
    public var inside: Bool?

    public init(arc: Double? = nil, start: Double? = nil, inside: Bool? = nil) {
        self.arc = arc
        self.start = start
        self.inside = inside
    }
}

/// A gradient fill for shapes and charts.
public struct SpecGradient: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case linear, radial }

    public var type: Kind
    /// 2…4 colors.
    public var colors: [String]
    /// Linear: degrees, 0 = left to right, 90 = top to bottom (like the background).
    public var angle: Double?

    public init(type: Kind, colors: [String], angle: Double? = nil) {
        self.type = type
        self.colors = colors
        self.angle = angle
    }
}

/// Values written as a number (`45`) or a string (`"{{qibla.bearing}}"`).
enum SpecNumberOrString {
    static func decode<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> String? {
        if let number = try? container.decodeIfPresent(Double.self, forKey: key) {
            return number.rounded() == number && abs(number) < 1e9 ? String(Int(number)) : String(number)
        }
        return try container.decodeIfPresent(String.self, forKey: key)
    }
}

/// The knob on a progress bar's end (a music scrubber).
public struct ProgressKnob: Codable, Sendable, Equatable {
    /// Diameter in canvas units (default: twice the bar's thickness).
    public var size: Double?
    public var color: String?

    public init(size: Double? = nil, color: String? = nil) {
        self.size = size
        self.color = color
    }
}

// MARK: - Chart

/// A chart of one series (ADR-029): heart rate, steps per hour, sleep stages, prices.
/// `values` is a series binding (`{{heart.today}}`) or a literal: numbers separated by commas; for
/// `candles`, `low:high` pairs. The y range is `min`…`max`, else the data's own.
public struct ChartLayer: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case line, area, bars, steps, candles }
    public enum Highlight: String, Codable, Sendable, CaseIterable { case none, last, max, min }

    public var kind: Kind
    public var values: String
    public var color: String
    /// Under a line or area, or the bars: a color or a gradient (default: `color` at 25 % for areas).
    public var fill: String?
    public var gradient: SpecGradient?
    /// Line width (default 2); bar and candle width share of a slot (0.1…1, default 0.6).
    public var lineWidth: Double?
    public var barWidth: Double?
    public var cornerRadius: Double?
    /// A dashed reference line: a number, `first` (the first value, like a stock's open) or `average`.
    public var baseline: String?
    public var baselineColor: String?
    public var min: Double?
    public var max: Double?
    /// One point or bar drawn in `highlightColor` (with a dot on lines).
    public var highlight: Highlight?
    public var highlightColor: String?
    /// Comma-separated labels under the chart (spread evenly) and on its leading side (top to bottom).
    public var xLabels: LocalizedText?
    public var yLabels: LocalizedText?
    public var labelFont: FontSpec?
    public var labelColor: String?
    /// Values below/above the baseline in these colors (a stock's red and green).
    public var downColor: String?
    /// Round line joins and a smoothed curve.
    public var smooth: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, values, color, fill, lineWidth, barWidth, cornerRadius, baseline, baselineColor, min, max, highlight,
             highlightColor, xLabels, yLabels, labelFont, labelColor, downColor, smooth
    }

    public init(kind: Kind, values: String, color: String) {
        self.kind = kind
        self.values = values
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        values = try SpecNumberOrString.decode(container, forKey: .values) ?? ""
        color = try container.decode(String.self, forKey: .color)
        if let gradient = try? container.decodeIfPresent(SpecGradient.self, forKey: .fill) {
            self.gradient = gradient
        } else {
            fill = try container.decodeIfPresent(String.self, forKey: .fill)
        }
        lineWidth = try container.decodeIfPresent(Double.self, forKey: .lineWidth)
        barWidth = try container.decodeIfPresent(Double.self, forKey: .barWidth)
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius)
        baseline = try SpecNumberOrString.decode(container, forKey: .baseline)
        baselineColor = try container.decodeIfPresent(String.self, forKey: .baselineColor)
        min = try container.decodeIfPresent(Double.self, forKey: .min)
        max = try container.decodeIfPresent(Double.self, forKey: .max)
        highlight = try container.decodeIfPresent(Highlight.self, forKey: .highlight)
        highlightColor = try container.decodeIfPresent(String.self, forKey: .highlightColor)
        xLabels = try container.decodeIfPresent(LocalizedText.self, forKey: .xLabels)
        yLabels = try container.decodeIfPresent(LocalizedText.self, forKey: .yLabels)
        labelFont = try container.decodeIfPresent(FontSpec.self, forKey: .labelFont)
        labelColor = try container.decodeIfPresent(String.self, forKey: .labelColor)
        downColor = try container.decodeIfPresent(String.self, forKey: .downColor)
        smooth = try container.decodeIfPresent(Bool.self, forKey: .smooth)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(values, forKey: .values)
        try container.encode(color, forKey: .color)
        if let gradient {
            try container.encode(gradient, forKey: .fill)
        } else {
            try container.encodeIfPresent(fill, forKey: .fill)
        }
        try container.encodeIfPresent(lineWidth, forKey: .lineWidth)
        try container.encodeIfPresent(barWidth, forKey: .barWidth)
        try container.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
        try container.encodeIfPresent(baseline, forKey: .baseline)
        try container.encodeIfPresent(baselineColor, forKey: .baselineColor)
        try container.encodeIfPresent(min, forKey: .min)
        try container.encodeIfPresent(max, forKey: .max)
        try container.encodeIfPresent(highlight, forKey: .highlight)
        try container.encodeIfPresent(highlightColor, forKey: .highlightColor)
        try container.encodeIfPresent(xLabels, forKey: .xLabels)
        try container.encodeIfPresent(yLabels, forKey: .yLabels)
        try container.encodeIfPresent(labelFont, forKey: .labelFont)
        try container.encodeIfPresent(labelColor, forKey: .labelColor)
        try container.encodeIfPresent(downColor, forKey: .downColor)
        try container.encodeIfPresent(smooth, forKey: .smooth)
    }

    /// Candles: `low:high` pairs; anything else: one number per point.
    public static func parse(_ text: String) -> [ChartPoint]? {
        let items = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !items.isEmpty, items.count <= 400 else { return nil }
        var points: [ChartPoint] = []
        for item in items {
            let parts = item.split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 {
                points.append(ChartPoint(low: Swift.min(parts[0], parts[1]), high: Swift.max(parts[0], parts[1])))
            } else if parts.count == 1, item.split(separator: ":").count == 1 {
                points.append(ChartPoint(low: parts[0], high: parts[0]))
            } else {
                return nil
            }
        }
        return points
    }
}

/// One chart point: a value (`low == high`) or a candle's range.
public struct ChartPoint: Sendable, Equatable {
    public let low: Double
    public let high: Double

    public var value: Double { high }

    public init(low: Double, high: Double) {
        self.low = low
        self.high = high
    }
}

// MARK: - Card

/// The widget's card inside the widget (ADR-029): its shape, its own aspect ratio and position, so a
/// tall pill or a wide strip keeps the source's proportions. Layer frames are in the card's own
/// canvas (`WidgetSpec.canvas`), and the widget around the card shows `outerColor`.
public struct CardSpec: Codable, Sendable, Equatable {
    public enum Shape: String, Codable, Sendable, CaseIterable { case roundedRect, circle, capsule, scallop, none }
    public enum Orientation: String, Codable, Sendable, CaseIterable { case horizontal, vertical }

    public var shape: Shape?
    /// Width ÷ height; the card is the largest such rectangle centered in the widget.
    public var aspect: Double?
    /// The card's exact place in the family canvas (wins over `aspect`).
    public var inset: Frame?
    /// `roundedRect` corners (default 20).
    public var cornerRadius: Double?
    /// A `capsule`'s long side; without `aspect`, a vertical capsule is 0.5 wide per 1 high.
    public var orientation: Orientation?
    /// `scallop` bumps (6…24, default 12).
    public var bumps: Int?
    /// Around the card (default: the background's `outerColor`, else the wallpaper token `@outer`).
    public var outerColor: String?

    public init(shape: Shape? = nil, aspect: Double? = nil, inset: Frame? = nil, cornerRadius: Double? = nil,
                orientation: Orientation? = nil, bumps: Int? = nil, outerColor: String? = nil) {
        self.shape = shape
        self.aspect = aspect
        self.inset = inset
        self.cornerRadius = cornerRadius
        self.orientation = orientation
        self.bumps = bumps
        self.outerColor = outerColor
    }

    /// The aspect in effect: given, else 1 for circles and scallops, 0.5 or 2.4 for capsules by orientation.
    public var effectiveAspect: Double? {
        if let aspect, aspect.isFinite, aspect > 0 { return aspect }
        switch shape {
        case .circle?, .scallop?: return 1
        case .capsule?: return orientation == .vertical ? 0.5 : nil
        default: return nil
        }
    }

    /// The card in the family canvas.
    public func frame(in canvas: CGSize) -> Frame {
        let full = Frame(x: 0, y: 0, w: Double(canvas.width), h: Double(canvas.height))
        if let inset, inset.w > 0, inset.h > 0 { return inset.clamped(to: canvas) }
        guard let aspect = effectiveAspect else {
            // A horizontal pill without its own ratio keeps the old inset look (ADR-024).
            if shape == .capsule {
                let pad = Swift.min(full.w, full.h) * 0.04
                return Frame(x: pad, y: pad, w: full.w - 2 * pad, h: full.h - 2 * pad)
            }
            return full
        }
        let width = Swift.min(full.w, full.h * aspect)
        let height = width / aspect
        return Frame(x: ((full.w - width) / 2 * 2).rounded() / 2, y: ((full.h - height) / 2 * 2).rounded() / 2,
                     w: (width * 2).rounded() / 2, h: (height * 2).rounded() / 2)
    }

    /// Whether the card leaves part of the widget to `outerColor`.
    public var hasOuter: Bool {
        shape != CardSpec.Shape.none && (shape != .roundedRect && shape != nil || effectiveAspect != nil || inset != nil)
    }
}

extension WidgetSpec {
    /// The card in the family canvas: the whole canvas without a card.
    public var cardFrame: Frame {
        let full = family.canvas
        return card?.frame(in: full) ?? Frame(x: 0, y: 0, w: Double(full.width), h: Double(full.height))
    }

    /// Layer coordinates: the card's own size (ADR-029), else the family canvas.
    public var canvas: CGSize {
        let frame = cardFrame
        return CGSize(width: frame.w, height: frame.h)
    }
}
