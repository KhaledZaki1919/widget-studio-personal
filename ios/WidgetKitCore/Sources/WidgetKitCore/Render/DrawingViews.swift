import SwiftUI

// ADR-029: shapes, gradients, text runs, text on an arc and charts. Twin: android/.../render/Drawing2.kt.
// Angles are degrees clockwise from 12 o'clock everywhere in the spec.

/// Paths for every shape kind and card outline, in a rect. Pure geometry, shared by layers and cards.
public enum ShapeGeometry {
    /// A point on the ellipse inscribed in `rect` at `degrees` clockwise from 12 o'clock, `share` of the radius out.
    static func point(_ rect: CGRect, degrees: Double, share: Double = 1) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: rect.midX + CGFloat(sin(radians) * share) * rect.width / 2,
                       y: rect.midY - CGFloat(cos(radians) * share) * rect.height / 2)
    }

    /// A wavy circle (Pixel's "cookie"): `bumps` round bumps, `depth` share of the radius deep.
    public static func scallop(in rect: CGRect, bumps: Int, depth: Double = 0.07) -> Path {
        let count = max(3, min(bumps, 40))
        var path = Path()
        let steps = 240
        for step in 0...steps {
            let theta = Double(step) / Double(steps) * 360
            let share = 1 - depth + depth * cos(Double(count) * theta * .pi / 180)
            let p = point(rect, degrees: theta, share: share)
            if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    static func regular(in rect: CGRect, sides: Int) -> Path {
        let count = max(3, min(sides, 24))
        return polygon((0..<count).map { point(rect, degrees: Double($0) * 360 / Double(count)) })
    }

    static func star(in rect: CGRect, rays: Int, inner: Double) -> Path {
        let count = max(3, min(rays, 24))
        let corners = (0..<(count * 2)).map { index in
            point(rect, degrees: Double(index) * 180 / Double(count), share: index % 2 == 0 ? 1 : max(0.05, min(inner, 0.95)))
        }
        return polygon(corners)
    }

    /// A pie slice (or a donut slice with `inner` > 0) from `start` to `end` degrees.
    static func sector(in rect: CGRect, start: Double, end: Double, inner: Double) -> Path {
        var path = Path()
        let sweep = max(0, min(end - start, 360))
        guard sweep > 0 else { return path }
        let steps = max(2, Int(sweep / 3))
        let outer = (0...steps).map { point(rect, degrees: start + sweep * Double($0) / Double(steps)) }
        let hole = max(0, min(inner, 0.95))
        path.move(to: hole > 0 ? point(rect, degrees: start, share: hole) : CGPoint(x: rect.midX, y: rect.midY))
        for p in outer { path.addLine(to: p) }
        if hole > 0 {
            for index in stride(from: steps, through: 0, by: -1) {
                path.addLine(to: point(rect, degrees: start + sweep * Double(index) / Double(steps), share: hole))
            }
        }
        path.closeSubpath()
        return path
    }

    static func triangle(in rect: CGRect, direction: ShapeLayer.Direction?) -> Path {
        switch direction ?? .up {
        case .down: polygon([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY)])
        case .left: polygon([CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)])
        case .right: polygon([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.minX, y: rect.maxY)])
        default: polygon([CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)])
        }
    }

    /// An open line across the frame: along its longer side by default.
    static func line(in rect: CGRect, direction: ShapeLayer.Direction?) -> Path {
        var path = Path()
        let along = direction ?? (rect.width >= rect.height ? .horizontal : .vertical)
        switch along {
        case .vertical, .up, .down:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        case .diagonal:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .antidiagonal:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        default:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }

    /// A shape layer's outline. `progress` is the resolved `sector` share, if any.
    public static func path(_ layer: ShapeLayer, in rect: CGRect, scale: CGFloat, progress: Double?) -> Path {
        switch layer.kind {
        case .rect: return Path(rect)
        case .roundedRect: return Path(roundedRect: rect, cornerRadius: CGFloat(layer.cornerRadius ?? 16) * scale, style: .continuous)
        case .circle:
            let side = min(rect.width, rect.height)
            return Path(ellipseIn: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        case .capsule: return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2, style: .continuous)
        case .line: return line(in: rect, direction: layer.direction)
        case .triangle: return triangle(in: rect, direction: layer.direction)
        case .polygon:
            if let points = layer.points, points.count >= 3 {
                return polygon(points.compactMap { pair in
                    pair.count == 2 ? CGPoint(x: rect.minX + CGFloat(pair[0]) * rect.width, y: rect.minY + CGFloat(pair[1]) * rect.height) : nil
                })
            }
            return regular(in: rect, sides: layer.sides ?? 6)
        case .star: return star(in: rect, rays: layer.sides ?? 5, inner: layer.innerRatio ?? 0.45)
        case .scallop: return scallop(in: rect, bumps: layer.sides ?? 12)
        case .sector:
            let start = layer.startAngle ?? 0
            let end = progress.map { start + 360 * min(max($0, 0), 1) } ?? layer.endAngle ?? start + 90
            return sector(in: rect, start: start, end: end, inner: layer.innerRatio ?? 0)
        }
    }

    /// A card outline (ADR-029).
    public static func card(_ card: CardSpec?, in rect: CGRect, scale: CGFloat) -> Path {
        switch card?.shape {
        case .circle?:
            let side = min(rect.width, rect.height)
            return Path(ellipseIn: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        case .capsule?: return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2, style: .continuous)
        case .scallop?: return scallop(in: rect, bumps: card?.bumps ?? 12)
        default: return Path(roundedRect: rect, cornerRadius: CGFloat(card?.cornerRadius ?? 20) * scale, style: .continuous)
        }
    }
}

/// A shape layer as a SwiftUI shape.
struct SpecShape: Shape {
    let layer: ShapeLayer
    let scale: CGFloat
    let progress: Double?

    func path(in rect: CGRect) -> Path {
        ShapeGeometry.path(layer, in: rect, scale: scale, progress: progress)
    }
}

/// A card outline as a SwiftUI shape.
struct CardOutline: Shape {
    let card: CardSpec?
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        ShapeGeometry.card(card, in: rect, scale: scale)
    }
}

extension SpecGradient {
    /// The gradient as a fill style; accented mode keeps it faint like other large fills (ADR-023).
    func style(accented: Bool) -> AnyShapeStyle {
        let colors = colors.prefix(4).map { Color(hex: $0).opacity(accented ? Accented.surfaceOpacity : 1) }
        switch type {
        case .radial:
            return AnyShapeStyle(EllipticalGradient(colors: Array(colors), center: .center))
        case .linear:
            let angle = Angle(degrees: angle ?? 90)
            let dx = cos(angle.radians) / 2
            let dy = sin(angle.radians) / 2
            return AnyShapeStyle(LinearGradient(colors: Array(colors), startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                                                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)))
        }
    }
}

// MARK: - Text runs and case

enum SpecText {
    static func cased(_ text: String, _ textCase: TextCase?, language: String) -> String {
        switch textCase {
        case .upper?: text.uppercased(with: Locale(identifier: language))
        case .lower?: text.lowercased(with: Locale(identifier: language))
        case nil: text
        }
    }

    /// The runs as one Text: each with its own font, color, raised baseline, case and tracking.
    static func spans(_ layer: TextLayer, resolver: BindingResolver, scale: CGFloat) -> Text {
        let language = resolver.context.language
        return (layer.spans ?? []).reduce(Text(verbatim: "")) { result, span in
            let raw = resolver.render(span.text.resolved(language: language))
            let value = BidiText.isolatingNumbers(cased(raw, span.textCase ?? layer.textCase, language: language))
            let font = span.font ?? layer.font
            let arabic = FontRegistry.containsArabic(value)
            var piece = Text(verbatim: value)
                .font(FontRegistry.font(font, size: (font.size + (arabic && font.family != "arabic" ? 1 : 0)) * scale, for: value))
                .foregroundColor(Color(hex: span.color ?? layer.color))
            if let offset = span.baselineOffset { piece = piece.baselineOffset(offset * scale) }
            if !arabic, let tracking = span.tracking ?? layer.tracking { piece = piece.tracking(tracking * scale) }
            return result + piece
        }
    }
}

/// Text along a circle (ADR-029): each character placed and turned on the arc, centered on `start`.
struct ArcTextView: View {
    let layer: TextLayer
    let path: TextPath
    let value: String
    let scale: CGFloat
    @Environment(\.specAccented) private var accented

    var body: some View {
        GeometryReader { proxy in
            let size = layer.font.size * scale
            let side = min(proxy.size.width, proxy.size.height)
            let radius: CGFloat = path.arc.map { CGFloat($0) * scale } ?? max(side / 2 - size * 0.7, size)
            let inside = path.inside == true
            let characters = Array(value)
            let advances: [CGFloat] = characters.map { Self.advance($0) * size + CGFloat(layer.tracking ?? 0) * scale }
            let total = Double(advances.reduce(0, +))
            let degreesPerUnit: Double = 180 / (Double.pi * Double(max(radius, 1)))
            let sign: Double = inside ? -1 : 1
            let start: Double = (path.start ?? 0) - total * degreesPerUnit / 2 * sign
            ZStack {
                ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                    let before = Double(advances.prefix(index).reduce(0, +) + advances[index] / 2)
                    let angle: Double = start + before * degreesPerUnit * sign
                    Text(verbatim: String(character))
                        .font(FontRegistry.font(layer.font, size: size, for: value))
                        .foregroundStyle(Color(hex: layer.color))
                        .accentable(layer.color, accented: accented)
                        .rotationEffect(.degrees(inside ? angle + 180 : angle))
                        .position(ShapeGeometry.point(CGRect(x: proxy.size.width / 2 - radius, y: proxy.size.height / 2 - radius,
                                                             width: radius * 2, height: radius * 2), degrees: angle))
                }
            }
        }
    }

    /// Rough advance of a character as a share of the font size.
    static func advance(_ character: Character) -> CGFloat {
        if character == " " { return 0.3 }
        if "il.,:;'!|".contains(character) { return 0.3 }
        if "mwMW".contains(character) { return 0.85 }
        if character.isUppercase || character.isNumber { return 0.65 }
        return 0.55
    }
}

// MARK: - Chart

/// A chart layer (ADR-029).
struct ChartView: View {
    let layer: ChartLayer
    let resolver: BindingResolver
    let scale: CGFloat
    let mirrored: Bool
    @Environment(\.specAccented) private var accented

    var body: some View {
        GeometryReader { proxy in
            let model = ChartModel(layer: layer, points: points, size: proxy.size, scale: scale, mirrored: mirrored,
                                   language: resolver.context.language, resolver: resolver)
            ZStack(alignment: .topLeading) {
                if let baseline = model.baselineY {
                    Path { path in
                        path.move(to: CGPoint(x: model.plot.minX, y: baseline))
                        path.addLine(to: CGPoint(x: model.plot.maxX, y: baseline))
                    }
                    .stroke(Color(hex: layer.baselineColor ?? muted), style: StrokeStyle(lineWidth: max(0.5, scale), dash: [3 * scale, 3 * scale]))
                }
                plot(model)
                ForEach(Array(model.yLabels.enumerated()), id: \.offset) { _, label in
                    labelText(label.text).position(label.at)
                }
                ForEach(Array(model.xLabels.enumerated()), id: \.offset) { _, label in
                    labelText(label.text).position(label.at)
                }
            }
        }
    }

    /// The theme's secondary gray (tokens are resolved before drawing, defaults are not).
    private var muted: String { SpecTokens.hex("muted", theme: resolver.spec.theme) ?? "#8A8A8A" }

    private var points: [ChartPoint] {
        if case .levels(let values)? = resolver.soleValue(layer.values) { return values.map { ChartPoint(low: $0, high: $0) } }
        return ChartLayer.parse(layer.values) ?? []
    }

    private func labelText(_ text: String) -> some View {
        let font = layer.labelFont ?? FontSpec(family: "system", size: 10, weight: .medium)
        return Text(verbatim: text)
            .font(FontRegistry.font(font, size: font.size * scale, for: text))
            .foregroundStyle(Color(hex: layer.labelColor ?? muted))
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder private func plot(_ model: ChartModel) -> some View {
        let color = Color(hex: layer.color)
        let highlight = Color(hex: layer.highlightColor ?? layer.color)
        switch layer.kind {
        case .line, .area, .steps:
            if layer.kind == .area || layer.fill != nil || layer.gradient != nil {
                model.areaPath().fill(areaStyle)
            }
            model.linePath().stroke(color, style: StrokeStyle(lineWidth: CGFloat(layer.lineWidth ?? 2) * scale, lineCap: .round,
                                                              lineJoin: .round))
                .widgetAccentableIf(accented)
            if let index = model.highlighted, model.centers.indices.contains(index) {
                let p = model.centers[index]
                let dot = CGFloat(layer.lineWidth ?? 2) * scale * 2.5
                Circle().fill(highlight).frame(width: dot, height: dot).position(p)
            }
        case .bars, .candles:
            ForEach(Array(model.bars.enumerated()), id: \.offset) { index, bar in
                let radius = layer.kind == .candles ? bar.width / 2 : CGFloat(layer.cornerRadius ?? 2) * scale
                RoundedRectangle(cornerRadius: min(radius, bar.width / 2), style: .continuous)
                    .fill(index == model.highlighted ? highlight : (bar.down ? Color(hex: layer.downColor ?? layer.color) : color))
                    .frame(width: bar.width, height: max(bar.height, 1))
                    .position(x: bar.x, y: bar.y)
            }
            .widgetAccentableIf(accented)
        }
    }

    private var areaStyle: AnyShapeStyle {
        if let gradient = layer.gradient { return gradient.style(accented: accented) }
        if let fill = layer.fill { return AnyShapeStyle(Accented.fill(fill, accented: accented)) }
        return AnyShapeStyle(LinearGradient(colors: [Color(hex: layer.color).opacity(0.35), Color(hex: layer.color).opacity(0)],
                                            startPoint: .top, endPoint: .bottom))
    }
}

/// Chart geometry, without SwiftUI views so it can be tested.
struct ChartModel {
    struct Bar { let x: CGFloat; let y: CGFloat; let width: CGFloat; let height: CGFloat; let down: Bool }
    struct Label { let text: String; let at: CGPoint }

    let plot: CGRect
    let centers: [CGPoint]
    let bars: [Bar]
    let baselineY: CGFloat?
    let highlighted: Int?
    let xLabels: [Label]
    let yLabels: [Label]
    let kind: ChartLayer.Kind
    let bottom: CGFloat

    init(layer: ChartLayer, points: [ChartPoint], size: CGSize, scale: CGFloat, mirrored: Bool, language: String, resolver: BindingResolver) {
        kind = layer.kind
        let labelSize = CGFloat((layer.labelFont?.size ?? 10)) * scale
        let xTexts = layer.xLabels.map { resolver.render($0.resolved(language: language)).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? []
        let yTexts = layer.yLabels.map { resolver.render($0.resolved(language: language)).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? []
        let yWidth = yTexts.isEmpty ? 0 : CGFloat(yTexts.map(\.count).max() ?? 0) * labelSize * 0.62 + 4 * scale
        let xHeight = xTexts.isEmpty ? 0 : labelSize * 1.5
        let left = mirrored ? 0 : yWidth
        plot = CGRect(x: left, y: labelSize * 0.2, width: max(1, size.width - yWidth), height: max(1, size.height - xHeight - labelSize * 0.2))
        bottom = plot.maxY
        let lows = points.map(\.low)
        let highs = points.map(\.high)
        var low = layer.min ?? (lows.min() ?? 0)
        var high = layer.max ?? (highs.max() ?? 1)
        if layer.kind == .bars, layer.min == nil { low = Swift.min(0, low) }
        if high - low < 1e-9 { high = low + 1 }
        if layer.kind != .bars, layer.min == nil, layer.max == nil {
            let pad = (high - low) * 0.08
            low -= pad
            high += pad
        }
        let plotRect = plot
        func y(_ value: Double) -> CGFloat { plotRect.maxY - CGFloat((value - low) / (high - low)) * plotRect.height }
        let count = points.count
        let slot = count > 0 ? plotRect.width / CGFloat(count) : plotRect.width
        func x(_ index: Int) -> CGFloat {
            let position = mirrored ? count - 1 - index : index
            switch layer.kind {
            case .bars, .candles: return plotRect.minX + slot * (CGFloat(position) + 0.5)
            default: return count > 1 ? plotRect.minX + plotRect.width * CGFloat(position) / CGFloat(count - 1) : plotRect.midX
            }
        }
        centers = points.indices.map { CGPoint(x: x($0), y: y(points[$0].value)) }
        let baselineValue: Double?
        switch layer.baseline?.lowercased() {
        case nil: baselineValue = nil
        case "first"?: baselineValue = points.first?.value
        case "average"?: baselineValue = points.isEmpty ? nil : points.map(\.value).reduce(0, +) / Double(points.count)
        case let text?: baselineValue = Double(text)
        }
        baselineY = baselineValue.map(y)
        let width = slot * CGFloat(Swift.min(Swift.max(layer.barWidth ?? (layer.kind == .candles ? 0.35 : 0.6), 0.05), 1))
        let zero = y(Swift.max(low, Swift.min(high, baselineValue ?? Swift.max(low, 0))))
        bars = points.indices.map { index in
            let point = points[index]
            if layer.kind == .candles {
                let top = y(point.high)
                let bottomY = y(point.low)
                return Bar(x: x(index), y: (top + bottomY) / 2, width: width, height: Swift.max(bottomY - top, width), down: false)
            }
            let top = y(point.value)
            let down = baselineValue.map { point.value < $0 } ?? false
            return Bar(x: x(index), y: (Swift.min(top, zero) + Swift.max(top, zero)) / 2, width: width, height: abs(zero - top), down: down)
        }
        switch layer.highlight ?? .none {
        case .none: highlighted = nil
        case .last: highlighted = count > 0 ? count - 1 : nil
        case .max: highlighted = points.indices.max { points[$0].value < points[$1].value }
        case .min: highlighted = points.indices.min { points[$0].value < points[$1].value }
        }
        let labelY = plotRect.maxY + labelSize * 0.85
        xLabels = xTexts.enumerated().map { index, text in
            let share = xTexts.count > 1 ? CGFloat(index) / CGFloat(xTexts.count - 1) : 0.5
            let position = mirrored ? 1 - share : share
            let inset = labelSize * CGFloat(text.count) * 0.31
            let at = plotRect.minX + inset + (plotRect.width - 2 * inset) * position
            return Label(text: text, at: CGPoint(x: at, y: labelY))
        }
        let labelX = mirrored ? plotRect.maxX + yWidth / 2 : yWidth / 2
        yLabels = yTexts.enumerated().map { index, text in
            let share = yTexts.count > 1 ? CGFloat(index) / CGFloat(yTexts.count - 1) : 0.5
            return Label(text: text, at: CGPoint(x: labelX, y: plotRect.minY + plotRect.height * share))
        }
    }

    func linePath() -> Path {
        var path = Path()
        guard let first = centers.first else { return path }
        path.move(to: first)
        for (index, p) in centers.enumerated().dropFirst() {
            if kind == .steps {
                path.addLine(to: CGPoint(x: p.x, y: centers[index - 1].y))
            }
            path.addLine(to: p)
        }
        return path
    }

    func areaPath() -> Path {
        var path = linePath()
        guard let first = centers.first, let last = centers.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: bottom))
        path.addLine(to: CGPoint(x: first.x, y: bottom))
        path.closeSubpath()
        return path
    }
}
