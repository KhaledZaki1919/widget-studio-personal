import Foundation

/// Google Gemini `generateContent` (v1beta), called directly with the user's key in the
/// `x-goog-api-key` header (ADR-008). JSON mode plus a native `responseSchema` (Google's OpenAPI
/// subset, converted from our JSON Schema). If Gemini rejects the schema, `StructuredAI` resends
/// with the schema in the prompt. Every answer is validated either way.
public struct GeminiProvider: AIProvider {
    public let kind = AIProviderKind.gemini
    private let apiKey: String
    private let session: URLSession
    static let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// The only credential on every Gemini request (generate and model list). Google's newer
    /// "AQ." auth keys and the older "AIza" keys both work this way; adding `?key=` or an
    /// `Authorization` header as well makes Google reject the request for carrying two credentials.
    var headers: [String: String] { ["x-goog-api-key": apiKey] }

    static func modelPath(_ model: String) -> String {
        model.hasPrefix("models/") ? model : "models/\(model)"
    }

    private static func isLegacy(_ model: String) -> Bool {
        ["gemini-1.", "gemini-2.0"].contains { model.lowercased().contains($0) }
    }

    /// Thinking models count thoughts against `maxOutputTokens`, so they get extra room, or a
    /// long think cuts the JSON off (finishReason MAX_TOKENS). Older models reject limits above 8192.
    static func outputTokenLimit(_ request: AIRequest, model: String) -> Int {
        isLegacy(model) ? min(request.maxOutputTokens, 8192) : request.maxOutputTokens + 24576
    }

    enum Thinking: Equatable {
        case off
        /// Gemini 2.5: `thinkingBudget` in tokens.
        case budget(Int)
        /// Gemini 3 and later: `thinkingLevel`.
        case level(String)
    }

    /// Low thinking keeps image analysis fast and cheap. Models that don't think get no setting;
    /// a model that rejects it is retried once without it (see `complete`).
    static func thinking(for model: String) -> Thinking {
        let id = model.lowercased()
        if isLegacy(id) || ["flash-lite", "gemma", "image", "tts"].contains(where: id.contains) { return .off }
        if id.contains("gemini-2.5") { return .budget(1024) }
        return .level("low")
    }

    func body(for request: AIRequest, model: String, structured: Bool, thinking: Thinking) -> JSONValue {
        var parts: [JSONValue] = request.images.map { jpeg in
            ["inlineData": ["mimeType": "image/jpeg", "data": .string(jpeg.base64EncodedString())]]
        }
        parts.append(["text": .string(request.userText)])
        var config: [String: JSONValue] = [
            "responseMimeType": "application/json",
            "maxOutputTokens": .int(Self.outputTokenLimit(request, model: model)),
        ]
        // ADR-029: the full JSON Schema through responseJsonSchema (limits, anyOf, patterns); the older
        // OpenAPI-subset responseSchema hung in the eval. A rejection or timeout falls back to the prompt.
        if structured { config["responseJsonSchema"] = request.schema }
        switch thinking {
        case .off: break
        case .budget(let tokens): config["thinkingConfig"] = ["thinkingBudget": .int(tokens)]
        case .level(let level): config["thinkingConfig"] = ["thinkingLevel": .string(level)]
        }
        return [
            "systemInstruction": ["parts": [["text": .string(request.system)]]],
            "contents": [["role": "user", "parts": .array(parts)]],
            "generationConfig": .object(config),
        ]
    }

    /// Gemini's `responseSchema` is an OpenAPI subset: no `additionalProperties`, no `$ref`, no
    /// `pattern`. `anyOf` is kept. Gemini doesn't need strict schemas, so nullable properties
    /// become optional (left out of `required`, no `nullable`): the model writes no nulls, which
    /// keeps answers short. The strict all-required form made answers so long that requests ran
    /// past the 180 s timeout in the M5 eval (ADR-019).
    static func openAPISchema(_ schema: JSONValue) -> JSONValue {
        guard case .object(let fields) = schema else { return schema }
        var converted: [String: JSONValue] = [:]
        if case .object(let properties)? = fields["properties"], case .array(let required)? = fields["required"] {
            let optional = Set(properties.filter { isNullable($0.value) }.keys)
            converted["required"] = .array(required.filter { !optional.contains($0.stringValue ?? "") })
        }
        for (key, value) in fields {
            switch key {
            case "additionalProperties", "$schema", "$ref", "$defs", "$id", "title", "pattern", "exclusiveMinimum":
                continue
            case "type":
                if case .array(let types) = value {
                    let concrete = types.filter { $0 != .string("null") }
                    converted["type"] = concrete.first ?? "string"
                } else {
                    converted["type"] = value
                }
            case "enum":
                if case .array(let values) = value {
                    converted["enum"] = .array(values.filter { $0 != .null })
                }
            case "properties":
                if case .object(let properties) = value {
                    converted["properties"] = .object(properties.mapValues(openAPISchema))
                }
            case "items":
                converted["items"] = openAPISchema(value)
            case "anyOf":
                if case .array(let options) = value {
                    converted["anyOf"] = .array(options.map(openAPISchema))
                }
            case "required":
                if converted["required"] == nil { converted["required"] = value }
            default:
                converted[key] = value
            }
        }
        return .object(converted)
    }

    /// A JSON Schema whose type list includes "null".
    static func isNullable(_ schema: JSONValue) -> Bool {
        if case .array(let types)? = schema["type"] { return types.contains(.string("null")) }
        return false
    }

    public func complete(_ request: AIRequest, model: String, structured: Bool) async throws -> AIResponse {
        guard let url = URL(string: "\(Self.baseURL)/\(Self.modelPath(model)):generateContent") else { throw AIError.modelNotFound }
        let thinking = Self.thinking(for: model)
        do {
            return try await send(request, url: url, model: model, structured: structured, thinking: thinking)
        } catch AIError.badRequest(let message) where thinking != .off && message.lowercased().contains("thinking") {
            return try await send(request, url: url, model: model, structured: structured, thinking: .off)
        }
    }

    private func send(_ request: AIRequest, url: URL, model: String, structured: Bool,
                      thinking: Thinking) async throws -> AIResponse {
        let body = body(for: request, model: model, structured: structured, thinking: thinking)
        let urlRequest = try AIHTTP.jsonRequest(url: url, headers: headers, body: body, timeout: request.timeout)
        let data = try await AIHTTP.send(urlRequest, session: session, retryTransient: true)
        return try Self.parse(data, model: model)
    }

    struct GenerateResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                    /// Thought summaries (only sent with includeThoughts) aren't part of the answer.
                    let thought: Bool?
                }

                let parts: [Part]?
            }

            let content: Content?
            let finishReason: String?
        }

        struct Feedback: Decodable { let blockReason: String? }

        struct Usage: Decodable {
            let promptTokenCount: Int?
            let candidatesTokenCount: Int?
            let thoughtsTokenCount: Int?
        }

        let candidates: [Candidate]?
        let promptFeedback: Feedback?
        let usageMetadata: Usage?
        let modelVersion: String?
    }

    static let blockedFinishReasons: Set<String> = [
        "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION", "IMAGE_SAFETY",
    ]

    static func parse(_ data: Data, model: String) throws -> AIResponse {
        guard let response = try? JSONDecoder().decode(GenerateResponse.self, from: data) else {
            throw AIError.invalidOutput("unreadable response")
        }
        if response.promptFeedback?.blockReason != nil { throw AIError.refused }
        let candidate = response.candidates?.first
        let finish = candidate?.finishReason ?? "none"
        if blockedFinishReasons.contains(finish) { throw AIError.refused }
        // Partial JSON is never usable, so a cut-off reply is reported as truncated right away.
        if finish == "MAX_TOKENS" { throw AIError.truncated }
        let text = candidate?.content?.parts?.filter { $0.thought != true }.compactMap(\.text).joined() ?? ""
        if text.isEmpty { throw AIError.invalidOutput("empty reply (finishReason \(finish))") }
        // Thinking tokens are billed as output.
        let usage = response.usageMetadata.map {
            AIUsage(inputTokens: $0.promptTokenCount ?? 0,
                    outputTokens: ($0.candidatesTokenCount ?? 0) + ($0.thoughtsTokenCount ?? 0))
        }
        return AIResponse(text: text, usage: usage, model: response.modelVersion ?? model)
    }

    public func listModels() async throws -> [String] {
        guard let url = URL(string: "\(Self.baseURL)/models?pageSize=200") else { return [] }
        let data = try await AIHTTP.send(AIHTTP.getRequest(url: url, headers: headers), session: session)
        return Self.parseModels(data)
    }

    static func parseModels(_ data: Data) -> [String] {
        struct List: Decodable {
            struct Model: Decodable {
                let name: String
                let supportedGenerationMethods: [String]?
            }

            let models: [Model]?
        }
        let models = (try? JSONDecoder().decode(List.self, from: data))?.models ?? []
        return models
            .filter { $0.supportedGenerationMethods?.contains("generateContent") ?? false }
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .filter { !["tts", "embedding", "image", "live", "transcribe"].contains(where: $0.contains) }
            .sorted()
    }
}
