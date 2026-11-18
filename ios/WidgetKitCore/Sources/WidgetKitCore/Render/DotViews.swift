import SwiftUI

/// A grid of dots, filled row by row; each value 0…1 blends from `offColor` (0) to `onColor` (1),
/// and a negative value leaves the cell empty (month padding, `MonthGrid`). Mirrored, each row
/// runs right to left, like an Arabic calendar.
struct DotGridView: View {
    let layer: DotGridLayer
    let levels: [Double]
    let scale: CGFloat
    let mirrored: Bool
    /// The mask's shape name, `weather` already resolved (ADR-029).
    var maskName: String?
    @Environment(\.specAccented) private var accented

    var body: some View {
        if layer.levelColors != nil || maskName != nil || layer.sizeByLevel == true || (layer.fade ?? .none) != .none {
            styled
        } else {
            plain
        }
    }

    /// ADR-029: level colors, a mask, halftone size and fade.
    private var styled: some View {
        let on = Color(hex: layer.onColor)
        let off = accented ? Color(hex: layer.offColor).opacity(0.35) : Color(hex: layer.offColor)
        let highlight = Color(hex: layer.highlightColor ?? layer.onColor)
        let bands = layer.levelColors?.map { Color(hex: $0) }
        return Canvas { context, size in
            let dot = layer.dotSize * scale
            let gap = layer.gap * scale
            let width = CGFloat(layer.cols) * dot + CGFloat(layer.cols - 1) * gap
            let height = CGFloat(layer.rows) * dot + CGFloat(layer.rows - 1) * gap
            let box = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
            let mask = maskName.map { ShapeGeometry.mask($0, in: box) }
            for row in 0..<layer.rows {
                for col in 0..<layer.cols {
                    let index = row * layer.cols + col
                    let level = index < levels.count ? levels[index] : 0
                    if level < 0 { continue }
                    let column = mirrored ? layer.cols - 1 - col : col
                    let center = CGPoint(x: box.minX + CGFloat(column) * (dot + gap) + dot / 2, y: box.minY + CGFloat(row) * (dot + gap) + dot / 2)
                    if let mask, !mask.contains(center) { continue }
                    let fade = DotGridLayout.fade(layer.fade, x: CGFloat(column) / CGFloat(max(layer.cols - 1, 1)),
                                                  y: CGFloat(row) / CGFloat(max(layer.rows - 1, 1)))
                    let radius = dot / 2 * fade
                    func disc(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)) }
                    let band = DotGridLayout.band(count: bands?.count ?? 0, level: level).flatMap { bands?[$0] }
                    if layer.sizeByLevel == true {
                        if level > 0 {
                            context.fill(disc(radius * max(0.15, min(level, 1))), with: .color(level >= MonthGrid.highlight ? highlight : band ?? on))
                        } else {
                            context.fill(disc(radius), with: .color(off))
                        }
                        continue
                    }
                    context.fill(disc(radius), with: .color(off))
                    if level >= MonthGrid.highlight {
                        context.fill(disc(radius), with: .color(highlight))
                    } else if level > 0 {
                        context.fill(disc(radius), with: .color(band ?? on.opacity(min(level, 1))))
                    }
                }
            }
        }
    }

    @ViewBuilder private var plain: some View {
        let on = Color(hex: layer.onColor)
        // Accented mode: unlit dots stay faint, so the lit ones read (ADR-023).
        let off = accented ? Color(hex: layer.offColor).opacity(0.35) : Color(hex: layer.offColor)
        let highlight = Color(hex: layer.highlightColor ?? layer.onColor)
        Canvas { context, size in
            let dot = layer.dotSize * scale
            let gap = layer.gap * scale
            let width = CGFloat(layer.cols) * dot + CGFloat(layer.cols - 1) * gap
            let height = CGFloat(layer.rows) * dot + CGFloat(layer.rows - 1) * gap
            let origin = CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2)
            for row in 0..<layer.rows {
                for col in 0..<layer.cols {
                    let index = row * layer.cols + col
                    let level = index < levels.count ? levels[index] : 0
                    if level < 0 { continue }
                    let column = mirrored ? layer.cols - 1 - col : col
                    let rect = CGRect(x: origin.x + CGFloat(column) * (dot + gap), y: origin.y + CGFloat(row) * (dot + gap),
                                      width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(off))
                    if level >= MonthGrid.highlight {
                        context.fill(Path(ellipseIn: rect), with: .color(highlight))
                    } else if level > 0 {
                        context.fill(Path(ellipseIn: rect), with: .color(on.opacity(min(level, 1))))
                    }
                }
            }
        }
    }
}

/// Dot grid rules (ADR-029), shared by the view and the tests; twin of DotGridLayout in Drawing2.kt.
enum DotGridLayout {
    /// Cell indices (row-major) in lighting order.
    static func order(rows: Int, cols: Int, _ order: DotGridLayer.DotOrder?) -> [Int] {
        switch order ?? .rows {
        case .rows: return Array(0..<(rows * cols))
        case .columns: return (0..<cols).flatMap { c in (0..<rows).map { $0 * cols + c } }
        case .bottomUp: return (0..<cols).flatMap { c in (0..<rows).reversed().map { $0 * cols + c } }
        }
    }

    /// The color band of a level 0…1 among `count` colors.
    static func band(count: Int, level: Double) -> Int? {
        guard count > 0, level > 0 else { return nil }
        return min(max(Int((min(level, 1) * Double(count)).rounded(.up)) - 1, 0), count - 1)
    }

    /// Dot size factor for a halftone fade toward a side (x, y are 0…1 across the grid).
    static func fade(_ side: DotGridLayer.DotFade?, x: CGFloat, y: CGFloat) -> CGFloat {
        switch side ?? .none {
        case .none: 1
        case .left: 0.25 + 0.75 * x
        case .right: 0.25 + 0.75 * (1 - x)
        case .up: 0.25 + 0.75 * y
        case .down: 0.25 + 0.75 * (1 - y)
        }
    }

    /// `weather` becomes the current condition's shape.
    static func maskName(_ mask: DotGridLayer.DotMask?, resolver: BindingResolver) -> String? {
        guard let mask else { return nil }
        guard mask == .weather else { return mask.rawValue }
        guard let kind = resolver.value(of: "weather.kind").map(resolver.display) else { return "cloud" }
        let day = resolver.value(of: "time.isDay").map(resolver.display) != "0"
        switch kind {
        case "clear": return day ? "sun" : "moon"
        case "storm": return "bolt"
        default: return "cloud"
        }
    }
}

extension ShapeGeometry {
    /// Mask outlines for dot grids, in `box` (twin of ShapeGeometry.mask in Drawing2.kt).
    static func mask(_ name: String, in box: CGRect) -> Path {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: box.minX + x * box.width, y: box.minY + y * box.height) }
        let side = min(box.width, box.height)
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            let c = at(x, y)
            return Path(ellipseIn: CGRect(x: c.x - r * side, y: c.y - r * side, width: 2 * r * side, height: 2 * r * side))
        }
        let square = CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
        switch name {
        case "cloud":
            var path = circle(0.3, 0.6, 0.22)
            path.addPath(circle(0.52, 0.42, 0.3))
            path.addPath(circle(0.75, 0.6, 0.2))
            path.addRoundedRect(in: CGRect(x: box.minX + 0.1 * box.width, y: box.minY + 0.55 * box.height, width: 0.84 * box.width,
                                           height: 0.27 * box.height), cornerSize: CGSize(width: 0.13 * side, height: 0.13 * side))
            return path
        case "sun": return star(in: square, rays: 12, inner: 0.72)
        case "moon": return circle(0.5, 0.5, 0.45).subtracting(circle(0.68, 0.38, 0.38))
        case "drop":
            var path = circle(0.5, 0.66, 0.3)
            path.addPath(polygon([at(0.5, 0.05), at(0.78, 0.6), at(0.22, 0.6)]))
            return path
        case "heart":
            var path = circle(0.3, 0.35, 0.25)
            path.addPath(circle(0.7, 0.35, 0.25))
            path.addPath(polygon([at(0.06, 0.42), at(0.94, 0.42), at(0.5, 0.95)]))
            return path
        case "bolt": return polygon([at(0.58, 0.02), at(0.18, 0.56), at(0.46, 0.56), at(0.38, 0.98), at(0.82, 0.4), at(0.54, 0.4)])
        default: return Path(ellipseIn: square)
        }
    }
}

/// A dot-matrix bar chart: each bar is a column of `maxDots` dots, lit from the bottom.
/// Mirrored, the bars (and their labels) run right to left.
struct DotBarsView: View {
    let layer: DotBarsLayer
    let resolver: BindingResolver
    let scale: CGFloat
    let mirrored: Bool
    @Environment(\.specAccented) private var accented

    var body: some View {
        let levels = ordered(resolver.levels(layer.values), count: layer.bars, filler: 0)
        let labels = ordered(self.labels, count: layer.bars, filler: "")
        let color = Color(hex: layer.color)
        let off = accented ? Color(hex: layer.offColor ?? "#FFFFFF26").opacity(0.35) : Color(hex: layer.offColor ?? "#FFFFFF26")
        // With a highlight color, the highest bar (first one on ties) is drawn in it.
        let best = layer.highlightColor == nil ? nil : levels.indices.max { levels[$0] < levels[$1] }
        let highlight = Color(hex: layer.highlightColor ?? layer.color)
        VStack(spacing: 4 * scale) {
            Canvas { context, size in
                let bars = CGFloat(layer.bars)
                let rows = CGFloat(layer.maxDots)
                let dot = min(size.width / (bars * 1.6), size.height / (rows * 1.4))
                let columnWidth = size.width / bars
                let rowHeight = size.height / rows
                for bar in 0..<layer.bars {
                    let lit = Int((min(max(levels[bar], 0), 1) * Double(layer.maxDots)).rounded())
                    let litColor = bar == best ? highlight : color
                    for row in 0..<layer.maxDots {
                        let x = CGFloat(bar) * columnWidth + (columnWidth - dot) / 2
                        let y = size.height - CGFloat(row + 1) * rowHeight + (rowHeight - dot) / 2
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot)), with: .color(row < lit ? litColor : off))
                    }
                }
            }
            if labels.contains(where: { !$0.isEmpty }) {
                HStack(spacing: 0) {
                    ForEach(0..<layer.bars, id: \.self) { index in
                        Text(verbatim: labels[index])
                            .font(FontRegistry.font(FontSpec(family: "system", size: 8, weight: .medium), size: 8 * scale, for: labels[index]))
                            .foregroundStyle(color.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var labels: [String] {
        guard let labels = layer.labels?.resolved(language: resolver.context.language) else { return [] }
        return resolver.render(labels).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Exactly `count` items, in reading order.
    private func ordered<T>(_ items: [T], count: Int, filler: T) -> [T] {
        let padded = Array(items.prefix(count)) + Array(repeating: filler, count: max(0, count - items.count))
        return mirrored ? padded.reversed() : padded
    }
}

/// n days of weather: day name, symbol, high and low. Mirrored, today is on the right.
struct ForecastRowView: View {
    let layer: ForecastRowLayer
    let resolver: BindingResolver
    let scale: CGFloat
    let mirrored: Bool

    var body: some View {
        if layer.mode == .hourly || layer.font != nil || layer.dividerColor != nil || layer.showLow != nil || layer.iconStyle != nil
            || layer.labelColor != nil || layer.showIcons != nil {
            ForecastColumnsView(layer: layer, resolver: resolver, scale: scale, mirrored: mirrored)
        } else {
            daily
        }
    }

    private var daily: some View {
        let next = Array((resolver.context.data.weather?.forecast ?? []).prefix(layer.days))
        let days = mirrored ? next.reversed() : next
        let color = Color(hex: layer.color)
        return HStack(spacing: 0) {
            if days.isEmpty {
                Text(verbatim: BindingResolver.missing)
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 3 * scale) {
                    let name = dayName(day.date)
                    Text(verbatim: name)
                        .font(FontRegistry.font(FontSpec(family: "system", size: 9, weight: .medium), size: 9 * scale, for: name))
                        .opacity(0.7)
                    Image(systemName: Icons.isAllowed(day.symbol) ? day.symbol : "questionmark")
                        .font(.system(size: 15 * scale))
                    highText(day.high)
                    Text(verbatim: "\(Int(day.low.rounded()))°")
                        .font(.system(size: 9 * scale))
                        .opacity(0.6)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The high in the dot font; the degree sign in the system font (Doto's looks wrong).
    private func highText(_ value: Double) -> Text {
        let digits = Text(verbatim: "\(Int(value.rounded()))")
            .font(FontRegistry.font(FontSpec(family: "dot", size: 13, weight: .bold), size: 13 * scale, for: ""))
        let degree = Text(verbatim: "°").font(.system(size: 11 * scale, weight: .bold))
        return digits + degree
    }

    /// "Wed" / "الأربعاء".
    private func dayName(_ date: Date) -> String {
        let context = resolver.context
        return FormatterCache.date(context.isArabic ? "EEEE" : "EEE", locale: context.localeIdentifier, zone: context.timeZone)
            .string(from: date)
    }
}

/// ADR-029: hourly or daily columns with the row's font, icon style, lows and dividers (twin of forecastColumns in ChartDrawer.kt).
struct ForecastColumnsView: View {
    let layer: ForecastRowLayer
    let resolver: BindingResolver
    let scale: CGFloat
    let mirrored: Bool

    struct Column {
        let label: String
        let symbol: String
        let high: String
        let low: String?
    }

    private var columns: [Column] {
        if layer.mode == .hourly {
            return (1...max(1, layer.days)).compactMap { n in
                guard let time = resolver.value(of: "hourly.\(n).time").map(resolver.display) else { return nil }
                let symbol = resolver.value(of: "hourly.\(n).symbol").map(resolver.display) ?? "cloud.fill"
                let temp = resolver.value(of: "hourly.\(n).temp").map(resolver.display) ?? BindingResolver.missing
                return Column(label: time, symbol: symbol, high: temp + "°", low: nil)
            }
        }
        let context = resolver.context
        return (context.data.weather?.forecast ?? []).prefix(layer.days).map { day in
            let name = FormatterCache.date(context.isArabic ? "EEEE" : "EEE", locale: context.localeIdentifier, zone: context.timeZone).string(from: day.date)
            return Column(label: name, symbol: day.symbol, high: "\(Int(day.high.rounded()))°", low: "\(Int(day.low.rounded()))°")
        }
    }

    var body: some View {
        let font = layer.font ?? FontSpec(family: "system", size: 12, weight: .semibold)
        let label = FontSpec(family: font.family, size: font.size * 0.85)
        let color = Color(hex: layer.color)
        let secondary = layer.labelColor.map(Color.init(hex:)) ?? color.opacity(0.6)
        let shown = mirrored ? columns.reversed() : columns
        let showLow = layer.mode != .hourly && layer.showLow != false
        HStack(spacing: 0) {
            if shown.isEmpty { Text(verbatim: BindingResolver.missing).frame(maxWidth: .infinity) }
            ForEach(Array(shown.enumerated()), id: \.offset) { index, column in
                HStack(spacing: 0) {
                    if index > 0, let divider = layer.dividerColor {
                        Rectangle().fill(Color(hex: divider)).frame(width: max(0.5, scale))
                    }
                    VStack(spacing: 3 * scale) {
                        Text(verbatim: column.label)
                            .font(FontRegistry.font(label, size: label.size * scale, for: column.label))
                            .foregroundStyle(secondary)
                        if layer.showIcons != false {
                            Image(systemName: IconRendering.symbol(Icons.styled(column.symbol, layer.iconStyle)))
                                .font(.system(size: font.size * 1.25 * scale))
                                .foregroundStyle(color)
                        }
                        Text(verbatim: column.high)
                            .font(FontRegistry.font(font, size: font.size * scale, for: column.high))
                            .foregroundStyle(color)
                        if showLow, let low = column.low {
                            Text(verbatim: low)
                                .font(FontRegistry.font(label, size: label.size * scale, for: low))
                                .foregroundStyle(secondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
