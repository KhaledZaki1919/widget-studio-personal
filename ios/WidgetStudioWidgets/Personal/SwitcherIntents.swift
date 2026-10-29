import AppIntents
import SwiftUI
import WidgetKit
import WidgetKitCore

// Personal build (docs/personal.md): the switcher widget's ◀ ▶ 🔒 buttons. Like the tasbeeh
// buttons they run in the widget extension and keep their state in its own container, so they
// need no App Group and no AppIntentConfiguration (ADR-013). WidgetKit reloads the widget after
// each tap; `quietUntil` lets that reload skip the network so the new design appears at once.

struct SwitcherStepIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("widget.switcher.intent.step", table: "Personal")
    static var isDiscoverable = false

    @Parameter(title: LocalizedStringResource("widget.switcher.intent.size", table: "Personal"), default: "small")
    var size: String

    /// 1 = next, -1 = previous.
    @Parameter(title: LocalizedStringResource("widget.switcher.intent.offset", table: "Personal"), default: 1)
    var offset: Int

    init() {}

    init(size: SpecFamily, offset: Int) {
        self.size = size.rawValue
        self.offset = offset
    }

    func perform() async throws -> some IntentResult {
        guard let family = SpecFamily(rawValue: size) else { return .result() }
        let cache = DataCache()
        var state = SwitcherState.load(family, cache)
        let keys = SwitcherProvider.keys(size: family, cache: cache)
        state.current = SwitcherCatalog.step(state.current, by: offset, keys: keys, size: family)
        state.quietUntil = Date.now.addingTimeInterval(20)
        try state.save(family, cache)
        WidgetLog.add("switcher \(size) \(offset > 0 ? "next" : "previous") -> \(state.current ?? "-")")
        return .result()
    }
}

struct SwitcherLockIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("widget.switcher.intent.lock", table: "Personal")
    static var isDiscoverable = false

    @Parameter(title: LocalizedStringResource("widget.switcher.intent.size", table: "Personal"), default: "small")
    var size: String

    init() {}

    init(size: SpecFamily) {
        self.size = size.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let family = SpecFamily(rawValue: size) else { return .result() }
        let cache = DataCache()
        var state = SwitcherState.load(family, cache)
        state.locked.toggle()
        state.quietUntil = Date.now.addingTimeInterval(20)
        try state.save(family, cache)
        WidgetLog.add("switcher \(size) \(state.locked ? "locked" : "unlocked")")
        return .result()
    }
}

/// ◀ ▶ 🔒 in the widget's corner; locked, only a faint 🔒 stays (tap it to show the arrows again).
struct SwitcherControls: View {
    let size: SpecFamily
    let locked: Bool

    var body: some View {
        HStack(spacing: 0) {
            if !locked {
                Button(intent: SwitcherStepIntent(size: size, offset: -1)) {
                    icon("chevron.left")
                }
                .accessibilityLabel(Text(personal: "widget.switcher.previous"))
                Button(intent: SwitcherStepIntent(size: size, offset: 1)) {
                    icon("chevron.right")
                }
                .accessibilityLabel(Text(personal: "widget.switcher.next"))
            }
            Button(intent: SwitcherLockIntent(size: size)) {
                icon(locked ? "lock.fill" : "lock.open")
            }
            .accessibilityLabel(Text(personal: locked ? "widget.switcher.unlock" : "widget.switcher.lock"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .background(Color.black.opacity(locked ? 0.18 : 0.45), in: Capsule())
        .opacity(locked ? 0.55 : 1)
        // ◀ always means "previous", in Arabic too.
        .environment(\.layoutDirection, .leftToRight)
        .padding(6)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
    }
}

extension Text {
    /// A string from the personal build's own table (`Personal.xcstrings`).
    init(personal key: LocalizedStringKey) {
        self.init(key, tableName: "Personal")
    }
}
