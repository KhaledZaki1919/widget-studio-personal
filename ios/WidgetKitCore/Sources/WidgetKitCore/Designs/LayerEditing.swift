import CoreGraphics
import Foundation

/// The layer editor's operations (M6.1, ADR-022), on a spec's layer tree. A path addresses a
/// layer: `[3]` is the fourth top-level layer, `[3, 0]` the first child of that stack. The AI
/// layout fix (`AILayoutFix`) uses the same grouping and reflow. Every result still goes
/// through `DesignEditing.validate` before it can be saved.
public enum LayerEditing {
    public typealias Path = [Int]

    public static func layer(at path: Path, in layers: [Layer]) -> Layer? {
        guard let first = path.first, layers.indices.contains(first) else { return nil }
        let layer = layers[first]
        guard path.count > 1 else { return layer }
        guard case .stack(let stack) = layer.content else { return nil }
        return self.layer(at: Array(path.dropFirst()), in: stack.children)
    }

    public static func replace(at path: Path, in layers: inout [Layer], with layer: Layer) {
        guard let last = path.last else { return }
        siblings(of: path, in: &layers) { list in
            if list.indices.contains(last) { list[last] = layer }
        }
    }

    public static func remove(at path: Path, in layers: inout [Layer]) {
        guard let last = path.last else { return }
        siblings(of: path, in: &layers) { list in
            // A stack keeps at least one child; remove the stack itself instead.
            if list.indices.contains(last), path.count == 1 || list.count > 1 { list.remove(at: last) }
        }
    }

    /// Inserts a copy after the layer; a top-level copy moves 6 units so both stay visible.
    public static func duplicate(at path: Path, in layers: inout [Layer]) {
        guard let last = path.last else { return }
        siblings(of: path, in: &layers) { list in
            guard list.indices.contains(last) else { return }
            var copy = list[last]
            if path.count == 1 {
                copy.frame.x += 6
                copy.frame.y += 6
            }
            list.insert(copy, at: last + 1)
        }
    }

    /// Reorders the children of `parent` (`[]` = the top level), like `List.onMove`.
    public static func move(in parent: Path, from source: IndexSet, to destination: Int, layers: inout [Layer]) {
        siblings(of: parent + [0], in: &layers) { list in
            let moving = source.sorted().filter(list.indices.contains).map { list[$0] }
            let before = source.filter { $0 < destination }.count
            for index in source.sorted(by: >) where list.indices.contains(index) { list.remove(at: index) }
            list.insert(contentsOf: moving, at: min(max(destination - before, 0), list.count))
        }
    }

    /// Runs `body` on the list that holds the layer at `path`.
    static func siblings(of path: Path, in layers: inout [Layer], _ body: (inout [Layer]) -> Void) {
        guard let first = path.first else { return }
        if path.count == 1 {
            body(&layers)
            return
        }
        guard layers.indices.contains(first), case .stack(var stack) = layers[first].content else { return }
        siblings(of: Array(path.dropFirst()), in: &stack.children, body)
        layers[first].content = .stack(stack)
    }

    // MARK: Stacks

    /// Types a stack can lay out (`SpecValidator.checkStack`).
    public static func canStack(_ layer: Layer) -> Bool {
        switch layer.content {
        case .text, .icon, .stack, .shape, .ring, .progressBar, .analogClock: true
        default: false
        }
    }

    /// 0 for a plain layer, 1 + the deepest child for a stack.
    static func depth(_ layer: Layer) -> Int {
        guard case .stack(let stack) = layer.content else { return 0 }
        return 1 + (stack.children.map(depth).max() ?? 0)
    }

    /// Side by side only when the layers clearly spread across more than down (by their centers);
    /// texts piled on one spot become a column, the usual widget layout.
    static func axis(for frames: [Frame]) -> StackLayer.Axis {
        let xs = frames.map { $0.x + $0.w / 2 }
        let ys = frames.map { $0.y + $0.h / 2 }
        let spreadX = (xs.max() ?? 0) - (xs.min() ?? 0)
        let spreadY = (ys.max() ?? 0) - (ys.min() ?? 0)
        return spreadX > max(spreadY * 2, 20) ? .horizontal : .vertical
    }

    /// Order along the axis by center: a tall list that starts higher than its header (a frame
    /// clamped to the canvas) still goes after it (eval 2026-11-01).
    static func precedes(_ a: Frame, _ b: Frame, axis: StackLayer.Axis) -> Bool {
        axis == .horizontal ? (a.x + a.w / 2, a.y) < (b.x + b.w / 2, b.y) : (a.y + a.h / 2, a.x) < (b.y + b.h / 2, b.x)
    }

    static func union(_ frames: [Frame]) -> Frame {
        let minX = frames.map(\.x).min() ?? 0
        let minY = frames.map(\.y).min() ?? 0
        let maxX = frames.map { $0.x + $0.w }.max() ?? 0
        let maxY = frames.map { $0.y + $0.h }.max() ?? 0
        return Frame(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    /// Wraps top-level layers in one stack over their combined frame, ordered by position, and
    /// returns its index (where the topmost of them was). nil when a layer can't go in a stack,
    /// there are too many, or the nesting would be too deep.
    @discardableResult
    public static func group(_ indexes: [Int], in layers: inout [Layer], axis chosen: StackLayer.Axis? = nil) -> Int? {
        let members = Array(Set(indexes)).sorted().filter(layers.indices.contains)
        guard members.count >= 2, members.count <= SpecValidator.maxChildren else { return nil }
        let picked = members.map { layers[$0] }
        guard picked.allSatisfy(canStack), (picked.map(depth).max() ?? 0) + 1 <= SpecValidator.maxStackDepth else { return nil }

        let frames = picked.map(\.frame)
        let axis = chosen ?? Self.axis(for: frames)
        let ordered = picked.sorted { a, b in
            precedes(a.frame, b.frame, axis: axis)
        }
        let children = ordered.map { member -> Layer in
            var child = member
            switch member.content {
            case .text, .icon:
                // Natural size: texts wrap and shrink to fit, icons keep their symbol size.
                child.frame = Frame(x: 0, y: 0, w: 0, h: 0)
            default:
                child.frame = Frame(x: 0, y: 0, w: member.frame.w, h: member.frame.h)
            }
            child.mirror = nil
            return child
        }
        let stack = StackLayer(axis: axis, spacing: spacing(ordered.map(\.frame), axis: axis),
                               alignItems: alignment(ordered, axis: axis), children: children)
        let stackLayer = Layer(frame: union(frames), mirror: picked.contains { $0.mirror == true } ? true : nil,
                               content: .stack(stack))
        let top = members.last ?? 0
        for index in members.reversed() { layers.remove(at: index) }
        let position = top - (members.count - 1)
        layers.insert(stackLayer, at: position)
        return position
    }

    /// The gap the layers had between them, 2…12 units (default 4).
    static func spacing(_ frames: [Frame], axis: StackLayer.Axis) -> Double {
        let gaps = zip(frames, frames.dropFirst()).map { a, b in
            axis == .horizontal ? b.x - (a.x + a.w) : b.y - (a.y + a.h)
        }.filter { $0 > 0 }
        guard !gaps.isEmpty else { return StackLayer.defaultSpacing }
        return min(max((gaps.reduce(0, +) / Double(gaps.count)).rounded(), 2), 12)
    }

    /// Vertical stacks follow the texts' alignment; horizontal ones center their items.
    static func alignment(_ layers: [Layer], axis: StackLayer.Axis) -> StackLayer.Align? {
        guard axis == .vertical else { return nil }
        let aligns = layers.compactMap { layer -> TextAlign? in
            if case .text(let text) = layer.content { return text.align ?? .leading }
            return nil
        }
        switch aligns.first ?? .leading {
        case .leading: return nil
        case .center: return .center
        case .trailing: return .end
        }
    }

    /// The stack's children back as top-level layers, in bands across its frame (the inverse of
    /// `group`, for the editor). Returns their indexes.
    @discardableResult
    public static func ungroup(at index: Int, in layers: inout [Layer]) -> [Int] {
        guard layers.indices.contains(index), case .stack(let stack) = layers[index].content else { return [] }
        let frame = layers[index].frame
        let horizontal = stack.axis == .horizontal
        let count = Double(stack.children.count)
        let freed = stack.children.enumerated().map { offset, child -> Layer in
            var layer = child
            let share = Double(offset)
            layer.frame = horizontal
                ? Frame(x: frame.x + frame.w * share / count, y: frame.y, w: frame.w / count, h: frame.h)
                : Frame(x: frame.x, y: frame.y + frame.h * share / count, w: frame.w, h: frame.h / count)
            layer.mirror = layers[index].mirror
            return layer
        }
        layers.remove(at: index)
        layers.insert(contentsOf: freed, at: index)
        return Array(index..<(index + freed.count))
    }

    /// Moves the layers apart without changing their types: their combined frame is split into
    /// bands along one axis, each as big as its share of the original sizes. For layers a stack
    /// can't hold (lists, calendars, forecasts).
    public static func reflow(_ indexes: [Int], in layers: inout [Layer]) {
        let members = Array(Set(indexes)).sorted().filter(layers.indices.contains)
        guard members.count >= 2 else { return }
        let frames = members.map { layers[$0].frame }
        let axis = axis(for: frames)
        let bounds = union(frames)
        let order = members.sorted { a, b in
            precedes(layers[a].frame, layers[b].frame, axis: axis)
        }
        let gap = 2.0
        let total = order.map { axis == .horizontal ? layers[$0].frame.w : layers[$0].frame.h }.reduce(0, +)
        let room = (axis == .horizontal ? bounds.w : bounds.h) - gap * Double(order.count - 1)
        guard total > 0, room > 0 else { return }
        var cursor = axis == .horizontal ? bounds.x : bounds.y
        for index in order {
            var frame = layers[index].frame
            if axis == .horizontal {
                frame.w = room * frame.w / total
                frame.x = cursor
                cursor += frame.w + gap
            } else {
                frame.h = room * frame.h / total
                frame.y = cursor
                cursor += frame.h + gap
            }
            layers[index].frame = frame
        }
    }
}
