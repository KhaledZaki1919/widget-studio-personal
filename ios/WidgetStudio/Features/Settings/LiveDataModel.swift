import CoreLocation
import Observation
import UIKit
import WidgetKit
import WidgetKitCore

/// The app's real data for previews (ADR-016), from the same providers the widget uses: location,
/// Open-Meteo (same cache format), prayer times, HealthKit, battery, and the app's own counter and
/// stopwatch. It also owns the settings and records its own `SourceStatus` ("app-status").
@MainActor
@Observable
final class LiveDataModel: NSObject, CLLocationManagerDelegate {
    private(set) var inputs = LiveInputs()
    private(set) var status = SourceStatus()
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isRefreshing = false
    private(set) var settings = AppSettings()

    /// Saves changed settings and refreshes previews; with an App Group the widget reads them too.
    func update(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        try? next.save(cache)
        inputs.settings = next
        WidgetCenter.shared.reloadAllTimelines()
        Task { await refresh() }
    }

    static let appStatusName = "app-status"

    @ObservationIgnored private let cache = DataCache()
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var fixContinuation: CheckedContinuation<CLLocation?, Never>?
    @ObservationIgnored private var fixToken = UUID()

    override init() {
        super.init()
        let settings = AppSettings.load(cache)
        self.settings = settings
        inputs = LiveInputs(location: cache.read(StoredLocation.self, StoredLocation.cacheName),
                            weather: cache.read(WeatherReport.self, WeatherReport.cacheName),
                            counter: CounterState.load(cache), stopwatch: StopwatchState.load(cache), settings: settings)
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorization = manager.authorizationStatus
    }

    /// Real data for previews at `now` (missing sources stay empty: previews show "--"). App Store
    /// screenshots (`-uiTestingSampleData`) use the sample data, since the Simulator has no
    /// location or Health data.
    func snapshot(now: Date) -> DataSnapshot {
        if Self.usesSampleData { return .sample(now: now) }
        return LiveData.snapshot(inputs, now: now)
    }

    static let usesSampleData = ProcessInfo.processInfo.arguments.contains("-uiTestingSampleData")

    var isLocationAllowed: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
    }

    func requestHealth() async {
        try? await HealthReader.requestAuthorization()
        UserDefaults.standard.set(true, forKey: Self.healthAskedKey)
        healthAsked = true
        await refresh()
    }

    /// iOS never says whether Health *read* access was granted, only that we asked; whether steps
    /// can be read (`isHealthReadable`) is the real answer.
    private(set) var healthAsked = UserDefaults.standard.bool(forKey: LiveDataModel.healthAskedKey)
    static let healthAskedKey = "healthAsked"

    var isHealthReadable: Bool {
        if case .success? = inputs.health { return true }
        return false
    }

    /// Re-reads every source. Cheap when caches are fresh.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let now = Date.now
        var updates: [SourceStatus.Source: SourceStatus.Entry] = [:]
        inputs.counter = CounterState.load(cache)
        inputs.stopwatch = StopwatchState.load(cache)

        if isLocationAllowed, let fix = await oneFix() {
            let stored = await PlaceNames.store(fix, previous: inputs.location, now: now)
            try? cache.write(stored, StoredLocation.cacheName)
            inputs.location = stored
            updates[.location] = .init(ok: true, detail: "fix ±\(Int(fix.horizontalAccuracy)) m", updated: now, checked: now)
        } else {
            updates[.location] = .init(ok: inputs.location != nil, detail: isLocationAllowed ? "no fix" : "no permission",
                                       updated: inputs.location?.updated, checked: now)
        }

        if let location = inputs.location {
            updates[.prayer] = .init(ok: true, detail: "computed (\(settings.prayerMethod))", updated: now, checked: now)
            if let cached = inputs.weather,
               cached.isFresh(now: now, latitude: location.latitude, longitude: location.longitude, unit: settings.temperatureUnit) {
                updates[.weather] = .init(ok: true, detail: "cached", updated: cached.fetched, checked: now)
            } else {
                do {
                    let report = try await OpenMeteo.fetch(latitude: location.latitude, longitude: location.longitude,
                                                           unit: settings.temperatureUnit, now: now)
                    try? cache.write(report, WeatherReport.cacheName)
                    inputs.weather = report
                    updates[.weather] = .init(ok: true, detail: "fetched", updated: now, checked: now)
                } catch {
                    updates[.weather] = .init(ok: inputs.weather != nil, detail: "fetch failed", updated: inputs.weather?.fetched,
                                              checked: now)
                }
            }
        } else {
            updates[.prayer] = .init(ok: false, detail: "no location", updated: nil, checked: now)
            updates[.weather] = .init(ok: false, detail: "no location", updated: nil, checked: now)
        }

        let health = await HealthReader.read(now: now)
        inputs.health = health
        switch health {
        case .success(let summary):
            try? cache.write(summary, HealthSummary.cacheName)
            updates[.health] = .init(ok: true, detail: "read \(summary.steps.count) days", updated: now, checked: now)
        case .failure(let issue):
            updates[.health] = .init(ok: false, detail: issue.rawValue, updated: nil, checked: now)
        }

        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        inputs.battery = level >= 0 ? Double(level) : nil
        updates[.battery] = .init(ok: inputs.battery != nil, detail: inputs.battery.map { "\(Int($0 * 100))%" } ?? "unknown",
                                  updated: now, checked: now)
        updates[.counter] = .init(ok: true, detail: "\(inputs.counter.value) (app)", updated: inputs.counter.updated, checked: now)
        updates[.stopwatch] = .init(ok: true, detail: inputs.stopwatch.isRunning ? "running (app)" : "stopped (app)",
                                    updated: inputs.stopwatch.start, checked: now)

        SourceStatus.record(updates, cache: cache, name: Self.appStatusName)
        status = SourceStatus.load(cache: cache, name: Self.appStatusName) ?? SourceStatus(entries: updates)
    }

    /// The widget's own status: readable only when app and widget share a container (App Group).
    var widgetStatus: SourceStatus? {
        SourceStatus.load(cache: cache)
    }

    // MARK: Location

    private func oneFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            finishFix(nil)
            let token = UUID()
            fixToken = token
            fixContinuation = continuation
            manager.requestLocation()
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if self.fixToken == token { self.finishFix(nil) }
            }
        }
    }

    private func finishFix(_ location: CLLocation?) {
        fixContinuation?.resume(returning: location)
        fixContinuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finishFix(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishFix(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { await self.refresh() }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
