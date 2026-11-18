import Foundation

/// A container laid out natively (M6.1, ADR-022): children are placed by SwiftUI stacks or a
/// grid instead of absolute frames, so texts can't run into each other. The stack itself has a
/// frame like any layer; its children give only an optional `width`/`height` (canvas units,
/// 0 or absent = natural size along that axis).
///
/// RTL (ADR-010): with `mirror: true` in Arabic, a horizontal stack or grid reverses its items
/// and `start`/`end` swap sides; glyphs never flip.
public struct StackLayer: Codable, Sendable, Equatable {
    /// `radial` (ADR-029): children around a circle, the first at `startAngle`, evenly spaced, each turned
    /// to face outward when `rotateChildren` is true (compass letters, clock numerals).
    public enum Axis: String, Codable, Sendable, CaseIterable { case vertical, horizontal, grid, radial }
    /// `start` is the leading edge (left in the canvas, right when mirrored) or the top.
    public enum Align: String, Codable, Sendable, CaseIterable { case start, center, end }

    public var axis: Axis
    /// Between children (canvas units, default 4).
    public var spacing: Double?
    /// Inside the frame on every side (default 0).
    public var padding: Double?
    /// Across the axis: horizontal position in a vertical stack or grid cell, vertical position in
    /// a horizontal one. Default: `start` for vertical stacks and grids, `center` for horizontal.
    public var alignItems: Align?
    /// Along the axis, where the children sit when they don't fill the frame (default `start`).
    /// Spacers do the same per gap.
    public var justify: Align?
    /// Grid only: items per row (1–8).
    public var columns: Int?
    /// Radial only: the circle the children's centers sit on (default: half the smaller side minus the
    /// largest child), the first child's angle in degrees clockwise from 12 o'clock (default 0), the arc
    /// they spread over (default 360) and whether each child turns with its angle.
    public var radius: Double?
    public var startAngle: Double?
    public var sweep: Double?
    public var rotateChildren: Bool?
    public var children: [Layer]

    public static let defaultSpacing = 4.0

    public init(axis: Axis, spacing: Double? = nil, padding: Double? = nil, alignItems: Align? = nil, justify: Align? = nil,
                columns: Int? = nil, children: [Layer]) {
        self.axis = axis
        self.spacing = spacing
        self.padding = padding
        self.alignItems = alignItems
        self.justify = justify
        self.columns = columns
        self.children = children
    }

    enum CodingKeys: String, CodingKey {
        case axis, spacing, padding, alignItems, justify, columns, children, radius, startAngle, sweep, rotateChildren
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(axis, forKey: .axis)
        try container.encodeIfPresent(spacing, forKey: .spacing)
        try container.encodeIfPresent(padding, forKey: .padding)
        try container.encodeIfPresent(alignItems, forKey: .alignItems)
        try container.encodeIfPresent(justify, forKey: .justify)
        try container.encodeIfPresent(columns, forKey: .columns)
        try container.encodeIfPresent(radius, forKey: .radius)
        try container.encodeIfPresent(startAngle, forKey: .startAngle)
        try container.encodeIfPresent(sweep, forKey: .sweep)
        try container.encodeIfPresent(rotateChildren, forKey: .rotateChildren)
        var list = container.nestedUnkeyedContainer(forKey: .children)
        for child in children { try list.encode(Child(layer: child)) }
    }

    /// Encodes a child without a frame.
    private struct Child: Encodable {
        let layer: Layer
        func encode(to encoder: Encoder) throws { try layer.encode(to: encoder, asChild: true) }
    }

    /// Children grouped into grid rows (`columns` per row).
    public var rows: [[Layer]] {
        let columns = max(1, min(columns ?? 2, 8))
        return stride(from: 0, to: children.count, by: columns).map { Array(children[$0..<min($0 + columns, children.count)]) }
    }
}

/// Flexible space inside a vertical or horizontal stack: pushes its neighbors apart.
public struct SpacerLayer: Codable, Sendable, Equatable {
    /// The least space it leaves (canvas units, default 0).
    public var minLength: Double?

    public init(minLength: Double? = nil) {
        self.minLength = minLength
    }
}

extension Layer {
    /// This layer and, for stacks, every layer inside it (depth first).
    public var flattened: [Layer] {
        switch content {
        case .stack(let stack): [self] + stack.children.flatMap(\.flattened)
        // Every look of a state layer: what it reads counts whichever look is showing.
        case .states(let states): [self] + states.expanded.flatMap { $0.layers.flatMap(\.flattened) }
        default: [self]
        }
    }

    /// This layer and the children of stacks: what is drawn at once, for the layer limits.
    var flattenedStacks: [Layer] {
        guard case .stack(let stack) = content else { return [self] }
        return [self] + stack.children.flatMap(\.flattenedStacks)
    }

    /// Whether the layer shows text (text, list, calendar, forecast, or a stack holding one).
    public var showsText: Bool {
        flattened.contains { layer in
            switch layer.content {
            case .text, .list, .calendarMonth, .forecastRow: true
            default: false
            }
        }
    }
}

extension WidgetSpec {
    /// Every layer, including the children of stacks.
    public var allLayers: [Layer] { layers.flatMap(\.flattened) }
}
