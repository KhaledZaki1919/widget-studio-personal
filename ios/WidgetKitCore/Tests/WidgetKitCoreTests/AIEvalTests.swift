import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WidgetKitCore

/// The AI eval (ADR-019), run only by the `ai-eval` workflow (`AI_EVAL=1`) with the repository
/// secret for the chosen provider (`AI_EVAL_PROVIDER`, key in `AI_EVAL_KEY`): for every case in `docs/ai-eval/cases.json`, generate a spec with the
/// app's real prompt, schema and parser, render it with the real renderer, and write a
/// side-by-side PNG (original | render), the spec and a summary. `AI_EVAL_MODEL` may name several
/// models (comma-separated); the summary starts with a table comparing them (ADR-022). When the
/// local layout fix ran, `<case>.fix.png` shows original | the model's layout | the fixed one.
/// Never prints the key; a failed case is written to the summary, not thrown, so one bad case
/// doesn't hide the others.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["AI_EVAL"] == "1"))
struct AIEvalTests {
    struct Case: Decodable {
        let file: String
        let mode: String
        let size: String
        let note: String?
    }

    /// One case's outcome, for the comparison table.
    struct Outcome {
        let ok: Bool
        let seconds: Int
        let attempts: Int
        let layout: LayoutRepair?
    }

    let environment = ProcessInfo.processInfo.environment

    @Test @MainActor func generateAndRenderEveryCase() async throws {
        let kind = AIProviderKind(rawValue: environment["AI_EVAL_PROVIDER"] ?? "gemini") ?? .gemini
        let key = try #require((environment["AI_EVAL_KEY"] ?? environment["GEMINI_API_KEY"]).flatMap { $0.isEmpty ? nil : $0 },
                               "no key for the provider")
        let input = URL(fileURLWithPath: try #require(environment["AI_EVAL_DIR"]))
        let output = URL(fileURLWithPath: environment["AI_EVAL_OUT"] ?? NSTemporaryDirectory() + "ai-eval")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if let fonts = environment["AI_EVAL_FONTS"] { registerFonts(in: URL(fileURLWithPath: fonts)) }

        let requested = (environment["AI_EVAL_MODEL"] ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let models = requested.isEmpty ? [kind.recommendedModel] : requested
        let review = environment["AI_EVAL_REVIEW"] == "1"
        let only = environment["AI_EVAL_CASES"].map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: input.appendingPathComponent("cases.json")))
            .filter { item in only.map { $0.contains(item.file) || $0.isEmpty } ?? true }
        let structured = environment["AI_EVAL_STRUCTURED"] != "0"

        // The provider's own model list confirms the IDs.
        let listed = (try? await kind.makeProvider(apiKey: key).listModels()) ?? []
        var summary = ["# AI eval", "", "Provider: \(kind.displayName) · prompt `\(WidgetPrompt.version)` · review: \(review ? "on" : "off") "
            + "· structured: \(structured) · \(cases.count) cases", ""]
        var table = ["| Model | Listed | Widgets | Median s | Answers | Fixed locally | Needs editing |", "|---|---|---|---|---|---|---|"]
        var details: [String] = []

        for model in models {
            let folder = output.appendingPathComponent(Self.slug(model))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let keys = AIKeyStore(storage: MemoryKeyStorage())
            try keys.save(key, for: kind)
            let defaults = testDefaults()
            AISettings(provider: kind, models: [kind.rawValue: model]).save(to: defaults)
            let service = AIService(keyStore: keys, defaults: defaults)
            service.structuredFirst = structured
            let generator = WidgetGenerator(service: service)
            var outcomes: [Outcome] = []
            details += ["# `\(model)`", ""]

            for item in cases {
                let name = (item.file as NSString).deletingPathExtension
                details.append("## \(name)")
                if let note = item.note { details.append("_\(note)_") }
                guard let data = try? Data(contentsOf: input.appendingPathComponent(item.file)),
                      let original = AIImage.upright(data: data, maxSide: 1024), let prepared = AIImage.prepare(data: data) else {
                    details += ["- could not read the image", ""]
                    continue
                }
                let options = GenerationOptions(mode: GenerationMode(rawValue: item.mode) ?? .recreate, size: SizeChoice(rawValue: item.size) ?? .auto)
                let photo = options.mode == .photo ? original : nil
                var renderer: SpecRenderer?
                if review {
                    renderer = { spec, colors in
                        await MainActor.run { () -> PreparedImage? in
                            guard let image = SpecSnapshot.render(spec, colors: colors, userImage: photo) else { return nil }
                            return AIImage.prepare(image: image)
                        }
                    }
                }
                let started = Date()
                do {
                    let result = try await generator.generate(image: prepared, options: options, review: renderer)
                    let seconds = Int(Date().timeIntervalSince(started))
                    let spec = result.spec
                    if let rendered = SpecSnapshot.render(spec, colors: result.colors, userImage: photo),
                       let combined = sideBySide([original, rendered]) {
                        try png(combined).write(to: folder.appendingPathComponent("\(name).png"))
                        // ADR-022: the model's own layout next to the local fix.
                        if case .fixed(let before) = result.layout,
                           let raw = SpecSnapshot.render(before, colors: result.colors, userImage: photo),
                           let triple = sideBySide([original, raw, rendered]) {
                            try png(triple).write(to: folder.appendingPathComponent("\(name).fix.png"))
                        }
                    }
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    try encoder.encode(spec).write(to: folder.appendingPathComponent("\(name).json"))
                    outcomes.append(Outcome(ok: true, seconds: seconds, attempts: result.attempts, layout: result.layout))
                    details.append("- \(result.spec.family.rawValue), \(result.spec.layers.count) layers, "
                        + "\(result.attempts) answer(s), \(seconds) s, reviewed: \(result.reviewed), layout: \(Self.describe(result.layout))")
                    details.append("- layers: " + result.spec.layers.map(\.content.typeName).joined(separator: ", "))
                    for difference in result.differences { details.append("  - fixed: \(difference)") }
                } catch {
                    outcomes.append(Outcome(ok: false, seconds: Int(Date().timeIntervalSince(started)), attempts: 0, layout: nil))
                    details.append("- FAILED: \(error)")
                    if let diagnostic = AIDiagnosticsStore.load(from: defaults) {
                        details += ["```", diagnostic.report(), "```"]
                    }
                }
                details.append("")
                // Free keys allow few requests per minute.
                try await Task.sleep(nanoseconds: UInt64((Double(environment["AI_EVAL_PAUSE"] ?? "") ?? 8) * 1_000_000_000))
            }
            table.append(Self.row(model: model, listed: listed.isEmpty ? nil : listed.contains(model), outcomes: outcomes))
            // Write as we go, so a cancelled run still leaves the finished models.
            try (summary + table + [""] + details).joined(separator: "\n")
                .write(to: output.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
        }

        let similar = listed.filter { id in models.compactMap(Self.stem).contains { id.lowercased().contains($0) } }
        summary += table + ["", "Listed by the provider (IDs like the requested ones): "
            + (listed.isEmpty ? "no model list" : similar.map { "`\($0)`" }.joined(separator: ", ")), ""] + details
        try summary.joined(separator: "\n").write(to: output.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
    }

    static func row(model: String, listed: Bool?, outcomes: [Outcome]) -> String {
        let done = outcomes.filter(\.ok)
        let seconds = done.map(\.seconds).sorted()
        let median = seconds.isEmpty ? "–" : String(seconds[seconds.count / 2])
        let answers = done.isEmpty ? "–" : String(format: "%.1f", Double(done.map(\.attempts).reduce(0, +)) / Double(done.count))
        let fixed = done.filter { if case .fixed = $0.layout { true } else { false } }.count
        let editing = done.filter { if case .needsEditing = $0.layout { true } else { false } }.count
        let listedText = listed.map { $0 ? "yes" : "**no**" } ?? "?"
        return "| `\(model)` | \(listedText) | \(done.count)/\(outcomes.count) | \(median) | \(answers) | \(fixed) | \(editing) |"
    }

    static func describe(_ layout: LayoutRepair) -> String {
        switch layout {
        case .clean: "clean"
        case .fixed: "fixed locally"
        case .needsEditing(let problems): "needs editing (" + problems.joined(separator: "; ") + ")"
        }
    }

    /// "meta/llama-4-maverick-17b-128e-instruct" → "meta_llama-4-maverick-17b-128e-instruct".
    static func slug(_ model: String) -> String {
        String(model.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" })
    }

    /// The family part of an ID ("gemma-3-27b"), to show near matches from the provider's list.
    static func stem(_ model: String) -> String? {
        let name = (model.split(separator: "/").last.map(String.init) ?? model).lowercased().replacingOccurrences(of: ":free", with: "")
        let parts = name.split(separator: "-").prefix(3)
        return parts.isEmpty ? nil : parts.joined(separator: "-")
    }

    /// Bundled fonts by file, so renders match the app (the eval process has no UIAppFonts).
    func registerFonts(in folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    /// Images left to right (original | render, or original | model's layout | fixed layout) at
    /// the same height on a light gray sheet.
    func sideBySide(_ images: [CGImage], height: CGFloat = 510, padding: CGFloat = 30) -> CGImage? {
        func width(_ image: CGImage) -> CGFloat { CGFloat(image.width) * height / CGFloat(max(image.height, 1)) }
        let size = CGSize(width: images.map(width).reduce(0, +) + padding * CGFloat(images.count + 1), height: height + padding * 2)
        return ImageProcessing.draw(size: size) { context in
            context.setFillColor(CGColor(red: 0.9, green: 0.91, blue: 0.93, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.interpolationQuality = .high
            var x = padding
            for image in images {
                context.draw(image, in: CGRect(x: x, y: padding, width: width(image), height: height))
                x += width(image) + padding
            }
        }
    }

    func png(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw AIValidationError("no PNG encoder")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AIValidationError("PNG encoding failed") }
        return output as Data
    }
}
