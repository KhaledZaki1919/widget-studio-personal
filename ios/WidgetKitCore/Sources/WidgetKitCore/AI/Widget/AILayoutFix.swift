import Foundation

/// What happened to the layout of an AI answer (M6.1, ADR-022).
public enum LayoutRepair: Sendable, Equatable {
    /// The answer had no layout problems.
    case clean
    /// The last answer still had overlaps and `AILayoutFix` removed them; `before` is the spec as
    /// the model wrote it (the eval renders both).
    case fixed(before: WidgetSpec)
    /// Overlaps are left after the fix; the result opens in the editor with these problems so
    /// the user can finish it in the layer editor.
    case needsEditing([String])
}

/// Repairs the layout of the last AI answer locally, so the user always gets a widget (M6.1,
/// ADR-022):
/// 1. icons drawn bigger than their frame shrink to it;
/// 2. a text hidden under a shape drawn after it moves just above that shape;
/// 3. layers whose text (or an icon over text) cover each other are put in one stack over their
///    combined frame: rows held apart by spacers, in a column (`LayerEditing.group`). Only layers
///    in the same container shape are grouped, so a time stays in its pill. Layers a stack can't
///    hold (lists, calendars, forecasts) are moved apart into bands instead.
/// Repeats until nothing overlaps or `maxPasses` is reached. Stacks always fit their frame
/// (`StackLayerView` shrinks the content), so nothing leaves the canvas.
public enum AILayoutFix {
    static let maxPasses = 8

    public static func fix(_ spec: WidgetSpec) -> WidgetSpec {
        var layers = spec.layers
        for index in layers.indices {
            if case .icon(var icon) = layers[index].content {
                let side = min(layers[index].frame.w, layers[index].frame.h)
                if icon.size > side * 1.15 {
                    icon.size = side.rounded(.down)
                    layers[index].content = .icon(icon)
                }
            }
        }
        raiseCoveredTexts(&layers)
        let canvas = spec.canvas
        for _ in 0..<maxPasses {
            if let group = firstGroup(in: layers, canvas: canvas) {
                if LayerEditing.group(group, in: &layers) == nil {
                    LayerEditing.reflow(group, in: &layers)
                }
            } else if !trimAcrossContainers(&layers, canvas: canvas) {
                break
            }
        }
        var fixed = spec
        fixed.layers = layers
        return fixed
    }

    /// Moves each text that a shape hides to just above that shape.
    static func raiseCoveredTexts(_ layers: inout [Layer]) {
        for _ in 0..<layers.count {
            guard let (cover, text) = SpecLayout.coveredTexts(in: layers).first else { return }
            let layer = layers.remove(at: text)
            layers.insert(layer, at: cover)   // the cover moved down by one: this is just above it
        }
    }

    /// The layers connected by overlaps that include the lowest overlapping index, counting only
    /// pairs that sit in the same container shape.
    static func firstGroup(in layers: [Layer], canvas: CGSize) -> [Int]? {
        let pairs = (SpecLayout.textOverlaps(in: layers) + SpecLayout.iconOverlaps(in: layers)).filter {
            SpecLayout.container(of: $0.0, in: layers, canvas: canvas) == SpecLayout.container(of: $0.1, in: layers, canvas: canvas)
        }
        guard let start = pairs.flatMap({ [$0.0, $0.1] }).min() else { return nil }
        var group: Set<Int> = [start]
        var grew = true
        while grew {
            grew = false
            for (a, b) in pairs where group.contains(a) != group.contains(b) {
                group.insert(a)
                group.insert(b)
                grew = true
            }
        }
        return group.sorted()
    }

    /// A layer outside a shape that overlaps a text inside it gives way: its frame shrinks to the
    /// largest part (above, below, left or right) that clears the shape, if that keeps at least
    /// 35 % of it. False when there is nothing to trim (or it can't be trimmed).
    static func trimAcrossContainers(_ layers: inout [Layer], canvas: CGSize) -> Bool {
        let pairs = SpecLayout.textOverlaps(in: layers) + SpecLayout.iconOverlaps(in: layers)
        for (a, b) in pairs {
            let containerA = SpecLayout.container(of: a, in: layers, canvas: canvas)
            let containerB = SpecLayout.container(of: b, in: layers, canvas: canvas)
            guard containerA != containerB else { continue }
            // The layer without a container (or in the bigger one) gives way.
            let (outside, inner) = containerA == nil ? (a, containerB) : containerB == nil ? (b, containerA) : (a, containerB)
            guard let inner, let trimmed = clear(layers[outside].frame, of: layers[inner].frame) else { continue }
            layers[outside].frame = trimmed
            return true
        }
        return false
    }

    static func clear(_ frame: Frame, of box: Frame) -> Frame? {
        let candidates = [
            Frame(x: frame.x, y: frame.y, w: frame.w, h: box.y - frame.y),
            Frame(x: frame.x, y: box.y + box.h, w: frame.w, h: frame.y + frame.h - (box.y + box.h)),
            Frame(x: frame.x, y: frame.y, w: box.x - frame.x, h: frame.h),
            Frame(x: box.x + box.w, y: frame.y, w: frame.x + frame.w - (box.x + box.w), h: frame.h),
        ].filter { $0.w >= 20 && $0.h >= 12 }
        guard let best = candidates.max(by: { $0.w * $0.h < $1.w * $1.h }), best.w * best.h >= 0.35 * frame.w * frame.h else { return nil }
        return best
    }

    /// Every text a spec shows, in reading order (the fix must keep them all).
    static func texts(in spec: WidgetSpec) -> [String] {
        spec.allLayers.flatMap { layer -> [String] in
            switch layer.content {
            case .text(let text): text.value.allValues
            case .list(let list): list.items.flatMap { $0.title.allValues + ($0.detail?.allValues ?? []) }
            default: []
            }
        }.sorted()
    }
}
