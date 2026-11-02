import Foundation
import Testing
@testable import WidgetKitCore

/// The example spec of brief §4.1, as a mutable dictionary for rule tests.
private func exampleSpec() -> [String: Any] {
    [
        "schemaVersion": 1,
        "id": "mono.weather.forecast",
        "name": ["en": "Forecast", "ar": "توقعات الطقس"],
        "family": "medium",
        "theme": "dark",
        "refresh": "hourly",
        "background": ["type": "solid", "color": "#0E0E0E"],
        "fields": [
            ["key": "city", "type": "city", "label": ["en": "City", "ar": "المدينة"], "default": "Cairo"],
        ],
        "layers": [
            ["type": "icon", "symbol": "cloud.sun.fill", "size": 26, "color": "#FFFFFF",
             "frame": ["x": 16, "y": 16, "w": 26, "h": 26]],
            ["type": "text", "value": "{{weather.temp}}°", "font": ["family": "dot", "size": 34], "color": "#FFFFFF",
             "frame": ["x": 48, "y": 10, "w": 90, "h": 40]],
            ["type": "text", "value": "{{field.city}}", "font": ["family": "system", "size": 11, "weight": "medium"],
             "color": "#FFFFFF", "align": "trailing", "frame": ["x": 220, "y": 16, "w": 128, "h": 14], "mirror": true],
            ["type": "forecastRow", "days": 6, "color": "#FFFFFF", "frame": ["x": 16, "y": 80, "w": 332, "h": 76]],
        ],
    ]
}

private func layer(_ type: String, _ properties: [String: Any], frame: [String: Any] = ["x": 0, "y": 0, "w": 50, "h": 50]) -> [String: Any] {
    properties.merging(["type": type, "frame": frame]) { _, new in new }
}

private func validate(_ spec: [String: Any], mode: SpecValidator.Mode = .standard) throws -> Result<WidgetSpec, SpecIssues> {
    SpecValidator(mode: mode).validate(data: try JSONSerialization.data(withJSONObject: spec))
}

/// Replaces the layers with `layers` (and optionally fields) and returns the issues.
private func issues(layers: [[String: Any]], fields: [[String: Any]]? = nil, mode: SpecValidator.Mode = .standard) throws -> [SpecIssue] {
    var spec = exampleSpec()
    spec["layers"] = layers
    if let fields { spec["fields"] = fields }
    if case .failure(let failure) = try validate(spec, mode: mode) { return failure.issues }
    return []
}

private func text(_ value: Any, family: String = "system", size: Double = 14) -> [String: Any] {
    layer("text", ["value": value, "font": ["family": family, "size": size], "color": "#FFFFFF"])
}

struct SpecValidatorTests {
    // MARK: Valid specs

    @Test func briefExampleIsValid() throws {
        let spec = try validate(exampleSpec()).get()
        #expect(spec.id == "mono.weather.forecast")
        #expect(spec.family == .medium)
        #expect(spec.layers.count == 4)
        #expect(spec.layers[3].content.typeName == "forecastRow")
        #expect(spec.name.resolved(language: "ar") == "توقعات الطقس")
    }

    @Test func unknownKeysAreIgnored() throws {
        var spec = exampleSpec()
        spec["designer"] = "someone"
        var layers = try #require(spec["layers"] as? [[String: Any]])
        layers[0]["sparkle"] = true
        spec["layers"] = layers
        #expect(try validate(spec).get().layers.count == 4)
    }

    @Test func encodesAndDecodesRoundTrip() throws {
        let spec = try validate(exampleSpec()).get()
        let again = try JSONDecoder().decode(WidgetSpec.self, from: JSONEncoder().encode(spec))
        #expect(again == spec)
    }

    // MARK: Top level

    @Test func schemaVersionMustBe1() throws {
        var spec = exampleSpec()
        spec["schemaVersion"] = 2
        #expect(try specIssues(spec).contains { $0.path == "schemaVersion" })
    }

    @Test func idMustBeLowercaseSlug() throws {
        var spec = exampleSpec()
        spec["id"] = "Mono Weather"
        #expect(try specIssues(spec).contains { $0.path == "id" })
    }

    @Test func nameNeedsBothLanguages() throws {
        var spec = exampleSpec()
        spec["name"] = "Forecast"
        #expect(try specIssues(spec).contains { $0.path == "name" })
    }

    @Test func unknownFamilyIsAnIssueNotACrash() throws {
        var spec = exampleSpec()
        spec["family"] = "extraLarge"
        #expect(try specIssues(spec) == [SpecIssue("family", "unknown value")])
    }

    @Test func missingKeyIsReportedWithItsPath() throws {
        var spec = exampleSpec()
        spec["background"] = ["color": "#000000"]
        #expect(try specIssues(spec) == [SpecIssue("background", "missing \"type\"")])
    }

    @Test func invalidJSONIsReported() {
        #expect(SpecValidator().validate(data: Data("{not json".utf8)) == .failure(SpecIssues([SpecIssue("", "not valid JSON")])))
    }

    @Test func gradientNeeds2To4Colors() throws {
        var spec = exampleSpec()
        spec["background"] = ["type": "gradient", "colors": ["#000000"]]
        #expect(try specIssues(spec).contains { $0.path == "background.colors" })
        spec["background"] = ["type": "gradient", "colors": ["#000000", "#FF0000"], "angle": 90]
        #expect(try specIssues(spec).isEmpty)
    }

    // MARK: Layers

    @Test func atMost30Layers() throws {
        let many = Array(repeating: text("hi"), count: 31)
        #expect(try issues(layers: many).contains { $0.message.contains("at most 30 layers") })
        #expect(try issues(layers: Array(repeating: text("hi"), count: 30)).isEmpty)
    }

    @Test func unknownLayerTypeFails() throws {
        #expect(try issues(layers: [layer("video", ["src": "x"])]) == [SpecIssue("layers[0].type", "unknown layer type \"video\"")])
    }

    @Test func textAtMost200Characters() throws {
        #expect(try issues(layers: [text(String(repeating: "a", count: 201))]).contains { $0.path == "layers[0].value" })
        #expect(try issues(layers: [text(String(repeating: "a", count: 200))]).isEmpty)
    }

    @Test func localizedTextChecksBothLanguages() throws {
        let value: [String: Any] = ["en": "ok", "ar": String(repeating: "ب", count: 201)]
        #expect(try issues(layers: [text(value)]).contains { $0.path == "layers[0].value" })
    }

    @Test func framesAreClampedToTheCanvas() throws {
        var spec = exampleSpec()
        spec["layers"] = [layer("shape", ["kind": "rect", "fill": "#FFFFFF"], frame: ["x": 300, "y": -20, "w": 500, "h": 40])]
        let frame = try validate(spec).get().layers[0].frame
        #expect(frame == Frame(x: 0, y: 0, w: 364, h: 40))
    }

    @Test func framesNeedPositiveSize() throws {
        let bad = layer("shape", ["kind": "rect", "fill": "#FFFFFF"], frame: ["x": 0, "y": 0, "w": 0, "h": 10])
        #expect(try issues(layers: [bad]).contains { $0.path == "layers[0].frame" })
    }

    @Test func colorsMustBeHex() throws {
        for color in ["red", "#FFF", "#GGGGGG", "rgb(0,0,0)", "FFFFFF"] {
            let bad = layer("shape", ["kind": "circle", "fill": color])
            #expect(try issues(layers: [bad]).contains { $0.path == "layers[0].fill" }, "accepted \(color)")
        }
        for color in ["#FFFFFF", "#ff000080"] {
            #expect(try issues(layers: [layer("shape", ["kind": "circle", "fill": color])]).isEmpty, "rejected \(color)")
        }
    }

    @Test func fontsOnlyFromTheRegistry() throws {
        #expect(try issues(layers: [text("x", family: "Helvetica")]).contains { $0.path == "layers[0].font.family" })
        for family in FontRegistry.families {
            #expect(try issues(layers: [text("x", family: family)]).isEmpty, "rejected \(family)")
        }
    }

    @Test func fontSizeInRange() throws {
        #expect(try issues(layers: [text("x", size: 400)]).contains { $0.path == "layers[0].font.size" })
    }

    @Test func noRemoteURLs() throws {
        #expect(try issues(layers: [text("see https://example.com")]).contains { $0.message.contains("URLs") })
        #expect(try issues(layers: [text("www.example.com")]).contains { $0.message.contains("URLs") })
    }

    @Test func iconsFromTheWhitelistOrASymbolBinding() throws {
        let unknown = layer("icon", ["symbol": "applelogo", "size": 20, "color": "#FFFFFF"])
        #expect(try issues(layers: [unknown]).contains { $0.path == "layers[0].symbol" })
        let bound = layer("icon", ["symbol": "{{weather.symbol}}", "size": 20, "color": "#FFFFFF"])
        #expect(try issues(layers: [bound]).isEmpty)
        let wrongKind = layer("icon", ["symbol": "{{weather.temp}}", "size": 20, "color": "#FFFFFF"])
        #expect(try issues(layers: [wrongKind]).contains { $0.path == "layers[0].symbol" })
    }

    @Test func imageSources() throws {
        #expect(try issues(layers: [layer("image", ["source": "user_image"])]).isEmpty)
        #expect(try issues(layers: [layer("image", ["source": "asset:halftone.dots"])]).isEmpty)
        #expect(try issues(layers: [layer("image", ["source": "https://x.y/z.png"])]).contains { $0.path == "layers[0].source" })
    }

    @Test func dotGridAndBarsLimits() throws {
        let grid = layer("dotGrid", ["rows": 50, "cols": 10, "dotSize": 3, "gap": 1, "onColor": "#FFFFFF",
                                     "offColor": "#333333", "values": "{{steps.monthGrid}}"])
        #expect(try issues(layers: [grid]).contains { $0.path == "layers[0].rows" })
        let bars = layer("dotBars", ["bars": 7, "maxDots": 8, "values": "0.2,0.5,2", "color": "#FFFFFF"])
        #expect(try issues(layers: [bars]).contains { $0.path == "layers[0].values" })
        let good = layer("dotBars", ["bars": 7, "maxDots": 8, "values": "{{sleep.week}}", "color": "#FFFFFF"])
        #expect(try issues(layers: [good]).isEmpty)
    }

    @Test func ringProgressIsANumberBinding() throws {
        let ok = layer("ring", ["progress": "{{battery.level}}", "color": "#FFFFFF", "lineWidth": 6])
        #expect(try issues(layers: [ok]).isEmpty)
        let literal = layer("ring", ["progress": "0.4", "color": "#FFFFFF", "lineWidth": 6])
        #expect(try issues(layers: [literal]).isEmpty)
        let text = layer("ring", ["progress": "{{weather.cond}}", "color": "#FFFFFF", "lineWidth": 6])
        #expect(try issues(layers: [text]).contains { $0.path == "layers[0].progress" })
        let tooBig = layer("ring", ["progress": "1.5", "color": "#FFFFFF", "lineWidth": 6])
        #expect(try issues(layers: [tooBig]).contains { $0.path == "layers[0].progress" })
    }

    // MARK: Bindings

    @Test func unknownBindingFails() throws {
        #expect(try issues(layers: [text("{{weather.uv}}")]) == [SpecIssue("layers[0].value", "unknown binding {{weather.uv}}")])
    }

    @Test func fieldBindingNeedsTheField() throws {
        #expect(try issues(layers: [text("{{field.name}}")]).contains { $0.message.contains("missing field") })
    }

    @Test func timezoneTimeNeedsATimezoneField() throws {
        let fields: [[String: Any]] = [["key": "zone", "type": "timezone", "label": ["en": "Zone", "ar": "المنطقة"], "default": "Asia/Tokyo"]]
        #expect(try issues(layers: [text("{{tz.zone.time}}")], fields: fields).isEmpty)
        #expect(try issues(layers: [text("{{tz.city.time}}")]).contains { $0.message.contains("timezone field") })
    }

    @Test func liveTimerNeedsADateField() throws {
        let fields: [[String: Any]] = [["key": "day", "type": "date", "label": ["en": "Day", "ar": "اليوم"], "default": "2026-12-31"]]
        var timer = text("")
        timer["live"] = ["kind": "timer", "target": "{{field.day}}"]
        #expect(try issues(layers: [timer], fields: fields).isEmpty)
        timer["live"] = ["kind": "relative", "target": "{{time.h}}"]
        #expect(try issues(layers: [timer], fields: fields).contains { $0.path == "layers[0].live.target" })
        timer["live"] = ["kind": "timer"]
        #expect(try issues(layers: [timer], fields: fields).contains { $0.path == "layers[0].live.target" })
    }

    @Test func tokenizerSplitsBindingsAndLiterals() {
        #expect(Bindings.tokenize("{{weather.temp}}°") == [.binding("weather.temp"), .literal("°")])
        #expect(Bindings.tokenize("a {{x}} b {{y") == [.literal("a "), .binding("x"), .literal(" b {{y")])
        #expect(Bindings.soleBinding(" {{field.day}} ") == "field.day")
        #expect(Bindings.soleBinding("{{a}}{{b}}") == nil)
    }

    // MARK: Fields

    @Test func fieldKeysAreUniqueAndDefaultsTyped() throws {
        let fields: [[String: Any]] = [
            ["key": "city", "type": "city", "label": ["en": "City", "ar": "المدينة"]],
            ["key": "city", "type": "text", "label": ["en": "Again", "ar": "مرة"]],
            ["key": "when", "type": "date", "label": ["en": "When", "ar": "متى"], "default": "tomorrow"],
            ["key": "zone", "type": "timezone", "label": ["en": "Zone", "ar": "منطقة"], "default": "Mars/Base"],
            ["key": "link", "type": "url", "label": ["en": "Link", "ar": "رابط"], "default": "https://example.com"],
        ]
        let found = try issues(layers: [text("x")], fields: fields)
        #expect(found.contains { $0.path == "fields[1].key" })
        #expect(found.contains { $0.path == "fields[2].default" })
        #expect(found.contains { $0.path == "fields[3].default" })
        #expect(found.contains { $0.path == "fields[4].default" })
    }

    // MARK: Buttons and actions

    @Test func unknownActionFails() throws {
        #expect(try issues(layers: [layer("button", ["action": "wifi.toggle"])]) == [SpecIssue("layers[0].action", "unknown value")])
    }

    @Test func openURLNeedsAURLField() throws {
        let fields: [[String: Any]] = [["key": "link", "type": "url", "label": ["en": "Link", "ar": "رابط"]]]
        #expect(try issues(layers: [layer("button", ["action": "open.url", "arg": "{{field.link}}"])], fields: fields).isEmpty)
        #expect(try issues(layers: [layer("button", ["action": "open.url", "arg": "https://x.y"])], fields: fields)
            .contains { $0.path == "layers[0].arg" })
    }

    @Test func shortcutRunNeedsAShortcutField() throws {
        let fields: [[String: Any]] = [["key": "torch", "type": "shortcut", "label": ["en": "Shortcut", "ar": "اختصار"]]]
        #expect(try issues(layers: [layer("button", ["action": "shortcut.run", "arg": "{{field.torch}}"])], fields: fields).isEmpty)
        #expect(try issues(layers: [layer("button", ["action": "shortcut.run", "arg": "Torch"])], fields: fields)
            .contains { $0.path == "layers[0].arg" })
    }

    // MARK: AI mode (brief §5.1)

    @Test func aiModeAllowsOnlyOpenAppAndItsBindings() throws {
        #expect(try issues(layers: [layer("button", ["action": "open.app"]), text("{{time.hh}}:{{time.mm}} {{weather.temp}}")], fields: [], mode: .ai).isEmpty)
        // ADR-018: battery, prayer and steps too.
        #expect(try issues(layers: [text("{{battery.level}} {{prayer.next.name}} {{qibla.bearing}} {{steps.today}}")], fields: [], mode: .ai).isEmpty)
        #expect(try issues(layers: [layer("button", ["action": "counter.increment"])], mode: .ai).contains { $0.path == "layers[0].action" })
        for binding in ["sleep.lastNight", "location.lat", "counter.value", "focus.today"] {
            #expect(try issues(layers: [text("{{\(binding)}}")], fields: [], mode: .ai).contains { $0.message.contains("AI output") }, "\(binding)")
        }
    }

    @Test func aiModeAllowsOnlyTextAndImageFields() throws {
        let shortcut: [[String: Any]] = [["key": "torch", "type": "shortcut", "label": ["en": "Shortcut", "ar": "اختصار"]]]
        #expect(try issues(layers: [text("hi")], fields: shortcut, mode: .ai).contains { $0.path == "fields[0].type" })
        let title: [[String: Any]] = [["key": "title", "type": "text", "label": ["en": "Title", "ar": "العنوان"]]]
        #expect(try issues(layers: [text("{{field.title}}")], fields: title, mode: .ai).isEmpty)
        // ADR-019: countdowns to a date field.
        let event: [[String: Any]] = [["key": "event", "type": "date", "label": ["en": "Event", "ar": "الموعد"], "default": "2026-12-31T09:00:00"]]
        var timer = text("x")
        timer["live"] = ["kind": "timer", "target": "{{field.event}}"]
        var days = text("{{days.event}}")
        days["frame"] = ["x": 0, "y": 60, "w": 50, "h": 50]   // AI text must not overlap (M6.1)
        #expect(try issues(layers: [timer, days], fields: event, mode: .ai).isEmpty)
        #expect(try issues(layers: [layer("image", ["source": "asset:logo"])], fields: [], mode: .ai).contains { $0.path == "layers[0].source" })
    }

    @Test func aiModeNeedsFontSize11() throws {
        #expect(try issues(layers: [text("tiny", size: 9)], mode: .ai).contains { $0.path == "layers[0].font.size" })
        #expect(try issues(layers: [text("tiny", size: 9)]).isEmpty)
    }

    @Test func describeJoinsIssuesForTheRetryPrompt() {
        let text = SpecValidator.describe([SpecIssue("id", "bad"), SpecIssue("", "not valid JSON")])
        #expect(text == "id: bad; not valid JSON")
    }

    // MARK: Values

    @Test func hexColorParsing() throws {
        let color = try #require(HexColor.parse("#FF000080"))
        #expect(color.red == 1 && color.green == 0 && abs(color.alpha - 128.0 / 255) < 0.0001)
        #expect(HexColor.parse("#00FF00")?.alpha == 1)
    }

    @Test func fieldDatesParse() {
        #expect(FieldValues.date("2026-12-31") != nil)
        #expect(FieldValues.date("2026-12-31T20:00:00Z") != nil)
        #expect(FieldValues.date("31/12/2026") == nil)
    }

    private func specIssues(_ spec: [String: Any]) throws -> [SpecIssue] {
        if case .failure(let failure) = try validate(spec) { return failure.issues }
        return []
    }
}
