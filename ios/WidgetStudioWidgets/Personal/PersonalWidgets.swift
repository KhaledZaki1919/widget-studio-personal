import SwiftUI
import WidgetKit

/// Personal build (docs/personal.md): the official "My widget" sizes plus the slot widgets that
/// show a design sent from the app to their code. `WidgetStudioWidgetsBundle` lists this instead
/// of `MyWidgets`, so the top-level bundle stays within its 10-line limit.
struct PersonalWidgets: WidgetBundle {
    var body: some Widget {
        MyWidgets().body
        Slot1Widget()
        Slot2Widget()
        Slot3Widget()
        Slot4Widget()
        Slot5Widget()
        SlotPickWidget()
    }
}
