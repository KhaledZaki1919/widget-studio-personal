import Foundation
import Testing
@testable import WidgetKitCore

/// Prompt v2 and the self-review round (ADR-019), with scripted providers (no network).
@Suite(.serialized)
struct ReviewRoundTests {
    let image = PreparedImage(jpeg: Data([0xFF, 0xD8, 0x01]), width: 800, height: 800)
    let render = PreparedImage(jpeg: Data([0xFF, 0xD8, 0x02]), width: 510, height: 510)

    func reply(_ name: String) throws -> String {
        String(decoding: try aiFixture(name), as: UTF8.self)
    }

    /// The recreate reply with a `differences` list and a new name, as a review answer.
    func reviewedReply() throws -> String {
        var object = try #require(try JSONSerialization.jsonObject(with: aiFixture("spec-recreate")) as? [String: Any])
        object["name"] = ["en": "Reviewed", "ar": "بعد المراجعة"]
        object["differences"] = ["Added the weekday row", "Moved the title up"]
        object["inventory"] = ["title AUG top-left"]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    func generator(_ provider: ScriptedProvider) -> WidgetGenerator {
        WidgetGenerator(service: AIService(keyStore: AIKeyStore(storage: MemoryKeyStorage()), defaults: testDefaults(), provider: provider))
    }

    // MARK: Prompt v3 (v2 + stacks, M6.1)

    @Test func promptAsksForInventoryFidelityAndStacks() {
        #expect(WidgetPrompt.version == "generate_v3")
        #expect(WidgetPrompt.system.contains("Never give a text its own absolute frame"))
        #expect(WidgetPrompt.system.contains("`spacer`") && WidgetPrompt.system.contains("`alignItems`"))
        let system = WidgetPrompt.system
        #expect(system.contains("Inventory first"))
        #expect(system.contains("Never replace visible text or numbers with dots"))
        #expect(system.contains("calendarMonth") && system.contains("progressBar") && system.contains("`list`"))
        #expect(system.contains("{{date.MMM}}"))
        #expect(system.contains("handwritten or rounded-casual → `hand`"))
        #expect(system.contains("x = fraction × canvas width"))
        #expect(!WidgetPrompt.review.isEmpty)
    }

    @Test func schemaHasInventoryAndReviewDifferences() {
        let plain = AIWidgetSchema.schema(mode: .recreate)
        #expect(plain["properties"]?["inventory"] != nil)
        #expect(plain["properties"]?["differences"] == nil)
        #expect(AIWidgetSchema.schema(mode: .recreate, review: true)["properties"]?["differences"] != nil)
    }

    @Test func parserDropsInventoryAndDifferences() throws {
        let (spec, _) = try AIWidgetParser.parse(try reviewedReply(), options: GenerationOptions(), id: "gen.review")
        let json = String(decoding: try JSONEncoder().encode(spec), as: UTF8.self)
        #expect(!json.contains("inventory") && !json.contains("differences"))
        #expect(AIWidgetParser.differences(in: try reviewedReply()) == ["Added the weekday row", "Moved the title up"])
    }

    @Test func reviewRequestCarriesBothImagesAndTheSpec() throws {
        let (spec, colors) = try AIWidgetParser.parse(try reply("spec-recreate"), options: GenerationOptions(), id: "gen.review")
        let request = WidgetPrompt.reviewRequest(options: GenerationOptions(), image: image, render: render, spec: spec, colors: colors)
        #expect(request.images == [image.jpeg, render.jpeg])
        #expect(request.userText.hasPrefix("Review round."))
        #expect(request.userText.contains("<current_spec>") && request.userText.contains("\"palette\""))
        #expect(request.userText.contains("<original_task>"))
        #expect(!request.userText.contains("\"id\""))
        #expect(request.schema["properties"]?["differences"] != nil)
    }

    // MARK: Review round

    @Test func reviewRoundReplacesTheFirstResult() async throws {
        let provider = ScriptedProvider([.success(try reply("spec-recreate")), .success(try reviewedReply())])
        let steps = StepRecorder()
        let result = try await generator(provider).generate(image: image, options: GenerationOptions(), review: { _, _ in render },
                                                            onStep: steps.record)
        #expect(result.reviewed)
        #expect(result.attempts == 2)
        #expect(result.spec.name.resolved(language: "en") == "Reviewed")
        #expect(result.differences.count == 2)
        #expect(provider.requests[1].request.images.count == 2)
        #expect(provider.requests[1].request.userText.contains("Review round."))
        #expect(steps.all == [.generating, .reviewing])
    }

    @Test func failedReviewKeepsTheFirstResult() async throws {
        let provider = ScriptedProvider([.success(try reply("spec-recreate")), .success("{}"), .success("not json")])
        let result = try await generator(provider).generate(image: image, options: GenerationOptions(), review: { _, _ in render })
        #expect(!result.reviewed)
        #expect(result.spec.name.resolved(language: "en") == "Clock")
        #expect(provider.calls == 3)
    }

    @Test func noRendererMeansOneRequest() async throws {
        let provider = ScriptedProvider([.success(try reply("spec-recreate"))])
        let result = try await generator(provider).generate(image: image, options: GenerationOptions(), review: { _, _ in nil })
        #expect(!result.reviewed)
        #expect(provider.calls == 1)
    }

    @Test func highQualityDefaultsPerProvider() {
        var settings = AISettings()
        #expect(!settings.usesHighQuality(for: .gemini))
        #expect(settings.usesHighQuality(for: .anthropic) && settings.usesHighQuality(for: .openai) && settings.usesHighQuality(for: .openrouter))
        settings.highQuality["gemini"] = true
        let defaults = testDefaults()
        settings.save(to: defaults)
        #expect(AISettings.load(from: defaults).usesHighQuality(for: .gemini))
    }
}

final class StepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [GenerationStep] = []

    var all: [GenerationStep] { lock.withLock { steps } }

    func record(_ step: GenerationStep) {
        lock.withLock { steps.append(step) }
    }
}
