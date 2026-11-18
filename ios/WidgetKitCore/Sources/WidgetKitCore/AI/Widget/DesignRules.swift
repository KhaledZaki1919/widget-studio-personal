import Foundation

/// The four product rules as generic detectors (ADR-028): they know shapes of problems, never a
/// widget. They run on every design, after the post-pass: what they still find goes in the
/// Interactive summary, and the eval scores each rule from the same counts. Templates must come out
/// clean (`TemplateRulesTests`). Ported in `DesignRules.kt`; both run `Fixtures/DesignRules/vectors.json`.
public enum DesignRules {
    public enum Rule: String, CaseIterable, Sendable, Codable {
        case live, interactive, alive, correct
    }

    public struct Finding: Sendable, Equatable {
        public let rule: Rule
        public let path: LayerEditing.Path
        public let element: String
        public let message: LocalizedText
    }

    public struct Report: Sendable, Equatable {
        public let findings: [Finding]
        /// How many elements each rule looked at.
        public let checked: [Rule: Int]

        /// The share of checked elements that passed, 0…1; 1 when nothing applies.
        public func score(_ rule: Rule) -> Double {
            let total = checked[rule] ?? 0
            guard total > 0 else { return 1 }
            return max(0, 1 - Double(findings.filter { $0.rule == rule }.count) / Double(total))
        }

        public var scores: [String: Double] {
            Dictionary(uniqueKeysWithValues: Rule.allCases.map { ($0.rawValue, score($0)) })
        }
    }

    private enum Say {
        static let frozen: LocalizedText = .localized(en: "A fixed value that should change. Nothing near it says what it shows.",
                                                      ar: "قيمة ثابتة يفترض أن تتغير، ولا شيء بجوارها يوضح ما تعرضه.")
        static let frozenLevel: LocalizedText = .localized(en: "A level drawn at a fixed value.", ar: "مستوى مرسوم بقيمة ثابتة.")
        static let noAction: LocalizedText = .localized(en: "Looks like a control but does nothing.", ar: "يبدو كزر لكنه لا يفعل شيئًا.")
        static let oneLook: LocalizedText = .localized(en: "Shows one look only, though it should change with the state.",
                                                       ar: "يعرض شكلًا واحدًا رغم أنه يجب أن يتغير مع الحالة.")
        static let mismatch: LocalizedText = .localized(en: "The picture and the value disagree.", ar: "الرسم لا يطابق القيمة.")
        static let label: LocalizedText = .localized(en: "The label beside it names something else.", ar: "العنوان بجواره يدل على شيء آخر.")
        static let battery: LocalizedText = .localized(en: "Shows the battery, but nothing on the card says so.",
                                                       ar: "يعرض البطارية، لكن لا شيء في البطاقة يدل على ذلك.")
    }

    private struct Tally {
        var findings: [Finding] = []
        var checked: [Rule: Int] = [:]

        mutating func pass(_ rule: Rule) {
            checked[rule, default: 0] += 1
        }

        mutating func fail(_ rule: Rule, _ item: AutoWire.Found, _ element: String, _ message: LocalizedText) {
            checked[rule, default: 0] += 1
            findings.append(Finding(rule: rule, path: item.path, element: element, message: message))
        }
    }

    public static func check(_ spec: WidgetSpec) -> Report {
        let run = AutoWire.Run(spec: spec, inventory: [])
        var tally = Tally()
        let items = AutoWire.walk(spec.layers)
        let buttons = items.compactMap { item -> (frame: Frame, action: String)? in
            if case .button(let button) = item.layer.content { return (item.frame, button.action.rawValue) }
            return nil
        }
        func hasAction(_ frame: Frame) -> Bool {
            buttons.contains { $0.action != "open.app" && AutoWire.Run.inside(frame, $0.frame) }
        }
        for (index, _) in spec.layers.enumerated() where run.topics.has("battery") {
            if AutoWire.Run.faceParts(of: index, in: spec.layers) != nil {
                tally.fail(.alive, AutoWire.Found(path: [index], layer: spec.layers[index], frame: spec.layers[index].frame, mirror: nil), "face", Say.oneLook)
            }
        }
        for item in items {
            switch item.layer.content {
            case .text(let text): checkText(text, item, run, &tally, hasAction: hasAction)
            case .ring(let ring): checkLevel(ring.progress, kind: "ring", item, run, &tally)
            case .progressBar(let bar): checkLevel(bar.progress, kind: "progressBar", item, run, &tally)
            case .dotGrid(let grid): checkDots(grid, item, run, &tally)
            case .icon(let icon): checkIcon(icon, item, run, &tally, hasAction: hasAction)
            case .shape: checkSwitch(item, run, &tally, hasAction: hasAction)
            case .list(let list): checkList(list, item, &tally, hasAction: hasAction)
            case .states: tally.pass(.alive)
            case .forecastRow, .analogClock, .calendarMonth: tally.pass(.live)
            default: break
            }
        }
        return Report(findings: tally.findings, checked: tally.checked)
    }

    /// What text looks like when it is really a value: the shapes the post-pass binds.
    static func looksChanging(_ text: String) -> Bool {
        typealias Shape = AutoWire.TextShape
        return Shape.isClock(text) || Shape.isPercent(text) || Shape.isTemperature(text) || Shape.isStepCount(text)
            || Shape.percentLabel(text) != nil || Shape.dateTemplate(text) != nil
    }

    private static func checkText(_ text: TextLayer, _ item: AutoWire.Found, _ run: AutoWire.Run, _ tally: inout Tally,
                                  hasAction: (Frame) -> Bool) {
        let english = text.value.resolved(language: "en").trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = english.unicodeScalars.filter { $0 != "\u{FE0E}" && $0 != "\u{FE0F}" }
        let glyph = String(String.UnicodeScalarView(scalars))
        if let set = Capabilities.stateSets.first(where: { $0.glyphs.contains(glyph) }), set.topic.map(run.topics.has) ?? false {
            tally.fail(.alive, item, english, Say.oneLook)
        }
        if Capabilities.actions.contains(where: { $0.glyphs.contains(glyph) }) {
            if hasAction(item.frame) { tally.pass(.interactive) } else { tally.fail(.interactive, item, english, Say.noAction) }
        }
        if text.live != nil {
            tally.pass(.live)
            return
        }
        let names = Bindings.names(in: english)
        if names.isEmpty {
            if looksChanging(english) { tally.fail(.live, item, english, Say.frozen) }
            return
        }
        if names.contains(where: { !$0.hasPrefix("field.") }) { tally.pass(.live) }
        checkBound(item, run, &tally, element: english)
    }

    /// A share beside a label that names another, or the battery with nothing to say so.
    private static func checkBound(_ item: AutoWire.Found, _ run: AutoWire.Run, _ tally: inout Tally, element: String) {
        guard let (current, kind) = run.boundShare(of: item.layer) else { return }
        let own = run.words(of: item.layer)
        if let named = run.namedShare(for: item, kind: kind, own: own), named != current.id, !run.isNamed(current, near: item, own: own) {
            tally.fail(.correct, item, element, Say.label)
        } else if current.id == "battery.level", !run.isNamed(current, near: item, own: own), !run.topics.has("battery"), !run.uses("battery.symbol") {
            tally.fail(.correct, item, element, Say.battery)
        } else {
            tally.pass(.correct)
        }
    }

    /// The nearest percent a text states or shows: the share as text says it, and whether it is live.
    private static func statedPercent(near item: AutoWire.Found, _ run: AutoWire.Run) -> (share: Double?, live: Bool)? {
        for other in run.neighbors(of: item) {
            guard case .text(let text) = other.layer.content else { continue }
            let english = text.value.resolved(language: "en").trimmingCharacters(in: .whitespaces)
            if Bindings.names(in: english).contains(where: { Capabilities.binding($0)?.isShare ?? false }) { return (nil, true) }
            guard AutoWire.TextShape.isPercent(english) || AutoWire.TextShape.percentLabel(english) != nil,
                  let range = english.range(of: "[0-9]{1,3}(?=\\s*[%٪]$)", options: .regularExpression), let number = Double(english[range]) else { continue }
            return (number / 100, false)
        }
        return nil
    }

    private static func checkLevel(_ value: String, kind: String, _ item: AutoWire.Found, _ run: AutoWire.Run, _ tally: inout Tally) {
        if Bindings.soleBinding(value) != nil {
            tally.pass(.live)
            checkBound(item, run, &tally, element: kind)
            return
        }
        // A bar that never moves (a full track, an empty one) is drawing, not data.
        guard let number = Double(value), number > 0, number < 1 else { return }
        tally.fail(.live, item, kind, Say.frozenLevel)
        checkVisual(number, item, run, &tally, element: kind)
    }

    private static func checkVisual(_ share: Double, _ item: AutoWire.Found, _ run: AutoWire.Run, _ tally: inout Tally, element: String) {
        guard let stated = statedPercent(near: item, run) else { return }
        if stated.live || abs((stated.share ?? share) - share) > 0.05 {
            tally.fail(.correct, item, element, Say.mismatch)
        } else {
            tally.pass(.correct)
        }
    }

    private static func checkDots(_ grid: DotGridLayer, _ item: AutoWire.Found, _ run: AutoWire.Run, _ tally: inout Tally) {
        if Bindings.soleBinding(grid.values) != nil {
            tally.pass(.live)
            checkBound(item, run, &tally, element: "dots")
            return
        }
        let digits = grid.values.filter { $0 == "0" || $0 == "1" }
        guard digits.contains("0"), digits.contains("1") else { return }
        if AutoWire.Run.isFillPattern(grid) {
            tally.fail(.live, item, "dots", Say.frozenLevel)
            checkVisual(Double(digits.filter { $0 == "1" }.count) / Double(digits.count), item, run, &tally, element: "dots")
        } else if grid.rows >= 8, grid.cols >= 8, run.artSet(for: item) != nil {
            tally.fail(.alive, item, "dots", Say.oneLook)
        }
    }

    private static func checkIcon(_ icon: IconLayer, _ item: AutoWire.Found, _ run: AutoWire.Run, _ tally: inout Tally, hasAction: (Frame) -> Bool) {
        let bound = Bindings.soleBinding(icon.symbol)
        if bound != nil {
            tally.pass(.alive)
        } else if let state = Capabilities.bindings.first(where: { capability in
            // Only on a card that shows that topic: a sun beside a prayer time isn't the weather.
            capability.type == "symbol" && !capability.id.hasPrefix("forecast.") && capability.icons.contains(icon.symbol)
                && run.showsTopic(AutoWire.Topics.prefix(capability.id))
        }), !(state.id == "volume.symbol" && run.topics.value("media") >= run.topics.value("volume")), item.frame.w >= 16 {
            tally.fail(.alive, item, icon.symbol, Say.oneLook)
            if state.id == "weather.symbol", run.uses("weather.cond") { tally.fail(.correct, item, icon.symbol, Say.mismatch) }
        }
        let symbol = bound.flatMap { raw in
            Capabilities.binding(raw)?.icons.first { icon in Capabilities.actions.contains { $0.icons.contains(icon) } }
        } ?? icon.symbol
        let tile = run.tile(around: item.frame)
        let area = tile ?? Frame(x: item.frame.x - 20, y: item.frame.y - 20, w: item.frame.w + 40, h: item.frame.h + 40)
        guard let action = run.actionFor(icons: [symbol], label: run.labels(in: area), isTile: tile != nil),
              !["media.open", "calendar.open", "weather.open", "compass.open", "reminders.open"].contains(action.id),
              !(tile == nil && (action.group == "open" || ["volume.up", "volume.down", "brightness.up", "brightness.down"].contains(action.id))) else { return }
        // The icon's own button, or one over the tile it sits on.
        if hasAction(item.frame) || tile.map(hasAction) == true { tally.pass(.interactive) } else { tally.fail(.interactive, item, icon.symbol, Say.noAction) }
    }

    /// A pill with a round knob is a switch: it needs a tap, and a look for each state.
    private static func checkSwitch(_ item: AutoWire.Found, _ run: AutoWire.Run, _ tally: inout Tally, hasAction: (Frame) -> Bool) {
        guard item.path.count == 1, case .shape(let track) = item.layer.content, track.kind == .capsule || track.kind == .roundedRect,
              item.layer.when == nil, item.frame.w >= 1.4 * item.frame.h, item.frame.h <= 70, item.frame.h >= 14 else { return }
        let knobs = run.spec.layers.filter { layer in
            guard case .shape(let shape) = layer.content, shape.kind == .circle else { return false }
            return AutoWire.Run.inside(layer.frame, item.frame) && layer.frame.h >= 0.5 * item.frame.h
        }
        guard !knobs.isEmpty else { return }
        if hasAction(item.frame) { tally.pass(.interactive) } else { tally.fail(.interactive, item, "switch", Say.noAction) }
        // A Shortcut has no state to read, so it has only one look to show.
        let action = run.spec.layers.compactMap { layer -> Capability? in
            guard case .button(let button) = layer.content, AutoWire.Run.inside(item.frame, layer.frame) else { return nil }
            return Capabilities.action(button.action.rawValue)
        }.first
        if knobs.contains(where: { $0.when != nil }) || (action != nil && action?.state == nil) {
            tally.pass(.alive)
        } else {
            tally.fail(.alive, item, "switch", Say.oneLook)
        }
    }

    private static func checkList(_ list: ListLayer, _ item: AutoWire.Found, _ tally: inout Tally, hasAction: (Frame) -> Bool) {
        let height = item.frame.h / Double(max(list.items.count, 1))
        for (index, row) in list.items.enumerated() {
            let detail = row.detail?.resolved(language: "en").trimmingCharacters(in: .whitespaces) ?? ""
            if row.done != nil {
                let frame = Frame(x: item.frame.x, y: item.frame.y + Double(index) * height, w: item.frame.w, h: height)
                if hasAction(frame) { tally.pass(.interactive) } else { tally.fail(.interactive, item, "checkbox", Say.noAction) }
                tally.pass(.alive)
            }
            if Bindings.names(in: row.title.resolved(language: "en")).isEmpty == false || Bindings.names(in: detail).isEmpty == false {
                tally.pass(.live)
            } else if AutoWire.TextShape.isClock(detail) {
                tally.fail(.live, item, detail, Say.frozen)
            }
        }
    }
}
