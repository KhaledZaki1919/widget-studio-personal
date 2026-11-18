import Foundation

/// Turns bindings into values for one render (brief §4.5). Digits are always Latin, so they
/// suit the `dot` font and never mirror; weekday and month names follow the language.
public struct BindingResolver {
    public enum Value: Equatable, Sendable {
        case text(String)
        case number(Double, display: String)
        case levels([Double])
        case date(Date)

        public var display: String {
            switch self {
            case .text(let text): text
            case .number(_, let display): display
            case .levels(let levels): levels.map { String(format: "%.2f", $0) }.joined(separator: ",")
            case .date(let date): FormatterCache.date("HH:mm", locale: "en_US_POSIX", zone: .current).string(from: date)
            }
        }
    }

    public static let missing = "--"

    public let spec: WidgetSpec
    public let context: RenderContext

    public init(spec: WidgetSpec, context: RenderContext) {
        self.spec = spec
        self.context = context
    }

    /// `"{{weather.temp}}°"` → `"30°"`. Unknown or missing values render as "--".
    public func render(_ template: String) -> String {
        Bindings.tokenize(template).map { token in
            switch token {
            case .literal(let text): text
            case .binding(let name): value(of: name).map(display) ?? Self.missing
            }
        }.joined()
    }

    /// Text for a value; times show in the render's time zone (prayer times, stopwatch start).
    public func display(_ value: Value) -> String {
        if case .date(let date) = value {
            return FormatterCache.date(context.timePattern, locale: "en_US_POSIX", zone: context.timeZone).string(from: date)
        }
        return value.display
    }

    /// Resolves `text` when it is exactly one binding.
    public func soleValue(_ text: String) -> Value? {
        Bindings.soleBinding(text).flatMap(value(of:))
    }

    /// A number from a literal ("0.4") or a binding.
    public func number(_ text: String) -> Double? {
        if let value = Double(text.trimmingCharacters(in: .whitespaces)) { return value }
        if case .number(let value, _)? = soleValue(text) { return value }
        return nil
    }

    /// Levels from a binding, a "0.2,0.5" list or a "0110" dot pattern.
    public func levels(_ text: String) -> [Double] {
        if case .levels(let levels)? = soleValue(text) { return levels }
        return SpecLiterals.levels(text) ?? SpecLiterals.dotPattern(text) ?? []
    }

    /// `dotGrid` values: levels as above, or a number 0…1 that lights that share of the cells.
    public func gridLevels(_ text: String, cells: Int) -> [Double] {
        gridLevels(text, cells: cells, order: nil)
    }

    /// With `order` (ADR-029): a share lights the cells in that order (`DotGridLayout.order`); `cells` = rows × cols.
    func gridLevels(_ text: String, cells: Int, order: DotGridLayer.DotOrder?, columns: Int? = nil) -> [Double] {
        if case .number(let share, _)? = soleValue(text) {
            let lit = Int((min(max(share, 0), 1) * Double(cells)).rounded())
            guard let order, order != .rows, let columns, columns > 0 else { return (0..<max(cells, 0)).map { $0 < lit ? 1 : 0 } }
            var result = [Double](repeating: 0, count: max(cells, 0))
            for index in DotGridLayout.order(rows: cells / columns, cols: columns, order).prefix(lit) where result.indices.contains(index) {
                result[index] = 1
            }
            return result
        }
        return levels(text)
    }

    public func date(_ text: String) -> Date? {
        if case .date(let date)? = soleValue(text) { return date }
        return nil
    }

    /// A field's current value: the user's, else the spec's default.
    public func fieldValue(_ key: String) -> String? {
        (context.fieldValues[key] ?? spec.field(key)?.default)?.resolved(language: context.language)
    }

    public func value(of raw: String) -> Value? {
        guard let name = Bindings.Name(raw) else { return nil }
        if !context.overrides.isEmpty, let forced = overridden(raw.trimmingCharacters(in: .whitespaces)) { return forced }
        switch name {
        case .field(let key):
            guard let field = spec.field(key), let value = fieldValue(key) else { return nil }
            switch field.type {
            case .date: return FieldValues.date(value).map(Value.date)
            case .number: return Double(value).map { .number($0, display: value) }
            default: return .text(value)
            }
        case .timezoneTime(let key):
            guard let zone = fieldValue(key).flatMap(TimeZone.init(identifier:)) else { return nil }
            return .text(format(context.timePattern, zone: zone))
        case .daysUntil(let key):
            guard let target = fieldValue(key).flatMap(FieldValues.date) else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = context.timeZone
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: context.date),
                                               to: calendar.startOfDay(for: target)).day ?? 0
            return number(Double(max(days, 0)), digits: 0)
        case .builtin(let name):
            return builtin(name)
        case .appIcon:
            return nil
        case .stock(let key, let part):
            guard let ticker = fieldValue(key)?.trimmingCharacters(in: .whitespaces).lowercased(), !ticker.isEmpty else { return nil }
            return context.data.live["stock.\(ticker).\(part)"]
        }
    }

    /// Whether a layer's `when` holds (ADR-011, ADR-028). Unknown or missing values are falsy,
    /// so no comparison can pass on data that isn't there.
    public func isSatisfied(_ text: String) -> Bool {
        guard let expression = SpecExpression(text) else { return true }
        return expression.groups.contains { $0.allSatisfy(holds) }
    }

    private func holds(_ condition: SpecCondition) -> Bool {
        let value = value(of: condition.binding)
        switch condition.test {
        case .truthy: return Self.isTruthy(value)
        case .falsy: return !Self.isTruthy(value)
        case .equals(let expected): return value.map(display) == expected
        case .notEquals(let expected): return value.map(display).map { $0 != expected } ?? false
        case .anyOf(let items): return value.map(display).map { items.contains($0) } ?? false
        case .range(let low, let high): return Self.number(of: value).map { $0 >= low && $0 <= high } ?? false
        case .compare(let symbol, let target):
            guard let number = Self.number(of: value) else { return false }
            switch symbol {
            case ">=": return number >= target
            case "<=": return number <= target
            case ">": return number > target
            default: return number < target
            }
        }
    }

    static func number(of value: Value?) -> Double? {
        switch value {
        case .number(let number, _)?: number
        case .text(let text)?: Double(text)
        default: nil
        }
    }

    static func isTruthy(_ value: Value?) -> Bool {
        switch value {
        case .text(let text)?: !text.isEmpty && text != "0"
        case .number(let number, _)?: number != 0
        case .levels(let levels)?: !levels.isEmpty
        case .date?: true
        case nil: false
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func builtin(_ name: String) -> Value? {
        let data = context.data
        switch name {
        case "time.h": return .text(format("h"))
        // The big clock hour follows the 12/24-hour choice (M4 feedback); 12-hour has no leading zero.
        case "time.hh": return .text(format(context.uses24Hour == false ? "h" : "HH"))
        case "time.mm": return .text(format("mm"))
        case "time.ampm": return .text(localizedFormat("a"))
        case "time.ss": return .text(format("ss"))
        case "time.words":
            let parts = gregorian.dateComponents([.hour, .minute], from: context.date)
            return .text(TimeWords.words(hour: parts.hour ?? 0, minute: parts.minute ?? 0, arabic: context.isArabic))
        case "date.EE":
            let short = localizedFormat("EEE")
            return .text(context.isArabic ? short : String(short.prefix(2)))
        case "weather.rainChance":
            if let hours = upcoming, !hours.isEmpty { return number(hours.prefix(3).map(\.rainChance).max() ?? 0, digits: 0) }
            return data.live[name]
        case "weather.rainNext":
            if let hours = upcoming, !hours.isEmpty { return .text(TimeWords.rainNext(hours, context: context)) }
            return data.live[name]
        case "weather.uv": return data.weather?.uv.map { number($0, digits: 0) } ?? data.live[name]
        case "weather.aqi": return data.weather?.aqi.map { number($0, digits: 0) } ?? data.live[name]
        case "hourly.temps":
            if let hours = upcoming, !hours.isEmpty { return .levels(hours.prefix(24).map(\.temperature)) }
            return data.live[name]
        case "date.d": return .text(format("d"))
        case "date.EEEE": return .text(localizedFormat("EEEE"))
        case "date.MMM": return .text(localizedFormat("MMM"))
        case "date.dd": return .text(format("dd"))
        case "date.EEE": return .text(localizedFormat("EEE"))
        case "date.MMMM": return .text(localizedFormat("MMMM"))
        case "date.M": return .text(format("M"))
        case "date.yyyy": return .text(format("yyyy"))
        case "date.hijri": return .text(hijriDate())
        case "tz.offset": return .text(Self.offset(context.timeZone, at: context.date))
        case "year.progress": return progress(.year)
        case "month.progress": return progress(.month)
        case "week.progress": return progress(.weekOfYear)
        case "day.progress": return progress(.day)
        case "year.day": return period(.year).map { number(Double(wholeDays(from: $0.start, to: context.date) + 1), digits: 0) }
        case "year.daysLeft": return daysLeft(.year)
        case "month.daysLeft": return daysLeft(.month)
        case "week.daysLeft": return daysLeft(.weekOfYear)
        case "time.isDay": return .text(isDay ? "1" : "0")
        case "weather.temp": return data.weather.map { number($0.temperature, digits: 0) }
        case "weather.hi": return data.weather.map { number($0.high, digits: 0) }
        case "weather.lo": return data.weather.map { number($0.low, digits: 0) }
        case "weather.cond": return data.weather.map { .text($0.condition.resolved(language: context.language)) }
        case "weather.symbol": return data.weather.map { .text($0.symbol) }
        case "weather.kind": return data.weather.map { .text(WeatherKind.of(symbol: $0.symbol)) }
        case "weather.city":
            return data.weather.map { .text(fieldValueOfType(.city) ?? $0.city.resolved(language: context.language)) }
        case "steps.today": return data.stepsToday.map { number($0, digits: 0, grouped: true) }
        case "steps.streak": return data.stepsStreak.map { number($0, digits: 0) }
        case "steps.monthGrid": return data.stepsMonthGrid.map(Value.levels)
        case "steps.month": return data.stepsMonth.map { number($0, digits: 0, grouped: true) }
        case "sleep.lastNight": return data.sleepLastNight.map { .text($0.resolved(language: context.language)) }
        case "sleep.week": return data.sleepWeek.map(Value.levels)
        case "counter.value": return data.counter.map { number($0, digits: 0) }
        case "counter.dhikr": return data.dhikr.map(Value.text)
        case "counter.progress":
            guard let count = data.counter, let target = fieldValue("target").flatMap(Double.init), target > 0 else { return nil }
            return number(min(count / target, 1), digits: 2)
        case "stopwatch.running": return .text(data.stopwatchStart == nil ? "0" : "1")
        case "stopwatch.start": return data.stopwatchStart.map(Value.date)
        case "focus.today": return data.focusToday.map { .text($0.resolved(language: context.language)) }
        case "focus.week": return data.focusWeek.map(Value.levels)
        case "prayer.next.name": return data.prayer.map { .text($0.nextName.resolved(language: context.language)) }
        case "prayer.next.time": return data.prayer.map { .date($0.nextTime) }
        case "prayer.next.key": return data.prayer.map { .text($0.nextKey) }
        case "qibla.bearing": return data.qiblaBearing.map { number($0, digits: 0) }
        case "location.city": return data.place.map { .text($0.resolved(language: context.language)) } ?? data.live[name]
        case "location.lat": return data.latitude.map { number($0, digits: 2) }
        case "location.lon": return data.longitude.map { number($0, digits: 2) }
        case "location.alt": return data.altitude.map { number($0, digits: 0) }
        case "battery.level": return data.batteryLevel.map { .number($0, display: String(Int(($0 * 100).rounded()))) }
        case "media.playing", "media.symbol", "media.elapsed", "media.duration", "media.remaining", "media.progress":
            return data.media.map { media(name, $0) } ?? data.live[name]
        case "timer.running", "timer.remaining", "timer.progress", "timer.end":
            return data.timer.flatMap { timer(name, $0) } ?? data.live[name]
        default:
            if name.hasPrefix("forecast.") { return forecast(name) }
            if name.hasPrefix("hourly.") || name.hasPrefix("week.d"), let value = indexed(name) { return value }
            if let value = data.live[name] { return value }
            if name.hasPrefix("prayer."), let time = data.prayer?.times[String(name.dropFirst("prayer.".count))] {
                return .date(time)
            }
            return nil
        }
    }

    // MARK: Hours and week days (ADR-029)

    /// The hours from the current one on.
    private var upcoming: [DataSnapshot.HourForecast]? {
        context.data.weather?.hourly.filter { $0.date.addingTimeInterval(3600) > context.date }
    }

    /// `hourly.N.time|symbol|temp` (hour 1 is the next full hour) and `week.dN.EEE|d|isToday`.
    private func indexed(_ name: String) -> Value? {
        let parts = name.split(separator: ".").map(String.init)
        guard parts.count == 3 else { return nil }
        if parts[0] == "hourly" {
            guard let n = Int(parts[1]) else { return nil }
            guard let hours = upcoming, !hours.isEmpty else { return context.data.live[name] }
            let next = hours.filter { $0.date > context.date }
            guard next.indices.contains(n - 1) else { return nil }
            let hour = next[n - 1]
            switch parts[2] {
            case "time":
                let pattern = context.uses24Hour == false ? "h a" : "HH:mm"
                return .text(FormatterCache.date(pattern, locale: context.localeIdentifier, zone: context.timeZone).string(from: hour.date))
            case "symbol": return .text(hour.symbol)
            case "temp": return number(hour.temperature, digits: 0)
            default: return nil
            }
        }
        if parts[0] == "week", parts[1].hasPrefix("d"), let n = Int(parts[1].dropFirst()), (1...7).contains(n) {
            let calendar = gregorian
            let today = calendar.startOfDay(for: context.date)
            let offset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
            guard let day = calendar.date(byAdding: .day, value: n - 1 - offset, to: today) else { return nil }
            switch parts[2] {
            case "EEE": return .text(FormatterCache.date("EEE", locale: context.localeIdentifier, zone: context.timeZone).string(from: day))
            case "d": return .text(String(calendar.component(.day, from: day)))
            case "isToday": return .text(calendar.isDate(day, inSameDayAs: today) ? "1" : "0")
            default: return nil
            }
        }
        return nil
    }

    // MARK: Time as a share (ADR-028)

    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    private func period(_ unit: Calendar.Component) -> DateInterval? {
        gregorian.dateInterval(of: unit, for: context.date)
    }

    private func wholeDays(from start: Date, to end: Date) -> Int {
        let calendar = gregorian
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// Share of the period gone: value 0…1, whole percent in text, like `battery.level`.
    private func progress(_ unit: Calendar.Component) -> Value? {
        period(unit).map { interval in
            let share = min(max(context.date.timeIntervalSince(interval.start) / max(interval.duration, 1), 0), 1)
            return .number(share, display: String(Int((share * 100).rounded())))
        }
    }

    /// Days after today in the period.
    private func daysLeft(_ unit: Calendar.Component) -> Value? {
        period(unit).map { number(Double(max(wholeDays(from: context.date, to: $0.end) - 1, 0)), digits: 0) }
    }

    /// Between today's sunrise and sunset when the weather gave them, else 6:00 to 18:00.
    private var isDay: Bool {
        let calendar = gregorian
        func minutes(_ date: Date) -> Int {
            calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        }
        let now = minutes(context.date)
        if case .date(let rise)? = context.data.live["weather.sunrise"], case .date(let set)? = context.data.live["weather.sunset"] {
            return now >= minutes(rise) && now < minutes(set)
        }
        return now >= 6 * 60 && now < 18 * 60
    }

    /// `forecast.<day>.<part>`: day 1 is tomorrow.
    private func forecast(_ name: String) -> Value? {
        let parts = name.split(separator: ".")
        guard parts.count == 3, let day = Int(parts[1]), let days = context.data.weather?.forecast, days.indices.contains(day) else { return nil }
        let item = days[day]
        switch parts[2] {
        case "symbol": return .text(item.symbol)
        case "hi": return number(item.high, digits: 0)
        case "lo": return number(item.low, digits: 0)
        default: return .text(FormatterCache.date("EEE", locale: context.localeIdentifier, zone: context.timeZone).string(from: item.date))
        }
    }

    /// Playback values at this entry's date, so they move along a timeline (ADR-027).
    private func media(_ name: String, _ playback: MediaPlayback) -> Value {
        let position = playback.position(at: context.date)
        switch name {
        case "media.playing": return .text(playback.playing ? "1" : "0")
        case "media.symbol": return .text(playback.playing ? "pause.fill" : "play.fill")
        case "media.elapsed": return .text(MediaPlayback.clock(position))
        case "media.duration": return .text(MediaPlayback.clock(playback.duration))
        case "media.remaining": return .text("-" + MediaPlayback.clock(playback.duration - position))
        default:
            let share = playback.duration > 0 ? min(position / playback.duration, 1) : 0
            return .number(share, display: String(Int((share * 100).rounded())))
        }
    }

    private func timer(_ name: String, _ timer: TimerState) -> Value? {
        switch name {
        case "timer.running": return .text(timer.isRunning(at: context.date) ? "1" : "0")
        case "timer.remaining": return .text(MediaPlayback.clock(timer.remaining(at: context.date)))
        case "timer.end": return timer.end.map(Value.date)
        default:
            let share = timer.progress(at: context.date)
            return .number(share, display: String(Int((share * 100).rounded())))
        }
    }

    /// "23 Jumada I 1448" in the render language, digits Latin (Umm al-Qura).
    private func hijriDate() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .islamicUmmAlQura)
        formatter.locale = Locale(identifier: context.localeIdentifier)
        formatter.timeZone = context.timeZone
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: context.date)
    }

    private func fieldValueOfType(_ type: FieldSpec.Kind) -> String? {
        spec.fields.first { $0.type == type }.flatMap { fieldValue($0.key) }
    }

    private func number(_ value: Double, digits: Int, grouped: Bool = false) -> Value {
        let formatter = FormatterCache.number(digits: digits, grouped: grouped)
        return .number(value, display: formatter.string(from: NSNumber(value: value)) ?? String(value))
    }

    /// Fixed-format, Latin digits.
    private func format(_ pattern: String, zone: TimeZone? = nil) -> String {
        FormatterCache.date(pattern, locale: "en_US_POSIX", zone: zone ?? context.timeZone).string(from: context.date)
    }

    /// Words in the render language, digits Latin (`ar@numbers=latn`).
    private func localizedFormat(_ pattern: String) -> String {
        FormatterCache.date(pattern, locale: context.localeIdentifier, zone: context.timeZone).string(from: context.date)
    }

    /// "GMT+2", "GMT-3:30", "GMT".
    static func offset(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        guard seconds != 0 else { return "GMT" }
        let sign = seconds > 0 ? "+" : "-"
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) % 3600 / 60
        return minutes == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }
}

/// Formatters are expensive to create and a widget renders up to 60 entries per timeline, so
/// they are created once per pattern, locale and time zone.
enum FormatterCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var dates: [String: DateFormatter] = [:]
    nonisolated(unsafe) private static var numbers: [String: NumberFormatter] = [:]

    static func date(_ pattern: String, locale: String, zone: TimeZone) -> DateFormatter {
        let key = "\(pattern)|\(locale)|\(zone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let formatter = dates[key] { return formatter }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        dates[key] = formatter
        return formatter
    }

    static func number(digits: Int, grouped: Bool) -> NumberFormatter {
        let key = "\(digits)|\(grouped)"
        lock.lock()
        defer { lock.unlock() }
        if let formatter = numbers[key] { return formatter }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouped
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        numbers[key] = formatter
        return formatter
    }
}
