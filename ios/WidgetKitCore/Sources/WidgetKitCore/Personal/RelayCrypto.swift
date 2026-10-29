import CommonCrypto
import CryptoKit
import Foundation

// Personal build (docs/personal.md): pairing and end-to-end encryption for the Cloudflare relay.
// The widget shows an 8-character code; the app gets it typed in once. Both derive, per slot, a
// storage ID and a separate AES key from it. The relay only ever sees the ID (a one-way hash)
// and ciphertext: it can't recover the code, the key or the design.

/// The pairing code the widget shows: 8 characters from an alphabet without look-alikes
/// (no 0/O, 1/I/L), shown as "ABCD-EFGH".
public enum RelayCode {
    public static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    public static let length = 8

    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(generator.next(upperBound: UInt32(alphabet.count)))] })
    }

    /// The canonical code from what the user typed (any case, spaces, dashes), or nil.
    public static func normalize(_ input: String) -> String? {
        let code = input.uppercased().filter { !" -_\t\n".contains($0) }
        guard code.count == length, code.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return code
    }

    /// "ABCD-EFGH".
    public static func formatted(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(length / 2))-\(code.suffix(length / 2))"
    }
}

/// What one paired item is stored under: `pair` confirms the pairing, the sizes carry designs.
public enum RelaySlot: String, Codable, Sendable, CaseIterable {
    case pair, small, medium, large

    public init(_ family: SpecFamily) {
        switch family {
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        }
    }
}

/// The storage ID and the encryption key of one slot, both derived from the code.
public struct RelayKeys: Sendable {
    /// 64 hex characters; the only thing the relay learns.
    public let id: String
    let key: SymmetricKey

    /// PBKDF2 stretches the short code (slows down guessing it from a stored ID), then HKDF
    /// gives independent outputs for the ID and the key: knowing one says nothing about the other.
    public static func derive(code: String, slot: RelaySlot) -> RelayKeys {
        let root = SymmetricKey(data: stretched(code))
        let id = HKDF<SHA256>.deriveKey(inputKeyMaterial: root, info: Data("id/\(slot.rawValue)".utf8), outputByteCount: 32)
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: root, info: Data("key/\(slot.rawValue)".utf8), outputByteCount: 32)
        return RelayKeys(id: id.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined(), key: key)
    }

    static let salt = Data("WidgetStudioP/relay/v1".utf8)
    static let rounds: UInt32 = 100_000

    private static let lock = NSLock()
    nonisolated(unsafe) private static var memo: [String: Data] = [:]

    /// PBKDF2-HMAC-SHA256 of the code, memoized per process (the widget derives several slots).
    static func stretched(_ code: String) -> Data {
        lock.lock()
        defer { lock.unlock() }
        if let known = memo[code] { return known }
        var output = Data(count: 32)
        let password = Array(code.utf8).map { Int8(bitPattern: $0) }
        let saltBytes = Array(salt)
        _ = output.withUnsafeMutableBytes { buffer in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.count, saltBytes, saltBytes.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                 buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
        }
        memo[code] = output
        return output
    }

    /// Format byte + AES-GCM (nonce, ciphertext, tag).
    public func seal(_ plaintext: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else { throw RelayError.crypto }
        return Data([Self.format]) + combined
    }

    public func open(_ sealed: Data) throws -> Data {
        guard sealed.first == Self.format else { throw RelayError.crypto }
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: Data(sealed.dropFirst())), using: key)
        } catch {
            throw RelayError.crypto
        }
    }

    static let format: UInt8 = 1
}

public enum RelayError: Error, Equatable, Sendable {
    /// No relay URL compiled in (`WSRelayURL`).
    case notConfigured
    /// Wrong code or damaged data.
    case crypto
    /// The design and photo don't fit in one item even after shrinking the photo.
    case tooLarge
    case rateLimited
    case http(Int)
    case network(String)
}
