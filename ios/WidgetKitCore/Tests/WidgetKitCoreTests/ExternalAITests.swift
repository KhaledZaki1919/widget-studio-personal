import Foundation
import Testing
@testable import WidgetKitCore

/// ADR-023: "Use another AI": self-contained instructions and the JSON import.
struct ExternalAITests {
    @Test func instructionsAreSelfContained() {
        let text = ExternalAI.instructions(options: GenerationOptions())
        #expect(text.contains(WidgetPrompt.system))
        #expect(text.contains("Reply with only the JSON object"))
        // ADR-029: a readable reference of the schema, not the JSON Schema itself.
        #expect(text.contains(ExternalAI.schemaReference) && text.contains("Layer, one of") && !text.contains("\"additionalProperties\""))
        #expect(text.contains("\"specVersion\":2,\"inventory\""))               // the example
        #expect(text.contains("\"card.aspect\""))
        var all = GenerationOptions()
        all.allWidgets = true
        #expect(ExternalAI.instructions(options: all).contains("\"widgets\": [ … ]"))
        #expect(!text.contains("0×0"))
        #expect(ExternalAI.instructions(options: GenerationOptions(size: .medium)).contains("\"family\" must be \"medium\""))
        // Photo mode can't travel to a web chat: the task is always to recreate.
        #expect(!ExternalAI.instructions(options: GenerationOptions(mode: .photo)).contains("user_image\" for the photo"))
    }

    @Test func importsAReplyWithFencesAndProse() throws {
        let reply = "Sure! Here is your widget:\n\n```json\n\(ExternalAI.example)\n```\nEnjoy."
        let widget = try ExternalAI.importWidget(reply)
        #expect(widget.spec.id.hasPrefix("ai."))
        #expect(widget.spec.family == .small)
        #expect(widget.model == "external")
        #expect(try ExternalAI.importWidget(ExternalAI.example, size: .medium).spec.family == .medium)
    }

    @Test func clearErrors() throws {
        #expect(throws: ExternalAI.ImportError.empty) { try ExternalAI.importWidget("  \n ") }
        #expect(throws: ExternalAI.ImportError.noJSON) { try ExternalAI.importWidget("I can't see the image.") }
        #expect(throws: ExternalAI.ImportError.tooLarge) {
            try ExternalAI.importWidget("{" + String(repeating: " ", count: ExternalAI.maxImportBytes) + "}")
        }
        let noPalette = ExternalAI.example.replacingOccurrences(of: "\"palette\":{\"bg\":\"#101418\",\"fg\":\"#F5F5F5\",\"accent\":\"#FF5A36\"},", with: "")
        do {
            _ = try ExternalAI.importWidget(noPalette)
            Issue.record("imported a reply without a palette")
        } catch ExternalAI.ImportError.invalid(let problems) {
            #expect(problems.contains("palette"))
            #expect(ExternalAI.fixRequest(for: .invalid(problems)).contains("- palette"))
        }
        // Code is never accepted: a script is not a widget.
        #expect(throws: ExternalAI.ImportError.self) { try ExternalAI.importWidget("function widget() { return 1 }") }
    }

    @Test func importedLayoutsAreRepaired() throws {
        // Two stacks of text on top of each other: imported, then fixed like the app's own results.
        let overlapping = ExternalAI.example.replacingOccurrences(
            of: "\"layers\":[", with: "\"layers\":[{\"type\":\"stack\",\"axis\":\"vertical\",\"frame\":{\"x\":12,\"y\":50,\"w\":146,\"h\":60},"
                + "\"children\":[{\"type\":\"text\",\"value\":{\"en\":\"Hi\",\"ar\":\"أهلا\"},\"font\":{\"family\":\"system\",\"size\":14},"
                + "\"color\":\"@fg\"}]},")
        let widget = try ExternalAI.importWidget(overlapping)
        #expect(SpecLayout.textOverlaps(in: widget.spec.layers).isEmpty)
        #expect(widget.layout != .clean)
    }
}

/// Eval 2026-11-02: invented shape kinds are mapped instead of failing the widget.
struct ShapeKindAliasTests {
    /// ADR-029: `line` is a shape kind of its own now; unknown kinds still fail.
    @Test func lineStaysALine() throws {
        let reply = ExternalAI.example.replacingOccurrences(
            of: "\"layers\":[", with: "\"layers\":[{\"type\":\"shape\",\"kind\":\"line\",\"fill\":\"@fg\",\"frame\":{\"x\":84,\"y\":10,\"w\":2,\"h\":150}},")
        let widget = try ExternalAI.importWidget(reply)
        guard case .shape(let shape) = widget.spec.layers[0].content else {
            Issue.record("the divider is gone")
            return
        }
        #expect(shape.kind == .line)
        #expect(throws: ExternalAI.ImportError.self) {
            try ExternalAI.importWidget(reply.replacingOccurrences(of: "\"kind\":\"line\"", with: "\"kind\":\"hexagon\""))
        }
    }

    @Test func defaultInsideTheLabelMovesOut() throws {
        let reply = ExternalAI.example.replacingOccurrences(
            of: "\"fields\":[]", with: "\"fields\":[{\"key\":\"greeting\",\"type\":\"text\",\"label\":{\"en\":\"Greeting\","
                + "\"default\":{\"en\":\"hello\",\"ar\":\"أهلا\"},\"ar\":\"التحية\"}}]")
        let field = try #require(try ExternalAI.importWidget(reply).spec.fields.first)
        #expect(field.default?.resolved(language: "en") == "hello")
        #expect(field.label.resolved(language: "ar") == "التحية")
    }
}
