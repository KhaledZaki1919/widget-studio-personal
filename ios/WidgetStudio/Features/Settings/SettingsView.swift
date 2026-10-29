import SwiftUI
import UIKit
import WidgetKitCore

/// Settings (brief §7.6, M4): weather units, prayer calculation method, step goal, location and
/// Health permissions, the Shortcut tiles guide. In store mode the widget can't see these
/// settings (no App Group) and uses the defaults, which the note says (ADR-016).
struct SettingsView: View {
    @Environment(LiveDataModel.self) private var live
    @Environment(DesignsModel.self) private var designs
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var showDiagnostics = false
    private let language = RenderContext.preferredLanguage

    var body: some View {
        List {
            if !designs.isShared {
                Section {
                    Label("settings.storeMode", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("ax.settings.storeMode")
                }
            }
            Section {
                NavigationLink {
                    AISettingsView()
                } label: {
                    Label("ai.title", systemImage: "sparkles")
                }
                .accessibilityIdentifier("ax.settings.ai")
            } footer: {
                Text("ai.settings.footer")
            }
            PairWidgetSection() // Personal build (docs/personal.md)
            Section {
                Picker("settings.clock", selection: binding(\.clockFormat)) {
                    Text("settings.clock.device").tag(ClockFormat.device)
                    Text("settings.clock.h12").tag(ClockFormat.h12)
                    Text("settings.clock.h24").tag(ClockFormat.h24)
                }
                .accessibilityIdentifier("ax.settings.clock")
            } footer: {
                Text("settings.clock.footer")
            }
            Section("settings.weather") {
                Picker("settings.units", selection: binding(\.temperatureUnit)) {
                    Text("settings.units.celsius").tag(AppSettings.TemperatureUnit.celsius)
                    Text("settings.units.fahrenheit").tag(AppSettings.TemperatureUnit.fahrenheit)
                }
                .accessibilityIdentifier("ax.settings.units")
            }
            Section {
                Picker("settings.prayer.method", selection: binding(\.prayerMethod)) {
                    ForEach(PrayerCalculator.methods, id: \.self) { method in
                        Text(verbatim: Self.methodName(method, language: language)).tag(method)
                    }
                }
                .accessibilityIdentifier("ax.settings.method")
                NavigationLink("compass.title") { QiblaView() }
                    .accessibilityIdentifier("ax.settings.qibla")
            } header: {
                Text("settings.prayer")
            } footer: {
                Text("settings.prayer.footer")
            }
            Section("settings.health") {
                Stepper(value: binding(\.stepGoal), in: 1000...40000, step: 500) {
                    LabeledContent("settings.steps.goal", value: "\(live.settings.stepGoal)")
                }
                .accessibilityIdentifier("ax.settings.stepGoal")
            }
            Section {
                Toggle("tasbeeh.autoAdvance", isOn: binding(\.tasbeehAutoAdvance))
                    .accessibilityIdentifier("ax.settings.autoAdvance")
                NavigationLink {
                    DhikrListView()
                } label: {
                    LabeledContent("tasbeeh.list", value: "\(live.settings.dhikrList.count)")
                }
                .accessibilityIdentifier("ax.settings.dhikrs")
            } header: {
                Text("tasbeeh.title")
            } footer: {
                Text(designs.isShared ? "tasbeeh.footer" : "tasbeeh.footer.storeMode")
            }
            permissionsSection
            Section {
                NavigationLink("tiles.list.title") { TilesListView() }
                    .accessibilityIdentifier("ax.settings.tiles")
                NavigationLink("settings.shortcuts.guide") { ShortcutGuideView() }
                    .accessibilityIdentifier("ax.settings.shortcutGuide")
            }
            Section {
                Button("settings.intro") { appState.isShowingOnboarding = true }
                    .accessibilityIdentifier("ax.settings.intro")
                Link(destination: AppInfo.privacyURL) {
                    Label("settings.privacy", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("ax.settings.privacy")
                Link(destination: AppInfo.supportURL) {
                    Label("settings.support", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("ax.settings.support")
                // Long-press opens the hidden Diagnostics (M6).
                LabeledContent("settings.version", value: AppInfo.versionText)
                    .contentShape(Rectangle())
                    .onLongPressGesture { showDiagnostics = true }
                    .accessibilityIdentifier("ax.settings.version")
            }
        }
        .navigationTitle("settings.title")
        .navigationDestination(isPresented: $showDiagnostics) { DiagnosticsView() }
        .task { await live.refresh() }
        .refreshable { await live.refresh() }
    }

    private var permissionsSection: some View {
        Section {
            LabeledContent("settings.location") {
                Text(locationStatus).foregroundStyle(live.isLocationAllowed ? .green : .secondary)
            }
            if live.authorization == .notDetermined {
                Button("settings.location.allow", action: live.requestLocation)
                    .accessibilityIdentifier("ax.settings.location.allow")
            } else if !live.isLocationAllowed {
                Button("settings.openSystemSettings", action: openSystemSettings)
            }
            LabeledContent("settings.healthAccess") {
                Text(healthStatus).foregroundStyle(healthOK ? .green : .secondary)
            }
            Button("settings.health.allow") { Task { await live.requestHealth() } }
                .accessibilityIdentifier("ax.settings.health.allow")
        } header: {
            Text("settings.permissions")
        } footer: {
            Text("settings.permissions.footer")
        }
    }

    private var locationStatus: LocalizedStringKey {
        switch live.authorization {
        case .authorizedWhenInUse, .authorizedAlways: "settings.status.allowed"
        case .denied, .restricted: "settings.status.denied"
        default: "settings.status.notAsked"
        }
    }

    private var healthOK: Bool {
        if case .success? = live.inputs.health { return true }
        return false
    }

    private var healthStatus: LocalizedStringKey {
        switch live.inputs.health {
        case .success?: "settings.status.reading"
        case .failure(.unavailable)?: "settings.status.unavailable"
        case .failure(.noData)?: "settings.status.noData"
        case .failure(.error)?: "settings.status.error"
        case nil: "settings.status.notAsked"
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { live.settings[keyPath: keyPath] }, set: { value in live.update { $0[keyPath: keyPath] = value } })
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    /// Display names of adhan-swift's methods.
    static func methodName(_ method: String, language: String) -> String {
        let names: [String: (en: String, ar: String)] = [
            "egyptian": ("Egyptian General Authority of Survey", "الهيئة المصرية العامة للمساحة"),
            "muslimWorldLeague": ("Muslim World League", "رابطة العالم الإسلامي"),
            "ummAlQura": ("Umm al-Qura, Makkah", "أم القرى، مكة"),
            "dubai": ("Dubai", "دبي"),
            "kuwait": ("Kuwait", "الكويت"),
            "qatar": ("Qatar", "قطر"),
            "karachi": ("University of Islamic Sciences, Karachi", "جامعة العلوم الإسلامية، كراتشي"),
            "northAmerica": ("ISNA, North America", "الجمعية الإسلامية لأمريكا الشمالية"),
            "moonsightingCommittee": ("Moonsighting Committee", "لجنة رؤية الهلال"),
            "singapore": ("Singapore", "سنغافورة"),
            "turkey": ("Diyanet, Turkey", "رئاسة الشؤون الدينية، تركيا"),
            "tehran": ("Institute of Geophysics, Tehran", "معهد الجيوفيزياء، طهران"),
        ]
        guard let name = names[method] else { return method }
        return language == "ar" ? name.ar : name.en
    }
}

/// How to make a Shortcut for a tile (brief §2: tiles run Shortcuts, iOS widgets can't toggle settings).
struct ShortcutGuideView: View {
    var body: some View {
        List {
            Section {
                Text("guide.intro").font(.callout)
            }
            Section("guide.steps") {
                ForEach(1...5, id: \.self) { step in
                    Label {
                        Text(LocalizedStringKey("guide.step\(step)"))
                    } icon: {
                        Text(verbatim: "\(step)")
                            .font(.caption.weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.accentColor.opacity(0.2)))
                    }
                }
            }
            Section("guide.examples") {
                Text("guide.examples.body").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings.shortcuts.guide")
    }
}
