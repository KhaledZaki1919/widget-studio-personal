import SwiftUI
import WidgetKitCore

@main
struct WidgetStudioApp: App {
    @State private var designs = DesignsModel()
    @State private var appState = AppState()
    /// Real data for previews and Settings (M4, ADR-016).
    @State private var live = LiveDataModel()
    /// Shortcut tiles' setup and runs (ADR-017).
    @State private var tiles = TilesModel()
    /// Online/offline for the AI flow's notice (M6).
    @State private var network = NetworkStatus()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // UI tests launch with -uiTesting and start without saved designs.
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let model = DesignsModel()
            model.deleteAll()
            // AI starts from defaults, so the consent sheet shows every run.
            AISettings().save()
            // The introduction only when a test asks for it.
            let introDone = !ProcessInfo.processInfo.arguments.contains("-uiTestingOnboarding")
            UserDefaults.standard.set(introDone, forKey: AppState.onboardingDoneKey)
            UserDefaults.standard.set(introDone, forKey: AppState.permissionsSeenKey)
            _appState = State(initialValue: AppState())
            // App Store screenshots: a few saved designs in My widgets.
            if ProcessInfo.processInfo.arguments.contains("-uiTestingSeedDesigns") {
                Self.seedDesigns(into: model)
            }
            _designs = State(initialValue: model)
        }
        // UI tests of Create from image: canned replies, no key, no network.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingStubAI") {
            AIService.overrideProvider = UITestingAIProvider(calendar: ProcessInfo.processInfo.arguments.contains("-uiTestingStubCalendar"))
        }
    }

    /// Four designs for the My widgets screenshot, named in the test's language.
    private static func seedDesigns(into model: DesignsModel) {
        let language = RenderContext.preferredLanguage
        let picks: [(String, String, String)] = [
            ("mono.prayer.day", "مواقيت اليوم", "Today's prayers"),
            ("mono.weather.forecast", "طقس القاهرة", "Cairo weather"),
            ("mono.clock.digital", "ساعة المكتب", "Desk clock"),
            ("mono.countdown.red", "العيد", "Holiday"),
        ]
        for (id, ar, en) in picks.reversed() {
            guard case .success(let spec) = TemplateLibrary.load(id: id) else { continue }
            try? model.save(SavedDesign(name: language == "ar" ? ar : en, template: spec), newPhoto: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(designs)
                .environment(appState)
                .environment(live)
                .environment(tiles)
                .environment(network)
                .task { await live.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await live.refresh() } }
                }
        }
    }
}
