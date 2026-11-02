import SwiftUI
import WidgetKitCore

/// The layer editor (M6.1, ADR-022): the design's layers back to front (or a stack's items),
/// with the live preview on top. Edit selects layers to put in one stack, reorders and deletes;
/// a tap opens the layer. Layers whose text covers another are marked, and Arrange fixes them
/// the way the AI flow does.
struct LayersView: View {
    @Environment(DesignsModel.self) private var designs
    @Bindable var model: EditorModel
    /// `[]` = the top level; else the stack whose items are listed.
    let parent: LayerEditing.Path
    @State private var selection = Set<Int>()
    @State private var editMode = EditMode.inactive
    @State private var groupFailed = false

    var body: some View {
        let layers = model.layers(in: parent)
        let overlapping = parent.isEmpty ? model.overlapping : []
        List(selection: $selection) {
            Section {
                DesignPreview(design: model.design, image: model.newPhoto ?? designs.image(for: model.design),
                              language: model.previewLanguage)
                    .frame(maxWidth: model.design.spec.family.canvas.width * 0.8)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
            }
            if parent.isEmpty, !overlapping.isEmpty {
                Section {
                    Label("editor.layers.overlaps", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                    Button {
                        model.arrangeOverlaps()
                        selection = []
                    } label: {
                        Label("editor.layers.arrange", systemImage: "wand.and.stars")
                    }
                    .accessibilityIdentifier("ax.editor.layers.arrange")
                }
                .selectionDisabled()
            }
            Section {
                ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                    NavigationLink {
                        LayerDetailView(model: model, path: parent + [index])
                    } label: {
                        LayerRow(layer: layer, language: model.previewLanguage, overlaps: overlapping.contains(index))
                    }
                    .tag(index)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.removeLayer(parent + [index])
                        } label: {
                            Label("editor.layer.delete", systemImage: "trash")
                        }
                        Button {
                            model.duplicateLayer(parent + [index])
                        } label: {
                            Label("editor.layer.duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                    }
                    .accessibilityIdentifier("ax.editor.layers.row.\(index)")
                }
                .onMove { source, destination in
                    model.moveLayers(in: parent, from: source, to: destination)
                }
            } header: {
                Text(parent.isEmpty ? LocalizedStringKey("editor.layers.order") : "editor.layers.items")
            } footer: {
                if parent.isEmpty { Text("editor.layers.footer") }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(parent.isEmpty ? Text("editor.layers") : Text("editor.layer.stack.items"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editMode.isEditing ? LocalizedStringKey("common.done") : "editor.layers.select") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    selection = []
                }
                .accessibilityIdentifier("ax.editor.layers.edit")
            }
            if parent.isEmpty, editMode.isEditing {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        if model.groupLayers(selection) {
                            selection = []
                            editMode = .inactive
                        } else {
                            groupFailed = true
                        }
                    } label: {
                        Label("editor.layers.group", systemImage: "square.stack")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(selection.count < 2)
                    .accessibilityIdentifier("ax.editor.layers.group")
                    Spacer()
                }
            }
        }
        .alert("editor.layers.groupFailed", isPresented: $groupFailed) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("editor.layers.groupFailed.body")
        }
    }
}

/// One layer in the list: its kind, what it shows, and a mark when it covers other text.
struct LayerRow: View {
    let layer: Layer
    let language: String
    let overlaps: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(layer.content))
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.kind(layer.content))
                    .font(.subheadline.weight(.medium))
                if let summary = Self.summary(layer, language: language), !summary.isEmpty {
                    Text(verbatim: summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if overlaps {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("editor.layers.overlapMark"))
            }
        }
    }

    static func summary(_ layer: Layer, language: String) -> String? {
        switch layer.content {
        case .text(let text): text.value.resolved(language: language)
        case .icon(let icon): icon.symbol
        case .stack(let stack): stack.children.compactMap { summary($0, language: language) }.joined(separator: " · ")
        case .list(let list): list.items.map { $0.title.resolved(language: language) }.joined(separator: " · ")
        default: nil
        }
    }

    static func kind(_ content: LayerContent) -> LocalizedStringKey {
        switch content {
        case .text: "editor.layer.kind.text"
        case .image: "editor.layer.kind.image"
        case .shape: "editor.layer.kind.shape"
        case .icon: "editor.layer.kind.icon"
        case .analogClock: "editor.layer.kind.clock"
        case .dotGrid, .dotBars: "editor.layer.kind.dots"
        case .ring: "editor.layer.kind.ring"
        case .forecastRow: "editor.layer.kind.forecast"
        case .button: "editor.layer.kind.button"
        case .calendarMonth: "editor.layer.kind.calendar"
        case .list: "editor.layer.kind.list"
        case .progressBar: "editor.layer.kind.progress"
        case .stack(let stack):
            switch stack.axis {
            case .vertical: "editor.layer.kind.column"
            case .horizontal: "editor.layer.kind.row"
            case .grid: "editor.layer.kind.grid"
            }
        case .spacer: "editor.layer.kind.spacer"
        case .unknown: "editor.layer.kind.unknown"
        }
    }

    static func symbol(_ content: LayerContent) -> String {
        switch content {
        case .text: "textformat"
        case .image: "photo"
        case .shape: "square.on.circle"
        case .icon: "star"
        case .analogClock: "clock"
        case .dotGrid, .dotBars: "circle.grid.3x3"
        case .ring: "circle.dashed"
        case .forecastRow: "cloud.sun"
        case .button: "hand.tap"
        case .calendarMonth: "calendar"
        case .list: "list.bullet"
        case .progressBar: "chart.bar.fill"
        case .stack(let stack):
            switch stack.axis {
            case .vertical: "rectangle.split.1x2"
            case .horizontal: "rectangle.split.2x1"
            case .grid: "square.grid.2x2"
            }
        case .spacer: "arrow.up.and.down"
        case .unknown: "questionmark.square"
        }
    }
}
