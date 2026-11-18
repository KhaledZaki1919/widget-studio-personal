import SwiftUI
import WidgetKit
import WidgetKitCore

// Personal build (docs/personal.md): "Send to widget". On any design (My widgets, editor incl.
// the AI result, import summary) → pick a widget the app knows or type the code a placed widget
// shows → the design is encrypted here, uploaded to the relay, and that widget is reloaded: it
// downloads, decrypts, caches and shows the design within seconds.

/// The editor's section (one hook line in `EditorView`).
struct SendToWidgetSection: View {
    let design: SavedDesign
    let photo: CGImage?
    let enabled: Bool
    @State private var isPresented = false

    var body: some View {
        Section {
            Button {
                isPresented = true
            } label: {
                Label { Text(personal: "send.button") } icon: { Image(systemName: "rectangle.portrait.and.arrow.forward") }
            }
            .buttonStyle(.m3TonalWide)
            .disabled(!enabled)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .accessibilityIdentifier("ax.editor.sendToWidget")
        }
        .sheet(isPresented: $isPresented) {
            SendToWidgetSheet(design: design, photo: photo)
        }
    }
}

/// The context-menu and swipe button in My widgets.
struct SendToWidgetButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(personal: "send.button") } icon: { Image(systemName: "rectangle.portrait.and.arrow.forward") }
        }
        .accessibilityIdentifier("ax.mywidgets.sendToWidget")
    }
}

/// A compact button for one design in the import summary (one hook line in `BulkImportView`).
struct SendToWidgetInlineButton: View {
    let design: SavedDesign
    @Environment(DesignsModel.self) private var designs
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "rectangle.portrait.and.arrow.forward")
                .frame(width: M3Space.target, height: M3Space.target)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(personal: "send.button"))
        .accessibilityIdentifier("ax.bulk.sendToWidget")
        .sheet(isPresented: $isPresented) {
            SendToWidgetSheet(design: design, photo: designs.image(for: design))
        }
    }
}

struct SendToWidgetSheet: View {
    let design: SavedDesign
    let photo: CGImage?
    /// Preselected code (from the My home screen list).
    var initialCode: String?
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var phase = Phase.idle
    @State private var known: [KnownWidget] = []
    @State private var local: [(SlotID, SlotState)] = []
    private let sender = HomeWidgetSender.make()
    private let language = RenderContext.preferredLanguage

    enum Phase: Equatable {
        case idle, sending
        case sent(KnownWidget)
        case failed(RelayError)
    }

    private var code: String? { RelayCode.normalize(typed) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: M3Space.xl) {
                    header
                    if sender == nil {
                        M3Status(tone: .error, text: Text(personal: "send.notConfigured"))
                    } else if case .sent(let widget) = phase {
                        sentView(widget)
                    } else {
                        if !known.isEmpty || !local.isEmpty { knownSection }
                        codeSection
                        sendButton
                    }
                }
                .padding(M3Space.l)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .m3Screen()
            .navigationTitle(Text(personal: "send.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                        .accessibilityIdentifier("ax.send.cancel")
                }
            }
            .onAppear {
                known = sender?.known() ?? []
                local = sender?.localSlots() ?? []
                if let initialCode { typed = RelayCode.formatted(initialCode) }
            }
        }
        .presentationDetents([.large])
        .m3Sheet()
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: M3Space.l) {
            DesignPreview(design: design, image: photo, language: language)
                .frame(width: design.spec.family == .small ? 72 : 132)
            VStack(alignment: .leading, spacing: M3Space.xs) {
                Text(verbatim: design.name).font(M3Type.titleMedium).foregroundStyle(M3.onSurface)
                Text(HomeScreenText.sizeKey(design.spec.family)).font(M3Type.bodySmall).foregroundStyle(M3.onSurfaceVariant)
            }
            Spacer(minLength: 0)
        }
    }

    private var knownSection: some View {
        VStack(alignment: .leading, spacing: M3Space.s) {
            M3SectionTitle(text: Text(personal: "send.known"))
            VStack(spacing: 0) {
                ForEach(known) { widget in
                    knownRow(code: widget.code, size: widget.size, slot: widget.slot,
                             detail: widget.designName.map { Text(verbatim: $0) } ?? Text(personal: "home.noDesign"))
                    if widget.id != known.last?.id || !local.isEmpty { Divider().overlay(M3.outlineVariant) }
                }
                ForEach(local, id: \.1.code) { slot, state in
                    knownRow(code: state.code, size: slot.size, slot: slot.slot, detail: Text(personal: "send.onThisPhone"))
                }
            }
            .m3Card(.filled)
        }
    }

    private func knownRow(code: String, size: SpecFamily, slot: String, detail: Text) -> some View {
        let fits = design.spec.family.rank <= size.rank
        let selected = self.code == code
        return Button {
            typed = RelayCode.formatted(code)
            phase = .idle
        } label: {
            HStack(spacing: M3Space.m) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? M3.primary : M3.onSurfaceVariant)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: RelayCode.formatted(code))
                        .font(M3Type.dots(20, relativeTo: .headline))
                        .foregroundStyle(M3.onSurface)
                        .environment(\.layoutDirection, .leftToRight)
                    HStack(spacing: M3Space.xs) {
                        Text(personal: "home.slot \(slot)")
                        Text(verbatim: "·")
                        Text(HomeScreenText.sizeKey(size))
                        Text(verbatim: "·")
                        detail
                    }
                    .font(M3Type.bodySmall)
                    .foregroundStyle(M3.onSurfaceVariant)
                    .lineLimit(1)
                    if !fits {
                        M3Status(tone: .warning, text: Text(personal: "send.tooBig"))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, M3Space.l)
            .padding(.vertical, M3Space.m)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!fits || phase == .sending)
        .opacity(fits ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("ax.send.known.\(code)")
    }

    private var codeSection: some View {
        TextField(text: $typed, prompt: Text(verbatim: "ABC-DEF")) {
            Text(personal: "send.code")
        }
        .font(M3Type.dots(26, relativeTo: .title2))
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .keyboardType(.asciiCapable)
        .submitLabel(.send)
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: typed) { _, value in
            let cleaned = String(value.uppercased().filter { RelayCode.alphabet.contains($0) }.prefix(RelayCode.length))
            let shown = cleaned.count > 3 ? "\(cleaned.prefix(3))-\(cleaned.dropFirst(3))" : cleaned
            if shown != value { typed = shown }
            if case .failed = phase { phase = .idle }
        }
        .onSubmit(send)
        .accessibilityIdentifier("ax.send.code")
        .m3Field(Text(personal: "send.code"), supporting: Text(personal: "send.code.help"), error: errorText)
    }

    private var errorText: Text? {
        guard case .failed(let error) = phase else { return nil }
        return HomeScreenText.message(error)
    }

    private var sendButton: some View {
        Button(action: send) {
            HStack(spacing: M3Space.s) {
                if phase == .sending {
                    ProgressView().tint(M3.onPrimary)
                    Text(personal: "send.sending")
                } else {
                    Image(systemName: "paperplane.fill")
                    Text(personal: "send.action")
                }
            }
        }
        .buttonStyle(.m3FilledWide)
        .disabled(code == nil || phase == .sending)
        .accessibilityIdentifier("ax.send.go")
    }

    private func sentView(_ widget: KnownWidget) -> some View {
        VStack(alignment: .leading, spacing: M3Space.l) {
            Label {
                Text(personal: "send.sent.title").font(M3Type.titleLarge)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(M3.success)
            }
            .foregroundStyle(M3.onSurface)
            Text(personal: "send.sent.body \(RelayCode.formatted(widget.code)) \(widget.slot)")
                .font(M3Type.bodyMedium)
                .foregroundStyle(M3.onSurfaceVariant)
            Button("common.done") { dismiss() }
                .buttonStyle(.m3FilledWide)
                .accessibilityIdentifier("ax.send.done")
            Button {
                phase = .idle
                typed = ""
            } label: {
                Text(personal: "send.another")
            }
            .buttonStyle(.m3Text)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ax.send.sent")
    }

    // MARK: Sending

    private func send() {
        guard let sender, let code, phase != .sending else { return }
        phase = .sending
        Task {
            do {
                let widget = try await sender.send(design, photo: photo, to: code)
                // Right away: the widget's timeline downloads the design now.
                WidgetCenter.shared.reloadTimelines(ofKind: widget.widgetKind)
                ReloadLog.record(kind: widget.widgetKind, reason: "sent to \(widget.code)")
                phase = .sent(widget)
                UIAccessibility.post(notification: .announcement, argument: String(localized: "send.sent.title", table: "Personal"))
            } catch {
                phase = .failed(error as? RelayError ?? .network(error.localizedDescription))
            }
            known = sender.known()
        }
    }
}

/// Shared texts for the personal screens.
enum HomeScreenText {
    static func sizeKey(_ size: SpecFamily) -> LocalizedStringKey {
        switch size {
        case .small: "detail.size.small"
        case .medium: "detail.size.medium"
        case .large: "detail.size.large"
        case .xlarge: "detail.size.xlarge"
        }
    }

    /// What went wrong and how to recover.
    static func message(_ error: RelayError) -> Text {
        switch error {
        case .invalidCode: Text(personal: "send.error.invalid")
        case .unknownCode: Text(personal: "send.error.unknown")
        case .doesNotFit: Text(personal: "send.error.fit")
        case .tooLarge: Text(personal: "send.error.tooLarge")
        case .rateLimited: Text(personal: "send.error.rate")
        case .notConfigured: Text(personal: "send.notConfigured")
        case .crypto, .http, .network: Text(personal: "send.error.network \(error.summary)")
        }
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .standard)
    }

    static func delay(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }
}
