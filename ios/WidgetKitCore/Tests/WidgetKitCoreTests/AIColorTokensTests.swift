import Foundation
import Testing
@testable import WidgetKitCore

/// M6.1 item 2a: AI colors become theme tokens, so the editor's pickers reach them.
struct AIColorTokensTests {
    /// The recreate reply with every token replaced by plain hex, plus a gray secondary label.
    func hexReply() throws -> String {
        var text = String(decoding: try aiFixture("spec-recreate"), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"@bg\"", with: "\"#101418\"")
            .replacingOccurrences(of: "\"@fg\"", with: "\"#F4F4F4\"")       // close to fg #F5F5F5
            .replacingOccurrences(of: "\"@accent\"", with: "\"#FF5A36\"")
            .replacingOccurrences(of: "\"@onAccent\"", with: "\"#8A8A8A\"")  // a gray secondary text
        return text
    }

    @Test func paletteHexBecomesTokens() throws {
        let (spec, colors) = try AIWidgetParser.parse(try hexReply(), options: GenerationOptions(), id: "gen.tokens")
        #expect(spec.background.color == "@bg")
        let texts = spec.layers.compactMap { layer -> String? in
            if case .text(let text) = layer.content { return text.color }
            return nil
        }
        #expect(texts.contains("@fg"))
        #expect(texts.contains("@muted"))
        #expect(!texts.contains { $0.hasPrefix("#") })
        guard case .shape(let shape) = spec.layers[0].content else {
            Issue.record("first layer should be the accent shape")
            return
        }
        #expect(shape.fill == "@accent")
        #expect(colors["muted"] == "#8A8A8A")
        #expect(colors["bg"] == "#101418")
    }

    @Test func colorsFarFromThePaletteStayHex() {
        var colors = ["bg": "#000000", "fg": "#FFFFFF", "accent": "#E2231A"]
        let value: JSONValue = ["layers": [["type": "shape", "fill": "#2E7D32"]]]
        let result = AIColorTokens.tokenize(value, colors: &colors)
        #expect(result == value)
        #expect(colors["muted"] == nil)
    }

    @Test func mutedIsAnEditableColor() {
        #expect(SavedDesign.editableColors.contains("muted"))
    }
}
