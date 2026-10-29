import CoreGraphics
import Foundation
import ImageIO

/// Personal build: what one relay item holds once decrypted. `pair` items only confirm the
/// pairing; size items carry a saved design and its photo (JPEG, or PNG for halftone/mono).
public struct RelayPayload: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case pair, design
    }

    public var kind: Kind
    public var design: SavedDesign?
    public var image: Data?
    public var sent: Date

    public init(kind: Kind, design: SavedDesign? = nil, image: Data? = nil, sent: Date = .now) {
        self.kind = kind
        self.design = design
        self.image = image
        self.sent = sent
    }

    /// The relay rejects items over 1 MiB; leave room for the envelope and JSON.
    public static let maxSealedBytes = 1_048_576
    static let budget = 980_000

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> RelayPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RelayPayload.self, from: data)
    }

    /// A design item whose JSON (photo as base64) fits the budget: the photo is shrunk (JPEG
    /// quality, then size) until it does.
    public static func design(_ design: SavedDesign, photo: CGImage?, now: Date = .now) throws -> RelayPayload {
        var payload = RelayPayload(kind: .design, design: design, sent: now)
        guard let photo else {
            guard try payload.encoded().count <= budget else { throw RelayError.tooLarge }
            return payload
        }
        let lossless = [ImageLayer.Filter.halftone, .mono].contains(design.imageLayer?.layer.filter ?? ImageLayer.Filter.none)
        var image = ImageProcessing.fit(photo, in: CGSize(width: ImageProcessing.maxSide, height: ImageProcessing.maxSide)) ?? photo
        var attempts: [(lossless: Bool, quality: Double)] = lossless ? [(true, 1)] : []
        attempts += [(false, 0.8), (false, 0.6)]
        for _ in 0..<4 {
            for attempt in attempts {
                payload.image = encode(image, lossless: attempt.lossless, quality: attempt.quality)
                if try payload.encoded().count <= budget { return payload }
            }
            guard let smaller = ImageProcessing.fit(image, in: CGSize(width: image.width * 3 / 4, height: image.height * 3 / 4)) else { break }
            image = smaller
        }
        throw RelayError.tooLarge
    }

    public var cgImage: CGImage? {
        guard let image, let source = CGImageSourceCreateWithData(image as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func encode(_ image: CGImage, lossless: Bool, quality: Double) -> Data? {
        if lossless { return SharedStore.encode(image, lossless: true) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
