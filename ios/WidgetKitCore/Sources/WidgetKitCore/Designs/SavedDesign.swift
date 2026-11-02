import CoreGraphics
import Foundation

/// A template the user customized and saved (M3, ADR-015): a copy of the template spec at save
/// time (later template updates don't change it), the user's field values, theme and color
/// overrides, and the processed photo's file in `SharedStore`.
public struct SavedDesign: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var templateID: String
    public var spec: WidgetSpec
    /// Field key → value; text, city and similar fields may hold `{en, ar}`.
    public var fieldValues: [String: LocalizedText]
    /// nil = the template's own theme.
    public var theme: SpecTheme?
    /// Color token overrides (`accent`, `bg`, `fg`) → hex.
    public var colors: [String: String]
    /// File name of the processed photo in `SharedStore`'s images folder.
    public var imageFile: String?
    /// 12/24-hour clock for this design; nil = the Settings default (ADR-017).
    public var clockFormat: ClockFormat?
    public var created: Date
    public var updated: Date

    /// Tokens the editor lets the user override.
    public static let editableColors = ["accent", "bg", "fg", "muted"]
    public static let maxNameLength = 60

    public init(id: String = UUID().uuidString, name: String, template: WidgetSpec, fieldValues: [String: LocalizedText] = [:],
                theme: SpecTheme? = nil, colors: [String: String] = [:], imageFile: String? = nil, now: Date = .now) {
        self.id = id
        self.name = name
        templateID = template.id
        spec = template
        self.fieldValues = fieldValues
        self.theme = theme
        self.colors = colors
        self.imageFile = imageFile
        created = now
        updated = now
    }

    /// A new design from a template, named after it in `language`. Field values start empty:
    /// the renderer falls back to each field's default until the user edits it.
    public static func new(from template: WidgetSpec, language: String, now: Date = .now) -> SavedDesign {
        SavedDesign(name: template.name.resolved(language: language), template: template, now: now)
    }

    /// The design's theme: the user's choice, else the template's.
    public var effectiveTheme: SpecTheme { theme ?? spec.theme }

    /// Everything a renderer needs for this design.
    /// `defaultClock` is the Settings default used when the design has no clock choice.
    public func renderContext(date: Date = .now, language: String, data: DataSnapshot, image: CGImage? = nil,
                              defaultClock: ClockFormat = .device) -> RenderContext {
        var context = RenderContext(date: date, language: language, fieldValues: fieldValues, data: data, userImage: image)
        context.theme = theme
        context.tokenOverrides = colors
        context.uses24Hour = (clockFormat ?? defaultClock).uses24Hour()
        return context
    }

    /// The image layer the photo is processed for (size, mask, filter), if the template has one.
    public var imageLayer: (frame: Frame, layer: ImageLayer)? {
        for layer in spec.layers {
            if case .image(let image) = layer.content, image.source == "user_image" { return (layer.frame, image) }
        }
        return nil
    }
}
