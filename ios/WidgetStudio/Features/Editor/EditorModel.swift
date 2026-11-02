import CoreGraphics
import Observation
import PhotosUI
import SwiftUI
import UIKit
import WidgetKitCore

/// The design being edited (M3): every field the template defines, theme and colors, and a
/// photo processed for the widget (downscaled; halftone/mono applied once, here, ADR-015).
@MainActor
@Observable
final class EditorModel {
    var design: SavedDesign
    let isNew: Bool
    /// The processed photo picked in this session (stored on save).
    private(set) var newPhoto: CGImage?
    private(set) var isProcessingPhoto = false
    /// Set by the PhotosPicker; the view calls `loadPhoto` when it changes.
    var photoItem: PhotosPickerItem?
    var previewLanguage = RenderContext.preferredLanguage

    /// `photo`: an already processed photo (the AI flow's "Build around my photo").
    init(design: SavedDesign, isNew: Bool, photo: CGImage? = nil) {
        self.design = design
        self.isNew = isNew
        newPhoto = photo
    }

    var issues: [SpecIssue] { DesignEditing.validate(design) }
    var canSave: Bool { issues.isEmpty && !isProcessingPhoto }

    /// Fields edited in their own sections (photos have the photo section).
    var editableFields: [FieldSpec] { design.spec.fields.filter { $0.type != .image } }
    var hasPhoto: Bool { design.imageLayer != nil }

    // MARK: Field bindings

    /// One language of a bilingual field (text, city).
    func text(_ field: FieldSpec, language: String) -> Binding<String> {
        Binding(
            get: { DesignEditing.value(of: field.key, in: self.design)?.resolved(language: language) ?? "" },
            set: { newValue in
                let current = DesignEditing.value(of: field.key, in: self.design)
                var en = current?.resolved(language: "en") ?? ""
                var ar = current?.resolved(language: "ar") ?? ""
                if language == "ar" { ar = newValue } else { en = newValue }
                self.design.fieldValues[field.key] = .localized(en: en, ar: ar)
            }
        )
    }

    /// A single-value field (number, shortcut, url, timezone, icon, color).
    func plain(_ field: FieldSpec) -> Binding<String> {
        Binding(
            get: { DesignEditing.value(of: field.key, in: self.design)?.resolved(language: "en") ?? "" },
            set: { self.design.fieldValues[field.key] = .plain($0) }
        )
    }

    func date(_ field: FieldSpec) -> Binding<Date> {
        Binding(
            get: { self.plain(field).wrappedValue.isEmpty ? .now : FieldValues.date(self.plain(field).wrappedValue) ?? .now },
            set: { self.design.fieldValues[field.key] = .plain(DesignEditing.dateValue($0, for: field)) }
        )
    }

    func dateHasTime(_ field: FieldSpec) -> Bool {
        field.default?.allValues.first?.contains("T") ?? false
    }

    // MARK: Appearance

    /// "template" | "light" | "dark" for the picker.
    var themeChoice: String {
        get { design.theme?.rawValue ?? "template" }
        set { design.theme = SpecTheme(rawValue: newValue) }
    }

    /// "default" (the Settings clock) or a `ClockFormat` for this design (ADR-017).
    var clockChoice: String {
        get { design.clockFormat?.rawValue ?? "default" }
        set { design.clockFormat = ClockFormat(rawValue: newValue) }
    }

    /// A color override, shown with the theme's value when not overridden.
    func color(_ token: String) -> Binding<Color> {
        Binding(
            get: {
                let hex = self.design.colors[token] ?? SpecTokens.hex(token, theme: self.design.effectiveTheme) ?? "#000000"
                return Color(hex: hex)
            },
            set: { self.design.colors[token] = Self.hex($0) }
        )
    }

    func resetColor(_ token: String) {
        design.colors[token] = nil
    }

    static func hex(_ color: Color) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    // MARK: Layers (M6.1, ADR-022)

    /// Top-level layers whose text (or an icon over text) covers another.
    var overlapping: Set<Int> { SpecLayout.overlapping(in: design.spec.layers) }

    /// The layers inside `parent` (`[]` = the top level).
    func layers(in parent: LayerEditing.Path) -> [Layer] {
        guard !parent.isEmpty else { return design.spec.layers }
        guard case .stack(let stack)? = LayerEditing.layer(at: parent, in: design.spec.layers)?.content else { return [] }
        return stack.children
    }

    /// The layer at `path`; nil once it's gone (deleted, or its stack was ungrouped).
    func layer(_ path: LayerEditing.Path) -> Binding<Layer>? {
        guard let current = LayerEditing.layer(at: path, in: design.spec.layers) else { return nil }
        return Binding(
            get: { LayerEditing.layer(at: path, in: self.design.spec.layers) ?? current },
            set: { LayerEditing.replace(at: path, in: &self.design.spec.layers, with: $0) }
        )
    }

    func removeLayer(_ path: LayerEditing.Path) {
        LayerEditing.remove(at: path, in: &design.spec.layers)
    }

    func duplicateLayer(_ path: LayerEditing.Path) {
        LayerEditing.duplicate(at: path, in: &design.spec.layers)
    }

    func moveLayers(in parent: LayerEditing.Path, from source: IndexSet, to destination: Int) {
        LayerEditing.move(in: parent, from: source, to: destination, layers: &design.spec.layers)
    }

    /// Puts top-level layers in one stack; false when they can't share one.
    func groupLayers(_ indexes: Set<Int>) -> Bool {
        LayerEditing.group(Array(indexes), in: &design.spec.layers) != nil
    }

    func ungroupLayer(_ index: Int) {
        LayerEditing.ungroup(at: index, in: &design.spec.layers)
    }

    /// The same local fix the AI flow uses, on demand.
    func arrangeOverlaps() {
        design.spec = AILayoutFix.fix(design.spec)
    }

    // MARK: Photo

    /// Loads the picked photo, applies its orientation, and processes it for the image layer.
    func loadPhoto(_ item: PhotosPickerItem) async {
        guard let slot = design.imageLayer else { return }
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data),
              let upright = Self.upright(picked, maxSide: 2048) else { return }
        newPhoto = ImageProcessing.prepare(upright, frame: slot.frame, layer: slot.layer)
    }

    /// Redraws with the photo's orientation applied, at most `maxSide` px, so CGImage is upright.
    static func upright(_ image: UIImage, maxSide: CGFloat) -> CGImage? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
