import Foundation
import Testing
@testable import WidgetKitCore

/// The AI prompt, schemas and import example as files for the Android app (ADR-025): Android
/// reads `Resources/Spec/ai/` instead of rebuilding them. This test fails when the committed files
/// differ from what the Swift code builds, and writes the fresh files to `RENDER_OUT/ai-export/`
/// (CI artifact `package-renders`) to commit.
struct AIExportTests {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Sources/WidgetKitCore/Resources/Spec/ai").standardizedFileURL

    static var expected: [String: String] {
        [
            "system_prompt.md": WidgetPrompt.system,
            "review_prompt.md": WidgetPrompt.review,
            "schema.recreate.json": AIWidgetSchema.schema(mode: .recreate).jsonString(),
            "schema.photo.json": AIWidgetSchema.schema(mode: .photo).jsonString(),
            "external_example.json": ExternalAI.example,
            "schema_reference.md": ExternalAI.schemaReference,
            "schema.many.json": AIWidgetSchema.many(mode: .recreate).jsonString(),
            "version.txt": WidgetPrompt.version,
        ]
    }

    @Test func committedExportMatchesTheSwiftSources() throws {
        var stale: [String] = []
        for (name, content) in Self.expected {
            let committed = try? String(contentsOf: Self.folder.appendingPathComponent(name), encoding: .utf8)
            if committed != content {
                stale.append(name)
                if let out = ProcessInfo.processInfo.environment["RENDER_OUT"] {
                    let url = URL(fileURLWithPath: out).appendingPathComponent("ai-export/\(name)")
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try content.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        }
        #expect(stale.isEmpty, "Resources/Spec/ai is stale: \(stale.sorted()); commit the files from package-renders/ai-export")
    }
}
