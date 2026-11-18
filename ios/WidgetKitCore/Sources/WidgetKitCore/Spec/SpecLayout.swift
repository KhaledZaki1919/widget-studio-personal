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

    /// Every top-level layer that takes part in a text or icon overlap, or whose text is hidden
    /// under a shape (the layer editor marks them).
    public static func overlapping(in layers: [Layer]) -> Set<Int> {
        Set((textOverlaps(in: layers) + iconOverlaps(in: layers) + coveredTexts(in: layers)).flatMap { [$0.0, $0.1] })
    }

    /// Layers that hide what is drawn under them: filled shapes (at least half opaque), images,
    /// clocks and progress bars.
    public static func hidesWhatIsUnder(_ layer: Layer) -> Bool {
        switch layer.content {
        case .shape(let shape):
            guard let fill = shape.fill else { return false }
            return HexColor.parse(fill).map { $0.alpha >= 0.5 } ?? true   // tokens are opaque
        case .image, .analogClock, .progressBar: return true
        default: return false
        }
    }

    /// Share of `inner` that lies inside `outer` (0…1).
    static func share(of inner: Frame, inside outer: Frame) -> Double {
        let width = min(inner.x + inner.w, outer.x + outer.w) - max(inner.x, outer.x)
        let height = min(inner.y + inner.h, outer.y + outer.h) - max(inner.y, outer.y)
        guard width > 0, height > 0, inner.w > 0, inner.h > 0 else { return 0 }
        return width * height / (inner.w * inner.h)
    }

    /// Pairs (cover, text): a shape drawn on top of a text layer hides more than half of it
    /// (eval 2026-11-02: the time drawn before its orange pill was invisible).
    public static func coveredTexts(in layers: [Layer]) -> [(Int, Int)] {
        let texts = layers.indices.filter { layers[$0].showsText && layers[$0].when == nil }
        return texts.flatMap { text in
            layers.indices.filter { cover in
                cover > text && layers[cover].when == nil && hidesWhatIsUnder(layers[cover])
                    && share(of: layers[text].frame, inside: layers[cover].frame) > 0.5
            }.map { ($0, text) }
        }
    }

    /// The shape a layer sits in (a pill, a card smaller than half the widget): the smallest
    /// shape or ring drawn under it that holds at least 80 % of its frame. The layout fix only
    /// groups layers that share one, so a time never leaves its pill.
    public static func container(of index: Int, in layers: [Layer], canvas: CGSize) -> Int? {
        guard layers.indices.contains(index) else { return nil }
        let frame = layers[index].frame
        let limit = 0.5 * canvas.width * canvas.height
        return layers.indices.filter { candidate in
            guard candidate < index, layers[candidate].when == nil else { return false }
            switch layers[candidate].content {
            case .shape, .ring: break
            default: return false
            }
            let box = layers[candidate].frame
            return box.w * box.h < limit && share(of: frame, inside: box) >= 0.8
        }.min { layers[$0].frame.w * layers[$0].frame.h < layers[$1].frame.w * layers[$1].frame.h }
    }
}
