import Foundation

// Personal build (docs/personal.md): state of the "Widget Studio" switcher widgets. Like the
// tasbeeh counter it lives in the extension's own container (`DataCache`), so it needs no App
// Group: the ◀ ▶ 🔒 buttons are AppIntents that run in the extension and write it there.

/// The widget's pairing code and what happened with the relay (shown on the pairing card and
/// in the widget log).
public struct WidgetPairing: Codable, Sendable, Equatable {
    public var code: String
    /// When the widget first saw an item made with its code.
    public var paired: Date?
    public var lastCheck: Date?
    public var lastDownload: Date?
    public var lastError: String?

    public init(code: String = RelayCode.generate()) {
        self.code = code
    }

    public var isPaired: Bool { paired != nil }

    public static let cacheName = "personal.pairing"

    /// The stored pairing, or a new code (saved right away so it never changes).
    public static func loadOrCreate(_ cache: DataCache = DataCache()) -> WidgetPairing {
        if let pairing = cache.read(WidgetPairing.self, cacheName), RelayCode.normalize(pairing.code) != nil { return pairing }
        let pairing = WidgetPairing()
        try? pairing.save(cache)
        return pairing
    }

    /// The stored pairing without creating one (the app, when it shares the container).
    public static func existing(_ cache: DataCache = DataCache()) -> WidgetPairing? {
        cache.read(WidgetPairing.self, cacheName)
    }

    public func save(_ cache: DataCache = DataCache()) throws {
        try cache.write(self, Self.cacheName)
    }
}

/// Which design a switcher widget of one size shows, and whether its arrows are hidden.
public struct SwitcherState: Codable, Sendable, Equatable {
    /// A `SwitcherCatalog` key; nil = the default.
    public var current: String?
    public var locked = false
    /// Set by a button tap: the timeline that follows redraws without waiting for the network.
    public var quietUntil: Date?

    public init(current: String? = nil, locked: Bool = false) {
        self.current = current
        self.locked = locked
    }

    public static func cacheName(_ size: SpecFamily) -> String { "personal.switcher.\(size.rawValue)" }

    public static func load(_ size: SpecFamily, _ cache: DataCache = DataCache()) -> SwitcherState {
        cache.read(SwitcherState.self, cacheName(size)) ?? SwitcherState()
    }

    public func save(_ size: SpecFamily, _ cache: DataCache = DataCache()) throws {
        try cache.write(self, Self.cacheName(size))
    }
}

/// A design that came through the relay, cached for offline use. The photo is a separate file
/// so a timeline only reads the one it draws (the widget has ~30 MB).
public struct RelayedDesign: Codable, Sendable, Equatable {
    public var design: SavedDesign
    public var imageFile: String?
    public var received: Date

    public var key: String { SwitcherCatalog.designKey(design.id) }
}

/// The designs relayed to one widget size, newest first (at most `limit`), and the relay ETag.
public struct RelayedStore: Sendable {
    public struct Index: Codable, Sendable, Equatable {
        public var items: [RelayedDesign] = []
        public var etag: String?
    }

    public static let limit = 5

    let size: SpecFamily
    let folder: URL
    public private(set) var index: Index

    public init(size: SpecFamily, cache: DataCache = DataCache()) {
        self.size = size
        folder = cache.directory.appendingPathComponent("Relayed", isDirectory: true)
        index = (try? Data(contentsOf: folder.appendingPathComponent("\(size.rawValue).json")))
            .flatMap { try? Self.decoder.decode(Index.self, from: $0) } ?? Index()
    }

    public var items: [RelayedDesign] { index.items }
    public var etag: String? { index.etag }

    public func item(key: String) -> RelayedDesign? {
        items.first { $0.key == key }
    }

    public func image(for item: RelayedDesign) -> Data? {
        item.imageFile.flatMap { try? Data(contentsOf: folder.appendingPathComponent($0)) }
    }

    /// Adds (or replaces, by design id) a design at the front; drops the oldest beyond `limit`.
    @discardableResult
    public mutating func insert(_ design: SavedDesign, image: Data?, etag: String?, now: Date) throws -> RelayedDesign {
        var imageFile: String?
        if let image {
            let name = "\(size.rawValue)-\(UUID().uuidString.prefix(8)).img"
            try FileProtection.write(image, to: folder.appendingPathComponent(name))
            imageFile = name
        }
        let item = RelayedDesign(design: design, imageFile: imageFile, received: now)
        var items = index.items.filter { $0.design.id != design.id }
        items.insert(item, at: 0)
        let kept = Array(items.prefix(Self.limit))
        index = Index(items: kept, etag: etag)
        try write()
        removeUnusedImages()
        return item
    }

    public mutating func setETag(_ etag: String?) throws {
        index.etag = etag
        try write()
    }

    private func write() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileProtection.write(try encoder.encode(index), to: folder.appendingPathComponent("\(size.rawValue).json"))
    }

    private func removeUnusedImages() {
        let used = Set(items.compactMap(\.imageFile))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where file.hasPrefix("\(size.rawValue)-") && file.hasSuffix(".img") && !used.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// What the ◀ ▶ buttons cycle through, as keys: the pairing card (until paired), relayed
/// designs (newest first), then every template that fits the size.
public enum SwitcherCatalog {
    public static let pairingKey = "pair"

    public static func designKey(_ id: String) -> String { "d:\(id)" }
    public static func templateKey(_ id: String) -> String { "t:\(id)" }

    /// The template id in a template key.
    public static func templateID(_ key: String) -> String? {
        key.hasPrefix("t:") ? String(key.dropFirst(2)) : nil
    }

    public static func keys(showsPairing: Bool, relayed: [RelayedDesign], templateIDs: [String]) -> [String] {
        (showsPairing ? [pairingKey] : []) + relayed.map(\.key) + templateIDs.map(templateKey)
    }

    /// The key to draw: `current` while it's still in the list, else the pairing card, the newest
    /// relayed design, the size's default template, or the first key.
    public static func resolve(_ current: String?, keys: [String], size: SpecFamily) -> String? {
        if let current, keys.contains(current) { return current }
        if keys.contains(pairingKey) { return pairingKey }
        if let design = keys.first(where: { $0.hasPrefix("d:") }) { return design }
        let fallback = templateKey(TemplateLibrary.defaultID(for: size))
        return keys.contains(fallback) ? fallback : keys.first
    }

    /// One step forward (1) or back (-1), wrapping around.
    public static func step(_ current: String?, by offset: Int, keys: [String], size: SpecFamily) -> String? {
        guard !keys.isEmpty, let shown = resolve(current, keys: keys, size: size), let index = keys.firstIndex(of: shown) else {
            return keys.first
        }
        let count = keys.count
        return keys[((index + offset) % count + count) % count]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var fitting: [SpecFamily: [String]] = [:]

    /// Ids of the templates that fit `size`, in library order (decoded once per process).
    public static func templateIDs(fitting size: SpecFamily) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        if let known = fitting[size] { return known }
        let ids = TemplateLibrary.fitting(size).map(\.id)
        fitting[size] = ids
        return ids
    }

    /// "3/31".
    public static func position(of key: String?, in keys: [String]) -> String {
        guard let key, let index = keys.firstIndex(of: key) else { return "" }
        return "\(index + 1)/\(keys.count)"
    }
}

/// The widget's side of the relay: checks the pairing item until it shows up, and downloads a
/// new design for its size (ETag, so unchanged items cost one tiny request). A new design
/// becomes the one the widget shows.
public enum RelaySync {
    public struct Outcome: Equatable, Sendable {
        public var newDesign = false
        public var error: String?
    }

    public static func refresh(size: SpecFamily, client: RelayClient, cache: DataCache = DataCache(),
                               now: Date = .now) async -> Outcome {
        var pairing = WidgetPairing.loadOrCreate(cache)
        var outcome = Outcome()
        pairing.lastCheck = now
        do {
            if !pairing.isPaired {
                let keys = RelayKeys.derive(code: pairing.code, slot: .pair)
                if case .item(let data, _) = try await client.download(id: keys.id, etag: nil),
                   try RelayPayload.decode(keys.open(data)).kind == .pair {
                    pairing.paired = now
                }
            }
            let keys = RelayKeys.derive(code: pairing.code, slot: RelaySlot(size))
            var store = RelayedStore(size: size, cache: cache)
            if case .item(let data, let etag) = try await client.download(id: keys.id, etag: store.etag) {
                let payload = try RelayPayload.decode(keys.open(data))
                if payload.kind == .design, let design = payload.design {
                    let item = try store.insert(design, image: payload.image, etag: etag, now: now)
                    var state = SwitcherState.load(size, cache)
                    state.current = item.key
                    try state.save(size, cache)
                    pairing.paired = pairing.paired ?? now
                    pairing.lastDownload = now
                    outcome.newDesign = true
                } else {
                    try store.setETag(etag)
                }
            }
            pairing.lastError = nil
        } catch {
            outcome.error = (error as? RelayError)?.summary ?? error.localizedDescription
            pairing.lastError = outcome.error
        }
        try? pairing.save(cache)
        return outcome
    }
}
