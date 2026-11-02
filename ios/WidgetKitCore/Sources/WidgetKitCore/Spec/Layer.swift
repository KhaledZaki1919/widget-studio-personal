import Foundation

/// One drawn element (brief §4.4). Layers are drawn in order; the first is at the bottom.
public struct Layer: Codable, Sendable, Equatable {
    public var frame: Frame
    public var opacity: Double?
    /// In Arabic, the layer moves to the mirrored frame and swaps its alignment and item order;
    /// its content is never flipped (ADR-010).
    public var mirror: Bool?
    /// Draws the layer only when the condition holds (ADR-011): `"{{binding}}"` (truthy),
    /// `"!{{binding}}"` (falsy) or `"{{binding}} == value"`.
    public var when: String?
    /// Degrees clockwise: a number literal or a number binding (`{{qibla.bearing}}`).
    public var rotation: String?
    public var content: LayerContent

    public init(frame: Frame, opacity: Double? = nil, mirror: Bool? = nil, when: String? = nil,
                rotation: String? = nil, content: LayerContent) {
        self.frame = frame
        self.opacity = opacity
        self.mirror = mirror
        self.when = when
        self.rotation = rotation
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case type, frame, opacity, mirror, when, rotation, width, height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        // Children of a stack (M6.1) give only `width`/`height` (both optional: 0 = natural size).
        if container.contains(.frame) {
            frame = try container.decode(Frame.self, forKey: .frame)
        } else {
            frame = Frame(x: 0, y: 0, w: try container.decodeIfPresent(Double.self, forKey: .width) ?? 0,
                          h: try container.decodeIfPresent(Double.self, forKey: .height) ?? 0)
        }
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity)
        mirror = try container.decodeIfPresent(Bool.self, forKey: .mirror)
        when = try container.decodeIfPresent(String.self, forKey: .when)
        rotation = try Self.decodeNumberOrString(container, .rotation)
        switch type {
        case "text": content = .text(try TextLayer(from: decoder))
        case "image": content = .image(try ImageLayer(from: decoder))
        case "shape": content = .shape(try ShapeLayer(from: decoder))
        case "icon": content = .icon(try IconLayer(from: decoder))
        case "analogClock": content = .analogClock(try AnalogClockLayer(from: decoder))
        case "dotGrid": content = .dotGrid(try DotGridLayer(from: decoder))
        case "dotBars": content = .dotBars(try DotBarsLayer(from: decoder))
        case "ring": content = .ring(try RingLayer(from: decoder))
        case "forecastRow": content = .forecastRow(try ForecastRowLayer(from: decoder))
        case "button": content = .button(try ButtonLayer(from: decoder))
        case "calendarMonth": content = .calendarMonth(try CalendarMonthLayer(from: decoder))
        case "list": content = .list(try ListLayer(from: decoder))
        case "progressBar": content = .progressBar(try ProgressBarLayer(from: decoder))
        case "stack": content = .stack(try StackLayer(from: decoder))
        case "spacer": content = .spacer(try SpacerLayer(from: decoder))
        default: content = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        try encode(to: encoder, asChild: false)
    }

    /// A stack's children write `width`/`height` (when set) instead of a frame.
    func encode(to encoder: Encoder, asChild: Bool) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(content.typeName, forKey: .type)
        if asChild {
            if frame.w > 0 { try container.encode(frame.w, forKey: .width) }
            if frame.h > 0 { try container.encode(frame.h, forKey: .height) }
        } else {
            try container.encode(frame, forKey: .frame)
        }
        try container.encodeIfPresent(opacity, forKey: .opacity)
        try container.encodeIfPresent(mirror, forKey: .mirror)
        try container.encodeIfPresent(when, forKey: .when)
        try container.encodeIfPresent(rotation, forKey: .rotation)
        switch content {
        case .text(let layer): try layer.encode(to: encoder)
        case .image(let layer): try layer.encode(to: encoder)
        case .shape(let layer): try layer.encode(to: encoder)
        case .icon(let layer): try layer.encode(to: encoder)
        case .analogClock(let layer): try layer.encode(to: encoder)
        case .dotGrid(let layer): try layer.encode(to: encoder)
        case .dotBars(let layer): try layer.encode(to: encoder)
        case .ring(let layer): try layer.encode(to: encoder)
        case .forecastRow(let layer): try layer.encode(to: encoder)
        case .button(let layer): try layer.encode(to: encoder)
        case .calendarMonth(let layer): try layer.encode(to: encoder)
        case .list(let layer): try layer.encode(to: encoder)
        case .progressBar(let layer): try layer.encode(to: encoder)
        case .stack(let layer): try layer.encode(to: encoder)
        case .spacer(let layer): try layer.encode(to: encoder)
        case .unknown: break
        }
    }
}

extension Layer {
    /// `rotation` may be written as a number (`45`) or a string (`"{{qibla.bearing}}"`).
    static func decodeNumberOrString(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> String? {
        if let number = try? container.decodeIfPresent(Double.self, forKey: key) {
            return number.rounded() == number ? String(Int(number)) : String(number)
        }
        return try container.decodeIfPresent(String.self, forKey: key)
    }
}

public enum LayerContent: Sendable, Equatable {
    case text(TextLayer)
    case image(ImageLayer)
    case shape(ShapeLayer)
    case icon(IconLayer)
    case analogClock(AnalogClockLayer)
    case dotGrid(DotGridLayer)
    case dotBars(DotBarsLayer)
    case ring(RingLayer)
    case forecastRow(ForecastRowLayer)
    case button(ButtonLayer)
    /// ADR-019: a month calendar, rows of text, a progress bar.
    case calendarMonth(CalendarMonthLayer)
    case list(ListLayer)
    case progressBar(ProgressBarLayer)
    /// M6.1: a vertical, horizontal or grid container laid out natively, and flexible space in one.
    case stack(StackLayer)
    case spacer(SpacerLayer)
    /// A `type` this app doesn't know; always a validation error.
    case unknown(String)

    /// The layer types of schema v1, as written in JSON.
    public static let knownTypes = [
        "text", "image", "shape", "icon", "analogClock", "dotGrid", "dotBars", "ring", "forecastRow", "button",
        "calendarMonth", "list", "progressBar", "stack", "spacer",
    ]

    public var typeName: String {
        switch self {
        case .text: "text"
        case .image: "image"
        case .shape: "shape"
        case .icon: "icon"
        case .analogClock: "analogClock"
        case .dotGrid: "dotGrid"
        case .dotBars: "dotBars"
        case .ring: "ring"
        case .forecastRow: "forecastRow"
        case .button: "button"
        case .calendarMonth: "calendarMonth"
        case .list: "list"
        case .progressBar: "progressBar"
        case .stack: "stack"
        case .spacer: "spacer"
        case .unknown(let type): type
        }
    }
}

public enum TextAlign: String, Codable, Sendable, CaseIterable {
    case leading, center, trailing
}

public enum FontWeightName: String, Codable, Sendable, CaseIterable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
}

public struct FontSpec: Codable, Sendable, Equatable {
    /// One of `FontRegistry.families`.
    public var family: String
    public var size: Double
    public var weight: FontWeightName?

    public init(family: String, size: Double, weight: FontWeightName? = nil) {
        self.family = family
        self.size = size
        self.weight = weight
    }
}

public struct LiveText: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Counts down to (or up from) `target`: `Text(timerInterval:)`.
        case timer
        /// "in 3 days": `Text(_:style: .relative)`.
        case relative
        /// The current time, ticking without timeline reloads: `Text(_:style: .time)`.
        case time
    }

    public var kind: Kind
    /// A date binding (`{{field.<dateKey>}}`); not needed for `time`.
    public var target: String?

    public init(kind: Kind, target: String? = nil) {
        self.kind = kind
        self.target = target
    }
}

public struct TextLayer: Codable, Sendable, Equatable {
    public var value: LocalizedText
    public var font: FontSpec
    public var color: String
    public var align: TextAlign?
    public var maxLines: Int?
    public var tracking: Double?
    public var live: LiveText?

    public init(value: LocalizedText, font: FontSpec, color: String, align: TextAlign? = nil,
                maxLines: Int? = nil, tracking: Double? = nil, live: LiveText? = nil) {
        self.value = value
        self.font = font
        self.color = color
        self.align = align
        self.maxLines = maxLines
        self.tracking = tracking
        self.live = live
    }
}

public struct ImageLayer: Codable, Sendable, Equatable {
    public enum Fit: String, Codable, Sendable, CaseIterable { case fill, fit }
    public enum Mask: String, Codable, Sendable, CaseIterable { case rect, roundedRect, circle }
    /// Applied once in the app when saving, never in the widget.
    public enum Filter: String, Codable, Sendable, CaseIterable { case none, mono, halftone }

    /// `user_image` or `asset:<id>`.
    public var source: String
    public var fit: Fit?
    public var mask: Mask?
    public var cornerRadius: Double?
    public var filter: Filter?

    public init(source: String, fit: Fit? = nil, mask: Mask? = nil, cornerRadius: Double? = nil, filter: Filter? = nil) {
        self.source = source
        self.fit = fit
        self.mask = mask
        self.cornerRadius = cornerRadius
        self.filter = filter
    }
}

public struct Stroke: Codable, Sendable, Equatable {
    public var color: String
    public var width: Double
    public var dash: [Double]?

    public init(color: String, width: Double, dash: [Double]? = nil) {
        self.color = color
        self.width = width
        self.dash = dash
    }
}

public struct ShapeLayer: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case rect, roundedRect, circle, capsule }

    public var kind: Kind
    public var fill: String?
    public var stroke: Stroke?
    public var cornerRadius: Double?

    public init(kind: Kind, fill: String? = nil, stroke: Stroke? = nil, cornerRadius: Double? = nil) {
        self.kind = kind
        self.fill = fill
        self.stroke = stroke
        self.cornerRadius = cornerRadius
    }
}

public struct IconLayer: Codable, Sendable, Equatable {
    /// An SF Symbol from `Icons.whitelist`, or a binding that yields one (`{{weather.symbol}}`).
    public var symbol: String
    public var size: Double
    public var color: String

    public init(symbol: String, size: Double, color: String) {
        self.symbol = symbol
        self.size = size
        self.color = color
    }
}

public struct AnalogClockLayer: Codable, Sendable, Equatable {
    public enum Style: String, Codable, Sendable, CaseIterable { case classic, dot }

    public var style: Style?
    public var faceColor: String?
    public var tickColor: String?
    public var hourColor: String?
    public var minuteColor: String?
    public var accentColor: String?
    /// A timezone field (`{{field.<key>}}`) or an IANA name; device time zone when absent.
    public var timezone: String?

    public init(style: Style? = nil, faceColor: String? = nil, tickColor: String? = nil, hourColor: String? = nil,
                minuteColor: String? = nil, accentColor: String? = nil, timezone: String? = nil) {
        self.style = style
        self.faceColor = faceColor
        self.tickColor = tickColor
        self.hourColor = hourColor
        self.minuteColor = minuteColor
        self.accentColor = accentColor
        self.timezone = timezone
    }
}

public struct DotGridLayer: Codable, Sendable, Equatable {
    public var rows: Int
    public var cols: Int
    public var dotSize: Double
    public var gap: Double
    public var onColor: String
    public var offColor: String
    /// A binding to levels (`{{steps.monthGrid}}`) or a literal pattern of `0`/`1` digits.
    public var values: String
    /// Cells with a level of 2 or more (today in `MonthGrid`) use this color (ADR-011).
    public var highlightColor: String?

    public init(rows: Int, cols: Int, dotSize: Double, gap: Double, onColor: String, offColor: String, values: String,
                highlightColor: String? = nil) {
        self.rows = rows
        self.cols = cols
        self.dotSize = dotSize
        self.gap = gap
        self.onColor = onColor
        self.offColor = offColor
        self.values = values
        self.highlightColor = highlightColor
    }
}

public struct DotBarsLayer: Codable, Sendable, Equatable {
    public var bars: Int
    public var maxDots: Int
    /// A binding to levels 0…1 (`{{sleep.week}}`).
    public var values: String
    public var color: String
    public var offColor: String?
    /// Comma-separated labels (a string or `{en, ar}`), one per bar.
    public var labels: LocalizedText?
    /// The highest bar's lit dots use this color ("best night", ADR-011).
    public var highlightColor: String?

    public init(bars: Int, maxDots: Int, values: String, color: String, offColor: String? = nil, labels: LocalizedText? = nil,
                highlightColor: String? = nil) {
        self.bars = bars
        self.maxDots = maxDots
        self.values = values
        self.color = color
        self.offColor = offColor
        self.labels = labels
        self.highlightColor = highlightColor
    }
}

public struct RingLayer: Codable, Sendable, Equatable {
    /// A number 0…1 or a binding to one (`{{battery.level}}`).
    public var progress: String
    public var color: String
    public var trackColor: String?
    public var lineWidth: Double

    public init(progress: String, color: String, trackColor: String? = nil, lineWidth: Double) {
        self.progress = progress
        self.color = color
        self.trackColor = trackColor
        self.lineWidth = lineWidth
    }
}

public struct ForecastRowLayer: Codable, Sendable, Equatable {
    public var days: Int
    public var color: String

    public init(days: Int, color: String) {
        self.days = days
        self.color = color
    }
}

public struct ButtonLayer: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable, CaseIterable {
        case counterIncrement = "counter.increment"
        case counterReset = "counter.reset"
        case counterNext = "counter.next"
        case stopwatchToggle = "stopwatch.toggle"
        case shortcutRun = "shortcut.run"
        case openURL = "open.url"
        case openApp = "open.app"
    }

    public var action: Action
    /// e.g. `{{field.shortcut}}`.
    public var arg: String?

    public init(action: Action, arg: String? = nil) {
        self.action = action
        self.arg = arg
    }
}
