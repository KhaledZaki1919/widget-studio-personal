import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Tinted and Clear home screens (iOS 18 accented rendering mode, ADR-023). iOS draws every
/// widget pixel in one tint and keeps only its opacity, so a solid fill becomes a solid white
/// block. In this mode the layer views draw an accented variant:
/// - large fills (shapes, today's box, the clock face, tracks) drop to `surfaceOpacity`, with a
///   thin outline where the shape needs one;
/// - chromatic colors (an accent red, a highlight) are marked `widgetAccentable()`, so iOS paints
///   them in the accent tint instead of the primary one;
/// - photos use `widgetAccentedRenderingMode(.accentedDesaturated)`;
/// - text, ticks and hands stay fully opaque, so they stay readable.
///
/// `SpecView` reads `widgetRenderingMode` and passes the result down as `specAccented`; tests
/// and previews set `specAccented` directly.
public extension EnvironmentValues {
    var specAccented: Bool {
        get { self[SpecAccentedKey.self] }
        set { self[SpecAccentedKey.self] = newValue }
    }
}

private struct SpecAccentedKey: EnvironmentKey {
    static let defaultValue = false
}

enum Accented {
    /// Opacity of large fills in accented mode: visible as a soft panel, never a solid block.
    static let surfaceOpacity = 0.2
    /// Opacity of outlines added to shapes that lost their fill.
    static let outlineOpacity = 0.6

    /// Saturated colors (not grays, black or white) join the accent group.
    static func isChromatic(_ hex: String?) -> Bool {
        guard let hex, let color = HexColor.parse(hex) else { return false }
        let high = max(color.red, color.green, color.blue)
        let low = min(color.red, color.green, color.blue)
        guard high > 0.15 else { return false }
        return (high - low) / high > 0.3
    }

    /// A fill color as drawn: unchanged normally, faint in accented mode.
    static func fill(_ hex: String, accented: Bool) -> Color {
        accented ? Color(hex: hex).opacity(surfaceOpacity) : Color(hex: hex)
    }
}

extension View {
    /// In accented mode, puts the view in the accent group when its color is chromatic.
    @ViewBuilder func accentable(_ hex: String?, accented: Bool) -> some View {
        #if canImport(WidgetKit)
        if accented {
            widgetAccentable(Accented.isChromatic(hex))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension View {
    /// In accented mode, puts the view in the accent group (progress, today's ring).
    @ViewBuilder func widgetAccentableIf(_ accented: Bool) -> some View {
        #if canImport(WidgetKit)
        if accented { widgetAccentable() } else { self }
        #else
        self
        #endif
    }
}

/// Reads the widget's rendering mode (where WidgetKit exists) and sets `specAccented` for the
/// layer views; an explicit `specAccented` from the host (tests, previews) wins.
struct AccentedModeReader: ViewModifier {
    @Environment(\.specAccented) private var forced
    #if canImport(WidgetKit)
    @Environment(\.widgetRenderingMode) private var mode
    #endif

    func body(content: Content) -> some View {
        #if canImport(WidgetKit)
        content.environment(\.specAccented, forced || mode == .accented)
        #else
        content.environment(\.specAccented, forced)
        #endif
    }
}

extension Image {
    /// Photos in accented mode: desaturated and tinted by iOS instead of a white block (iOS 18).
    @ViewBuilder func accentedPhoto(_ accented: Bool) -> some View {
        #if canImport(WidgetKit)
        if #available(iOS 18.0, macOS 15.0, *) {
            widgetAccentedRenderingMode(accented ? .accentedDesaturated : nil)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
