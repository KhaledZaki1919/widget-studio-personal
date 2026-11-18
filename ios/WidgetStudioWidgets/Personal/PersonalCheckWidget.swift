import SwiftUI
import WidgetKit
import WidgetKitCore

// Personal build (docs/personal.md): "Widget Studio P check", always in the gallery (release builds
// too), first in `PersonalWidgets`. If the gallery lists it, the extension loads and its widget list
// is valid; if Widget Studio P is missing from the gallery entirely, the extension never loaded
// (install or signing), not one widget's drawing. Kept as small as possible: a static
// configuration, no network, no App Intents; the timeline only reads the bundle and the
// App Group resolver.

struct PersonalCheckWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WidgetStudioP.check", provider: PersonalCheckProvider()) { PersonalCheckView(entry: $0) }
            .configurationDisplayName(Text(personal: "widget.check.name"))
            .description(Text(personal: "widget.check.description"))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PersonalCheckEntry: TimelineEntry {
    let date: Date
    let bundleID: String
    let version: String
    /// The App Group this extension resolved; nil = its own container (normal on Fast Store).
    let group: String?
    let relay: Bool

    static func now() -> PersonalCheckEntry {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let relay = (info["WSRelayURL"] as? String).map { !$0.isEmpty } ?? false
        return PersonalCheckEntry(date: .now, bundleID: Bundle.main.bundleIdentifier ?? "?",
                                  version: "\(short) (\(build))", group: AppGroupResolver.resolve().appGroupID, relay: relay)
    }
}

struct PersonalCheckProvider: TimelineProvider {
    func placeholder(in context: Context) -> PersonalCheckEntry {
        PersonalCheckEntry(date: .now, bundleID: "com.khaled.widgetstudio.personal.widgets", version: "1.0", group: nil, relay: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PersonalCheckEntry) -> Void) {
        completion(.now())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PersonalCheckEntry>) -> Void) {
        let entry = PersonalCheckEntry.now()
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(3600))))
    }
}

struct PersonalCheckView: View {
    let entry: PersonalCheckEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(verbatim: "Widget Studio P").font(.caption.weight(.semibold))
            }
            Text(personal: "widget.check.loaded")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 0)
            Group {
                Text(verbatim: entry.bundleID)
                Text(verbatim: "v\(entry.version) · " + (entry.relay ? "relay ✓" : "relay ✗"))
                if family != .systemSmall {
                    Text(verbatim: "App Group: " + (entry.group ?? "— (own container)"))
                }
                Text(entry.date, style: .time)
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
        .containerBackground(Color(white: 0.055), for: .widget)
    }
}
