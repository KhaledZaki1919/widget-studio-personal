import SwiftUI
import WidgetKitCore

/// A saved (or edited) design rendered like its widget: the design's field values, theme,
/// colors and photo, at widget proportions, ticking every minute. Taps pass through.
struct DesignPreview: View {
    @Environment(LiveDataModel.self) private var live
    let design: SavedDesign
    let image: CGImage?
    let language: String
    /// The States panel's preview (ADR-028).
    var forced: [String: String] = [:]
    var overrides: [String: String] = [:]

    private func context(at date: Date) -> RenderContext {
        var context = design.renderContext(date: date, language: language, data: live.snapshot(now: date), image: image,
                                           defaultClock: live.settings.clockFormat)
        context.forcedStates = forced
        context.overrides = overrides
        return context
    }

    var body: some View {
        let canvas = design.spec.family.canvas
        TimelineView(.everyMinute) { timeline in
            SpecView(spec: design.spec, context: context(at: timeline.date))
        }
        .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: design.name))
        .accessibilityAddTraits(.isImage)
    }
}
