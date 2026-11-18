import Foundation

// Personal build (docs/personal.md): the widget's side of "one code per widget".
//
// A slot is one placed widget identity: a slot name ("1"…"5" for the fixed "Slot" widgets,
// "A"…"E" for the configurable one) in one size. Each slot keeps, in the extension's own
// container (`DataCache`, no App Group needed): its code, the design assigned to it (cached for
// offline use, photo in a separate file) and what happened with the relay. `SlotSync` runs in
// the widget's timeline: it announces the slot under its code (size + name, encrypted) and
// downloads the design the app sent to that code.

/// One widget identity: a slot name in one size.
public struct SlotID: Hashable, Codable, Sendable {
    public var slot: String
    public var size: SpecFamily

    public init(slot: String, size: SpecFamily) {
        self.slot = slot
        self.size = size
    }

    /// "1.small".
    public var key: String { "\(slot).\(size.rawValue)" }

    /// The fixed widgets' slot names and the configurable widget's.
    public static let fixedSlots = ["1", "2", "3", "4", "5"]
    public static let pickableSlots = ["A", "B", "C", "D", "E"]

    /// The widget kind the app reloads after a send.
    public var widgetKind: String { SlotCatalog.kind(slot: slot) }
}

public enum SlotCatalog {
    public static func kind(slot: String) -> String {
        SlotID.pickableSlots.contains(slot) ? pickableKind : "WidgetStudio.slot.\(slot)"
    }

    public static let pickableKind = "WidgetStudio.slot.pick"
}

/// Everything a slot keeps between timelines.
public struct SlotState: Codable, Sendable, Equatable {
    public var code: String
    public var created: Date
    /// When the info item (size, slot) was last uploaded under the code.
    public var announced: Date?
    public var lastCheck: Date?
    /// When a new design last arrived.
    public var lastDownload: Date?
    public var lastError: String?
    public var etag: String?
    public var design: SavedDesign?
    public var imageFile: String?
    /// When the app sent the shown design (from the payload).
    public var sent: Date?

    public init(code: String = RelayCode.generate(), created: Date = .now) {
        self.code = code
        self.created = created
    }

    static func cacheName(_ id: SlotID) -> String { "personal.slot.\(id.key)" }
    static let prefix = "personal.slot."

    /// The slot's state, or a new one with a fresh code (saved at once, so the code never changes).
    public static func load(_ id: SlotID, _ cache: DataCache = DataCache(), now: Date = .now) -> SlotState {
        if let state = cache.read(SlotState.self, cacheName(id)), RelayCode.normalize(state.code) != nil { return state }
        let state = SlotState(created: now)
        try? state.save(id, cache)
        return state
    }

    public func save(_ id: SlotID, _ cache: DataCache = DataCache()) throws {
        try cache.write(self, Self.cacheName(id))
    }

    /// Every slot this container knows (the app sees them only when it shares the App Group).
    public static func all(_ cache: DataCache = DataCache()) -> [(SlotID, SlotState)] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: cache.directory.path)) ?? []
        return files.compactMap { file -> (SlotID, SlotState)? in
            guard file.hasPrefix(prefix), file.hasSuffix(".json") else { return nil }
            let key = String(file.dropFirst(prefix.count).dropLast(5))
            let parts = key.split(separator: ".").map(String.init)
            guard parts.count == 2, let size = SpecFamily(rawValue: parts[1]) else { return nil }
            let id = SlotID(slot: parts[0], size: size)
            return cache.read(SlotState.self, cacheName(id)).map { (id, $0) }
        }
    }

    public func imageData(_ cache: DataCache = DataCache()) -> Data? {
        imageFile.flatMap { try? Data(contentsOf: Self.imagesFolder(cache).appendingPathComponent($0)) }
    }

    static func imagesFolder(_ cache: DataCache) -> URL {
        cache.directory.appendingPathComponent("Slots", isDirectory: true)
    }
}

/// The widget's relay round in its timeline.
public enum SlotSync {
    public struct Outcome: Equatable, Sendable {
        public var newDesign = false
        /// The app removed the code's design: the widget shows its code again.
        public var removed = false
        public var announced = false
        public var error: String?

        public init() {}
    }

    /// Re-announce weekly, so the info item never expires on the relay (30 days without access).
    static let announceEvery: TimeInterval = 7 * 24 * 3600

    public static func refresh(_ id: SlotID, client: RelayClient, cache: DataCache = DataCache(),
                               now: Date = .now) async -> Outcome {
        var state = SlotState.load(id, cache, now: now)
        var outcome = Outcome()
        state.lastCheck = now
        do {
            if state.announced.map({ now.timeIntervalSince($0) > announceEvery }) ?? true {
                let keys = RelayKeys.derive(code: state.code, purpose: .info)
                let info = RelayPayload(kind: .info, widget: .init(size: id.size, slot: id.slot), sent: now)
                try await client.upload(try keys.seal(try info.encoded()), id: keys.id)
                state.announced = now
                outcome.announced = true
            }
            let keys = RelayKeys.derive(code: state.code, purpose: .design)
            switch try await client.download(id: keys.id, etag: state.etag) {
            case .item(let data, let etag):
                let payload = try RelayPayload.decode(keys.open(data))
                if payload.kind == .design, let design = payload.design {
                    try store(payload, design: design, in: &state, id: id, cache: cache)
                    state.lastDownload = now
                    outcome.newDesign = true
                }
                // Only once it's stored: a failed write is retried on the next timeline.
                state.etag = etag
            case .notModified:
                break
            case .missing:
                // The app removed the design (the code is free again): back to showing the code.
                if state.design != nil {
                    removeImage(state, cache: cache)
                    state.design = nil
                    state.imageFile = nil
                    state.sent = nil
                    outcome.removed = true
                }
                state.etag = nil
            }
            state.lastError = nil
        } catch {
            outcome.error = (error as? RelayError)?.summary ?? error.localizedDescription
            state.lastError = outcome.error
        }
        try? state.save(id, cache)
        return outcome
    }

    private static func store(_ payload: RelayPayload, design: SavedDesign, in state: inout SlotState, id: SlotID,
                              cache: DataCache) throws {
        removeImage(state, cache: cache)
        state.imageFile = nil
        if let image = payload.image {
            let name = "\(id.key)-\(UUID().uuidString.prefix(8)).img"
            try FileProtection.write(image, to: SlotState.imagesFolder(cache).appendingPathComponent(name))
            state.imageFile = name
        }
        state.design = design
        state.sent = payload.sent
    }

    private static func removeImage(_ state: SlotState, cache: DataCache) {
        guard let file = state.imageFile else { return }
        try? FileManager.default.removeItem(at: SlotState.imagesFolder(cache).appendingPathComponent(file))
    }
}
