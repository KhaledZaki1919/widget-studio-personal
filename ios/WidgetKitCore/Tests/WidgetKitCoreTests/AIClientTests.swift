import Foundation
import Testing
@testable import WidgetKitCore

/// The BYOK client ported from Lakhas (ADR-008, ADR-018): request bodies, recorded responses,
/// error mapping, retries and deadlines. No real keys and no network.
@Suite(.serialized)
struct AIClientTests {
    /// Short fake keys that the secret scan can't mistake for real ones.
    let geminiKey = "AQ.fake-test-key"
    let schema = JSONSchema.object([
        "ok": JSONSchema.boolean,
        "note": JSONSchema.nullable(JSONSchema.string),
        "kind": JSONSchema.nullable(JSONSchema.enumeration(["a", "b"])),
    ])

    func request(images: [Data] = []) -> AIRequest {
        AIRequest(system: "system", userText: "user", images: images, schema: schema, schemaName: "connection_test")
    }

    // MARK: Gemini

    @Test func geminiSendsTheKeyOnlyInTheHeader() async throws {
        let (session, id) = StubURLProtocol.session([.http(status: 200, body: try aiFixture("gemini-ok"))])
        let provider = GeminiProvider(apiKey: geminiKey, session: session)
        let response = try await provider.complete(request(), model: "gemini-3.8-flash", structured: true)
        #expect(response.text == "{\"ok\":true}")
        #expect(response.usage == AIUsage(inputTokens: 41, outputTokens: 23))
        let sent = try #require(StubURLProtocol.requests(id).first)
        #expect(sent.value(forHTTPHeaderField: "x-goog-api-key") == geminiKey)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.url?.query == nil)
        #expect(sent.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
    }

    @Test func geminiBodyUsesResponseSchemaAndLowThinking() throws {
        let provider = GeminiProvider(apiKey: geminiKey)
        let body = provider.body(for: request(images: [Data([0xFF, 0xD8])]), model: "gemini-3.8-flash", structured: true,
                                 thinking: GeminiProvider.thinking(for: "gemini-3.8-flash"))
        let config = try #require(body["generationConfig"])
        #expect(config["responseMimeType"] == "application/json")
        #expect(config["thinkingConfig"]?["thinkingLevel"] == "low")
        let responseSchema = try #require(config["responseSchema"])
        #expect(responseSchema["additionalProperties"] == nil)
        #expect(responseSchema["properties"]?["note"]?["type"] == "string")
        // Compact for Gemini (ADR-019): nullable properties are optional, not required-and-null.
        #expect(responseSchema["required"] == ["ok"])
        #expect(responseSchema["properties"]?["note"]?["nullable"] == nil)
        #expect(responseSchema["properties"]?["kind"]?["enum"] == ["a", "b"])
        guard case .array(let parts)? = body["contents"]?.arrayFirst?["parts"] else {
            Issue.record("no parts")
            return
        }
        #expect(parts.first?["inlineData"]?["mimeType"] == "image/jpeg")
        #expect(GeminiProvider.thinking(for: "gemini-3.5-flash-lite") == .off)
        #expect(GeminiProvider.thinking(for: "gemini-2.5-flash") == .budget(1024))
    }

    @Test func geminiRecordedReplies() throws {
        #expect(throws: AIError.refused) { try GeminiProvider.parse(try aiFixture("gemini-blocked"), model: "m") }
        #expect(throws: AIError.refused) { try GeminiProvider.parse(try aiFixture("gemini-image-safety"), model: "m") }
        #expect(throws: AIError.truncated) { try GeminiProvider.parse(try aiFixture("gemini-max-tokens"), model: "m") }
        #expect(GeminiProvider.parseModels(try aiFixture("gemini-models")) == ["gemini-3.5-flash-lite", "gemini-3.8-flash"])
    }

    @Test func geminiAnyOfAndNestedTypesConvert() {
        let converted = GeminiProvider.openAPISchema(JSONSchema.anyOf([
            JSONSchema.object(["type": JSONSchema.enumeration(["text"]), "size": JSONSchema.nullable(JSONSchema.number)]),
        ]))
        #expect(converted["anyOf"]?.arrayFirst?["required"] == ["type"])
        #expect(converted["anyOf"]?.arrayFirst?["properties"]?["size"]?["type"] == "number")
        #expect(converted["anyOf"]?.arrayFirst?["additionalProperties"] == nil)
    }

    // MARK: Anthropic

    @Test func anthropicUsesAStrictToolWithAutoChoice() throws {
        let body = AnthropicProvider(apiKey: "sk-test").body(for: request(), model: "claude-haiku-5-5", structured: true)
        let tool = try #require(body["tools"]?.arrayFirst)
        #expect(tool["name"] == "connection_test")
        #expect(tool["input_schema"] == schema)
        #expect(tool["strict"] == true)
        #expect(body["tool_choice"]?["type"] == "auto")
        #expect(body["output_config"]?["effort"] == "low")
        let plain = AnthropicProvider(apiKey: "sk-test").body(for: request(), model: "claude-haiku-5-5", structured: false)
        #expect(plain["tools"] == nil)
    }

    @Test func anthropicRecordedReplies() throws {
        let tool = try AnthropicProvider.parse(try aiFixture("anthropic-tool"), model: "m")
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(tool.text.utf8)) == ["ok": true])
        #expect(tool.model == "claude-haiku-5-5")
        let text = try AnthropicProvider.parse(try aiFixture("anthropic-text"), model: "m")
        #expect(try StructuredAI.decode(ConnectionTest.Reply.self, from: text.text).ok)
        #expect(throws: AIError.refused) { try AnthropicProvider.parse(try aiFixture("anthropic-refusal"), model: "m") }
    }

    // MARK: OpenAI and OpenRouter

    @Test func openAIUsesStrictJSONSchema() throws {
        let body = OpenAICompatibleProvider(kind: .openai, apiKey: "sk-test")
            .body(for: request(), model: "gpt-6-luna", structured: true, reasoning: true)
        #expect(body["response_format"]?["type"] == "json_schema")
        #expect(body["response_format"]?["json_schema"]?["strict"] == true)
        #expect(body["response_format"]?["json_schema"]?["schema"] == schema)
        #expect(body["max_completion_tokens"] == 2048)
        #expect(body["reasoning_effort"] == "low")
        #expect(OpenAICompatibleProvider.usesReasoningEffort("gpt-6-luna"))
        #expect(!OpenAICompatibleProvider.usesReasoningEffort("gpt-4o"))
    }

    @Test func openRouterUsesJSONModeWithTheSchemaInThePrompt() throws {
        let provider = OpenAICompatibleProvider(kind: .openrouter, apiKey: "sk-or-test")
        let body = provider.body(for: request(), model: "google/gemini-3.8-flash", structured: true, reasoning: false)
        #expect(body["response_format"] == ["type": "json_object"])
        #expect(body["max_tokens"] == 2048)
        guard case .array(let messages)? = body["messages"], case .string(let system)? = messages.first?["content"] else {
            Issue.record("no system message")
            return
        }
        #expect(system.contains("JSON Schema"))
        #expect(provider.headers["Authorization"] == "Bearer sk-or-test")
    }

    @Test func openAIRecordedReplies() throws {
        #expect(try OpenAICompatibleProvider.parse(try aiFixture("openai-ok"), model: "m").text == "{\"ok\":true}")
        #expect(try OpenAICompatibleProvider.parse(try aiFixture("openrouter-ok"), model: "m").model == "google/gemini-3.8-flash")
        #expect(throws: AIError.refused) { try OpenAICompatibleProvider.parse(try aiFixture("openai-refusal"), model: "m") }
        #expect(throws: AIError.badRequest("Provider returned error")) {
            try OpenAICompatibleProvider.parse(try aiFixture("openrouter-200-error"), model: "m")
        }
        #expect(OpenAICompatibleProvider.parseModels(try aiFixture("openrouter-models"), kind: .openrouter) == ["google/gemini-3.8-flash"])
    }

    // MARK: Error mapping

    @Test func errorsMapToWhatTheUserCanDo() throws {
        #expect(AIHTTP.mapError(status: 429, body: try aiFixture("gemini-429")) == .rateLimited)
        #expect(AIHTTP.mapError(status: 429, body: try aiFixture("gemini-429-daily")) == .dailyQuota)
        #expect(AIHTTP.retryDelay(status: 429, body: try aiFixture("gemini-429-daily")) == nil)
        #expect(AIHTTP.mapError(status: 400, body: try aiFixture("gemini-400-key")) == .invalidKey)
        #expect(AIHTTP.mapError(status: 401, body: try aiFixture("anthropic-401")) == .invalidKey)
        #expect(AIHTTP.mapError(status: 429, body: try aiFixture("anthropic-429")) == .rateLimited)
        #expect(AIHTTP.mapError(status: 400, body: try aiFixture("anthropic-400-credit")) == .insufficientCredit)
        #expect(AIHTTP.mapError(status: 429, body: try aiFixture("openai-429-quota")) == .insufficientCredit)
        #expect(AIHTTP.mapError(status: 404, body: Data()) == .modelNotFound)
        #expect(AIHTTP.mapError(status: 410, body: Data()) == .modelNotFound)
        #expect(AIHTTP.mapError(status: 500, body: Data()) == .providerUnavailable)
        #expect(AIHTTP.mapError(status: 503, body: try aiFixture("gemini-503")) == .busy)
        #expect(AIHTTP.mapError(status: 529, body: Data()) == .busy)
        #expect(AIHTTP.mapTransportError(URLError(.notConnectedToInternet)) == .network)
        #expect(AIHTTP.mapTransportError(URLError(.timedOut)) == .timedOut)
        if case .badRequest(let message) = AIHTTP.mapError(status: 400, body: try aiFixture("openai-400-schema")) {
            #expect(StructuredAI.looksLikeSchemaRejection(message))
        } else {
            Issue.record("schema rejection should stay a bad request")
        }
    }

    @Test func geminiRetryDelayOnlyForShortWaits() throws {
        #expect(AIHTTP.retryDelay(status: 429, body: try aiFixture("gemini-429")) == nil)
        let short = Data(#"{"error":{"details":[{"retryDelay":"17s"}]}}"#.utf8)
        #expect(AIHTTP.retryDelay(status: 429, body: short) == 17.5)
        #expect(AIHTTP.retryDelay(status: 503, body: Data(), attempt: 0) == 3)
        #expect(AIHTTP.retryDelay(status: 503, body: Data(), attempt: 1) == 8)
        #expect(AIHTTP.retryDelay(status: 429, body: short, attempt: 1) == nil)
    }

    @Test func transportFailuresMapThroughTheProvider() async throws {
        let (offline, _) = StubURLProtocol.session([.failure(.notConnectedToInternet)])
        await #expect(throws: AIError.network) {
            try await GeminiProvider(apiKey: geminiKey, session: offline).complete(request(), model: "gemini-3.8-flash", structured: true)
        }
        let (slow, _) = StubURLProtocol.session([.failure(.timedOut)])
        await #expect(throws: AIError.timedOut) {
            try await AnthropicProvider(apiKey: "sk-test", session: slow).complete(request(), model: "claude-haiku-5-5", structured: true)
        }
        let (limited, _) = StubURLProtocol.session([.http(status: 429, body: try aiFixture("gemini-429"))])
        await #expect(throws: AIError.rateLimited) {
            try await GeminiProvider(apiKey: geminiKey, session: limited).complete(request(), model: "gemini-3.8-flash", structured: true)
        }
    }

    // MARK: StructuredAI

    @Test func invalidReplyIsRetriedOnceWithTheProblem() async throws {
        let provider = ScriptedProvider([.success("{\"ok\": false}"), .success("{\"ok\": true}")])
        let result = try await StructuredAI(provider: provider, model: "m")
            .run(ConnectionTest.Reply.self, request: request(), feature: .connectionTest)
        #expect(result.attempts == 2)
        #expect(provider.requests[1].request.userText.contains("<validation_error>Your previous reply was not valid: ok must be true."))
    }

    @Test func twoInvalidRepliesGiveInvalidOutput() async throws {
        let provider = ScriptedProvider([.success("not json"), .success("{\"ok\": false}")])
        await #expect(throws: AIError.invalidOutput("ok must be true")) {
            try await StructuredAI(provider: provider, model: "m").run(ConnectionTest.Reply.self, request: request(), feature: .connectionTest)
        }
        #expect(provider.calls == 2)
    }

    @Test func schemaRejectionFallsBackToPromptMode() async throws {
        let provider = ScriptedProvider([.failure(.badRequest("Invalid schema for response_format")), .success("{\"ok\": true}")])
        let result = try await StructuredAI(provider: provider, model: "m")
            .run(ConnectionTest.Reply.self, request: request(), feature: .connectionTest)
        #expect(result.attempts == 1)
        #expect(provider.requests[1].structured == false)
        #expect(provider.requests[1].request.system.contains("JSON Schema"))
    }

    /// ADR-019: Gemini starts in JSON mode (schema in the prompt); the others start structured.
    @Test func geminiStartsInJSONMode() async throws {
        let gemini = ScriptedProvider(kind: .gemini, [.success("{\"ok\": true}")])
        _ = try await StructuredAI(provider: gemini, model: "m").run(ConnectionTest.Reply.self, request: request(), feature: .connectionTest)
        #expect(gemini.requests.map(\.structured) == [false])
        #expect(gemini.requests[0].request.system.contains("JSON Schema"))
        #expect(!AIProviderKind.gemini.prefersStructuredOutput && AIProviderKind.openai.prefersStructuredOutput)
    }

    @Test func runawayStructuredAnswerFallsBackToPromptMode() async throws {
        for failure in [AIError.timedOut, .truncated] {
            let provider = ScriptedProvider([.failure(failure), .success("{\"ok\": true}")])
            let result = try await StructuredAI(provider: provider, model: "m")
                .run(ConnectionTest.Reply.self, request: request(), feature: .connectionTest)
            #expect(result.attempts == 1)
            #expect(provider.requests.map(\.structured) == [true, false])
        }
    }

    @Test func diagnosticIsRedacted() async throws {
        let provider = ScriptedProvider([.failure(.invalidKey)])
        let recorder = DiagnosticRecorder()
        await #expect(throws: AIError.invalidKey) {
            try await StructuredAI(provider: provider, model: "m", secrets: ["secret-key-123"], onDiagnostic: recorder.record)
                .run(ConnectionTest.Reply.self, request: request(), feature: .connectionTest)
        }
        #expect(recorder.last?.succeeded == false)
        #expect(AIRedactor.redact("x secret-key-123 key=abc AIzaSyA1234567890123456789012", secrets: ["secret-key-123"]) == "x [redacted] key=[redacted] [redacted]")
    }

    // MARK: Deadline, keys, service

    @Test func deadlineReturnsTimedOut() async {
        await #expect(throws: AIError.timedOut) {
            try await AIDeadline.run(seconds: 0.05) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
    }

    @Test func cancellingReturnsCancelled() async {
        let task = Task {
            try await AIDeadline.run(seconds: 30) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
        task.cancel()
        await #expect(throws: AIError.cancelled) { try await task.value }
    }

    @Test func pastedKeysAreCleaned() {
        #expect(AIKeyStore.sanitize("  Bearer AQ.abc\u{200F}def \n") == "AQ.abcdef")
        #expect(AIKeyStore.sanitize("\"sk-ant-xyz\"") == "sk-ant-xyz")
        #expect(AIKeyStore.warnings(for: "sk-ant-0123456789012345678", provider: .gemini) == [.looksLike(.anthropic)])
        #expect(AIKeyStore.warnings(for: "AQ.0123456789012345678", provider: .gemini).isEmpty)
        #expect(AIKeyStore.masked("AQ.Ab123456789xyz9f3c") == "AQ.A…9f3c · 21")
    }

    @Test func keysAndSettingsRoundTrip() throws {
        let store = AIKeyStore(storage: MemoryKeyStorage())
        try store.save(" AIzaFakeKey\u{200E} ", for: .gemini)
        #expect(store.key(for: .gemini) == "AIzaFakeKey")
        store.delete(for: .gemini)
        #expect(!store.hasKey(for: .gemini))

        let defaults = testDefaults()
        var settings = AISettings.load(from: defaults)
        #expect(settings.provider == .gemini)
        #expect(settings.model == "gemini-3.5-flash-lite")
        settings.setConsent(true, for: .gemini)
        settings.models["gemini"] = "gemini-3.5-flash-lite"
        settings.save(to: defaults)
        let loaded = AISettings.load(from: defaults)
        #expect(loaded.hasConsent(for: .gemini))
        #expect(!loaded.hasConsent(for: .openai))
        #expect(loaded.model == "gemini-3.5-flash-lite")
    }

    @Test func serviceWithoutKeyThrowsNoKey() async {
        let service = AIService(keyStore: AIKeyStore(storage: MemoryKeyStorage()), defaults: testDefaults())
        await #expect(throws: AIError.noKey) {
            try await service.run(request: request(), feature: .connectionTest) { $0 }
        }
    }

    @Test func connectionTestThroughTheStub() async throws {
        let (session, _) = StubURLProtocol.session([.http(status: 200, body: try aiFixture("openai-ok"))])
        let service = AIService(keyStore: AIKeyStore(storage: MemoryKeyStorage()), defaults: testDefaults(), session: session)
        #expect(await service.testConnection(provider: .openai, key: " sk-test ", model: "gpt-6-luna") == .success("gpt-6-luna"))
        let (bad, _) = StubURLProtocol.session([.http(status: 401, body: try aiFixture("anthropic-401"))])
        let failing = AIService(keyStore: AIKeyStore(storage: MemoryKeyStorage()), defaults: testDefaults(), session: bad)
        #expect(await failing.testConnection(provider: .anthropic, key: "sk-ant-x", model: "claude-haiku-5-5") == .failure(.invalidKey))
    }
}

/// Collects diagnostics from a run.
final class DiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AIDiagnostic] = []

    var last: AIDiagnostic? { lock.withLock { items.last } }

    func record(_ diagnostic: AIDiagnostic) {
        lock.withLock { items.append(diagnostic) }
    }
}

extension JSONValue {
    var arrayFirst: JSONValue? {
        if case .array(let items) = self { return items.first }
        return nil
    }
}
