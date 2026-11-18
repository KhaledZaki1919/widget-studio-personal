import Foundation
import Testing
@testable import WidgetKitCore

/// ADR-011: color tokens, `when`, `rotation`, highlight colors, icon fields, new bindings, categories.
private func spec(fields: [FieldSpec] = [], layers: [Layer], category: SpecCategory? = nil) -> WidgetSpec {
    WidgetSpec(id: "test.ext", name: .localized(en: "Ext", ar: "إضافة"), family: .small, theme: .light,
               background: Background(type: .solid, color: "@bg", outerColor: "@outer"),
               fields: fields, layers: layers, category: category)
}

private func shape(_ fill: String = "@accent", when: String? = nil, rotation: String? = nil) -> Layer {
    Layer(frame: Frame(x: 0, y: 0, w: 10, h: 10), when: when, rotation: rotation,
          content: .shape(ShapeLayer(kind: .circle, fill: fill)))
}

private func issues(_ spec: WidgetSpec) -> [SpecIssue] {
    if case .failure(let failure) = SpecValidator().validate(spec) { return failure.issues }
    return []
}

/// 2026-10-21 14:05 UTC.
private let now = Date(timeIntervalSince1970: 1_792_591_500)
private let utc = TimeZone(identifier: "UTC") ?? .current

private func resolver(_ spec: WidgetSpec, data: DataSnapshot? = nil) -> BindingResolver {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return BindingResolver(spec: spec, context: RenderContext(date: now, language: "en", timeZone: utc,
                                                              data: data ?? .sample(now: now, calendar: calendar)))
}

struct TokenTests {
    @Test func tokensAreValidColors() {
        #expect(issues(spec(layers: [shape("@accent"), shape("@fg"), shape("@dim")])).isEmpty)
        #expect(issues(spec(layers: [shape("@brand")])).contains { $0.path == "layers[0].fill" })
    }

    @Test func tokensResolvePerTheme() {
        let light = spec(layers: [shape("@fg")]).resolvingTokens(theme: .light)
        let dark = spec(layers: [shape("@fg")]).resolvingTokens(theme: .dark)
        #expect(light.background.color == "#FFFFFF" && light.background.outerColor == "#E6E9EC")
        #expect(dark.background.color == "#0E0E0E" && dark.background.outerColor == "#000000")
        #expect(dark.theme == .dark)
        guard case .shape(let lightShape) = light.layers[0].content, case .shape(let darkShape) = dark.layers[0].content else {
            Issue.record("expected shapes")
            return
        }
        #expect(lightShape.fill == "#0E0E0E" && darkShape.fill == "#FFFFFF")
    }

    @Test func everyTokenHasAValueInBothThemes() {
        for name in SpecTokens.names {
            for theme in SpecTheme.allCases {
                #expect(SpecTokens.hex(name, theme: theme).flatMap(HexColor.parse) != nil, "@\(name) \(theme)")
            }
        }
    }
}

struct ConditionTests {
    @Test func parsesTheThreeForms() {
        #expect(SpecCondition("{{stopwatch.running}}")?.binding == "stopwatch.running")
        #expect(SpecCondition("{{stopwatch.running}}")?.test == .truthy)
        #expect(SpecCondition("!{{stopwatch.running}}")?.test == .falsy)
        #expect(SpecCondition(" {{prayer.next.key}} == asr ")?.test == .equals("asr"))
        #expect(SpecCondition("stopwatch.running") == nil)
        #expect(SpecCondition("!{{a}} == b") == nil)
        #expect(SpecCondition("{{a}} ==") == nil)
    }

    @Test func validatorChecksTheBinding() {
        #expect(issues(spec(layers: [shape(when: "{{stopwatch.running}}")])).isEmpty)
        #expect(issues(spec(layers: [shape(when: "{{nope}}")])).contains { $0.path == "layers[0].when" })
        #expect(issues(spec(layers: [shape(when: "running")])).contains { $0.path == "layers[0].when" })
    }

    @Test func evaluatesWithData() {
        let spec = spec(layers: [shape()])
        let running = resolver(spec)
        #expect(running.isSatisfied("{{stopwatch.running}}"))
        #expect(!running.isSatisfied("!{{stopwatch.running}}"))
        // Sample next prayer at 14:05 UTC is Asr (14:58).
        #expect(running.isSatisfied("{{prayer.next.key}} == asr"))
        #expect(!running.isSatisfied("{{prayer.next.key}} == fajr"))
        #expect(!resolver(spec, data: DataSnapshot()).isSatisfied("{{prayer.next.key}} == asr"))
    }

    @Test func emptyFieldIsFalsy() {
        let fields = [FieldSpec(key: "zone", type: .timezone, label: "Zone", default: "")]
        let resolver = resolver(spec(fields: fields, layers: [shape()]))
        #expect(!resolver.isSatisfied("{{field.zone}}"))
        #expect(resolver.isSatisfied("!{{field.zone}}"))
    }
}

struct RotationAndBindingTests {
    @Test func rotationIsANumberOrNumberBinding() {
        #expect(issues(spec(layers: [shape(rotation: "45"), shape(rotation: "{{qibla.bearing}}")])).isEmpty)
        #expect(issues(spec(layers: [shape(rotation: "{{weather.cond}}")])).contains { $0.path == "layers[0].rotation" })
        #expect(issues(spec(layers: [shape(rotation: "720")])).contains { $0.path == "layers[0].rotation" })
    }

    @Test func rotationDecodesFromANumber() throws {
        let json = ##"{"type":"shape","kind":"circle","fill":"#FFFFFF","rotation":90,"frame":{"x":0,"y":0,"w":1,"h":1}}"##
        let layer = try JSONDecoder().decode(Layer.self, from: Data(json.utf8))
        #expect(layer.rotation == "90")
    }

    @Test func daysUntilADateField() {
        let fields = [FieldSpec(key: "day", type: .date, label: "Day", default: "2026-10-31")]
        #expect(resolver(spec(fields: fields, layers: [shape()])).render("{{days.day}}") == "10")
        let wrong = [FieldSpec(key: "day", type: .text, label: "Day", default: "x")]
        #expect(!issues(spec(fields: wrong, layers: [Layer(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: .text(TextLayer(
            value: "{{days.day}}", font: FontSpec(family: "system", size: 12), color: "@fg"
        )))])).isEmpty)
    }

    @Test func counterProgressNeedsATarget() {
        let ring = Layer(frame: Frame(x: 0, y: 0, w: 50, h: 50), content: .ring(RingLayer(
            progress: "{{counter.progress}}", color: "@accent", lineWidth: 4
        )))
        let target = [FieldSpec(key: "target", type: .number, label: "Target", default: "100")]
        #expect(issues(spec(fields: target, layers: [ring])).isEmpty)
        #expect(issues(spec(layers: [ring])).contains { $0.message.contains("target") })
        // Sample counter 33 of 100.
        #expect(resolver(spec(fields: target, layers: [ring])).number("{{counter.progress}}") == 0.33)
    }

    @Test func iconFieldsAreWhitelistedSymbols() {
        let icon = Layer(frame: Frame(x: 0, y: 0, w: 20, h: 20), content: .icon(IconLayer(
            symbol: "{{field.icon}}", size: 16, color: "@fg"
        )))
        let good = [FieldSpec(key: "icon", type: .icon, label: "Icon", default: "wifi")]
        let bad = [FieldSpec(key: "icon", type: .icon, label: "Icon", default: "applelogo")]
        #expect(issues(spec(fields: good, layers: [icon])).isEmpty)
        #expect(issues(spec(fields: bad, layers: [icon])).contains { $0.path == "fields[0].default" })
    }

    @Test func stepsMonthAndNextKey() {
        let resolver = resolver(spec(layers: [shape()]))
        #expect(resolver.render("{{steps.month}}") == "128,430")
        #expect(resolver.render("{{prayer.next.key}}") == "asr")
    }

    @Test func categoryRoundTrips() throws {
        let original = spec(layers: [shape()], category: .tiles)
        let decoded = try JSONDecoder().decode(WidgetSpec.self, from: JSONEncoder().encode(original))
        #expect(decoded.category == .tiles)
    }

    @Test func supportedFamiliesAreOwnAndLarger() {
        #expect(SpecFamily.small.supportedFamilies == [.small, .medium, .large, .xlarge])
        #expect(SpecFamily.medium.supportedFamilies == [.medium, .large, .xlarge])
        #expect(SpecFamily.large.supportedFamilies == [.large, .xlarge])
        #expect(SpecFamily.xlarge.supportedFamilies == [.xlarge])
    }
}
