import Foundation

/// Personal build: the HTTP client for the Cloudflare Worker relay (`relay/`). The base URL is
/// compiled in as `WSRelayURL` (ios/personal.yml), so the widget knows it without the app.
///
/// - `PUT /v1/items/<id>` body = sealed bytes → `{"version": "…", "size": n}`
/// - `GET /v1/items/<id>` with `If-None-Match` → 200 (body, `ETag`), 304 or 404
/// - `GET /v1/items/<id>/status` → `{"exists", "size", "uploaded", "lastDownload"}` (ms since 1970)
public struct RelayClient: Sendable {
    public let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    public static let infoPlistKey = "WSRelayURL"

    public init(baseURL: URL, session: URLSession = RelayClient.session, timeout: TimeInterval = 20) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    /// nil when no relay URL is compiled in.
    public init?(bundle: Bundle = .main, timeout: TimeInterval = 20) {
        guard let text = bundle.object(forInfoDictionaryKey: Self.infoPlistKey) as? String,
              let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.scheme == "https" else { return nil }
        self.init(baseURL: url, timeout: timeout)
    }

    /// No URL cache: ETags are handled here.
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    public enum Download: Equatable, Sendable {
        case item(Data, etag: String?)
        case notModified
        case missing
    }

    public struct Status: Codable, Equatable, Sendable {
        public var exists: Bool
        public var size: Int?
        public var uploaded: Double?
        public var lastDownload: Double?

        public var uploadedDate: Date? { uploaded.map { Date(timeIntervalSince1970: $0 / 1000) } }
        public var lastDownloadDate: Date? { lastDownload.map { Date(timeIntervalSince1970: $0 / 1000) } }
    }

    public func upload(_ sealed: Data, id: String) async throws {
        guard sealed.count <= RelayPayload.maxSealedBytes else { throw RelayError.tooLarge }
        var request = request(id)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await send(request, body: sealed)
        try check(response, allowed: [200, 201])
    }

    public func download(id: String, etag: String?) async throws -> Download {
        var request = request(id)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await send(request, body: nil)
        switch response.statusCode {
        case 304: return .notModified
        case 404: return .missing
        default:
            try check(response, allowed: [200])
            return .item(data, etag: response.value(forHTTPHeaderField: "ETag"))
        }
    }

    public func status(id: String) async throws -> Status {
        let (data, response) = try await send(request(id, suffix: "/status"), body: nil)
        try check(response, allowed: [200])
        return try JSONDecoder().decode(Status.self, from: data)
    }

    public func delete(id: String) async throws {
        var request = request(id)
        request.httpMethod = "DELETE"
        let (_, response) = try await send(request, body: nil)
        try check(response, allowed: [200, 204, 404])
    }

    func request(_ id: String, suffix: String = "") -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/items/\(id)\(suffix)"), timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        do {
            let data: Data
            let response: URLResponse
            if let body {
                (data, response) = try await session.upload(for: request, from: body)
            } else {
                (data, response) = try await session.data(for: request)
            }
            guard let http = response as? HTTPURLResponse else { throw RelayError.network("no HTTP response") }
            return (data, http)
        } catch let error as RelayError {
            throw error
        } catch {
            throw RelayError.network(error.localizedDescription)
        }
    }

    private func check(_ response: HTTPURLResponse, allowed: Set<Int>) throws {
        if allowed.contains(response.statusCode) { return }
        if response.statusCode == 429 { throw RelayError.rateLimited }
        if response.statusCode == 413 { throw RelayError.tooLarge }
        throw RelayError.http(response.statusCode)
    }
}

/// Short readable text for an error (Diagnostics, the pairing screen).
public extension RelayError {
    var summary: String {
        switch self {
        case .notConfigured: "relay URL not set"
        case .crypto: "can't decrypt (wrong code?)"
        case .tooLarge: "too large"
        case .rateLimited: "rate limited, try again in a minute"
        case .http(let code): "HTTP \(code)"
        case .network(let text): text
        }
    }
}
