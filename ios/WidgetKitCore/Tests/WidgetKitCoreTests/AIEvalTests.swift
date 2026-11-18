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
        /// Catalog ids this design must end up with (ADR-027); "a|b" takes either. "clock" is an analog clock.
        let wiring: [String]?
    }

    /// One case's outcome, for the comparison table.
    struct Outcome {
        let ok: Bool
        let seconds: Int
        let attempts: Int
        let layout: LayoutRepair?
        var modelScore: Double?
        var finalScore: Double?
        /// The four product rules on this case (ADR-028).
        var rules: [String: Double]?
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
            .filter { item in
                guard let only, !only.isEmpty, only != [""] else { return true }
                return only.contains(item.file) || only.contains { $0.hasSuffix("*") && item.file.hasPrefix($0.dropLast()) }
            }
        let structured = environment["AI_EVAL_STRUCTURED"] != "0"

        // The provider's own model list confirms the IDs.
        let listed = (try? await kind.makeProvider(apiKey: key).listModels()) ?? []
        var summary = ["# AI eval", "", "Provider: \(kind.displayName) · prompt `\(WidgetPrompt.version)` · review: \(review ? "on" : "off") "
            + "· structured: \(structured) · \(cases.count) cases", ""]
        var table = ["| Model | Listed | Widgets | Median s | Answers | Fixed locally | Needs editing |", "|---|---|---|---|---|---|---|"]
        var details: [String] = []

        // ADR-024: "off" sends the whole image, "on" crops to each detected widget (all of them,
        // up to four, like Create all), "both" runs the two for comparison.
        let crop = environment["AI_EVAL_CROP"] ?? "off"
        let modes = crop == "both" ? ["off", "on"] : [crop == "on" ? "on" : "off"]

        for model in models {
            for mode in modes {
                let folder = output.appendingPathComponent(Self.slug(model)).appendingPathComponent("crop-" + mode)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let keys = AIKeyStore(storage: MemoryKeyStorage())
                try keys.save(key, for: kind)
                let defaults = testDefaults()
                AISettings(provider: kind, models: [kind.rawValue: model]).save(to: defaults)
                let service = AIService(keyStore: keys, defaults: defaults)
                service.structuredFirst = structured
                let generator = WidgetGenerator(service: service)
                var outcomes: [Outcome] = []
                var scores: [String: Double] = [:]
                details += ["# `\(model)` · crop \(mode)", ""]

                for item in cases {
                    let name = (item.file as NSString).deletingPathExtension
                    details.append("## \(name)")
                    if let note = item.note { details.append("_\(note)_") }
                    guard let data = try? Data(contentsOf: input.appendingPathComponent(item.file)),
                          let original = AIImage.upright(data: data, maxSide: 1024), let whole = AIImage.prepare(data: data) else {
                        details += ["- could not read the image", ""]
                        continue
                    }
                    var base = GenerationOptions(mode: GenerationMode(rawValue: item.mode) ?? .recreate, size: SizeChoice(rawValue: item.size) ?? .auto)
                    base.wallpaperColor = WidgetDetector.wallpaperColor(original, around: .null)   // like the app
                    var targets = [EvalTarget(image: original, prepared: whole, options: base, suffix: "")]
                    if mode == "on", base.mode == .recreate {
                        let found = Array(WidgetDetector.detect(original).prefix(4))
                        if let outlined = WidgetDetectorTests.outlined(original, found) {
                            try png(outlined).write(to: folder.appendingPathComponent("\(name).detect.png"))
                        }
                        let listedShapes = found.map { "\($0.shape.rawValue) \(Int($0.rect.width))×\(Int($0.rect.height))" }
                        details.append("- detected: " + (found.isEmpty ? "nothing (whole image)" : listedShapes.joined(separator: ", ")))
                        let crops = found.enumerated().compactMap { index, widget in
                            Self.target(original, widget, base: base, suffix: found.count > 1 ? ".\(index + 1)" : "")
                        }
                        if !crops.isEmpty { targets = crops }
                    }
                    for target in targets {
                        let outcome = await run(generator, target: target, review: review, folder: folder, name: name + target.suffix,
                                                defaults: defaults, details: &details, wiring: item.wiring)
                        if let score = outcome.finalScore { scores[name] = score }
                        outcomes.append(outcome)
                        // Free keys allow few requests per minute.
                        try await Task.sleep(nanoseconds: UInt64((Double(environment["AI_EVAL_PAUSE"] ?? "") ?? 8) * 1_000_000_000))
                    }
                    details.append("")
                }
                try gate(scores, model: model, folder: folder, table: &table, outcomes: outcomes)
                let label = model + (modes.count > 1 || mode == "on" ? " · crop \(mode)" : "")
                table.append(Self.row(model: label, listed: listed.isEmpty ? nil : listed.contains(model), outcomes: outcomes))
                // Write as we go, so a cancelled run still leaves the finished models.
                try (summary + table + [""] + details).joined(separator: "\n")
                    .write(to: output.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
            }
        }

        let similar = listed.filter { id in models.compactMap(Self.stem).contains { id.lowercased().contains($0) } }
        summary += table + ["", "Listed by the provider (IDs like the requested ones): "
            + (listed.isEmpty ? "no model list" : similar.map { "`\($0)`" }.joined(separator: ", ")), ""] + details
        try summary.joined(separator: "\n").write(to: output.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
    }

    /// The wiring score of a run (ADR-027): the mean over the interactive cases, written to
    /// `wiring.json`. With `AI_EVAL_GATE=1` a score under the best run fails the workflow.
    func gate(_ scores: [String: Double], model: String, folder: URL, table: inout [String], outcomes: [Outcome]) throws {
        guard !scores.isEmpty else { return }
        let final = scores.values.reduce(0, +) / Double(scores.count)
        let modelScores = outcomes.compactMap(\.modelScore)
        let raw = modelScores.isEmpty ? 0 : modelScores.reduce(0, +) / Double(modelScores.count)
        table.append("")
        table.append("**Wiring \(model):** \(Self.percent(final)) with the post-pass, \(Self.percent(raw)) from the model alone, \(scores.count) cases")
        let metrics = WiringGateTests.means(outcomes.compactMap(\.rules))
        table.append("**Rules \(model):** " + DesignRules.Rule.allCases.map { "\($0.rawValue) \(Self.percent(metrics[$0.rawValue] ?? 0))" }.joined(separator: " · "))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let report = WiringBest(score: final, model: model, prompt: WidgetPrompt.version, cases: scores, metrics: metrics)
        try encoder.encode(report).write(to: folder.appendingPathComponent("wiring.json"))
        if environment["AI_EVAL_GATE"] == "1", let best = WiringGateTests.best(), final + 0.0001 < best.score {
            Issue.record("Wiring score \(Self.percent(final)) is below the best run \(Self.percent(best.score))")
        }
        if environment["AI_EVAL_GATE"] == "1", let best = WiringGateTests.best()?.metrics {
            for (rule, floor) in best where (metrics[rule] ?? 0) + 0.0001 < floor {
                Issue.record("\(rule) \(Self.percent(metrics[rule] ?? 0)) is below the best run \(Self.percent(floor))")
            }
        }
    }

    static func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }

    /// The 10 widgets of a set before and after (ADR-027): each JSON as it was, through the
    /// post-pass, and through prompt v5 from a render of the old design. `AI_EVAL_SET` is a folder
    /// outside the repo; the set isn't committed.
    @Test @MainActor func setBeforeAndAfter() async throws {
        guard let folderPath = environment["AI_EVAL_SET"], !folderPath.isEmpty else { return }
        let input = URL(fileURLWithPath: folderPath)
        let output = URL(fileURLWithPath: environment["AI_EVAL_OUT"] ?? NSTemporaryDirectory() + "ai-eval").appendingPathComponent("set")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if let fonts = environment["AI_EVAL_FONTS"] { registerFonts(in: URL(fileURLWithPath: fonts)) }
        let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        func wired(_ spec: WidgetSpec) -> (live: Int, taps: Int, ids: [String]) {
            let ids = WiringScore.ids(in: spec).filter { !$0.hasPrefix("field.") && $0 != "open.app" }
            let taps = ids.filter { Capabilities.action($0) != nil }.count
            return (ids.count - taps, taps, ids.sorted())
        }
        var generator: WidgetGenerator?
        let kind = AIProviderKind(rawValue: environment["AI_EVAL_PROVIDER"] ?? "gemini") ?? .gemini
        if environment["AI_EVAL_SET_V5"] == "1", let key = environment["AI_EVAL_KEY"], !key.isEmpty {
            let keys = AIKeyStore(storage: MemoryKeyStorage())
            try keys.save(key, for: kind)
            let defaults = testDefaults()
            let model = (environment["AI_EVAL_MODEL"] ?? "").split(separator: ",").first.map(String.init) ?? kind.recommendedModel
            AISettings(provider: kind, models: [kind.rawValue: model]).save(to: defaults)
            generator = WidgetGenerator(service: AIService(keyStore: keys, defaults: defaults))
        }
        var lines = ["# The set, before and after", "", "| Widget | Before (live / taps) | Post-pass | Prompt v5 + post-pass | Post-pass changed |", "|---|---|---|---|---|"]
        var detail: [String] = []
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let text = try String(contentsOf: file, encoding: .utf8)
            let options = GenerationOptions()
            do {
                let before = try AIWidgetParser.parseWidget(text, options: options, id: "set.\(name)", enforceLayout: false, autoWire: false)
                let after = try AIWidgetParser.parseWidget(text, options: options, id: "set.\(name)", enforceLayout: false)
                let (was, now) = (wired(before.spec), wired(after.spec))
                var images = [SpecSnapshot.render(before.spec, colors: before.colors), SpecSnapshot.render(after.spec, colors: after.colors)].compactMap { $0 }
                var third = "not run"
                if let generator, let render = images.first, let prepared = AIImage.prepare(image: render) {
                    var v5Options = GenerationOptions(size: SizeChoice(rawValue: before.spec.family.rawValue) ?? .auto)
                    v5Options.cropped = true
                    do {
                        let result = try await generator.generate(image: prepared, options: v5Options)
                        let v5 = wired(result.spec)
                        third = "\(v5.live) / \(v5.taps)"
                        if let image = SpecSnapshot.render(result.spec, colors: result.colors) { images.append(image) }
                        detail.append("- \(name) v5: \(v5.ids.joined(separator: ", "))")
                        try result.reply.write(to: output.appendingPathComponent("\(name).v5.reply.json"), atomically: true, encoding: .utf8)
                    } catch {
                        third = "failed"
                        detail.append("- \(name) v5 failed: \(error)")
                    }
                    try await Task.sleep(nanoseconds: UInt64((Double(environment["AI_EVAL_PAUSE"] ?? "") ?? 8) * 1_000_000_000))
                }
                lines.append("| \(name) | \(was.live) / \(was.taps) | \(now.live) / \(now.taps) | \(third) | \(after.autoWired.count) |")
                detail.append("- \(name) before: \(was.ids.joined(separator: ", "))")
                detail.append("- \(name) post-pass: \(now.ids.joined(separator: ", "))")
                detail += after.autoWired.map { "  - \($0)" }
                if let combined = sideBySide(images) { try png(combined).write(to: output.appendingPathComponent("\(name).png")) }
            } catch {
                lines.append("| \(name) | failed | | | |")
                detail.append("- \(name) failed: \(error)")
            }
        }
        try (lines + [""] + detail).joined(separator: "\n").write(to: output.appendingPathComponent("set.md"), atomically: true, encoding: .utf8)
    }

    /// One image sent to the model: the whole picture, or one detected widget's crop (ADR-024).
    struct EvalTarget {
        let image: CGImage
        let prepared: PreparedImage
        let options: GenerationOptions
        let suffix: String
    }

    static func target(_ original: CGImage, _ widget: DetectedWidget, base: GenerationOptions, suffix: String) -> EvalTarget? {
        guard let image = WidgetDetector.crop(original, to: widget.rect), let prepared = AIImage.prepare(image: image) else { return nil }
        var options = base
        if options.size == .auto { options.size = widget.suggestedSize(imageWidth: original.width) }
        options.detectedCard = widget.shape
        options.cropped = true
        options.wallpaperColor = WidgetDetector.wallpaperColor(original, around: widget.rect)
        return EvalTarget(image: image, prepared: prepared, options: options, suffix: suffix)
    }

    /// Generates, renders and records one target; failures go to the summary.
    @MainActor
    func run(_ generator: WidgetGenerator, target: EvalTarget, review: Bool, folder: URL, name: String,
             defaults: UserDefaults, details: inout [String], wiring: [String]? = nil) async -> Outcome {
        let photo = target.options.mode == .photo ? target.image : nil
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
            let result = try await generator.generate(image: target.prepared, options: target.options, review: renderer)
            let seconds = Int(Date().timeIntervalSince(started))
            let spec = result.spec
            if let rendered = SpecSnapshot.render(spec, colors: result.colors, userImage: photo),
               let combined = sideBySide([target.image, rendered]) {
                try png(combined).write(to: folder.appendingPathComponent("\(name).png"))
                // ADR-022: the model's own layout next to the local fix.
                if case .fixed(let before) = result.layout,
                   let raw = SpecSnapshot.render(before, colors: result.colors, userImage: photo),
                   let triple = sideBySide([target.image, raw, rendered]) {
                    try png(triple).write(to: folder.appendingPathComponent("\(name).fix.png"))
                }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(spec).write(to: folder.appendingPathComponent("\(name).json"))
            let card = spec.background.outerColor == nil ? (spec.background.type == .glass ? "glass" : "card")
                : (spec.background.cardShape?.rawValue ?? "circle")
            details.append("- \(name): \(spec.family.rawValue), \(card), \(spec.layers.count) layers, \(result.attempts) answer(s), "
                + "\(seconds) s, reviewed: \(result.reviewed), layout: \(Self.describe(result.layout))")
            details.append("- layers: " + spec.layers.map(\.content.typeName).joined(separator: ", "))
            for difference in result.differences { details.append("  - fixed: \(difference)") }
            var outcome = Outcome(ok: true, seconds: seconds, attempts: result.attempts, layout: result.layout)
            if let wiring {
                try result.reply.write(to: folder.appendingPathComponent("\(name).reply.json"), atomically: true, encoding: .utf8)
                let raw = try? AIWidgetParser.parseWidget(result.reply, options: target.options, id: "eval", enforceLayout: false, autoWire: false)
                outcome.modelScore = raw.map { WiringScore.score($0.spec, expected: wiring) }
                outcome.finalScore = WiringScore.score(spec, expected: wiring)
                outcome.rules = DesignRules.check(spec).scores
                for finding in DesignRules.check(spec).findings { details.append("  - rule \(finding.rule.rawValue): \(finding.element)") }
                let missing = wiring.filter { !WiringScore.hits(spec, expected: [$0]).contains($0) }
                details.append("- wiring: \(Self.percent(outcome.finalScore ?? 0)) (model \(Self.percent(outcome.modelScore ?? 0))), missing: "
                    + (missing.isEmpty ? "nothing" : missing.joined(separator: ", ")))
                for change in result.autoWired { details.append("  - \(change)") }
            }
            return outcome
        } catch {
            details.append("- \(name) FAILED: \(error)")
            if let diagnostic = AIDiagnosticsStore.load(from: defaults) {
                details += ["```", diagnostic.report(), "```"]
            }
            return Outcome(ok: false, seconds: Int(Date().timeIntervalSince(started)), attempts: 0, layout: nil, modelScore: nil, finalScore: nil)
        }
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
