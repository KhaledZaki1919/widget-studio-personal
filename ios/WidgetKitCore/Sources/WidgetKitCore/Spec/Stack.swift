import Foundation

/// A container laid out natively (M6.1, ADR-022): children are placed by SwiftUI stacks or a
/// grid instead of absolute frames, so texts can't run into each other. The stack itself has a
/// frame like any layer; its children give only an optional `width`/`height` (canvas units,
/// 0 or absent = natural size along that axis).
///
/// RTL (ADR-010): with `mirror: true` in Arabic, a horizontal stack or grid reverses its items
/// and `start`/`end` swap sides; glyphs never flip.
public struct StackLayer: Codable, Sendable, Equatable {
    public enum Axis: String, Codable, Sendable, CaseIterable { case vertical, horizontal, grid }
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
        case axis, spacing, padding, alignItems, justify, columns, children
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(axis, forKey: .axis)
        try container.encodeIfPresent(spacing, forKey: .spacing)
        try container.encodeIfPresent(padding, forKey: .padding)
        try container.encodeIfPresent(alignItems, forKey: .alignItems)
        try container.encodeIfPresent(justify, forKey: .justify)
        try container.encodeIfPresent(columns, forKey: .columns)
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
        guard case .stack(let stack) = content else { return [self] }
        return [self] + stack.children.flatMap(\.flattened)
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
