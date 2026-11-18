import Foundation
#if canImport(HealthKit) && os(iOS)
import HealthKit
#endif

/// ADR-029: heart rate, variability, exercise, energy, sleep stages and steps per hour, read with the
/// summary and cached with it. Each part is optional: a type the user didn't allow is simply missing.
/// Twin of Extras.healthValues on Android.
public struct HealthExtras: Codable, Sendable, Equatable {
    /// Today's heart rate as (time since midnight in seconds, bpm).
    public var heart: [[Double]]?
    public var resting: Double?
    /// Heart-rate variability (SDNN, ms) for the stress estimate.
    public var variability: Double?
    public var exerciseMinutes: Double?
    public var activeKcal: Double?
    /// Last night's stages every 10 minutes: 0 deep, 1 core, 2 REM, 3 awake.
    public var stages: [Double]?
    public var stepsHourly: [Double]?

    public init() {}

    /// The catalog values (ADR-029).
    public func values(now: Date, calendar: Calendar, sleepMinutes: Double?) -> [String: BindingResolver.Value] {
        var live: [String: BindingResolver.Value] = [:]
        func number(_ id: String, _ value: Double) { live[id] = .number(value, display: String(Int(value.rounded()))) }
        let samples = heart ?? []
        if let last = samples.last, last.count == 2 { number("heart.rate", last[1]) }
        if !samples.isEmpty {
            // 20-minute averages from midnight.
            var bins: [Int: [Double]] = [:]
            for sample in samples where sample.count == 2 { bins[Int(sample[0] / 1200), default: []].append(sample[1]) }
            live["heart.today"] = .levels(bins.keys.sorted().compactMap { key in bins[key].map { $0.reduce(0, +) / Double($0.count) } })
        }
        if let rest = resting ?? samples.compactMap({ $0.count == 2 ? $0[1] : nil }).min() { number("heart.resting", rest) }
        if let variability { number("stress.level", Self.stress(variability)) }
        if let exerciseMinutes { number("activity.minutes", exerciseMinutes) }
        if let activeKcal { number("activity.kcal", activeKcal) }
        if let energy = Self.energy(sleepMinutes: sleepMinutes, exercise: exerciseMinutes, now: now, calendar: calendar) { number("energy.level", energy) }
        if let stages { live["sleep.stages"] = .levels(stages) }
        if let stepsHourly { live["steps.hourly"] = .levels(stepsHourly) }
        if let sleepMinutes {
            let total = Int(sleepMinutes.rounded())
            live["sleep.time"] = .text(String(format: "%d:%02d", total / 60, total % 60))
        }
        return live
    }

    /// Stress 0…100 from variability: 80 ms or more is calm (0), 20 ms or less is high (100). An estimate.
    public static func stress(_ variability: Double) -> Double { min(max((80 - variability) / 60 * 100, 0), 100) }

    /// Energy 0…100: last night's sleep against 8 hours, drained through the day and by exercise. An estimate.
    public static func energy(sleepMinutes: Double?, exercise: Double?, now: Date, calendar: Calendar) -> Double? {
        guard let sleepMinutes else { return nil }
        let rested = min(max(sleepMinutes / 480, 0), 1) * 100
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        let drain = min(max(hour - 7, 0), 16) / 16 * 35 + (exercise ?? 0) * 0.2
        return min(max(rested - drain, 5), 100)
    }
}

#if canImport(HealthKit) && os(iOS)
extension HealthReader {
    /// The types ADR-029 reads besides steps and sleep.
    static var extraTypes: Set<HKObjectType> {
        let ids: [HKQuantityTypeIdentifier] = [.heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .appleExerciseTime, .activeEnergyBurned]
        return Set(ids.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
    }

    /// Reads every extra the user allowed; a missing one stays nil.
    static func extras(now: Date, calendar: Calendar) async -> HealthExtras {
        var extras = HealthExtras()
        let midnight = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight
        let bpm = HKUnit.count().unitDivided(by: .minute())
        if let samples = try? await quantities(.heartRate, from: midnight, to: now, limit: 600, newestFirst: false) {
            extras.heart = samples.map { [$0.startDate.timeIntervalSince(midnight), $0.quantity.doubleValue(for: bpm)] }
        }
        extras.resting = try? await quantities(.restingHeartRate, from: yesterday, to: now, limit: 1, newestFirst: true).first?.quantity.doubleValue(for: bpm)
        extras.variability = try? await quantities(.heartRateVariabilitySDNN, from: yesterday, to: now, limit: 1, newestFirst: true).first?
            .quantity.doubleValue(for: .secondUnit(with: .milli))
        extras.exerciseMinutes = try? await sum(.appleExerciseTime, unit: .minute(), from: midnight, to: now)
        extras.activeKcal = try? await sum(.activeEnergyBurned, unit: .kilocalorie(), from: midnight, to: now)
        extras.stepsHourly = try? await hourlySteps(from: midnight, to: now)
        extras.stages = try? await stages(from: yesterday.addingTimeInterval(12 * 3600), to: now)
        return extras
    }

    static func quantities(_ id: HKQuantityTypeIdentifier, from start: Date, to end: Date, limit: Int, newestFirst: Bool) async throws -> [HKQuantitySample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: !newestFirst)]
        return try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sort) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples as? [HKQuantitySample] ?? []) }
            })
        }
    }

    static func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            store.execute(HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error, (error as? HKError)?.code != .errorNoData { continuation.resume(throwing: error) } else {
                    continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
                }
            })
        }
    }

    static func hourlySteps(from start: Date, to end: Date) async throws -> [Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum,
                                                    anchorDate: start, intervalComponents: DateComponents(hour: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                    return
                }
                var hours = [Double](repeating: 0, count: 24)
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let hour = Int(statistics.startDate.timeIntervalSince(start) / 3600)
                    if hours.indices.contains(hour) { hours[hour] = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0 }
                }
                continuation.resume(returning: hours)
            }
            store.execute(query)
        }
    }

    /// Last night's stages in 10-minute steps.
    static func stages(from start: Date, to end: Date) async throws -> [Double] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples as? [HKCategorySample] ?? []) }
            })
        }
        let stages = samples.filter { $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue }
        guard let first = stages.map(\.startDate).min(), let last = stages.map(\.endDate).max() else { return [] }
        var bins: [Double] = []
        var time = first
        while time < last && bins.count < 120 {
            let value = stages.first { $0.startDate <= time && time < $0.endDate }?.value
            switch value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue?: bins.append(0)
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue?: bins.append(2)
            case HKCategoryValueSleepAnalysis.awake.rawValue?, nil: bins.append(3)
            default: bins.append(1)
            }
            time = time.addingTimeInterval(600)
        }
        return bins
    }
}
#endif
