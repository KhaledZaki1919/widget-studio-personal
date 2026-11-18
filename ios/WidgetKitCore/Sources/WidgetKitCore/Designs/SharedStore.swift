import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The one storage layer for saved designs and their photos (M3, ADR-015). It writes to the App
/// Group container when the resolver finds one (shared with the widget), otherwise to the app's
/// own container. All app and widget code goes through it, so nothing changes when the App
/// Group starts working with the owner's own Apple account.
///
/// Layout: `<container>/Designs/designs.json` (all designs, newest first) and
/// `<container>/Designs/Images/<file>`.
public struct SharedStore: Sendable {
    public let location: StoreLocation

    public init(location: StoreLocation = AppGroupResolver.resolve()) {
        self.location = location
    }

    /// True when the widget extension can read what the app saves.
    public var isShared: Bool { location.isShared }

    var folder: URL { location.directory.appendingPathComponent("Designs", isDirectory: true) }
    var designsURL: URL { folder.appendingPathComponent("designs.json") }
    var imagesFolder: URL { folder.appendingPathComponent("Images", isDirectory: true) }

    // MARK: Designs

    /// All saved designs, most recently updated first. An unreadable file reads as empty.
    public func designs() -> [SavedDesign] {
        guard let data = try? Data(contentsOf: designsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let designs = (try? decoder.decode([SavedDesign].self, from: data)) ?? []
        return designs.sorted { $0.updated > $1.updated }
    }

    public func design(id: String) -> SavedDesign? {
        designs().first { $0.id == id }
    }

    /// Designs that fit a widget of `size` (same size or smaller), newest first.
    public func designs(fitting size: SpecFamily) -> [SavedDesign] {
        designs().filter { $0.spec.family.rank <= size.rank }
    }

    /// Inserts or replaces by id, stamping `updated`.
    @discardableResult
    public func save(_ design: SavedDesign, now: Date = .now) throws -> SavedDesign {
        var design = design
        design.updated = now
        var all = designs().filter { $0.id != design.id }
        all.insert(design, at: 0)
        try write(all)
        return design
    }

    public func rename(id: String, to name: String, now: Date = .now) throws {
        guard var design = design(id: id) else { return }
        design.name = name
        try save(design, now: now)
    }

    /// A copy with a new id and name, including a copy of the photo.
    @discardableResult
    public func duplicate(id: String, name: String, now: Date = .now) throws -> SavedDesign? {
        guard let original = design(id: id) else { return nil }
        var copy = original
        copy.id = UUID().uuidString
        copy.name = name
        copy.created = now
        if let file = original.imageFile, let data = try? Data(contentsOf: imagesFolder.appendingPathComponent(file)) {
            copy.imageFile = try storeImageData(data, designID: copy.id, fileExtension: (file as NSString).pathExtension)
        }
        return try save(copy, now: now)
    }

    /// The bytes of a photo, kept while a delete can still be undone.
    public func imageData(named file: String) -> Data? {
        try? Data(contentsOf: imagesFolder.appendingPathComponent(file))
    }

    /// Puts a deleted design back, with its photo (Undo, ADR-028).
    public func restore(_ design: SavedDesign, image: Data?) throws {
        if let file = design.imageFile, let image { try FileProtection.write(image, to: imagesFolder.appendingPathComponent(file)) }
        var all = designs().filter { $0.id != design.id }
        all.append(design)
        try write(all)
        try? FileManager.default.removeItem(at: deletedMark)
    }

    private var deletedMark: URL { folder.appendingPathComponent("deleted") }

    /// A design was deleted, so a widget with nothing to show says so instead of looking empty.
    public var hasDeletedDesign: Bool { FileManager.default.fileExists(atPath: deletedMark.path) }

    /// Removes the design and its photo.
    public func delete(id: String) throws {
        let all = designs()
        if let file = all.first(where: { $0.id == id })?.imageFile {
            try? FileManager.default.removeItem(at: imagesFolder.appendingPathComponent(file))
        }
        try write(all.filter { $0.id != id })
        try? FileProtection.write(Data(), to: deletedMark)
    }

    private func write(_ designs: [SavedDesign]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try FileProtection.write(try encoder.encode(designs), to: designsURL)
    }

    // MARK: Images

    /// Stores an already processed photo for a design (PNG keeps halftone dots sharp, JPEG else)
    /// and returns the file name to put in `SavedDesign.imageFile`.
    public func storeImage(_ image: CGImage, designID: String, lossless: Bool) throws -> String {
        guard let data = Self.encode(image, lossless: lossless) else { throw CocoaError(.fileWriteUnknown) }
        return try storeImageData(data, designID: designID, fileExtension: lossless ? "png" : "jpg")
    }

    func storeImageData(_ data: Data, designID: String, fileExtension: String) throws -> String {
        // A fresh name per save, so a widget never shows a half-written file.
        let name = "\(designID)-\(UUID().uuidString.prefix(8)).\(fileExtension)"
        try FileProtection.write(data, to: imagesFolder.appendingPathComponent(name))
        return name
    }

    public func image(named file: String) -> CGImage? {
        let url = imagesFolder.appendingPathComponent(file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Deletes photos no design refers to (after edits replace a photo).
    public func removeUnusedImages() {
        let used = Set(designs().compactMap(\.imageFile))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesFolder.path)) ?? []
        for file in files where !used.contains(file) {
            try? FileManager.default.removeItem(at: imagesFolder.appendingPathComponent(file))
        }
    }

    static func encode(_ image: CGImage, lossless: Bool) -> Data? {
        let data = NSMutableData()
        let type = (lossless ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        let options: [CFString: Any] = lossless ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
