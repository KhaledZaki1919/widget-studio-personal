import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import WidgetKitCore

/// ADR-024: finding the widget(s) in a picked image, on the drawn eval images in `docs/ai-eval`.
/// Writes each image with its detections outlined to `RENDER_OUT/detect/` (CI artifact
/// `package-renders`).
@Suite(.serialized)
@MainActor
struct WidgetDetectorTests {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../docs/ai-eval").standardizedFileURL

    func image(_ name: String) throws -> CGImage {
        let url = Self.folder.appendingPathComponent(name)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "missing \(name)")
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Detects, writes the outlined image, and returns the widgets.
    func detect(_ name: String) throws -> [DetectedWidget] {
        let picture = try image(name)
        let found = WidgetDetector.detect(picture)
        try Self.writeOutlined(picture, found, name: name)
        return found
    }

    func matches(_ found: DetectedWidget?, _ expected: CGRect, tolerance: CGFloat = 0.8) -> Bool {
        guard let found else { return false }
        return WidgetDetector.inside(expected, found.rect) >= tolerance && WidgetDetector.inside(found.rect, expected.insetBy(dx: -40, dy: -40)) >= tolerance
    }

    @Test func cardOnABusyWallpaper() throws {
        let found = try detect("draw-wallpaper.png")
        let biggest = found.max { WidgetDetector.area($0.rect) < WidgetDetector.area($1.rect) }
        #expect(matches(biggest, CGRect(x: 70, y: 250, width: 860, height: 410)), "\(found)")
        #expect(biggest?.shape == .roundedRect)
        #expect(biggest?.suggestedSize(imageWidth: 1000) == .medium)
    }

    @Test func cardWithADropShadow() throws {
        let found = try detect("draw-shadow.png")
        #expect(found.count == 1, "\(found)")
        #expect(matches(found.first, CGRect(x: 230, y: 200, width: 440, height: 440)), "\(found)")
    }

    @Test func circleAndCapsuleCards() throws {
        let circle = try detect("draw-circle.png")
        #expect(matches(circle.first, CGRect(x: 190, y: 170, width: 520, height: 520)), "\(circle)")
        #expect(circle.first?.shape == .circle, "\(circle)")
        let capsule = try detect("draw-capsule.png")
        #expect(matches(capsule.first, CGRect(x: 110, y: 220, width: 880, height: 260)), "\(capsule)")
        #expect(capsule.first?.shape == .capsule, "\(capsule)")
    }

    @Test func floatingContentWithNoCard() throws {
        let found = try detect("draw-floating.png")
        #expect(found.count == 1, "\(found)")
        #expect(found.first?.shape == WidgetCardShape.none, "\(found)")
        // The padded box holds the day, the date and the month line.
        if let rect = found.first?.rect {
            #expect(WidgetDetector.inside(CGRect(x: 300, y: 320, width: 260, height: 280), rect) > 0.85, "\(rect)")
        }
    }

    @Test func galleryOfFour() throws {
        let found = try detect("draw-gallery.png")
        #expect(found.count == 4, "\(found)")
        let expected = [CGRect(x: 70, y: 70, width: 400, height: 400), CGRect(x: 530, y: 70, width: 400, height: 400),
                        CGRect(x: 70, y: 530, width: 400, height: 400), CGRect(x: 530, y: 530, width: 400, height: 400)]
        for (index, rect) in expected.enumerated() where index < found.count {
            #expect(matches(found[index], rect), "widget \(index): \(found[index])")
        }
    }

    /// The app and the eval detect on downscaled copies (AIImage.upright): the shapes must hold.
    @Test func shapesHoldWhenScaledDown() throws {
        for (name, shape, count) in [("draw-circle.png", WidgetCardShape.circle, 1), ("draw-capsule.png", .capsule, 1),
                                     ("draw-gallery.png", .roundedRect, 4), ("draw-wallpaper.png", .roundedRect, 1)] {
            for side in [1024, 700] {
                let data = try Data(contentsOf: Self.folder.appendingPathComponent(name))
                let picture = try #require(AIImage.upright(data: data, maxSide: side))
                let found = WidgetDetector.detect(picture)
                try Self.writeOutlined(picture, found, name: "\(side)-\(name)")
                // One widget: the biggest detection; a gallery: the first in reading order.
                let main = count == 1 ? found.max { WidgetDetector.area($0.rect) < WidgetDetector.area($1.rect) } : found.first
                // The pill must be whole, not half of it (eval 2026-11-02).
                if shape == .capsule, let main { #expect(main.rect.width > 0.7 * CGFloat(picture.width), "(name) at (side): (main.rect)") }
                #expect(found.count >= count && main?.shape == shape, "\(name) at \(side): \(found)")
            }
        }
    }

    @Test func wallpaperColorAroundACard() throws {
        let picture = try image("draw-circle.png")
        let hex = try #require(WidgetDetector.wallpaperColor(picture, around: CGRect(x: 190, y: 170, width: 520, height: 520)))
        let color = try #require(HexColor.parse(hex))
        #expect(color.red < 0.3 && color.blue < 0.4, "\(hex) should be the dark blue wallpaper")
    }

    @Test func classification() {
        #expect(WidgetDetector.classify(fill: 0.785, aspect: 1) == .circle)
        #expect(WidgetDetector.classify(fill: 0.89, aspect: 2) == .capsule)
        #expect(WidgetDetector.classify(fill: 0.937, aspect: 3.4) == .capsule)   // the long pill of the eval
        #expect(WidgetDetector.classify(fill: 0.97, aspect: 2.1) == .roundedRect)
        #expect(WidgetDetector.classify(fill: 0.96, aspect: 1) == .roundedRect)
        #expect(WidgetDetector.classify(fill: 0.5, aspect: 1) == nil)
    }

    static func writeOutlined(_ image: CGImage, _ widgets: [DetectedWidget], name: String) throws {
        guard let picture = outlined(image, widgets) else { return }
        try RenderSnapshotTests.write(picture, "detect/\(name)")
    }

    /// The image with each detection outlined in its shape (the first in pink, the rest in cyan).
    static func outlined(_ image: CGImage, _ widgets: [DetectedWidget]) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        return ImageProcessing.draw(size: size, { context in
            context.draw(image, in: CGRect(origin: .zero, size: size))
            for (index, widget) in widgets.enumerated() {
                // Drawing coordinates have the origin at the bottom left.
                let rect = CGRect(x: widget.rect.minX, y: size.height - widget.rect.maxY, width: widget.rect.width, height: widget.rect.height)
                context.setStrokeColor(index == 0 ? CGColor(red: 1, green: 0.1, blue: 0.4, alpha: 1) : CGColor(red: 0.1, green: 0.9, blue: 1, alpha: 1))
                context.setLineWidth(6)
                switch widget.shape {
                case .circle: context.strokeEllipse(in: rect)
                case .capsule: context.addPath(CGPath(roundedRect: rect, cornerWidth: min(rect.width, rect.height) / 2,
                                                      cornerHeight: min(rect.width, rect.height) / 2, transform: nil)); context.strokePath()
                case .none: context.setLineDash(phase: 0, lengths: [16, 10]); context.stroke(rect); context.setLineDash(phase: 0, lengths: [])
                case .roundedRect: context.addPath(CGPath(roundedRect: rect, cornerWidth: 30, cornerHeight: 30, transform: nil)); context.strokePath()
                }
            }
        })
    }
}

/// ADR-024: the model reports the card shape; circle and capsule cards are drawn inside the widget.
struct CardShapeTests {
    /// A v1 reply (no specVersion): circles and pills are drawn inside the family canvas.
    static var v1Example: String {
        ExternalAI.example.replacingOccurrences(of: "\"specVersion\":2,", with: "")
            .replacingOccurrences(of: "\"card\":{\"shape\":\"roundedRect\",\"aspect\":1,\"cornerRadius\":28},", with: "")
    }

    /// ADR-029: a v2 reply's card becomes the spec's card, and layers live in its canvas.
    @Test func v2CardsKeepTheirShapeAndRatio() throws {
        let reply = ExternalAI.example.replacingOccurrences(of: "\"card\":{\"shape\":\"roundedRect\",\"aspect\":1,\"cornerRadius\":28}",
                                                            with: "\"card\":{\"shape\":\"capsule\",\"aspect\":0.66,\"orientation\":\"vertical\"}")
        let parsed = try AIWidgetParser.parse(reply, options: GenerationOptions(wallpaperColor: "#123456"), id: "gen.card")
        #expect(parsed.spec.card?.shape == .capsule && parsed.spec.card?.aspect == 0.66)
        #expect(abs(parsed.spec.canvas.width - 112.2) < 0.6 && parsed.spec.canvas.height == 170)
        #expect(parsed.colors["outer"] == "#123456")
        let square = try AIWidgetParser.parse(ExternalAI.example, options: GenerationOptions(), id: "gen.card")
        #expect(square.spec.card == nil && square.spec.schemaVersion == 2)
    }

    func reply(card: String?) -> String {
        guard let card else { return Self.v1Example }
        return Self.v1Example.replacingOccurrences(of: "\"fields\":[]", with: "\"card\":{\"shape\":\"\(card)\"},\"fields\":[]")
    }

    @Test func circleAndCapsuleCardsUseTheOuterColor() throws {
        let options = GenerationOptions(wallpaperColor: "#123456")
        let circle = try AIWidgetParser.parse(reply(card: "circle"), options: options, id: "gen.card")
        #expect(circle.spec.background.outerColor == "@outer" && circle.spec.background.cardShape == .circle)
        #expect(circle.colors["outer"] == "#123456")
        let capsule = try AIWidgetParser.parse(reply(card: "capsule"), options: GenerationOptions(), id: "gen.card")
        #expect(capsule.spec.background.cardShape == .capsule && capsule.colors["outer"] == "#000000")
        let plain = try AIWidgetParser.parse(reply(card: "roundedRect"), options: options, id: "gen.card")
        #expect(plain.spec.background.outerColor == nil && plain.colors["outer"] == nil)
    }

    @Test func floatingDesignsUseTheWallpaperColor() throws {
        let floating = try AIWidgetParser.parse(reply(card: "none"), options: GenerationOptions(wallpaperColor: "#2a3b4c"), id: "gen.card")
        #expect(floating.spec.background.type == .solid && floating.spec.background.color == "@bg")
        #expect(floating.colors["bg"] == "#2A3B4C")
    }

    @Test func theDetectedShapeIsTheFallback() throws {
        let parsed = try AIWidgetParser.parse(reply(card: nil), options: GenerationOptions(detectedCard: .capsule), id: "gen.card")
        #expect(parsed.spec.background.cardShape == .capsule)
        #expect(WidgetPrompt.system.contains("Design only the content inside the widget's own card"))
        #expect(AIWidgetSchema.schema(mode: .recreate)["properties"]?["card"] != nil)
        let text = WidgetPrompt.userText(options: GenerationOptions(detectedCard: .circle, cropped: true), imageWidth: 500, imageHeight: 500)
        #expect(text.contains("cropped to the widget") && text.contains("a circle"))
    }
}
