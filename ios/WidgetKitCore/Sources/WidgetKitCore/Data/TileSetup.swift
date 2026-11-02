import Foundation

/// How to build the Shortcut a tile runs (M4 feedback, ADR-017). iOS doesn't let a widget or an
/// app switch Wi-Fi, the torch or Dark Mode, but a Shortcut can, so each tile runs the Shortcut
/// with its name. Action names are the English names in the Shortcuts app's search.
public struct ShortcutRecipe: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case wifi, torch, appearance, bluetooth, airplane, lowPower, cellular, orientation, silent, qr, camera, custom
    }

    public let kind: Kind
    /// The Shortcuts action to search for, e.g. "Set Wi-Fi"; nil for a custom Shortcut.
    public let action: String?
    /// What to choose in the action ("Toggle"), as shown in Shortcuts.
    public let option: String?
    /// The SF Symbol shown in the setup screen.
    public let symbol: String

    /// The recipe for a tile's Shortcut name: the templates' default names and common variants
    /// ("Wifi", "Flashlight", "الكشاف"…); anything else is a custom Shortcut.
    public static func forName(_ name: String) -> ShortcutRecipe {
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        func has(_ words: String...) -> Bool { words.contains { key.contains($0) } }
        let kind: Kind = if has("wifi", "wlan", "واي") {
            .wifi
        } else if has("torch", "flash", "كشاف", "فلاش") {
            .torch
        } else if has("dark", "appearance", "داكن", "ليلي", "مظهر") {
            .appearance
        } else if has("bluetooth", "بلوتوث") {
            .bluetooth
        } else if has("airplane", "aeroplane", "flight", "طيران") {
            .airplane
        } else if has("lowpower", "battery", "توفير", "طاقة") {
            .lowPower
        } else if has("cellular", "mobiledata", "data", "بيانات") {
            .cellular
        } else if has("rotation", "orientation", "rotate", "تدوير") {
            .orientation
        } else if has("mute", "silent", "silence", "صامت", "كتم") {
            .silent
        } else if has("qr", "barcode", "باركود") {
            .qr
        } else if has("camera", "كاميرا") {
            .camera
        } else {
            .custom
        }
        return recipe(kind)
    }

    public static func recipe(_ kind: Kind) -> ShortcutRecipe {
        switch kind {
        case .wifi: ShortcutRecipe(kind: kind, action: "Set Wi-Fi", option: "Toggle", symbol: "wifi")
        case .torch: ShortcutRecipe(kind: kind, action: "Set Flashlight", option: "Toggle", symbol: "flashlight.on.fill")
        case .appearance: ShortcutRecipe(kind: kind, action: "Set Appearance", option: "Toggle", symbol: "circle.lefthalf.filled")
        case .bluetooth: ShortcutRecipe(kind: kind, action: "Set Bluetooth", option: "Toggle", symbol: "dot.radiowaves.left.and.right")
        case .airplane: ShortcutRecipe(kind: kind, action: "Set Airplane Mode", option: "Toggle", symbol: "airplane")
        case .lowPower: ShortcutRecipe(kind: kind, action: "Set Low Power Mode", option: "Toggle", symbol: "battery.25")
        case .cellular: ShortcutRecipe(kind: kind, action: "Set Cellular Data", option: "Toggle", symbol: "antenna.radiowaves.left.and.right")
        case .orientation: ShortcutRecipe(kind: kind, action: "Set Orientation Lock", option: "Toggle", symbol: "lock.rotation")
        case .silent: ShortcutRecipe(kind: kind, action: "Set Silent Mode", option: "Toggle", symbol: "bell.slash.fill")
        case .qr: ShortcutRecipe(kind: kind, action: "Scan QR or Barcode", option: nil, symbol: "qrcode")
        case .camera: ShortcutRecipe(kind: kind, action: "Open Camera", option: nil, symbol: "camera.fill")
        case .custom: ShortcutRecipe(kind: kind, action: nil, option: nil, symbol: "square.on.square")
        }
    }
}

/// Which tile Shortcuts the user has set up (the app's own container; tile taps always come to
/// the app, so this needs no App Group).
public struct TileSetupState: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        /// The name as the user wrote it (entries are keyed case-insensitively).
        public var name: String?
        /// When the user said "I created it"; nil = not set up yet.
        public var confirmed: Date?
        public var lastRun: Date?
        /// Shortcuts reported an error (usually: no Shortcut with this name).
        public var lastError: Date?

        public init(confirmed: Date? = nil, lastRun: Date? = nil, lastError: Date? = nil) {
            self.confirmed = confirmed
            self.lastRun = lastRun
            self.lastError = lastError
        }
    }

    public enum Status: String, Sendable {
        case notSetUp, ready, failed
    }

    /// Keyed by `key(_:)` of the Shortcut name.
    public var entries: [String: Entry] = [:]

    public init() {}

    public static let cacheName = "tiles"

    public static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public func status(_ name: String) -> Status {
        guard let entry = entries[Self.key(name)], let confirmed = entry.confirmed else { return .notSetUp }
        if let error = entry.lastError, error >= confirmed { return .failed }
        return .ready
    }

    /// A tap runs the Shortcut only once it is set up and hasn't failed since.
    public func shouldRun(_ name: String) -> Bool {
        status(name) == .ready
    }

    public mutating func confirm(_ name: String, now: Date = .now) {
        entries[Self.key(name), default: Entry()].confirmed = now
        entries[Self.key(name)]?.name = name
    }

    public mutating func recordRun(_ name: String, now: Date = .now) {
        entries[Self.key(name), default: Entry()].lastRun = now
    }

    public mutating func recordError(_ name: String, now: Date = .now) {
        entries[Self.key(name), default: Entry()].lastError = now
        entries[Self.key(name)]?.name = name
    }

    public mutating func forget(_ name: String) {
        entries[Self.key(name)] = nil
    }

    public static func load(_ cache: DataCache = DataCache()) -> TileSetupState {
        cache.read(TileSetupState.self, cacheName) ?? TileSetupState()
    }

    public func save(_ cache: DataCache = DataCache()) throws {
        try cache.write(self, Self.cacheName)
    }
}

public enum ShortcutLinks {
    /// Runs the Shortcut; if Shortcuts can't (no Shortcut with that name, or it failed), it calls
    /// back `widgetstudio://tiles/setup?name=…&error=1`, which opens the tile's setup screen.
    public static func run(name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let error = setup(name: trimmed, error: true) else { return nil }
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: trimmed), URLQueryItem(name: "x-error", value: error.absoluteString)]
        return components.url
    }

    /// `widgetstudio://tiles/setup?name=…` (with `error=1` when Shortcuts reported a failure).
    public static func setup(name: String, error: Bool = false) -> URL? {
        var components = URLComponents()
        components.scheme = "widgetstudio"
        components.host = "tiles"
        components.path = "/setup"
        components.queryItems = [URLQueryItem(name: "name", value: name)] + (error ? [URLQueryItem(name: "error", value: "1")] : [])
        return components.url
    }

    /// Opens Shortcuts on a new, empty Shortcut.
    public static let create = URL(string: "shortcuts://create-shortcut")

    /// The Shortcut names of a spec's tiles (its `shortcut.run` buttons), resolved with the
    /// design's field values.
    public static func names(in spec: WidgetSpec, fieldValues: [String: LocalizedText] = [:], language: String) -> [String] {
        spec.allLayers.compactMap { layer -> String? in
            guard case .button(let button) = layer.content, button.action == .shortcutRun, let arg = button.arg,
                  let raw = Bindings.soleBinding(arg), case .field(let key)? = Bindings.Name(raw) else { return nil }
            let value = (fieldValues[key] ?? spec.field(key)?.default)?.resolved(language: language) ?? ""
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
