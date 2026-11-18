import AppIntents
import SwiftUI
import WidgetKit
import WidgetKitCore

// Interactive widget buttons (iOS 17, ADR-016): tasbeeh +1 / next dhikr / reset and stopwatch
// start/stop. They run in the widget extension and keep their state in its own container, so
// they need no App Group. Each run is logged; the large check widget shows whether they ran on
// this install (ADR-013 showed AppIntent configuration doesn't render on Fast Store).

struct CounterIncrementIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.intent.counter.increment"
    static var isDiscoverable = false

    /// The template's `target` field (the button's arg), for auto-advance; 0 = none.
    @Parameter(title: "widget.intent.counter.target", default: 0)
    var target: Int

    init() {}

    init(target: Int) {
        self.target = target
    }

    func perform() async throws -> some IntentResult {
        let settings = AppSettings.load()
        var counter = CounterState.load()
        counter.increment(list: settings.dhikrList, target: target, autoAdvance: settings.tasbeehAutoAdvance)
        try counter.save()
        WidgetLog.add("intent counter +1 -> \(counter.count(in: settings.dhikrList)) (dhikr \(counter.index + 1))")
        WidgetReloads.afterAction(String(describing: Self.self))
        return .result()
    }
}

/// Resets the current dhikr only.
struct CounterResetIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.intent.counter.reset"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var counter = CounterState.load()
        counter.reset(list: AppSettings.load().dhikrList)
        try counter.save()
        WidgetLog.add("intent counter reset")
        WidgetReloads.afterAction(String(describing: Self.self))
        return .result()
    }
}

/// The next dhikr in the list (each keeps its own count).
struct CounterNextIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.intent.counter.next"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var counter = CounterState.load()
        counter.next(list: AppSettings.load().dhikrList)
        try counter.save()
        WidgetLog.add("intent counter next -> dhikr \(counter.index + 1)")
        WidgetReloads.afterAction(String(describing: Self.self))
        return .result()
    }
}

struct StopwatchToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.intent.stopwatch.toggle"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var stopwatch = StopwatchState.load()
        stopwatch.toggle()
        try stopwatch.save()
        WidgetLog.add("intent stopwatch \(stopwatch.isRunning ? "started" : "stopped")")
        WidgetReloads.afterAction(String(describing: Self.self))
        return .result()
    }
}

/// Starts, pauses or resumes the timer; `minutes` sets its length when it starts (ADR-027).
struct TimerToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.intent.timer.toggle"
    static var isDiscoverable = false

    @Parameter(title: "widget.intent.timer.minutes", default: 0)
    var minutes: Int

    init() {}

    init(minutes: Int) {
        self.minutes = minutes
    }

    func perform() async throws -> some IntentResult {
        var timer = TimerState.load()
        timer.toggle(minutes: minutes > 0 ? minutes : nil)
        try timer.save()
        WidgetLog.add("intent timer toggle")
        WidgetReloads.afterAction(String(describing: Self.self))
        return .result()
    }
}

struct TimerAddIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.intent.timer.add"
    static var isDiscoverable = false

    @Parameter(title: "widget.intent.timer.minutes", default: 5)
    var minutes: Int

    init() {}

    init(minutes: Int) {
        self.minutes = minutes
    }

    func perform() async throws -> some IntentResult {
        var timer = TimerState.load()
        timer.add(minutes: minutes)
        try timer.save()
        WidgetLog.add("intent timer add \(minutes)")
        WidgetReloads.afterAction(String(describing: Self.self))
        return .result()
    }
}

struct TimerResetIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.intent.timer.reset"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var timer = TimerState.load()
        timer.reset()
        try timer.save()
        WidgetLog.add("intent timer reset")
        WidgetReloads.afterAction(String(describing: Self.self))
        return .result()
    }
}

/// Apple Music controls, run in the extension (ADR-027). Whether they run on the Fast Store
/// install shows in the step log and in Diagnostics → Media.
struct MediaControlIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.intent.media"
    static var isDiscoverable = false

    /// `media.playPause`, `media.next` or `media.previous`.
    @Parameter(title: "widget.intent.media.command")
    var command: String

    init() {}

    init(command: String) {
        self.command = command
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let done = MediaControl.perform(command)
        WidgetLog.add("intent \(command) \(done ? "sent" : "not allowed")")
        WidgetReloads.afterAction(String(describing: Self.self))
        return .result()
    }
}

/// Ticks a task in the widget itself (ADR-028): Reminders is shared with the app without an App
/// Group, and WidgetKit redraws after an intent runs.
struct TaskToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.intent.task.toggle"
    static var isDiscoverable = false

    @Parameter(title: "widget.intent.task.id", default: "")
    var id: String

    init() {}

    init(id: String) {
        self.id = id
    }

    func perform() async throws -> some IntentResult {
        guard !id.isEmpty else { return .result() }
        do {
            try TaskStore().toggle(id: id)
            WidgetLog.add("intent task toggled")
        } catch {
            WidgetLog.add("intent task failed: \(error)")
        }
        WidgetReloads.afterAction(String(describing: Self.self))
        return .result()
    }
}

/// Interactive controls for the renderer's button layers (`specActionButton`). Everything else
/// keeps the default link to the app, which follows the catalog (Shortcut, hint, open…).
enum WidgetActionButtons {
    static let make: SpecActionButton = { action, arg in
        switch action.rawValue {
        case "counter.increment": AnyView(button(CounterIncrementIntent(target: arg.flatMap { Int($0) } ?? 0)))
        case "counter.reset": AnyView(button(CounterResetIntent()))
        case "counter.next": AnyView(button(CounterNextIntent()))
        case "stopwatch.toggle": AnyView(button(StopwatchToggleIntent()))
        case "task.toggle": (arg ?? "").isEmpty ? nil : AnyView(button(TaskToggleIntent(id: arg ?? "")))
        case "timer.toggle": AnyView(button(TimerToggleIntent(minutes: arg.flatMap { Int($0) } ?? 0)))
        case "timer.add": AnyView(button(TimerAddIntent(minutes: arg.flatMap { Int($0) } ?? 5)))
        case "timer.reset": AnyView(button(TimerResetIntent()))
        // arg "shortcut" sends the tap through a Shortcut, which controls any player.
        case "media.playPause", "media.next", "media.previous":
            arg == "shortcut" || !MediaControl.isAuthorized ? nil : AnyView(button(MediaControlIntent(command: action.rawValue)))
        default: nil
        }
    }

    static func button<Intent: AppIntent>(_ intent: Intent) -> some View {
        Button(intent: intent) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// ADR-030: after an action, every widget reloads at once (others may show the same counter, timer or task),
/// and the reason goes to the reload log.
enum WidgetReloads {
    static func afterAction(_ name: String) {
        ReloadLog.record(kind: "all", reason: "action " + name)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
