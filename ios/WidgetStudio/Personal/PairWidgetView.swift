import SwiftUI
import WidgetKit
import WidgetKitCore

// Personal build (docs/personal.md): Settings → Pair widget. The user types the code the
// "Widget Studio" widget shows; the app keeps it in the Keychain and uploads an encrypted pair
// item, which tells the widget it's paired. Diagnostics: pairing, last upload, and per size what
// the relay has and when a widget last downloaded it.

/// The row in Settings (one hook line in `SettingsView`).
struct PairWidgetSection: View {
    @State private var code = RelaySender.storedCode()

    var body: some View {
        Section {
            NavigationLink {
                PairWidgetView()
            } label: {
                LabeledContent {
                    Text(personal: code == nil ? "settings.pair.status.unpaired" : "settings.pair.status.paired")
                } label: {
                    Label {
                        Text(personal: "settings.pair.title")
                    } icon: {
                        Image(systemName: "link")
                    }
                }
            }
            .accessibilityIdentifier("ax.settings.pair")
        } footer: {
            Text(personal: "settings.pair.row.footer")
        }
        .onAppear { code = RelaySender.storedCode() }
    }
}

struct PairWidgetView: View {
    @State private var typed = ""
    @State private var code = RelaySender.storedCode()
    @State private var isBusy = false
    @State private var result: LocalizedStringKey?
    @State private var errorText: String?
    @State private var record = RelaySender.Record()
    @State private var statuses: [RelaySlot: RelayClient.Status] = [:]
    @State private var statusError: String?
    @State private var confirmUnpair = false
    private let sender = RelayClient().map { RelaySender(client: $0) }

    var body: some View {
        Form {
            if sender == nil {
                Section {
                    Label {
                        Text(personal: "settings.pair.notConfigured")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .foregroundStyle(.orange)
                }
            }
            pairingSection
            diagnosticsSection
        }
        .navigationTitle(Text(personal: "settings.pair.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // With a working App Group the app can read the widget's own code.
            if code == nil, typed.isEmpty, let found = WidgetPairing.existing()?.code {
                typed = RelayCode.formatted(found)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .confirmationDialog(Text(personal: "settings.pair.unpair.confirm"), isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button(role: .destructive) {
                sender?.unpair()
                code = nil
                statuses = [:]
                record = RelaySender.Record()
                result = nil
            } label: {
                Text(personal: "settings.pair.unpair")
            }
        }
    }

    private var pairingSection: some View {
        Section {
            if let code {
                LabeledContent {
                    Text(verbatim: RelayCode.formatted(code))
                        .font(.body.monospaced())
                        .environment(\.layoutDirection, .leftToRight)
                } label: {
                    Text(personal: "settings.pair.status.paired")
                }
                Button(role: .destructive) {
                    confirmUnpair = true
                } label: {
                    Text(personal: "settings.pair.unpair")
                }
                .accessibilityIdentifier("ax.pair.unpair")
            } else {
                TextField(text: $typed, prompt: Text(verbatim: "ABCD-EFGH")) {
                    Text(personal: "settings.pair.code")
                }
                .font(.title3.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIdentifier("ax.pair.code")
                if !typed.isEmpty, RelayCode.normalize(typed) == nil {
                    Text(personal: "settings.pair.invalid")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(action: pair) {
                    HStack {
                        Text(personal: "settings.pair.button")
                        if isBusy {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isBusy || sender == nil || RelayCode.normalize(typed) == nil)
                .accessibilityIdentifier("ax.pair.submit")
            }
            if let result {
                Text(personal: result)
                    .font(.footnote)
                    .foregroundStyle(errorText == nil ? .green : .red)
            }
            if let errorText {
                Text(verbatim: errorText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(personal: "settings.pair.code")
        } footer: {
            Text(personal: "settings.pair.footer")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            row("settings.pair.diag.relay", sender?.client.baseURL.host() ?? "—")
            row("settings.pair.diag.paired", date(record.paired))
            row("settings.pair.diag.lastUpload", uploadText)
            if let error = record.lastError {
                row("settings.pair.diag.lastError", error)
            }
            if code != nil {
                row("settings.pair.diag.widgetConfirmed", date(statuses[.pair]?.lastDownloadDate))
                ForEach([SpecFamily.small, .medium, .large], id: \.self) { size in
                    LabeledContent {
                        Text(verbatim: slotText(RelaySlot(size)))
                            .font(.footnote.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text(sizeKey(size))
                    }
                }
                if let statusError {
                    row("settings.pair.diag.lastError", statusError)
                }
                Button {
                    Task { await refresh() }
                } label: {
                    Text(personal: "settings.pair.diag.refresh")
                }
            }
        } header: {
            Text(personal: "settings.pair.diag.title")
        } footer: {
            Text(personal: "settings.pair.diag.footer")
        }
    }

    private func row(_ key: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .font(.footnote)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(personal: key)
        }
    }

    private var uploadText: String {
        guard let date = record.lastUpload else { return "—" }
        let parts = [self.date(date), record.lastSlot?.rawValue, record.lastDesign,
                     record.lastBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// "↑ 10:42 · ↓ 10:42" (uploaded, last widget download) or "—".
    private func slotText(_ slot: RelaySlot) -> String {
        guard let status = statuses[slot], status.exists else { return "—" }
        return "↑ \(date(status.uploadedDate)) · ↓ \(date(status.lastDownloadDate))"
    }

    private func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }

    private func sizeKey(_ size: SpecFamily) -> LocalizedStringKey {
        switch size {
        case .small: "detail.size.small"
        case .medium: "detail.size.medium"
        case .large: "detail.size.large"
        }
    }

    private func pair() {
        guard let sender else { return }
        isBusy = true
        result = nil
        errorText = nil
        Task {
            do {
                try await sender.pair(typed)
                code = RelaySender.storedCode()
                typed = ""
                result = "settings.pair.success"
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                result = "settings.pair.failed"
                errorText = (error as? RelayError)?.summary ?? error.localizedDescription
            }
            isBusy = false
            await refresh()
        }
    }

    private func refresh() async {
        guard let sender else { return }
        record = sender.record()
        guard code != nil else { return }
        statusError = nil
        var found: [RelaySlot: RelayClient.Status] = [:]
        for slot in RelaySlot.allCases {
            do {
                found[slot] = try await sender.status(slot)
            } catch {
                statusError = (error as? RelayError)?.summary ?? error.localizedDescription
            }
        }
        statuses = found
    }
}

extension Text {
    /// A string from the personal build's own table (`Personal.xcstrings`).
    init(personal key: LocalizedStringKey) {
        self.init(key, tableName: "Personal")
    }
}
