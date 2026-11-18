import os
import SwiftUI
import WidgetKit
import WidgetKitCore

// Template widgets (ADR-013): one StaticConfiguration widget per template, in the template's
// own size. The owner's M2 device test showed StaticConfiguration rendering a template on the
// Fast Store install while every AppIntentConfiguration widget stayed gray, even in the gallery.
// The user picks a template by swiping the widget gallery, which previews each real design.
// Each step is written to `WidgetLog` (shown by the large check widget), and anything that goes
// wrong shows a plain error text.

struct TemplateWidget<ID: TemplateIdentity>: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WidgetStudio.\(ID.id)", provider: TemplateProvider(templateID: ID.id)) {
            TemplateWidgetView(entry: $0)
        }
        .configurationDisplayName(Self.name)
        .description(Self.summary)
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }

    private static var spec: WidgetSpec? { TemplateLibrary.template(id: ID.id) }

    static var name: String {
        spec?.name.resolved(language: RenderContext.preferredLanguage) ?? ID.id
    }

    /// "Weather · Widget Studio".
    static var summary: String {
        [spec?.category?.title.resolved(language: RenderContext.preferredLanguage), "Widget Studio"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The template's own size only: nothing is shrunk or stretched.
    static var families: [WidgetFamily] {
        // ADR-030: tall templates also fill iOS 27's 4 × 6 widget, scaled and centered.
        switch spec?.family {
        case .medium?: [.systemMedium]
        case .large?: [.systemLarge] + WidgetFamily.extraLargePortrait
        case .xlarge?: WidgetFamily.extraLargePortrait.isEmpty ? [.systemLarge] : WidgetFamily.extraLargePortrait
        default: [.systemSmall]
        }
    }
}

// MARK: Bundles per category (a widget bundle block takes at most 10 widgets)

struct TimeTemplateWidgets: WidgetBundle {
    var body: some Widget {
        TemplateWidget<TemplateIDs.ClockAnalog>()
        TemplateWidget<TemplateIDs.ClockDotAnalog>()
        TemplateWidget<TemplateIDs.ClockDigital>()
        TemplateWidget<TemplateIDs.DateBig>()
        TemplateWidget<TemplateIDs.DateDayZone>()
        TemplateWidget<TemplateIDs.YearDots>()
    }
}

struct WeatherTemplateWidgets: WidgetBundle {
    var body: some Widget {
        TemplateWidget<TemplateIDs.WeatherHiLo>()
        TemplateWidget<TemplateIDs.WeatherTemp>()
        TemplateWidget<TemplateIDs.WeatherForecast>()
        TemplateWidget<TemplateIDs.WeatherArt>()
        TemplateWidget<TemplateIDs.LocationCoords>()
    }
}

struct HealthTemplateWidgets: WidgetBundle {
    var body: some Widget {
        TemplateWidget<TemplateIDs.StepsStreak>()
        TemplateWidget<TemplateIDs.StepsMonth>()
        TemplateWidget<TemplateIDs.SleepWeek>()
    }
}

struct PrayerTemplateWidgets: WidgetBundle {
    var body: some Widget {
        TemplateWidget<TemplateIDs.PrayerNext>()
        TemplateWidget<TemplateIDs.PrayerDay>()
        TemplateWidget<TemplateIDs.Qibla>()
    }
}

struct CountdownTemplateWidgets: WidgetBundle {
    var body: some Widget {
        TemplateWidget<TemplateIDs.FocusToday>()
        TemplateWidget<TemplateIDs.CountdownRed>()
        TemplateWidget<TemplateIDs.CountdownTrip>()
        TemplateWidget<TemplateIDs.Stopwatch>()
    }
}

struct PhotoTemplateWidgets: WidgetBundle {
    var body: some Widget {
        TemplateWidget<TemplateIDs.PhotoSquare>()
        TemplateWidget<TemplateIDs.PhotoCircle>()
        TemplateWidget<TemplateIDs.PhotoHalftone>()
        TemplateWidget<TemplateIDs.MusicCard>()
    }
}

struct TilesTemplateWidgets: WidgetBundle {
    var body: some Widget {
        TemplateWidget<TemplateIDs.TilesPills2>()
        TemplateWidget<TemplateIDs.TilesPills4>()
        TemplateWidget<TemplateIDs.TilesRound>()
        TemplateWidget<TemplateIDs.TilesHero>()
        TemplateWidget<TemplateIDs.MediaPlayer>()
        TemplateWidget<TemplateIDs.ControlCenter>()
        TemplateWidget<TemplateIDs.BatteryMood>()
    }
}

struct CounterTemplateWidgets: WidgetBundle {
    var body: some Widget {
        TemplateWidget<TemplateIDs.CounterTasbeeh>()
        TemplateWidget<TemplateIDs.TimerFocus>()
        TemplateWidget<TemplateIDs.TasksSmall>()
        TemplateWidget<TemplateIDs.TasksMedium>()
        TemplateWidget<TemplateIDs.TasksLarge>()
    }
}

// MARK: Timeline

struct TemplateEntry: TimelineEntry {
    let date: Date
    let templateID: String
    let spec: WidgetSpec?
    /// Why nothing can be drawn; shown as plain text instead of a gray widget (ADR-012).
    let problem: String?
    /// Real data for this timeline (ADR-016).
    var inputs = LiveInputs()
    /// A needed source with nothing real to show: the widget says so instead of showing numbers.
    var gap: DataGap?
    /// Widget gallery previews show the design with sample data (no fixes or downloads there).
    var sample = false
}

struct TemplateProvider: TimelineProvider {
    let templateID: String

    func placeholder(in context: Context) -> TemplateEntry {
        var entry = entry(date: .now)
        entry.sample = true
        return entry
    }

    func getSnapshot(in context: Context, completion: @escaping (TemplateEntry) -> Void) {
        var entry = entry(date: .now)
        if context.isPreview {
            entry.sample = true
        } else if let spec = entry.spec {
            entry.inputs = WidgetData.cachedInputs()
            entry.gap = LiveData.gap(for: spec, entry.inputs)
        }
        WidgetLog.add("snapshot \(templateID) preview=\(context.isPreview) \(entry.gap.map { "gap \($0.rawValue)" } ?? "ok")")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TemplateEntry>) -> Void) {
        Task {
            let start = Date.now
            let first = entry(date: start)
            guard let spec = first.spec else {
                completion(Timeline(entries: [first], policy: .never))
                return
            }
            let inputs = await WidgetData.inputs(for: DataRequirements.groups(for: spec), tickers: MarketData.tickers(in: spec), now: start)
            let gap = LiveData.gap(for: spec, inputs)
            let (dates, reload) = LiveSchedule.make(for: spec, inputs: inputs, now: start)
            ReloadLog.record(kind: templateID, reason: "timeline", entries: dates.count, next: reload, now: start)
            let entries = dates.map {
                TemplateEntry(date: $0, templateID: templateID, spec: spec, problem: nil, inputs: inputs, gap: gap)
            }
            WidgetLog.add("timeline \(templateID) \(entries.count) entries \(gap.map { "gap \($0.rawValue)" } ?? "ok") "
                + "\(WidgetLog.elapsed(since: start))ms \(Self.memory())")
            completion(Timeline(entries: entries, policy: .after(reload)))
        }
    }

    /// Loads only this template; failures become `problem`.
    func entry(date: Date) -> TemplateEntry {
        switch TemplateLibrary.load(id: templateID) {
        case .success(let spec):
            return TemplateEntry(date: date, templateID: templateID, spec: spec, problem: nil)
        case .failure(let issues):
            return TemplateEntry(date: date, templateID: templateID, spec: nil, problem: issues.description)
        }
    }

    /// "free 23.4 MB" (the extension's remaining memory budget).
    static func memory() -> String {
        String(format: "free %.1f MB", Double(os_proc_available_memory()) / 1_048_576)
    }
}

/// Entry dates and the next reload for a spec with live data: the spec's own refresh, at most an
/// hour for data (weather is hourly), and right after the next prayer when it shows prayers.
enum LiveSchedule {
    static func make(for spec: WidgetSpec, inputs: LiveInputs, now: Date) -> (dates: [Date], reload: Date) {
        let schedule = SpecTimeline.schedule(for: spec.refresh, from: now)
        let groups = DataRequirements.groups(for: spec)
        var reload = schedule.reloadAfter ?? .distantFuture
        if !groups.isDisjoint(with: [.weather, .health, .location, .device, .prayer]) {
            reload = min(reload, now.addingTimeInterval(3600))
        }
        // Values that change without telling the widget: iOS allows a reload about every 15 minutes.
        if !groups.isDisjoint(with: [.media, .audio, .system, .calendar, .reminders]) {
            reload = min(reload, now.addingTimeInterval(900))
        }
        if groups.contains(.prayer), let next = LiveData.snapshot(inputs, now: now).prayer?.nextTime {
            reload = min(reload, next.addingTimeInterval(60))
        }
        if reload == .distantFuture { reload = now.addingTimeInterval(6 * 3600) }
        // ADR-030: entries at the moments data is known to change (midnight, prayers, events, the timer's end),
        // so they show on time without spending a reload.
        let boundaries = TimelineBoundaries.dates(for: spec, data: LiveData.snapshot(inputs, now: now), now: now, until: reload)
        let dates = Array(Set(schedule.dates.filter { $0 < reload } + boundaries)).sorted()
        return (dates.isEmpty ? [now] : dates, reload)
    }
}

// MARK: View

/// Draws the template with live data through the package view the tests also render
/// (`SpecWidgetContent`), a data gap or a problem as plain text. Counter and stopwatch buttons
/// are interactive (ADR-016).
struct TemplateWidgetView: View {
    let entry: TemplateEntry

    var body: some View {
        if let problem = entry.problem {
            WidgetProblemView(title: entry.templateID, message: problem)
        } else if let gap = entry.gap, !entry.sample {
            DataGapView(gap: gap, title: entry.spec?.name.resolved(language: RenderContext.preferredLanguage) ?? entry.templateID)
        } else {
            SpecWidgetContent(spec: entry.spec, context: context)
                .environment(\.specActionButton, WidgetActionButtons.make)
                // The widget can't read the compass: a tap opens the live Qibla compass in the app.
                .widgetURL(entry.spec.map(DataRequirements.showsQibla) == true ? URL(string: "widgetstudio://qibla") : nil)
        }
    }

    /// Real data (or the gallery sample) with the 12/24-hour clock from the settings (ADR-017).
    private var context: RenderContext {
        var context = RenderContext(
            date: entry.date, language: RenderContext.preferredLanguage,
            data: entry.sample ? .sample(now: entry.date) : LiveData.snapshot(entry.inputs, now: entry.date)
        )
        context.uses24Hour = entry.inputs.settings.clockFormat.uses24Hour()
        context.mediaArtwork = entry.inputs.device.artwork
        return context
    }
}

/// Why a template has no real data yet, in the app's language (never fake numbers, ADR-016).
struct DataGapView: View {
    let gap: DataGap
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color(hex: "#E2231A"))
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .containerBackground(Color(white: 0.055), for: .widget)
        .widgetURL(URL(string: "widgetstudio://settings"))
    }

    private var icon: String {
        switch gap {
        case .noLocation: "location.slash"
        case .noWeather: "cloud"
        case .noHealth: "heart.text.square"
        case .noBattery: "battery.0"
        case .noTasks: "checklist"
        }
    }

    private var message: LocalizedStringKey {
        switch gap {
        case .noLocation: "widget.gap.noLocation"
        case .noWeather: "widget.gap.noWeather"
        case .noHealth: "widget.gap.noHealth"
        case .noBattery: "widget.gap.noBattery"
        case .noTasks: "widget.gap.noTasks"
        }
    }
}

/// Plain text in system fonts: renders even when a template can't.
struct WidgetProblemView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("widget.problem.title")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.yellow)
            Text(verbatim: title)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(verbatim: message)
                .font(.system(size: 10))
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .containerBackground(Color(white: 0.1), for: .widget)
        .environment(\.layoutDirection, .leftToRight)
    }
}
