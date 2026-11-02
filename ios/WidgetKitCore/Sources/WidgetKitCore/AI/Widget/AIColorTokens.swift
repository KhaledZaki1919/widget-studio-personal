import Foundation

/// AI output to theme tokens (M6.1): models often write the palette as plain hex, which the
/// editor's color pickers can't reach. Every hex close to `bg`, `fg` or `accent` becomes that
/// token, and the most frequent grayish secondary text color becomes `@muted` (with its value
/// kept as the design's `muted` override), so the global pickers work as they do for templates.
public enum AIColorTokens {
    /// How close (0…√3 in RGB) a color must be to count as the palette color.
    static let tolerance = 0.09

    public static func tokenize(_ value: JSONValue, colors: inout [String: String]) -> JSONValue {
        let palette: [(String, HexColor)] = ["accent", "bg", "fg"].compactMap { token in colors[token].flatMap(HexColor.parse).map { (token, $0) } }
        if colors["muted"] == nil, let muted = secondaryColor(in: value, palette: palette.map(\.1)) {
            colors["muted"] = muted
        }
        var all = palette
        if let muted = colors["muted"].flatMap(HexColor.parse) { all.append(("muted", muted)) }
        return replace(value, with: all)
    }

    static func replace(_ value: JSONValue, with palette: [(String, HexColor)]) -> JSONValue {
        switch value {
        case .string(let text):
            guard let color = opaque(text), let match = palette.min(by: { distance($0.1, color) < distance($1.1, color) }),
                  distance(match.1, color) <= tolerance else { return value }
            return .string("@" + match.0)
        case .array(let items):
            return .array(items.map { replace($0, with: palette) })
        case .object(let fields):
            return .object(fields.mapValues { replace($0, with: palette) })
        default:
            return value
        }
    }

    /// The most used text color that isn't a palette color and is grayish (low saturation).
    static func secondaryColor(in value: JSONValue, palette: [HexColor]) -> String? {
        var counts: [String: Int] = [:]
        func visit(_ value: JSONValue) {
            switch value {
            case .object(let fields):
                if case .string("text")? = fields["type"], let hex = fields["color"]?.stringValue, let color = opaque(hex),
                   !palette.contains(where: { distance($0, color) <= tolerance }), isGrayish(color) {
                    counts[hex.uppercased(), default: 0] += 1
                }
                fields.values.forEach(visit)
            case .array(let items):
                items.forEach(visit)
            default:
                break
            }
        }
        visit(value)
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    static func opaque(_ text: String) -> HexColor? {
        guard let color = HexColor.parse(text), color.alpha > 0.99 else { return nil }
        return color
    }

    static func isGrayish(_ color: HexColor) -> Bool {
        let high = max(color.red, color.green, color.blue)
        let low = min(color.red, color.green, color.blue)
        return high - low < 0.12
    }

    static func distance(_ first: HexColor, _ second: HexColor) -> Double {
        let red = first.red - second.red
        let green = first.green - second.green
        let blue = first.blue - second.blue
        return (red * red + green * green + blue * blue).squareRoot()
    }
}
