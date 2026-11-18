import Foundation

/// The tasbeeh counter (ADR-016), kept by whoever runs the button: the widget extension (in its
/// own container, no App Group needed) or the app. It cycles through a dhikr list with a separate
/// count per dhikr (M4 feedback); the list comes from `AppSettings.dhikrs` (the default list in
/// store mode, where the widget can't see the app's settings).
public struct CounterState: Codable, Sendable, Equatable {
    public static let defaultDhikrs = ["سبحان الله", "الحمد لله", "الله أكبر", "لا إله إلا الله"]

    /// Count per dhikr text; a reset removes the entry.
    public var counts: [String: Int] = [:]
    /// The current dhikr's position in the list (wrapped to the list's length).
    public var index: Int = 0
    public var updated: Date = .distantPast

    public static let cacheName = "counter"

    /// `value` is the first default dhikr's count (M4 files before the dhikr list).
    public init(value: Int = 0, updated: Date = .distantPast) {
        if value > 0 { counts[Self.defaultDhikrs[0]] = value }
        self.updated = updated
    }

    /// The current dhikr's count in the default list.
    public var value: Int { count(in: Self.defaultDhikrs) }

    public func dhikr(in list: [String]) -> String {
        let list = Self.usable(list)
        return list[((index % list.count) + list.count) % list.count]
    }

    public func count(in list: [String]) -> Int {
        counts[dhikr(in: list)] ?? 0
    }

    /// +1 for the current dhikr. With `autoAdvance`, a tap after the current dhikr reached
    /// `target` moves to the next dhikr (starting it from 0) and counts there, so the full ring
    /// stays visible until then.
    public mutating func increment(list: [String] = defaultDhikrs, target: Int? = nil, autoAdvance: Bool = false,
                                   now: Date = .now) {
        if autoAdvance, let target, target > 0, count(in: list) >= target {
            index = (index + 1) % Self.usable(list).count
            counts[dhikr(in: list)] = nil
        }
        counts[dhikr(in: list), default: 0] += 1
        updated = now
    }

    /// The next dhikr in the list; counts stay.
    public mutating func next(list: [String] = defaultDhikrs, now: Date = .now) {
        index = (index + 1) % Self.usable(list).count
        updated = now
    }

    /// Resets the current dhikr only.
    public mutating func reset(list: [String] = defaultDhikrs, now: Date = .now) {
        counts[dhikr(in: list)] = nil
        updated = now
    }

    /// The list without blank entries; the default list when nothing is left.
    public static func usable(_ list: [String]) -> [String] {
        let cleaned = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? defaultDhikrs : cleaned
    }

    public static func load(_ cache: DataCache = DataCache()) -> CounterState {
        cache.read(CounterState.self, cacheName) ?? CounterState()
    }

    public func save(_ cache: DataCache = DataCache()) throws {
        try cache.write(self, Self.cacheName)
    }

    enum CodingKeys: String, CodingKey {
        case counts, index, updated, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updated = (try? container.decode(Date.self, forKey: .updated)) ?? .distantPast
        index = (try? container.decode(Int.self, forKey: .index)) ?? 0
        if let counts = try? container.decode([String: Int].self, forKey: .counts) {
            self.counts = counts
        } else if let value = try? container.decode(Int.self, forKey: .value), value > 0 {
            counts = [Self.defaultDhikrs[0]: value]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(counts, forKey: .counts)
        try container.encode(index, forKey: .index)
        try container.encode(updated, forKey: .updated)
    }
}

/// The stopwatch: running since `start`, plus finished sessions (14 days), which also feed Focus
/// Today (`focus.today`, `focus.week`).
public struct StopwatchState: Codable, Sendable, Equatable {
    public struct Session: Codable, Sendable, Equatable {
        public var start: Date
        public var end: Date
    }

    public var start: Date?
    public var sessions: [Session] = []

    public static let cacheName = "stopwatch"
    static let keepDays: TimeInterval = 14 * 86_400

    public init(start: Date? = nil, sessions: [Session] = []) {
        self.start = start
        self.sessions = sessions
    }

    public var isRunning: Bool { start != nil }

    /// Starts, or stops and records the session.
    public mutating func toggle(now: Date = .now) {
        if let start {
            if now > start { sessions.append(Session(start: start, end: now)) }
            self.start = nil
        } else {
            start = now
        }
        sessions.removeAll { now.timeIntervalSince($0.end) > Self.keepDays }
    }

    /// Minutes recorded on `day` (sessions split at midnight; a running session counts until now).
    public func minutes(on day: Date, now: Date, calendar: Calendar) -> Double {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return 0 }
        let all = sessions + (start.map { [Session(start: $0, end: now)] } ?? [])
        return all.reduce(0) { total, session in
            let overlap = min(session.end, interval.end).timeIntervalSince(max(session.start, interval.start))
            return total + max(0, overlap) / 60
        }
    }

    /// The last 7 days, oldest first, as 0…1 of the busiest day (at least one hour).
    public func week(now: Date, calendar: Calendar) -> [Double] {
        let minutes = (0..<7).reversed().map { offset -> Double in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return 0 }
            return self.minutes(on: day, now: now, calendar: calendar)
        }
        let top = max(minutes.max() ?? 0, 60)
        return minutes.map { $0 / top }
    }

    public static func load(_ cache: DataCache = DataCache()) -> StopwatchState {
        cache.read(StopwatchState.self, cacheName) ?? StopwatchState()
    }

    public func save(_ cache: DataCache = DataCache()) throws {
        try cache.write(self, Self.cacheName)
    }
}

/// The in-widget timer (ADR-027): running until `end`, or paused with `left` seconds to go. Kept
/// by whoever runs the button, like the stopwatch.
public struct TimerState: Codable, Sendable, Equatable {
    public var end: Date?
    /// Seconds left while paused; 0 = idle.
    public var left: TimeInterval = 0
    /// The length it started with, for the progress.
    public var total: TimeInterval = 0

    public static let cacheName = "timer"
    public static let defaultMinutes = 25

    public init(end: Date? = nil, left: TimeInterval = 0, total: TimeInterval = 0) {
        self.end = end
        self.left = left
        self.total = total
    }

    public func isRunning(at date: Date) -> Bool {
        end.map { $0 > date } ?? false
    }

    public func remaining(at date: Date) -> TimeInterval {
        if let end { return max(end.timeIntervalSince(date), 0) }
        return left
    }

    /// The share that has passed, 0…1.
    public func progress(at date: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(max(1 - remaining(at: date) / total, 0), 1)
    }

    /// Starts (`minutes` when idle or finished), pauses, or resumes.
    public mutating func toggle(minutes: Int? = nil, now: Date = .now) {
        if isRunning(at: now) {
            left = remaining(at: now)
            end = nil
        } else if left > 0 {
            end = now.addingTimeInterval(left)
            left = 0
        } else {
            total = TimeInterval(max(minutes ?? Self.defaultMinutes, 1)) * 60
            end = now.addingTimeInterval(total)
        }
    }

    public mutating func add(minutes: Int, now: Date = .now) {
        let extra = TimeInterval(minutes) * 60
        total += extra
        if isRunning(at: now), let current = end {
            end = current.addingTimeInterval(extra)
        } else if left > 0 {
            left += extra
        } else {
            total = extra
            end = now.addingTimeInterval(extra)
        }
    }

    public mutating func reset() {
        end = nil
        left = 0
        total = 0
    }

    public static func load(_ cache: DataCache = DataCache()) -> TimerState {
        cache.read(TimerState.self, cacheName) ?? TimerState()
    }

    public func save(_ cache: DataCache = DataCache()) throws {
        try cache.write(self, Self.cacheName)
    }
}

/// What is playing and where (ADR-027).
public struct MediaPlayback: Sendable, Equatable {
    public var elapsed: TimeInterval
    public var duration: TimeInterval
    public var playing: Bool
    /// When `elapsed` was read.
    public var at: Date

    public init(elapsed: TimeInterval, duration: TimeInterval, playing: Bool, at: Date) {
        self.elapsed = elapsed
        self.duration = duration
        self.playing = playing
        self.at = at
    }

    public func position(at date: Date) -> TimeInterval {
        let moved = playing ? max(date.timeIntervalSince(at), 0) : 0
        return duration > 0 ? min(elapsed + moved, duration) : elapsed + moved
    }

    /// "4:23" or "1:02:03".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded())
        let (hours, minutes, rest) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}
