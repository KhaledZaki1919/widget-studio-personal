import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKitCore

/// "Use another AI" (ADR-023), inside Create from image: pick and crop the image to the widget
/// (ADR-024) and share the crop, copy self-contained instructions for ChatGPT, Claude or Gemini
/// on the web, then import the JSON they return: a paste opens in the editor; files, a .zip, a folder
/// or several pasted designs go to bulk import (ADR-027). Every import runs the app's own checks,
/// layout fix and auto-wire. Nothing here calls an AI or runs code.
struct ExternalAIView: View {
    let onImported: (SavedDesign, LayoutRepair) -> Void

    @State private var size = SizeChoice.auto
    /// ADR-029: every widget in the image, as {"widgets": [...]}.
    @State private var allWidgets = false
    @State private var copied = false
    @State private var pasted = ""
    @State private var error: ExternalAI.ImportError?
    @State private var fixCopied = false
    @State private var fileUnreadable = false
    /// Files or several pasted designs: bulk import (ADR-027).
    @State private var bulk: BulkRequest?
    /// Crop step (ADR-024).
    @State private var photoItem: PhotosPickerItem?
    @State private var picked: CGImage?
    @State private var detected: [DetectedWidget] = []
    @State private var crop: CGRect?
    @State private var cardShape: WidgetCardShape?
    @State private var showCrop = false
    @State private var croppedFile: URL?
    private let language = RenderContext.preferredLanguage

    var body: some View {
        Form {
            imageSection
            Section {
                Picker("create.size", selection: $size) {
                    Text("create.size.auto").tag(SizeChoice.auto)
                    Text("detail.size.small").tag(SizeChoice.small)
                    Text("detail.size.medium").tag(SizeChoice.medium)
                    Text("detail.size.large").tag(SizeChoice.large)
                    Text("detail.size.xlarge").tag(SizeChoice.xlarge)
                }
                .pickerStyle(.segmented)
                Toggle("create.external.all", isOn: $allWidgets)
                    .accessibilityIdentifier("ax.create.external.all")
                Button {
                    var options = GenerationOptions(size: size, detectedCard: cardShape, cropped: crop != nil)
                    options.allWidgets = allWidgets
                    UIPasteboard.general.string = ExternalAI.instructions(options: options)
                    copied = true
                } label: {
                    Label(copied ? LocalizedStringKey("create.external.copied") : "create.external.copy",
                          systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                }
                .accessibilityIdentifier("ax.create.external.copy")
            } header: {
                Text("create.external.step1")
            } footer: {
                Text("create.external.step1.footer")
            }

            Section {
                Button {
                    importText(UIPasteboard.general.string ?? "")
                } label: {
                    Label("create.external.paste", systemImage: "doc.on.clipboard")
                }
                .accessibilityIdentifier("ax.create.external.paste")
                Button {
                    DocumentPicker.present { bulk = BulkRequest(urls: $0) }
                } label: {
                    Label("create.external.file", systemImage: "doc")
                }
                .accessibilityIdentifier("ax.create.external.file")
                Button {
                    DocumentPicker.present(folder: true) { bulk = BulkRequest(urls: $0) }
                } label: {
                    Label("create.external.folder", systemImage: "folder")
                }
                .accessibilityIdentifier("ax.create.external.folder")
                TextField("create.external.field", text: $pasted, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityIdentifier("ax.create.external.field")
                if !pasted.isEmpty {
                    Button("create.external.import") { importText(pasted) }
                        .accessibilityIdentifier("ax.create.external.import")
                }
            } header: {
                Text("create.external.step2")
            } footer: {
                Text("create.external.step2.footer")
            }

            if let error {
                errorSection(error)
            }
            if fileUnreadable {
                Section {
                    Label("create.external.error.file", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("create.external.title")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $bulk) { BulkImportView(request: $0) }
        .onChange(of: photoItem) { _, item in
            if let item { Task { await load(item) } }
        }
        .sheet(isPresented: $showCrop) {
            if let picked {
                CropView(image: picked, detected: detected, allowsAll: false, onDone: applyCrop) { showCrop = false }
                    .interactiveDismissDisabled()
            }
        }
    }

    // MARK: Image and crop (ADR-024)

    private var imageSection: some View {
        Section {
            if let shown = cropped ?? picked {
                Image(decorative: shown, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowBackground(Color.clear)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(picked == nil ? LocalizedStringKey("create.external.pickImage") : "create.pick.change", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("ax.create.external.pick")
            if picked != nil {
                Button {
                    showCrop = true
                } label: {
                    Label("create.crop.adjust", systemImage: "crop")
                }
            }
            if let croppedFile {
                ShareLink(item: croppedFile) {
                    Label("create.external.shareImage", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("ax.create.external.share")
            }
        } header: {
            Text("create.external.step0")
        } footer: {
            Text("create.external.step0.footer")
        }
    }

    private var cropped: CGImage? {
        guard let picked, let crop else { return nil }
        return WidgetDetector.crop(picked, to: crop)
    }

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = AIImage.upright(data: data) else {
            fileUnreadable = true
            return
        }
        picked = image
        crop = nil
        cardShape = nil
        croppedFile = nil
        detected = await Task.detached(priority: .userInitiated) { WidgetDetector.detect(image) }.value
        showCrop = true
    }

    private func applyCrop(_ choice: CropChoice) {
        showCrop = false
        guard case .one(let rect, let shape, let suggested) = choice else { return }
        crop = rect
        cardShape = shape
        if suggested != .auto { size = suggested }
        // The image to upload to the web chat: the crop (or the whole image), as a PNG file.
        guard let shareable = cropped ?? picked, let data = UIImage(cgImage: shareable).pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-crop.png")
        croppedFile = (try? data.write(to: url, options: .atomic)).map { url }
    }

    private func errorSection(_ error: ExternalAI.ImportError) -> some View {
        Section {
            Label(Self.message(error), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            if case .invalid(let problems) = error {
                Text(verbatim: problems)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)
            }
            Button {
                UIPasteboard.general.string = ExternalAI.fixRequest(for: error)
                fixCopied = true
            } label: {
                Label(fixCopied ? LocalizedStringKey("create.external.fixCopied") : "create.external.copyFix",
                      systemImage: fixCopied ? "checkmark.circle.fill" : "arrow.uturn.left.circle")
            }
            .accessibilityIdentifier("ax.create.external.copyFix")
        } header: {
            Text("create.external.error.title")
        } footer: {
            Text("create.external.error.footer")
        }
        .accessibilityIdentifier("ax.create.external.error")
    }

    private func importText(_ text: String) {
        fileUnreadable = false
        fixCopied = false
        // A JSON array or several objects in one paste (ADR-027).
        if BulkImport.split(text).count > 1 {
            bulk = BulkRequest(text: text)
            return
        }
        do {
            let widget = try ExternalAI.importWidget(text, size: size)
            error = nil
            onImported(widget.design(language: language), widget.layout)
        } catch let importError as ExternalAI.ImportError {
            error = importError
        } catch {
            self.error = .noJSON
        }
    }

    static func message(_ error: ExternalAI.ImportError) -> LocalizedStringKey {
        switch error {
        case .empty: "create.external.error.empty"
        case .tooLarge: "create.external.error.tooLarge"
        case .noJSON: "create.external.error.noJSON"
        case .invalid: "create.external.error.invalid"
        case .unreadable: "create.external.error.file"
        }
    }
}
