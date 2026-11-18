import Foundation
import Testing
@testable import WidgetKitCore

/// State layers and the values they read (ADR-028).
struct StatesTests {
    private func spec(_ layers: [Layer] = []) -> WidgetSpec {
        WidgetSpec(id: "t", name: .localized(en: "t", ar: "t"), family: .small, background: .solid("#000000"), layers: layers)
    }

    private func make(_ date: Date = .now, data: DataSnapshot = .sample(), overrides: [String: String] = [:]) -> BindingResolver {
        var context = RenderContext(date: date, language: "en", timeZone: TimeZone(identifier: "Africa/Cairo") ?? .current, data: data)
        context.overrides = overrides
        return BindingResolver(spec: spec(), context: context)
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? .distantPast
    }

    // MARK: Conditions

    @Test func conditionsParse() {
        #expect(SpecCondition("{{a.b}} >= 0.9")?.test == .compare(">=", 0.9))
        #expect(SpecCondition("{{a.b}} < 1")?.test == .compare("<", 1))
        #expect(SpecCondition("{{a.b}} != x")?.test == .notEquals("x"))
        #expect(SpecCondition("{{a.b}} in 0.5..0.89")?.test == .range(0.5, 0.89))
        #expect(SpecCondition("{{a.b}} in rain, storm")?.test == .anyOf(["rain", "storm"]))
        #expect(SpecCondition("{{a.b}} >= high") == nil)
        #expect(SpecCondition("!{{a.b}} >= 1") == nil)
        #expect(SpecExpression("{{a}} && {{b}} || {{c}}")?.groups.map(\.count) == [2, 1])
        #expect(SpecExpression("{{a}} && nothing") == nil)
    }

    @Test func conditionsCompareRealNumbers() {
        let low = make(overrides: ["battery.level": "0.2", "battery.charging": "0"])
        #expect(low.isSatisfied("{{battery.level}} <= 0.2"))
        #expect(!low.isSatisfied("{{battery.level}} > 0.2"))
        #expect(low.isSatisfied("{{battery.level}} in 0.1..0.3"))
        #expect(low.isSatisfied("!{{battery.charging}} && {{battery.level}} < 0.5"))
        #expect(low.isSatisfied("{{battery.charging}} || {{battery.level}} < 0.5"))
        // No data: nothing passes, so a state never shows on a value that isn't there.
        let none = make(data: DataSnapshot())
        #expect(!none.isSatisfied("{{battery.level}} <= 0.2"))
        #expect(!none.isSatisfied("{{weather.kind}} != rain"))
    }

    // MARK: Time

    @Test func yearProgressOnTheOwnersDate() {
        let resolver = make(date("2026-11-05T10:00:00Z"))
        guard case .number(let share, let display)? = resolver.value(of: "year.progress") else {
            Issue.record("year.progress is not a number")
            return
        }
        #expect(abs(share - 0.846) < 0.002)
        #expect(display == "85")
        #expect(resolver.render("{{year.progress}}%") == "85%")
        #expect(resolver.render("{{year.day}}") == "309")
        #expect(resolver.render("{{year.daysLeft}}") == "56")
        #expect(resolver.render("{{month.daysLeft}}") == "25")
        #expect(resolver.render("{{month.progress}}") == "15")
        #expect(resolver.render("{{day.progress}}") == "50")
    }

    @Test func leapYearAndEdges() {
        #expect(make(date("2028-12-31T12:00:00Z")).render("{{year.day}}") == "366")
        #expect(make(date("2026-12-31T12:00:00Z")).render("{{year.daysLeft}}") == "0")
        #expect(make(date("2026-01-01T00:00:00Z")).render("{{year.progress}}") == "0")
    }

    /// The bug the owner reported: 15 of 48 dots on Nov 5. The lit count must be the bound share.
    @Test func dotsMatchTheBoundValue() {
        let resolver = make(date("2026-11-05T10:00:00Z"))
        for (rows, cols) in [(6, 8), (5, 10), (20, 20), (1, 12)] {
            let cells = rows * cols
            let lit = resolver.gridLevels("{{year.progress}}", cells: cells).filter { $0 > 0 }.count
            #expect(lit == Int((0.8459 * Double(cells)).rounded()), "\(rows)×\(cols): \(lit)")
        }
        #expect(resolver.gridLevels("{{year.progress}}", cells: 48).filter { $0 > 0 }.count == 41)
    }

    @Test func dayAndNight() {
        var data = DataSnapshot()
        #expect(make(date("2026-11-05T10:00:00Z"), data: data).render("{{time.isDay}}") == "1")
        #expect(make(date("2026-11-05T20:00:00Z"), data: data).render("{{time.isDay}}") == "0")
        data.live["weather.sunrise"] = .date(date("2026-11-05T05:00:00Z"))
        data.live["weather.sunset"] = .date(date("2026-11-05T15:00:00Z"))
        #expect(make(date("2026-11-05T14:00:00Z"), data: data).render("{{time.isDay}}") == "1")
        #expect(make(date("2026-11-05T15:30:00Z"), data: data).render("{{time.isDay}}") == "0")
    }

    @Test func forecastFollowsEachDay() {
        let data = DataSnapshot.sample()
        let days = data.weather?.forecast ?? []
        let resolver = make(data: data)
        for day in 1...6 {
            #expect(resolver.render("{{forecast.\(day).symbol}}") == days[day].symbol)
            #expect(resolver.render("{{forecast.\(day).hi}}") == String(Int(days[day].high)))
        }
    }

    @Test func weatherKinds() {
        #expect(["sun.max.fill", "moon.stars.fill"].map(WeatherKind.of) == ["clear", "clear"])
        #expect(["cloud.sun.fill", "cloud.moon.fill"].map(WeatherKind.of) == ["partlyCloudy", "partlyCloudy"])
        #expect(WeatherKind.of(symbol: "cloud.heavyrain.fill") == "rain")
        #expect(WeatherKind.of(symbol: "cloud.bolt.rain.fill") == "storm")
    }

    // MARK: Sets

    @Test func everySetIsDrawableAndCovered() {
        let all = Capabilities.stateSets
        #expect(all.count >= 8)
        for set in all {
            #expect(!set.description.isEmpty)
            let states = StatesLayer(set: set.id, value: set.value)
            let variants = states.expanded
            #expect(variants.count == set.variants.count, "\(set.id) did not expand")
            for variant in variants {
                #expect(!variant.layers.isEmpty, "\(set.id).\(variant.id) draws nothing")
                #expect(variant.sample != nil, "\(set.id).\(variant.id) has no sample")
                if let when = variant.when { #expect(SpecExpression(when) != nil, "\(set.id).\(variant.id): \(when)") }
                let text = String(data: (try? JSONEncoder().encode(variant.layers)) ?? Data(), encoding: .utf8) ?? ""
                #expect(!text.contains("$") && !(variant.when ?? "").contains("$"), "\(set.id).\(variant.id) left a placeholder")
                // The sample really selects this variant: the data, not the override of a state.
                var context = RenderContext(language: "en", data: DataSnapshot())
                context.overrides = BindingResolver.overrides(for: variant, of: states)
                let picked = BindingResolver(spec: spec(), context: context).variant(of: states)
                #expect(picked?.id == variant.id, "\(set.id): sample of \(variant.id) picked \(picked?.id ?? "none")")
            }
            let layer = Layer(frame: Frame(x: 0, y: 0, w: 100, h: 100), content: .states(states))
            let result = SpecValidator().validate(spec([layer]))
            if case .failure(let issues) = result { Issue.record("\(set.id): \(issues)") }
        }
    }

    @Test func batteryMoodThresholds() {
        let states = StatesLayer(set: "battery.mood")
        func mood(_ level: String, charging: String = "0") -> String? {
            make(data: DataSnapshot(), overrides: ["battery.level": level, "battery.charging": charging]).variant(of: states)?.id
        }
        #expect(mood("0.5", charging: "1") == "charging")
        #expect(mood("0.05", charging: "1") == "charging")
        #expect(mood("1") == "full")
        #expect(mood("0.9") == "full")
        #expect(mood("0.89") == "normal")
        #expect(mood("0.5") == "normal")
        #expect(mood("0.49") == "worried")
        #expect(mood("0.21") == "worried")
        #expect(mood("0.2") == "sad")
        #expect(mood("0") == "sad")
    }

    @Test func weatherArtFollowsConditionAndNight() {
        let states = StatesLayer(set: "weather.art")
        func art(_ symbol: String, hour: String) -> String? {
            var data = DataSnapshot()
            data.weather = .init(temperature: 20, high: 22, low: 10, condition: "x", symbol: symbol, city: "x", forecast: [])
            return make(date(hour), data: data).variant(of: states)?.id
        }
        let (day, night) = ("2026-11-05T10:00:00Z", "2026-11-05T21:00:00Z")
        #expect(art("sun.max.fill", hour: day) == "sun")
        #expect(art("moon.stars.fill", hour: night) == "moon")
        #expect(art("cloud.sun.fill", hour: day) == "partlyDay")
        #expect(art("cloud.moon.fill", hour: night) == "partlyNight")
        #expect(art("cloud.fill", hour: day) == "cloud")
        #expect(art("cloud.rain.fill", hour: night) == "rain")
        #expect(art("cloud.bolt.rain.fill", hour: day) == "storm")
        #expect(art("cloud.snow.fill", hour: day) == "snow")
        #expect(art("cloud.fog.fill", hour: day) == "fog")
    }

    @Test func validatorRules() throws {
        func issues(_ states: StatesLayer, frame: Frame = Frame(x: 0, y: 0, w: 50, h: 50)) -> String {
            let result = SpecValidator().validate(spec([Layer(frame: frame, content: .states(states))]))
            if case .failure(let failed) = result { return failed.description }
            return ""
        }
        #expect(issues(StatesLayer(set: "nope")).contains("unknown state set"))
        #expect(issues(StatesLayer()).contains("needs a built-in set"))
        #expect(issues(StatesLayer(set: "task.done")).contains("needs one binding"))
        #expect(issues(StatesLayer(set: "task.done", value: "{{tasks.1.done}}")).isEmpty)
        let icon = Layer(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: .icon(IconLayer(symbol: "star", size: 8, color: "#FFFFFF")))
        #expect(issues(StatesLayer(variants: [.init(id: "a", layers: [icon]), .init(id: "b", layers: [icon])])).contains("only the last"))
        #expect(issues(StatesLayer(variants: [.init(id: "a", when: "{{nope.nope}}", layers: [icon])])).contains("nope"))
        let button = Layer(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: .button(ButtonLayer(action: .openApp)))
        #expect(issues(StatesLayer(variants: [.init(id: "a", layers: [button])])).contains("top level"))
    }

    @Test func roundTripAndRequirements() throws {
        let text = ##"{"schemaVersion":1,"id":"t","name":{"en":"t","ar":"t"},"family":"small","background":{"type":"solid","color":"#000000"},"##
            + ##""layers":[{"type":"states","frame":{"x":0,"y":0,"w":50,"h":50},"set":"weather.art"}]}"##
        let spec = try JSONDecoder().decode(WidgetSpec.self, from: Data(text.utf8))
        let again = try JSONDecoder().decode(WidgetSpec.self, from: JSONEncoder().encode(spec))
        #expect(again == spec)
        #expect(DataRequirements.groups(for: spec).contains(.weather))
        let names = DataRequirements.bindingNames(in: spec)
        #expect(names.contains("weather.kind") && names.contains("time.isDay"))
        // The token survives until the theme resolves it, then the art takes the hex.
        let resolved = spec.resolvingTokens(theme: .dark)
        guard case .states(let states) = resolved.layers[0].content else { return }
        #expect(states.color == "#FFFFFF")
        guard case .dotGrid(let grid)? = states.expanded[7].layers.first?.content else {
            Issue.record("no dots")
            return
        }
        #expect(grid.onColor == "#E2231A", "the sun takes the accent")
    }
}

/// Tasks' pure logic (ADR-028); `TasksTest.kt` pins the same answers.
struct TaskFormatTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Africa/Cairo") ?? .current
        return calendar
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text) ?? .distantPast }

    private var now: Date { date("2026-11-05T10:00:00Z") }

    private var tasks: [TaskItem] {
        [
            TaskItem(id: "c", title: "No date"),
            TaskItem(id: "b", title: "Later", due: date("2026-11-08T10:00:00Z")),
            TaskItem(id: "a", title: "Today", due: date("2026-11-05T12:30:00Z"), hasTime: true, priority: .high),
            TaskItem(id: "o", title: "Late", due: date("2026-11-01T10:00:00Z")),
            TaskItem(id: "d", title: "Done", done: true, doneAt: date("2026-11-05T08:00:00Z")),
            TaskItem(id: "e", title: "Old", done: true, doneAt: date("2026-11-01T08:00:00Z")),
        ]
    }

    @Test func filters() {
        #expect(TaskFormat.filter(tasks, .today, now: now, calendar: calendar).map(\.id) == ["o", "a"])
        #expect(TaskFormat.filter(tasks, .upcoming, now: now, calendar: calendar).map(\.id) == ["b", "c"])
        #expect(TaskFormat.filter(tasks, .done, now: now, calendar: calendar).map(\.id) == ["d", "e"])
    }

    @Test func dueTexts() {
        let today = tasks[2]
        #expect(TaskFormat.dueText(today, now: now, calendar: calendar, language: "en") == "Today 14:30")
        #expect(TaskFormat.dueText(tasks[3], now: now, calendar: calendar, language: "en") == "Overdue")
        #expect(TaskFormat.dueText(tasks[1], now: now, calendar: calendar, language: "en") == "8 Nov")
    }

    @Test func widgetValues() {
        let live = TaskFormat.values(tasks, now: now, calendar: calendar, language: "en")
        func shown(_ key: String) -> String? { live[key]?.display }
        #expect(shown("tasks.today.count") == "2")
        #expect(shown("tasks.open.count") == "4")
        #expect(shown("tasks.done.count") == "1")
        #expect(shown("tasks.progress") == "33")
        #expect(shown("tasks.next.title") == "Late")
        #expect(shown("tasks.1.id") == "o")
        // Open first, then today's done one, ticked.
        #expect(shown("tasks.5.title") == "Done")
        #expect(shown("tasks.5.done") == "1")
        #expect(shown("tasks.6.title") == "")
        #expect(shown("tasks.list") == "Late\nToday\nLater\nNo date")
    }

    @Test func emptyList() {
        let live = TaskFormat.values([], now: now, calendar: calendar, language: "ar")
        #expect(live["tasks.next.title"]?.display == "لا مهام")
        #expect(live["tasks.progress"]?.display == "0")
    }
}
