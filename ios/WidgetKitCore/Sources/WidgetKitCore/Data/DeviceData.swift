import CoreGraphics
import Foundation
#if os(iOS)
import AVFAudio
import EventKit
import MediaPlayer
import Network
import UIKit
#endif

/// Catalog bindings read from the device for one timeline (ADR-027).
public struct DeviceValues: Sendable {
    public var live: [String: BindingResolver.Value] = [:]
    public var media: MediaPlayback?
    public var artwork: CGImage?
    /// A widget that needs tasks can't read Reminders here.
    public var noTasks = false

    public init() {}
}

/// The actions a widget tap performs without leaving the home screen. `CapabilityDriftTests`
/// fails when a catalog action marked native on iOS is neither here nor in `AppActions`.
public enum NativeActions {
    public static let widgetExtension: Set<String> = [
        "counter.increment", "counter.reset", "counter.next", "stopwatch.toggle",
        "timer.toggle", "timer.add", "timer.reset", "media.playPause", "media.next", "media.previous", "task.toggle",
    ]
    /// Opened by the app when the widget's link arrives.
    public static let app: Set<String> = [
        "open.app", "open.url", "open.deeplink", "call.dial", "message.open", "calendar.open", "reminders.open",
        "compass.open", "weather.open", "media.open", "task.add",
        // ADR-029: the system apps, by their URL schemes.
        "alarm.open", "clock.open", "health.open",
    ]
}

/// Pure pieces of the readers, so the unit tests cover them on any host.
public enum DeviceFormat {
    static func bool(_ value: Bool) -> BindingResolver.Value { .text(value ? "1" : "0") }

    static func share(_ value: Double) -> BindingResolver.Value {
        .number(value, display: String(Int((min(max(value, 0), 1) * 100).rounded())))
    }

    public static func batterySymbol(_ level: Double) -> String {
        switch level {
        case ..<0.2: "battery.25"
        case ..<0.45: "battery.50"
        case ..<0.8: "battery.75"
        default: "battery.100"
        }
    }

    public static func volumeSymbol(_ level: Double) -> String {
        switch level {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.5: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    public static func volumeValues(_ level: Double) -> [String: BindingResolver.Value] {
        ["volume.level": share(level), "volume.muted": bool(level < 0.01), "volume.symbol": .text(volumeSymbol(level))]
    }

    /// Up to `limit` upcoming events as `calendar.N.*`, plus `calendar.next.*` and the count of today's.
    public static func events(_ events: [(title: String, start: Date, location: String?)], now: Date,
                              calendar: Calendar) -> [String: BindingResolver.Value] {
        var live: [String: BindingResolver.Value] = [:]
        let upcoming = events.filter { $0.start >= now || calendar.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
        live["calendar.count"] = .number(Double(upcoming.filter { calendar.isDate($0.start, inSameDayAs: now) }.count),
                                         display: String(upcoming.filter { calendar.isDate($0.start, inSameDayAs: now) }.count))
        if let next = upcoming.first {
            live["calendar.next.title"] = .text(next.title)
            live["calendar.next.time"] = .date(next.start)
            live["calendar.next.location"] = .text(next.location ?? "")
        }
        for (index, event) in upcoming.prefix(4).enumerated() {
            live["calendar.\(index + 1).title"] = .text(event.title)
            live["calendar.\(index + 1).time"] = .date(event.start)
        }
        return live
    }

    /// ADR-029: `calendar.N.end`, `.calendar`, `.color` and `calendar.next.end`, in the order of `events`.
    public static func eventExtras(_ events: [(start: Date, end: Date, calendar: String, color: String)], now: Date,
                                   calendar: Calendar) -> [String: BindingResolver.Value] {
        var live: [String: BindingResolver.Value] = [:]
        let upcoming = events.filter { $0.start >= now || calendar.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
        if let next = upcoming.first { live["calendar.next.end"] = .date(next.end) }
        for (index, event) in upcoming.prefix(4).enumerated() {
            live["calendar.(index + 1).end"] = .date(event.end)
            live["calendar.(index + 1).calendar"] = .text(event.calendar)
            live["calendar.(index + 1).color"] = .text(event.color)
        }
        return live
    }

    public static func reminders(_ titles: [String]) -> [String: BindingResolver.Value] {
        var live: [String: BindingResolver.Value] = ["reminders.count": .number(Double(titles.count), display: String(titles.count))]
        for (index, title) in titles.prefix(4).enumerated() { live["reminders.\(index + 1).title"] = .text(title) }
        return live
    }

    /// When nothing plays (or the app has no access), the title says so instead of "--".
    public static func nothingPlaying(language: String) -> BindingResolver.Value {
        .text(language.hasPrefix("ar") ? "لا يوجد تشغيل" : "Not playing")
    }
}

public enum DeviceData {
    /// Reads only what `groups` needs. Anything iOS won't give stays absent and renders "--"
    /// (or the off look of a switch); the catalog says which.
    @MainActor
    public static func read(groups: Set<Bindings.Group>, language: String, now: Date = .now) async -> DeviceValues {
        var values = DeviceValues()
        #if os(iOS)
        if groups.contains(.device) {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            values.live["battery.charging"] = DeviceFormat.bool(device.batteryState == .charging || device.batteryState == .full)
            if device.batteryLevel >= 0 { values.live["battery.symbol"] = .text(DeviceFormat.batterySymbol(Double(device.batteryLevel))) }
        }
        if groups.contains(.audio) {
            values.live.merge(DeviceFormat.volumeValues(Double(AVAudioSession.sharedInstance().outputVolume))) { _, new in new }
        }
        if groups.contains(.system) {
            values.live["system.lowPower"] = DeviceFormat.bool(ProcessInfo.processInfo.isLowPowerModeEnabled)
            values.live["system.darkMode"] = DeviceFormat.bool(UITraitCollection.current.userInterfaceStyle == .dark)
            if let path = await currentPath() {
                values.live["system.wifi"] = DeviceFormat.bool(path.usesInterfaceType(.wifi))
                values.live["system.mobileData"] = DeviceFormat.bool(path.usesInterfaceType(.cellular))
            }
        }
        if groups.contains(.media) { readMedia(into: &values, language: language, now: now) }
        if groups.contains(.calendar) {
            let events = await calendarValues(now: now)
            values.live.merge(events) { _, new in new }
        }
        if groups.contains(.reminders) {
            let reminders = await reminderValues()
            values.live.merge(reminders) { _, new in new }
        }
        if groups.contains(.tasks) {
            values.noTasks = !TaskStore.isAuthorized
            let tasks = await TaskStore().load()
            values.live.merge(TaskFormat.values(tasks, now: now, calendar: .current, language: language)) { _, new in new }
        }
        #endif
        return values
    }

    #if os(iOS)
    /// The network path after its first update, or nil after a second.
    private static func currentPath() async -> NWPath? {
        await withCheckedContinuation { (continuation: CheckedContinuation<NWPath?, Never>) in
            let monitor = NWPathMonitor()
            let once = ResumeOnce()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                if once.claim() { continuation.resume(returning: path) }
            }
            monitor.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                monitor.cancel()
                if once.claim() { continuation.resume(returning: nil) }
            }
        }
    }

    /// `MPMusicPlayerController` covers Apple Music only: iOS has no API for other players'
    /// now playing (ADR-027).
    private static func readMedia(into values: inout DeviceValues, language: String, now: Date) {
        guard MediaControl.isAuthorized else {
            values.live["media.title"] = DeviceFormat.nothingPlaying(language: language)
            return
        }
        let player = MPMusicPlayerController.systemMusicPlayer
        guard let item = player.nowPlayingItem else {
            values.live["media.title"] = DeviceFormat.nothingPlaying(language: language)
            return
        }
        values.live["media.title"] = .text(item.title ?? "")
        values.live["media.artist"] = .text(item.artist ?? "")
        values.live["media.album"] = .text(item.albumTitle ?? "")
        values.live["media.app"] = .text(language.hasPrefix("ar") ? "الموسيقى" : "Music")
        values.media = MediaPlayback(elapsed: player.currentPlaybackTime.isFinite ? player.currentPlaybackTime : 0,
                                     duration: item.playbackDuration, playing: player.playbackState == .playing, at: now)
        values.artwork = item.artwork?.image(at: CGSize(width: 300, height: 300))?.cgImage
    }

    private static func calendarValues(now: Date) async -> [String: BindingResolver.Value] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [:] }
        let store = EKEventStore()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [:] }
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).filter { !$0.isAllDay }
        let events = found.map { (title: $0.title ?? "", start: $0.startDate ?? now, location: $0.location) }
        // ADR-029: end time, calendar name and color.
        let extras = found.map { event in
            (start: event.startDate ?? now, end: event.endDate ?? now, calendar: event.calendar?.title ?? "",
             color: event.calendar.flatMap { HexColor.hex($0.cgColor) } ?? "#8E8E93")
        }
        return DeviceFormat.events(events, now: now, calendar: calendar)
            .merging(DeviceFormat.eventExtras(extras, now: now, calendar: calendar)) { _, new in new }
    }

    private static func reminderValues() async -> [String: BindingResolver.Value] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [:] }
        let store = EKEventStore()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let titles: [String] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).compactMap(\.title))
            }
        }
        return DeviceFormat.reminders(titles)
    }
    #endif
}

#if os(iOS)
/// One resume for a continuation raced by a callback and a timeout.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
#endif

/// Apple Music controls from the widget extension (ADR-027).
public enum MediaControl {
    public static var isAuthorized: Bool {
        #if os(iOS)
        MPMediaLibrary.authorizationStatus() == .authorized
        #else
        false
        #endif
    }

    /// Runs `media.playPause`, `media.next` or `media.previous`; false without access.
    @MainActor
    @discardableResult
    public static func perform(_ command: String) -> Bool {
        #if os(iOS)
        guard isAuthorized else { return false }
        let player = MPMusicPlayerController.systemMusicPlayer
        switch command {
        case "media.playPause":
            if player.playbackState == .playing { player.pause() } else { player.play() }
        case "media.next": player.skipToNextItem()
        case "media.previous": player.skipToPreviousItem()
        default: return false
        }
        return true
        #else
        return false
        #endif
    }
}

extension HexColor {
    /// "#RRGGBB" of a color, through sRGB (a calendar's color, ADR-029).
    public static func hex(_ color: CGColor) -> String? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = color.converted(to: space, intent: .defaultIntent, options: nil),
              let parts = rgb.components, parts.count >= 3 else { return nil }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(parts[0]), byte(parts[1]), byte(parts[2]))
    }
}
