import SwiftUI
import WidgetKit

/// Personal build (docs/personal.md): the check widget, the official "My widget" sizes and the slot
/// widgets that show a design sent from the app to their code. `WidgetStudioWidgetsBundle` lists this
/// instead of `MyWidgets`, so the top-level bundle stays within its 10-line limit.
///
/// Only `StaticConfiguration` widgets here, like the official store build. "Slot (choose)"
/// (`SlotPickWidget`, an `AppIntentConfiguration`) is left out since the 2026-11-18 build where the
/// whole app vanished from the gallery: it was the one widget kind of a type the official store
/// build doesn't ship (ADR-013). Its code stays compiled for a later, separate test.
struct PersonalWidgets: WidgetBundle {
    var body: some Widget {
        PersonalCheckWidget()
        MyWidgets().body
        Slot1Widget()
        Slot2Widget()
        Slot3Widget()
        Slot4Widget()
        Slot5Widget()
    }
}
