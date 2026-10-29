import CoreGraphics
import Foundation
import Testing
@testable import WidgetKitCore

// Personal build (docs/personal.md): pairing code, key derivation, encryption, payload size,
// the relay client against an in-memory relay, and the widget's sync.

/// An in-memory stand-in for the Worker (relay/src/relay.js): PUT, GET with ETag, status.
final class FakeRelayProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var items: [String: (data: Data, version: Int)] = [:]
    nonisolated(unsafe) private static var downloads: [String: Int] = [:]
    nonisolated(unsafe) private static var clock = 1000
    nonisolated(unsafe) static var failing = false

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeRelayProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func stored(_ id: String) -> Data? {
        lock.withLock { items[id]?.data }
    }

    static func reset() {
        lock.withLock {
            items = [:]
            downloads = [:]
            failing = false
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(fileURLWithPath: "/")
        let parts = url.path.split(separator: "/").map(String.init)
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let (status, data, headers): (Int, Data, [String: String]) = Self.lock.withLock {
            if Self.failing { return (500, Data(), [:]) }
            guard parts.count >= 3, parts[0] == "v1", parts[1] == "items" else { return (404, Data(), [:]) }
            let id = parts[2]
            if parts.count == 4 {
                let item = Self.items[id]
                let json = """
                {"exists":\(item != nil),"size":\(item.map { "\($0.data.count)" } ?? "null"),\
                "uploaded":\(item.map { "\($0.version)" } ?? "null"),"lastDownload":\(Self.downloads[id].map { "\($0)" } ?? "null")}
                """
                return (200, Data(json.utf8), [:])
            }
            Self.clock += 1
            switch request.httpMethod ?? "GET" {
            case "PUT":
                if body.count > RelayPayload.maxSealedBytes { return (413, Data(), [:]) }
                Self.items[id] = (body, Self.clock)
                return (201, Data(#"{"version":"\#(Self.clock)"}"#.utf8), [:])
            default:
                guard let item = Self.items[id] else { return (404, Data(), [:]) }
                let etag = "\"\(item.version)\""
                if request.value(forHTTPHeaderField: "If-None-Match") == etag { return (304, Data(), ["ETag": etag]) }
                Self.downloads[id] = Self.clock
                return (200, item.data, ["ETag": etag])
            }
        }
        if let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Whole seconds: JSON dates (ISO 8601) drop fractions.
private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

private func tempCache() throws -> DataCache {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("RelayTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return DataCache(directory: url)
}

private func client() throws -> RelayClient {
    RelayClient(baseURL: try #require(URL(string: "https://relay.example.workers.dev")), session: FakeRelayProtocol.session())
}

/// A noisy test photo (compresses badly, like a real one).
private func noisyImage(side: Int) -> CGImage? {
    var generator = SystemRandomNumberGenerator()
    var pixels = (0..<(side * side * 4)).map { _ in UInt8.random(in: 0...255, using: &generator) }
    return pixels.withUnsafeMutableBytes { buffer in
        CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
    }
}

struct RelayCodeTests {
    @Test func generatedCodesUseTheAlphabet() {
        let codes = (0..<50).map { _ in RelayCode.generate() }
        for code in codes {
            #expect(code.count == 8)
            #expect(RelayCode.normalize(code) == code)
        }
        #expect(Set(codes).count > 45)
    }

    @Test func normalizesWhatTheUserTypes() {
        #expect(RelayCode.normalize("abcd-efgh") == "ABCDEFGH")
        #expect(RelayCode.normalize(" AB CD EF GH ") == "ABCDEFGH")
        #expect(RelayCode.normalize("ABCDEFG") == nil)
        #expect(RelayCode.normalize("ABCDEFG0") == nil)
        #expect(RelayCode.normalize("ABCDEFGI") == nil)
        #expect(RelayCode.formatted("ABCDEFGH") == "ABCD-EFGH")
    }
}

struct RelayKeysTests {
    @Test func derivationIsStableAndSeparatesSlotsIDsAndKeys() throws {
        let small = RelayKeys.derive(code: "ABCDEFGH", slot: .small)
        #expect(small.id.count == 64)
        #expect(small.id.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(RelayKeys.derive(code: "ABCDEFGH", slot: .small).id == small.id)
        #expect(RelayKeys.derive(code: "ABCDEFGH", slot: .medium).id != small.id)
        #expect(RelayKeys.derive(code: "ABCDEFGJ", slot: .small).id != small.id)
        // The ID is not the key: the relay can't decrypt with what it stores under.
        let idBytes = Data(stride(from: 0, to: 64, by: 2).compactMap { offset -> UInt8? in
            let start = small.id.index(small.id.startIndex, offsetBy: offset)
            return UInt8(small.id[start...small.id.index(after: start)], radix: 16)
        })
        #expect(small.key.withUnsafeBytes { Data($0) } != idBytes)
    }

    @Test func sealOpensOnlyWithTheSameCodeAndSlot() throws {
        let plaintext = Data("hello widget".utf8)
        let sealed = try RelayKeys.derive(code: "ABCDEFGH", slot: .large).seal(plaintext)
        #expect(sealed.first == 1)
        #expect(sealed.range(of: plaintext) == nil)
        #expect(try RelayKeys.derive(code: "ABCDEFGH", slot: .large).open(sealed) == plaintext)
        #expect(throws: RelayError.crypto) { try RelayKeys.derive(code: "ABCDEFGJ", slot: .large).open(sealed) }
        #expect(throws: RelayError.crypto) { try RelayKeys.derive(code: "ABCDEFGH", slot: .small).open(sealed) }
        var tampered = sealed
        tampered[tampered.count - 1] ^= 1
        #expect(throws: RelayError.crypto) { try RelayKeys.derive(code: "ABCDEFGH", slot: .large).open(tampered) }
    }
}

struct RelayPayloadTests {
    @Test func designRoundTripsWithItsPhotoUnderTheLimit() throws {
        let template = try TemplateLibrary.load(id: "mono.photo.square").get()
        let design = SavedDesign.new(from: template, language: "en", now: fixedDate)
        let photo = try #require(noisyImage(side: 1600))
        let payload = try RelayPayload.design(design, photo: photo)
        let sealed = try RelayKeys.derive(code: "ABCDEFGH", slot: .small).seal(try payload.encoded())
        #expect(sealed.count <= RelayPayload.maxSealedBytes)
        let decoded = try RelayPayload.decode(try RelayKeys.derive(code: "ABCDEFGH", slot: .small).open(sealed))
        #expect(decoded.design == design)
        let image = try #require(decoded.cgImage)
        #expect(max(image.width, image.height) <= ImageProcessing.maxSide)
    }

    @Test func designWithoutPhoto() throws {
        let design = SavedDesign.new(from: try TemplateLibrary.load(id: "mono.clock.digital").get(), language: "ar", now: fixedDate)
        let payload = try RelayPayload.design(design, photo: nil, now: fixedDate)
        #expect(payload.image == nil)
        #expect(try RelayPayload.decode(payload.encoded()) == payload)
    }
}

@Suite(.serialized)
struct RelaySyncTests {
    init() {
        FakeRelayProtocol.reset()
    }

    private func upload(_ payload: RelayPayload, code: String, slot: RelaySlot) async throws {
        let keys = RelayKeys.derive(code: code, slot: slot)
        try await client().upload(try keys.seal(try payload.encoded()), id: keys.id)
    }

    @Test func clientTalksToTheRelay() async throws {
        let relay = try client()
        let id = String(repeating: "b", count: 64)
        #expect(try await relay.download(id: id, etag: nil) == .missing)
        try await relay.upload(Data([1, 2, 3]), id: id)
        guard case .item(let data, let etag) = try await relay.download(id: id, etag: nil) else {
            Issue.record("expected an item")
            return
        }
        #expect(data == Data([1, 2, 3]))
        #expect(try await relay.download(id: id, etag: etag) == .notModified)
        let status = try await relay.status(id: id)
        #expect(status.exists && status.size == 3 && status.lastDownloadDate != nil)
        await #expect(throws: RelayError.tooLarge) {
            try await relay.upload(Data(count: RelayPayload.maxSealedBytes + 1), id: id)
        }
    }

    @Test func unpairedWidgetKeepsItsCodeUntilThePairItemArrives() async throws {
        let cache = try tempCache()
        let code = WidgetPairing.loadOrCreate(cache).code
        #expect(WidgetPairing.loadOrCreate(cache).code == code)

        var outcome = await RelaySync.refresh(size: .small, client: try client(), cache: cache)
        #expect(outcome == RelaySync.Outcome())
        #expect(WidgetPairing.loadOrCreate(cache).isPaired == false)

        try await upload(RelayPayload(kind: .pair), code: code, slot: .pair)
        outcome = await RelaySync.refresh(size: .small, client: try client(), cache: cache)
        #expect(outcome.error == nil)
        #expect(WidgetPairing.loadOrCreate(cache).isPaired)
    }

    @Test func newDesignIsCachedAndShown() async throws {
        let cache = try tempCache()
        let code = WidgetPairing.loadOrCreate(cache).code
        let design = SavedDesign.new(from: try TemplateLibrary.load(id: "mono.photo.square").get(), language: "en", now: fixedDate)
        try await upload(try RelayPayload.design(design, photo: noisyImage(side: 300)), code: code, slot: .medium)

        let outcome = await RelaySync.refresh(size: .medium, client: try client(), cache: cache)
        #expect(outcome.newDesign)
        let store = RelayedStore(size: .medium, cache: cache)
        let item = try #require(store.items.first)
        #expect(item.design == design)
        #expect(store.image(for: item) != nil)
        #expect(SwitcherState.load(.medium, cache).current == item.key)
        #expect(WidgetPairing.loadOrCreate(cache).lastDownload != nil)

        // Unchanged: a 304, nothing new. Other sizes don't see it.
        #expect(await RelaySync.refresh(size: .medium, client: try client(), cache: cache).newDesign == false)
        #expect(RelayedStore(size: .small, cache: cache).items.isEmpty)
    }

    @Test func failuresKeepTheCacheAndReportTheError() async throws {
        let cache = try tempCache()
        FakeRelayProtocol.failing = true
        let outcome = await RelaySync.refresh(size: .large, client: try client(), cache: cache)
        #expect(outcome.error == "HTTP 500")
        #expect(WidgetPairing.loadOrCreate(cache).lastError == "HTTP 500")
        FakeRelayProtocol.failing = false
    }

    @Test func itemsFromAnotherCodeAreRejected() async throws {
        let cache = try tempCache()
        let code = WidgetPairing.loadOrCreate(cache).code
        let keys = RelayKeys.derive(code: code, slot: .small)
        // Garbage under the right ID (someone who only knows the ID can't plant a design).
        try await client().upload(Data([1]) + Data(repeating: 7, count: 40), id: keys.id)
        let outcome = await RelaySync.refresh(size: .small, client: try client(), cache: cache)
        #expect(outcome.error != nil)
        #expect(RelayedStore(size: .small, cache: cache).items.isEmpty)
    }
}

struct SwitcherTests {
    private let templates = ["mono.clock.analog", "mono.clock.digital", "mono.date.big"]

    @Test func cyclesThroughPairingDesignsAndTemplates() {
        let keys = SwitcherCatalog.keys(showsPairing: true, relayed: [], templateIDs: templates)
        #expect(keys == ["pair", "t:mono.clock.analog", "t:mono.clock.digital", "t:mono.date.big"])
        #expect(SwitcherCatalog.resolve(nil, keys: keys, size: .small) == "pair")
        #expect(SwitcherCatalog.step(nil, by: 1, keys: keys, size: .small) == "t:mono.clock.analog")
        #expect(SwitcherCatalog.step("pair", by: -1, keys: keys, size: .small) == "t:mono.date.big")
        #expect(SwitcherCatalog.step("t:mono.date.big", by: 1, keys: keys, size: .small) == "pair")
        #expect(SwitcherCatalog.position(of: "t:mono.clock.digital", in: keys) == "3/4")
    }

    @Test func pairedWidgetDefaultsToTheSizesTemplate() {
        let keys = SwitcherCatalog.keys(showsPairing: false, relayed: [], templateIDs: templates)
        #expect(SwitcherCatalog.resolve(nil, keys: keys, size: .small) == "t:mono.clock.digital")
        // A key that's gone (an old pairing card, a dropped design) falls back the same way.
        #expect(SwitcherCatalog.resolve("pair", keys: keys, size: .small) == "t:mono.clock.digital")
        #expect(SwitcherCatalog.templateID("t:mono.date.big") == "mono.date.big")
        #expect(SwitcherCatalog.templateID("d:x") == nil)
    }

    @Test func templatesFittingEachSize() {
        let small = SwitcherCatalog.templateIDs(fitting: .small)
        let large = SwitcherCatalog.templateIDs(fitting: .large)
        #expect(!small.isEmpty)
        #expect(large.count > small.count)
        #expect(Set(small).isSubset(of: Set(large)))
        #expect(small.contains(TemplateLibrary.defaultID(for: .small)))
    }

    @Test func relayedStoreKeepsTheNewestFive() throws {
        let cache = try tempCache()
        var store = RelayedStore(size: .small, cache: cache)
        let template = try TemplateLibrary.load(id: "mono.clock.digital").get()
        var designs: [SavedDesign] = []
        for index in 0..<7 {
            let design = SavedDesign(id: "d\(index)", name: "D\(index)", template: template)
            designs.append(design)
            try store.insert(design, image: Data([UInt8(index)]), etag: "\"\(index)\"", now: Date(timeIntervalSince1970: Double(index)))
        }
        try store.insert(designs[3], image: nil, etag: "\"9\"", now: .now)
        let reopened = RelayedStore(size: .small, cache: cache)
        #expect(reopened.items.map(\.design.id) == ["d3", "d6", "d5", "d4", "d2"])
        #expect(reopened.etag == "\"9\"")
        #expect(reopened.image(for: reopened.items[1]) == Data([6]))
        let files = try FileManager.default.contentsOfDirectory(atPath: cache.directory.appendingPathComponent("Relayed").path)
        #expect(files.filter { $0.hasSuffix(".img") }.count == 4)

        let keys = SwitcherCatalog.keys(showsPairing: false, relayed: reopened.items, templateIDs: templates)
        #expect(SwitcherCatalog.resolve(nil, keys: keys, size: .small) == "d:d3")
    }

    @Test func stateRoundTrips() throws {
        let cache = try tempCache()
        #expect(SwitcherState.load(.large, cache) == SwitcherState())
        try SwitcherState(current: "t:mono.prayer.day", locked: true).save(.large, cache)
        #expect(SwitcherState.load(.large, cache) == SwitcherState(current: "t:mono.prayer.day", locked: true))
        #expect(SwitcherState.load(.small, cache) == SwitcherState())
    }
}
