import ImageIO
import SwiftUI
import WidgetKit
import WidgetKitCore

// Personal build (docs/personal.md): the "Widget Studio" widget in small, medium and large.
// StaticConfiguration (the path that renders on Fast Store installs, ADR-013). ◀ ▶ cycle through
// the pairing card (until paired), designs sent from the app through the relay, and every
// template that fits the size; 🔒 hides the arrows. All state is in the extension's own container.

struct SmallSwitcherWidget: Widget {
    var body: some WidgetConfiguration { SwitcherConfiguration.make(size: .small) }
}

struct MediumSwitcherWidget: Widget {
    var body: some WidgetConfiguration { SwitcherConfiguration.make(size: .medium) }
}

struct LargeSwitcherWidget: Widget {
    var body: some WidgetConfiguration { SwitcherConfiguration.make(size: .large) }
}

enum SwitcherConfiguration {
    static func make(size: SpecFamily) -> some WidgetConfiguration {
        StaticConfiguration(kind: SwitcherCatalog.widgetKind(size), provider: SwitcherProvider(size: size)) {
            SwitcherWidgetView(entry: $0)
        }
        .configurationDisplayName(Text(verbatim: "Widget Studio"))
        .description(Text(personal: "widget.switcher.description"))
        .supportedFamilies([WidgetFamily(size)])
        .contentMarginsDisabled()
    }
}

struct SwitcherEntry: TimelineEntry {
    enum Content {
        case pairing(code: String, error: String?)
        case template(WidgetSpec)
        case design(SavedDesign, CGImage?)
        case problem(title: String, message: String)
    }

    let date: Date
    let size: SpecFamily
    let content: Content
    var locked = false
    var inputs = LiveInputs()
    var gap: DataGap?
    /// Widget gallery previews draw the sample data.
    var sample = false

    var spec: WidgetSpec? {
        switch content {
        case .template(let spec): spec
        case .design(let design, _): design.spec
        case .pairing, .problem: nil
        }
    }

    func at(_ date: Date) -> SwitcherEntry {
        var entry = SwitcherEntry(date: date, size: size, content: content, locked: locked)
        entry.inputs = inputs
        entry.gap = gap
        entry.sample = sample
        return entry
    }
}

struct SwitcherProvider: TimelineProvider {
    let size: SpecFamily

    func placeholder(in context: Context) -> SwitcherEntry {
        Self.preview(size: size)
    }

    func getSnapshot(in context: Context, completion: @escaping (SwitcherEntry) -> Void) {
        if context.isPreview {
            completion(Self.preview(size: size))
            return
        }
        var entry = Self.entry(size: size, cache: DataCache(), now: .now)
        if let spec = entry.spec {
            entry.inputs = WidgetData.cachedInputs()
            entry.gap = LiveData.gap(for: spec, entry.inputs)
        }
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SwitcherEntry>) -> Void) {
        Task {
            let now = Date.now
            let cache = DataCache()
            // After a button tap, redraw at once; otherwise ask the relay for a new design first.
            if let client = RelayClient(timeout: 8), (SwitcherState.load(size, cache).quietUntil ?? .distantPast) <= now {
                let outcome = await RelaySync.refresh(size: size, client: client, cache: cache, now: now)
                WidgetLog.add("switcher \(size.rawValue) relay \(outcome.newDesign ? "new design" : "no change")"
                    + (outcome.error.map { " error \($0)" } ?? ""))
            }
            let first = Self.entry(size: size, cache: cache, now: now)
            guard let spec = first.spec else {
                // The pairing card checks again every 15 minutes (the app also reloads it).
                completion(Timeline(entries: [first], policy: .after(now.addingTimeInterval(15 * 60))))
                return
            }
            var live = first
            live.inputs = await WidgetData.inputs(for: DataRequirements.groups(for: spec), now: now)
            live.gap = LiveData.gap(for: spec, live.inputs)
            let (dates, reload) = LiveSchedule.make(for: spec, inputs: live.inputs, now: now)
            WidgetLog.add("switcher \(size.rawValue): \(spec.id), \(dates.count) entries")
            completion(Timeline(entries: dates.map(live.at), policy: .after(min(reload, now.addingTimeInterval(3600)))))
        }
    }

    /// Every key the arrows cycle through for `size`.
    static func keys(size: SpecFamily, cache: DataCache) -> [String] {
        let pairing = WidgetPairing.loadOrCreate(cache)
        return SwitcherCatalog.keys(showsPairing: !pairing.isPaired && RelayClient() != nil,
                                    relayed: RelayedStore(size: size, cache: cache).items,
                                    templateIDs: SwitcherCatalog.templateIDs(fitting: size))
    }

    /// The entry for the current key (without live data).
    static func entry(size: SpecFamily, cache: DataCache, now: Date) -> SwitcherEntry {
        let state = SwitcherState.load(size, cache)
        let key = SwitcherCatalog.resolve(state.current, keys: keys(size: size, cache: cache), size: size)
        return SwitcherEntry(date: now, size: size, content: content(key: key, size: size, cache: cache), locked: state.locked)
    }

    static func content(key: String?, size: SpecFamily, cache: DataCache) -> SwitcherEntry.Content {
        guard let key else { return .problem(title: "Widget Studio", message: "no templates") }
        if key == SwitcherCatalog.pairingKey {
            let pairing = WidgetPairing.loadOrCreate(cache)
            return .pairing(code: pairing.code, error: pairing.lastError)
        }
        if let id = SwitcherCatalog.templateID(key) {
            switch TemplateLibrary.load(id: id) {
            case .success(let spec): return .template(spec)
            case .failure(let issues): return .problem(title: id, message: issues.description)
            }
        }
        let store = RelayedStore(size: size, cache: cache)
        guard let item = store.item(key: key) else { return .problem(title: "Widget Studio", message: "design \(key) is gone") }
        let image = store.image(for: item).flatMap { data -> CGImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return .design(item.design, image)
    }

    /// The gallery shows the size's default template with sample data.
    static func preview(size: SpecFamily) -> SwitcherEntry {
        let id = TemplateLibrary.defaultID(for: size)
        var entry = SwitcherEntry(date: .now, size: size, content: content(key: SwitcherCatalog.templateKey(id), size: size,
                                                                          cache: DataCache()))
        entry.sample = true
        return entry
    }
}

// MARK: View

struct SwitcherWidgetView: View {
    let entry: SwitcherEntry

    var body: some View {
        content
            .overlay(alignment: .bottomTrailing) {
                SwitcherControls(size: entry.size, locked: entry.locked)
            }
    }

    @ViewBuilder private var content: some View {
        switch entry.content {
        case .pairing(let code, let error):
            SwitcherPairingCard(code: code, error: error, size: entry.size)
        case .problem(let title, let message):
            WidgetProblemView(title: title, message: message)
        case .template(let spec):
            if let gap = entry.gap, !entry.sample {
                DataGapView(gap: gap, title: spec.name.resolved(language: RenderContext.preferredLanguage))
            } else {
                SpecWidgetContent(spec: spec, context: templateContext)
                    .environment(\.specActionButton, WidgetActionButtons.make)
                    .widgetURL(DataRequirements.showsQibla(spec) ? URL(string: "widgetstudio://qibla") : nil)
            }
        case .design(let design, let image):
            if let gap = entry.gap {
                DataGapView(gap: gap, title: design.name)
            } else {
                SpecWidgetContent(spec: design.spec, context: design.renderContext(
                    date: entry.date, language: RenderContext.preferredLanguage,
                    data: LiveData.snapshot(entry.inputs, now: entry.date), image: image,
                    defaultClock: entry.inputs.settings.clockFormat
                ))
                .environment(\.specActionButton, WidgetActionButtons.make)
            }
        }
    }

    private var templateContext: RenderContext {
        var context = RenderContext(
            date: entry.date, language: RenderContext.preferredLanguage,
            data: entry.sample ? .sample(now: entry.date) : LiveData.snapshot(entry.inputs, now: entry.date)
        )
        context.uses24Hour = entry.inputs.settings.clockFormat.uses24Hour()
        return context
    }
}

/// An unpaired widget: its code, to type once in the app (Settings → Pair widget).
struct SwitcherPairingCard: View {
    let code: String
    let error: String?
    let size: SpecFamily

    var body: some View {
        VStack(alignment: .leading, spacing: size == .small ? 4 : 6) {
            Label {
                Text(personal: "widget.switcher.pair.title")
            } icon: {
                Image(systemName: "link")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(hex: "#E2231A"))
            Text(verbatim: RelayCode.formatted(code))
                .font(.system(size: size == .small ? 24 : 30, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .environment(\.layoutDirection, .leftToRight)
            Text(personal: "widget.switcher.pair.hint")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)
            if let error, size != .small {
                Text(verbatim: error)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .containerBackground(Color(white: 0.055), for: .widget)
        .widgetURL(URL(string: "widgetstudio://settings"))
    }
}
