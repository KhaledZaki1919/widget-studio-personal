import Foundation
import Testing
@testable import WidgetKitCore

/// M6.1 item 3: `stack` (vertical, horizontal, grid) and `spacer` layers.
struct StackTests {
    func spec(layers: String, family: String = "small") -> Data {
        Data("""
        {"schemaVersion": 1, "id": "test.stack", "name": {"en": "S", "ar": "س"}, "family": "\(family)", "theme": "dark",
         "background": {"type": "solid", "color": "#000000"}, "layers": [\(layers)]}
        """.utf8)
    }

    let text = ##"{"type": "text", "value": {"en": "Hi", "ar": "أهلا"}, "font": {"family": "system", "size": 13}, "color": "#FFFFFF"}"##

    func issues(_ layers: String, mode: SpecValidator.Mode = .standard) -> [String] {
        switch SpecValidator(mode: mode).validate(data: spec(layers: layers)) {
        case .success: return []
        case .failure(let failure): return failure.issues.map(\.description)
        }
    }

    @Test func decodesChildrenWithoutFramesAndRoundTrips() throws {
        let json = """
        {"type": "stack", "axis": "vertical", "spacing": 6, "alignItems": "center", "frame": {"x": 10, "y": 10, "w": 150, "h": 150},
         "children": [\(text), {"type": "spacer", "minLength": 4}, {"type": "shape", "kind": "rect", "fill": "#FFFFFF", "height": 1}]}
        """
        let decoded = try JSONDecoder().decode(WidgetSpec.self, from: spec(layers: json))
        guard case .stack(let stack) = decoded.layers[0].content else {
            Issue.record("not a stack")
            return
        }
        #expect(stack.axis == .vertical && stack.alignItems == .center && stack.children.count == 3)
        #expect(stack.children[2].frame == Frame(x: 0, y: 0, w: 0, h: 1))
        let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        #expect(encoded.contains(#""height":1"#))
        #expect(encoded.components(separatedBy: #""frame""#).count == 2, "only the stack has a frame")
        #expect(try JSONDecoder().decode(WidgetSpec.self, from: Data(encoded.utf8)) == decoded)
        #expect(decoded.allLayers.count == 4)
    }

    @Test func validStacksPass() {
        #expect(TestSpecs.spec(id: "test.stacks") != nil)
        let grid = """
        {"type": "stack", "axis": "grid", "columns": 2, "frame": {"x": 0, "y": 0, "w": 170, "h": 170}, "children": [\(text), \(text), \(text)]}
        """
        #expect(issues(grid).isEmpty)
    }

    @Test func stackRules() {
        let spacerOnTop = #"{"type": "spacer", "frame": {"x": 0, "y": 0, "w": 10, "h": 10}}"#
        #expect(issues(spacerOnTop).contains { $0.contains("only goes inside") })

        let shapeWithoutHeight = """
        {"type": "stack", "axis": "vertical", "frame": {"x": 0, "y": 0, "w": 170, "h": 170},
         "children": [{"type": "shape", "kind": "rect", "fill": "#FFFFFF"}]}
        """
        #expect(issues(shapeWithoutHeight).contains { $0.contains("needs a height") })

        let spacerInGrid = """
        {"type": "stack", "axis": "grid", "frame": {"x": 0, "y": 0, "w": 170, "h": 170}, "children": [\(text), {"type": "spacer"}]}
        """
        #expect(issues(spacerInGrid).contains { $0.contains("can't hold spacers") })

        let listInStack = """
        {"type": "stack", "axis": "vertical", "frame": {"x": 0, "y": 0, "w": 170, "h": 170},
         "children": [{"type": "forecastRow", "days": 3, "color": "#FFFFFF"}]}
        """
        #expect(issues(listInStack).contains { $0.contains("can't go in a stack") })

        let empty = #"{"type": "stack", "axis": "horizontal", "frame": {"x": 0, "y": 0, "w": 170, "h": 170}, "children": []}"#
        #expect(!issues(empty).isEmpty)

        var nested = text
        for _ in 0..<3 { nested = #"{"type": "stack", "axis": "vertical", "children": ["# + nested + "]}" }
        let deep = #"{"type": "stack", "axis": "vertical", "frame": {"x": 0, "y": 0, "w": 170, "h": 170}, "children": ["# + nested + "]}"
        #expect(issues(deep).contains { $0.contains("nest at most") })
    }

    @Test func aiRejectsOverlappingText() {
        func placed(_ x: Int, _ y: Int) -> String {
            text.replacingOccurrences(of: ##""color": "#FFFFFF"}"##, with: ##""color": "#FFFFFF", "frame": {"x": \##(x), "y": \##(y), "w": 100, "h": 30}}"##)
        }
        #expect(issues(placed(10, 10) + "," + placed(20, 15), mode: .ai).contains { $0.contains("overlaps") })
        #expect(issues(placed(10, 10) + "," + placed(10, 60), mode: .ai).isEmpty)
        // Templates may layer texts (e.g. a shadow); only AI output is held to it.
        #expect(issues(placed(10, 10) + "," + placed(20, 15)).isEmpty)
    }

    @Test func bindingsAndTokensInsideStacks() throws {
        let json = """
        {"type": "stack", "axis": "horizontal", "frame": {"x": 0, "y": 0, "w": 170, "h": 40},
         "children": [{"type": "text", "value": "{{weather.temp}}°", "font": {"family": "system", "size": 13}, "color": "@accent"}]}
        """
        let decoded = try JSONDecoder().decode(WidgetSpec.self, from: spec(layers: json))
        #expect(DataRequirements.groups(for: decoded).contains(.weather))
        let resolved = decoded.resolvingTokens(overrides: ["accent": "#123456"])
        guard case .stack(let stack) = resolved.layers[0].content, case .text(let child) = stack.children[0].content else {
            Issue.record("structure changed")
            return
        }
        #expect(child.color == "#123456")
    }

    @Test func gridRows() {
        let stack = StackLayer(axis: .grid, columns: 2, children: Array(repeating: Layer(frame: Frame(x: 0, y: 0, w: 0, h: 0),
                                                                                          content: .spacer(SpacerLayer())), count: 5))
        #expect(stack.rows.map(\.count) == [2, 2, 1])
    }

    func typeOf(_ shape: JSONValue) -> String? {
        guard case .array(let values)? = shape["properties"]?["type"]?["enum"] else { return nil }
        return values.first?.stringValue
    }

    /// Prompt v3: stacks at the top level with texts inside; no top-level text shape.
    @Test func aiSchemaPutsTextInStacks() {
        func types(_ shapes: JSONValue?) -> [String] {
            guard case .array(let list)? = shapes else { return [] }
            return list.compactMap { typeOf($0) }
        }
        let top = AIWidgetSchema.schema(mode: .recreate)["properties"]?["layers"]?["items"]?["anyOf"]
        #expect(types(top).contains("stack") && !types(top).contains("text"))
        guard case .array(let list)? = top, let stack = list.first(where: { typeOf($0) == "stack" }) else {
            Issue.record("no stack shape")
            return
        }
        let children = stack["properties"]?["children"]?["items"]?["anyOf"]
        #expect(Set(types(children)) == ["text", "icon", "shape", "ring", "progressBar", "spacer", "stack"])
        guard case .array(let childList)? = children,
              let nested = childList.first(where: { typeOf($0) == "stack" }) else { return }
        let nestedTypes = types(nested["properties"]?["children"]?["items"]?["anyOf"])
        #expect(!nestedTypes.contains("stack"))
    }

    @Test func aiReplyWithStacksParses() throws {
        let reply = """
        {"inventory": ["header"], "name": {"en": "Weather", "ar": "الطقس"}, "family": "small", "theme": "dark",
         "palette": {"bg": "#101418", "fg": "#F5F5F5", "accent": "#FF5A36"},
         "background": {"type": "solid", "color": "@bg", "colors": null, "angle": null, "outerColor": null}, "fields": [],
         "layers": [{"type": "stack", "frame": {"x": 12, "y": 12, "w": 146, "h": 146}, "opacity": null, "mirror": true,
           "axis": "vertical", "spacing": 6, "padding": null, "alignItems": "start", "justify": null, "columns": null,
           "children": [
             {"type": "stack", "width": null, "height": null, "axis": "horizontal", "spacing": null, "padding": null, "alignItems": null,
              "justify": null, "columns": null, "children": [
                {"type": "text", "width": null, "height": null, "value": {"en": "{{weather.city}}", "ar": "{{weather.city}}"},
                 "font": {"family": "system", "size": 13, "weight": "semibold"}, "color": "@fg", "align": null, "maxLines": null, "live": null},
                {"type": "spacer", "width": null, "height": null, "minLength": null},
                {"type": "icon", "width": null, "height": null, "symbol": "{{weather.symbol}}", "size": 16, "color": "@accent"}]},
             {"type": "text", "width": null, "height": null, "value": {"en": "{{weather.temp}}°", "ar": "{{weather.temp}}°"},
              "font": {"family": "system-rounded", "size": 44, "weight": "bold"}, "color": "@fg", "align": null, "maxLines": null, "live": null},
             {"type": "shape", "width": null, "height": 1, "kind": "rect", "fill": "@line", "stroke": null, "cornerRadius": null}]}]}
        """
        let (spec, _) = try AIWidgetParser.parse(reply, options: GenerationOptions(), id: "gen.stack")
        #expect(spec.allLayers.count == 7)
        #expect(spec.refresh == .hourly)
    }
}
