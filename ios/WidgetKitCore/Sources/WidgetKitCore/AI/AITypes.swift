import Foundation

/// The AI providers a user can bring a key for (brief D4, ADR-008, M6.1). Ported from Lakhas;
/// NVIDIA NIM, Groq and Custom are OpenAI-compatible (free vision presets checked in their docs
/// on 2026-10-29, ADR-022).
public enum AIProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case gemini, nvidia, groq, openrouter, anthropic, openai, custom

    public var id: String { rawValue }

    /// Product names stay in Latin script in both languages; Custom is localized in the UI.
    public var displayName: String {
        switch self {
        case .gemini: "Google Gemini"
        case .nvidia: "NVIDIA NIM"
        case .groq: "Groq"
        case .openrouter: "OpenRouter"
        case .anthropic: "Anthropic Claude"
        case .openai: "OpenAI"
        case .custom: "Custom (OpenAI-compatible)"
        }
    }

    /// The company name for short messages ("Google is busy").
    public var shortName: String {
        switch self {
        case .gemini: "Google"
        case .nvidia: "NVIDIA"
        case .groq: "Groq"
        case .openrouter: "OpenRouter"
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .custom: "The provider"
        }
    }

    /// Providers with a free tier that reads images (ADR-022).
    public var hasFreeTier: Bool {
        [.gemini, .nvidia, .groq, .openrouter].contains(self)
    }

    /// Where the user creates an API key.
    public var keyPageURL: URL? {
        switch self {
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .nvidia: URL(string: "https://build.nvidia.com")
        case .groq: URL(string: "https://console.groq.com/keys")
        case .openrouter: URL(string: "https://openrouter.ai/keys")
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .custom: nil
        }
    }

    /// Fixed OpenAI-compatible base URL; Custom uses the user's.
    public var baseURL: String? {
        switch self {
        case .nvidia: "https://integrate.api.nvidia.com/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .openrouter: "https://openrouter.ai/api/v1"
        case .openai: "https://api.openai.com/v1"
        case .gemini, .anthropic, .custom: nil
        }
    }

    /// Fast, low-cost vision model used by default. IDs checked in each provider's model docs
    /// (ADR-018, ADR-019); the free providers' picks come from the AI eval of 2026-11-01/02
    /// (ADR-022): every free preset reads images at no cost. Custom has none: the user types it.
    public var recommendedModel: String {
        switch self {
        case .gemini: "gemini-3.5-flash-lite"
        case .nvidia: "nvidia/nemotron-3.5-super-vl-120b-a12b"
        case .groq: "qwen/qwen3.8-27b"
        case .openrouter: "nvidia/nemotron-3.5-super-vl:free"
        case .anthropic: "claude-haiku-5-5"
        case .openai: "gpt-6-luna"
        case .custom: ""
        }
    }

    /// Suggested when the default model is rate limited.
    public var alternativeModel: String {
        switch self {
        case .gemini: "gemini-3.8-flash"
        case .nvidia: "meta/llama-3.2-90b-vision-instruct"
        case .groq: "qwen/qwen3.8-27b"
        case .openrouter: "openrouter/free"
        case .anthropic: "claude-sonnet-5-5"
        case .openai: "gpt-6.1-sol"
        case .custom: ""
        }
    }

    /// Shown before a key is set; the provider's live list replaces it afterwards.
    public var builtInModels: [String] {
        switch self {
        case .gemini: ["gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-3.6-flash"]
        case .nvidia: ["nvidia/nemotron-3.5-super-vl-120b-a12b", "meta/llama-3.2-90b-vision-instruct", "google/gemma-4-31b-it"]
        case .groq: ["qwen/qwen3.8-27b"]
        case .openrouter: ["nvidia/nemotron-3.5-super-vl:free", "openrouter/free", "google/gemma-4-31b-it:free",
                           "google/gemini-3.8-flash", "anthropic/claude-haiku-5.5", "openai/gpt-6-luna"]
        case .anthropic: ["claude-haiku-5-5", "claude-sonnet-5-5"]
        case .openai: ["gpt-6-luna", "gpt-6.1-sol"]
        case .custom: []
        }
    }

    /// Whether requests start with the provider's native structured output. Gemini starts in
    /// JSON mode with the schema in the prompt: with `responseSchema`, Gemini 3.8 Flash ran past
    /// three minutes on most eval images while JSON mode answered in 1–12 s (ADR-019). NVIDIA NIM
    /// and Custom start with the schema in the prompt too, since JSON-mode support varies by model.
    /// Every reply is validated either way.
    public var prefersStructuredOutput: Bool {
        ![.gemini, .nvidia, .custom].contains(self)
    }

    /// `customBaseURL` is used by `.custom` only.
    public func makeProvider(apiKey: String, session: URLSession = .shared, customBaseURL: String = "") -> AIProvider {
        switch self {
        case .gemini: GeminiProvider(apiKey: apiKey, session: session)
        case .anthropic: AnthropicProvider(apiKey: apiKey, session: session)
        case .openai, .openrouter, .nvidia, .groq:
            OpenAICompatibleProvider(kind: self, apiKey: apiKey, baseURL: baseURL ?? "", session: session)
        case .custom:
            OpenAICompatibleProvider(kind: .custom, apiKey: apiKey, baseURL: CustomEndpoint.normalized(customBaseURL) ?? "", session: session)
        }
    }
}

/// The user's base URL for the Custom provider (M6.1).
public enum CustomEndpoint {
    /// "https://host/v1/" or ".../chat/completions" → "https://host/v1"; nil unless https (or
    /// http on localhost) with a host.
    public static func normalized(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["/chat/completions", "/"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else { return nil }
        let local = host == "localhost" || host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && local) else { return nil }
        return text
    }
}

/// What an AI request is for (diagnostics).
public enum AIFeature: String, Codable, Sendable, CaseIterable {
    case generateWidget, reviewWidget, connectionTest
}

public struct AIRequest: Sendable, Equatable {
    public var system: String
    public var userText: String
    /// JPEG images, already downscaled with metadata stripped.
    public var images: [Data]
    /// JSON Schema of the expected answer.
    public var schema: JSONValue
    public var schemaName: String
    public var maxOutputTokens: Int

    public init(system: String, userText: String, images: [Data] = [], schema: JSONValue,
                schemaName: String = "result", maxOutputTokens: Int = 2048, timeout: TimeInterval = 180) {
        self.system = system
        self.userText = userText
        self.images = images
        self.schema = schema
        self.schemaName = schemaName
        self.maxOutputTokens = maxOutputTokens
        self.timeout = timeout
    }

    /// Seconds before one HTTP request gives up. Widget generation uses less than the default, so
    /// a runaway structured answer leaves time for the prompt-only retry (ADR-019).
    public var timeout: TimeInterval

    /// For providers without native structured output, or after a provider rejected it.
    public func withSchemaInstructions() -> AIRequest {
        var copy = self
        copy.system += "\n\nReply with only one JSON object, no prose and no code fences. It must match this JSON Schema:\n"
            + schema.jsonString()
        return copy
    }

    /// The one retry after an invalid answer.
    public func withRetryNote(_ problem: String) -> AIRequest {
        var copy = self
        copy.userText += "\n\n<validation_error>Your previous reply was not valid: \(problem). "
            + "Reply again with only the corrected JSON object.</validation_error>"
        return copy
    }
}

public struct AIUsage: Sendable, Equatable, Codable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct AIResponse: Sendable, Equatable {
    public let text: String
    public let usage: AIUsage?
    public let model: String

    public init(text: String, usage: AIUsage?, model: String) {
        self.text = text
        self.usage = usage
        self.model = model
    }
}

public enum AIError: Error, Equatable, Sendable {
    case noKey
    case invalidKey
    case insufficientCredit
    case rateLimited
    /// The day's request quota for this model is used up (free Gemini keys: 20 a day per model).
    case dailyQuota
    case modelNotFound
    /// The provider declined the request or flagged the image (brief §8).
    case refused
    case truncated
    /// Still invalid after the one retry; the text says what was wrong.
    case invalidOutput(String)
    case network
    case providerUnavailable
    /// The provider is overloaded right now (HTTP 503 "high demand", 529); worth trying again soon.
    case busy
    case badRequest(String)
    /// No answer before the app's hard deadline (`AIDeadline`) or the request timed out.
    case timedOut
    /// The user cancelled.
    case cancelled
}

/// One provider implementation (plain URLSession, no SDKs).
public protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    /// `structured`: ask the provider to enforce `request.schema` natively.
    func complete(_ request: AIRequest, model: String, structured: Bool) async throws -> AIResponse
    func listModels() async throws -> [String]
}
