import Foundation

/// Stock and coin prices for `{{stock.<tickerField>.*}}` (ADR-029): Yahoo Finance's public chart endpoint
/// (no key), cached for 15 minutes. Only the ticker leaves the phone. Twin of Markets in Extras.kt.
public enum MarketData {
    public static let cacheName = "markets"
    public static let maxAge: TimeInterval = 15 * 60

    public struct Quote: Codable, Sendable, Equatable {
        public var price: Double
        public var previous: Double?
        public var series: [Double]
        public var fetched: Date
    }

    static let coins = ["bitcoin": "BTC-USD", "btc": "BTC-USD", "ethereum": "ETH-USD", "eth": "ETH-USD", "solana": "SOL-USD", "sol": "SOL-USD"]

    /// The provider's symbol: TSLA, AMZN, BTC-USD; coin names map to their pair.
    public static func symbol(_ ticker: String) -> String {
        let key = ticker.trimmingCharacters(in: .whitespaces).lowercased()
        return coins[key] ?? key.uppercased()
    }

    /// The tickers a spec shows: the values of its ticker fields (lower-cased).
    public static func tickers(in spec: WidgetSpec, fieldValues: [String: LocalizedText] = [:]) -> [String] {
        spec.fields.filter { $0.type == .ticker }.compactMap { field in
            let value = (fieldValues[field.key] ?? field.default)?.resolved(language: "en").trimmingCharacters(in: .whitespaces).lowercased()
            return value?.isEmpty == false ? value : nil
        }
    }

    /// Fresh quotes for `tickers`, fetching what is missing or older than `maxAge`; the cache keeps the rest.
    public static func refresh(_ tickers: [String], cache: DataCache, now: Date = .now, session: URLSession = .shared) async -> [String: Quote] {
        var quotes = cache.read([String: Quote].self, cacheName) ?? [:]
        for ticker in Set(tickers) where quotes[ticker].map({ now.timeIntervalSince($0.fetched) > maxAge }) ?? true {
            if let quote = await fetch(ticker, now: now, session: session) { quotes[ticker] = quote }
        }
        try? cache.write(quotes, cacheName)
        return quotes
    }

    static func fetch(_ ticker: String, now: Date, session: URLSession) async -> Quote? {
        let encoded = symbol(ticker).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1mo&interval=1d") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("WidgetStudio", forHTTPHeaderField: "User-Agent")
        guard let result = try? await session.data(for: request) else { return nil }
        return parse(result.0, now: now)
    }

    /// One chart response → a quote (the last close as the previous price when the market is open).
    static func parse(_ data: Data, now: Date) -> Quote? {
        guard case .object(let root)? = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .array(let results)? = root["chart"]?["result"], case .object(let first)? = results.first,
              case .object(let meta)? = first["meta"] else { return nil }
        func number(_ value: JSONValue?) -> Double? {
            switch value {
            case .number(let number)?: number
            case .int(let number)?: Double(number)
            default: nil
            }
        }
        var series: [Double] = []
        if case .array(let quotes)? = first["indicators"]?["quote"], case .array(let closes)? = quotes.first?["close"] {
            series = closes.compactMap(number)
        }
        guard let price = number(meta["regularMarketPrice"]) ?? series.last else { return nil }
        let previous = series.count >= 2 ? series[series.count - 2] : number(meta["chartPreviousClose"])
        return Quote(price: price, previous: previous, series: series, fetched: now)
    }

    /// `stock.<ticker>.<part>` for every quote.
    public static func values(_ quotes: [String: Quote]) -> [String: BindingResolver.Value] {
        var live: [String: BindingResolver.Value] = [:]
        for (ticker, quote) in quotes {
            live["stock.\(ticker).price"] = .number(quote.price, display: String(format: "%.2f", quote.price))
            if let previous = quote.previous, previous != 0 {
                let change = quote.price - previous
                let percent = change / previous * 100
                live["stock.\(ticker).change"] = .number(change, display: (change >= 0 ? "+" : "") + String(format: "%.2f", change))
                live["stock.\(ticker).changePct"] = .number(percent, display: (percent >= 0 ? "+" : "") + String(format: "%.2f", percent))
            }
            live["stock.\(ticker).series"] = .levels(quote.series)
        }
        return live
    }
}
