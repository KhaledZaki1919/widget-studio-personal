import SwiftUI
import UIKit
import WidgetKitCore

/// Settings → AI (brief §7.6, ADR-018): provider, API key in the Keychain (show/hide), Test
/// connection, model, image-upload consent per provider (revocable), and the last request's
/// diagnostic. Keys never leave the device except in the request to the chosen provider.
struct AISettingsView: View {
    @State private var settings = AISettings.load()
    @State private var keyDraft = ""
    @State private var storedKey: String?
    @State private var showKey = false
    @State private var liveModels: [String] = []
    @State private var testState: TestState = .idle
    @State private var testTask: Task<Void, Never>?
    @State private var testID: UUID?
    @State private var diagnostic = AIDiagnosticsStore.load()

    private let keyStore = AIKeyStore()

    enum TestState: Equatable {
        case idle, running
        case passed(model: String)
        case failed(AIError)
    }

    private var provider: AIProviderKind { settings.provider }
    private var availableModels: [String] { liveModels.isEmpty ? provider.builtInModels : liveModels }

    var body: some View {
        Form {
            providerSection
            if provider == .custom { customSection }
            keySection
            if storedKey != nil { testSection }
            modelSection
            consentSection
            diagnosticsSection
        }
        .navigationTitle("ai.title")
        .onAppear(perform: reload)
        .onChange(of: settings) { _, new in new.save() }
        .onChange(of: settings.provider) { _, _ in reload() }
    }

    // MARK: Sections

    private var providerSection: some View {
        Section {
            Picker("ai.provider", selection: $settings.provider) {
                ForEach(AIProviderKind.allCases) { kind in
                    Self.label(kind).tag(kind)
                }
            }
            .accessibilityIdentifier("ax.ai.provider")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("ai.privacy \(settings.providerName)")
                if provider.hasFreeTier { Text("ai.provider.free") }
            }
        }
    }

    /// Custom (OpenAI-compatible): the endpoint's base URL (M6.1).
    private var customSection: some View {
        Section {
            TextField("ai.custom.url.placeholder", text: $settings.customBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.callout.monospaced())
                .accessibilityIdentifier("ax.ai.custom.url")
            if !settings.customBaseURL.isEmpty && CustomEndpoint.normalized(settings.customBaseURL) == nil {
                Label("ai.custom.url.invalid", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("ai.custom.url")
        } footer: {
            Text("ai.custom.url.footer")
        }
    }

    /// The provider's name in lists: product names stay Latin; Custom is localized.
    static func label(_ kind: AIProviderKind) -> Text {
        kind == .custom ? Text("ai.provider.custom") : Text(verbatim: kind.displayName)
    }

    private var keySection: some View {
        Section {
            if let storedKey {
                LabeledContent("ai.key.saved") {
                    Text(verbatim: showKey ? storedKey : AIKeyStore.masked(storedKey))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("ax.ai.key.masked")
                }
                showHideButton
                keyWarnings(storedKey)
                Button("ai.key.delete", role: .destructive) {
                    keyStore.delete(for: provider)
                    reload()
                }
                .accessibilityIdentifier("ax.ai.key.delete")
            } else {
                HStack {
                    Group {
                        if showKey {
                            TextField("ai.key.placeholder", text: $keyDraft)
                        } else {
                            SecureField("ai.key.placeholder", text: $keyDraft)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .font(.callout.monospaced())
                    .accessibilityIdentifier("ax.ai.key")
                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(showKey ? Text("ai.key.hide") : Text("ai.key.show"))
                    .accessibilityIdentifier("ax.ai.key.toggle")
                }
                let clean = AIKeyStore.sanitize(keyDraft)
                if !clean.isEmpty {
                    Text(verbatim: AIKeyStore.masked(clean))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                    keyWarnings(clean)
                }
                Button("ai.key.save") {
                    try? keyStore.save(keyDraft, for: provider)
                    keyDraft = ""
                    reload()
                    startTest()
                }
                .disabled(clean.isEmpty)
                .accessibilityIdentifier("ax.ai.saveKey")
            }
            if storedKey == nil && provider == .gemini {
                NavigationLink {
                    FreeKeyGuideView()
                } label: {
                    Label("create.getFreeKey", systemImage: "gift")
                }
                .accessibilityIdentifier("ax.ai.keyGuide")
            } else if let url = provider.keyPageURL {
                Link(destination: url) {
                    Label("ai.key.get", systemImage: "arrow.up.forward.square")
                }
            }
        } header: {
            Text("ai.key.title")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if provider == .gemini { Text("ai.key.gemini.hint") }
                Text("ai.key.footer")
            }
        }
    }

    private var showHideButton: some View {
        Button {
            showKey.toggle()
        } label: {
            Label(showKey ? LocalizedStringKey("ai.key.hide") : "ai.key.show", systemImage: showKey ? "eye.slash" : "eye")
        }
        .accessibilityIdentifier("ax.ai.key.toggle")
    }

    private var testSection: some View {
        Section {
            Button {
                startTest()
            } label: {
                HStack {
                    Text("ai.test")
                    Spacer()
                    if testState == .running { ProgressView() }
                }
            }
            .disabled(testState == .running)
            .accessibilityIdentifier("ax.ai.test")
            if testState == .running {
                Button("ai.test.cancel", role: .cancel) { testTask?.cancel() }
                    .accessibilityIdentifier("ax.ai.test.cancel")
            }
            switch testState {
            case .idle, .running:
                EmptyView()
            case .passed(let model):
                Label {
                    Text("ai.test.passed \(model)")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.callout)
                .accessibilityIdentifier("ax.ai.test.passed")
            case .failed(let error):
                AIErrorView(error: error, provider: provider)
            }
        }
    }

    private var modelSection: some View {
        Section {
            NavigationLink {
                AIModelPickerView(
                    selection: Binding(
                        get: { settings.model(for: provider) },
                        set: { settings.models[provider.rawValue] = $0 }
                    ),
                    models: availableModels,
                    recommended: provider.recommendedModel,
                    isLiveList: !liveModels.isEmpty
                )
            } label: {
                LabeledContent("ai.model") {
                    Text(verbatim: settings.model(for: provider).isEmpty ? "—" : settings.model(for: provider))
                }
            }
            .accessibilityIdentifier("ax.ai.model")
            Toggle("ai.highQuality", isOn: Binding(
                get: { settings.usesHighQuality(for: provider) },
                set: { settings.highQuality[provider.rawValue] = $0 }
            ))
            .accessibilityIdentifier("ax.ai.highQuality")
        } header: {
            Text("ai.model.title")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("ai.model.footer")
                Text("ai.highQuality.footer")
            }
        }
    }

    private var consentSection: some View {
        Section {
            if settings.consented.isEmpty {
                Text("ai.consent.none").foregroundStyle(.secondary)
            }
            ForEach(AIProviderKind.allCases.filter { settings.hasConsent(for: $0) }) { kind in
                Toggle(isOn: Binding(
                    get: { settings.hasConsent(for: kind) },
                    set: { settings.setConsent($0, for: kind) }
                )) {
                    Self.label(kind)
                }
                .accessibilityIdentifier("ax.ai.consent.\(kind.rawValue)")
            }
        } header: {
            Text("ai.consent.title")
        } footer: {
            Text("ai.consent.footer")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            NavigationLink {
                AIDiagnosticView(diagnostic: diagnostic)
            } label: {
                LabeledContent("ai.diag.title") {
                    if let diagnostic {
                        Text(diagnostic.succeeded ? LocalizedStringKey("ai.diag.success") : "ai.diag.failed")
                    } else {
                        Text("ai.diag.none")
                    }
                }
            }
            .accessibilityIdentifier("ax.ai.diagnostics")
        } footer: {
            Text("ai.diag.footer")
        }
    }

    /// Format hints for a key (never block saving).
    @ViewBuilder private func keyWarnings(_ key: String) -> some View {
        ForEach(Array(AIKeyStore.warnings(for: key, provider: provider).enumerated()), id: \.offset) { _, warning in
            Label {
                warningText(warning)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.footnote)
            .accessibilityIdentifier("ax.ai.key.warning")
        }
    }

    private func warningText(_ warning: AIKeyWarning) -> Text {
        switch warning {
        case .looksLike(let owner):
            Text("ai.key.warn.looksLike \(owner.displayName) \(provider.displayName)")
        case .unexpectedFormat:
            Text("ai.key.warn.format \(provider.keyPrefixes.map { "\($0)…" }.joined(separator: " / "))")
        case .unexpectedCharacters:
            Text("ai.key.warn.characters")
        case .tooShort:
            Text("ai.key.warn.short")
        }
    }

    // MARK: Actions

    private func reload() {
        storedKey = keyStore.key(for: provider)
        showKey = false
        testTask?.cancel()
        testTask = nil
        testID = nil
        testState = .idle
        liveModels = []
        diagnostic = AIDiagnosticsStore.load()
        if let key = storedKey {
            let kind = provider
            Task {
                let models = await AIService().listModels(provider: kind, key: key, customBaseURL: settings.customBaseURL)
                if kind == provider { liveModels = models }
            }
        }
    }

    /// Runs the test in a task the Cancel button can stop. `testConnection` always returns
    /// (answer, error, 30 s timeout or cancellation), so the spinner always stops.
    private func startTest() {
        testTask?.cancel()
        guard let key = storedKey ?? keyStore.key(for: provider) else {
            testState = .idle
            return
        }
        testState = .running
        let kind = provider
        let model = settings.model(for: kind)
        let id = UUID()
        testID = id
        testTask = Task {
            let result = await AIService().testConnection(provider: kind, key: key, model: model, customBaseURL: settings.customBaseURL)
            guard testID == id else { return }   // a newer test (or a provider change) replaced this one
            switch result {
            case .success(let model): testState = .passed(model: model)
            case .failure(.cancelled): testState = .idle
            case .failure(let error): testState = .failed(error)
            }
            diagnostic = AIDiagnosticsStore.load()
            testTask = nil
        }
    }
}

/// Model list (live from the provider when a key is set) plus a custom model ID.
struct AIModelPickerView: View {
    @Binding var selection: String
    let models: [String]
    let recommended: String
    let isLiveList: Bool

    @State private var custom = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("ai.model.custom", text: $custom)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                        .accessibilityIdentifier("ax.ai.model.custom")
                    Button("ai.model.use") {
                        selection = custom.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("ai.model.customFooter")
            }
            Section {
                ForEach(models, id: \.self) { model in
                    Button {
                        selection = model
                        dismiss()
                    } label: {
                        HStack {
                            Text(verbatim: model).font(.callout.monospaced()).foregroundStyle(.primary)
                            if model == recommended {
                                Text("ai.model.recommended")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            }
                            Spacer()
                            if model == selection { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                }
            } footer: {
                Text(isLiveList ? LocalizedStringKey("ai.model.liveFooter") : "ai.model.builtInFooter")
            }
        }
        .navigationTitle("ai.model")
    }
}

/// Settings → AI → Last AI request: what happened, without key or image; copyable.
struct AIDiagnosticView: View {
    let diagnostic: AIDiagnostic?

    var body: some View {
        List {
            if let diagnostic {
                Section {
                    Text(verbatim: diagnostic.report())
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                Section {
                    Button {
                        UIPasteboard.general.string = diagnostic.report()
                    } label: {
                        Label("ai.diag.copy", systemImage: "doc.on.doc")
                    }
                }
            } else {
                Text("ai.diag.none").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("ai.diag.title")
    }
}
