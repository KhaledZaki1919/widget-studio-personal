import Foundation
import Testing
@testable import WidgetKitCore

/// M6.1: NVIDIA NIM, Groq and Custom (OpenAI-compatible) providers; free presets (ADR-022).
@Suite(.serialized)
struct ProviderPresetsTests {
    let request = AIRequest(system: "system", userText: "user", images: [Data([0xFF, 0xD8])],
                            schema: JSONSchema.object(["ok": JSONSchema.boolean]), schemaName: "connection_test")

    @Test func presetsHaveEndpointsAndVisionModels() {
        #expect(AIProviderKind.nvidia.baseURL == "https://integrate.api.nvidia.com/v1")
        #expect(AIProviderKind.groq.baseURL == "https://api.groq.com/openai/v1")
        #expect(AIProviderKind.nvidia.recommendedModel == "nvidia/nemotron-3.5-super-vl-120b-a12b")
        #expect(AIProviderKind.groq.recommendedModel == "qwen/qwen3.8-27b")
        #expect(AIProviderKind.openrouter.builtInModels.contains("nvidia/nemotron-3.5-super-vl:free"))
        // ADR-022: the free providers default to free vision models (AI eval 2026-11-01/02).
        #expect(AIProviderKind.gemini.recommendedModel == "gemini-3.5-flash-lite")
        #expect(AIProviderKind.openrouter.recommendedModel.hasSuffix(":free"))
        #expect(AIProviderKind.openrouter.alternativeModel == "openrouter/free")
        #expect(AIProviderKind.allCases.filter(\.hasFreeTier) == [.gemini, .nvidia, .groq, .openrouter])
        #expect(!AIProviderKind.nvidia.prefersStructuredOutput && !AIProviderKind.custom.prefersStructuredOutput)
        #expect(AIProviderKind.groq.prefersStructuredOutput)
    }

    @Test func compatibleBodies() {
        let nim = OpenAICompatibleProvider(kind: .nvidia, apiKey: "k")
        let plain = nim.body(for: request, model: "m", structured: false, reasoning: false)
        #expect(plain["response_format"] == nil)
        #expect(plain["max_tokens"] == 2048)
        let groq = OpenAICompatibleProvider(kind: .groq, apiKey: "k").body(for: request, model: "m", structured: true, reasoning: false)
        #expect(groq["response_format"] == ["type": "json_object"])
    }

    @Test func customEndpointsAreNormalized() {
        #expect(CustomEndpoint.normalized("https://host.ai/v1/") == "https://host.ai/v1")
        #expect(CustomEndpoint.normalized(" https://host.ai/v1/chat/completions ") == "https://host.ai/v1")
        #expect(CustomEndpoint.normalized("http://localhost:1234/v1") == "http://localhost:1234/v1")
        #expect(CustomEndpoint.normalized("http://host.ai/v1") == nil)
        #expect(CustomEndpoint.normalized("host.ai/v1") == nil)
        #expect(CustomEndpoint.normalized("") == nil)
    }

    @Test func customProviderNeedsURLAndModel() async {
        var settings = AISettings(provider: .custom)
        #expect(!settings.isCustomReady)
        settings.customBaseURL = "https://llm.example.com/v1"
        #expect(!settings.isCustomReady)
        settings.models["custom"] = "my-vlm"
        #expect(settings.isCustomReady)
        #expect(settings.providerName == "llm.example.com")

        let keys = AIKeyStore(storage: MemoryKeyStorage())
        try? keys.save("local-token", for: .custom)
        let defaults = testDefaults()
        AISettings(provider: .custom, customBaseURL: "https://llm.example.com/v1").save(to: defaults)
        let service = AIService(keyStore: keys, defaults: defaults)
        #expect(!service.hasKey)
        await #expect(throws: AIError.noKey) {
            try await service.run(request: request, feature: .connectionTest) { $0 }
        }
    }

    @Test func keyFormats() {
        #expect(AIProviderKind.owner(ofKey: "nvapi-0123456789abcdef0123") == .nvidia)
        #expect(AIProviderKind.owner(ofKey: "gsk_0123456789abcdef0123") == .groq)
        #expect(AIKeyStore.warnings(for: "gsk_0123456789abcdef0123", provider: .nvidia) == [.looksLike(.groq)])
        #expect(AIKeyStore.warnings(for: "tok", provider: .custom).isEmpty)
        #expect(AIRedactor.redact("x nvapi-abcdefghijklmnop y gsk_abcdefghijklmnop") == "x [redacted] y [redacted]")
    }
}

/// In the serialized client suite, because it shares the URL stub with it.
extension AIClientTests {
    @Test func requestsGoToTheProviderEndpoint() async throws {
        for (kind, url) in [(AIProviderKind.nvidia, "https://integrate.api.nvidia.com/v1/chat/completions"),
                            (.groq, "https://api.groq.com/openai/v1/chat/completions")] {
            let (session, id) = StubURLProtocol.session([.http(status: 200, body: try aiFixture("openai-ok"))])
            let provider = kind.makeProvider(apiKey: "fake-key", session: session)
            _ = try await provider.complete(presetRequest, model: kind.recommendedModel, structured: false)
            let sent = try #require(StubURLProtocol.requests(id).last)
            #expect(sent.url?.absoluteString == url)
            #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer fake-key")
        }
        let (session, id) = StubURLProtocol.session([.http(status: 200, body: try aiFixture("openai-ok"))])
        let custom = AIProviderKind.custom.makeProvider(apiKey: "local", session: session, customBaseURL: "https://llm.example.com/v1/chat/completions")
        _ = try await custom.complete(presetRequest, model: "my-vlm", structured: false)
        #expect(StubURLProtocol.requests(id).last?.url?.absoluteString == "https://llm.example.com/v1/chat/completions")
    }

    var presetRequest: AIRequest {
        AIRequest(system: "system", userText: "user", images: [Data([0xFF, 0xD8])],
                  schema: JSONSchema.object(["ok": JSONSchema.boolean]), schemaName: "connection_test")
    }
}
