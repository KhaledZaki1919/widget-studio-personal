import Foundation

/// One drawn element (brief §4.4). Layers are drawn in order; the first is at the bottom.
public struct Layer: Codable, Sendable, Equatable {
    public var frame: Frame
    public var opacity: Double?
    /// In Arabic, the layer moves to the mirrored frame and swaps its alignment and item order;
    /// its content is never flipped (ADR-010).
    public var mirror: Bool?
    /// Draws the layer only when the condition holds (ADR-011, ADR-028): see `SpecExpression`.
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
        case "states": content = .states(try StatesLayer(from: decoder))
        case "chart": content = .chart(try ChartLayer(from: decoder))
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
        case .states(let layer): try layer.encode(to: encoder)
        case .chart(let layer): try layer.encode(to: encoder)
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
    /// ADR-028: one look per state, chosen by real data.
    case states(StatesLayer)
    /// ADR-029: a line, area, bar, step or candle chart of a series.
    case chart(ChartLayer)
    /// A `type` this app doesn't know; always a validation error.
    case unknown(String)

    /// The layer types of schema v1, as written in JSON.
    public static let knownTypes = [
        "text", "image", "shape", "icon", "analogClock", "dotGrid", "dotBars", "ring", "forecastRow", "button",
        "calendarMonth", "list", "progressBar", "stack", "spacer", "states", "chart",
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
        case .states: "states"
        case .chart: "chart"
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
    /// ADR-029: runs with their own weight, color, size, raised baseline, case or tracking ("is in **50 min.**",
    /// a raised "AM"). When present they are drawn instead of `value`.
    public var spans: [TextSpan]?
    /// `upper` or `lower`, applied after bindings resolve.
    public var textCase: TextCase?
    /// The smallest share of `font.size` the text may shrink to before it truncates (0.3…1, default 0.5).
    public var minScale: Double?
    /// Text set along a circle (ADR-029).
    public var path: TextPath?

    enum CodingKeys: String, CodingKey {
        case value, font, color, align, maxLines, tracking, live, spans, minScale, path
        case textCase = "case"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spans = try container.decodeIfPresent([TextSpan].self, forKey: .spans)
        // With spans, `value` may be left out: it is then the spans' text (search, auto-wire, rules).
        if let value = try container.decodeIfPresent(LocalizedText.self, forKey: .value) {
            self.value = value
        } else if let spans, !spans.isEmpty {
            value = TextSpan.joined(spans)
        } else {
            value = try container.decode(LocalizedText.self, forKey: .value)
        }
        font = try container.decode(FontSpec.self, forKey: .font)
        color = try container.decode(String.self, forKey: .color)
        align = try container.decodeIfPresent(TextAlign.self, forKey: .align)
        maxLines = try container.decodeIfPresent(Int.self, forKey: .maxLines)
        tracking = try container.decodeIfPresent(Double.self, forKey: .tracking)
        live = try container.decodeIfPresent(LiveText.self, forKey: .live)
        textCase = try container.decodeIfPresent(TextCase.self, forKey: .textCase)
        minScale = try container.decodeIfPresent(Double.self, forKey: .minScale)
        path = try container.decodeIfPresent(TextPath.self, forKey: .path)
    }

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
    /// ADR-029 adds `line`, `triangle`, `polygon`, `sector`, `star` and `scallop` (see `ShapeGeometry`).
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case rect, roundedRect, circle, capsule, line, triangle, polygon, sector, star, scallop
    }
    /// Where a `line` runs or a `triangle` points.
    public enum Direction: String, Codable, Sendable, CaseIterable {
        case up, down, left, right, horizontal, vertical, diagonal, antidiagonal
    }

    public var kind: Kind
    public var fill: String?
    public var stroke: Stroke?
    public var cornerRadius: Double?
    /// Frosted glass (ADR-023): the fill (default white at 15 %) gets a sheen and, without a
    /// stroke, a thin light border. Over a photo it reads as a frosted card.
    public var glass: Bool?
    /// `fill` written as `{"type": "linear"|"radial", "colors": […], "angle": …}` (ADR-029).
    public var gradient: SpecGradient?
    /// `polygon`: corners as [x, y] fractions of the frame (0…1); without them, a regular polygon of `sides`.
    public var points: [[Double]]?
    /// `polygon` corners, `star` rays, `scallop` bumps.
    public var sides: Int?
    /// `star`: inner radius share; `sector`: the hole's share (a donut slice).
    public var innerRatio: Double?
    /// `sector`: degrees clockwise from 12 o'clock.
    public var startAngle: Double?
    public var endAngle: Double?
    /// `sector`: a number 0…1 or a binding; the slice then runs from `startAngle` over that share of the circle.
    public var progress: String?
    public var direction: Direction?

    enum CodingKeys: String, CodingKey {
        case kind, fill, stroke, cornerRadius, glass, points, sides, innerRatio, startAngle, endAngle, progress, direction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        if let gradient = try? container.decodeIfPresent(SpecGradient.self, forKey: .fill) {
            self.gradient = gradient
            fill = gradient.colors.first
        } else {
            fill = try container.decodeIfPresent(String.self, forKey: .fill)
        }
        stroke = try container.decodeIfPresent(Stroke.self, forKey: .stroke)
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius)
        glass = try container.decodeIfPresent(Bool.self, forKey: .glass)
        points = try container.decodeIfPresent([[Double]].self, forKey: .points)
        sides = try container.decodeIfPresent(Int.self, forKey: .sides)
        innerRatio = try container.decodeIfPresent(Double.self, forKey: .innerRatio)
        startAngle = try container.decodeIfPresent(Double.self, forKey: .startAngle)
        endAngle = try container.decodeIfPresent(Double.self, forKey: .endAngle)
        progress = try SpecNumberOrString.decode(container, forKey: .progress)
        direction = try container.decodeIfPresent(Direction.self, forKey: .direction)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if let gradient {
            try container.encode(gradient, forKey: .fill)
        } else {
            try container.encodeIfPresent(fill, forKey: .fill)
        }
        try container.encodeIfPresent(stroke, forKey: .stroke)
        try container.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
        try container.encodeIfPresent(glass, forKey: .glass)
        try container.encodeIfPresent(points, forKey: .points)
        try container.encodeIfPresent(sides, forKey: .sides)
        try container.encodeIfPresent(innerRatio, forKey: .innerRatio)
        try container.encodeIfPresent(startAngle, forKey: .startAngle)
        try container.encodeIfPresent(endAngle, forKey: .endAngle)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(direction, forKey: .direction)
    }

    public init(kind: Kind, fill: String? = nil, stroke: Stroke? = nil, cornerRadius: Double? = nil, glass: Bool? = nil) {
        self.kind = kind
        self.fill = fill
        self.stroke = stroke
        self.cornerRadius = cornerRadius
        self.glass = glass
    }
}

public struct IconLayer: Codable, Sendable, Equatable {
    /// An SF Symbol from `Icons.whitelist`, or a binding that yields one (`{{weather.symbol}}`).
    public var symbol: String
    public var size: Double
    public var color: String
    /// ADR-029: `outline` draws the symbol without its fill (`cloud` for `cloud.fill`), `fill` the filled one.
    public var style: IconStyle?

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
    /// ADR-029: hand widths as shares of the radius (default hour 0.07, minute 0.045), round or flat ends,
    /// lengths as shares of the radius (hour 0.5, minute 0.75), the marks (`12` lines, `60` lines, `dots`,
    /// `none`; default `60`, or `dots` for `style: dot`), and a seconds `hand` or `dot` in `accentColor`.
    public var hourWidth: Double?
    public var minuteWidth: Double?
    public var handCap: HandCap?
    public var hourLength: Double?
    public var minuteLength: Double?
    public var ticks: Ticks?
    public var seconds: Seconds?
    /// The center cap in `accentColor` (default true).
    public var centerDot: Bool?

    public enum HandCap: String, Codable, Sendable, CaseIterable { case round, flat }
    public enum Ticks: String, Codable, Sendable, CaseIterable {
        case none, twelve = "12", sixty = "60", dots
    }
    public enum Seconds: String, Codable, Sendable, CaseIterable { case none, hand, dot }

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
    /// ADR-029: in a literal, digits 0…9 are a level per dot (0 off, 9 full). `levelColors` colors levels
    /// in bands (a level up to 1/n takes the first color, and so on) instead of fading `onColor`.
    public var levelColors: [String]?
    /// Dots outside this shape are hidden: `circle`, `cloud`, `sun`, `moon`, `drop`, `heart`, `bolt`, or
    /// `weather` (the current condition's shape, so the drawing changes with the weather).
    public var mask: DotMask?
    /// Each dot's size follows its level (halftone) instead of its opacity.
    public var sizeByLevel: Bool?
    /// A number binding lights dots by `rows` (left to right, top down; right to left when mirrored in
    /// Arabic), by `columns` (top down, column by column) or `bottomUp` (each column from the bottom).
    public var order: DotOrder?
    /// A halftone fade: dots shrink toward this side.
    public var fade: DotFade?

    public enum DotMask: String, Codable, Sendable, CaseIterable { case circle, cloud, sun, moon, drop, heart, bolt, weather }
    public enum DotOrder: String, Codable, Sendable, CaseIterable { case rows, columns, bottomUp }
    public enum DotFade: String, Codable, Sendable, CaseIterable { case none, left, right, up, down }

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
    /// Columns: days in `daily` mode (1…7), hours in `hourly` mode (1…8).
    public var days: Int
    public var color: String
    /// ADR-029: `daily` (from tomorrow) or `hourly` (from the next hour).
    public var mode: Mode?
    /// Temperatures; labels use it at 0.85 size. Default system 12.
    public var font: FontSpec?
    public var iconStyle: IconStyle?
    /// The low under the high (daily; default true).
    public var showLow: Bool?
    /// A thin line between columns.
    public var dividerColor: String?
    /// Day or hour labels and lows (default `@muted`).
    public var labelColor: String?
    /// The icons (default true).
    public var showIcons: Bool?

    public enum Mode: String, Codable, Sendable, CaseIterable { case daily, hourly }

    public init(days: Int, color: String) {
        self.days = days
        self.color = color
    }
}

public struct ButtonLayer: Codable, Sendable, Equatable {
    /// A catalog action id (`capabilities.json`, ADR-027). Any string decodes; `SpecValidator`
    /// rejects ids the catalog doesn't have, so old designs keep opening.
    public struct Action: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let counterIncrement = Action(rawValue: "counter.increment")
        public static let counterReset = Action(rawValue: "counter.reset")
        public static let counterNext = Action(rawValue: "counter.next")
        public static let stopwatchToggle = Action(rawValue: "stopwatch.toggle")
        public static let shortcutRun = Action(rawValue: "shortcut.run")
        public static let openURL = Action(rawValue: "open.url")
        public static let openApp = Action(rawValue: "open.app")

        /// Every action in the catalog.
        public static var allCases: [Action] { Capabilities.actions.map { Action(rawValue: $0.id) } }
    }

    public var action: Action
    /// e.g. `{{field.shortcut}}`.
    public var arg: String?

    public init(action: Action, arg: String? = nil) {
        self.action = action
        self.arg = arg
    }
}
