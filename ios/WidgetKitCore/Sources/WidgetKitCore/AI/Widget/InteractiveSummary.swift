import Foundation

/// What a design does (ADR-027), for the result screen: which elements are live, which are
/// tappable and what they do, and which only look like controls. Each item points at its layer,
/// so "Change" opens the layer editor there.
public struct InteractiveSummary: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Identifiable {
        public var id: String { "\(path)|\(capability ?? title)" }
        /// The layer; empty for a decorative note with no layer of its own.
        public let path: LayerEditing.Path
        public let title: String
        /// The capability id, nil for decorative items.
        public let capability: String?
        public let detail: String?
    }

    public let live: [Item]
    public let tappable: [Item]
    public let decorative: [Item]

    public var isEmpty: Bool { live.isEmpty && tappable.isEmpty && decorative.isEmpty }

    public static func build(_ spec: WidgetSpec, language: String, platform: CapabilityPlatform = .ios) -> InteractiveSummary {
        var live: [Item] = []
        var tappable: [Item] = []
        var decorative: [Item] = []
        var buttons: [Frame] = []
        for item in AutoWire.walk(spec.layers) {
            guard case .button = item.layer.content else { continue }
            buttons.append(item.frame)
        }
        func title(_ capability: Capability) -> String { capability.title.resolved(language: language) }
        func note(_ capability: Capability) -> String? {
            switch capability.support(on: platform) {
            case .shortcut: language.hasPrefix("ar") ? "عبر اختصار" : "through a Shortcut"
            case .panel: language.hasPrefix("ar") ? "يفتح لوحة النظام" : "opens the system panel"
            case .unsupported: language.hasPrefix("ar") ? "غير متاح على هذا النظام" : "not available on this system"
            case .native: nil
            }
        }
        for item in AutoWire.walk(spec.layers) {
            var names: [String] = []
            switch item.layer.content {
            case .text(let text):
                names = Bindings.names(in: text.value.resolved(language: "en")) + [text.live?.target].compactMap { $0 }.flatMap(Bindings.names(in:))
                    + (text.spans ?? []).flatMap { Bindings.names(in: $0.text.resolved(language: "en")) }
            case .chart(let chart): names = Bindings.names(in: chart.values)
            case .shape(let shape): names = Bindings.names(in: shape.progress ?? "")
            case .icon(let icon): names = Bindings.names(in: icon.symbol)
            case .ring(let ring): names = Bindings.names(in: ring.progress)
            case .progressBar(let bar): names = Bindings.names(in: bar.progress)
            case .dotGrid(let grid): names = Bindings.names(in: grid.values)
            case .dotBars(let bars): names = Bindings.names(in: bars.values)
            case .image(let image): names = Bindings.names(in: image.source)
            case .list(let list):
                names = list.items.flatMap { item in
                    [item.title, item.detail, item.subtitle, item.detail2].compactMap { $0 }.flatMap { Bindings.names(in: $0.resolved(language: "en")) }
                }
            case .analogClock: names = ["time.hh"]
            case .forecastRow: names = ["weather.temp"]
            case .states(let states): names = states.expanded.compactMap(\.when).flatMap(Bindings.names(in:)) + Bindings.names(in: states.value ?? "")
            case .button(let button):
                if let capability = Capabilities.action(button.action.rawValue) {
                    tappable.append(Item(path: item.path, title: title(capability), capability: capability.id, detail: note(capability)))
                }
                continue
            default:
                break
            }
            names += Bindings.names(in: item.layer.rotation ?? "")
            let capabilities = names.compactMap { Capabilities.binding($0) }
            var shown = Set<String>()
            for capability in capabilities where shown.insert(capability.id).inserted {
                live.append(Item(path: item.path, title: title(capability), capability: capability.id, detail: note(capability)))
            }
            // An icon that looks like a control but has no tap area.
            if case .icon(let icon) = item.layer.content, capabilities.isEmpty,
               !buttons.contains(where: { AutoWire.Run.inside(item.frame, $0) }),
               Capabilities.actions.contains(where: { $0.group != "open" && $0.icons.contains(icon.symbol) }) {
                decorative.append(Item(path: item.path, title: icon.symbol, capability: nil, detail: nil))
            }
        }
        for entry in spec.decorative ?? [] {
            decorative.append(Item(path: [], title: entry.element, capability: nil, detail: entry.reason))
        }
        // What the product rules still find after the post-pass (ADR-028): static when unsure, marked here.
        for finding in DesignRules.check(spec).findings where !decorative.contains(where: { $0.path == finding.path && !finding.path.isEmpty }) {
            decorative.append(Item(path: finding.path, title: finding.element, capability: nil, detail: finding.message.resolved(language: language)))
        }
        return InteractiveSummary(live: live, tappable: tappable, decorative: decorative)
    }
}

/// An element the AI found no capability for, with why (prompt v5's wiring list).
public struct DecorativeNote: Codable, Sendable, Equatable {
    public var element: String
    public var reason: String

    public init(element: String, reason: String) {
        self.element = element
        self.reason = reason
    }
}
