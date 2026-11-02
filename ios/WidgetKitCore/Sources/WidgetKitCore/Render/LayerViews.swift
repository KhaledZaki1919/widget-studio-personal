import SwiftUI

struct TextLayerView: View {
    let layer: TextLayer
    let resolver: BindingResolver
    let scale: CGFloat
    /// Swaps leading and trailing alignment (RTL `mirror`); the text itself is never flipped.
    let mirrored: Bool
    /// The axes the text fills (its frame); inside a stack it keeps its natural size (M6.1).
    var fill: Axis.Set = [.horizontal, .vertical]

    var body: some View {
        let raw = layer.value.resolved(language: resolver.context.language)
        let value = BidiText.isolatingNumbers(resolver.render(raw))
        let arabic = FontRegistry.containsArabic(value)
        content(value)
            // Arabic text set in a Latin family falls back to `arabic` one point larger (TEMPLATES.md).
            .font(FontRegistry.font(layer.font, size: (layer.font.size + (arabic && layer.font.family != "arabic" ? 1 : 0)) * scale,
                                    for: value))
            // Letter spacing breaks Arabic letter joining, so tracking applies to Latin text only.
            .tracking(arabic ? 0 : (layer.tracking ?? 0) * scale)
            .foregroundStyle(Color(hex: layer.color))
            .multilineTextAlignment(textAlignment)
            .lineLimit(layer.maxLines ?? 1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: fill.contains(.horizontal) ? .infinity : nil,
                   maxHeight: fill.contains(.vertical) ? .infinity : nil, alignment: frameAlignment)
    }

    @ViewBuilder private func content(_ value: String) -> some View {
        let now = resolver.context.date
        let target = layer.live?.target.flatMap(resolver.date)
        let frozen = resolver.context.freezesLiveText
        switch layer.live?.kind {
        case .time?:
            Text(now, style: .time)
        case .relative?:
            if let target {
                if frozen {
                    Text(verbatim: Self.frozen(from: now, to: target, locale: resolver.context.localeIdentifier))
                } else {
                    Text(target, style: .relative)
                }
            } else {
                Text(verbatim: BindingResolver.missing)
            }
        case .timer?:
            if let target {
                if frozen {
                    Text(verbatim: Self.frozen(from: now, to: target, locale: resolver.context.localeIdentifier))
                } else {
                    // Counts down to a future target, up from a past one.
                    Text(timerInterval: min(now, target)...max(now, target), countsDown: target > now)
                }
            } else {
                Text(verbatim: BindingResolver.missing)
            }
        case nil:
            styled(value)
        }
    }

    /// "2 months, 10 days" from `now` to `target`, as fixed text.
    static func frozen(from now: Date, to target: Date, locale: String) -> String {
        let formatter = DateComponentsFormatter()
        formatter.calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: locale)
            return calendar
        }()
        formatter.allowedUnits = [.month, .day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: min(now, target), to: max(now, target)) ?? BindingResolver.missing
    }

    /// Doto has no good degree sign, so in `dot` text "°" is drawn in the system font.
    private func styled(_ value: String) -> Text {
        guard FontRegistry.effectiveFamily(layer.font, for: value) == "dot", value.contains("°") else {
            return Text(verbatim: value)
        }
        let degree = Font.system(size: layer.font.size * scale * 0.8, weight: (layer.font.weight ?? .regular).swiftUI)
        return value.split(separator: "°", omittingEmptySubsequences: false).enumerated().reduce(Text(verbatim: "")) { text, part in
            let piece = Text(verbatim: String(part.element))
            return part.offset == 0 ? text + piece : text + Text(verbatim: "°").font(degree) + piece
        }
    }

    private var alignment: TextAlign {
        let align = layer.align ?? .leading
        guard mirrored else { return align }
        switch align {
        case .leading: return .trailing
        case .center: return .center
        case .trailing: return .leading
        }
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

struct ImageLayerView: View {
    let layer: ImageLayer
    let image: CGImage?
    let scale: CGFloat

    var body: some View {
        picture
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(mask)
    }

    @ViewBuilder private var picture: some View {
        if layer.source == "user_image", let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: layer.fit == .fit ? .fit : .fill)
        } else {
            // No photo yet (or an asset that arrives with the template library): a neutral placeholder.
            ZStack {
                Color.gray.opacity(0.25)
                Image(systemName: "photo")
                    .font(.system(size: 18 * scale))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mask: AnyShape {
        switch layer.mask ?? .rect {
        case .rect: AnyShape(Rectangle())
        case .roundedRect: AnyShape(RoundedRectangle(cornerRadius: (layer.cornerRadius ?? 16) * scale, style: .continuous))
        case .circle: AnyShape(Circle())
        }
    }
}

struct ShapeLayerView: View {
    let layer: ShapeLayer
    let scale: CGFloat

    var body: some View {
        ZStack {
            if let fill = layer.fill {
                shape.fill(Color(hex: fill))
            }
            if let stroke = layer.stroke {
                shape.stroke(Color(hex: stroke.color), style: StrokeStyle(
                    lineWidth: stroke.width * scale,
                    dash: (stroke.dash ?? []).map { $0 * scale }
                ))
            }
        }
    }

    private var shape: AnyShape {
        switch layer.kind {
        case .rect: AnyShape(Rectangle())
        case .roundedRect: AnyShape(RoundedRectangle(cornerRadius: (layer.cornerRadius ?? 16) * scale, style: .continuous))
        case .circle: AnyShape(Circle())
        case .capsule: AnyShape(Capsule())
        }
    }
}

struct IconLayerView: View {
    let layer: IconLayer
    let resolver: BindingResolver
    let scale: CGFloat

    var body: some View {
        let symbol = resolver.soleValue(layer.symbol)?.display ?? layer.symbol
        Image(systemName: Icons.isAllowed(symbol) ? symbol : "questionmark")
            .font(.system(size: layer.size * scale))
            .foregroundStyle(Color(hex: layer.color))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RingView: View {
    let layer: RingLayer
    let progress: Double
    let scale: CGFloat

    var body: some View {
        let width = layer.lineWidth * scale
        ZStack {
            Circle()
                .stroke(Color(hex: layer.trackColor ?? "#FFFFFF33"), lineWidth: width)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color(hex: layer.color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(width / 2)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Invisible tap area (brief §4.4). The widget extension can supply its own control per action
/// (`specActionButton`: interactive AppIntent buttons for counter and stopwatch, ADR-016);
/// everything else is a link that opens the app, which performs the action (e.g. runs a Shortcut).
struct ButtonLayerView: View {
    let layer: ButtonLayer
    let resolver: BindingResolver
    @Environment(\.specActionButton) private var custom

    var body: some View {
        if let custom, let button = custom(layer.action, layer.arg.map(resolver.render)) {
            button
        } else if let url = actionURL {
            Link(destination: url) {
                Color.clear.contentShape(Rectangle())
            }
        } else {
            Color.clear
        }
    }

    /// `widgetstudio://action/<action>?arg=<value>&spec=<id>`
    var actionURL: URL? {
        var components = URLComponents()
        components.scheme = "widgetstudio"
        components.host = "action"
        components.path = "/" + layer.action.rawValue
        var items = [URLQueryItem(name: "spec", value: resolver.spec.id)]
        if let arg = layer.arg { items.append(URLQueryItem(name: "arg", value: resolver.render(arg))) }
        components.queryItems = items
        return components.url
    }
}

/// Builds the control for a button action, or nil to use the default link (ADR-016).
public typealias SpecActionButton = (ButtonLayer.Action, String?) -> AnyView?

private struct SpecActionButtonKey: EnvironmentKey {
    static let defaultValue: SpecActionButton? = nil
}

extension EnvironmentValues {
    /// Set by the widget extension to make counter and stopwatch buttons interactive.
    public var specActionButton: SpecActionButton? {
        get { self[SpecActionButtonKey.self] }
        set { self[SpecActionButtonKey.self] = newValue }
    }
}
