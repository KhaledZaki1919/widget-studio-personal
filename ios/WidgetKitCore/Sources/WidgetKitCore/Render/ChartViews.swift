import SwiftUI

/// Hour and minute hands only: widgets update once a minute, so there is no seconds hand (brief §2).
struct AnalogClockView: View {
    let layer: AnalogClockLayer
    let resolver: BindingResolver
    @Environment(\.specAccented) private var accented

    var body: some View {
        let dark = resolver.spec.theme == .dark
        // Accented mode: the face is a faint disc with an outline, not a solid white circle (ADR-023).
        let face = Accented.fill(layer.faceColor ?? (dark ? "#1A1A1A" : "#FFFFFF"), accented: accented)
        let rim = accented
        let ink = Color(hex: layer.tickColor ?? (dark ? "#FFFFFF" : "#0E0E0E"))
        let hour = Color(hex: layer.hourColor ?? (dark ? "#FFFFFF" : "#0E0E0E"))
        let minute = Color(hex: layer.minuteColor ?? (dark ? "#FFFFFF" : "#0E0E0E"))
        let accent = Color(hex: layer.accentColor ?? "#E31C24")
        let clock = time
        Canvas { context, size in
            let hours = clock.hours
            let minutes = clock.minutes
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side / 2
            let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: side, height: side))
            context.fill(disc, with: .color(face))
            if rim {
                context.stroke(disc.strokedPath(StrokeStyle(lineWidth: 1)), with: .color(ink.opacity(Accented.outlineOpacity)))
            }

            // ADR-029: marks `60` (default), `12`, `dots` (default for style dot) or `none`.
            let ticks = layer.ticks ?? (layer.style == .dot ? .dots : .sixty)
            for tick in 0..<60 where ticks != AnalogClockLayer.Ticks.none {
                let isHour = tick % 5 == 0
                if (ticks == .dots || ticks == .twelve) && !isHour { continue }
                let angle = Double(tick) / 60 * 2 * .pi
                let direction = CGPoint(x: sin(angle), y: -cos(angle))
                if ticks == .dots {
                    let dot = radius * 0.07
                    let point = CGPoint(x: center.x + direction.x * radius * 0.82, y: center.y + direction.y * radius * 0.82)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)), with: .color(ink))
                } else {
                    let outer = radius * 0.92
                    let inner = radius * (isHour ? 0.76 : 0.86)
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + direction.x * inner, y: center.y + direction.y * inner))
                    path.addLine(to: CGPoint(x: center.x + direction.x * outer, y: center.y + direction.y * outer))
                    context.stroke(path, with: .color(ink), lineWidth: radius * (isHour ? 0.035 : 0.015))
                }
            }

            let cap: CGLineCap = layer.handCap == .flat ? .butt : .round
            Self.hand(in: &context, center: center, radius: radius,
                      fraction: (Double(hours % 12) + Double(minutes) / 60) / 12, length: layer.hourLength ?? 0.5, width: layer.hourWidth ?? 0.07,
                      color: hour, cap: cap)
            Self.hand(in: &context, center: center, radius: radius,
                      fraction: Double(minutes) / 60, length: layer.minuteLength ?? 0.75, width: layer.minuteWidth ?? 0.045, color: minute, cap: cap)
            // Seconds as of this entry (a hand or a dot on the rim), in the accent color.
            switch layer.seconds {
            case .hand?:
                Self.hand(in: &context, center: center, radius: radius, fraction: Double(clock.seconds) / 60, length: 0.85, width: 0.015,
                          color: accent, cap: .round)
            case .dot?:
                let angle = Double(clock.seconds) / 60 * 2 * .pi
                let dot = radius * 0.1
                let point = CGPoint(x: center.x + sin(angle) * radius * 0.86, y: center.y - cos(angle) * radius * 0.86)
                context.fill(Path(ellipseIn: CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)), with: .color(accent))
            default:
                break
            }
            if layer.centerDot != false {
                let pin = radius * 0.09
                context.fill(Path(ellipseIn: CGRect(x: center.x - pin / 2, y: center.y - pin / 2, width: pin, height: pin)), with: .color(accent))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // swiftlint:disable:next function_parameter_count
    private static func hand(in context: inout GraphicsContext, center: CGPoint, radius: Double,
                             fraction: Double, length: Double, width: Double, color: Color, cap: CGLineCap) {
        let angle = fraction * 2 * .pi
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + sin(angle) * radius * length, y: center.y - cos(angle) * radius * length))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: radius * width, lineCap: cap))
    }

    /// Hours, minutes and seconds in the clock's time zone (a timezone field, an IANA name or the device's).
    private var time: (hours: Int, minutes: Int, seconds: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = layer.timezone.flatMap(zone) ?? resolver.context.timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: resolver.context.date)
        return (parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    private func zone(_ value: String) -> TimeZone? {
        if let raw = Bindings.soleBinding(value), case .field(let key)? = Bindings.Name(raw) {
            return resolver.fieldValue(key).flatMap(TimeZone.init(identifier:))
        }
        return TimeZone(identifier: value)
    }
}

