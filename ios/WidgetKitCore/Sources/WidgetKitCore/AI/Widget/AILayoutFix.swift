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
/// ADR-022): icons drawn bigger than their frame shrink to it; layers whose text (or an icon
/// over text) cover each other are wrapped in one stack over their combined frame, or, when a
/// stack can't hold them (lists, calendars, forecasts), moved apart into bands. Repeats until
/// nothing overlaps or `maxPasses` is reached.
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
        for _ in 0..<maxPasses {
            guard let group = firstGroup(in: layers) else { break }
            if LayerEditing.group(group, in: &layers) == nil {
                LayerEditing.reflow(group, in: &layers)
            }
        }
        var fixed = spec
        fixed.layers = layers
        return fixed
    }

    /// The layers connected by overlaps that include the lowest overlapping index.
    static func firstGroup(in layers: [Layer]) -> [Int]? {
        let pairs = SpecLayout.textOverlaps(in: layers) + SpecLayout.iconOverlaps(in: layers)
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
}
