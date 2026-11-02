import SwiftUI
import UIKit
import WidgetKit
import WidgetKitCore

/// Three tabs: the template library, My widgets (M3) and Settings (M4). Diagnostics (with the M1 test designs)
/// opens from the Library toolbar button (until M6), a long press on the version, or the check
/// widget (`widgetstudio://diagnostics`).
struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var showDiagnostics = false
    @State private var showQibla = false
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
        .onAppear(perform: AppInfo.touchHeartbeat)
        .onOpenURL { url in
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
                WidgetActions.perform(url, tiles: tiles)
            case "tiles":
                WidgetActions.tileSetup(url, tiles: tiles)
            default:
                break
            }
        }
    }
}

/// Actions a widget button sends to the app (`widgetstudio://action/<action>?arg=…`, ADR-016).
/// Shortcut tiles go to `TilesModel` (setup screen, or run the Shortcut); links open only
/// http/https pages. Counter and stopwatch buttons are interactive in the widget itself and
/// don't come here.
enum WidgetActions {
    @MainActor
    static func perform(_ url: URL, tiles: TilesModel) {
        let action = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let arg = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "arg" }?.value ?? ""
        switch action {
        case ButtonLayer.Action.shortcutRun.rawValue:
            tiles.tap(arg)
        case ButtonLayer.Action.openURL.rawValue:
            guard let target = URL(string: arg), let scheme = target.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                return
            }
            UIApplication.shared.open(target)
        default:
            break
        }
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
        WidgetCenter.shared.reloadAllTimelines()
        return nil
    }
}
