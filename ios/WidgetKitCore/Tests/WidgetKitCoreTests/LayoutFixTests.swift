import Foundation
import Testing
@testable import WidgetKitCore

/// M6.1, ADR-022: the local layout fix for the last AI answer and the layer editor's operations.
struct LayoutFixTests {
    func text(_ en: String, _ frame: Frame, align: TextAlign? = nil) -> Layer {
        Layer(frame: frame, content: .text(TextLayer(value: .localized(en: en, ar: en), font: FontSpec(family: "system", size: 14),
                                                     color: "@fg", align: align)))
    }

    func shape(_ frame: Frame) -> Layer {
        Layer(frame: frame, content: .shape(ShapeLayer(kind: .roundedRect, fill: "@accent")))
    }

    func spec(_ layers: [Layer]) throws -> WidgetSpec {
        let json = """
        {"schemaVersion": 1, "id": "test.layout", "name": {"en": "L", "ar": "ل"}, "family": "small", "theme": "dark",
         "background": {"type": "solid", "color": "@bg"}, "layers": []}
        """
        var spec = try JSONDecoder().decode(WidgetSpec.self, from: Data(json.utf8))
        spec.layers = layers
        return spec
    }

    @Test func overlappingTextsBecomeOneColumn() throws {
        let original = try spec([
            shape(Frame(x: 0, y: 0, w: 170, h: 170)),
            text("Title", Frame(x: 12, y: 20, w: 146, h: 30), align: .center),
            text("Subtitle", Frame(x: 12, y: 36, w: 146, h: 30), align: .center),
            text("Footer", Frame(x: 12, y: 130, w: 146, h: 24)),
        ])
        #expect(SpecLayout.textOverlaps(in: original.layers).count == 1)
        let fixed = AILayoutFix.fix(original)
        #expect(SpecLayout.textOverlaps(in: fixed.layers).isEmpty)
        #expect(fixed.layers.count == 3)
        guard case .stack(let stack) = fixed.layers[1].content else {
            Issue.record("expected a stack where the texts were")
            return
        }
        #expect(stack.axis == .vertical && stack.alignItems == .center && stack.children.count == 2)
        #expect(fixed.layers[1].frame == Frame(x: 12, y: 20, w: 146, h: 46))
        // Texts keep their natural size inside the stack.
        #expect(stack.children.allSatisfy { $0.frame.w == 0 && $0.frame.h == 0 })
        #expect(SpecValidator(mode: .ai).validate(fixed).isSuccess)
    }

    @Test func sideBySideTextsBecomeARow() throws {
        let original = try spec([
            text("12", Frame(x: 10, y: 60, w: 80, h: 40)),
            text("°C", Frame(x: 70, y: 62, w: 80, h: 40)),
        ])
        let fixed = AILayoutFix.fix(original)
        guard case .stack(let stack) = fixed.layers[0].content else {
            Issue.record("expected a stack")
            return
        }
        #expect(stack.axis == .horizontal)
        #expect(stack.children.map { $0.content.typeName } == ["text", "text"])
    }

    @Test func layersAStackCantHoldAreMovedApart() throws {
        let list = Layer(frame: Frame(x: 10, y: 10, w: 150, h: 100), content: .list(ListLayer(
            items: [ListLayer.Item(title: .localized(en: "One", ar: "واحد"))], font: FontSpec(family: "system", size: 13), color: "@fg")))
        let original = try spec([list, text("Overlay", Frame(x: 10, y: 60, w: 150, h: 60))])
        let fixed = AILayoutFix.fix(original)
        #expect(fixed.layers.count == 2)
        #expect(SpecLayout.textOverlaps(in: fixed.layers).isEmpty)
        #expect(fixed.layers[0].frame.y + fixed.layers[0].frame.h <= fixed.layers[1].frame.y)
    }

    /// Eval 2026-11-01: a list taller than the widget is clamped up under the header; the overlap
    /// check sees the clamped frames, so the retry (and then the local fix) handles it.
    @Test func overlapsAreCheckedOnClampedFrames() throws {
        let list = Layer(frame: Frame(x: 10, y: 60, w: 150, h: 170), content: .list(ListLayer(
            items: [ListLayer.Item(title: .localized(en: "Gym", ar: "النادي"))], font: FontSpec(family: "system", size: 13), color: "@fg")))
        let original = try spec([text("Today", Frame(x: 10, y: 10, w: 150, h: 30)), list])
        guard case .failure(let failure) = SpecValidator(mode: .ai).validate(original) else {
            Issue.record("the clamped list covers the header")
            return
        }
        #expect(failure.issues.contains { $0.message.contains("overlaps") })
        guard case .success(let clamped) = SpecValidator(mode: .ai, checksTextOverlaps: false).validate(original) else {
            Issue.record("valid apart from the overlap")
            return
        }
        let fixed = AILayoutFix.fix(clamped)
        #expect(SpecLayout.textOverlaps(in: fixed.layers).isEmpty)
        // The header stays above the list (ordered by center, not by the clamped top).
        #expect(fixed.layers[0].frame.y < fixed.layers[1].frame.y)
    }

    @Test func layoutRepairIsReported() throws {
        let empty = try spec([])
        #expect(GeneratedWidget(spec: empty, colors: [:], model: "m", attempts: 2,
                                layout: .needsEditing(["layers[1]: its text overlaps layers[0]"])).needsEditing)
        #expect(!GeneratedWidget(spec: empty, colors: [:], model: "m", attempts: 1).needsEditing)
    }

    // MARK: Layer editor

    @Test func pathsReachNestedChildren() throws {
        var layers = AILayoutFix.fix(try spec([
            text("A", Frame(x: 10, y: 10, w: 100, h: 30)),
            text("B", Frame(x: 10, y: 20, w: 100, h: 30)),
        ])).layers
        #expect(LayerEditing.layer(at: [0, 1], in: layers)?.content.typeName == "text")
        var renamed = try #require(LayerEditing.layer(at: [0, 1], in: layers))
        renamed.opacity = 0.5
        LayerEditing.replace(at: [0, 1], in: &layers, with: renamed)
        #expect(LayerEditing.layer(at: [0, 1], in: layers)?.opacity == 0.5)

        LayerEditing.duplicate(at: [0, 0], in: &layers)
        #expect(LayerEditing.layer(at: [0, 2], in: layers)?.opacity == 0.5)
        LayerEditing.move(in: [0], from: [2], to: 0, layers: &layers)
        #expect(LayerEditing.layer(at: [0, 0], in: layers)?.opacity == 0.5)
        LayerEditing.remove(at: [0, 0], in: &layers)
        #expect(LayerEditing.layer(at: [0, 2], in: layers) == nil)
    }

    @Test func groupAndUngroupRoundTrip() throws {
        var layers = try spec([
            shape(Frame(x: 0, y: 0, w: 170, h: 170)),
            text("A", Frame(x: 10, y: 10, w: 100, h: 30)),
            text("B", Frame(x: 10, y: 50, w: 100, h: 30)),
        ]).layers
        let index = try #require(LayerEditing.group([1, 2], in: &layers))
        #expect(index == 1 && layers.count == 2)
        #expect(LayerEditing.group([0, 0], in: &layers) == nil)
        let freed = LayerEditing.ungroup(at: index, in: &layers)
        #expect(freed == [1, 2] && layers.count == 3)
        #expect(SpecLayout.textOverlaps(in: layers).isEmpty)
        // Top-level layers move like List.onMove.
        LayerEditing.move(in: [], from: [0], to: 3, layers: &layers)
        #expect(layers[2].content.typeName == "shape")
    }
}
