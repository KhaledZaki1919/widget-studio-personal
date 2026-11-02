import Foundation
import Testing
@testable import WidgetKitCore

struct TestSpecsTests {
    @Test func allTestSpecsAreValid() {
        let entries = TestSpecs.load()
        #expect(entries.count == 12)
        for entry in entries {
            if case .failure(let failure) = entry.result {
                Issue.record("\(entry.fileName): \(failure.description)")
            }
        }
    }

    @Test func idsAreUnique() {
        let ids = TestSpecs.all().map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func togetherTheyUseEveryLayerTypeFamilyAndTheme() {
        let specs = TestSpecs.all()
        let types = Set(specs.flatMap { $0.allLayers.map(\.content.typeName) })
        #expect(types == Set(LayerContent.knownTypes))
        #expect(Set(specs.map(\.family)) == Set(SpecFamily.allCases))
        #expect(Set(specs.map(\.theme)) == Set(SpecTheme.allCases))
    }

    /// The exported schema lists the same layer types, fonts and actions as the Swift code.
    @Test func schemaMatchesTheSwiftWhitelists() throws {
        let data = try #require(SpecSchema.data())
        let schema = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let defs = try #require(schema["$defs"] as? [String: Any])
        let layer = try #require((defs["layer"] as? [String: Any])?["properties"] as? [String: Any])
        func enumValues(_ property: Any?) -> [String] {
            (property as? [String: Any])?["enum"] as? [String] ?? []
        }
        #expect(enumValues(layer["type"]) == LayerContent.knownTypes)
        #expect(enumValues(layer["action"]) == ButtonLayer.Action.allCases.map(\.rawValue))
        let font = try #require((defs["font"] as? [String: Any])?["properties"] as? [String: Any])
        #expect(enumValues(font["family"]) == FontRegistry.families)
        // ADR-019 layers.
        #expect(enumValues(layer["todayStyle"]) == CalendarMonthLayer.TodayStyle.allCases.map(\.rawValue))
        #expect(enumValues(layer["titleFormat"]) == CalendarMonthLayer.TitleFormat.allCases.map(\.rawValue))
        #expect(enumValues(layer["marker"]) == ListLayer.Marker.allCases.map(\.rawValue))
    }

    @Test func everyBindingResolvesWithSampleData() {
        for spec in TestSpecs.all() {
            let resolver = BindingResolver(spec: spec, context: RenderContext(language: "en", data: .sample()))
            for layer in spec.layers {
                guard case .text(let text) = layer.content, text.live == nil else { continue }
                for value in text.value.allValues {
                    #expect(!resolver.render(value).contains(BindingResolver.missing), "\(spec.id): \(value)")
                }
            }
        }
    }
}
