import SwiftUI
import WidgetKit
import WidgetKitCore

// Personal build (docs/personal.md): "Use on home screen". Pick the "Widget Studio" widget size,
// the design and its downscaled photo are encrypted here and uploaded to the relay, then the
// widget is reloaded: it downloads, decrypts, caches and shows the design within seconds.

/// The editor's section (AI result, new and saved designs; one hook line in `EditorView`).
struct UseOnHomeScreenSection: View {
    let design: SavedDesign
    let photo: CGImage?
    let enabled: Bool
    @State private var isPresented = false

    var body: some View {
        Section {
            Button {
                isPresented = true
            } label: {
                Label {
                    Text(personal: "mywidgets.home.button")
                } icon: {
                    Image(systemName: "rectangle.on.rectangle.angled")
                }
            }
            .disabled(!enabled)
            .accessibilityIdentifier("ax.editor.homeScreen")
        }
        .sheet(isPresented: $isPresented) {
            UseOnHomeScreenSheet(design: design, photo: photo)
        }
    }
}

/// The context-menu and swipe button in My widgets.
struct UseOnHomeScreenButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(personal: "mywidgets.home.button")
            } icon: {
                Image(systemName: "rectangle.on.rectangle.angled")
            }
        }
        .accessibilityIdentifier("ax.mywidgets.homeScreen")
    }
}

struct UseOnHomeScreenSheet: View {
    let design: SavedDesign
    let photo: CGImage?
    @Environment(\.dismiss) private var dismiss
    @State private var sending: SpecFamily?
    @State private var sent: SpecFamily?
    @State private var errorText: String?
    @State private var isPaired = RelaySender.storedCode() != nil
    private let sender = RelayClient().map { RelaySender(client: $0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Text(verbatim: design.name)
                    } label: {
                        Text(personal: "mywidgets.home.design")
                    }
                }
                if sender == nil {
                    Section {
                        Text(personal: "settings.pair.notConfigured")
                            .foregroundStyle(.orange)
                    }
                } else if !isPaired {
                    Section {
                        Text(personal: "mywidgets.home.notPaired")
                        NavigationLink {
                            PairWidgetView()
                        } label: {
                            Text(personal: "settings.pair.title")
                        }
                        .accessibilityIdentifier("ax.home.pair")
                    }
                } else {
                    sizesSection
                }
            }
            .navigationTitle(Text(personal: "mywidgets.home.button"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                        .accessibilityIdentifier("ax.home.done")
                }
            }
            .onAppear { isPaired = RelaySender.storedCode() != nil }
        }
        .presentationDetents([.medium, .large])
    }

    private var sizesSection: some View {
        Section {
            // The design's own size and larger ones (it's never shrunk).
            ForEach(design.spec.supportedFamilies, id: \.self) { size in
                Button {
                    send(to: size)
                } label: {
                    HStack {
                        Label {
                            Text(sizeKey(size))
                        } icon: {
                            Image(systemName: icon(size))
                        }
                        Spacer()
                        if sending == size {
                            ProgressView()
                        } else if sent == size {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                .disabled(sending != nil)
                .accessibilityIdentifier("ax.home.size.\(size.rawValue)")
            }
            if sent != nil {
                Text(personal: "mywidgets.home.sent")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            if let errorText {
                Text(personal: "mywidgets.home.failed")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Text(verbatim: errorText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(personal: "mywidgets.home.pick")
        } footer: {
            Text(personal: "mywidgets.home.footer")
        }
    }

    private func send(to size: SpecFamily) {
        guard let sender else { return }
        sending = size
        sent = nil
        errorText = nil
        Task {
            do {
                try await sender.send(design, photo: photo, to: size)
                WidgetCenter.shared.reloadTimelines(ofKind: SwitcherCatalog.widgetKind(size))
                sent = size
            } catch {
                errorText = (error as? RelayError)?.summary ?? error.localizedDescription
            }
            sending = nil
        }
    }

    private func sizeKey(_ size: SpecFamily) -> LocalizedStringKey {
        switch size {
        case .small: "detail.size.small"
        case .medium: "detail.size.medium"
        case .large: "detail.size.large"
        }
    }

    private func icon(_ size: SpecFamily) -> String {
        switch size {
        case .small: "square"
        case .medium: "rectangle"
        case .large: "square.fill"
        }
    }
}
