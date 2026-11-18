import SwiftUI

/// `calendarMonth` (ADR-019): title, weekday row and day grid of the render date's month.
/// `mirrored` reverses the column order (right-to-left week); digits keep their shape.
struct CalendarMonthView: View {
    let layer: CalendarMonthLayer
    let resolver: BindingResolver
    let scale: CGFloat
    let mirrored: Bool
    @Environment(\.specAccented) private var accented

    var body: some View {
        let context = resolver.context
        let layout = CalendarMonthLayout(layer: layer, date: context.date, timeZone: context.timeZone,
                                         localeIdentifier: context.localeIdentifier)
        GeometryReader { proxy in
            let titleHeight = layout.title.isEmpty ? 0 : layer.effectiveTitleFont.size * 1.35 * scale
            let headerHeight = layout.weekdays.isEmpty ? 0 : layer.effectiveWeekdayFont.size * 1.7 * scale
            let cellWidth = proxy.size.width / 7
            let cellHeight = max(0, (proxy.size.height - titleHeight - headerHeight) / CGFloat(max(layout.rows.count, 1)))
            let columns = mirrored ? Array((0..<7).reversed()) : Array(0..<7)
            VStack(spacing: 0) {
                if !layout.title.isEmpty {
                    title(layout.title, inset: cellWidth * 0.18)
                        .frame(width: proxy.size.width, height: titleHeight)
                }
                if !layout.weekdays.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(columns, id: \.self) { column in
                            label(layout.weekdays[column], font: layer.effectiveWeekdayFont,
                                  color: layout.weekendColumns[column] ? layer.weekendColor ?? weekdayColor : weekdayColor)
                                .frame(width: cellWidth, height: headerHeight)
                        }
                    }
                }
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(columns, id: \.self) { column in
                            cell(row[column], width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private var weekdayColor: String { layer.weekdayColor ?? layer.color }

    private func title(_ text: String, inset: CGFloat) -> some View {
        let align: TextAlign = {
            let align = layer.titleAlign ?? .leading
            guard mirrored else { return align }
            return align == .leading ? .trailing : align == .trailing ? .leading : .center
        }()
        let font = layer.effectiveTitleFont
        return Text(verbatim: text)
            .font(FontRegistry.font(font, size: font.size * scale, for: text))
            .foregroundStyle(Color(hex: layer.titleColor ?? layer.color))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, inset)
            .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : align == .trailing ? .trailing : .center)
    }

    private func label(_ text: String, font: FontSpec, color: String) -> some View {
        Text(verbatim: text)
            .font(FontRegistry.font(font, size: font.size * scale, for: text))
            .foregroundStyle(Color(hex: color))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder private func cell(_ cell: CalendarMonthLayout.Cell, width: CGFloat, height: CGFloat) -> some View {
        let side = min(width, height) * 0.86
        // Accented mode: today's box and circle become outlines in the accent tint (ADR-023).
        let base = layer.todayStyle ?? .filled
        let style: CalendarMonthLayer.TodayStyle = accented && (base == .filled || base == .circle) ? .ring : base
        let highlight = Color(hex: layer.todayColor ?? layer.color)
        let onHighlight = cell.isToday && (style == .filled || style == .circle)
        ZStack {
            if cell.isToday {
                switch style {
                case .filled: RoundedRectangle(cornerRadius: side * 0.28, style: .continuous).fill(highlight).frame(width: side, height: side)
                case .circle: Circle().fill(highlight).frame(width: side, height: side)
                case .ring: Circle().stroke(highlight, lineWidth: max(1, 1.5 * scale)).frame(width: side, height: side)
                    .widgetAccentableIf(accented)
                case .dot: Circle().fill(highlight).frame(width: side * 0.16, height: side * 0.16).offset(y: side * 0.42)
                case .none: EmptyView()
                }
            }
            if let day = cell.day {
                let color = onHighlight ? layer.todayTextColor ?? "#FFFFFF" : cell.isWeekend ? layer.weekendColor ?? layer.color : layer.color
                label("\(day)", font: layer.font, color: color)
                    .opacity(cell.isOtherMonth ? 0.3 : 1)
            }
        }
        .frame(width: width, height: height)
    }
}

/// `list` (ADR-019): equal-height rows with marker, title and trailing detail. `mirrored`
/// reverses each row's order and alignment.
struct ListLayerView: View {
    let layer: ListLayer
    let resolver: BindingResolver
    let scale: CGFloat
    let mirrored: Bool

    var body: some View {
        GeometryReader { proxy in
            let rowHeight = proxy.size.height / CGFloat(max(layer.items.count, 1))
            VStack(spacing: 0) {
                ForEach(Array(layer.items.enumerated()), id: \.offset) { index, item in
                    row(item, height: rowHeight)
                        .frame(width: proxy.size.width, height: rowHeight)
                        .overlay(alignment: .bottom) {
                            if let divider = layer.dividerColor, index < layer.items.count - 1 {
                                Rectangle().fill(Color(hex: divider)).frame(height: max(0.5, 0.75 * scale))
                            }
                        }
                }
            }
        }
    }

    private var size: CGFloat { layer.font.size * scale }

    @ViewBuilder private func row(_ item: ListLayer.Item, height: CGFloat) -> some View {
        let isDone = item.done.map(resolver.isSatisfied) ?? false
        let secondary = layer.detailColor.map(Color.init(hex:)) ?? Color(hex: layer.color).opacity(0.6)
        // ADR-029: a subtitle under the title and a second detail under the first.
        let title = VStack(alignment: mirrored ? .trailing : .leading, spacing: 0) {
            text(item.title, color: Color(hex: layer.color).opacity(isDone ? 0.5 : 1))
            if let subtitle = item.subtitle { text(subtitle, color: secondary, small: true) }
        }
        let detail = item.detail.map { first in
            VStack(alignment: mirrored ? .leading : .trailing, spacing: 0) {
                text(first, color: secondary, small: item.detail2 != nil)
                if let second = item.detail2 { text(second, color: secondary, small: true) }
            }
        }
        HStack(spacing: 8 * scale) {
            if mirrored {
                detail
                Spacer(minLength: 4 * scale)
                title
                marker(item, height: height)
            } else {
                marker(item, height: height)
                title
                Spacer(minLength: 4 * scale)
                detail
            }
        }
    }

    private func text(_ value: LocalizedText, color: Color, small: Bool = false) -> some View {
        let rendered = BidiText.isolatingNumbers(resolver.render(value.resolved(language: resolver.context.language)))
        return Text(verbatim: rendered)
            .font(FontRegistry.font(layer.font, size: size * (small ? 0.82 : 1), for: rendered))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder private func marker(_ item: ListLayer.Item, height: CGFloat) -> some View {
        // A row color may be a binding: a calendar's own color (ADR-029).
        let color = Color(hex: item.color.map(resolver.render) ?? layer.markerColor ?? layer.color)
        // A row with a done state is a checkbox, whatever the list's marker says.
        switch item.done.map({ resolver.isSatisfied($0) ? ListLayer.Marker.check : .circle }) ?? layer.marker ?? .none {
        case .none: EmptyView()
        case .dot: Circle().fill(color).frame(width: size * 0.45, height: size * 0.45)
        case .circle: Circle().stroke(color, lineWidth: max(1, 1.5 * scale)).frame(width: size * 0.95, height: size * 0.95)
        case .check: Image(systemName: "checkmark.circle.fill").font(.system(size: size)).foregroundStyle(color)
        case .icon:
            Image(systemName: item.icon.flatMap { Icons.isAllowed($0) ? $0 : nil } ?? "circle.fill")
                .font(.system(size: size * 0.9))
                .foregroundStyle(color)
                .frame(width: size * 1.2)
        case .bar: RoundedRectangle(cornerRadius: 1.5 * scale).fill(color).frame(width: 3 * scale, height: height * 0.76)
        }
    }
}

/// `progressBar` (ADR-019): continuous or segmented; `mirrored` fills from the right.
struct ProgressBarView: View {
    let layer: ProgressBarLayer
    let progress: Double
    let scale: CGFloat
    let mirrored: Bool
    @Environment(\.specAccented) private var accented

    var body: some View {
        GeometryReader { proxy in
            let value = min(max(progress, 0), 1)
            let vertical = layer.vertical == true
            let radius = layer.cornerRadius.map { $0 * scale } ?? (vertical ? proxy.size.width : proxy.size.height) / 2
            let fill = Color(hex: layer.color)
            let track = Accented.fill(layer.trackColor ?? "#8080804D", accented: accented)
            let segments = layer.segments ?? 1
            if vertical {
                if segments > 1 {
                    let lit = Int((value * Double(segments)).rounded())
                    VStack(spacing: max(1, 2 * scale)) {
                        ForEach(0..<segments, id: \.self) { index in
                            RoundedRectangle(cornerRadius: min(radius, proxy.size.width / 2), style: .continuous)
                                .fill(index >= segments - lit ? fill : track)
                        }
                    }
                } else {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(track)
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
                            .frame(height: proxy.size.height * value)
                            .widgetAccentableIf(accented)
                    }
                }
            } else if segments > 1 {
                let lit = Int((value * Double(segments)).rounded())
                HStack(spacing: max(1, 2 * scale)) {
                    ForEach(0..<segments, id: \.self) { index in
                        let on = mirrored ? index >= segments - lit : index < lit
                        RoundedRectangle(cornerRadius: min(radius, proxy.size.height / 2), style: .continuous).fill(on ? fill : track)
                    }
                }
            } else {
                ZStack(alignment: mirrored ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(track)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
                        .frame(width: proxy.size.width * value)
                        .widgetAccentableIf(accented)
                }
            }
            // ADR-029: a round knob at the fill's end.
            if let knob = layer.knob {
                let side = knob.size.map { $0 * scale } ?? 2 * min(proxy.size.width, proxy.size.height)
                let x = vertical ? proxy.size.width / 2 : (mirrored ? proxy.size.width * (1 - value) : proxy.size.width * value)
                let y = vertical ? proxy.size.height * (1 - value) : proxy.size.height / 2
                Circle().fill(Color(hex: knob.color ?? layer.color)).frame(width: side, height: side).position(x: x, y: y)
            }
        }
    }
}
