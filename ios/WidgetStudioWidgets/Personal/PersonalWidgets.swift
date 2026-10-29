import SwiftUI
import WidgetKit

/// Personal build (docs/personal.md): the official "My widget" sizes plus the three "Widget
/// Studio" switcher widgets. `WidgetStudioWidgetsBundle` lists this instead of `MyWidgets`, so the
/// top-level bundle stays within its 10-line limit.
struct PersonalWidgets: WidgetBundle {
    var body: some Widget {
        MyWidgets().body
        SmallSwitcherWidget()
        MediumSwitcherWidget()
        LargeSwitcherWidget()
    }
}
