import Foundation
import Testing
@testable import WidgetKitCore

/// The Mono library (TEMPLATES.md, ADR-011).
struct TemplateLibraryTests {
    @Test func everyTemplateIsValid() {
        let entries = TemplateLibrary.load()
        #expect(entries.count == 37)
        for entry in entries {
            if case .failure(let failure) = entry.result {
                Issue.record("\(entry.fileName): \(failure.description)")
            }
        }
    }

    @Test func idsMatchFileNamesAndTheCatalog() {
        for entry in TemplateLibrary.load() {
            guard let spec = entry.spec else { continue }
            #expect(entry.fileName == "\(spec.id).json")
        }
        let ids = TemplateLibrary.all().map(\.id)
        #expect(ids == TemplateLibrary.catalogOrder)
    }

    @Test func everyCategoryHasTemplates() {
        for category in SpecCategory.allCases {
            #expect(!TemplateLibrary.templates(in: category).isEmpty, "\(category) is empty")
        }
        #expect(TemplateLibrary.all().allSatisfy { $0.category != nil })
    }

    /// Arabic and English everywhere: names, field labels, and every text with literal words.
    @Test func everyTemplateIsBilingual() {
        for spec in TemplateLibrary.all() {
            #expect(Self.isPair(spec.name), "\(spec.id): name")
            for field in spec.fields {
                #expect(Self.isPair(field.label), "\(spec.id): label of \(field.key)")
            }
            for (index, layer) in spec.layers.enumerated() {
                switch layer.content {
                case .text(let text):
                    if case .plain(let value) = text.value {
                        #expect(!Self.hasWords(value), "\(spec.id) layers[\(index)]: \"\(value)\" needs en and ar")
                    }
                case .dotBars(let bars):
                    if case .plain(let value)? = bars.labels {
                        #expect(!Self.hasWords(value), "\(spec.id) layers[\(index)]: labels need en and ar")
                    }
                default:
                    break
                }
            }
        }
    }

    /// Visible text never shows "--" with the sample data, in either language.
    @Test func everyVisibleBindingResolvesWithSampleData() {
        for spec in TemplateLibrary.all() {
            for language in ["en", "ar"] {
                let resolver = BindingResolver(spec: spec, context: RenderContext(language: language, data: .sample()))
                for layer in spec.layers where layer.when.map(resolver.isSatisfied) ?? true {
                    guard case .text(let text) = layer.content, text.live == nil else { continue }
                    let value = resolver.render(text.value.resolved(language: language))
                    #expect(!value.contains(BindingResolver.missing), "\(spec.id) [\(language)]: \(value)")
                }
            }
        }
    }

    @Test func tokensResolveInBothThemes() {
        for spec in TemplateLibrary.all() {
            for theme in SpecTheme.allCases {
                let resolved = spec.resolvingTokens(theme: theme)
                let json = String(decoding: (try? JSONEncoder().encode(resolved)) ?? Data(), as: UTF8.self)
                #expect(!json.contains("\"@"), "\(spec.id) \(theme): unresolved token")
                #expect(SpecValidator().validate(resolved).isSuccess, "\(spec.id) \(theme): invalid after resolving")
            }
        }
    }

    @Test func stopwatchShowsExactlyOneState() {
        guard let spec = TemplateLibrary.template(id: "mono.stopwatch") else {
            Issue.record("missing mono.stopwatch")
            return
        }
        var idle = DataSnapshot.sample()
        idle.stopwatchStart = nil
        let running = BindingResolver(spec: spec, context: RenderContext(data: .sample()))
        let stopped = BindingResolver(spec: spec, context: RenderContext(data: idle))
        let conditional = spec.layers.compactMap(\.when)
        #expect(conditional.filter(running.isSatisfied).count == 3)
        #expect(conditional.filter(stopped.isSatisfied).count == 2)
    }

    @Test func prayerDayHighlightsOneColumn() {
        guard let spec = TemplateLibrary.template(id: "mono.prayer.day") else {
            Issue.record("missing mono.prayer.day")
            return
        }
        let resolver = BindingResolver(spec: spec, context: RenderContext(data: .sample()))
        #expect(spec.layers.compactMap(\.when).filter(resolver.isSatisfied).count == 1)
    }

    // MARK: Widget loading (ADR-012)

    @Test func loadsOneTemplateByID() throws {
        let spec = try TemplateLibrary.load(id: "mono.weather.forecast").get()
        #expect(spec.family == .medium)
    }

    @Test func unknownOrUnsafeIDsAreProblemsNotCrashes() {
        for id in ["mono.nope", "../TestSpecs/01-clock-digital", "", "mono/clock"] {
            guard case .failure(let failure) = TemplateLibrary.load(id: id) else {
                Issue.record("\(id) loaded")
                continue
            }
            #expect(failure.description.contains("not in the library"))
        }
    }

    @Test func widgetSizesListOnlyTemplatesThatFit() {
        #expect(TemplateLibrary.fitting(.small).allSatisfy { $0.family == .small })
        #expect(TemplateLibrary.fitting(.medium).allSatisfy { $0.family != .large })
        #expect(TemplateLibrary.fitting(.large).count == TemplateLibrary.all().count)
        #expect(TemplateLibrary.fitting(.medium).contains { $0.family == .medium })
    }

    /// Every template has a widget identity (ADR-013), in library order.
    @Test func everyTemplateHasAWidgetIdentity() {
        #expect(TemplateIDs.all.map { $0.id } == TemplateLibrary.catalogOrder)
        #expect(TemplateIDs.all.map { $0.id } == TemplateLibrary.all().map(\.id))
    }

    @Test func defaultTemplatesExistAndFit() throws {
        for size in SpecFamily.allCases {
            let spec = try TemplateLibrary.load(id: TemplateLibrary.defaultID(for: size)).get()
            #expect(spec.family.rank <= size.rank, "\(size)")
        }
    }

    @Test func widgetLogKeepsTheLastLines() {
        WidgetLog.clear()
        for index in 0..<(WidgetLog.capacity + 5) {
            WidgetLog.add("line \(index)")
        }
        let lines = WidgetLog.last(100)
        #expect(lines.count == WidgetLog.capacity)
        #expect(lines.last?.hasSuffix("line \(WidgetLog.capacity + 4)") == true)
        #expect(WidgetLog.last(2).count == 2)
        WidgetLog.clear()
        #expect(WidgetLog.last(5).isEmpty)
    }

    static func isPair(_ text: LocalizedText) -> Bool {
        if case .localized = text { return true }
        return false
    }

    /// Letters outside `{{…}}` (digits, symbols and Arabic-only text don't count).
    static func hasWords(_ value: String) -> Bool {
        let literal = Bindings.tokenize(value).compactMap { token -> String? in
            if case .literal(let text) = token { return text }
            return nil
        }.joined()
        return !FontRegistry.containsArabic(literal) && literal.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
