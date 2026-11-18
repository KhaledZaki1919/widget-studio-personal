import Foundation

/// A weather report from Open-Meteo (no API key; brief §2), as cached (ADR-016).
public struct WeatherReport: Codable, Sendable, Equatable {
    public struct Day: Codable, Sendable, Equatable {
        /// "yyyy-MM-dd" in the report's time zone.
        public var date: String
        public var code: Int
        public var high: Double
        public var low: Double
    }

    public var fetched: Date
    public var latitude: Double
    public var longitude: Double
    public var unit: AppSettings.TemperatureUnit
    public var timeZone: String
    public var temperature: Double
    public var code: Int
    public var isDay: Bool
    public var days: [Day]
    /// Optional: reports cached before ADR-027 don't have them.
    public var humidity: Double?
    public var wind: Double?
    public var feelsLike: Double?
    /// Local "yyyy-MM-ddTHH:mm" per day, in `timeZone`.
    public var sunrise: [String]?
    public var sunset: [String]?
    /// ADR-029: the next hours, the UV index and the air quality (optional: older caches lack them).
    public var hours: [Hour]?
    public var uv: Double?
    public var aqi: Double?

    public struct Hour: Codable, Sendable, Equatable {
        /// Local "yyyy-MM-ddTHH:mm" in `timeZone`.
        public var time: String
        public var code: Int
        public var temperature: Double
        public var rainChance: Double
        public var rain: Double
        public var isDay: Bool
    }

    public static let cacheName = "weather"
    /// Hourly refresh (brief §4.5); a little early so the hourly timeline reload fetches.
    public static let maxAge: TimeInterval = 55 * 60

    /// Fresh enough for `now` at this place and unit (moved less than 5 km).
    public func isFresh(now: Date, latitude lat: Double, longitude lon: Double, unit wanted: AppSettings.TemperatureUnit) -> Bool {
        let place = StoredLocation(latitude: latitude, longitude: longitude, altitude: nil, updated: fetched)
        return now.timeIntervalSince(fetched) < Self.maxAge && now >= fetched && unit == wanted
            && place.distance(toLatitude: lat, longitude: lon) < 5
    }

    /// The extra values as catalog bindings (ADR-027).
    public func liveValues(now: Date) -> [String: BindingResolver.Value] {
        var live: [String: BindingResolver.Value] = [:]
        func number(_ value: Double?, _ id: String) {
            if let value { live[id] = .number(value, display: String(Int(value.rounded()))) }
        }
        number(humidity, "weather.humidity")
        number(wind, "weather.wind")
        number(feelsLike, "weather.feels")
        let zone = TimeZone(identifier: timeZone) ?? .current
        let today = FormatterCache.date("yyyy-MM-dd", locale: "en_US_POSIX", zone: zone).string(from: now)
        let parser = FormatterCache.date("yyyy-MM-dd'T'HH:mm", locale: "en_US_POSIX", zone: zone)
        if let text = sunrise?.first(where: { $0.hasPrefix(today) }), let date = parser.date(from: text) { live["weather.sunrise"] = .date(date) }
        if let text = sunset?.first(where: { $0.hasPrefix(today) }), let date = parser.date(from: text) { live["weather.sunset"] = .date(date) }
        return live
    }

    /// The renderer's weather: today's high/low and the days from today on.
    public func snapshot(now: Date, city: LocalizedText?) -> DataSnapshot.Weather {
        let zone = TimeZone(identifier: timeZone) ?? .current
        let today = FormatterCache.date("yyyy-MM-dd", locale: "en_US_POSIX", zone: zone).string(from: now)
        let upcoming = days.filter { $0.date >= today }
        let first = upcoming.first ?? days.last
        let condition = WeatherCode.describe(code, isDay: isDay)
        let parser = FormatterCache.date("yyyy-MM-dd'T'HH:mm", locale: "en_US_POSIX", zone: zone)
        var weather = DataSnapshot.Weather(
            temperature: temperature, high: first?.high ?? temperature, low: first?.low ?? temperature,
            condition: condition.text, symbol: condition.symbol, city: city ?? .plain(""),
            forecast: upcoming.compactMap { day in
                guard let date = FormatterCache.date("yyyy-MM-dd", locale: "en_US_POSIX", zone: zone).date(from: day.date) else {
                    return nil
                }
                return DataSnapshot.DayForecast(date: date, symbol: WeatherCode.describe(day.code, isDay: true).symbol,
                                                high: day.high, low: day.low)
            }
        )
        weather.hourly = (hours ?? []).compactMap { hour in
            parser.date(from: hour.time).map {
                DataSnapshot.HourForecast(date: $0, symbol: WeatherCode.describe(hour.code, isDay: hour.isDay).symbol,
                                          temperature: hour.temperature, rainChance: hour.rainChance, rain: hour.rain)
            }
        }
        weather.uv = uv
        weather.aqi = aqi
        return weather
    }
}

/// Open-Meteo forecast API: current temperature and code, 7 days of code, high and low.
public enum OpenMeteo {
    public static func url(latitude: Double, longitude: Double, unit: AppSettings.TemperatureUnit) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day,relative_humidity_2m,apparent_temperature,wind_speed_10m,uv_index"),
            // ADR-029: the next hours (icons, temperatures, rain).
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,precipitation,is_day"),
            URLQueryItem(name: "forecast_hours", value: "30"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
        ]
        return components?.url
    }

    public enum Failure: Error, Equatable {
        case badURL
        case http(Int)
        case unreadable
    }

    struct Response: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let weatherCode: Int
            let isDay: Int?
            let humidity: Double?
            let feelsLike: Double?
            let wind: Double?
            let uv: Double?

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m", weatherCode = "weather_code", isDay = "is_day",
                     humidity = "relative_humidity_2m", feelsLike = "apparent_temperature", wind = "wind_speed_10m", uv = "uv_index"
            }
        }

        struct Hourly: Decodable {
            let time: [String]
            let temperature: [Double?]
            let weatherCode: [Int?]
            let rainChance: [Double?]?
            let rain: [Double?]?
            let isDay: [Int?]?

            enum CodingKeys: String, CodingKey {
                case time, temperature = "temperature_2m", weatherCode = "weather_code", rainChance = "precipitation_probability",
                     rain = "precipitation", isDay = "is_day"
            }
        }

        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int]
            let high: [Double?]
            let low: [Double?]
            let sunrise: [String]?
            let sunset: [String]?

            enum CodingKeys: String, CodingKey {
                case time, weatherCode = "weather_code", high = "temperature_2m_max", low = "temperature_2m_min", sunrise, sunset
            }
        }

        let timezone: String?
        let current: Current
        let daily: Daily
        let hourly: Hourly?
    }

    public static func parse(_ data: Data, fetched: Date, latitude: Double, longitude: Double,
                             unit: AppSettings.TemperatureUnit) throws -> WeatherReport {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw Failure.unreadable }
        let daily = response.daily
        let count = min(daily.time.count, daily.weatherCode.count, daily.high.count, daily.low.count)
        let days = (0..<count).compactMap { index -> WeatherReport.Day? in
            guard let high = daily.high[index], let low = daily.low[index] else { return nil }
            return WeatherReport.Day(date: daily.time[index], code: daily.weatherCode[index], high: high, low: low)
        }
        var report = WeatherReport(
            fetched: fetched, latitude: latitude, longitude: longitude, unit: unit,
            timeZone: response.timezone ?? TimeZone.current.identifier,
            temperature: response.current.temperature, code: response.current.weatherCode,
            isDay: (response.current.isDay ?? 1) == 1, days: days, humidity: response.current.humidity, wind: response.current.wind,
            feelsLike: response.current.feelsLike, sunrise: daily.sunrise, sunset: daily.sunset
        )
        report.uv = response.current.uv
        if let hourly = response.hourly {
            report.hours = hourly.time.indices.compactMap { index -> WeatherReport.Hour? in
                guard index < hourly.temperature.count, let temperature = hourly.temperature[index],
                      index < hourly.weatherCode.count, let code = hourly.weatherCode[index] else { return nil }
                return WeatherReport.Hour(time: hourly.time[index], code: code, temperature: temperature,
                                          rainChance: hourly.rainChance?[safe: index].flatMap { $0 } ?? 0,
                                          rain: hourly.rain?[safe: index].flatMap { $0 } ?? 0,
                                          isDay: (hourly.isDay?[safe: index].flatMap { $0 } ?? 1) == 1)
            }
        }
        return report
    }

    /// The current European AQI (Open-Meteo air quality, no key), or nil.
    public static func airQuality(latitude: Double, longitude: Double, session: URLSession = .shared) async -> Double? {
        let text = String(format: "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=%.2f&longitude=%.2f&current=european_aqi",
                          latitude, longitude)
        guard let url = URL(string: text), let result = try? await session.data(from: url),
              case .object(let root)? = try? JSONDecoder().decode(JSONValue.self, from: result.0),
              case .object(let current)? = root["current"] else { return nil }
        switch current["european_aqi"] {
        case .int(let value)?: return Double(value)
        case .number(let value)?: return value
        default: return nil
        }
    }

    /// Downloads a report (15 s timeout: a widget timeline has little time).
    public static func fetch(latitude: Double, longitude: Double, unit: AppSettings.TemperatureUnit,
                             session: URLSession = .shared, now: Date = .now) async throws -> WeatherReport {
        guard let url = url(latitude: latitude, longitude: longitude, unit: unit) else { throw Failure.badURL }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("WidgetStudio/1.0 (iOS widget)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.http(http.statusCode) }
        var report = try parse(data, fetched: now, latitude: latitude, longitude: longitude, unit: unit)
        report.aqi = await airQuality(latitude: latitude, longitude: longitude, session: session)
        return report
    }
}

/// WMO weather interpretation codes (Open-Meteo) → whitelisted SF Symbol and ar/en text.
public enum WeatherCode {
    public static func describe(_ code: Int, isDay: Bool) -> (symbol: String, text: LocalizedText) {
        switch code {
        case 0: return (isDay ? "sun.max.fill" : "moon.fill", .localized(en: "Clear", ar: "صافٍ"))
        case 1: return (isDay ? "sun.max.fill" : "moon.stars.fill", .localized(en: "Mainly clear", ar: "صافٍ غالبًا"))
        case 2: return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", .localized(en: "Partly cloudy", ar: "غائم جزئيًا"))
        case 3: return ("cloud.fill", .localized(en: "Overcast", ar: "غائم"))
        case 45, 48: return ("cloud.fog.fill", .localized(en: "Fog", ar: "ضباب"))
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", .localized(en: "Drizzle", ar: "رذاذ"))
        case 61, 63, 66, 80, 81: return ("cloud.rain.fill", .localized(en: "Rain", ar: "مطر"))
        case 65, 67, 82: return ("cloud.heavyrain.fill", .localized(en: "Heavy rain", ar: "مطر غزير"))
        case 71, 73, 75, 77, 85, 86: return ("cloud.snow.fill", .localized(en: "Snow", ar: "ثلج"))
        case 95, 96, 99: return ("cloud.bolt.rain.fill", .localized(en: "Thunderstorm", ar: "عاصفة رعدية"))
        default: return ("cloud.fill", .localized(en: "Cloudy", ar: "غائم"))
        }
    }
}

extension Array {
    /// The element at `index`, or nil past the end.
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
