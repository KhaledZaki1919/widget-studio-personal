import SwiftUI

/// Draws a validated spec (brief §3.2). The same view renders the in-app preview and the real
/// widget, so the preview is exact. Positions are canvas units scaled uniformly to the space
/// offered.
///
/// RTL (ADR-010): the canvas is always laid out left-to-right and nothing is ever flipped like an
/// image, so text, digits and clocks keep their shape. In Arabic, a layer with `mirror: true`
/// moves to the mirrored frame and swaps its own alignment and item order (`LayerView.mirrored`).
/// Layers without `mirror` stay exactly where they are.
public struct SpecView: View {
    let spec: WidgetSpec
    let context: RenderContext
    /// False inside a widget, which draws `SpecBackground` through `containerBackground`.
    let drawsBackground: Bool

    /// `spec` may use color tokens; they are resolved here for `context.theme ?? spec.theme`.
    public init(spec: WidgetSpec, context: RenderContext, drawsBackground: Bool = true) {
        self.spec = spec.resolvingTokens(theme: context.theme, overrides: context.tokenOverrides)
        self.context = context
        self.drawsBackground = drawsBackground
    }

    public var body: some View {
        GeometryReader { proxy in
            let canvas = spec.family.canvas
            // A spec shown in a larger widget is scaled uniformly and centered (ADR-011).
            let scale = min(proxy.size.width / canvas.width, proxy.size.height / canvas.height)
            let resolver = BindingResolver(spec: spec, context: context)
            ZStack {
                if drawsBackground {
                    SpecBackground(spec: spec)
                }
                ZStack(alignment: .topLeading) {
                    ForEach(Array(spec.layers.enumerated()), id: \.offset) { _, layer in
                        if layer.when.map(resolver.isSatisfied) ?? true {
                            let mirrored = context.isArabic && layer.mirror == true
                            let frame = mirrored ? layer.frame.mirrored(canvasWidth: canvas.width) : layer.frame
                            LayerView(layer: layer, resolver: resolver, scale: scale, mirrored: mirrored)
                                .frame(width: frame.w * scale, height: frame.h * scale)
                                .modifier(LayerRotation(degrees: layer.rotation.flatMap(resolver.number)))
                                .opacity(layer.opacity ?? 1)
                                .position(x: (frame.x + frame.w / 2) * scale, y: (frame.y + frame.h / 2) * scale)
                        }
                    }
                }
                .frame(width: canvas.width * scale, height: canvas.height * scale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Absolute canvas coordinates, whatever the host's direction.
        .environment(\.layoutDirection, .leftToRight)
        // Live texts (time, relative, timer) format in the spec's language with Latin digits.
        .environment(\.locale, context.locale)
        .environment(\.timeZone, context.timeZone)
        .environment(\.colorScheme, spec.theme == .dark ? .dark : .light)
    }
}

/// Rotates only layers that declare `rotation`, so the others render without an extra transform.
struct LayerRotation: ViewModifier {
    let degrees: Double?

    @ViewBuilder func body(content: Content) -> some View {
        if let degrees {
            content.rotationEffect(.degrees(degrees))
        } else {
            content
        }
    }
}

/// The spec's background. With `outerColor` (circle templates), the widget is filled with the
/// outer color and the background is drawn as the largest centered circle (brief §2).
public struct SpecBackground: View {
    let spec: WidgetSpec

    /// Resolves color tokens for `theme` (else the spec's own theme).
    public init(spec: WidgetSpec, theme: SpecTheme? = nil, overrides: [String: String] = [:]) {
        self.spec = spec.resolvingTokens(theme: theme, overrides: overrides)
    }

    public var body: some View {
        if let outer = spec.background.outerColor {
            ZStack {
                Color(hex: outer)
                fill.clipShape(Circle()).aspectRatio(1, contentMode: .fit)
            }
        } else {
            fill
        }
    }

    @ViewBuilder private var fill: some View {
        switch spec.background.type {
        case .solid:
            Color(hex: spec.background.color ?? "#000000")
        case .gradient:
            let angle = Angle(degrees: spec.background.angle ?? 90)
            let dx = cos(angle.radians) / 2
            let dy = sin(angle.radians) / 2
            LinearGradient(
                colors: (spec.background.colors ?? []).map { Color(hex: $0) },
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
            )
        }
    }
}

extension Color {
    /// A spec color; invalid strings (already rejected by the validator) draw as clear.
    public init(hex: String) {
        if let color = HexColor.parse(hex) {
            self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
        } else {
            self = .clear
        }
    }
}

/// One layer, filling the frame it is given. `mirrored` swaps leading/trailing alignment and
/// reverses horizontal item order; it never flips glyphs.
struct LayerView: View {
    let layer: Layer
    let resolver: BindingResolver
    let scale: CGFloat
    let mirrored: Bool

    var body: some View {
        switch layer.content {
        case .text(let text): TextLayerView(layer: text, resolver: resolver, scale: scale, mirrored: mirrored)
        case .image(let image): ImageLayerView(layer: image, image: resolver.context.userImage, scale: scale)
        case .shape(let shape): ShapeLayerView(layer: shape, scale: scale)
        case .icon(let icon): IconLayerView(layer: icon, resolver: resolver, scale: scale)
        case .analogClock(let clock): AnalogClockView(layer: clock, resolver: resolver)
        case .dotGrid(let grid):
            DotGridView(layer: grid, levels: resolver.levels(grid.values), scale: scale, mirrored: mirrored)
        case .dotBars(let bars): DotBarsView(layer: bars, resolver: resolver, scale: scale, mirrored: mirrored)
        case .ring(let ring): RingView(layer: ring, progress: resolver.number(ring.progress) ?? 0, scale: scale)
        case .forecastRow(let row): ForecastRowView(layer: row, resolver: resolver, scale: scale, mirrored: mirrored)
        case .button(let button): ButtonLayerView(layer: button, resolver: resolver)
        case .calendarMonth(let calendar): CalendarMonthView(layer: calendar, resolver: resolver, scale: scale, mirrored: mirrored)
        case .list(let list): ListLayerView(layer: list, resolver: resolver, scale: scale, mirrored: mirrored)
        case .progressBar(let bar):
            ProgressBarView(layer: bar, progress: resolver.number(bar.progress) ?? 0, scale: scale, mirrored: mirrored)
        case .stack(let stack): StackLayerView(layer: stack, resolver: resolver, scale: scale, mirrored: mirrored)
        case .spacer, .unknown: Color.clear
        }
    }
}
