import Foundation
import Testing
@testable import WidgetKitCore

/// ADR-019 layers: `calendarMonth` layout, `list` and `progressBar` rules, the new fonts.
struct CalendarListTests {
    /// 2025-08-31 12:00 UTC, a Sunday; August 2025 starts on a Friday.
    let lastOfAugust = Date(timeIntervalSince1970: 1_756_641_600)
    let utc = TimeZone(identifier: "UTC") ?? .current

    func layout(_ layer: CalendarMonthLayer, language: String = "en") -> CalendarMonthLayout {
        CalendarMonthLayout(layer: layer, date: lastOfAugust, timeZone: utc,
                            localeIdentifier: language == "ar" ? "ar_EG@numbers=latn" : "en_US")
    }

    let monday = CalendarMonthLayer(font: FontSpec(family: "hand", size: 13), color: "#000000", weekStart: .monday,
                                    weekendDays: ["sun"])

    // MARK: Calendar layout

    @Test func augustStartingMonday() {
        let grid = layout(monday)
        #expect(grid.title == "AUG")
        #expect(grid.weekdays == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(grid.weekendColumns == [false, false, false, false, false, false, true])
        #expect(grid.rows.count == 5)
        #expect(grid.rows[0].map(\.day) == [nil, nil, nil, nil, 1, 2, 3])
        let last = grid.rows[4][6]
        #expect(last.day == 31 && last.isToday && last.isWeekend && !last.isOtherMonth)
        #expect(grid.rows.flatMap { $0 }.filter(\.isToday).count == 1)
    }

    @Test func otherMonthDaysCanBeDimmed() {
        var layer = monday
        layer.otherDays = .dimmed
        let grid = layout(layer)
        #expect(grid.rows[0].prefix(4).map(\.day) == [28, 29, 30, 31])
        #expect(grid.rows[0][0].isOtherMonth)
    }

    @Test func titleFormatsAndCases() {
        var layer = monday
        layer.titleCase = .natural
        #expect(layout(layer).title == "Aug")
        layer.titleFormat = .longYear
        #expect(layout(layer).title == "August 2025")
        layer.titleFormat = CalendarMonthLayer.TitleFormat.none
        layer.weekdays = CalendarMonthLayer.WeekdayStyle.none
        #expect(layout(layer).title.isEmpty)
        #expect(layout(layer).weekdays.isEmpty)
    }

    @Test func sundayStartShiftsTheGrid() {
        var layer = monday
        layer.weekStart = .sunday
        let grid = layout(layer)
        #expect(grid.rows[0].map(\.day) == [nil, nil, nil, nil, nil, 1, 2])
        #expect(grid.weekendColumns.first == true)
        #expect(grid.rows.count == 6)
    }

    @Test func arabicNamesWithLatinDigits() {
        var layer = monday
        layer.titleFormat = .long
        let grid = layout(layer, language: "ar")
        #expect(grid.title.contains("أغسطس"))
        #expect(grid.weekdays.count == 7)
        #expect(grid.rows.flatMap { $0 }.compactMap(\.day).contains(31))
    }

    // MARK: Validation

    func issues(_ layer: LayerContent, mode: SpecValidator.Mode = .standard) -> [SpecIssue] {
        let spec = WidgetSpec(id: "test.m5", name: .localized(en: "T", ar: "ت"), family: .medium, background: .solid("#FFFFFF"),
                              layers: [Layer(frame: Frame(x: 0, y: 0, w: 200, h: 150), content: layer)])
        if case .failure(let failure) = SpecValidator(mode: mode).validate(spec) { return failure.issues }
        return []
    }

    @Test func calendarRules() {
        #expect(issues(.calendarMonth(monday)).isEmpty)
        var bad = monday
        bad.weekendDays = ["sunday"]
        bad.todayColor = "red"
        let found = issues(.calendarMonth(bad))
        #expect(found.contains { $0.path == "layers[0].weekendDays[0]" })
        #expect(found.contains { $0.path == "layers[0].todayColor" })
        var tiny = monday
        tiny.font.size = 9
        #expect(issues(.calendarMonth(tiny)).isEmpty)
        #expect(issues(.calendarMonth(tiny), mode: .ai).contains { $0.path == "layers[0].font.size" })
    }

    @Test func listRules() {
        let item = ListLayer.Item(title: .localized(en: "Fajr", ar: "الفجر"), detail: "{{prayer.fajr}}")
        let list = ListLayer(items: [item], font: FontSpec(family: "system", size: 12), color: "#000000", marker: .icon)
        #expect(issues(.list(list)).isEmpty)
        #expect(issues(.list(list), mode: .ai).isEmpty)
        var empty = list
        empty.items = []
        #expect(issues(.list(empty)).contains { $0.path == "layers[0].items" })
        var many = list
        many.items = Array(repeating: item, count: 9)
        #expect(issues(.list(many)).contains { $0.path == "layers[0].items" })
        var located = list
        located.items[0].detail = "{{prayer.next.key}}"
        #expect(issues(.list(located), mode: .ai).contains { $0.path == "layers[0].items[0].detail" })
        var icon = list
        icon.items[0].icon = "not.a.symbol"
        #expect(issues(.list(icon)).contains { $0.path == "layers[0].items[0].icon" })
    }

    @Test func progressBarRules() {
        #expect(issues(.progressBar(ProgressBarLayer(progress: "{{battery.level}}", color: "#000000"))).isEmpty)
        #expect(issues(.progressBar(ProgressBarLayer(progress: "0.4", color: "#000000", segments: 10))).isEmpty)
        #expect(issues(.progressBar(ProgressBarLayer(progress: "1.5", color: "#000000"))).contains { $0.path == "layers[0].progress" })
        #expect(issues(.progressBar(ProgressBarLayer(progress: "{{weather.city}}", color: "#000000"))).contains { $0.path == "layers[0].progress" })
        #expect(issues(.progressBar(ProgressBarLayer(progress: "0.5", color: "#000000", segments: 30))).contains { $0.path == "layers[0].segments" })
    }

    @Test func newLayersRoundTripThroughJSON() throws {
        let item = ListLayer.Item(title: .localized(en: "Gym", ar: "الجيم"), detail: "18:00", icon: "figure.run", color: "#FF0000")
        let layers: [LayerContent] = [
            .calendarMonth(monday),
            .list(ListLayer(items: [item], font: FontSpec(family: "condensed", size: 14), color: "#000000", marker: .bar)),
            .progressBar(ProgressBarLayer(progress: "0.3", color: "#000000", segments: 5)),
        ]
        for content in layers {
            let layer = Layer(frame: Frame(x: 1, y: 2, w: 3, h: 4), mirror: true, content: content)
            #expect(try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(layer)) == layer)
        }
    }

    // MARK: Fonts, data, AI

    @Test func newFontsHaveArabicFallbacks() {
        for family in ["hand", "serif-display", "condensed"] {
            #expect(FontRegistry.families.contains(family))
            for weight in FontWeightName.allCases {
                #expect(FontRegistry.bundledPostScriptNames.contains(FontRegistry.arabicPostScriptName(weight, family: family)))
            }
        }
        #expect(FontRegistry.arabicPostScriptName(.bold, family: "hand") == "ArefRuqaa-Bold")
        #expect(FontRegistry.arabicPostScriptName(.regular, family: "serif-display") == "Amiri-Regular")
        #expect(FontRegistry.arabicPostScriptName(.black, family: "condensed") == "Lalezar-Regular")
    }

    @Test func listAndBarBindingsCountAsData() throws {
        let spec = try #require(TestSpecs.spec(id: "test.calendar.list"))
        let groups = DataRequirements.groups(for: spec)
        #expect(groups.contains(.prayer) && groups.contains(.device))
    }

    @Test func aiSchemaOffersTheNewLayers() {
        guard case .array(let shapes)? = AIWidgetSchema.schema(mode: .recreate)["properties"]?["layers"]?["items"]?["anyOf"] else {
            Issue.record("no layer shapes")
            return
        }
        let types = shapes.compactMap { shape -> String? in
            guard case .array(let values)? = shape["properties"]?["type"]?["enum"] else { return nil }
            return values.first?.stringValue
        }
        #expect(types.contains("calendarMonth") && types.contains("list") && types.contains("progressBar"))
    }

    @Test func refreshFollowsTheNewLayers() {
        func spec(_ content: LayerContent) -> WidgetSpec {
            WidgetSpec(id: "t", name: "t", family: .small, background: .solid("#000000"),
                       layers: [Layer(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: content)])
        }
        #expect(AIWidgetParser.refresh(for: spec(.calendarMonth(monday))) == .daily)
        let prayer = ListLayer(items: [ListLayer.Item(title: "Fajr", detail: "{{prayer.fajr}}")], font: FontSpec(family: "system", size: 12),
                               color: "#000000")
        #expect(AIWidgetParser.refresh(for: spec(.list(prayer))) == .hourly)
        #expect(AIWidgetParser.refresh(for: spec(.progressBar(ProgressBarLayer(progress: "0.5", color: "#000000")))) == .none)
    }
}
