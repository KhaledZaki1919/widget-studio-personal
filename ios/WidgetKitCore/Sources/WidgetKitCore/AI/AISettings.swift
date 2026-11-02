import Foundation

/// Where API keys are kept: the Keychain in the app, a dictionary in tests.
public protocol AIKeyStorage: Sendable {
    func readKey(account: String) -> String?
    func writeKey(_ value: String, account: String) throws
    func removeKey(account: String)
}

extension KeychainStore: AIKeyStorage {
    public func readKey(account: String) -> String? {
        guard let data = try? read(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func writeKey(_ value: String, account: String) throws {
        try save(Data(value.utf8), account: account)
    }

    public func removeKey(account: String) {
        try? delete(account: account)
    }
}

/// The user's API keys: one Keychain item per provider, readable only while the device is
/// unlocked, never synced or backed up. Keys are never logged or exported (ported from Lakhas).
public struct AIKeyStore: Sendable {
    private let storage: AIKeyStorage

    public init(storage: AIKeyStorage = KeychainStore(service: "widgetstudio.ai-keys")) {
        self.storage = storage
    }

    /// Sanitized on read too, so a key saved before sanitizing existed still works.
    public func key(for provider: AIProviderKind) -> String? {
        guard let raw = storage.readKey(account: provider.rawValue) else { return nil }
        let key = Self.sanitize(raw)
        return key.isEmpty ? nil : key
    }

    public func hasKey(for provider: AIProviderKind) -> Bool { key(for: provider) != nil }

    public func save(_ key: String, for provider: AIProviderKind) throws {
        let clean = Self.sanitize(key)
        guard !clean.isEmpty else { return delete(for: provider) }
        try storage.writeKey(clean, account: provider.rawValue)
    }

    public func delete(for provider: AIProviderKind) {
        storage.removeKey(account: provider.rawValue)
    }

    /// Pasted keys often carry spaces, line breaks, wrapping quotes, a "Bearer " prefix, or
    /// invisible characters (zero-width spaces, LTR/RTL marks from Arabic text). Any of these
    /// breaks the auth header, so they're removed. Nothing else about the key changes.
    public static func sanitize(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            let category = scalar.properties.generalCategory
            return !(scalar.properties.isWhitespace || category == .format || category == .control)
        }
        var key = String(String.UnicodeScalarView(scalars))
        if key.lowercased().hasPrefix("bearer") && raw.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("bearer ") {
            key.removeFirst("bearer".count)
        }
        let wrappers = CharacterSet(charactersIn: "\"'`“”‘’<>")
        return key.trimmingCharacters(in: wrappers)
    }

    /// Format hints shown while typing. They never block saving: providers change formats
    /// (Google's AI Studio issues "AQ." keys alongside older "AIza" keys).
    public static func warnings(for key: String, provider: AIProviderKind) -> [AIKeyWarning] {
        let clean = sanitize(key)
        guard !clean.isEmpty else { return [] }
        var warnings: [AIKeyWarning] = []
        if !clean.unicodeScalars.allSatisfy({ $0.isASCII }) { warnings.append(.unexpectedCharacters) }
        // A custom endpoint may use any key format (or a short local token).
        guard provider != .custom else { return warnings }
        if let owner = AIProviderKind.owner(ofKey: clean) {
            if owner != provider { warnings.insert(.looksLike(owner), at: 0) }
        } else {
            warnings.insert(.unexpectedFormat, at: 0)
        }
        if clean.count < 20 { warnings.append(.tooShort) }
        return warnings
    }

    /// "AQ.A…9f3c · 39" for display: first 4, last 4 and the length.
    public static func masked(_ key: String) -> String {
        guard key.count > 12 else { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(4))…\(key.suffix(4)) · \(key.count)"
    }
}

public enum AIKeyWarning: Equatable, Sendable {
    /// The key has another provider's format (e.g. "sk-ant-" in the Gemini field).
    case looksLike(AIProviderKind)
    /// Not a format we know for any provider.
    case unexpectedFormat
    /// Non-ASCII characters remain after cleaning.
    case unexpectedCharacters
    case tooShort
}

extension AIProviderKind {
    /// Usual key prefixes, for the format hint.
    public var keyPrefixes: [String] {
        switch self {
        case .anthropic: ["sk-ant-"]
        case .openai: ["sk-"]
        case .gemini: ["AIza", "AQ."]
        case .openrouter: ["sk-or-"]
        case .nvidia: ["nvapi-"]
        case .groq: ["gsk_"]
        case .custom: []
        }
    }

    /// The provider whose key format this is, most specific prefix first.
    public static func owner(ofKey key: String) -> AIProviderKind? {
        if key.hasPrefix("sk-ant-") { return .anthropic }
        if key.hasPrefix("sk-or-") { return .openrouter }
        if key.hasPrefix("AIza") || key.hasPrefix("AQ.") { return .gemini }
        if key.hasPrefix("nvapi-") { return .nvidia }
        if key.hasPrefix("gsk_") { return .groq }
        if key.hasPrefix("sk-") { return .openai }
        return nil
    }
}

/// Provider, model per provider, upload consent per provider and "High quality" per provider
/// (UserDefaults; no secrets).
public struct AISettings: Codable, Sendable, Equatable {
    public var provider: AIProviderKind
    public var models: [String: String]
    /// Providers the user agreed to send images to (brief §5 step 3); revocable in Settings.
    public var consented: [String]
    /// "High quality (2 requests)" per provider: the self-review round (ADR-019). Unset = the
    /// provider's default (`defaultHighQuality`).
    public var highQuality: [String: Bool]
    /// Base URL of the Custom (OpenAI-compatible) provider, e.g. "https://host/v1" (M6.1).
    public var customBaseURL: String

    public static let defaultsKey = "aiSettings"

    enum CodingKeys: String, CodingKey {
        case provider, models, consented, highQuality, customBaseURL
    }

    public init(provider: AIProviderKind = .gemini, models: [String: String] = [:], consented: [String] = [],
                highQuality: [String: Bool] = [:], customBaseURL: String = "") {
        self.provider = provider
        self.models = models
        self.consented = consented
        self.highQuality = highQuality
        self.customBaseURL = customBaseURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = (try? container.decode(AIProviderKind.self, forKey: .provider)) ?? .gemini
        models = (try? container.decode([String: String].self, forKey: .models)) ?? [:]
        consented = (try? container.decode([String].self, forKey: .consented)) ?? []
        highQuality = (try? container.decode([String: Bool].self, forKey: .highQuality)) ?? [:]
        customBaseURL = (try? container.decode(String.self, forKey: .customBaseURL)) ?? ""
    }

    public static func load(from defaults: UserDefaults = .standard) -> AISettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AISettings.self, from: data) else { return AISettings() }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    public func model(for provider: AIProviderKind) -> String {
        models[provider.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? provider.recommendedModel
    }

    public var model: String { model(for: provider) }

    /// On for paid providers; off for Gemini, whose free keys have tight per-minute limits.
    public static func defaultHighQuality(for provider: AIProviderKind) -> Bool {
        provider != .gemini
    }

    public func usesHighQuality(for provider: AIProviderKind) -> Bool {
        highQuality[provider.rawValue] ?? Self.defaultHighQuality(for: provider)
    }

    /// The provider's name for messages: the host for a custom endpoint.
    public var providerName: String {
        guard provider == .custom else { return provider.displayName }
        return CustomEndpoint.normalized(customBaseURL).flatMap { URL(string: $0)?.host } ?? provider.displayName
    }

    /// A custom endpoint needs a valid base URL and a model ID.
    public var isCustomReady: Bool {
        CustomEndpoint.normalized(customBaseURL) != nil && !model(for: .custom).isEmpty
    }

    public func hasConsent(for provider: AIProviderKind) -> Bool {
        consented.contains(provider.rawValue)
    }

    public mutating func setConsent(_ granted: Bool, for provider: AIProviderKind) {
        consented.removeAll { $0 == provider.rawValue }
        if granted { consented.append(provider.rawValue) }
    }
}
