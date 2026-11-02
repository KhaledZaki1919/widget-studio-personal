import Foundation

/// The overlap rule shared by the AI validator, the layout fix and the layer editor (M6.1,
/// ADR-022): two top-level frames collide when they share more than 20 % of the smaller one.
/// Only layers that show text (and icons over text) count; layers with a `when` condition are
/// exempt, since they may take turns.
public enum SpecLayout {
    public static let overlapShare = 0.2

    public static func collide(_ a: Frame, _ b: Frame) -> Bool {
        let width = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
        let height = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
        guard width > 0, height > 0 else { return false }
        return width * height > overlapShare * min(a.w * a.h, b.w * b.h)
    }

    /// Pairs of top-level layers (first < second) whose texts cover each other.
    public static func textOverlaps(in layers: [Layer]) -> [(Int, Int)] {
        let texts = layers.indices.filter { layers[$0].showsText && layers[$0].when == nil }
        var pairs: [(Int, Int)] = []
        for (position, first) in texts.enumerated() {
            for second in texts[(position + 1)...] where collide(layers[first].frame, layers[second].frame) {
                pairs.append((first, second))
            }
        }
        return pairs
    }

    /// Pairs (icon, text) of top-level layers where an icon covers text.
    public static func iconOverlaps(in layers: [Layer]) -> [(Int, Int)] {
        let icons = layers.indices.filter { if case .icon = layers[$0].content { layers[$0].when == nil } else { false } }
        let texts = layers.indices.filter { layers[$0].showsText && layers[$0].when == nil }
        return icons.flatMap { icon in
            texts.filter { collide(layers[icon].frame, layers[$0].frame) }.map { (icon, $0) }
        }
    }

    /// Every top-level layer that takes part in a text or icon overlap (the layer editor marks them).
    public static func overlapping(in layers: [Layer]) -> Set<Int> {
        Set((textOverlaps(in: layers) + iconOverlaps(in: layers)).flatMap { [$0.0, $0.1] })
    }
}
