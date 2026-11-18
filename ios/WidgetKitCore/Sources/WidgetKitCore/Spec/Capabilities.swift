import Foundation

/// How a platform provides a capability (ADR-027).
public enum CapabilitySupport: String, Sendable {
    /// Works inside the widget or directly from a tap.
    case native
    /// iOS: a tap runs a Shortcut the user creates once.
    case shortcut
    /// Android: a tap opens the system panel for it.
    case panel
    /// The OS forbids it: the widget shows a hint on tap.
    case unsupported
}

public enum CapabilityPlatform: String, Sendable {
    case ios, android
}

/// One live value or tap action of `Resources/Spec/capabilities.json`, the single source of truth
/// (ADR-027). Validators, schema, prompt, instructions, pickers and auto-wire are built from these.
public struct Capability: Decodable, Sendable, Equatable, Identifiable {
    /// A value that may be one string or one per platform (`{"ios": …, "android": …}`).
    public struct PerPlatform: Decodable, Sendable, Equatable {
        public let both: String?
        public let ios: String?
        public let android: String?

        public init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer().decode(String.self) {
                both = single
                ios = nil
                android = nil
            } else {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                both = nil
                ios = try values.decodeIfPresent(String.self, forKey: .ios)
                android = try values.decodeIfPresent(String.self, forKey: .android)
            }
        }

        public func on(_ platform: CapabilityPlatform) -> String? {
            both ?? (platform == .ios ? ios : android)
        }

        enum CodingKeys: String, CodingKey { case ios, android }
    }

    /// The Shortcut an action runs on iOS: its name, and the Shortcuts action and option to pick.
    public struct ShortcutInfo: Decodable, Sendable, Equatable {
        public let name: String
        public let action: String
        public let option: String?
    }

    public let id: String
    public let group: String
    /// `text`, `number`, `bool`, `date`, `levels`, `symbol` or `image` (bindings only).
    public let type: String?
    public let title: LocalizedText
    public let description: String
    public let example: String?
    public let keywords: [String]
    public let icons: [String]
    /// Text glyphs that look like this control (⏭).
    public let glyphs: [String]
    /// Layer kinds it suits: `text`, `ring`, `progressBar`, `dotGrid`, `icon`, `when`, `rotation`…
    public let layers: [String]
    /// A share 0…1 that reads as a whole percent in text: what a level, ring or dots can show.
    public var isShare: Bool { type == "number" && layers.contains("ring") }

    /// Takes a key (`field.<key>`): resolved by `Bindings.Name`, not listed in `Bindings.catalog`.
    public let parametric: Bool
    public let ai: Bool
    /// What the action's `arg` holds: `url`, `shortcut`, `text`, `optional`, or nil for nothing.
    public let arg: String?
    /// The binding that shows this action's state.
    public let state: String?
    public let hint: LocalizedText?
    public let shortcut: ShortcutInfo?
    public let panel: String?
    let support: PerPlatform?
    let permission: PerPlatform?
    let note: PerPlatform?

    enum CodingKeys: String, CodingKey {
        case id, group, type, title, description, example, keywords, icons, glyphs, layers, parametric, ai, arg, state, hint, shortcut, panel,
             support, permission, note
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        group = try values.decode(String.self, forKey: .group)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        title = try values.decode(LocalizedText.self, forKey: .title)
        description = try values.decode(String.self, forKey: .description)
        example = try values.decodeIfPresent(String.self, forKey: .example)
        keywords = try values.decodeIfPresent([String].self, forKey: .keywords) ?? []
        icons = try values.decodeIfPresent([String].self, forKey: .icons) ?? []
        glyphs = try values.decodeIfPresent([String].self, forKey: .glyphs) ?? []
        layers = try values.decodeIfPresent([String].self, forKey: .layers) ?? []
        parametric = try values.decodeIfPresent(Bool.self, forKey: .parametric) ?? false
        ai = try values.decodeIfPresent(Bool.self, forKey: .ai) ?? true
        arg = try values.decodeIfPresent(String.self, forKey: .arg)
        state = try values.decodeIfPresent(String.self, forKey: .state)
        hint = try values.decodeIfPresent(LocalizedText.self, forKey: .hint)
        shortcut = try values.decodeIfPresent(ShortcutInfo.self, forKey: .shortcut)
        panel = try values.decodeIfPresent(String.self, forKey: .panel)
        support = try values.decodeIfPresent(PerPlatform.self, forKey: .support)
        permission = try values.decodeIfPresent(PerPlatform.self, forKey: .permission)
        note = try values.decodeIfPresent(PerPlatform.self, forKey: .note)
    }

    /// Native unless the catalog says otherwise.
    public func support(on platform: CapabilityPlatform) -> CapabilitySupport {
        support?.on(platform).flatMap(CapabilitySupport.init(rawValue:)) ?? .native
    }

    public func permission(on platform: CapabilityPlatform) -> String? { permission?.on(platform) }
    public func note(on platform: CapabilityPlatform) -> String? { note?.on(platform) }

    /// The validator's kind for a binding.
    public var bindingKind: Bindings.Kind {
        switch type {
        case "number": .number
        case "levels", "series": .levels
        case "date": .date
        case "symbol": .symbol
        case "image": .image
        default: .text
        }
    }

    /// The field type an action's `arg` must point to; nil when it needs no field.
    public var argFieldKind: FieldSpec.Kind? {
        switch arg {
        case "url": .url
        case "shortcut": .shortcut
        case "text": .text
        case "app": .app
        default: nil
        }
    }

    /// The hint for a tap the OS doesn't allow: the catalog's, or a generic one.
    public func hintText(language: String, platform: CapabilityPlatform) -> String {
        if let hint { return hint.resolved(language: language) }
        let name = title.resolved(language: language)
        let system = platform == .ios ? "iOS" : "Android"
        return language.hasPrefix("ar") ? "لا يسمح \(system) بـ«\(name)» من الويدجت." : "\(system) doesn't allow \(name) from a widget."
    }
}

public enum Capabilities {
    public struct Named: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let title: LocalizedText
    }

    struct Catalog: Decodable {
        var version = 0
        var permissions: [Named] = []
        var groups: [Named] = []
        var bindings: [Capability] = []
        var actions: [Capability] = []
        var stateSets: [StateSet] = []
    }

    private static let catalog: Catalog = {
        guard let url = Bundle.module.url(forResource: "capabilities", withExtension: "json", subdirectory: "Spec"),
              let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(Catalog.self, from: data) else {
            return Catalog()
        }
        return decoded
    }()

    public static var version: Int { catalog.version }
    public static var bindings: [Capability] { catalog.bindings }
    public static var actions: [Capability] { catalog.actions }
    public static var groups: [Named] { catalog.groups }
    public static var permissions: [Named] { catalog.permissions }
    /// Built-in state sets (ADR-028): the AI, the post-pass and the editor reuse them.
    public static var stateSets: [StateSet] { catalog.stateSets }

    public static func stateSet(_ id: String) -> StateSet? { catalog.stateSets.first { $0.id == id } }

    private static let bindingsByID = Dictionary(catalog.bindings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    private static let actionsByID = Dictionary(catalog.actions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    public static func binding(_ id: String) -> Capability? { bindingsByID[id.trimmingCharacters(in: .whitespaces)] }
    public static func action(_ id: String) -> Capability? { actionsByID[id] }
    public static func permission(_ id: String) -> Named? { catalog.permissions.first { $0.id == id } }

    /// The action whose Shortcut has this name.
    public static func action(shortcutName name: String) -> Capability? {
        let key = TileSetupState.key(name)
        return catalog.actions.first { $0.shortcut.map { TileSetupState.key($0.name) == key } ?? false }
    }

    /// Permissions a spec needs on `platform`, in catalog order.
    public static func permissions(for spec: WidgetSpec, on platform: CapabilityPlatform) -> [Named] {
        var ids = Set<String>()
        for name in DataRequirements.bindingNames(in: spec) {
            if let permission = binding(name)?.permission(on: platform) { ids.insert(permission) }
        }
        for layer in spec.allLayers {
            guard case .button(let button) = layer.content else { continue }
            if let permission = action(button.action.rawValue)?.permission(on: platform) { ids.insert(permission) }
        }
        return catalog.permissions.filter { ids.contains($0.id) }
    }
}
