import SwiftUI
import WidgetKit
import WidgetKitCore

// Personal build (docs/personal.md): "My home screen", every widget code the app has sent a
// design to: size, slot, current design, last update and delivery, with Remove (frees the code)
// and Send another design (reassigns it). Diagnostics shows per code the last upload, the last
// widget download and the delay between them.

/// The row at the top of My widgets (one hook line in `MyWidgetsView`).
struct HomeScreenListRow: View {
    @State private var count = HomeWidgetSender.make()?.known().count ?? 0

    var body: some View {
        Section {
            NavigationLink {
                HomeScreenView()
            } label: {
                HStack(spacing: M3Space.l) {
                    Image(systemName: "iphone.gen3")
                        .font(.title3)
                        .foregroundStyle(M3.onSecondaryContainer)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(M3.secondaryContainer))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(personal: "home.title").font(M3Type.titleMedium).foregroundStyle(M3.onSurface)
                        Text(personal: "home.row.count \(count)").font(M3Type.bodySmall).foregroundStyle(M3.onSurfaceVariant)
                    }
                }
                .frame(minHeight: M3Space.target)
            }
            .accessibilityIdentifier("ax.mywidgets.homeScreen")
        }
        .onAppear { count = HomeWidgetSender.make()?.known().count ?? 0 }
    }
}

/// The Settings entry (one hook line in `SettingsView`).
struct HomeScreenSettingsSection: View {
    var body: some View {
        Section {
            NavigationLink {
                HomeScreenView()
            } label: {
                Label { Text(personal: "home.title") } icon: { Image(systemName: "iphone.gen3") }
            }
            .accessibilityIdentifier("ax.settings.homeScreen")
        } footer: {
            Text(personal: "home.settings.footer").font(M3Type.bodySmall).foregroundStyle(M3.onSurfaceVariant)
        }
    }
}

struct HomeScreenView: View {
    @State private var widgets: [KnownWidget] = []
    @State private var statuses: [String: WidgetRelayStatus] = [:]
    @State private var statusError: String?
    @State private var removing: KnownWidget?
    @State private var removeError: String?
    private let sender = HomeWidgetSender.make()

    var body: some View {
        List {
            if sender == nil {
                Section { M3Status(tone: .error, text: Text(personal: "send.notConfigured")) }
            }
            if widgets.isEmpty {
                Section {
                    M3EmptyState(symbol: "iphone.gen3", title: Text(personal: "home.empty.title"),
                                 message: Text(personal: "home.empty.body")) { EmptyView() }
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(widgets) { widget in
                        NavigationLink {
                            HomeWidgetDetailView(widget: widget, onChange: reload)
                        } label: {
                            HomeWidgetRow(widget: widget, status: statuses[widget.code])
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { removing = widget } label: {
                                Label { Text(personal: "home.remove") } icon: { Image(systemName: "xmark.circle") }
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) { removing = widget } label: {
                                Label { Text(personal: "home.remove") } icon: { Image(systemName: "xmark.circle") }
                            }
                        }
                        .accessibilityIdentifier("ax.home.widget.\(widget.code)")
                    }
                } header: {
                    M3SectionTitle(text: Text(personal: "home.section"))
                } footer: {
                    if let statusError {
                        M3Status(tone: .warning, text: Text(personal: "home.statusFailed \(statusError)"))
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: M3Space.s) {
                    ForEach(1...4, id: \.self) { step in
                        Label {
                            Text(personal: LocalizedStringKey("home.howto.\(step)")).font(M3Type.bodyMedium)
                        } icon: {
                            Text(verbatim: "\(step)")
                                .font(M3Type.labelMedium.weight(.bold))
                                .foregroundStyle(M3.onSecondaryContainer)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(M3.secondaryContainer))
                        }
                    }
                }
                .padding(.vertical, M3Space.xs)
            } header: {
                M3SectionTitle(text: Text(personal: "home.howto"))
            }
        }
        .m3List()
        .navigationTitle(Text(personal: "home.title"))
        .accessibilityIdentifier("ax.home.list")
        .onAppear(perform: reload)
        .task { await refreshStatuses() }
        .refreshable { await refreshStatuses() }
        .confirmationDialog(Text(personal: "home.remove.title \(RelayCode.formatted(removing?.code ?? ""))"),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button(role: .destructive) {
                if let removing { remove(removing) }
            } label: {
                Text(personal: "home.remove")
            }
            .accessibilityIdentifier("ax.home.remove.confirm")
        } message: {
            Text(personal: "home.remove.body")
        }
        .alert(Text(personal: "home.remove.failed"),
               isPresented: Binding(get: { removeError != nil }, set: { if !$0 { removeError = nil } })) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: removeError ?? "")
        }
    }

    private func reload() {
        widgets = sender?.known() ?? []
    }

    private func refreshStatuses() async {
        guard let sender else { return }
        reload()
        statusError = nil
        for widget in widgets {
            do {
                statuses[widget.code] = try await sender.status(widget.code)
            } catch {
                statusError = (error as? RelayError)?.summary ?? error.localizedDescription
            }
        }
    }

    private func remove(_ widget: KnownWidget) {
        guard let sender else { return }
        Task {
            do {
                try await sender.remove(widget.code)
                WidgetCenter.shared.reloadTimelines(ofKind: widget.widgetKind)
                ReloadLog.record(kind: widget.widgetKind, reason: "removed \(widget.code)")
            } catch {
                removeError = (error as? RelayError)?.summary ?? error.localizedDescription
            }
            reload()
        }
    }
}

/// One widget: code in dot numerals, design, slot and size, last update, delivery state.
struct HomeWidgetRow: View {
    let widget: KnownWidget
    let status: WidgetRelayStatus?

    var body: some View {
        HStack(alignment: .top, spacing: M3Space.l) {
            Text(verbatim: RelayCode.formatted(widget.code))
                .font(M3Type.dots(18, relativeTo: .headline))
                .foregroundStyle(M3.onSurface)
                .padding(.horizontal, M3Space.s)
                .padding(.vertical, M3Space.xs)
                .background(M3Shape.rounded(M3Shape.small).fill(M3.surfaceContainerHighest))
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(Text(personal: "home.code \(widget.code.map(String.init).joined(separator: " "))"))
            VStack(alignment: .leading, spacing: M3Space.xs) {
                Text(verbatim: widget.designName ?? "—")
                    .font(M3Type.titleMedium)
                    .foregroundStyle(M3.onSurface)
                HStack(spacing: M3Space.xs) {
                    Text(personal: "home.slot \(widget.slot)")
                    Text(verbatim: "·")
                    Text(HomeScreenText.sizeKey(widget.size))
                }
                .font(M3Type.bodySmall)
                .foregroundStyle(M3.onSurfaceVariant)
                if let sent = widget.lastSent {
                    Text(personal: "home.updated \(sent.formatted(.relative(presentation: .named)))")
                        .font(M3Type.bodySmall)
                        .foregroundStyle(M3.onSurfaceVariant)
                }
                delivery
            }
        }
        .padding(.vertical, M3Space.xs)
    }

    @ViewBuilder private var delivery: some View {
        if let error = widget.lastError {
            M3Status(tone: .error, text: Text(verbatim: error))
        } else if let status {
            if let delay = status.delay {
                M3Status(tone: .success, text: Text(personal: "home.delivered \(HomeScreenText.delay(delay))"))
            } else if status.waiting {
                M3Status(tone: .warning, text: Text(personal: "home.waiting"))
            } else if !status.exists {
                M3Status(tone: .warning, text: Text(personal: "home.missing"))
            }
        }
    }
}

struct HomeWidgetDetailView: View {
    let widget: KnownWidget
    var onChange: () -> Void = {}
    @Environment(DesignsModel.self) private var designs
    @Environment(\.dismiss) private var dismiss
    @State private var status: WidgetRelayStatus?
    @State private var statusError: String?
    @State private var picking = false
    @State private var sending: SavedDesign?
    @State private var confirmingRemove = false
    private let sender = HomeWidgetSender.make()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: M3Space.s) {
                    Text(verbatim: RelayCode.formatted(widget.code))
                        .font(M3Type.dots(40, relativeTo: .largeTitle))
                        .foregroundStyle(M3.onSurface)
                        .environment(\.layoutDirection, .leftToRight)
                    HStack(spacing: M3Space.xs) {
                        Text(personal: "home.slot \(widget.slot)")
                        Text(verbatim: "·")
                        Text(HomeScreenText.sizeKey(widget.size))
                    }
                    .font(M3Type.bodyMedium)
                    .foregroundStyle(M3.onSurfaceVariant)
                }
                .padding(.vertical, M3Space.s)
                LabeledContent {
                    Text(verbatim: widget.designName ?? "—")
                } label: {
                    Text(personal: "home.design")
                }
            }
            Section {
                Button {
                    picking = true
                } label: {
                    Label { Text(personal: "home.sendAnother") } icon: { Image(systemName: "rectangle.portrait.and.arrow.forward") }
                }
                .buttonStyle(.m3FilledWide)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("ax.home.sendAnother")
                Button(role: .destructive) {
                    confirmingRemove = true
                } label: {
                    Label { Text(personal: "home.remove") } icon: { Image(systemName: "xmark.circle") }
                }
                .buttonStyle(M3ButtonStyle(kind: .outlined, fullWidth: true))
                .foregroundStyle(M3.error)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("ax.home.remove")
            }
            Section {
                HomeWidgetDiagnostics(widget: widget, status: status, error: statusError)
            } header: {
                M3SectionTitle(text: Text(personal: "home.diagnostics"))
            }
        }
        .m3List()
        .navigationTitle(Text(verbatim: RelayCode.formatted(widget.code)))
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $picking) {
            DesignPickerSheet(size: widget.size) { design in
                picking = false
                sending = design
            }
        }
        .sheet(item: $sending, onDismiss: {
            onChange()
            Task { await refresh() }
        }, content: { design in
            SendToWidgetSheet(design: design, photo: designs.image(for: design), initialCode: widget.code)
        })
        .confirmationDialog(Text(personal: "home.remove.title \(RelayCode.formatted(widget.code))"), isPresented: $confirmingRemove,
                            titleVisibility: .visible) {
            Button(role: .destructive) {
                remove()
            } label: {
                Text(personal: "home.remove")
            }
        } message: {
            Text(personal: "home.remove.body")
        }
    }

    private func refresh() async {
        guard let sender else { return }
        do {
            status = try await sender.status(widget.code)
            statusError = nil
        } catch {
            statusError = (error as? RelayError)?.summary ?? error.localizedDescription
        }
    }

    private func remove() {
        guard let sender else { return }
        Task {
            do {
                try await sender.remove(widget.code)
                WidgetCenter.shared.reloadTimelines(ofKind: widget.widgetKind)
                onChange()
                dismiss()
            } catch {
                statusError = (error as? RelayError)?.summary ?? error.localizedDescription
            }
        }
    }
}

/// Upload → widget download → delay, for one code. Also in Diagnostics.
struct HomeWidgetDiagnostics: View {
    let widget: KnownWidget
    let status: WidgetRelayStatus?
    let error: String?

    var body: some View {
        row("home.diag.lastSent", HomeScreenText.time(widget.lastSent))
        row("home.diag.uploaded", HomeScreenText.time(status?.uploaded))
        row("home.diag.downloaded", HomeScreenText.time(status?.lastDownload))
        row("home.diag.delay", status?.delay.map(HomeScreenText.delay) ?? (status?.waiting == true ? "…" : "—"))
        if let bytes = status?.bytes ?? widget.lastBytes {
            row("home.diag.bytes", ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        if let error {
            M3Status(tone: .warning, text: Text(verbatim: error))
        }
    }

    private func row(_ key: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value).monospacedDigit().foregroundStyle(M3.onSurfaceVariant)
        } label: {
            Text(personal: key)
        }
    }
}

/// Diagnostics: per code, last upload, last widget download and the delay (one hook line in
/// `DiagnosticsView`).
struct HomeWidgetsDiagnosticsSection: View {
    @State private var widgets: [KnownWidget] = []
    @State private var statuses: [String: WidgetRelayStatus] = [:]
    @State private var error: String?
    private let sender = HomeWidgetSender.make()

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: sender?.client.baseURL.host() ?? "—").font(M3Type.bodySmall.monospaced())
            } label: {
                Text(personal: "home.diag.relay")
            }
            if widgets.isEmpty {
                Text(personal: "home.empty.title").foregroundStyle(M3.onSurfaceVariant)
            }
            ForEach(widgets) { widget in
                DisclosureGroup {
                    HomeWidgetDiagnostics(widget: widget, status: statuses[widget.code], error: nil)
                } label: {
                    HStack {
                        Text(verbatim: RelayCode.formatted(widget.code)).font(M3Type.bodyMedium.monospaced())
                        Spacer()
                        Text(verbatim: statuses[widget.code]?.delay.map(HomeScreenText.delay) ?? "—")
                            .font(M3Type.bodySmall)
                            .foregroundStyle(M3.onSurfaceVariant)
                    }
                }
            }
            if let error { M3Status(tone: .warning, text: Text(verbatim: error)) }
        } header: {
            Text(personal: "home.diag.section")
        }
        .task {
            guard let sender else { return }
            widgets = sender.known()
            for widget in widgets {
                do { statuses[widget.code] = try await sender.status(widget.code) } catch {
                    self.error = (error as? RelayError)?.summary ?? error.localizedDescription
                }
            }
        }
    }
}

/// Picks one of My widgets' designs that fits a widget size.
struct DesignPickerSheet: View {
    let size: SpecFamily
    let onPick: (SavedDesign) -> Void
    @Environment(DesignsModel.self) private var designs
    @Environment(\.dismiss) private var dismiss
    private let language = RenderContext.preferredLanguage

    var body: some View {
        NavigationStack {
            List {
                let fitting = designs.designs.filter { $0.spec.family.rank <= size.rank }
                if fitting.isEmpty {
                    M3EmptyState(symbol: "rectangle.stack", title: Text(personal: "home.pick.empty"),
                                 message: Text(personal: "home.pick.empty.body")) { EmptyView() }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                ForEach(fitting) { design in
                    Button {
                        onPick(design)
                    } label: {
                        HStack(spacing: M3Space.l) {
                            DesignPreview(design: design, image: designs.image(for: design), language: language)
                                .frame(width: design.spec.family == .small ? 64 : 120)
                            Text(verbatim: design.name).font(M3Type.titleMedium).foregroundStyle(M3.onSurface)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .m3List()
            .navigationTitle(Text(personal: "home.pick.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
            }
        }
        .m3Sheet()
    }
}
