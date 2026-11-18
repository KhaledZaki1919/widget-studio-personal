import Foundation
import Testing
@testable import WidgetKitCore

/// The four product rules (ADR-028). The vectors are shared with the Kotlin port.
struct DesignRulesTests {
    struct Vector: Decodable {
        let name: String
        let spec: WidgetSpec
        let findings: [String]
    }

    static let vectors: [Vector] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/DesignRules/vectors.json")
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Vector].self, from: data) else { return [] }
        return decoded
    }()

    @Test func vectorsFindWhatTheySay() {
        #expect(Self.vectors.count >= 6, "Fixtures/DesignRules/vectors.json did not load")
        for vector in Self.vectors {
            let found = DesignRules.check(vector.spec).findings.map(\.rule.rawValue).sorted()
            #expect(found == vector.findings.sorted(), "\(vector.name): \(DesignRules.check(vector.spec).findings.map(\.element))")
        }
    }

    @Test func scoresCountEachRule() {
        let report = DesignRules.check(Self.vectors[0].spec)
        #expect(report.score(.live) == 0)
        #expect(report.score(.interactive) == 1)
        #expect(DesignRules.check(Self.vectors[5].spec).scores.values.allSatisfy { $0 == 1 })
    }

    /// What can be fixed is fixed: the year widget comes out of the post-pass with no finding.
    @Test func thePostPassClearsTheYearWidget() {
        let wired = AutoWire.apply(Self.vectors[0].spec).spec
        #expect(DesignRules.check(wired).findings.isEmpty, "\(DesignRules.check(wired).findings)")
    }

    /// Unsure values stay static and show in the Interactive summary.
    @Test func unsureValuesReachTheSummary() throws {
        let vectors = try JSONDecoder().decode([AutoWireTests.Vector].self, from: Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Fixtures/AutoWire/vectors.json")))
        let vector = try #require(vectors.first { $0.name.hasPrefix("a lone percent") })
        let summary = InteractiveSummary.build(AutoWire.apply(vector.spec).spec, language: "en")
        #expect(summary.decorative.contains { $0.title == "42%" })
    }

    /// Every template meets the rules (ADR-028): the audit, kept forever.
    @Test func everyTemplatePasses() {
        for spec in TemplateLibrary.all() {
            let findings = DesignRules.check(spec).findings
            #expect(findings.isEmpty, "\(spec.id): \(findings.map { "\($0.rule.rawValue) \($0.element)" })")
        }
    }
}
