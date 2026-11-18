import Foundation

/// Every widget reload and its reason (ADR-030): the app's reload requests (a design saved, the app
/// going to the background, a tap's action) and every timeline the extension builds (entries, next
/// reload). Diagnostics shows the last one per widget. Without an App Group the app and the extension
/// keep separate logs; each side shows its own.
public struct ReloadLog: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var kind: String
        public var reason: String
        public var date: Date
        /// Timeline builds: how many entries, and when WidgetKit may ask again.
        public var entries: Int?
        public var next: Date?

        public var id: String { "\(kind)|\(date.timeIntervalSince1970)" }
    }

    public var entries: [Entry] = []

    public static let cacheName = "reloads"
    public static let limit = 60

    public static func record(kind: String, reason: String, entries count: Int? = nil, next: Date? = nil,
                              cache: DataCache = DataCache(), now: Date = .now) {
        var log = cache.read(ReloadLog.self, cacheName) ?? ReloadLog()
        log.entries.append(Entry(kind: kind, reason: reason, date: now, entries: count, next: next))
        if log.entries.count > limit { log.entries.removeFirst(log.entries.count - limit) }
        try? cache.write(log, cacheName)
    }

    public static func load(cache: DataCache = DataCache()) -> [Entry] {
        cache.read(ReloadLog.self, cacheName)?.entries ?? []
    }

    /// The newest entry per kind, newest first.
    public static func latest(cache: DataCache = DataCache()) -> [Entry] {
        var seen: [String: Entry] = [:]
        for entry in load(cache: cache) { seen[entry.kind] = entry }
        return seen.values.sorted { $0.date > $1.date }
    }
}

/// Moments a timeline should have an entry at, beyond its refresh cadence (ADR-030): midnight (dates and
/// day shares), the day's prayer times, upcoming calendar starts and ends, the timer's end. Predictable
/// changes then appear on time without spending a reload.
public enum TimelineBoundaries {
    public static func dates(for spec: WidgetSpec, data: DataSnapshot, now: Date, until end: Date, calendar: Calendar = .current) -> [Date] {
        let groups = DataRequirements.groups(for: spec)
        var dates: [Date] = []
        if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) {
            dates.append(midnight)
        }
        if groups.contains(.prayer), let times = data.prayer?.times.values { dates += times }
        if groups.contains(.calendar) {
            for (key, value) in data.live where key.hasPrefix("calendar.") && (key.hasSuffix(".time") || key.hasSuffix(".end")) {
                if case .date(let date) = value { dates.append(date) }
            }
        }
        if groups.contains(.app), let end = data.timer?.end { dates.append(end) }
        return Array(Set(dates.filter { $0 > now && $0 < end })).sorted()
    }
}
