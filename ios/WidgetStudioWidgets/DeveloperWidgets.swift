#if WS_DEVELOPER
import AppIntents
import SwiftUI
import WidgetKit
import WidgetKitCore

// Developer mode only (ADR-014): the configurable widget from before ADR-013 (commit 997651a),
// extended to saved designs. One kind per size; Edit Widget lists "My widgets" (saved designs
// that fit, from SharedStore, which needs the App Group of a real Apple account) and every
// template that fits, grouped and searchable, with an Appearance option. Not built in store
// mode, because AppIntent widgets never render on the owner's Fast Store install (ADR-013).

struct DeveloperWidgets: WidgetBundle {
    var body: some Widget {
        SmallPickWidget()
        MediumPickWidget()
        LargePickWidget()
        #if WS_XL27
        // ADR-030: with a real Apple account, a large widget that takes WidgetKit push updates (iOS 26+).
        // Widget bundles accept "if #available" without an else, so it is a second kind next to the first.
        if #available(iOS 26.0, *) {
            LargePushPickWidget()
        }
        #endif
    }
}

#if WS_XL27
/// The large configurable widget with WidgetKit push updates (ADR-030): a server holding the push token can
/// make it reload at once, with no daily budget. Needs the push entitlement of a real Apple account
/// (docs/app-store/when-account.md); never on the Fast Store install.
@available(iOS 26.0, *)
struct LargePushPickWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WidgetStudio.pick.push", intent: LargePickIntent.self,
                               provider: PickProvider<LargePickIntent>()) { PickWidgetView(entry: $0) }
            .configurationDisplayName("widget.pick.name")
            .description("widget.pick.description")
            .supportedFamilies([.systemLarge] + WidgetFamily.extraLargePortrait)
            .contentMarginsDisabled()
            .pushHandler(WidgetPushTokens.self)
    }
}

/// Keeps the widgets' push token for the owner's server and logs it (ADR-030).
@available(iOS 26.0, *)
struct WidgetPushTokens: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        let token = pushInfo.token.map { String(format: "%02x", $0) }.joined()
        try? DataCache().write(token, "widgetPushToken")
        ReloadLog.record(kind: "push", reason: "token \(token.prefix(8))… for \(widgets.count) widgets")
    }
}
#endif

struct SmallPickWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WidgetStudio.pick.small", intent: SmallPickIntent.self,
                               provider: PickProvider<SmallPickIntent>()) { PickWidgetView(entry: $0) }
            .configurationDisplayName("widget.pick.name")
            .description("widget.pick.description")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

struct MediumPickWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WidgetStudio.pick.medium", intent: MediumPickIntent.self,
                               provider: PickProvider<MediumPickIntent>()) { PickWidgetView(entry: $0) }
            .configurationDisplayName("widget.pick.name")
            .description("widget.pick.description")
            .supportedFamilies([.systemMedium])
            .contentMarginsDisabled()
    }
}

struct LargePickWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WidgetStudio.pick.large", intent: LargePickIntent.self,
                               provider: PickProvider<LargePickIntent>()) { PickWidgetView(entry: $0) }
            .configurationDisplayName("widget.pick.name")
            .description("widget.pick.description")
            .supportedFamilies([.systemLarge])
            .contentMarginsDisabled()
    }
}

// MARK: Configuration

protocol PickConfiguration: WidgetConfigurationIntent {
    static var size: SpecFamily { get }
    /// "design:<id>" or "template:<id>"; nil = nothing chosen yet (never picked for the user).
    var itemID: String? { get }
    var appearanceChoice: PickAppearance { get }
}

struct SmallPickIntent: PickConfiguration {
    static var title: LocalizedStringResource = "widget.pick.intent.title"
    static var description = IntentDescription("widget.pick.intent.description")
    static let size = SpecFamily.small

    @Parameter(title: "widget.pick.param")
    var item: SmallItemEntity?

    @Parameter(title: "widget.pick.appearance", default: .template)
    var appearance: PickAppearance

    var itemID: String? { item?.id }
    var appearanceChoice: PickAppearance { appearance }
}

struct MediumPickIntent: PickConfiguration {
    static var title: LocalizedStringResource = "widget.pick.intent.title"
    static var description = IntentDescription("widget.pick.intent.description")
    static let size = SpecFamily.medium

    @Parameter(title: "widget.pick.param")
    var item: MediumItemEntity?

    @Parameter(title: "widget.pick.appearance", default: .template)
    var appearance: PickAppearance

    var itemID: String? { item?.id }
    var appearanceChoice: PickAppearance { appearance }
}

struct LargePickIntent: PickConfiguration {
    static var title: LocalizedStringResource = "widget.pick.intent.title"
    static var description = IntentDescription("widget.pick.intent.description")
    static let size = SpecFamily.large

    @Parameter(title: "widget.pick.param")
    var item: LargeItemEntity?

    @Parameter(title: "widget.pick.appearance", default: .template)
    var appearance: PickAppearance

    var itemID: String? { item?.id }
    var appearanceChoice: PickAppearance { appearance }
}

enum PickAppearance: String, AppEnum {
    case template, system, light, dark

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "widget.pick.appearance"
    static var caseDisplayRepresentations: [PickAppearance: DisplayRepresentation] = [
        .template: "widget.pick.appearance.template",
        .system: "widget.pick.appearance.system",
        .light: "widget.pick.appearance.light",
        .dark: "widget.pick.appearance.dark",
    ]
}

// MARK: Entities (one per size: the query must know what fits)

struct SmallItemEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "widget.pick.entity"
    static var defaultQuery = SmallItemQuery()
    let id: String
    let name: String
    let detail: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(detail)") }
}

struct MediumItemEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "widget.pick.entity"
    static var defaultQuery = MediumItemQuery()
    let id: String
    let name: String
    let detail: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(detail)") }
}

struct LargeItemEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "widget.pick.entity"
    static var defaultQuery = LargeItemQuery()
    let id: String
    let name: String
    let detail: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(detail)") }
}

struct SmallItemQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SmallItemEntity] {
        PickCatalog.entities(for: identifiers, size: .small, make: SmallItemEntity.init)
    }

    func suggestedEntities() async throws -> IntentItemCollection<SmallItemEntity> {
        PickCatalog.sections(size: .small, make: SmallItemEntity.init)
    }

    func entities(matching string: String) async throws -> IntentItemCollection<SmallItemEntity> {
        PickCatalog.search(string, size: .small, make: SmallItemEntity.init)
    }
}

struct MediumItemQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [MediumItemEntity] {
        PickCatalog.entities(for: identifiers, size: .medium, make: MediumItemEntity.init)
    }

    func suggestedEntities() async throws -> IntentItemCollection<MediumItemEntity> {
        PickCatalog.sections(size: .medium, make: MediumItemEntity.init)
    }

    func entities(matching string: String) async throws -> IntentItemCollection<MediumItemEntity> {
        PickCatalog.search(string, size: .medium, make: MediumItemEntity.init)
    }
}

struct LargeItemQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [LargeItemEntity] {
        PickCatalog.entities(for: identifiers, size: .large, make: LargeItemEntity.init)
    }

    func suggestedEntities() async throws -> IntentItemCollection<LargeItemEntity> {
        PickCatalog.sections(size: .large, make: LargeItemEntity.init)
    }

    func entities(matching string: String) async throws -> IntentItemCollection<LargeItemEntity> {
        PickCatalog.search(string, size: .large, make: LargeItemEntity.init)
    }
}

/// Saved designs and templates as pickable items.
enum PickCatalog {
    typealias Make<Entity> = (_ id: String, _ name: String, _ detail: String) -> Entity

    typealias Item = WidgetPicker.Item

    /// Saved designs (incl. AI-made ones) from SharedStore, then templates (`WidgetPicker`, tested in the package).
    static func items(size: SpecFamily) -> [Item] {
        WidgetPicker.items(size: size)
    }

    static func entities<Entity>(for identifiers: [String], size: SpecFamily, make: Make<Entity>) -> [Entity] {
        let all = items(size: size)
        return identifiers.compactMap { id in all.first { $0.id == id }.map { entity($0, make: make) } }
    }

    static func sections<Entity: AppEntity>(size: SpecFamily, make: Make<Entity>) -> IntentItemCollection<Entity> {
        let language = RenderContext.preferredLanguage
        let all = items(size: size)
        var sections: [IntentItemSection<Entity>] = []
        let designs = all.filter(\.isDesign).map { IntentItem(entity($0, make: make)) }
        if !designs.isEmpty {
            sections.append(IntentItemSection(LocalizedStringResource(stringLiteral: language == "ar" ? "ودجاتي" : "My widgets"),
                                              items: designs))
        }
        for category in SpecCategory.allCases {
            let items = all.filter { !$0.isDesign && $0.category == category }.map { IntentItem(entity($0, make: make)) }
            if !items.isEmpty {
                sections.append(IntentItemSection(LocalizedStringResource(stringLiteral: category.title.resolved(language: language)),
                                                  items: items))
            }
        }
        return IntentItemCollection(sections: sections)
    }

    static func search<Entity: AppEntity>(_ string: String, size: SpecFamily, make: Make<Entity>) -> IntentItemCollection<Entity> {
        IntentItemCollection(items: WidgetPicker.search(string, in: items(size: size)).map { entity($0, make: make) })
    }

    static func entity<Entity>(_ item: Item, make: Make<Entity>) -> Entity {
        let language = RenderContext.preferredLanguage
        let kind = item.isDesign ? (language == "ar" ? "تصميمي" : "My design") : item.category?.title.resolved(language: language)
        return make(item.id, item.name.resolved(language: language), [kind].compactMap { $0 }.joined())
    }
}

// MARK: Timeline

struct PickEntry: TimelineEntry {
    let date: Date
    let spec: WidgetSpec?
    let design: SavedDesign?
    let image: CGImage?
    let problem: String?
    let appearance: PickAppearance
    /// Placed but not configured: "Long-press → Edit Widget to choose".
    var needsChoice = false
    /// Real data (ADR-016).
    var inputs = LiveInputs()
    var gap: DataGap?
}

struct PickProvider<Configuration: PickConfiguration>: AppIntentTimelineProvider {
    typealias Entry = PickEntry
    typealias Intent = Configuration

    /// The gallery shows a template preview; a placed widget without a choice asks for one.
    func placeholder(in context: Context) -> PickEntry {
        Self.entry(itemID: "template:" + TemplateLibrary.defaultID(for: Configuration.size), appearance: .template, date: .now)
    }

    func snapshot(for configuration: Configuration, in context: Context) async -> PickEntry {
        let itemID = configuration.itemID ?? (context.isPreview ? "template:" + TemplateLibrary.defaultID(for: Configuration.size) : nil)
        return Self.entry(itemID: itemID, appearance: configuration.appearanceChoice, date: .now)
    }

    func timeline(for configuration: Configuration, in context: Context) async -> Timeline<PickEntry> {
        let now = Date.now
        let first = Self.entry(itemID: configuration.itemID, appearance: configuration.appearanceChoice, date: now)
        guard let spec = first.spec else { return Timeline(entries: [first], policy: .never) }
        let inputs = await WidgetData.inputs(for: DataRequirements.groups(for: spec), tickers: MarketData.tickers(in: spec), now: now)
        let gap = LiveData.gap(for: spec, inputs)
        let (dates, reload) = LiveSchedule.make(for: spec, inputs: inputs, now: now)
        ReloadLog.record(kind: "pick", reason: "timeline", entries: dates.count, next: reload, now: now)
        let entries = dates.map {
            PickEntry(date: $0, spec: first.spec, design: first.design, image: first.image, problem: first.problem,
                      appearance: first.appearance, inputs: inputs, gap: gap)
        }
        WidgetLog.add("pick \(Configuration.size.rawValue) \(configuration.itemID ?? "default") \(gap?.rawValue ?? "ok")")
        return Timeline(entries: entries, policy: .after(reload))
    }

    static func entry(itemID: String?, appearance: PickAppearance, date: Date) -> PickEntry {
        let store = SharedStore()
        switch WidgetPicker.resolve(itemID: itemID, store: store) {
        case .none:
            return PickEntry(date: date, spec: nil, design: nil, image: nil, problem: nil, appearance: appearance, needsChoice: true)
        case .design(let design):
            return PickEntry(date: date, spec: design.spec, design: design, image: design.imageFile.flatMap(store.image(named:)),
                             problem: nil, appearance: appearance)
        case .template(let spec):
            return PickEntry(date: date, spec: spec, design: nil, image: nil, problem: nil, appearance: appearance)
        case .missingDesign:
            return PickEntry(date: date, spec: nil, design: nil, image: nil,
                             problem: String(localized: "widget.pick.deleted"), appearance: appearance)
        case .invalidTemplate(let description):
            return PickEntry(date: date, spec: nil, design: nil, image: nil, problem: description, appearance: appearance)
        }
    }
}

struct PickWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: PickEntry

    var body: some View {
        if entry.needsChoice {
            PickPromptView()
        } else if let problem = entry.problem {
            WidgetProblemView(title: "Widget Studio", message: problem)
        } else if let gap = entry.gap {
            DataGapView(gap: gap, title: entry.design?.name ?? entry.spec?.name.resolved(language: RenderContext.preferredLanguage) ?? "")
        } else {
            SpecWidgetContent(spec: entry.spec, context: context)
                .environment(\.specActionButton, WidgetActionButtons.make)
        }
    }

    private var context: RenderContext {
        let language = RenderContext.preferredLanguage
        let data = LiveData.snapshot(entry.inputs, now: entry.date)
        var context = entry.design?.renderContext(date: entry.date, language: language, data: data, image: entry.image,
                                                 defaultClock: entry.inputs.settings.clockFormat)
            ?? RenderContext(date: entry.date, language: language, data: data)
        if entry.design == nil { context.uses24Hour = entry.inputs.settings.clockFormat.uses24Hour() }
        context.mediaArtwork = entry.inputs.device.artwork
        switch entry.appearance {
        case .template: break
        case .system: context.theme = colorScheme == .dark ? .dark : .light
        case .light: context.theme = .light
        case .dark: context.theme = .dark
        }
        return context
    }
}

/// A placed "My widget" with no choice yet; it is never filled in automatically (M6).
struct PickPromptView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.title2)
                .accessibilityHidden(true)
            Text("widget.pick.choose.title")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("widget.pick.choose.body")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
}
#endif
