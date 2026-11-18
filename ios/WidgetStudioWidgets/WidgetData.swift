import CoreLocation
import Foundation
import WidgetKitCore

/// The widget extension's own data pipeline (ADR-016): without an App Group nothing comes from
/// the app, so each timeline gets what its template needs. Location from a fix of its own
/// (cached, with the city name), weather from Open-Meteo (cached, hourly), steps and sleep from
/// HealthKit, battery from the device, counter and stopwatch from its own files. Every source's
/// outcome goes to `SourceStatus` (the large check widget shows it) and to `WidgetLog`.
enum WidgetData {
    /// Inputs for a spec that reads `groups`, fetching what's missing or stale.
    static func inputs(for groups: Set<Bindings.Group>, tickers: [String] = [], now: Date = .now) async -> LiveInputs {
        let cache = DataCache()
        let settings = AppSettings.load(cache)
        var inputs = LiveInputs(counter: CounterState.load(cache), stopwatch: StopwatchState.load(cache), timer: TimerState.load(cache),
                                settings: settings)
        var status: [SourceStatus.Source: SourceStatus.Entry] = [:]

        if !groups.isDisjoint(with: [.weather, .prayer, .location]) {
            let (location, entry) = await location(cache: cache, now: now)
            inputs.location = location
            status[.location] = entry
            if groups.contains(.prayer) {
                status[.prayer] = location == nil
                    ? .init(ok: false, detail: "no location", updated: nil, checked: now)
                    : .init(ok: true, detail: "computed (\(settings.prayerMethod))", updated: now, checked: now)
            }
        }
        if groups.contains(.weather), let location = inputs.location {
            let (weather, entry) = await weather(at: location, unit: settings.temperatureUnit, cache: cache, now: now)
            inputs.weather = weather
            status[.weather] = entry
        } else if groups.contains(.weather) {
            status[.weather] = .init(ok: false, detail: "no location", updated: nil, checked: now)
        }
        if groups.contains(.health) {
            let (health, entry) = await health(cache: cache, now: now)
            inputs.health = health
            status[.health] = entry
        }
        if groups.contains(.device) {
            inputs.battery = await WidgetProbes.batteryLevel()
            status[.battery] = .init(ok: inputs.battery != nil, detail: inputs.battery.map { "\(Int($0 * 100))%" } ?? "unknown",
                                     updated: now, checked: now)
        }
        // Media, volume, system switches, calendar, reminders, charging (ADR-027).
        inputs.device = await DeviceData.read(groups: groups, language: RenderContext.preferredLanguage, now: now)
        // ADR-029: prices of the spec's ticker fields.
        if !tickers.isEmpty {
            inputs.device.live.merge(MarketData.values(await MarketData.refresh(tickers, cache: cache, now: now))) { _, new in new }
        }
        if groups.contains(.app) {
            status[.counter] = .init(ok: true, detail: "\(inputs.counter.value)", updated: inputs.counter.updated, checked: now)
            status[.stopwatch] = .init(ok: true, detail: inputs.stopwatch.isRunning ? "running" : "stopped",
                                       updated: inputs.stopwatch.start ?? inputs.stopwatch.sessions.last?.end, checked: now)
        }
        SourceStatus.record(status, cache: cache)
        WidgetLog.add("data " + status.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value.ok ? "ok" : "no"):\($0.value.detail)" }.joined(separator: " "))
        return inputs
    }

    /// What's cached, without fixes or downloads (gallery previews must answer fast).
    static func cachedInputs() -> LiveInputs {
        let cache = DataCache()
        let health = cache.read(HealthSummary.self, HealthSummary.cacheName)
        return LiveInputs(location: cache.read(StoredLocation.self, StoredLocation.cacheName),
                          weather: cache.read(WeatherReport.self, WeatherReport.cacheName),
                          health: health.map { .success($0) }, counter: CounterState.load(cache),
                          stopwatch: StopwatchState.load(cache), timer: TimerState.load(cache), settings: AppSettings.load(cache))
    }

    // MARK: Sources

    static func location(cache: DataCache, now: Date) async -> (StoredLocation?, SourceStatus.Entry) {
        let cached = cache.read(StoredLocation.self, StoredLocation.cacheName)
        let (authorized, fix) = await WidgetProbes.fix()
        guard let fix else {
            if let cached {
                let detail = authorized ? "no fix, cached" : "not authorized for widget, cached"
                return (cached, .init(ok: true, detail: detail, updated: cached.updated, checked: now))
            }
            return (nil, .init(ok: false, detail: authorized ? "no fix" : "not authorized for widget", updated: nil, checked: now))
        }
        let location = await PlaceNames.store(fix, previous: cached, now: now)
        try? cache.write(location, StoredLocation.cacheName)
        return (location, .init(ok: true, detail: "fix ±\(Int(fix.horizontalAccuracy)) m", updated: now, checked: now))
    }

    static func weather(at location: StoredLocation, unit: AppSettings.TemperatureUnit, cache: DataCache,
                        now: Date) async -> (WeatherReport?, SourceStatus.Entry) {
        let cached = cache.read(WeatherReport.self, WeatherReport.cacheName)
        if let cached, cached.isFresh(now: now, latitude: location.latitude, longitude: location.longitude, unit: unit) {
            return (cached, .init(ok: true, detail: "cached \(Int(now.timeIntervalSince(cached.fetched) / 60)) min",
                                  updated: cached.fetched, checked: now))
        }
        do {
            let report = try await OpenMeteo.fetch(latitude: location.latitude, longitude: location.longitude, unit: unit, now: now)
            try? cache.write(report, WeatherReport.cacheName)
            return (report, .init(ok: true, detail: "fetched", updated: now, checked: now))
        } catch {
            // A stale report (same unit, under 6 h) beats nothing while offline.
            if let cached, cached.unit == unit, now.timeIntervalSince(cached.fetched) < 6 * 3600 {
                return (cached, .init(ok: true, detail: "fetch failed, cached", updated: cached.fetched, checked: now))
            }
            return (nil, .init(ok: false, detail: "fetch failed: \(error.localizedDescription)", updated: cached?.fetched, checked: now))
        }
    }

    static func health(cache: DataCache, now: Date) async -> (Result<HealthSummary, HealthIssue>, SourceStatus.Entry) {
        let result = await HealthReader.read(now: now)
        switch result {
        case .success(let summary):
            try? cache.write(summary, HealthSummary.cacheName)
            return (result, .init(ok: true, detail: "read \(summary.steps.count) days", updated: now, checked: now))
        case .failure(let issue):
            // Locked devices can't read HealthKit; a recent copy (under 3 h) is still real data.
            if issue == .error, let cached = cache.read(HealthSummary.self, HealthSummary.cacheName),
               now.timeIntervalSince(cached.fetched) < 3 * 3600 {
                return (.success(cached), .init(ok: true, detail: "read failed, cached", updated: cached.fetched, checked: now))
            }
            return (result, .init(ok: false, detail: issue.rawValue, updated: nil, checked: now))
        }
    }
}
