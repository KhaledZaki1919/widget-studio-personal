import Foundation

/// Rules for what the editor lets the user change (M3, ADR-015). User values follow the field
/// types of brief §4.3; unlike spec defaults, a `url` field may hold a link (http/https only),
/// which is what `open.url` buttons need.
public enum DesignEditing {
    public static let maxTextLength = SpecValidator.maxTextLength

    /// Every issue of an edited design: name, colors, each field value (both languages) and the
    /// spec with the overrides applied. Empty = saveable.
    public static func validate(_ design: SavedDesign) -> [SpecIssue] {
        var issues: [SpecIssue] = []
        let name = design.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { issues.append(SpecIssue("name", "a name is required")) }
        if name.count > SavedDesign.maxNameLength { issues.append(SpecIssue("name", "at most \(SavedDesign.maxNameLength) characters")) }

        for (token, hex) in design.colors.sorted(by: { $0.key < $1.key }) {
            if !SavedDesign.editableColors.contains(token) { issues.append(SpecIssue("colors.\(token)", "not an editable color")) }
            if HexColor.parse(hex) == nil { issues.append(SpecIssue("colors.\(token)", "color must be #RRGGBB or #RRGGBBAA")) }
        }

        for (key, value) in design.fieldValues.sorted(by: { $0.key < $1.key }) {
            guard let field = design.spec.field(key) else {
                issues.append(SpecIssue("fields.\(key)", "the template has no field \"\(key)\""))
                continue
            }
            for text in value.allValues {
                issues += self.issues(value: text, for: field).map { SpecIssue("fields.\(key)", $0.message) }
            }
        }

        let resolved = design.spec.resolvingTokens(theme: design.theme, overrides: design.colors)
        if case .failure(let failure) = SpecValidator().validate(resolved) {
            issues += failure.issues.map { SpecIssue("spec.\($0.path)", $0.message) }
        }
        return issues
    }

    /// Issues of one user value for `field` (empty = valid).
    public static func issues(value: String, for field: FieldSpec) -> [SpecIssue] {
        let path = field.key
        if value.count > maxTextLength { return [SpecIssue(path, "at most \(maxTextLength) characters")] }
        switch field.type {
        case .text, .city:
            return SpecValidatorText.containsURL(value) ? [SpecIssue(path, "links are only allowed in link fields")] : []
        case .shortcut:
            return value.contains("://") ? [SpecIssue(path, "enter the Shortcut's name, not a link")] : []
        case .app:
            return value.contains("/") ? [SpecIssue(path, "enter an app id like com.spotify.music")] : []
        case .ticker:
            return value.count > 24 || value.contains(" ") ? [SpecIssue(path, "enter a ticker like TSLA or a coin like bitcoin")] : []
        case .url:
            guard !value.isEmpty else { return [] }
            guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else {
                return [SpecIssue(path, "must be a web link starting with https://")]
            }
            return []
        case .number:
            return Double(value) == nil ? [SpecIssue(path, "must be a number")] : []
        case .date:
            return FieldValues.date(value) == nil ? [SpecIssue(path, "must be a date")] : []
        case .timezone:
            return value.isEmpty || TimeZone(identifier: value) != nil ? [] : [SpecIssue(path, "unknown time zone")]
        case .color:
            return HexColor.parse(value) == nil ? [SpecIssue(path, "color must be #RRGGBB or #RRGGBBAA")] : []
        case .icon:
            return Icons.isAllowed(value) ? [] : [SpecIssue(path, "pick an icon from the list")]
        case .image:
            return []
        }
    }

    /// Whether the editor offers separate Arabic and English values for the field.
    public static func isBilingual(_ field: FieldSpec) -> Bool {
        field.type == .text || field.type == .city
    }

    /// The value currently in effect for a field: the user's, else the default.
    public static func value(of key: String, in design: SavedDesign) -> LocalizedText? {
        design.fieldValues[key] ?? design.spec.field(key)?.default
    }

    /// Writes an ISO 8601 value for a date field, keeping a time only if the default has one.
    public static func dateValue(_ date: Date, for field: FieldSpec, timeZone: TimeZone = .current) -> String {
        let defaultHasTime = field.default?.allValues.first?.contains("T") ?? false
        if defaultHasTime {
            return ISO8601DateFormatter().string(from: date)
        }
        return FormatterCache.date("yyyy-MM-dd", locale: "en_US_POSIX", zone: timeZone).string(from: date)
    }
}

/// The URL check the validator uses for spec texts, shared with the editor.
enum SpecValidatorText {
    static func containsURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("://") || lower.hasPrefix("www.") || lower.contains(" www.")
    }
}
