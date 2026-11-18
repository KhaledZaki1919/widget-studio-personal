import SwiftUI
import UIKit
import WidgetKit
import WidgetKitCore

/// Four tabs: the template library, My widgets (M3), Tasks (ADR-028) and Settings (M4). Diagnostics (with the M1 test designs)
/// opens from the Library toolbar button (until M6), a long press on the version, or the check
/// widget (`widgetstudio://diagnostics`).
struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var showDiagnostics = false
    @State private var showQibla = false
    /// What a widget tap couldn't do here, and why (ADR-027).
    @State private var actionHint: String?
    @Environment(TilesModel.self) private var tiles

    var body: some View {
        @Bindable var appState = appState
        @Bindable var tiles = tiles
        TabView(selection: $appState.tab) {
            NavigationStack {
                // Diagnostics is hidden (M6): long-press the version at the bottom of the Library
                // or in Settings, or open widgetstudio://diagnostics.
                LibraryView(onLongPressVersion: { showDiagnostics = true })
                    .navigationTitle("library.title")
                    .navigationDestination(isPresented: $showDiagnostics) {
                        DiagnosticsView()
                    }
            }
            .tabItem { Label("tab.library", systemImage: "square.grid.2x2") }
            .tag(AppState.Tab.library)

            NavigationStack {
                MyWidgetsView()
            }
            .tabItem { Label("tab.myWidgets", systemImage: "rectangle.stack") }
            .tag(AppState.Tab.myWidgets)

            NavigationStack {
                TasksView()
            }
            .tabItem { Label("tab.tasks", systemImage: "checklist") }
            .tag(AppState.Tab.tasks)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("tab.settings", systemImage: "gearshape") }
            .tag(AppState.Tab.settings)
        }
        .fullScreenCover(isPresented: $appState.isShowingOnboarding) {
            OnboardingView(permissionsOnly: appState.onboardingPermissionsOnly, onFinish: appState.finishOnboarding)
        }
        .sheet(isPresented: $appState.isCreatingFromImage) {
            CreateFromImageView()
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showQibla) {
            NavigationStack {
                QiblaView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("common.done") { showQibla = false }
                        }
                    }
            }
        }
        .sheet(item: $tiles.request) { request in
            NavigationStack {
                TileSetupView(name: request.name, failed: request.failed)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.cancel") { tiles.request = nil }
                        }
                    }
            }
        }
        .alert("action.hint.title", isPresented: Binding(get: { actionHint != nil }, set: { if !$0 { actionHint = nil } })) {
            Button("common.done") { actionHint = nil }
        } message: {
            Text(verbatim: actionHint ?? "")
        }
        .onAppear(perform: AppInfo.touchHeartbeat)
        .onOpenURL { url in
            // A .json or .zip opened or shared to the app starts bulk import (ADR-027).
            if url.isFileURL {
                appState.isCreatingFromImage = false
                appState.tab = .myWidgets
                appState.pendingBulk = BulkRequest(urls: [url])
                return
            }
            guard url.scheme == "widgetstudio" else { return }
            switch url.host() {
            case "diagnostics":
                appState.tab = .library
                showDiagnostics = true
            case "mywidgets":
                appState.tab = .myWidgets
            case "settings":
                appState.tab = .settings
            case "qibla":
                showQibla = true
            case "action":
                switch WidgetActions.perform(url, tiles: tiles) {
                case .compass: showQibla = true
                case .addTask:
                    appState.tab = .tasks
                    appState.isAddingTask = true
                case .hint(let text): actionHint = text
                case .done: break
                }
            case "tiles":
                WidgetActions.tileSetup(url, tiles: tiles)
            default:
                break
            }
        }
    }
}

/// Actions a widget button sends to the app (`widgetstudio://action/<action>?arg=…`, ADR-016,
/// ADR-027). The catalog decides: a Shortcut action goes to `TilesModel`, an action the OS forbids
/// shows its hint, the rest open what they name. Actions the extension runs itself never come here.
enum WidgetActions {
    enum Outcome: Equatable {
        case done
        case compass
        case addTask
        case hint(String)
    }

    @MainActor
    static func perform(_ url: URL, tiles: TilesModel) -> Outcome {
        let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let arg = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "arg" }?.value ?? ""
        let language = RenderContext.preferredLanguage
        guard let capability = Capabilities.action(id) else { return .done }
        if capability.support(on: .ios) == .unsupported {
            return .hint(capability.hintText(language: language, platform: .ios))
        }
        if id == ButtonLayer.Action.shortcutRun.rawValue {
            if arg.isEmpty { return .hint(needsValue(capability, language: language)) }
            tiles.tap(arg)
            return .done
        }
        // Shortcut actions, and media controls that reach the app (arg "shortcut", or no Apple Music access).
        if let shortcut = capability.shortcut, capability.support(on: .ios) == .shortcut || capability.group == "media" {
            tiles.tap(shortcut.name)
            return .done
        }
        switch id {
        case "compass.open":
            return .compass
        case "task.add":
            return .addTask
        case "open.url":
            guard let target = URL(string: arg), let scheme = target.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                return .hint(needsValue(capability, language: language))
            }
            UIApplication.shared.open(target)
        case "open.deeplink":
            guard let target = URL(string: arg), let scheme = target.scheme?.lowercased(), !["file", "javascript", "data"].contains(scheme) else {
                return .hint(needsValue(capability, language: language))
            }
            UIApplication.shared.open(target)
        case "call.dial", "message.open":
            let digits = arg.filter { $0.isNumber || $0 == "+" }
            guard !digits.isEmpty, let target = URL(string: (id == "call.dial" ? "tel:" : "sms:") + digits) else {
                return .hint(needsValue(capability, language: language))
            }
            UIApplication.shared.open(target)
        case "calendar.open": open("calshow://")
        case "reminders.open": open("x-apple-reminderkit://")
        case "weather.open": open("weather://")
        // ADR-029: the Clock app (alarms, world clock) and Apple Health.
        case "alarm.open": open("clock-alarm://")
        case "clock.open": open("clock-worldclock://")
        case "health.open": open("x-apple-health://")
        case "media.open": open("music://")
        default: break
        }
        return .done
    }

    private static func open(_ link: String) {
        if let url = URL(string: link) { UIApplication.shared.open(url) }
    }

    private static func needsValue(_ capability: Capability, language: String) -> String {
        let name = capability.title.resolved(language: language)
        return language == "ar" ? "اضبط قيمة «\(name)» في المحرر أولًا." : "Set the value for \(name) in the editor first."
    }

    /// `widgetstudio://tiles/setup?name=…[&error=1]`: a tile's setup screen, or Shortcuts' error callback.
    @MainActor
    static func tileSetup(_ url: URL, tiles: TilesModel) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let name = items.first(where: { $0.name == "name" })?.value, !name.isEmpty else { return }
        if items.contains(where: { $0.name == "error" }) {
            tiles.shortcutFailed(name)
        } else {
            tiles.request = TileSetupRequest(name: name, failed: tiles.status(name) == .failed)
        }
    }
}

enum AppInfo {
    /// Static pages on GitHub Pages (site/, M6), in the app's language.
    static var privacyURL: URL { page("privacy") }
    static var supportURL: URL { page("support") }

    private static func page(_ name: String) -> URL {
        let anchor = RenderContext.preferredLanguage == "ar" ? "ar" : "en"
        return URL(string: "https://khaledzaki1919.github.io/widget-studio/\(name).html#\(anchor)")
            ?? URL(fileURLWithPath: "/")
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// Refreshes the app heartbeat (keeping the test value) and asks the widget to reload.
    static func touchHeartbeat() {
        writeHeartbeat(changeValue: 0)
    }

    @discardableResult
    static func writeHeartbeat(changeValue delta: Int) -> Error? {
        let location = AppGroupResolver.resolve()
        let store = ProbeStore(location: location)
        let value = (store.readAppHeartbeat()?.testValue ?? 0) + delta
        do {
            try store.writeAppHeartbeat(AppHeartbeat(
                date: .now,
                bundleID: Bundle.main.bundleIdentifier ?? "",
                appGroupID: location.appGroupID,
                testValue: value
            ))
        } catch {
            return error
        }
        AppReloads.all("action from a widget link")
        return nil
    }
}
