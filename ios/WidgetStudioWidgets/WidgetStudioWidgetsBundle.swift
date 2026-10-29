import SwiftUI
import WidgetKit
import WidgetKitCore

/// Store mode (default, ADR-014): one widget per template (ADR-013) in category bundles, one
/// "My widget" per size, and the check widget. Developer mode (WS_DEVELOPER): the configurable
/// widget for saved designs and templates, and the check widget. Each block stays within the
/// builder's limit of 10 widgets.
@main
struct WidgetStudioWidgetsBundle: WidgetBundle {
    var body: some Widget {
        #if WS_DEVELOPER
        DeveloperWidgets().body
        #else
        TimeTemplateWidgets().body
        WeatherTemplateWidgets().body
        HealthTemplateWidgets().body
        PrayerTemplateWidgets().body
        CountdownTemplateWidgets().body
        PhotoTemplateWidgets().body
        TilesTemplateWidgets().body
        CounterTemplateWidgets().body
        PersonalWidgets().body
        #endif
        #if DEBUG || WS_DEVELOPER
        // Install checks (Diagnostics, ADR-005); large shows the widget step log. Not in release
        // builds (M6): the gallery shows only real widgets.
        ProbeWidget()
        #endif
    }
}
