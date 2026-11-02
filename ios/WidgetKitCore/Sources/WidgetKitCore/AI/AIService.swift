import Foundation

/// The app's single entry point to AI (ADR-008): picks the provider, key and model from the
/// settings, runs `StructuredAI` under a hard deadline, and stores the "Last AI request"
/// diagnostic. Without a key every call throws `AIError.noKey`. Lives in the package for the
/// tests; only the app calls it, never the widget extension.
public final class AIService: @unchecked Sendable {
    private let keyStore: AIKeyStore
    private let defaults: UserDefaults
    private let session: URLSession
    /// A fixed provider (tests); no key needed.
    private let fixedProvider: AIProvider?

    /// Settings → AI "Test connection" and the model list.
    public var testTimeout: TimeInterval = 30
    /// Widget generation, including the retry (each URL request also times out after 180 s).
    public var generationTimeout: TimeInterval = 240
    /// false starts in prompt-only JSON mode; the app always starts structured (AI eval knob).
    public var structuredFirst = true

    public init(keyStore: AIKeyStore = AIKeyStore(), defaults: UserDefaults = .standard, session: URLSession = .shared,
                provider: AIProvider? = nil) {
        self.keyStore = keyStore
        self.defaults = defaults
        self.session = session
        fixedProvider = provider
    }

    /// UI tests only (`-uiTestingStubAI`): requests go to this provider and no key is required.
    public nonisolated(unsafe) static var overrideProvider: AIProvider?

    public var settings: AISettings { AISettings.load(from: defaults) }

    public var hasKey: Bool {
        if activeOverride != nil { return true }
        let settings = settings
        return keyStore.hasKey(for: settings.provider) && (settings.provider != .custom || settings.isCustomReady)
    }

    private var activeOverride: AIProvider? { fixedProvider ?? Self.overrideProvider }

    /// A structured request with the selected provider, key and model.
    public func run<Value>(
        request: AIRequest, feature: AIFeature, parse: @escaping @Sendable (String) throws -> Value
    ) async throws -> StructuredResult<Value> {
        let settings = settings
        let provider: AIProvider
        var secrets: [String] = []
        if let override = activeOverride {
            provider = override
        } else {
            guard let key = keyStore.key(for: settings.provider),
                  settings.provider != .custom || settings.isCustomReady else { throw AIError.noKey }
            provider = settings.provider.makeProvider(apiKey: key, session: session, customBaseURL: settings.customBaseURL)
            secrets = [key]
        }
        return try await guarded(request: request, feature: feature, provider: provider, model: settings.model,
                                 secrets: secrets, seconds: generationTimeout, parse: parse)
    }

    /// Settings → AI "Test connection" with the given provider, key and model. Returns within
    /// `testTimeout`; cancelling the calling task returns `.cancelled`.
    public func testConnection(provider: AIProviderKind, key: String, model: String, customBaseURL: String = "") async -> Result<String, AIError> {
        let clean = AIKeyStore.sanitize(key)
        do {
            let result = try await guarded(
                request: ConnectionTest.request, feature: .connectionTest,
                provider: provider.makeProvider(apiKey: clean, session: session, customBaseURL: customBaseURL), model: model,
                secrets: [clean, key], seconds: testTimeout
            ) { text in
                let reply = try StructuredAI.decode(ConnectionTest.Reply.self, from: text)
                try reply.validate()
                return reply
            }
            return .success(result.model)
        } catch let error as AIError {
            return .failure(error)
        } catch {
            return .failure(.network)
        }
    }

    /// The provider's live model list, or [] on any failure or after `testTimeout`.
    public func listModels(provider: AIProviderKind, key: String, customBaseURL: String = "") async -> [String] {
        let client = provider.makeProvider(apiKey: AIKeyStore.sanitize(key), session: session, customBaseURL: customBaseURL)
        return (try? await AIDeadline.run(seconds: testTimeout) { try await client.listModels() }) ?? []
    }

    /// `StructuredAI` under a deadline. A timeout or cancellation writes its own diagnostic and
    /// silences the abandoned run, so a late answer can't overwrite it.
    private func guarded<Value>(
        request: AIRequest, feature: AIFeature, provider: AIProvider, model: String,
        secrets: [String], seconds: TimeInterval, parse: @escaping @Sendable (String) throws -> Value
    ) async throws -> StructuredResult<Value> {
        let latch = DiagnosticLatch(UncheckedDefaults(defaults))
        let trace = AITrace()
        let started = Date()
        let ai = StructuredAI(provider: provider, model: model, secrets: secrets, structuredFirst: structuredFirst,
                              onDiagnostic: { latch.save($0) })
        do {
            return try await AIDeadline.run(seconds: seconds) {
                try await ai.run(request: request, feature: feature, trace: trace, parse: parse)
            }
        } catch let error as AIError where error == .timedOut || error == .cancelled {
            let timedOut = error == .timedOut
            latch.close(with: AIDiagnostic(
                date: started,
                provider: provider.kind,
                model: model,
                feature: feature,
                endpoint: trace.endpoint.map { AIRedactor.redact($0, secrets: secrets) },
                httpStatus: trace.status,
                failedStep: timedOut ? .timeout : .cancelled,
                attempts: 1,
                durationMs: Int(Date().timeIntervalSince(started) * 1000),
                message: timedOut ? "No answer within \(Int(seconds)) s" : "Cancelled",
                errorBody: nil,
                replyExcerpt: nil
            ))
            throw error
        }
    }
}

/// UserDefaults is thread-safe but not marked Sendable.
private struct UncheckedDefaults: @unchecked Sendable {
    let value: UserDefaults
    init(_ value: UserDefaults) { self.value = value }
}

/// Saves diagnostics until a timeout/cancellation closes it with its own.
private final class DiagnosticLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private let defaults: UncheckedDefaults

    init(_ defaults: UncheckedDefaults) {
        self.defaults = defaults
    }

    func save(_ diagnostic: AIDiagnostic) {
        lock.withLock {
            guard !closed else { return }
            AIDiagnosticsStore.save(diagnostic, to: defaults.value)
        }
    }

    func close(with diagnostic: AIDiagnostic) {
        lock.withLock {
            closed = true
            AIDiagnosticsStore.save(diagnostic, to: defaults.value)
        }
    }
}
