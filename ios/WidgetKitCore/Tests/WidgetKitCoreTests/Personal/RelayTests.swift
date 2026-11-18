import CoreGraphics
import Foundation
import Testing
@testable import WidgetKitCore

// Personal build (docs/personal.md): widget codes, key derivation, encryption, payload size, the
// relay client against an in-memory relay, the widget slot's sync and the app's sender.

/// An in-memory stand-in for the Worker (relay/src/relay.js): PUT, GET with ETag, DELETE, status.
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

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(fileURLWithPath: "/")
        let parts = url.path.split(separator: "/").map(String.init)
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let reply: Reply = Self.lock.withLock {
            if Self.failing { return .empty(500) }
            guard parts.count >= 3, parts[0] == "v1", parts[1] == "items" else { return .empty(404) }
            let id = parts[2]
            if parts.count == 4 {
                let item = Self.items[id]
                let json = """
                {"exists":\(item != nil),"size":\(item.map { "\($0.data.count)" } ?? "null"),\
                "uploaded":\(item.map { "\($0.version)" } ?? "null"),"lastDownload":\(Self.downloads[id].map { "\($0)" } ?? "null")}
                """
                return Reply(status: 200, data: Data(json.utf8), headers: [:])
            }
            Self.clock += 1
            switch request.httpMethod ?? "GET" {
            case "DELETE":
                Self.items[id] = nil
                Self.downloads[id] = nil
                return Reply(status: 200, data: Data(#"{"deleted":true}"#.utf8), headers: [:])
            case "PUT":
                if body.count > RelayPayload.maxSealedBytes { return .empty(413) }
                Self.items[id] = (body, Self.clock)
                return Reply(status: 201, data: Data(#"{"version":"\#(Self.clock)"}"#.utf8), headers: [:])
            default:
                guard let item = Self.items[id] else { return .empty(404) }
                let etag = "\"\(item.version)\""
                if request.value(forHTTPHeaderField: "If-None-Match") == etag {
                    return Reply(status: 304, data: Data(), headers: ["ETag": etag])
                }
                Self.downloads[id] = Self.clock
                return Reply(status: 200, data: item.data, headers: ["ETag": etag])
            }
        }
        if let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private struct Reply {
        let status: Int
        let data: Data
        let headers: [String: String]

        static func empty(_ status: Int) -> Reply {
            Reply(status: status, data: Data(), headers: [:])
        }
    }

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
        for _ in 0..<50 {
            let code = RelayCode.generate()
            #expect(code.count == 6)
            #expect(RelayCode.normalize(code) == code)
        }
    }

    @Test func normalizesWhatTheUserTypes() {
        #expect(RelayCode.normalize("abc def") == "ABCDEF")
        #expect(RelayCode.normalize(" a-b-c-d-e-f ") == "ABCDEF")
        #expect(RelayCode.normalize("ABCDE0") == nil) // 0 is not in the alphabet
        #expect(RelayCode.normalize("ABCDE") == nil)
        #expect(RelayCode.formatted("ABCDEF") == "ABC-DEF")
    }
}

struct RelayKeysTests {
    @Test func derivationIsStableAndSeparatesPurposesIDsAndKeys() throws {
        let info = RelayKeys.derive(code: "ABCDEF", purpose: .info)
        let design = RelayKeys.derive(code: "ABCDEF", purpose: .design)
        #expect(info.id == RelayKeys.derive(code: "ABCDEF", purpose: .info).id)
        #expect(info.id.count == 64)
        #expect(info.id != design.id)
        #expect(design.id != RelayKeys.derive(code: "ABCDEG", purpose: .design).id)
    }

    @Test func sealOpensOnlyWithTheSameCodeAndPurpose() throws {
        let sealed = try RelayKeys.derive(code: "ABCDEF", purpose: .design).seal(Data("hello".utf8))
        #expect(try RelayKeys.derive(code: "ABCDEF", purpose: .design).open(sealed) == Data("hello".utf8))
        #expect(throws: RelayError.crypto) { try RelayKeys.derive(code: "ABCDEG", purpose: .design).open(sealed) }
        #expect(throws: RelayError.crypto) { try RelayKeys.derive(code: "ABCDEF", purpose: .info).open(sealed) }
    }
}

struct RelayPayloadTests {
    @Test func designRoundTripsWithItsPhotoUnderTheLimit() throws {
        let template = try TemplateLibrary.load(id: "mono.photo.square").get()
        let design = SavedDesign.new(from: template, language: "en", now: fixedDate)
        let photo = try #require(noisyImage(side: 1600))
        let payload = try RelayPayload.design(design, photo: photo)
        let keys = RelayKeys.derive(code: "ABCDEF", purpose: .design)
        let sealed = try keys.seal(try payload.encoded())
        #expect(sealed.count <= RelayPayload.maxSealedBytes)
        let decoded = try RelayPayload.decode(try keys.open(sealed))
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

/// Everything that talks to the in-memory relay, one test at a time (shared state).
@Suite(.serialized)
struct SlotRelayTests {
    init() {
        FakeRelayProtocol.reset()
    }

    private func sender(_ cache: DataCache) throws -> HomeWidgetSender {
        HomeWidgetSender(client: try client(), cache: cache)
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
        try await relay.delete(id: id)
        #expect(try await relay.download(id: id, etag: nil) == .missing)
        await #expect(throws: RelayError.tooLarge) {
            try await relay.upload(Data(count: RelayPayload.maxSealedBytes + 1), id: id)
        }
    }

    @Test func slotKeepsItsCodeAndAnnouncesItself() async throws {
        let cache = try tempCache()
        let small = SlotID(slot: "2", size: .small)
        let code = SlotState.load(small, cache).code
        #expect(SlotState.load(small, cache).code == code)
        // Another size of the same slot is another widget with another code.
        #expect(SlotState.load(SlotID(slot: "2", size: .large), cache).code != code)

        let outcome = await SlotSync.refresh(small, client: try client(), cache: cache, now: fixedDate)
        #expect(outcome.announced && outcome.error == nil && !outcome.newDesign)
        #expect(SlotState.load(small, cache).design == nil)

        // The app checks the typed code and learns the size.
        let info = try await sender(try tempCache()).lookup(RelayCode.formatted(code).lowercased())
        #expect(info == RelayPayload.WidgetInfo(size: .small, slot: "2"))
        // Announced once a week, not every timeline.
        let again = await SlotSync.refresh(small, client: try client(), cache: cache, now: fixedDate.addingTimeInterval(60))
        #expect(again.announced == false)
    }

    @Test func sentDesignIsCachedShownAndReplaced() async throws {
        let widgetCache = try tempCache()
        let appCache = try tempCache()
        let id = SlotID(slot: "1", size: .medium)
        _ = await SlotSync.refresh(id, client: try client(), cache: widgetCache, now: fixedDate)
        let code = SlotState.load(id, widgetCache).code

        let first = SavedDesign.new(from: try TemplateLibrary.load(id: "mono.photo.square").get(), language: "en", now: fixedDate)
        let known = try await sender(appCache).send(first, photo: noisyImage(side: 300), to: code, now: fixedDate)
        #expect(known.size == .medium && known.slot == "1" && known.designName == first.name)
        #expect(known.widgetKind == "WidgetStudio.slot.1")
        #expect(try sender(appCache).known() == [known])

        var outcome = await SlotSync.refresh(id, client: try client(), cache: widgetCache)
        #expect(outcome.newDesign)
        var state = SlotState.load(id, widgetCache)
        #expect(state.design == first)
        #expect(state.imageData(widgetCache) != nil)
        #expect(state.lastDownload != nil)

        // Unchanged: a 304, nothing new.
        #expect(await SlotSync.refresh(id, client: try client(), cache: widgetCache).newDesign == false)

        // Reassign: another design to the same code replaces it.
        let second = SavedDesign.new(from: try TemplateLibrary.load(id: "mono.clock.digital").get(), language: "en", now: fixedDate)
        try await sender(appCache).send(second, photo: nil, to: code)
        outcome = await SlotSync.refresh(id, client: try client(), cache: widgetCache)
        #expect(outcome.newDesign)
        state = SlotState.load(id, widgetCache)
        #expect(state.design == second && state.imageFile == nil)

        // The relay's view: uploaded, downloaded after it, so a delay.
        let status = try await sender(appCache).status(code)
        #expect(status.exists && status.delay != nil && !status.waiting)
    }

    @Test func removeFreesTheCode() async throws {
        let widgetCache = try tempCache()
        let appCache = try tempCache()
        let id = SlotID(slot: "3", size: .large)
        _ = await SlotSync.refresh(id, client: try client(), cache: widgetCache)
        let code = SlotState.load(id, widgetCache).code
        let design = SavedDesign.new(from: try TemplateLibrary.load(id: "mono.clock.digital").get(), language: "en", now: fixedDate)
        try await sender(appCache).send(design, photo: nil, to: code)
        _ = await SlotSync.refresh(id, client: try client(), cache: widgetCache)
        #expect(SlotState.load(id, widgetCache).design != nil)

        try await sender(appCache).remove(code)
        #expect(try sender(appCache).known().isEmpty)
        let outcome = await SlotSync.refresh(id, client: try client(), cache: widgetCache)
        #expect(outcome.removed)
        let state = SlotState.load(id, widgetCache)
        #expect(state.design == nil && state.code == code)
    }

    @Test func wrongCodesAndSizesAreRefused() async throws {
        let appCache = try tempCache()
        let design = SavedDesign.new(from: try TemplateLibrary.load(id: "mono.weather.forecast").get(), language: "en", now: fixedDate)
        await #expect(throws: RelayError.invalidCode) { try await sender(appCache).send(design, photo: nil, to: "AB") }
        await #expect(throws: RelayError.unknownCode) { try await sender(appCache).send(design, photo: nil, to: "ABCDEF") }

        // A medium design never goes to a small widget (it would be shrunk).
        let widgetCache = try tempCache()
        let small = SlotID(slot: "4", size: .small)
        _ = await SlotSync.refresh(small, client: try client(), cache: widgetCache)
        let code = SlotState.load(small, widgetCache).code
        await #expect(throws: RelayError.doesNotFit(.small)) { try await sender(appCache).send(design, photo: nil, to: code) }
        #expect(try sender(appCache).known().first?.lastError != nil)
    }

    @Test func failuresKeepTheCacheAndReportTheError() async throws {
        let widgetCache = try tempCache()
        let id = SlotID(slot: "5", size: .small)
        _ = await SlotSync.refresh(id, client: try client(), cache: widgetCache)
        let code = SlotState.load(id, widgetCache).code
        let design = SavedDesign.new(from: try TemplateLibrary.load(id: "mono.clock.digital").get(), language: "en", now: fixedDate)
        try await sender(try tempCache()).send(design, photo: nil, to: code)
        _ = await SlotSync.refresh(id, client: try client(), cache: widgetCache)

        FakeRelayProtocol.failing = true
        let outcome = await SlotSync.refresh(id, client: try client(), cache: widgetCache)
        #expect(outcome.error == "HTTP 500")
        // Offline or failing: the cached design stays.
        #expect(SlotState.load(id, widgetCache).design == design)
        #expect(SlotState.load(id, widgetCache).lastError == "HTTP 500")
    }

    @Test func slotsInTheContainerAreListed() throws {
        let cache = try tempCache()
        _ = SlotState.load(SlotID(slot: "1", size: .small), cache)
        _ = SlotState.load(SlotID(slot: "A", size: .xlarge), cache)
        let all = SlotState.all(cache).map(\.0)
        #expect(Set(all) == [SlotID(slot: "1", size: .small), SlotID(slot: "A", size: .xlarge)])
        #expect(SlotID(slot: "A", size: .small).widgetKind == SlotCatalog.pickableKind)
    }
}
