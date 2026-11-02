import PhotosUI
import SwiftUI
import WidgetKitCore

/// The editor (brief §7.3, M3): a live preview at real size above every field the template
/// defines, theme, colors, photo and the layer editor (M6.1). Save validates the design and puts
/// it in My widgets. AI results say when their layout was fixed or still needs the layer editor
/// (ADR-022).
struct EditorView: View {
    @Environment(DesignsModel.self) private var designs
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditorModel
    @State private var saveError: String?

    /// Shown for AI results (M5): a new design from the same image and options.
    private let onRegenerate: (() -> Void)?
    /// AI results (ADR-022): what the local layout fix did.
    private let layout: LayoutRepair

    init(design: SavedDesign, isNew: Bool, photo: CGImage? = nil, layout: LayoutRepair = .clean,
         onRegenerate: (() -> Void)? = nil) {
        _model = State(initialValue: EditorModel(design: design, isNew: isNew, photo: photo))
        self.layout = layout
        self.onRegenerate = onRegenerate
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                previewSection
                layoutSection
                if let onRegenerate {
                    Section {
                        Button(action: onRegenerate) {
                            Label("create.regenerate", systemImage: "arrow.clockwise")
                        }
                        .accessibilityIdentifier("ax.editor.regenerate")
                    } footer: {
                        Text("create.regenerate.footer")
                    }
                }
                // Personal build (docs/personal.md)
                UseOnHomeScreenSection(design: model.design, photo: model.newPhoto ?? designs.image(for: model.design),
                                       enabled: model.canSave)
                Section("editor.name") {
                    TextField("editor.name", text: $model.design.name)
                        .accessibilityIdentifier("ax.editor.name")
                }
                if model.hasPhoto { photoSection }
                appearanceSection
                layersSection
                if !model.editableFields.isEmpty {
                    Section("editor.fields") {
                        ForEach(model.editableFields, id: \.key) { field in
                            FieldEditor(field: field, model: model)
                        }
                    }
                }
                if !model.issues.isEmpty {
                    Section {
                        ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
                            Label(issue.description, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("editor.issues")
                    }
                    .accessibilityIdentifier("ax.editor.issues")
                }
            }
            .navigationTitle(model.isNew ? Text("editor.title.new") : Text("editor.title.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                        .accessibilityIdentifier("ax.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("ax.editor.save")
                }
            }
            .onChange(of: model.photoItem) { _, item in
                if let item { Task { await model.loadPhoto(item) } }
            }
            .alert("editor.saveFailed", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(verbatim: saveError ?? "")
            }
        }
    }

    // MARK: Sections

    private var previewSection: some View {
        @Bindable var model = model
        let canvas = model.design.spec.family.canvas
        return Section {
            Picker("editor.previewLanguage", selection: $model.previewLanguage) {
                Text(verbatim: "العربية").tag("ar")
                Text(verbatim: "English").tag("en")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ax.editor.previewLanguage")
            // Real size: canvas units are widget points.
            DesignPreview(design: model.design, image: model.newPhoto ?? designs.image(for: model.design),
                          language: model.previewLanguage)
                .frame(maxWidth: canvas.width)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .id(model.previewLanguage)
                .accessibilityLabel(Text("detail.preview.label \(model.design.name)"))
                .accessibilityHint(Text("editor.preview.footer"))
                .accessibilityIdentifier("ax.editor.preview")
        } footer: {
            Text("editor.preview.footer")
        }
    }

    /// AI results: overlaps the model left that the app couldn't fix go to the layer editor.
    @ViewBuilder private var layoutSection: some View {
        switch layout {
        case .clean:
            EmptyView()
        case .fixed:
            Section {
                Label("editor.layout.fixed", systemImage: "wand.and.stars")
                    .font(.footnote)
            }
            .accessibilityIdentifier("ax.editor.layout.fixed")
        case .needsEditing:
            Section {
                Label("editor.layout.needsEditing", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                if !model.overlapping.isEmpty {
                    NavigationLink {
                        LayersView(model: model, parent: [])
                    } label: {
                        Label("editor.layout.openLayers", systemImage: "square.3.layers.3d")
                    }
                    .accessibilityIdentifier("ax.editor.layout.openLayers")
                } else {
                    Label("editor.layout.resolved", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
            .accessibilityIdentifier("ax.editor.layout.warning")
        }
    }

    private var layersSection: some View {
        Section {
            NavigationLink {
                LayersView(model: model, parent: [])
            } label: {
                LabeledContent {
                    if !model.overlapping.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Text(verbatim: "(model.design.spec.layers.count)")
                } label: {
                    Label("editor.layers", systemImage: "square.3.layers.3d")
                }
            }
            .accessibilityIdentifier("ax.editor.layers")
        } footer: {
            Text("editor.layers.entry.footer")
        }
    }

    private var photoSection: some View {
        @Bindable var model = model
        return Section {
            PhotosPicker(selection: $model.photoItem, matching: .images) {
                Label(model.design.imageFile == nil && model.newPhoto == nil
                      ? LocalizedStringKey("editor.photo.pick") : "editor.photo.change",
                      systemImage: "photo")
            }
            .accessibilityIdentifier("ax.editor.photo")
            if model.isProcessingPhoto {
                ProgressView()
            }
        } header: {
            Text("editor.photo")
        } footer: {
            if model.design.imageLayer?.layer.filter == .halftone {
                Text("editor.photo.halftone")
            } else {
                Text("editor.photo.footer")
            }
        }
    }

    private var appearanceSection: some View {
        @Bindable var model = model
        return Section("editor.appearance") {
            Picker("editor.theme", selection: $model.themeChoice) {
                Text("editor.theme.template").tag("template")
                Text("detail.light").tag("light")
                Text("detail.dark").tag("dark")
            }
            .accessibilityIdentifier("ax.editor.theme")
            Picker("editor.clock", selection: $model.clockChoice) {
                Text("editor.clock.default").tag("default")
                Text("settings.clock.device").tag(ClockFormat.device.rawValue)
                Text("settings.clock.h12").tag(ClockFormat.h12.rawValue)
                Text("settings.clock.h24").tag(ClockFormat.h24.rawValue)
            }
            .accessibilityIdentifier("ax.editor.clock")
            colorRow("editor.color.accent", token: "accent")
            colorRow("editor.color.bg", token: "bg")
            colorRow("editor.color.fg", token: "fg")
            colorRow("editor.color.muted", token: "muted")
        }
    }

    private func colorRow(_ title: LocalizedStringKey, token: String) -> some View {
        HStack {
            ColorPicker(title, selection: model.color(token), supportsOpacity: false)
            if model.design.colors[token] != nil {
                Button {
                    model.resetColor(token)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("editor.color.reset"))
            }
        }
        .accessibilityIdentifier("ax.editor.color.\(token)")
    }

    // MARK: Save

    private func save() {
        do {
            try designs.save(model.design, newPhoto: model.newPhoto)
            dismiss()
            appState.tab = .myWidgets
        } catch {
            saveError = error.localizedDescription
        }
    }
}
