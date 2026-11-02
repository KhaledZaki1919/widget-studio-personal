import Foundation

/// What happened on the last AI request, for Settings → AI → "Last AI request". Stored locally,
/// never sent anywhere. Holds no key (redacted), no image and no user text; error bodies and
/// reply excerpts come from the provider.
public struct AIDiagnostic: Codable, Equatable, Sendable {
    public enum Step: String, Codable, Sendable, CaseIterable {
        /// No HTTP response (offline, DNS, TLS, timeout).
        case network
        /// The provider answered with an error status.
        case http
        /// 2xx, but the provider's envelope was unusable (empty, truncated, blocked).
        case response
        /// The model's text wasn't the JSON we asked for.
        case json
        /// Valid JSON that failed validation.
        case validation
        /// No answer before the app's hard deadline (`AIDeadline`).
        case timeout
        case cancelled
    }

    public var date: Date
    public var provider: AIProviderKind
    public var model: String
    public var feature: AIFeature
    /// Without query string; keys are sent in headers, never in URLs.
    public var endpoint: String?
    public var httpStatus: Int?
    /// nil when the request succeeded.
    public var failedStep: Step?
    /// Provider calls made (2 = the one retry after an invalid answer, or a resend without an
    /// unsupported option).
    public var attempts: Int
    public var durationMs: Int
    /// The provider's own error text, the network error, or what was wrong with the reply.
    public var message: String?
    /// Raw provider body for errors, key redacted, truncated.
    public var errorBody: String?
    /// Start of the model's reply when it couldn't be used.
    public var replyExcerpt: String?

    public var succeeded: Bool { failedStep == nil }

    /// Plain text for "Copy details" (no key, no user content).
    public func report() -> String {
        var lines = [
            "Widget Studio — last AI request",
            "Date: \(ISO8601DateFormatter().string(from: date))",
            "Provider: \(provider.displayName)",
            "Model: \(model)",
            "Feature: \(feature.rawValue)",
            "Endpoint: \(endpoint ?? "—")",
            "HTTP status: \(httpStatus.map(String.init) ?? "—")",
            "Result: \(failedStep.map { "failed at \($0.rawValue)" } ?? "success")",
            "Attempts: \(attempts)",
            "Duration: \(durationMs) ms",
        ]
        if let message { lines.append("Message: \(message)") }
        if let errorBody { lines.append("Error body:\n\(errorBody)") }
        if let replyExcerpt { lines.append("Reply excerpt:\n\(replyExcerpt)") }
        return lines.joined(separator: "\n")
    }
}

/// The last request's diagnostic (UserDefaults; it holds no secrets).
public enum AIDiagnosticsStore {
    public static let defaultsKey = "aiLastRequest"

    public static func load(from defaults: UserDefaults = .standard) -> AIDiagnostic? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(AIDiagnostic.self, from: data)
    }

    public static func save(_ diagnostic: AIDiagnostic, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(diagnostic) { defaults.set(data, forKey: defaultsKey) }
    }

    public static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// HTTP facts collected while one structured request runs. `AIHTTP.send` fills it through the
/// task-local `current`, so providers don't need to pass it along.
public final class AITrace: @unchecked Sendable {
    @TaskLocal public static var current: AITrace?

    private let lock = NSLock()
    private var _endpoint: String?
    private var _status: Int?
    private var _body: Data?
    private var _networkError: String?

    public init() {}

    var endpoint: String? { lock.withLock { _endpoint } }
    var status: Int? { lock.withLock { _status } }
    var body: Data? { lock.withLock { _body } }
    var networkError: String? { lock.withLock { _networkError } }

    func begin(_ url: URL?) {
        lock.withLock {
            var components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            components?.query = nil
            _endpoint = components?.string
            _status = nil
            _body = nil
            _networkError = nil
        }
    }

    func received(status: Int, body: Data) {
        lock.withLock {
            _status = status
            _body = body
        }
    }

    func failed(_ error: Error) {
        let nsError = error as NSError
        lock.withLock { _networkError = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)" }
    }
}

/// Removes API keys from text before it's stored or shown.
public enum AIRedactor {
    /// Google (AIza…, AQ.…), OpenAI/Anthropic/OpenRouter (sk-…) style keys, and `key=` parameters.
    private static let patterns = [
        #"\bAIza[0-9A-Za-z_\-]{20,}"#, #"\bAQ\.[0-9A-Za-z_\-]{20,}"#, #"\bsk-[A-Za-z0-9_\-]{12,}"#,
        #"\bnvapi-[A-Za-z0-9_\-]{12,}"#, #"\bgsk_[A-Za-z0-9]{12,}"#, #"(?i)(key=)[^&\s"]+"#,
    ]

    public static func redact(_ text: String, secrets: [String] = []) -> String {
        var result = text
        for secret in secrets where secret.count >= 6 {
            result = result.replacingOccurrences(of: secret, with: "[redacted]")
        }
        for pattern in patterns {
            let template = pattern.hasPrefix("(?i)(key=)") ? "$1[redacted]" : "[redacted]"
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return result
    }

    /// Redacted and capped, for storage.
    static func excerpt(_ data: Data?, secrets: [String], limit: Int = 4000) -> String? {
        guard let data, !data.isEmpty else { return nil }
        return excerpt(String(bytes: data, encoding: .utf8) ?? "<\(data.count) bytes, not UTF-8>", secrets: secrets, limit: limit)
    }

    static func excerpt(_ text: String, secrets: [String], limit: Int = 4000) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let redacted = redact(trimmed, secrets: secrets)
        return redacted.count > limit ? String(redacted.prefix(limit)) + "…" : redacted
    }
}
