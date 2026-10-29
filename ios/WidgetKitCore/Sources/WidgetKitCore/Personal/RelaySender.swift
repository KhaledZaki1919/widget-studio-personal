import CoreGraphics
import Foundation

/// Personal build: the app's side of the relay. It keeps the typed pairing code in the Keychain,
/// encrypts a design (and its downscaled photo) with the slot's key and uploads it. The upload
/// record and the pairing time are kept for the pairing screen's diagnostics.
public struct RelaySender: Sendable {
    public struct Record: Codable, Sendable, Equatable {
        public var paired: Date?
        public var lastUpload: Date?
        public var lastSlot: RelaySlot?
        public var lastDesign: String?
        public var lastBytes: Int?
        public var lastError: String?

        public init() {}
    }

    let client: RelayClient
    let keychain: KeychainStore
    let cache: DataCache

    public init(client: RelayClient, keychain: KeychainStore = RelaySender.keychain, cache: DataCache = DataCache()) {
        self.client = client
        self.keychain = keychain
        self.cache = cache
    }

    public static let keychain = KeychainStore(service: "WidgetStudioP.relay")
    static let codeAccount = "pairing-code"
    public static let recordName = "personal.relay.app"

    // MARK: Pairing code

    public static func storedCode(_ keychain: KeychainStore = RelaySender.keychain) -> String? {
        (try? keychain.read(account: codeAccount)).flatMap { $0 }.flatMap { String(data: $0, encoding: .utf8) }
    }

    public var code: String? { Self.storedCode(keychain) }

    public func record() -> Record {
        cache.read(Record.self, Self.recordName) ?? Record()
    }

    private func update(_ change: (inout Record) -> Void) {
        var record = record()
        change(&record)
        try? cache.write(record, Self.recordName)
    }

    /// Stores the code and uploads the pairing item, which tells the widget it's paired.
    public func pair(_ typed: String, now: Date = .now) async throws {
        guard let code = RelayCode.normalize(typed) else { throw RelayError.crypto }
        let keys = RelayKeys.derive(code: code, slot: .pair)
        do {
            try await client.upload(try keys.seal(RelayPayload(kind: .pair, sent: now).encoded()), id: keys.id)
        } catch {
            update { $0.lastError = (error as? RelayError)?.summary ?? error.localizedDescription }
            throw error
        }
        try keychain.save(Data(code.utf8), account: Self.codeAccount)
        update {
            $0 = Record()
            $0.paired = now
        }
    }

    public func unpair() {
        try? keychain.delete(account: Self.codeAccount)
        cache.remove(Self.recordName)
    }

    // MARK: Upload

    /// Encrypts and uploads `design` to the widget of `size`; returns the uploaded byte count.
    @discardableResult
    public func send(_ design: SavedDesign, photo: CGImage?, to size: SpecFamily, now: Date = .now) async throws -> Int {
        guard let code else { throw RelayError.crypto }
        do {
            let keys = RelayKeys.derive(code: code, slot: RelaySlot(size))
            let sealed = try keys.seal(try RelayPayload.design(design, photo: photo, now: now).encoded())
            try await client.upload(sealed, id: keys.id)
            update {
                $0.lastUpload = now
                $0.lastSlot = RelaySlot(size)
                $0.lastDesign = design.name
                $0.lastBytes = sealed.count
                $0.lastError = nil
            }
            return sealed.count
        } catch {
            update { $0.lastError = (error as? RelayError)?.summary ?? error.localizedDescription }
            throw error
        }
    }

    /// The relay's view of a slot: uploaded, size, last widget download.
    public func status(_ slot: RelaySlot) async throws -> RelayClient.Status {
        guard let code else { throw RelayError.crypto }
        return try await client.status(id: RelayKeys.derive(code: code, slot: slot).id)
    }
}
