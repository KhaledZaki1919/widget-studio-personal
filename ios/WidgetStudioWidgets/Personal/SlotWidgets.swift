import AppIntents
import ImageIO
import SwiftUI
import WidgetKit
import WidgetKitCore

// Personal build (docs/personal.md): one code per placed widget.
//
// Identity. WidgetKit gives a placed widget no instance ID, so identity = widget kind + size:
// - "Slot 1"…"Slot 5": StaticConfiguration (the path that renders on the owner's Fast Store
//   install, ADR-013), each in every size. Slot 2 small and Slot 2 large are different widgets
//   with different codes. Two copies of the same slot in the same size would share one code.
// - "Slot (choose)": AppIntentConfiguration; Edit Widget picks slot A…E. It is the experiment:
//   ADR-013 saw every AppIntent-configured widget stay gray on this install, but another app's
//   Edit Widget works there, so this build tries again. If it renders, it adds 5 more slots
//   per size; if it stays gray, the fixed slots are the path.
//
// Every slot shows its own code until a design is assigned. The timeline asks the relay for
// the design (ETag: 304 when unchanged), caches it in the extension's container for offline
// use, and draws it with the official My widget view: same renderer, live data, states, artwork
// and tap actions (counters, timers, tasks, media) computed in the widget.

struct Slot1Widget: Widget {
    var body: some WidgetConfiguration { SlotConfiguration.make(slot: "1") }
}

struct Slot2Widget: Widget {
    var body: some WidgetConfiguration { SlotConfiguration.make(slot: "2") }
}

struct Slot3Widget: Widget {
    var body: some WidgetConfiguration { SlotConfiguration.make(slot: "3") }
}

struct Slot4Widget: Widget {
    var body: some WidgetConfiguration { SlotConfiguration.make(slot: "4") }
}

struct Slot5Widget: Widget {
    var body: some WidgetConfiguration { SlotConfiguration.make(slot: "5") }
}

/// The configurable experiment: Edit Widget picks slot A…E.
struct SlotPickWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SlotCatalog.pickableKind, intent: SlotPickIntent.self,
                               provider: SlotPickProvider()) { SlotWidgetView(entry: $0) }
            .configurationDisplayName(Text(personal: "widget.slot.pick.name"))
            .description(Text(personal: "widget.slot.pick.description"))
            .supportedFamilies(SlotConfiguration.families)
            .contentMarginsDisabled()
    }
}

enum SlotConfiguration {
    static func make(slot: String) -> some WidgetConfiguration {
        StaticConfiguration(kind: SlotCatalog.kind(slot: slot), provider: SlotProvider(slot: slot)) { SlotWidgetView(entry: $0) }
            .configurationDisplayName(Text(personal: "widget.slot.name \(slot)"))
            .description(Text(personal: "widget.slot.description"))
            .supportedFamilies(families)
            .contentMarginsDisabled()
    }

    static var families: [WidgetFamily] {
        [.systemSmall, .systemMedium, .systemLarge] + WidgetFamily.extraLargePortrait
    }
}

extension SpecFamily {
    /// The spec size a placed widget family draws (accessory families never reach these widgets).
    init(widgetFamily: WidgetFamily) {
        switch widgetFamily {
        case .systemMedium: self = .medium
        case .systemLarge: self = .large
        case .systemSmall: self = .small
        default: self = WidgetFamily.extraLargePortrait.contains(widgetFamily) ? .xlarge : .large
        }
    }
}

// MARK: Configuration intent (the experiment)

struct SlotPickIntent: WidgetConfigurationIntent {
    static var title = LocalizedStringResource("widget.slot.pick.intent", table: "Personal")
    static var description = IntentDescription(LocalizedStringResource("widget.slot.pick.description", table: "Personal"))

    @Parameter(title: LocalizedStringResource("widget.slot.pick.param", table: "Personal"), default: .slotA)
    var slot: SlotLetter
}

enum SlotLetter: String, AppEnum {
    case slotA = "A", slotB = "B", slotC = "C", slotD = "D", slotE = "E"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget.slot.pick.param", table: "Personal"))
    static var caseDisplayRepresentations: [SlotLetter: DisplayRepresentation] = [
        .slotA: DisplayRepresentation(title: LocalizedStringResource("widget.slot.pick.a", table: "Personal")),
        .slotB: DisplayRepresentation(title: LocalizedStringResource("widget.slot.pick.b", table: "Personal")),
        .slotC: DisplayRepresentation(title: LocalizedStringResource("widget.slot.pick.c", table: "Personal")),
        .slotD: DisplayRepresentation(title: LocalizedStringResource("widget.slot.pick.d", table: "Personal")),
        .slotE: DisplayRepresentation(title: LocalizedStringResource("widget.slot.pick.e", table: "Personal")),
    ]
}

// MARK: Timeline

struct SlotEntry: TimelineEntry {
    enum Content {
        case code(String, error: String?)
        case design(SavedDesign, CGImage?)
        /// Widget gallery: the size's default template with sample data.
        case preview(WidgetSpec)
        case notConfigured
    }

    let date: Date
    let id: SlotID
    let content: Content
    var inputs = LiveInputs()
    var gap: DataGap?

    func at(_ date: Date) -> SlotEntry {
        SlotEntry(date: date, id: id, content: content, inputs: inputs, gap: gap)
    }
}

/// The shared timeline work of both providers.
enum SlotTimeline {
    static func placeholder(_ id: SlotID) -> SlotEntry {
        SlotEntry(date: .now, id: id, content: .code("ABCDEF", error: nil))
    }

    static func preview(_ id: SlotID) -> SlotEntry {
        switch TemplateLibrary.load(id: TemplateLibrary.defaultID(for: id.size == .xlarge ? .large : id.size)) {
        case .success(let spec): SlotEntry(date: .now, id: id, content: .preview(spec))
        case .failure: placeholder(id)
        }
    }

    /// What the slot shows from its cache (no network).
    static func current(_ id: SlotID, cache: DataCache = DataCache(), now: Date = .now) -> SlotEntry {
        guard RelayClient() != nil else { return SlotEntry(date: now, id: id, content: .notConfigured) }
        let state = SlotState.load(id, cache, now: now)
        guard let design = state.design else {
            return SlotEntry(date: now, id: id, content: .code(state.code, error: state.lastError))
        }
        let image = state.imageData(cache).flatMap { data -> CGImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return SlotEntry(date: now, id: id, content: .design(design, image))
    }

    static func timeline(_ id: SlotID) async -> Timeline<SlotEntry> {
        let now = Date.now
        let cache = DataCache()
        if let client = RelayClient(timeout: 8) {
            let outcome = await SlotSync.refresh(id, client: client, cache: cache, now: now)
            let what = outcome.newDesign ? "new design" : outcome.removed ? "removed" : "no change"
            WidgetLog.add("slot \(id.key) \(what)" + (outcome.error.map { " error \($0)" } ?? ""))
        }
        var first = current(id, cache: cache, now: now)
        guard case .design(let design, _) = first.content else {
            // Unassigned: check again in 15 minutes (the app also reloads this widget after a send).
            ReloadLog.record(kind: "slot.\(id.key)", reason: "timeline (code)", entries: 1, next: now.addingTimeInterval(900), now: now)
            return Timeline(entries: [first], policy: .after(now.addingTimeInterval(15 * 60)))
        }
        first.inputs = await WidgetData.inputs(for: DataRequirements.groups(for: design.spec),
                                               tickers: MarketData.tickers(in: design.spec, fieldValues: design.fieldValues), now: now)
        first.gap = LiveData.gap(for: design.spec, first.inputs)
        let (dates, reload) = LiveSchedule.make(for: design.spec, inputs: first.inputs, now: now)
        // At most an hour, so a reassigned code shows up even without the app's reload.
        let next = min(reload, now.addingTimeInterval(3600))
        ReloadLog.record(kind: "slot.\(id.key)", reason: "timeline", entries: dates.count, next: next, now: now)
        return Timeline(entries: dates.map(first.at), policy: .after(next))
    }
}

struct SlotProvider: TimelineProvider {
    let slot: String

    func placeholder(in context: Context) -> SlotEntry {
        SlotTimeline.placeholder(SlotID(slot: slot, size: SpecFamily(widgetFamily: context.family)))
    }

    func getSnapshot(in context: Context, completion: @escaping (SlotEntry) -> Void) {
        let id = SlotID(slot: slot, size: SpecFamily(widgetFamily: context.family))
        completion(context.isPreview ? SlotTimeline.preview(id) : SlotTimeline.current(id))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SlotEntry>) -> Void) {
        let id = SlotID(slot: slot, size: SpecFamily(widgetFamily: context.family))
        Task { completion(await SlotTimeline.timeline(id)) }
    }
}

struct SlotPickProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SlotEntry {
        SlotTimeline.placeholder(SlotID(slot: "A", size: SpecFamily(widgetFamily: context.family)))
    }

    func snapshot(for configuration: SlotPickIntent, in context: Context) async -> SlotEntry {
        let id = SlotID(slot: configuration.slot.rawValue, size: SpecFamily(widgetFamily: context.family))
        return context.isPreview ? SlotTimeline.preview(id) : SlotTimeline.current(id)
    }

    func timeline(for configuration: SlotPickIntent, in context: Context) async -> Timeline<SlotEntry> {
        await SlotTimeline.timeline(SlotID(slot: configuration.slot.rawValue, size: SpecFamily(widgetFamily: context.family)))
    }
}

// MARK: Views

struct SlotWidgetView: View {
    let entry: SlotEntry

    var body: some View {
        switch entry.content {
        case .design(let design, let image):
            // The official My widget view: identical rendering and taps.
            MyWidgetView(entry: MyWidgetEntry(date: entry.date, content: .design(design, image), inputs: entry.inputs, gap: entry.gap))
        case .preview(let spec):
            SpecWidgetContent(spec: spec, context: RenderContext(date: entry.date, language: RenderContext.preferredLanguage,
                                                                  data: .sample(now: entry.date)))
        case .code(let code, let error):
            SlotCodeCard(code: code, error: error, id: entry.id)
        case .notConfigured:
            WidgetProblemView(title: "Widget Studio P", message: "relay URL not set")
        }
    }
}

/// An unassigned slot: its code, big, in dot numerals. Opens the app's My home screen list.
struct SlotCodeCard: View {
    let code: String
    let error: String?
    let id: SlotID

    private var compact: Bool { id.size == .small }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: 6) {
                Circle().fill(Self.red).frame(width: 8, height: 8)
                Text(personal: "widget.slot.name \(id.slot)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            Text(verbatim: RelayCode.formatted(code))
                .font(.custom("Doto-Black", size: compact ? 30 : 44))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(Text(verbatim: code.map(String.init).joined(separator: " ")))
            Text(personal: "widget.slot.code.hint")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(compact ? 3 : 2)
                .minimumScaleFactor(0.7)
            if let error, !compact {
                Text(verbatim: error)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(compact ? 14 : 18)
        .containerBackground(Color(white: 0.055), for: .widget)
        .widgetURL(URL(string: "widgetstudio://homescreen?code=\(code)"))
    }

    static let red = Color(red: 0.886, green: 0.137, blue: 0.102)
}

extension Text {
    /// A string from the personal build's own table (`Personal.xcstrings`).
    init(personal key: LocalizedStringKey) {
        self.init(key, tableName: "Personal")
    }
}
