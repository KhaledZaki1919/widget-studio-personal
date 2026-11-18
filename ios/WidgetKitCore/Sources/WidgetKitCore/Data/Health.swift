import Foundation
#if canImport(HealthKit) && os(iOS)
import HealthKit
#endif

/// Steps and sleep as read from HealthKit (ADR-016), cached, plus the pure aggregation the
/// templates need (streak, month grid, week bars). Day keys are "yyyy-MM-dd" in the calendar's zone.
public struct HealthSummary: Codable, Sendable, Equatable {
    /// Steps per day for the last ~62 days.
    public var steps: [String: Double]
    /// Minutes asleep per night, keyed by the morning's date.
    public var sleep: [String: Double]
    /// Bedtime and wake time per night, same keys (ADR-027; absent in older caches).
    public var sleepWindows: [String: SleepWindow]?
    /// ADR-029: heart, variability, exercise, energy, stages, steps per hour (absent in older caches).
    public var extras: HealthExtras?
    public var fetched: Date

    public struct SleepWindow: Codable, Sendable, Equatable {
        public var start: Date
        public var end: Date
    }

    public static let cacheName = "health"
    public static let stepDays = 62

    public init(steps: [String: Double], sleep: [String: Double], sleepWindows: [String: SleepWindow]? = nil, fetched: Date) {
        self.steps = steps
        self.sleep = sleep
        self.sleepWindows = sleepWindows
        self.fetched = fetched
    }

    /// Last night's bedtime and wake time.
    public func sleepWindow(now: Date, calendar: Calendar) -> SleepWindow? {
        sleepWindows?[Self.key(now, calendar)]
    }

    static func key(_ date: Date, _ calendar: Calendar) -> String {
        FormatterCache.date("yyyy-MM-dd", locale: "en_US_POSIX", zone: calendar.timeZone).string(from: date)
    }

    public func stepsToday(now: Date, calendar: Calendar) -> Double {
        steps[Self.key(now, calendar)] ?? 0
    }

    /// Consecutive days at or over the goal, ending today if today already made it, else yesterday.
    public func streak(now: Date, goal: Double, calendar: Calendar) -> Int {
        var day = now
        if (steps[Self.key(day, calendar)] ?? 0) < goal {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while (steps[Self.key(day, calendar)] ?? 0) >= goal, count < Self.stepDays {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// The month as `MonthGrid` cells: steps ÷ goal for past days, today highlighted, the rest 0.
    public func monthLevels(now: Date, goal: Double, calendar: Calendar) -> [Double] {
        let today = calendar.component(.day, from: now)
        guard let month = calendar.dateInterval(of: .month, for: now),
              let days = calendar.range(of: .day, in: .month, for: now)?.count else { return [] }
        let perDay = (1...days).map { day -> Double in
            if day == today { return MonthGrid.highlight }
            guard day < today, let date = calendar.date(byAdding: .day, value: day - 1, to: month.start) else { return 0 }
            return min((steps[Self.key(date, calendar)] ?? 0) / max(goal, 1), 1)
        }
        return MonthGrid.levels(perDay: perDay, monthOf: now, calendar: calendar)
    }

    public func monthTotal(now: Date, calendar: Calendar) -> Double {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return 0 }
        let today = calendar.component(.day, from: now)
        return (0..<today).reduce(0) { total, offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: month.start) else { return total }
            return total + (steps[Self.key(date, calendar)] ?? 0)
        }
    }

    public func sleepLastNight(now: Date, calendar: Calendar) -> Double? {
        sleep[Self.key(now, calendar)]
    }

    /// This week's nights, Sunday to Saturday (the Sleep Week labels), as 0…1 of 9 hours.
    public func sleepWeek(now: Date, calendar: Calendar) -> [Double] {
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        return (1...7).map { day -> Double in
            guard day <= weekday, let date = calendar.date(byAdding: .day, value: day - weekday, to: now) else { return 0 }
            return min((sleep[Self.key(date, calendar)] ?? 0) / (9 * 60), 1)
        }
    }

    /// "7h 20m" / "7س 20د".
    public static func duration(minutes: Double) -> LocalizedText {
        let total = Int(minutes.rounded())
        return .localized(en: "\(total / 60)h \(total % 60)m", ar: "\(total / 60)س \(total % 60)د")
    }
}

/// Why steps or sleep can't be shown; the widget shows a message instead of numbers.
public enum HealthIssue: String, Codable, Sendable, Error {
    /// HealthKit doesn't exist here (or the extension isn't entitled).
    case unavailable
    /// No data came back: read access denied or never granted (HealthKit hides which), or no data.
    case noData
    /// HealthKit returned an error (e.g. the device is locked).
    case error
}

#if canImport(HealthKit) && os(iOS)
/// Reads steps (62 days) and sleep (8 nights). Used by the app and by the widget extension.
public enum HealthReader {
    public static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let store = HKHealthStore()

    public static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        return types.union(extraTypes)
    }

    /// Asks for read access (the app only; extensions can't show the prompt).
    public static func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    public static func read(now: Date = .now, calendar: Calendar = .current) async -> Result<HealthSummary, HealthIssue> {
        guard isAvailable else { return .failure(.unavailable) }
        do {
            let steps = try await dailySteps(now: now, calendar: calendar)
            let (sleep, windows) = try await nightlySleep(now: now, calendar: calendar)
            if steps.isEmpty && sleep.isEmpty { return .failure(.noData) }
            var summary = HealthSummary(steps: steps, sleep: sleep, sleepWindows: windows, fetched: now)
            summary.extras = await extras(now: now, calendar: calendar)
            return .success(summary)
        } catch let error as HKError where error.code == .errorAuthorizationDenied || error.code == .errorAuthorizationNotDetermined {
            return .failure(.noData)
        } catch let error as HKError where error.code == .errorHealthDataUnavailable {
            return .failure(.unavailable)
        } catch {
            return .failure(.error)
        }
    }

    static func dailySteps(now: Date, calendar: Calendar) async throws -> [String: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let start = calendar.date(byAdding: .day, value: -(HealthSummary.stepDays - 1), to: calendar.startOfDay(for: now))
        else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    if (error as? HKError)?.code == .errorNoData { continuation.resume(returning: [:]) } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var result: [String: Double] = [:]
                collection?.enumerateStatistics(from: start, to: now) { statistics, _ in
                    if let sum = statistics.sumQuantity()?.doubleValue(for: .count()), sum > 0 {
                        result[HealthSummary.key(statistics.startDate, calendar)] = sum
                    }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    static func nightlySleep(now: Date, calendar: Calendar) async throws -> ([String: Double], [String: HealthSummary.SleepWindow]) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
              let start = calendar.date(byAdding: .day, value: -8, to: calendar.startOfDay(for: now)) else { return ([:], [:]) }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) {
                _, samples, error in
                if let error {
                    if (error as? HKError)?.code == .errorNoData { continuation.resume(returning: ([:], [:])) } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var nights: [String: Double] = [:]
                var windows: [String: HealthSummary.SleepWindow] = [:]
                for case let sample as HKCategorySample in samples ?? [] where asleep.contains(sample.value) {
                    // A night belongs to the morning it ends in: start + 12 h lands on that day.
                    let night = HealthSummary.key(sample.startDate.addingTimeInterval(12 * 3600), calendar)
                    nights[night, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60
                    let window = windows[night]
                    windows[night] = HealthSummary.SleepWindow(start: min(window?.start ?? sample.startDate, sample.startDate),
                                                               end: max(window?.end ?? sample.endDate, sample.endDate))
                }
                continuation.resume(returning: (nights, windows))
            }
            store.execute(query)
        }
    }
}
#endif
