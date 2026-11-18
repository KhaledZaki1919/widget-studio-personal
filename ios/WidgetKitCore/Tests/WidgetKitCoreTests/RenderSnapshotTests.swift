import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WidgetKitCore

/// Renders checked on every push (ADR-023), written to `RENDER_OUT` when set (CI uploads them as
/// `package-renders`):
/// - every template in the Tinted home screen's accented mode: no large solid block may be left,
///   since iOS turns it into a solid white shape (device report 2026-11-02: the Prayer Times
///   column and the analog clock face); `accented/<id>.png` shows before | after as iOS tints them;
/// - the frosted-card AI answer from the same report, before and after the local layout fix.
@Suite(.serialized)
@MainActor
struct RenderSnapshotTests {
    /// Every state of every set, one PNG each, in `RENDER_OUT/states/` (ADR-028).
    @Test @MainActor func everyStateOfEverySet() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { return }
        let folder = URL(fileURLWithPath: out).appendingPathComponent("states")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for set in Capabilities.stateSets {
            let states = StatesLayer(set: set.id, value: set.value)
            let layer = Layer(frame: Frame(x: 25, y: 25, w: 120, h: 120), content: .states(states))
            let spec = WidgetSpec(id: "state", name: "state", family: .small, background: .solid("@bg"), layers: [layer])
            for variant in states.expanded {
                var context = RenderContext(language: "en", data: .sample())
                context.overrides = BindingResolver.overrides(for: variant, of: states)
                #expect(BindingResolver(spec: spec, context: context).variant(of: states)?.id == variant.id)
                if let image = SpecSnapshot.render(spec, overrides: context.overrides) {
                    try writePNG(image, to: folder.appendingPathComponent("\(set.id).\(variant.id).png"))
                }
            }
        }
        // The templates that show them: the same widget in each state, real date for the year.
        let date = ISO8601DateFormatter().date(from: "2026-11-05T10:00:00Z") ?? .now
        for id in ["mono.battery.mood", "mono.weather.art"] {
            guard let spec = TemplateLibrary.template(id: id) else { continue }
            for layer in spec.layers {
                guard case .states(let states) = layer.content else { continue }
                for variant in states.expanded {
                    var overrides = BindingResolver.overrides(for: variant, of: states)
                    if overrides["weather.kind"] != nil {
                        overrides["weather.symbol"] = symbol(for: variant.id)
                        overrides["weather.cond"] = variant.title?.resolved(language: "en")
                    }
                    if let image = SpecSnapshot.render(spec, date: date, overrides: overrides) {
                        try writePNG(image, to: folder.appendingPathComponent("\(id).\(variant.id).png"))
                    }
                }
            }
        }
        if let spec = TemplateLibrary.template(id: "mono.year.dots"), let image = SpecSnapshot.render(spec, date: date) {
            try writePNG(image, to: folder.appendingPathComponent("mono.year.dots.2026-11-05.png"))
        }
    }

    private func symbol(for variant: String) -> String {
        ["storm": "cloud.bolt.rain.fill", "snow": "cloud.snow.fill", "rain": "cloud.rain.fill", "fog": "cloud.fog.fill", "cloud": "cloud.fill",
         "partlyDay": "cloud.sun.fill", "partlyNight": "cloud.moon.fill", "sun": "sun.max.fill", "moon": "moon.stars.fill"][variant] ?? "cloud.fill"
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// The largest share of 8 pt cells that may be solid in the accented variant.
    static let maxSolidShare = 0.08

    init() {
        Self.registerFonts()
    }

    @Test func everyTemplateHasNoSolidBlocksInAccentedMode() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-02T09:41:00Z"))
        var report = ["| Template | Solid before | Solid after |", "|---|---|---|"]
        for spec in TemplateLibrary.all() {
            let before = try #require(SpecSnapshot.render(spec, date: date, accented: false, background: false))
            let after = try #require(SpecSnapshot.render(spec, date: date, accented: true))
            let solidBefore = Self.solidShare(before)
            let solidAfter = Self.solidShare(after)
            report.append("| \(spec.id) | \(Int(solidBefore * 100)) % | \(Int(solidAfter * 100)) % |")
            #expect(solidAfter <= Self.maxSolidShare, "\(spec.id): \(Int(solidAfter * 100)) % solid in accented mode")
            if let tintedBefore = SpecSnapshot.tinted(before), let tintedAfter = SpecSnapshot.tinted(after),
               let pair = Self.sideBySide([tintedBefore, tintedAfter]) {
                try Self.write(pair, "accented/\(spec.id).png")
            }
        }
        try Self.writeText(report.joined(separator: "\n"), "accented/summary.md")
    }

    /// Device report 2026-11-02, rebuilt: a frosted card with "hello" and the date at the top,
    /// weather and month at the bottom, a center line and the time in an orange pill. The model
    /// drew the time before the pill and let the corner texts' frames overlap.
    @Test func frostedCardKeepsEveryTextInsideTheWidget() throws {
        let spec = try Self.frostedCard()
        #expect(!SpecLayout.textOverlaps(in: spec.layers).isEmpty)
        #expect(!SpecLayout.coveredTexts(in: spec.layers).isEmpty)
        let fixed = AILayoutFix.fix(spec)
        #expect(SpecLayout.textOverlaps(in: fixed.layers).isEmpty)
        #expect(SpecLayout.coveredTexts(in: fixed.layers).isEmpty)
        #expect(AILayoutFix.texts(in: fixed) == AILayoutFix.texts(in: spec), "a text was lost")
        guard case .success = SpecValidator(mode: .ai).validate(fixed) else {
            Issue.record("the fixed card is invalid")
            return
        }
        let canvas = fixed.family.canvas
        for layer in fixed.layers {
            let frame = layer.frame
            #expect(frame.x >= 0 && frame.y >= 0 && frame.x + frame.w <= canvas.width && frame.y + frame.h <= canvas.height)
        }
        // The time stays in its pill, above it.
        let pill = try #require(fixed.layers.firstIndex { if case .shape(let shape) = $0.content { shape.kind == .capsule } else { false } })
        let time = try #require(fixed.layers.firstIndex { layer in
            layer.flattened.contains { if case .text(let text) = $0.content { text.value.resolved(language: "en").contains("time.hh") } else { false } }
        })
        #expect(time > pill)
        #expect(SpecLayout.share(of: fixed.layers[time].frame, inside: fixed.layers[pill].frame) >= 0.8)

        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-02T09:41:00Z"))
        if let raw = SpecSnapshot.render(spec, date: date), let done = SpecSnapshot.render(fixed, date: date),
           let pair = Self.sideBySide([raw, done]) {
            try Self.write(pair, "layout/frosted-card.png")
        }
    }

    // MARK: Fixtures

    static func frostedCard() throws -> WidgetSpec {
        func text(_ value: String, _ frame: [Double], size: Double, family: String = "system", align: String = "leading") -> String {
            """
            {"type": "text", "value": {"en": "\(value)", "ar": "\(value)"}, "font": {"family": "\(family)", "size": \(size)},
             "color": "#FFFFFF", "align": "\(align)", "frame": {"x": \(frame[0]), "y": \(frame[1]), "w": \(frame[2]), "h": \(frame[3])}}
            """
        }
        let layers = [
            ##"{"type": "shape", "kind": "rect", "fill": "#FFFFFF2E", "glass": true, "frame": {"x": 0, "y": 0, "w": 364, "h": 170}}"##,
            ##"{"type": "shape", "kind": "rect", "fill": "#FFFFFFB3", "frame": {"x": 181, "y": 10, "w": 2, "h": 150}}"##,
            text("hello", [20, 16, 200, 50], size: 30, family: "hand"),
            text("{{date.d}} {{date.EEEE}}", [150, 16, 194, 50], size: 16, align: "trailing"),
            text("{{weather.temp}}° {{weather.cond}}", [20, 110, 200, 44], size: 16),
            text("{{date.MMM}}", [150, 110, 194, 44], size: 16, align: "trailing"),
            text("{{time.hh}}\\n{{time.mm}}", [166, 52, 32, 66], size: 15, family: "system-mono", align: "center"),
            ##"{"type": "shape", "kind": "capsule", "fill": "#FF5A1F", "frame": {"x": 164, "y": 50, "w": 36, "h": 70}}"##,
        ]
        let json = """
        {"schemaVersion": 1, "id": "test.frosted", "name": {"en": "Hello", "ar": "مرحبا"}, "family": "medium", "theme": "dark",
         "background": {"type": "glass", "color": "#2A2622CC"}, "layers": [\(layers.joined(separator: ","))]}
        """
        return try JSONDecoder().decode(WidgetSpec.self, from: Data(json.utf8))
    }

    // MARK: Helpers

    /// Share of 8 pt cells (24 px at scale 3) whose pixels are all nearly opaque.
    static func solidShare(_ image: CGImage, cell: Int = 24) -> Double {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var solid = 0
        var cells = 0
        for top in stride(from: 0, to: height - cell, by: cell) {
            for left in stride(from: 0, to: width - cell, by: cell) {
                cells += 1
                var full = true
                scan: for y in top..<(top + cell) {
                    for x in left..<(left + cell) where pixels[(y * width + x) * 4 + 3] < 230 {
                        full = false
                        break scan
                    }
                }
                if full { solid += 1 }
            }
        }
        return Double(solid) / Double(max(cells, 1))
    }

    static func registerFonts() {
        let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Fonts").standardizedFileURL
        let files = (try? FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil)) ?? []
        for file in files where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    static func sideBySide(_ images: [CGImage], padding: CGFloat = 24) -> CGImage? {
        let height = CGFloat(images.map(\.height).max() ?? 0)
        let size = CGSize(width: CGFloat(images.map(\.width).reduce(0, +)) + padding * CGFloat(images.count + 1), height: height + padding * 2)
        return ImageProcessing.draw(size: size) { context in
            context.setFillColor(CGColor(red: 0.9, green: 0.91, blue: 0.93, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            var x = padding
            for image in images {
                context.draw(image, in: CGRect(x: x, y: padding, width: CGFloat(image.width), height: CGFloat(image.height)))
                x += CGFloat(image.width) + padding
            }
        }
    }

    static func write(_ image: CGImage, _ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["RENDER_OUT"] else { return }
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return }
        try (data as Data).write(to: url)
    }

    static func writeText(_ text: String, _ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["RENDER_OUT"] else { return }
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
