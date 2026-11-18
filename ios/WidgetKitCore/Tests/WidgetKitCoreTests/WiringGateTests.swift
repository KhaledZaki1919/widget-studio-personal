import Foundation
import Testing
@testable import WidgetKitCore

/// The best eval run's score (ADR-027), kept in `docs/ai-eval/wiring-best.json`.
struct WiringBest: Codable {
    var score: Double
    var model: String
    var prompt: String
    var cases: [String: Double]
    /// The four product rules over the same replies (ADR-028): live, interactive, alive, correct.
    var metrics: [String: Double]?
}

/// Every push replays the best runs' recorded model replies (one per case, prompt v5 or v6) through today's parser and post-pass,
/// with no network: if the wiring score drops below that run, CI fails. The Kotlin test does the same.
struct WiringGateTests {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../docs/ai-eval").standardizedFileURL

    static func best() -> WiringBest? {
        (try? Data(contentsOf: folder.appendingPathComponent("wiring-best.json"))).flatMap { try? JSONDecoder().decode(WiringBest.self, from: $0) }
    }

    static func means(_ rows: [[String: Double]]) -> [String: Double] {
        var result: [String: Double] = [:]
        for rule in DesignRules.Rule.allCases.map(\.rawValue) {
            result[rule] = rows.isEmpty ? 0 : rows.map { $0[rule] ?? 1 }.reduce(0, +) / Double(rows.count)
        }
        return result
    }

    @Test func replayedScoreHoldsTheBestRun() throws {
        guard let best = Self.best() else { return }
        struct Case: Decodable {
            let file: String
            let size: String
            let wiring: [String]?
        }
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: Self.folder.appendingPathComponent("cases.json")))
        var scores: [Double] = []
        var rules: [[String: Double]] = []
        for item in cases {
            guard let wiring = item.wiring else { continue }
            let name = (item.file as NSString).deletingPathExtension
            guard let reply = try? String(contentsOf: Self.folder.appendingPathComponent("recorded/\(name).json"), encoding: .utf8) else { continue }
            let options = GenerationOptions(size: SizeChoice(rawValue: item.size) ?? .auto)
            let parsed = try AIWidgetParser.parseWidget(reply, options: options, id: "gate", enforceLayout: false)
            let score = WiringScore.score(parsed.spec, expected: wiring)
            #expect(score + 0.0001 >= (best.cases[name] ?? 0), "\(name) dropped to \(score); missing \(wiring.filter { !WiringScore.hits(parsed.spec, expected: [$0]).contains($0) })")
            scores.append(score)
            rules.append(DesignRules.check(parsed.spec).scores)
        }
        // Each rule's mean must hold its best run: a drop in any one of the four fails CI.
        let means = Self.means(rules)
        for (rule, floor) in best.metrics ?? [:] {
            #expect((means[rule] ?? 0) + 0.0001 >= floor, "\(rule) dropped to \(means[rule] ?? 0), best run \(floor)")
        }
        if let out = ProcessInfo.processInfo.environment["RENDER_OUT"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
            try encoder.encode(means).write(to: URL(fileURLWithPath: out).appendingPathComponent("rules-replayed.json"))
        }
        #expect(!scores.isEmpty, "wiring-best.json exists but no recorded replies do")
        #expect(scores.reduce(0, +) / Double(max(scores.count, 1)) + 0.0001 >= best.score)
    }
}
