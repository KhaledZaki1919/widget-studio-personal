import Foundation

/// The data groups a spec reads (brief §4.5), so a widget knows what it must have before it can
/// draw real numbers (ADR-016).
public enum DataRequirements {
    public static func groups(for spec: WidgetSpec) -> Set<Bindings.Group> {
        var groups: Set<Bindings.Group> = spec.allLayers.contains { if case .forecastRow = $0.content { true } else { false } } ? [.weather] : []
        for name in bindingNames(in: spec) {
            if let parsed = Bindings.Name(name) { groups.insert(parsed.group) }
        }
        return groups
    }

    /// Whether the spec shows the Qibla direction (a tap then opens the live compass in the app).
    public static func showsQibla(_ spec: WidgetSpec) -> Bool {
        bindingNames(in: spec).contains { $0.hasPrefix("qibla.") }
    }

    /// Every binding name in the spec's layers.
    static func bindingNames(in spec: WidgetSpec) -> [String] {
        var strings: [String] = []
        for layer in spec.allLayers {
            strings += [layer.when, layer.rotation].compactMap { $0 }
            switch layer.content {
            case .text(let text):
                strings += text.value.allValues + [text.live?.target].compactMap { $0 }
                strings += (text.spans ?? []).flatMap(\.text.allValues)
            case .icon(let icon): strings.append(icon.symbol)
            case .dotGrid(let grid): strings.append(grid.values)
            case .dotBars(let bars): strings += [bars.values] + (bars.labels?.allValues ?? [])
            case .ring(let ring): strings.append(ring.progress)
            case .forecastRow: break
            case .analogClock(let clock): strings += [clock.timezone].compactMap { $0 }
            case .button(let button): strings += [button.arg].compactMap { $0 }
            case .list(let list):
                for item in list.items {
                    strings += item.title.allValues
                    strings += item.detail?.allValues ?? []
                    strings += item.subtitle?.allValues ?? []
                    strings += item.detail2?.allValues ?? []
                    if let done = item.done { strings.append(done) }
                }
            case .progressBar(let bar): strings.append(bar.progress)
            case .image(let image): strings.append(image.source)
            case .states(let states): strings += states.expanded.compactMap(\.when) + [states.value].compactMap { $0 }
            case .chart(let chart): strings.append(chart.values)
            case .shape(let shape): strings += [shape.progress].compactMap { $0 }
            case .calendarMonth, .stack, .spacer, .unknown: break
            }
        }
        return strings.flatMap(Bindings.names(in:))
    }
}

/// Why a data group has nothing real to show (the widget then shows a message).
public enum DataGap: String, Codable, Sendable {
    /// No location yet (permission or no fix): weather, prayer and coordinates need it.
    case noLocation
    /// Location known, but no weather could be fetched yet.
    case noWeather
    /// Steps and sleep can't be read here (`HealthIssue`).
    case noHealth
    case noBattery
    /// Reminders access isn't granted, and tasks live there on iOS.
    case noTasks
}

/// Everything real the renderer can use at one moment (ADR-016).
public struct LiveInputs: Sendable {
    public var location: StoredLocation?
    public var weather: WeatherReport?
    public var health: Result<HealthSummary, HealthIssue>?
    /// 0…1, nil when unknown.
    public var battery: Double?
    public var counter: CounterState
    public var stopwatch: StopwatchState
    public var timer: TimerState
    public var settings: AppSettings
    /// Catalog bindings read from the device (`DeviceData`, ADR-027).
    public var device = DeviceValues()

    public init(location: StoredLocation? = nil, weather: WeatherReport? = nil, health: Result<HealthSummary, HealthIssue>? = nil,
                battery: Double? = nil, counter: CounterState = CounterState(), stopwatch: StopwatchState = StopwatchState(),
                timer: TimerState = TimerState(), settings: AppSettings = AppSettings()) {
        self.location = location
        self.weather = weather
        self.health = health
        self.battery = battery
        self.counter = counter
        self.stopwatch = stopwatch
        self.timer = timer
        self.settings = settings
    }
}

public enum LiveData {
    /// Real data only: whatever is missing stays nil (renders "--" or triggers a `DataGap`).
    public static func snapshot(_ inputs: LiveInputs, now: Date, calendar: Calendar = .current) -> DataSnapshot {
        var data = DataSnapshot()
        let zone = calendar.timeZone
        if let location = inputs.location {
            data.latitude = location.latitude
            data.longitude = location.longitude
            data.altitude = location.altitude
            data.prayer = PrayerCalculator.prayer(latitude: location.latitude, longitude: location.longitude, date: now,
                                                  timeZone: zone, method: inputs.settings.prayerMethod)
            data.qiblaBearing = PrayerCalculator.qibla(latitude: location.latitude, longitude: location.longitude)
            data.place = location.city
        }
        data.live = inputs.device.live
        data.media = inputs.device.media
        data.timer = inputs.timer
        if let weather = inputs.weather {
            data.weather = weather.snapshot(now: now, city: inputs.location?.city)
            data.live.merge(weather.liveValues(now: now)) { _, new in new }
        }
        if case .success(let health)? = inputs.health {
            let goal = Double(inputs.settings.stepGoal)
            data.stepsToday = health.stepsToday(now: now, calendar: calendar)
            data.stepsStreak = Double(health.streak(now: now, goal: goal, calendar: calendar))
            data.stepsMonthGrid = health.monthLevels(now: now, goal: goal, calendar: calendar)
            data.stepsMonth = health.monthTotal(now: now, calendar: calendar)
            data.sleepLastNight = health.sleepLastNight(now: now, calendar: calendar).map(HealthSummary.duration(minutes:))
            data.sleepWeek = health.sleepWeek(now: now, calendar: calendar)
            if goal > 0 {
                let share = min(health.stepsToday(now: now, calendar: calendar) / goal, 1)
                data.live["steps.progress"] = .number(share, display: String(Int((share * 100).rounded())))
            }
            if let window = health.sleepWindow(now: now, calendar: calendar) {
                data.live["sleep.bedtime"] = .date(window.start)
                data.live["sleep.wake"] = .date(window.end)
            }
            // ADR-029: heart, stress, energy, activity, stages and steps per hour.
            let extras = health.extras ?? HealthExtras()
            data.live.merge(extras.values(now: now, calendar: calendar, sleepMinutes: health.sleepLastNight(now: now, calendar: calendar))) { _, new in new }
        }
        data.batteryLevel = inputs.battery
        data.counter = Double(inputs.counter.count(in: inputs.settings.dhikrList))
        data.dhikr = inputs.counter.dhikr(in: inputs.settings.dhikrList)
        data.stopwatchStart = inputs.stopwatch.start
        data.focusToday = HealthSummary.duration(minutes: inputs.stopwatch.minutes(on: now, now: now, calendar: calendar))
        data.focusWeek = inputs.stopwatch.week(now: now, calendar: calendar)
        return data
    }

    /// The first group the spec needs that has no real data, if any.
    public static func gap(for spec: WidgetSpec, _ inputs: LiveInputs) -> DataGap? {
        let groups = DataRequirements.groups(for: spec)
        if !groups.isDisjoint(with: [.weather, .prayer, .location]), inputs.location == nil { return .noLocation }
        if groups.contains(.weather), inputs.weather == nil { return .noWeather }
        if groups.contains(.health) {
            guard case .success? = inputs.health else { return .noHealth }
        }
        if groups.contains(.device), inputs.battery == nil { return .noBattery }
        if groups.contains(.tasks), inputs.device.noTasks { return .noTasks }
        return nil
    }
}
