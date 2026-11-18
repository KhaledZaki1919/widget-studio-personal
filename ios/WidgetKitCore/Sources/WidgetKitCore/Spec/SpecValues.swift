import Foundation

/// `#RRGGBB` / `#RRGGBBAA` (brief §4.6).
public struct HexColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public static func parse(_ text: String) -> HexColor? {
        guard text.hasPrefix("#") else { return nil }
        let hex = text.dropFirst()
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let rgba = hex.count == 6 ? (value << 8) | 0xFF : value
        return HexColor(
            red: Double((rgba >> 24) & 0xFF) / 255,
            green: Double((rgba >> 16) & 0xFF) / 255,
            blue: Double((rgba >> 8) & 0xFF) / 255,
            alpha: Double(rgba & 0xFF) / 255
        )
    }
}

/// Literal values allowed where a binding could also go.
public enum SpecLiterals {
    /// Comma-separated levels 0…1: `"0.2,0.5,1"` (at most 31).
    public static func levels(_ value: String) -> [Double]? {
        let parts = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.count <= 31,
              parts.allSatisfy({ $0.map { (0...1).contains($0) } ?? false }) else { return nil }
        return parts.compactMap { $0 }
    }

    /// A dot pattern of digits, row by row; spaces are ignored. `"0110 1001"` (0 off, 1 on), or levels
    /// `0`…`9` (ADR-029: 9 full, 5 about half) when any digit is above 1.
    public static func dotPattern(_ value: String) -> [Double]? {
        let digits = value.filter { $0 != " " }
        guard !digits.isEmpty, digits.count <= SpecValidator.maxDots, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        let binary = digits.allSatisfy { $0 == "0" || $0 == "1" }
        return digits.map { digit in
            let level = Double(digit.wholeNumberValue ?? 0)
            return binary ? level : level / 9
        }
    }
}

/// Parses field values stored as strings.
public enum FieldValues {
    /// `2026-12-31` (local midnight) or full ISO 8601 with a time.
    public static func date(_ value: String) -> Date? {
        let full = ISO8601DateFormatter()
        if let date = full.date(from: value) { return date }
        // Without a zone ("2026-12-31T09:00:00", as AI output writes them): local time.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let date = local.date(from: value) { return date }
        }
        return nil
    }
}
