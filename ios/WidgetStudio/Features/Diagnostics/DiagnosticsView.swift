import SwiftUI
import WidgetKitCore

/// Hidden screen (long-press the version number; in M0 also linked from Home) that shows which
/// capabilities work on this sideloaded install (ADR-005), with a shareable report.
struct DiagnosticsView: View {
    @State private var model = DiagnosticsModel()
    @Environment(LiveDataModel.self) private var live
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                NavigationLink("diag.testSpecs") {
                    TestSpecsView()
                }
                .accessibilityIdentifier("ax.diag.testSpecs")
            } footer: {
                Text("diag.testSpecs.footer")
            }
            dataSection
            buildSection
            ForEach(model.signings, id: \.name) { signing in
                signingSection(signing)
            }
            appGroupSection
            widgetSection
            locationSection
            healthSection
            Section("diag.section.battery") {
                outcomeRow("diag.battery.app", model.battery)
            }
            reloadSection
            // Whether Apple Music is reachable here; the check widget's step log shows the widget's own taps (ADR-027).
            Section("diag.section.media") {
                LabeledContent {
                    Text(verbatim: MediaControl.isAuthorized ? "authorized" : "not authorized")
                } label: {
                    Text("diag.media.access")
                }
            }
            Section {
                Button("diag.refresh", action: model.refresh)
                    .accessibilityIdentifier("ax.diag.refresh")
                ShareLink(item: model.reportText + "\n\n" + dataReport) {
                    Label("diag.share", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("ax.diag.share")
            } footer: {
                Text("diag.share.footer")
            }
        }
        .accessibilityIdentifier("ax.diag.list")
        .navigationTitle("diag.title")
        .onAppear(perform: model.refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }

    /// ADR-030: the last reload per widget kind, with its reason, and how to lift the budget for testing.
    private var reloadSection: some View {
        Section {
            let latest = ReloadLog.latest()
            if latest.isEmpty {
                Text("diag.reloads.none").foregroundStyle(.secondary)
            }
            ForEach(Array(latest.prefix(12))) { entry in
                ReloadRow(entry: entry)
            }
        } header: {
            Text("diag.section.reloads")
        } footer: {
            Text("diag.reloads.footer")
        }
    }

    private var buildSection: some View {
        Section("diag.section.build") {
            valueRow("diag.version", AppInfo.versionText)
            valueRow("diag.bundleID", Bundle.main.bundleIdentifier ?? "—")
            valueRow("diag.profile", DiagnosticsModel.describe(model.profileStatus))
            valueRow("diag.team", model.profile?.teamIdentifiers.joined(separator: ", ") ?? "—")
            valueRow("diag.profileGroups", model.profile.map { $0.appGroups.isEmpty ? "—" : $0.appGroups.joined(separator: "\n") } ?? "—")
            valueRow("diag.entitlements", model.profile?.entitlementKeys.joined(separator: "\n") ?? "—")
        }
    }

    /// Each data source in the app and in the widget, with the last update (M4, ADR-016). The
    /// widget's status is only readable here with an App Group; otherwise the large check widget
    /// shows it.
    private var dataSection: some View {
        let widget = live.widgetStatus
        return Section {
            ForEach(SourceStatus.Source.allCases, id: \.self) { source in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: source.rawValue).font(.subheadline.weight(.medium))
                    sourceLine(label: "diag.data.app", entry: live.status.entries[source])
                    if let widget {
                        sourceLine(label: "diag.data.widget", entry: widget.entries[source])
                    }
                }
                .accessibilityIdentifier("ax.diag.data.\(source.rawValue)")
            }
            Button("diag.data.refresh") { Task { await live.refresh() } }
                .accessibilityIdentifier("ax.diag.data.refresh")
        } header: {
            Text("diag.data")
        } footer: {
            Text(widget == nil ? "diag.data.footer.storeMode" : "diag.data.footer.shared")
        }
    }

    private func sourceLine(label: LocalizedStringKey, entry: SourceStatus.Entry?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: entry == nil ? "circle.dotted" : entry?.ok == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry == nil ? .gray : entry?.ok == true ? .green : .red)
            Text(label)
            Spacer(minLength: 4)
            Text(verbatim: [entry?.detail, entry?.updated.map { $0.formatted(date: .omitted, time: .shortened) }]
                .compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.footnote)
    }

    /// Plain English data-source lines for the shared report.
    private var dataReport: String {
        func line(_ entry: SourceStatus.Entry?) -> String {
            guard let entry else { return "not checked" }
            return "\(entry.ok ? "OK" : "NO") \(entry.detail)" + (entry.updated.map { " (updated \($0.formatted(.iso8601)))" } ?? "")
        }
        let widget = live.widgetStatus
        return (["[Data sources]"] + SourceStatus.Source.allCases.map { source in
            "\(source.rawValue): app \(line(live.status.entries[source]))"
                + (widget.map { "; widget \(line($0.entries[source]))" } ?? "; widget: see the large check widget (no App Group)")
        }).joined(separator: "\n")
    }

    /// What the signing store gave one bundle: signed identity and entitlements, and the profile.
    private func signingSection(_ signing: BundleSigning) -> some View {
        let signature = signing.signature
        let profile = signing.profile.profile
        return Section {
            valueRow("diag.signing.bundleID", signing.bundleID ?? "—")
            valueRow("diag.signing.identifier", signature?.identifier ?? "—")
            valueRow("diag.signing.team", signature.map { $0.teamID ?? ($0.isAdHoc ? "ad hoc" : "—") } ?? "—")
            valueRow("diag.signing.groups", signature.map { $0.appGroups.isEmpty ? "—" : $0.appGroups.joined(separator: "\n") } ?? "—")
            valueRow("diag.signing.entitlements", signature.map { $0.entitlementKeys.isEmpty ? "—" : $0.entitlementKeys.joined(separator: "\n") } ?? "—")
            valueRow("diag.profile", DiagnosticsModel.describe(signing.profile))
            valueRow("diag.team", profile?.teamIdentifiers.joined(separator: ", ") ?? "—")
            valueRow("diag.signing.expires", profile?.expirationDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
            valueRow("diag.profileGroups", profile.map { $0.appGroups.isEmpty ? "—" : $0.appGroups.joined(separator: "\n") } ?? "—")
        } header: {
            Text(verbatim: signing.name)
        } footer: {
            Text("diag.signing.footer")
        }
        .accessibilityIdentifier("ax.diag.signing.\(signing.name)")
    }

    private var appGroupSection: some View {
        Section {
            valueRow("diag.group.resolved", model.store.appGroupID ?? "—")
                .accessibilityIdentifier("ax.diag.groupName")
            valueRow("diag.group.source", model.store.source?.rawValue ?? "—")
            valueRow("diag.group.candidates", model.candidates.isEmpty ? "—"
                : model.candidates.map { "\($0.id) (\($0.source.rawValue))" }.joined(separator: "\n"))
            statusRow("diag.group.shared", ok: model.store.isShared)
                .accessibilityIdentifier("ax.diag.appGroup")
            outcomeRow("diag.group.readWrite", model.appGroupTest)
            valueRow("diag.group.value", model.testValue.map { "#\($0)" } ?? "—")
            Button("diag.group.write", action: model.writeTestValue)
                .accessibilityIdentifier("ax.diag.writeValue")
        } header: {
            Text("diag.section.appGroup")
        } footer: {
            Text("diag.group.footer")
        }
    }

    private var widgetSection: some View {
        Section {
            if let report = model.widgetReport {
                valueRow("diag.widget.lastReport", report.date.formatted(date: .abbreviated, time: .standard))
                statusRow("diag.widget.sawApp", ok: report.appHeartbeat != nil,
                          detail: report.appHeartbeat.map { "#\($0.testValue)" })
                statusRow("diag.widget.locationAuthorized", ok: report.locationAuthorizedForWidget)
                outcomeRow("diag.widget.location", report.location)
                outcomeRow("diag.widget.battery", report.battery)
            } else {
                Text(model.store.isShared ? LocalizedStringKey("diag.widget.none") : "diag.widget.notShared")
                    .foregroundStyle(.secondary)
            }
            if let reloaded = model.widgetReloadedAt {
                valueRow("diag.widget.reloadRequested", reloaded.formatted(date: .omitted, time: .standard))
            }
        } header: {
            Text("diag.section.widget")
        } footer: {
            Text("diag.widget.footer")
        }
    }

    private var locationSection: some View {
        Section {
            statusRow("diag.location.permission", ok: model.locationAllowed,
                      detail: DiagnosticsModel.describe(model.locationStatus))
            if model.locationStatus == .notDetermined {
                Button("diag.location.request", action: model.requestLocation)
                    .accessibilityIdentifier("ax.diag.location")
            }
        } header: {
            Text("diag.section.location")
        } footer: {
            Text("diag.location.footer")
        }
    }

    private var healthSection: some View {
        Section("diag.section.health") {
            statusRow("diag.health.available", ok: model.healthAvailable)
            if let granted = model.profileGrantsHealthKit {
                statusRow("diag.health.entitlement", ok: granted)
            }
            outcomeRow("diag.health.steps", model.health)
            Button {
                Task { await model.runHealthKit() }
            } label: {
                HStack {
                    Text("diag.health.run")
                    if model.healthRunning { Spacer(); ProgressView() }
                }
            }
            .disabled(model.healthRunning)
            .accessibilityIdentifier("ax.diag.health")
        }
    }

    // MARK: Rows

    private func valueRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
    }

    private func statusRow(_ title: LocalizedStringKey, ok: Bool, detail: String? = nil) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                if let detail { Text(verbatim: detail).foregroundStyle(.secondary) }
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? .green : .red)
                    .accessibilityLabel(Text(ok ? LocalizedStringKey("common.yes") : "common.no"))
            }
        } label: {
            Text(title)
        }
    }

    private func outcomeRow(_ title: LocalizedStringKey, _ outcome: ProbeOutcome) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                switch outcome {
                case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                case .notRun: Text("diag.notRun").foregroundStyle(.secondary)
                }
            }
            switch outcome {
            case .ok(let detail), .failed(let detail):
                Text(verbatim: detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            case .notRun:
                EmptyView()
            }
        }
    }
}

/// One reload log line (ADR-030), left to right like the other log lines.
private struct ReloadRow: View {
    let entry: ReloadLog.Entry

    private var detail: String {
        var parts: [String] = [entry.date.formatted(date: .omitted, time: .standard), entry.reason]
        if let count = entry.entries { parts.append("\(count) entries") }
        if let next = entry.next { parts.append("next " + next.formatted(date: .omitted, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: entry.kind).font(.footnote.monospaced())
            Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}
