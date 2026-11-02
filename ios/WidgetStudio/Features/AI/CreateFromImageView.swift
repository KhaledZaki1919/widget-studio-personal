import PhotosUI
import SwiftUI
import UIKit
import WidgetKitCore

/// Create from image (brief §5, §7.5, M5): pick an image → mode and size → consent (once per
/// provider) → generating (Cancel) → the result opens in the editor (Regenerate) → Save puts it
/// in My widgets. The image goes only to the provider the user chose, with their own key.
struct CreateFromImageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NetworkStatus.self) private var network
    @State private var photoItem: PhotosPickerItem?
    /// Upright, ≤ 2048 px: preview and the photo a "Build around my photo" design keeps.
    @State private var picked: CGImage?
    @State private var isLoadingImage = false
    @State private var imageUnreadable = false
    @State private var options = GenerationOptions()
    @State private var phase: Phase = .setup
    @State private var task: Task<Void, Never>?
    @State private var askConsent = false
    @State private var settings = AISettings.load()
    @State private var step: GenerationStep = .generating

    enum Phase {
        case setup
        case generating
        case failed(AIError)
        case result(design: SavedDesign, photo: CGImage?, layout: LayoutRepair)
    }

    private let service = AIService()
    private let language = RenderContext.preferredLanguage
    /// UI tests (`-uiTestingStubAI`) use a generated sample instead of the photo library.
    private let offersSample = ProcessInfo.processInfo.arguments.contains("-uiTestingStubAI")

    var body: some View {
        switch phase {
        case .result(let design, let photo, let layout):
            EditorView(design: design, isNew: true, photo: photo, layout: layout, onRegenerate: generate)
                .id(design.id)
        default:
            NavigationStack {
                content
                    .navigationTitle("create.title")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.cancel") {
                                task?.cancel()
                                dismiss()
                            }
                            .accessibilityIdentifier("ax.create.close")
                        }
                    }
            }
            .onAppear { settings = AISettings.load() }
            .onChange(of: photoItem) { _, item in
                if let item { Task { await load(item) } }
            }
            .sheet(isPresented: $askConsent) {
                ConsentSheet(providerName: settings.providerName) {
                    settings.setConsent(true, for: settings.provider)
                    settings.save()
                    askConsent = false
                    generate()
                } onCancel: {
                    askConsent = false
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .generating:
            generatingView
        case .failed(let error):
            failedView(error)
        default:
            setupForm
        }
    }

    // MARK: Setup

    private var setupForm: some View {
        Form {
            imageSection
            Section {
                Picker("create.mode", selection: $options.mode) {
                    Text("create.mode.recreate").tag(GenerationMode.recreate)
                    Text("create.mode.photo").tag(GenerationMode.photo)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("ax.create.mode")
            } header: {
                Text("create.mode")
            } footer: {
                Text(options.mode == .recreate ? LocalizedStringKey("create.mode.recreate.footer") : "create.mode.photo.footer")
            }
            Section("create.size") {
                Picker("create.size", selection: $options.size) {
                    Text("create.size.auto").tag(SizeChoice.auto)
                    Text("detail.size.small").tag(SizeChoice.small)
                    Text("detail.size.medium").tag(SizeChoice.medium)
                    Text("detail.size.large").tag(SizeChoice.large)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ax.create.size")
            }
            Section {
                TextField("create.instructions.placeholder", text: $options.instructions, axis: .vertical)
                    .lineLimit(2...5)
                    .onChange(of: options.instructions) { _, text in
                        if text.count > GenerationOptions.maxInstructions {
                            options.instructions = String(text.prefix(GenerationOptions.maxInstructions))
                        }
                    }
                    .accessibilityIdentifier("ax.create.instructions")
            } header: {
                Text("create.instructions")
            }
            Section {
                Button(action: start) {
                    Label("create.generate", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .disabled(picked == nil || isLoadingImage || !network.isOnline)
                .accessibilityIdentifier("ax.create.generate")
                if !network.isOnline {
                    NoticeRow(symbol: "wifi.slash", title: "notice.offline.title", message: "notice.offline.body")
                        .accessibilityIdentifier("ax.create.offline")
                }
                if !service.hasKey {
                    Label("create.noKey", systemImage: "key")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    keyGuideLink
                    settingsLink
                }
            } footer: {
                Text("create.provider \(settings.providerName) \(settings.model)")
            }
        }
    }

    private var imageSection: some View {
        Section {
            if let picked {
                Image(decorative: picked, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("ax.create.image")
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(picked == nil ? LocalizedStringKey("create.pick") : "create.pick.change", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("ax.create.pick")
            if offersSample {
                Button {
                    picked = Self.sampleImage()
                } label: {
                    Label("create.sample", systemImage: "wand.and.stars")
                }
                .accessibilityIdentifier("ax.create.sample")
            }
            if isLoadingImage { ProgressView() }
            if imageUnreadable {
                Text("create.imageUnreadable").font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text("create.pick.footer")
        }
    }

    private var keyGuideLink: some View {
        NavigationLink {
            FreeKeyGuideView()
                .onDisappear { settings = AISettings.load() }
        } label: {
            Label("create.getFreeKey", systemImage: "gift")
        }
        .accessibilityIdentifier("ax.create.keyGuide")
    }

    private var settingsLink: some View {
        NavigationLink {
            AISettingsView()
                .onDisappear { settings = AISettings.load() }
        } label: {
            Label("create.openSettings", systemImage: "gearshape")
        }
        .accessibilityIdentifier("ax.create.settings")
    }

    // MARK: Generating and errors

    private var generatingView: some View {
        VStack(spacing: 18) {
            Spacer()
            if let picked {
                Image(decorative: picked, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(0.6)
            }
            ProgressView()
                .controlSize(.large)
            Text(step == .reviewing ? LocalizedStringKey("create.reviewing") : "create.generating").font(.headline)
            Text(step == .reviewing ? LocalizedStringKey("create.reviewing.detail") : "create.generating.detail \(settings.providerName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("common.cancel", role: .cancel) {
                task?.cancel()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("ax.create.cancel")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("ax.create.generating")
    }

    private func failedView(_ error: AIError) -> some View {
        Form {
            Section {
                AIErrorView(error: error, provider: settings.provider)
            } header: {
                Text("create.failed")
            }
            Section {
                Button {
                    generate()
                } label: {
                    Label("create.retry", systemImage: "arrow.clockwise")
                }
                .disabled(error == .noKey)
                .accessibilityIdentifier("ax.create.retry")
                Button {
                    phase = .setup
                } label: {
                    Label("create.back", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("ax.create.back")
                if error == .noKey { keyGuideLink }
                if error.needsSettings { settingsLink }
            }
        }
    }

    // MARK: Actions

    private func load(_ item: PhotosPickerItem) async {
        isLoadingImage = true
        imageUnreadable = false
        defer { isLoadingImage = false }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = AIImage.upright(data: data) else {
            imageUnreadable = true
            return
        }
        picked = image
    }

    /// Checks the key and the consent for this provider, then generates.
    private func start() {
        settings = AISettings.load()
        guard service.hasKey else {
            phase = .failed(.noKey)
            return
        }
        // UI tests use a stub provider, but still go through the consent sheet.
        guard settings.hasConsent(for: settings.provider) else {
            askConsent = true
            return
        }
        generate()
    }

    /// Runs (or re-runs, for Regenerate) with the same image and options.
    private func generate() {
        guard let picked, let prepared = AIImage.prepare(image: picked) else {
            phase = .setup
            return
        }
        task?.cancel()
        phase = .generating
        let options = options
        let language = language
        step = .generating
        // "High quality (2 requests)": render the result and let the model correct it once (ADR-019).
        let photo = options.mode == .photo ? picked : nil
        var review: SpecRenderer?
        if settings.usesHighQuality(for: settings.provider) {
            review = { spec, colors in
                await MainActor.run { () -> PreparedImage? in
                    guard let image = SpecSnapshot.render(spec, colors: colors, language: "en", userImage: photo) else { return nil }
                    return AIImage.prepare(image: image)
                }
            }
        }
        task = Task {
            do {
                let generated = try await WidgetGenerator(service: service).generate(image: prepared, options: options, review: review) { next in
                    Task { @MainActor in step = next }
                }
                let design = generated.design(language: language)
                var photo: CGImage?
                if options.mode == .photo, let slot = design.imageLayer {
                    photo = ImageProcessing.prepare(picked, frame: slot.frame, layer: slot.layer)
                }
                phase = .result(design: design, photo: photo, layout: generated.layout)
            } catch AIError.cancelled {
                phase = .setup
            } catch let error as AIError {
                phase = .failed(error)
            } catch {
                phase = .failed(.network)
            }
        }
    }

    /// A widget-like sample for UI tests (no photo library on CI Simulators).
    static func sampleImage() -> CGImage? {
        let size = CGSize(width: 600, height: 600)
        return UIGraphicsImageRenderer(size: size, format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor(red: 0.06, green: 0.08, blue: 0.1, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 120).fill()
            UIColor(red: 1, green: 0.35, blue: 0.21, alpha: 1).setFill()
            context.fill(CGRect(x: 120, y: 420, width: 360, height: 40))
        }.cgImage
    }
}

/// Asked before the first image goes to a provider (brief §5 step 3); revocable in Settings → AI.
private struct ConsentSheet: View {
    let providerName: String
    let onAllow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                    Text("create.consent.body \(providerName)")
                        .font(.body)
                    Label("create.consent.points", systemImage: "photo.badge.checkmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Label("create.consent.revoke", systemImage: "hand.raised")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(action: onAllow) {
                        Text("create.consent.allow")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    .accessibilityIdentifier("ax.create.consent.allow")
                }
                .padding(20)
            }
            .navigationTitle("create.consent.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", action: onCancel)
                        .accessibilityIdentifier("ax.create.consent.cancel")
                }
            }
        }
    }
}
