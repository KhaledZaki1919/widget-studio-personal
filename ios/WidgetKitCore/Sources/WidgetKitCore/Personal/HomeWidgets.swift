import CoreGraphics
import Foundation

// Personal build (docs/personal.md): the app's side of "one code per widget". The user types the
// code a placed widget shows (or picks a widget the app already knows); the app checks the code
// against the widget's encrypted info item (it also learns the widget's size), encrypts the
// design with the code's key and uploads it. The app remembers every widget it sent to:
// that's the "My home screen" list.

/// A widget the app has sent a design to.
public struct KnownWidget: Codable, Sendable, Equatable, Identifiable {
    public var code: String
    public var size: SpecFamily
    public var slot: String
    public var designID: String?
    public var designName: String?
    /// When the app last uploaded a design to this code.
    public var lastSent: Date?
    public var lastBytes: Int?
    public var lastError: String?

    public var id: String { code }

    public init(code: String, size: SpecFamily, slot: String) {
        self.code = code
        self.size = size
        self.slot = slot
    }

    /// The widget kind to reload after a send.
    public var widgetKind: String { SlotCatalog.kind(slot: slot) }
}

/// The relay's view of one code: the design item (upload time, size, last widget download).
public struct WidgetRelayStatus: Sendable, Equatable {
    public var uploaded: Date?
    public var lastDownload: Date?
    public var bytes: Int?
    public var exists: Bool

    /// Upload → the widget's next download: how long the design took to reach the widget.
    /// nil while the widget hasn't downloaded the current upload yet.
    public var delay: TimeInterval? {
        guard let uploaded, let lastDownload, lastDownload >= uploaded else { return nil }
        return lastDownload.timeIntervalSince(uploaded)
    }

    /// Uploaded, and the widget hasn't fetched it yet.
    public var waiting: Bool { exists && uploaded != nil && delay == nil }
}

public struct HomeWidgetSender: Sendable {
    public let client: RelayClient
    let cache: DataCache

    public init(client: RelayClient, cache: DataCache = DataCache()) {
        self.client = client
        self.cache = cache
    }

    /// nil when no relay URL is compiled in.
    public static func make() -> HomeWidgetSender? {
        RelayClient().map { HomeWidgetSender(client: $0) }
    }

    static let listName = "personal.homewidgets"

    // MARK: Known widgets

    /// Newest send first.
    public func known() -> [KnownWidget] {
        (cache.read([KnownWidget].self, Self.listName) ?? [])
            .sorted { ($0.lastSent ?? .distantPast) > ($1.lastSent ?? .distantPast) }
    }

    public func widget(code: String) -> KnownWidget? {
        known().first { $0.code == code }
    }

    private func update(_ code: String, _ change: (inout KnownWidget) -> Void) {
        var list = cache.read([KnownWidget].self, Self.listName) ?? []
        guard let index = list.firstIndex(where: { $0.code == code }) else { return }
        change(&list[index])
        try? cache.write(list, Self.listName)
    }

    private func upsert(_ widget: KnownWidget) {
        var list = (cache.read([KnownWidget].self, Self.listName) ?? []).filter { $0.code != widget.code }
        list.append(widget)
        try? cache.write(list, Self.listName)
    }

    // MARK: Relay

    /// Checks a typed code: the widget's announced size and slot.
    public func lookup(_ typed: String) async throws -> RelayPayload.WidgetInfo {
        guard let code = RelayCode.normalize(typed) else { throw RelayError.invalidCode }
        let keys = RelayKeys.derive(code: code, purpose: .info)
        guard case .item(let data, _) = try await client.download(id: keys.id, etag: nil) else { throw RelayError.unknownCode }
        guard let info = try RelayPayload.decode(keys.open(data)).widget else { throw RelayError.unknownCode }
        return info
    }

    /// Encrypts and uploads `design` to the widget showing `typed`; returns the updated widget.
    /// A design bigger than the widget is refused (designs are never shrunk); smaller ones are
    /// drawn the way My widget draws them.
    @discardableResult
    public func send(_ design: SavedDesign, photo: CGImage?, to typed: String, now: Date = .now) async throws -> KnownWidget {
        guard let code = RelayCode.normalize(typed) else { throw RelayError.invalidCode }
        let info = try await lookup(code)
        var widget = widget(code: code) ?? KnownWidget(code: code, size: info.size, slot: info.slot)
        widget.size = info.size
        widget.slot = info.slot
        guard design.spec.family.rank <= info.size.rank else {
            widget.lastError = RelayError.doesNotFit(info.size).summary
            upsert(widget)
            throw RelayError.doesNotFit(info.size)
        }
        do {
            let keys = RelayKeys.derive(code: code, purpose: .design)
            let sealed = try keys.seal(try RelayPayload.design(design, photo: photo, now: now).encoded())
            try await client.upload(sealed, id: keys.id)
            widget.designID = design.id
            widget.designName = design.name
            widget.lastSent = now
            widget.lastBytes = sealed.count
            widget.lastError = nil
            upsert(widget)
            return widget
        } catch {
            widget.lastError = (error as? RelayError)?.summary ?? error.localizedDescription
            upsert(widget)
            throw error
        }
    }

    /// Frees the code: the design is deleted from the relay (the widget shows its code again on
    /// its next timeline) and the widget leaves the list.
    public func remove(_ code: String) async throws {
        let keys = RelayKeys.derive(code: code, purpose: .design)
        try await client.delete(id: keys.id)
        let list = (cache.read([KnownWidget].self, Self.listName) ?? []).filter { $0.code != code }
        try? cache.write(list, Self.listName)
    }

    /// Forget a widget without touching the relay (e.g. the widget is gone from the home screen).
    public func forget(_ code: String) {
        let list = (cache.read([KnownWidget].self, Self.listName) ?? []).filter { $0.code != code }
        try? cache.write(list, Self.listName)
    }

    public func status(_ code: String) async throws -> WidgetRelayStatus {
        let status = try await client.status(id: RelayKeys.derive(code: code, purpose: .design).id)
        return WidgetRelayStatus(uploaded: status.uploadedDate, lastDownload: status.lastDownloadDate, bytes: status.size,
                                 exists: status.exists)
    }

    /// Unassigned widgets the app can see directly (only with a shared App Group): handy picks.
    public func localSlots() -> [(SlotID, SlotState)] {
        let knownCodes = Set(known().map(\.code))
        return SlotState.all(cache).filter { !knownCodes.contains($0.1.code) }
    }
}
