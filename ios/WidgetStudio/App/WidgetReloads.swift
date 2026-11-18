import WidgetKit
import WidgetKitCore

/// Every reload the app asks for, with its reason in the reload log (ADR-030). Reloads asked while the app
/// is in the foreground don't count against the widgets' daily budget; the one when it goes to the
/// background makes the home screen current as the user returns to it.
enum AppReloads {
    static func all(_ reason: String) {
        ReloadLog.record(kind: "all", reason: reason)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
