import Foundation

/// The post-pass after AI output and imports (ADR-027): whatever the model left static becomes
/// live. Static text that looks like a time, date, %, temperature or duration gets a binding;
/// control-like layers get a button by icon and nearby text, using the catalog's keywords; static
/// progress on media, volume and battery cards gets the matching binding; drawn sliders become a
/// level bar with up/down tap zones. Every change is logged in `changes`. It never touches a
/// layer that is already wired. The Kotlin port (`design/AutoWire.kt`) must behave the same: both
/// run the vectors in `Tests/WidgetKitCoreTests/Fixtures/AutoWire`.
// swiftlint:disable:next type_body_length
public enum AutoWire {
    public struct Outcome: Sendable, Equatable {
        public var spec: WidgetSpec
        public var changes: [String]
    }

    /// One line of the model's wiring list: what it said an element shows.
    public struct WiringEntry: Decodable, Sendable, Equatable {
        public let element: String
        public let shows: String?
        public let tap: String?

        public init(element: String, shows: String?, tap: String? = nil) {
            self.element = element
            self.shows = shows
            self.tap = tap
        }
    }

    public static func apply(_ spec: WidgetSpec, inventory: [String] = [], wiring: [WiringEntry] = []) -> Outcome {
        var run = Run(spec: spec, inventory: inventory)
        run.sliders()
        run.modelWiring(wiring)
        run.forecastRows()
        run.texts()
        run.listRows()
        run.mediaTitles()
        run.symbols()
        run.stateSets()
        run.progress()
        run.correctShares()
        run.toggles()
        run.controls()
        run.sliderZones()
        run.stateLooks()
        run.card()
        run.dropUnusedFields()
        return Outcome(spec: run.spec, changes: run.changes)
    }

    /// How much a spec talks about each capability prefix (`media`, `volume`, `battery`…).
    public struct Topics: Sendable, Equatable {
        public private(set) var score: [String: Int] = [:]

        public init(corpus: String, icons: Set<String>) {
            for capability in Capabilities.bindings + Capabilities.actions {
                let prefix = Self.prefix(capability.id)
                let hits = capability.keywords.filter { Keyword.occurs($0, in: corpus) }.count
                    + 2 * capability.icons.filter(icons.contains).count
                if hits > 0 { score[prefix, default: 0] += hits }
            }
        }

        public static func prefix(_ id: String) -> String {
            String(id.prefix { $0 != "." })
        }

        public func has(_ prefix: String) -> Bool { (score[prefix] ?? 0) > 0 }
        public func value(_ prefix: String) -> Int { score[prefix] ?? 0 }

        /// The strongest of `prefixes`; ties go to the first listed.
        public func best(of prefixes: [String]) -> String? {
            var result: (String, Int)?
            for prefix in prefixes where has(prefix) && value(prefix) > (result?.1 ?? 0) {
                result = (prefix, value(prefix))
            }
            return result?.0
        }
    }

    /// Whole-word match for Latin keywords, substring for Arabic. `corpus` is lowercased.
    enum Keyword {
        static func occurs(_ keyword: String, in corpus: String) -> Bool {
            let word = keyword.lowercased()
            guard word.unicodeScalars.allSatisfy(\.isASCII) else { return corpus.contains(word) }
            var searchFrom = corpus.startIndex
            while let found = corpus.range(of: word, range: searchFrom..<corpus.endIndex) {
                let before = found.lowerBound > corpus.startIndex ? corpus[corpus.index(before: found.lowerBound)] : " "
                let after = found.upperBound < corpus.endIndex ? corpus[found.upperBound] : " "
                if !before.isLetter && !after.isLetter { return true }
                searchFrom = found.upperBound
            }
            return false
        }
    }

    /// Pure recognizers for a single text; the tests pin them.
    public enum TextShape {
        static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
                               "الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
        static let shortDays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
                             "november", "december"]
        static let shortMonths = ["jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec"]

        static func matches(_ text: String, _ pattern: String) -> Bool {
            text.range(of: pattern, options: .regularExpression) != nil
        }

        public static func isClock(_ text: String) -> Bool {
            matches(text, "^[0-2]?[0-9]:[0-5][0-9](:[0-5][0-9])?\\s*([AaPp]\\.?[Mm]\\.?|ص|م)?$")
        }

        public static func hasMeridiem(_ text: String) -> Bool {
            matches(text, "([AaPp]\\.?[Mm]\\.?|ص|م)$")
        }

        public static func isPercent(_ text: String) -> Bool { matches(text, "^[0-9]{1,3}\\s*[%٪]$") }
        public static func isTemperature(_ text: String) -> Bool { matches(text, "^-?[0-9]{1,3}\\s*°\\s*[CFcfمف]?$") }
        public static func isDuration(_ text: String) -> Bool {
            matches(text, "^[0-9]{1,3}\\s*([hH]|hr|hrs|س)\\s*([0-9]{1,2}\\s*([mM]|min|mins|د))?$")
                || matches(text, "^[0-9]{1,3}\\s*(min|mins|m|د)$")
        }

        public static func isStepCount(_ text: String) -> Bool { matches(text, "^[0-9]{1,3}(,[0-9]{3})+$") }

        /// `Thursday 22` → `{{date.EEEE}} {{date.d}}`; nil unless every word is a date part and
        /// at least one is a weekday or a month.
        public static func dateTemplate(_ text: String) -> String? {
            let words = text.split(whereSeparator: { $0 == " " || $0 == "," }).map { String($0).lowercased() }
            guard !words.isEmpty, words.count <= 4 else { return nil }
            var named = false
            var parts: [String] = []
            for word in words {
                if weekdays.contains(word) {
                    parts.append("{{date.EEEE}}")
                    named = true
                } else if shortDays.contains(word) {
                    parts.append("{{date.EEE}}")
                    named = true
                } else if months.contains(word) {
                    parts.append("{{date.MMMM}}")
                    named = true
                } else if shortMonths.contains(word) {
                    parts.append("{{date.MMM}}")
                    named = true
                } else if let number = Int(word), (1...31).contains(number) {
                    parts.append("{{date.d}}")
                } else if let number = Int(word), (1900...2100).contains(number) {
                    parts.append("{{date.yyyy}}")
                } else {
                    return nil
                }
            }
            return named ? parts.joined(separator: " ") : nil
        }
    }

    /// Where a stack's child sits, estimated: natural sizes along the axis, spacers take the rest.
    static func childFrames(of stack: StackLayer, in frame: Frame) -> [Frame] {
        guard stack.axis != .grid else {
            let columns = max(stack.columns ?? 2, 1)
            let rows = max(Int((Double(stack.children.count) / Double(columns)).rounded(.up)), 1)
            let (width, height) = (frame.w / Double(columns), frame.h / Double(rows))
            return stack.children.indices.map { index in
                Frame(x: frame.x + Double(index % columns) * width, y: frame.y + Double(index / columns) * height, w: width, h: height)
            }
        }
        let horizontal = stack.axis == .horizontal
        let padding = stack.padding ?? 0
        let spacing = stack.spacing ?? 4
        let length = (horizontal ? frame.w : frame.h) - 2 * padding
        func natural(_ child: Layer) -> Double {
            let given = horizontal ? child.frame.w : child.frame.h
            if given > 0 { return given }
            switch child.content {
            case .icon(let icon): return icon.size
            case .text(let text):
                let size = text.font.size
                let characters = Double(text.value.resolved(language: "en").count)
                return horizontal ? characters * size * 0.6 : size * 1.25
            case .spacer: return 0
            default: return 20
            }
        }
        let sizes = stack.children.map(natural)
        let spacers = stack.children.filter { if case .spacer = $0.content { true } else { false } }.count
        let used = sizes.reduce(0, +) + spacing * Double(max(stack.children.count - 1, 0))
        let free = max(length - used, 0)
        var cursor = padding
        if spacers == 0 {
            switch stack.justify {
            case .center?: cursor += free / 2
            case .end?: cursor += free
            default: break
            }
        }
        var frames: [Frame] = []
        for (index, child) in stack.children.enumerated() {
            var size = sizes[index]
            if case .spacer = child.content { size = free / Double(max(spacers, 1)) }
            if horizontal {
                frames.append(Frame(x: frame.x + cursor, y: frame.y, w: size, h: frame.h))
            } else {
                frames.append(Frame(x: frame.x, y: frame.y + cursor, w: frame.w, h: size))
            }
            cursor += size + spacing
        }
        return frames
    }

    /// One layer found while walking the spec, with its path and estimated frame.
    struct Found {
        let path: LayerEditing.Path
        let layer: Layer
        let frame: Frame
        let mirror: Bool?
    }

    static func walk(_ layers: [Layer], base: LayerEditing.Path = [], inherited: Frame? = nil, mirror: Bool? = nil) -> [Found] {
        var found: [Found] = []
        for (index, layer) in layers.enumerated() {
            let frame = inherited ?? layer.frame
            let path = base + [index]
            let mirrored = base.isEmpty ? layer.mirror : mirror
            found.append(Found(path: path, layer: layer, frame: frame, mirror: mirrored))
            if case .stack(let stack) = layer.content {
                let frames = childFrames(of: stack, in: frame)
                for (position, child) in stack.children.enumerated() {
                    found += walk([child], base: path, inherited: frames[position], mirror: mirrored).map { item in
                        var childPath = item.path
                        childPath[base.count + 1] = position
                        return Found(path: childPath, layer: item.layer, frame: item.frame, mirror: item.mirror)
                    }
                }
            }
        }
        return found
    }

    /// A planned tap area.
    struct Planned {
        var frame: Frame
        let action: Capability
        let mirror: Bool?
        let element: String
    }

    // swiftlint:disable:next type_body_length
    struct Run {
        var spec: WidgetSpec
        var changes: [String] = []
        /// Text fields a live value replaced.
        var replacedFields = Set<String>()
        let topics: Topics
        let canvas: CGSizeLike

        struct CGSizeLike {
            let width: Double
            let height: Double
        }

        init(spec: WidgetSpec, inventory: [String] = []) {
            self.spec = spec
            canvas = CGSizeLike(width: Double(spec.canvas.width), height: Double(spec.canvas.height))
            var words = spec.name.allValues + inventory
            var icons = Set<String>()
            for layer in spec.allLayers {
                switch layer.content {
                case .text(let text): words += text.value.allValues.filter { Bindings.names(in: $0).isEmpty }
                case .icon(let icon): icons.insert(icon.symbol)
                case .list(let list): words += list.items.flatMap { $0.title.allValues }
                default: break
                }
            }
            for field in spec.fields {
                words += [field.key] + field.label.allValues + (field.default?.allValues ?? [])
            }
            topics = Topics(corpus: words.joined(separator: "\n").lowercased(), icons: icons)
        }

        /// Switch-like icons on the card.
        var systemIcons: Int {
            spec.allLayers.filter { layer in
                guard case .icon(let icon) = layer.content else { return false }
                return Capabilities.actions.contains { $0.id.hasPrefix("system.toggle") && $0.icons.contains(icon.symbol) }
            }.count
        }

        var hasControls: Bool {
            spec.allLayers.contains { layer in
                guard case .icon(let icon) = layer.content else { return false }
                return Capabilities.actions.contains { $0.group == "media" && $0.icons.contains(icon.symbol) }
            }
        }

        func uses(_ binding: String) -> Bool {
            DataRequirements.bindingNames(in: spec).map { $0.trimmingCharacters(in: .whitespaces) }.contains(binding)
        }

        mutating func log(_ what: String, _ id: String) {
            changes.append("\(what) → \(id)")
        }

        mutating func update(_ path: LayerEditing.Path, _ change: (inout Layer) -> Void) {
            guard var layer = LayerEditing.layer(at: path, in: spec.layers) else { return }
            change(&layer)
            LayerEditing.replace(at: path, in: &spec.layers, with: layer)
        }

        mutating func setText(_ path: LayerEditing.Path, en: String, ar: String, was: String, id: String) {
            update(path) { layer in
                guard case .text(var text) = layer.content else { return }
                text.value = .localized(en: en, ar: ar)
                layer.content = .text(text)
            }
            log("text \"\(was)\"", id)
        }

        // MARK: The model's own list

        /// The model said what an element shows but left the layer static: "'12:30'" → {{timer.remaining}}.
        mutating func modelWiring(_ wiring: [WiringEntry]) {
            for entry in wiring {
                guard let shows = entry.shows, !shows.isEmpty, !Bindings.names(in: shows).isEmpty,
                      Bindings.names(in: shows).allSatisfy({ Capabilities.binding($0) != nil }) else { continue }
                let element = entry.element.lowercased()
                for item in AutoWire.walk(spec.layers) {
                    guard case .text(let text) = item.layer.content, text.live == nil else { continue }
                    let english = text.value.resolved(language: "en").trimmingCharacters(in: .whitespaces)
                    guard english.count >= 2, Bindings.names(in: english).isEmpty, element.contains(english.lowercased()) else { continue }
                    setText(item.path, en: shows, ar: shows, was: english, id: Bindings.names(in: shows).first ?? shows)
                    break
                }
            }
        }

        // MARK: Texts

        /// Binds static text that looks live, and field-bound text whose field names a live value.
        mutating func texts() {
            var clocks = 0
            for item in AutoWire.walk(spec.layers) {
                guard case .text(let text) = item.layer.content else { continue }
                let english = text.value.resolved(language: "en").trimmingCharacters(in: .whitespacesAndNewlines)
                // A countdown on a card called a timer follows the timer a tap starts, not a fixed date.
                if text.live?.kind == .timer, let target = text.live?.target, let raw = Bindings.soleBinding(target),
                   case .field(let key)? = Bindings.Name(raw), topics.has("timer") {
                    update(item.path) { layer in
                        guard case .text(var changed) = layer.content else { return }
                        changed.value = "{{timer.remaining}}"
                        changed.live = nil
                        layer.content = .text(changed)
                    }
                    replacedFields.insert(key)
                    log("countdown {{field.\(key)}}", "timer.remaining")
                    continue
                }
                guard text.live == nil else { continue }
                if let sole = Bindings.soleBinding(english), case .field(let key)? = Bindings.Name(sole) {
                    if let id = fieldBinding(key), Capabilities.binding(id) != nil {
                        let template = "{{\(id)}}"
                        replacedFields.insert(key)
                        setText(item.path, en: template, ar: template, was: "{{field.\(key)}}", id: id)
                    }
                    continue
                }
                guard Bindings.names(in: english).isEmpty, !english.isEmpty else { continue }
                if TextShape.isClock(english) {
                    clocks += 1
                    let id = clockBinding(index: clocks)
                    let template = id == "time.hh"
                        ? "{{time.hh}}:{{time.mm}}" + (TextShape.hasMeridiem(english) ? " {{time.ampm}}" : "") : "{{\(id)}}"
                    setText(item.path, en: template, ar: template, was: english, id: id)
                } else if TextShape.isPercent(english) {
                    // Only what a label names (ADR-028); unsure stays static, and DesignRules lists it.
                    if let id = shareBinding(for: item, kind: "text") {
                        setText(item.path, en: "{{\(id)}}%", ar: "{{\(id)}}%", was: english, id: id)
                    }
                } else if let label = TextShape.percentLabel(english) {
                    if let id = namedShare(for: item, kind: "text", own: label) {
                        setText(item.path, en: TextShape.replacingPercent(english, with: id), ar: TextShape.replacingPercent(text.value.resolved(language: "ar"), with: id),
                                was: english, id: id)
                    }
                } else if TextShape.isTemperature(english) {
                    let unit = english.hasSuffix("C") ? "C" : english.hasSuffix("F") ? "F" : ""
                    setText(item.path, en: "{{weather.temp}}°\(unit)", ar: "{{weather.temp}}°\(unit == "C" ? "م" : unit == "F" ? "ف" : "")",
                            was: english, id: "weather.temp")
                } else if TextShape.isStepCount(english), topics.has("steps") {
                    setText(item.path, en: "{{steps.today}}", ar: "{{steps.today}}", was: english, id: "steps.today")
                } else if TextShape.isDuration(english) {
                    if let id = durationBinding() {
                        setText(item.path, en: "{{\(id)}}", ar: "{{\(id)}}", was: english, id: id)
                    }
                } else if let template = TextShape.dateTemplate(english) {
                    setText(item.path, en: template, ar: template, was: english, id: "date")
                }
            }
        }

        /// Rows of a list: an agenda's events, open reminders, prayer times. Row N takes item N, and
        /// a row's own title may already name it.
        mutating func listRows() {
            var rowButtons: [Layer] = []
            defer { spec.layers += rowButtons }
            for item in AutoWire.walk(spec.layers) {
                guard case .list(let list) = item.layer.content else { continue }
                let prefix = topics.best(of: ["calendar", "tasks", "reminders"])
                var rows = list.items
                var changed = false
                for (index, row) in rows.enumerated() {
                    let title = row.title.resolved(language: "en")
                    let detail = row.detail?.resolved(language: "en").trimmingCharacters(in: .whitespaces) ?? ""
                    let lower = (title + " " + row.title.resolved(language: "ar")).lowercased()
                    if TextShape.isClock(detail), let prayer = Capabilities.bindings.first(where: { capability in
                        capability.type == "date" && capability.id.hasPrefix("prayer.") && capability.keywords.contains { Keyword.occurs($0, in: lower) }
                    }) {
                        rows[index].detail = .plain("{{\(prayer.id)}}")
                        changed = true
                        log("row \(title)", prayer.id)
                        continue
                    }
                    guard index < 4, let prefix else { continue }
                    let number = index + 1
                    if Bindings.names(in: title).isEmpty {
                        rows[index].title = .plain("{{\(prefix).\(number).title}}")
                        changed = true
                        log("row \(title)", "\(prefix).\(number).title")
                    }
                    // A task row is a checkbox: its tick follows the task, and a tap completes it.
                    if prefix == "tasks", rows[index].done == nil {
                        rows[index].done = "{{tasks.\(number).done}}"
                        changed = true
                        let height = item.frame.h / Double(max(rows.count, 1))
                        rowButtons.append(Layer(frame: Frame(x: item.frame.x, y: item.frame.y + Double(index) * height, w: item.frame.w, h: height),
                                                when: "{{tasks.\(number).title}}",
                                                content: .button(ButtonLayer(action: ButtonLayer.Action(rawValue: "task.toggle"), arg: "{{tasks.\(number).id}}"))))
                        log("row \(title)", "task.toggle")
                    }
                    if prefix == "calendar", TextShape.isClock(detail) {
                        rows[index].detail = .plain("{{calendar.\(number).time}}")
                        changed = true
                        log("row \(detail)", "calendar.\(number).time")
                    }
                }
                guard changed else { continue }
                update(item.path) { layer in
                    guard case .list(var content) = layer.content else { return }
                    content.items = rows
                    layer.content = .list(content)
                }
            }
        }

        /// On a media card "1:42" and "4:23" are positions; on a timer the time left; else the clock.
        func clockBinding(index: Int) -> String {
            if hasControls { return index == 1 && !uses("media.duration") ? "media.elapsed" : "media.duration" }
            if topics.has("timer") { return "timer.remaining" }
            return "time.hh"
        }

        func durationBinding() -> String? {
            switch topics.best(of: ["sleep", "focus", "timer"]) {
            case "sleep": "sleep.lastNight"
            case "focus": "focus.today"
            case "timer": "timer.remaining"
            default: nil
            }
        }

        /// A text field whose key or label names a value of a topic this widget is about.
        func fieldBinding(_ key: String) -> String? {
            guard let field = spec.field(key), field.type == .text else { return nil }
            let words = ([key] + field.label.allValues).joined(separator: " ").lowercased()
            for capability in Capabilities.bindings where !capability.parametric && capability.layers.contains("text")
                && capability.ai && topics.has(Topics.prefix(capability.id)) {
                if capability.keywords.contains(where: { Keyword.occurs($0, in: words) }) { return capability.id }
            }
            return nil
        }

        /// A media card names its song in plain text: the biggest text becomes the title, the
        /// next one the artist.
        mutating func mediaTitles() {
            guard hasControls || uses("media.progress"), !uses("media.title") else { return }
            let generic = ["music", "player", "now playing", "playing", "موسيقى", "مشغل", "مشغّل"]
            let texts = AutoWire.walk(spec.layers).filter { item in
                guard case .text(let text) = item.layer.content else { return false }
                let value = text.value.resolved(language: "en").lowercased()
                return !value.isEmpty && !generic.contains { value.contains($0) }
                    && (Bindings.names(in: value).isEmpty || value.hasPrefix("{{field."))
                    && !value.contains(where: \.isNumber)
            }
            let sorted = texts.sorted { first, second in
                guard case .text(let a) = first.layer.content, case .text(let b) = second.layer.content else { return false }
                return a.font.size > b.font.size
            }
            for (item, id) in zip(sorted, ["media.title", "media.artist"]) where !uses(id) {
                if let raw = Bindings.soleBinding(text(item)), case .field(let key)? = Bindings.Name(raw) { replacedFields.insert(key) }
                setText(item.path, en: "{{\(id)}}", ar: "{{\(id)}}", was: text(item), id: id)
            }
        }

        func text(_ item: Found) -> String {
            if case .text(let text) = item.layer.content { return text.value.resolved(language: "en") }
            return ""
        }

        /// A play icon, a battery or a speaker follows the live state.
        mutating func symbols() {
            for item in AutoWire.walk(spec.layers) {
                guard case .icon(let icon) = item.layer.content, Bindings.soleBinding(icon.symbol) == nil else { continue }
                guard let binding = Capabilities.bindings.first(where: {
                    $0.type == "symbol" && $0.icons.contains(icon.symbol) && topics.has(Topics.prefix($0.id))
                }) else { continue }
                // A speaker in the media row stays a speaker; only a level widget's icon follows it.
                if binding.id == "volume.symbol", topics.value("media") >= topics.value("volume") { continue }
                update(item.path) { layer in
                    guard case .icon(var changed) = layer.content else { return }
                    changed.symbol = "{{\(binding.id)}}"
                    layer.content = .icon(changed)
                }
                log("icon \(icon.symbol)", binding.id)
            }
            for item in AutoWire.walk(spec.layers) where item.layer.rotation == nil {
                guard case .icon(let icon) = item.layer.content, ["location.north.fill", "safari.fill"].contains(icon.symbol),
                      let prefix = topics.best(of: ["compass", "qibla"]) else { continue }
                let id = prefix == "qibla" ? "qibla.bearing" : "compass.north"
                update(item.path) { $0.rotation = "{{\(id)}}" }
                log("arrow \(icon.symbol)", id)
            }
        }

        // MARK: Progress

        mutating func progress() {
            for item in AutoWire.walk(spec.layers) {
                switch item.layer.content {
                case .progressBar(let bar) where Bindings.soleBinding(bar.progress) == nil:
                    guard let id = shareBinding(for: item, kind: "progressBar") else { continue }
                    update(item.path) { layer in
                        guard case .progressBar(var changed) = layer.content else { return }
                        changed.progress = "{{\(id)}}"
                        layer.content = .progressBar(changed)
                    }
                    log("progress bar \(bar.progress)", id)
                case .ring(let ring) where Bindings.soleBinding(ring.progress) == nil:
                    guard let id = shareBinding(for: item, kind: "ring") else { continue }
                    update(item.path) { layer in
                        guard case .ring(var changed) = layer.content else { return }
                        changed.progress = "{{\(id)}}"
                        layer.content = .ring(changed)
                    }
                    log("ring \(ring.progress)", id)
                case .dotGrid(let grid) where Bindings.soleBinding(grid.values) == nil:
                    // A label that names a share binds dots of any pattern: 15 of 48 lit is still a level.
                    let named = namedShare(for: item, kind: "dotGrid")
                    guard named != nil || Self.isFillPattern(grid), let id = named ?? shareBinding(for: item, kind: "dotGrid") else { continue }
                    update(item.path) { layer in
                        guard case .dotGrid(var changed) = layer.content else { return }
                        changed.values = "{{\(id)}}"
                        layer.content = .dotGrid(changed)
                    }
                    log("dots \(grid.values)", id)
                default:
                    break
                }
            }
        }

        /// Lit dots that run from the start of each row and then stop look like a level.
        static func isFillPattern(_ grid: DotGridLayer) -> Bool {
            let digits = Array(grid.values.filter { $0 == "0" || $0 == "1" })
            guard digits.contains("0"), digits.contains("1"), grid.cols > 0 else { return false }
            let rows = stride(from: 0, to: digits.count, by: grid.cols).map { Array(digits[$0..<min($0 + grid.cols, digits.count)]) }
            return rows.allSatisfy { row in
                guard let firstOff = row.firstIndex(of: "0") else { return true }
                return !row[firstOff...].contains("1")
            }
        }

        // MARK: Sliders

        /// Thin shapes on a volume or brightness card are sliders: fill and track (a shape or a
        /// dot column) become one level bar.
        mutating func sliders() {
            guard topics.has("volume") || topics.has("brightness") else { return }
            var taken = Set<Int>()
            var bars: [(index: Int, layer: Layer)] = []
            var removed = Set<Int>()
            var level = 0
            for (index, layer) in spec.layers.enumerated() where !taken.contains(index) {
                // A badge holds a text; a slider holds none.
                guard Self.isSliderPiece(layer), labels(in: layer.frame).isEmpty else { continue }
                let vertical = layer.frame.h > layer.frame.w
                var parts = [index]
                var union = layer.frame
                for (other, candidate) in spec.layers.enumerated() where other != index && !taken.contains(other) {
                    let thin = Self.isSliderPiece(candidate) || Self.isDotTrack(candidate)
                    if thin, vertical == (candidate.frame.h > candidate.frame.w), Self.aligned(layer.frame, candidate.frame, vertical: vertical) {
                        parts.append(other)
                        union = Self.union(union, candidate.frame)
                    }
                }
                let id = sliderBinding(near: union, position: level)
                level += 1
                taken.formUnion(parts)
                removed.formUnion(parts)
                var color = "@fg"
                var track = "@dim"
                if case .shape(let shape) = layer.content, let fill = shape.fill { color = fill }
                for part in parts {
                    if case .dotGrid(let grid) = spec.layers[part].content { track = grid.offColor }
                }
                let bar = ProgressBarLayer(progress: "{{\(id)}}", color: color, trackColor: track, vertical: vertical ? true : nil)
                var frame = union
                if vertical { frame.w = max(frame.w, 12) } else { frame.h = max(frame.h, 8) }
                bars.append((index, Layer(frame: frame, mirror: layer.mirror, content: .progressBar(bar))))
                log("drawn slider", id)
            }
            guard !bars.isEmpty else { return }
            var layers: [Layer] = []
            for (index, layer) in spec.layers.enumerated() {
                if let bar = bars.first(where: { $0.index == index }) { layers.append(bar.layer) } else if !removed.contains(index) { layers.append(layer) }
            }
            spec.layers = layers
        }

        static func isSliderPiece(_ layer: Layer) -> Bool {
            guard case .shape(let shape) = layer.content, shape.kind == .capsule || shape.kind == .roundedRect || shape.kind == .rect,
                  shape.fill != nil else { return false }
            let long = max(layer.frame.w, layer.frame.h)
            let short = min(layer.frame.w, layer.frame.h)
            return short > 1.5 && short <= 44 && long >= 4 * short && long >= 60
        }

        static func isDotTrack(_ layer: Layer) -> Bool {
            guard case .dotGrid(let grid) = layer.content else { return false }
            return grid.rows == 1 || grid.cols == 1
        }

        static func aligned(_ a: Frame, _ b: Frame, vertical: Bool) -> Bool {
            let (first, second) = vertical ? (a.x + a.w / 2, b.x + b.w / 2) : (a.y + a.h / 2, b.y + b.h / 2)
            return abs(first - second) <= max(vertical ? max(a.w, b.w) : max(a.h, b.h), 8) / 2 + 2
        }

        static func union(_ a: Frame, _ b: Frame) -> Frame {
            let x = min(a.x, b.x)
            let y = min(a.y, b.y)
            return Frame(x: x, y: y, w: max(a.x + a.w, b.x + b.w) - x, h: max(a.y + a.h, b.y + b.h) - y)
        }

        /// By the icon beside it; otherwise media volume, then ringer, then brightness in order.
        func sliderBinding(near frame: Frame, position: Int) -> String {
            var bestIcon: String?
            var bestDistance = Double.infinity
            for item in AutoWire.walk(spec.layers) {
                guard case .icon(let icon) = item.layer.content else { continue }
                let distance = hypot(item.frame.x + item.frame.w / 2 - (frame.x + frame.w / 2),
                                     item.frame.y + item.frame.h / 2 - (frame.y + frame.h / 2))
                let reach = max(frame.w, frame.h) / 2 + 60
                if distance < min(bestDistance, reach) {
                    bestDistance = distance
                    bestIcon = icon.symbol
                }
            }
            if let bestIcon, let match = Capabilities.bindings.first(where: {
                $0.type == "number" && $0.layers.contains("progressBar") && $0.icons.contains(bestIcon)
                    && ["volume", "brightness"].contains(Topics.prefix($0.id))
            }), !uses(match.id) { return match.id }
            let order = topics.has("volume") ? ["volume.level", "volume.ring", "brightness.level"] : ["brightness.level", "volume.level"]
            return order[min(position, order.count - 1)]
        }

        /// Up and down zones on every level bar for volume, ringer and brightness.
        mutating func sliderZones() {
            let pairs = ["volume.level": ("volume.up", "volume.down"), "volume.ring": ("volume.ringUp", "volume.ringDown"),
                         "brightness.level": ("brightness.up", "brightness.down")]
            var planned: [Planned] = []
            for layer in spec.layers {
                guard case .progressBar(let bar) = layer.content, let raw = Bindings.soleBinding(bar.progress),
                      let pair = pairs[raw.trimmingCharacters(in: .whitespaces)], let up = Capabilities.action(pair.0),
                      let down = Capabilities.action(pair.1) else { continue }
                let frame = layer.frame
                if buttons.contains(where: { $0.action == up.id || $0.action == down.id }) { continue }
                if bar.vertical == true {
                    planned.append(Planned(frame: Frame(x: frame.x - 10, y: frame.y, w: frame.w + 20, h: frame.h / 2), action: up, mirror: nil, element: raw))
                    planned.append(Planned(frame: Frame(x: frame.x - 10, y: frame.y + frame.h / 2, w: frame.w + 20, h: frame.h / 2), action: down,
                                           mirror: nil, element: raw))
                } else {
                    planned.append(Planned(frame: Frame(x: frame.x, y: frame.y - 10, w: frame.w / 2, h: frame.h + 20), action: down, mirror: layer.mirror,
                                           element: raw))
                    planned.append(Planned(frame: Frame(x: frame.x + frame.w / 2, y: frame.y - 10, w: frame.w / 2, h: frame.h + 20), action: up,
                                           mirror: layer.mirror, element: raw))
                }
            }
            add(planned)
        }

        // MARK: Toggles

        /// A pill with a round knob is a switch: tap = its toggle, and the knob moves with the state.
        mutating func toggles() {
            let layers = spec.layers
            var extra: [Layer] = []
            var planned: [Planned] = []
            for (index, layer) in layers.enumerated() {
                guard case .shape(let track) = layer.content, track.kind == .capsule || track.kind == .roundedRect,
                      layer.frame.w >= 1.4 * layer.frame.h, layer.frame.h <= 70 else { continue }
                guard let knobIndex = layers.indices.first(where: { other in
                    guard other != index, case .shape(let shape) = layers[other].content, shape.kind == .circle else { return false }
                    return Self.inside(layers[other].frame, layer.frame) && layers[other].frame.h >= 0.5 * layer.frame.h
                }), layers[knobIndex].when == nil else { continue }
                let label = labels(in: layer.frame, wide: true)
                let icons = iconSymbols(in: layer.frame)
                guard let action = actionFor(icons: icons, label: label, isTile: true, requireSystem: true) else { continue }
                planned.append(Planned(frame: layer.frame, action: action, mirror: layer.mirror, element: "switch"))
                log("switch", action.id)
                guard let state = action.state else { continue }
                let knob = layers[knobIndex]
                let isOffLook = knob.frame.x + knob.frame.w / 2 < layer.frame.x + layer.frame.w / 2
                // The knob's other end, the same distance from the track's edge.
                let shift = isOffLook ? (layer.frame.x + layer.frame.w - (knob.frame.x + knob.frame.w)) - (knob.frame.x - layer.frame.x)
                    : (layer.frame.x - knob.frame.x) + (layer.frame.x + layer.frame.w - (knob.frame.x + knob.frame.w))
                var pieces = [knobIndex]
                pieces += layers.indices.filter { if case .icon = layers[$0].content { Self.inside(layers[$0].frame, knob.frame) } else { false } }
                for piece in pieces {
                    var moved = layers[piece]
                    moved.frame.x += shift
                    moved.when = isOffLook ? "{{\(state)}}" : "!{{\(state)}}"
                    extra.append(moved)
                    update([piece]) { $0.when = isOffLook ? "!{{\(state)}}" : "{{\(state)}}" }
                }
            }
            insertDrawn(extra)
            add(planned)
        }

        /// Drawn layers go under the tap areas: anything on top of a button takes its taps.
        mutating func insertDrawn(_ layers: [Layer]) {
            let index = spec.layers.firstIndex { if case .button = $0.content { true } else { false } } ?? spec.layers.count
            spec.layers.insert(contentsOf: layers, at: index)
        }

        /// A switch drawn inside a stack can't be moved, so its on look is laid over it: an accent
        /// track with its knob at the end, shown only while the state is on.
        mutating func stateLooks() {
            var looks: [Layer] = []
            for button in buttons {
                guard let state = Capabilities.action(button.action)?.state, !uses(state) else { continue }
                let track = AutoWire.walk(spec.layers).first { item in
                    guard case .shape(let shape) = item.layer.content, shape.kind == .capsule || shape.kind == .roundedRect else { return false }
                    return Self.inside(item.frame, button.frame) && item.frame.w >= 1.4 * item.frame.h && item.frame.h > 8
                }
                guard let track else { continue }
                let frame = track.frame
                let inset = frame.h * 0.1
                let knob = Frame(x: frame.x + frame.w - frame.h + inset, y: frame.y + inset, w: frame.h - 2 * inset, h: frame.h - 2 * inset)
                looks.append(Layer(frame: frame, mirror: track.mirror, when: "{{\(state)}}", content: .shape(ShapeLayer(kind: .capsule, fill: "@accent"))))
                looks.append(Layer(frame: knob, mirror: track.mirror, when: "{{\(state)}}", content: .shape(ShapeLayer(kind: .circle, fill: "#FFFFFF"))))
                log("switch look", state)
            }
            insertDrawn(looks)
        }

        static func inside(_ inner: Frame, _ outer: Frame) -> Bool {
            let (x, y) = (inner.x + inner.w / 2, inner.y + inner.h / 2)
            return x >= outer.x && x <= outer.x + outer.w && y >= outer.y && y <= outer.y + outer.h
        }

        func labels(in frame: Frame, wide: Bool = false) -> String {
            let area = wide ? Frame(x: 0, y: frame.y - 24, w: canvas.width, h: frame.h + 48) : frame
            return AutoWire.walk(spec.layers).compactMap { item -> String? in
                guard case .text(let text) = item.layer.content, Self.inside(item.frame, area) else { return nil }
                return text.value.allValues.joined(separator: " ")
            }.joined(separator: " ").lowercased()
        }

        func iconSymbols(in frame: Frame) -> [String] {
            AutoWire.walk(spec.layers).compactMap { item in
                guard case .icon(let icon) = item.layer.content, Self.inside(item.frame, frame) else { return nil }
                return icon.symbol
            }
        }

        // MARK: Controls

        /// The best action for icons and nearby words. A status icon on a plain card (a Wi-Fi mark
        /// in a clock's corner) gets none: it must sit on a tile or the card must be about it.
        func actionFor(icons: [String], label: String, isTile: Bool, requireSystem: Bool = false) -> Capability? {
            var best: (Capability, Int)?
            for capability in Capabilities.actions where capability.ai {
                let prefix = capability.id.hasPrefix("system.toggle") ? "system" : Topics.prefix(capability.id)
                if requireSystem, !["system", "volume"].contains(prefix) { continue }
                let iconHit = !capability.icons.filter(icons.contains).isEmpty
                let wordHit = !label.isEmpty && capability.keywords.contains { Keyword.occurs($0, in: label) }
                guard iconHit || (wordHit && isTile) else { continue }
                let topic = topics.value(prefix)
                // A lone status icon on a plain card is not a switch; a row of them is.
                let allowed = isTile || (prefix == "system" ? systemIcons >= 3 : topic > 0)
                guard allowed else { continue }
                let score = (wordHit ? 100 : 0) + (iconHit ? 10 : 0) + min(topic, 9)
                if score > (best?.1 ?? 0) { best = (capability, score) }
            }
            return best?.0
        }

        /// The tile an element sits on: the smallest shape around it, not the whole card.
        func tile(around frame: Frame) -> Frame? {
            let limit = canvas.width * canvas.height * 0.5
            return spec.allLayers.compactMap { layer -> Frame? in
                guard case .shape(let shape) = layer.content, shape.fill != nil || shape.stroke != nil, layer.when == nil,
                      layer.frame.w * layer.frame.h <= limit, layer.frame.w >= frame.w, layer.frame.h >= frame.h,
                      Self.inside(frame, layer.frame) else { return nil }
                return layer.frame
            }.min { $0.w * $0.h < $1.w * $1.h }
        }

        var buttons: [(index: Int, frame: Frame, action: String)] {
            spec.layers.enumerated().compactMap { index, layer in
                if case .button(let button) = layer.content { return (index, layer.frame, button.action.rawValue) }
                return nil
            }
        }

        mutating func controls() {
            var planned: [Planned] = []
            var seen: [Frame] = []
            func covered(_ frame: Frame, buttons: [(index: Int, frame: Frame, action: String)]) -> Bool {
                buttons.contains { $0.action != "open.app" && Self.inside(frame, $0.frame) }
            }
            for item in AutoWire.walk(spec.layers) {
                var symbol: String?
                var glyphAction: Capability?
                switch item.layer.content {
                case .icon(let icon):
                    symbol = Bindings.soleBinding(icon.symbol).flatMap { raw in
                        Capabilities.binding(raw)?.icons.first { icon in Capabilities.actions.contains { $0.icons.contains(icon) } }
                    } ?? icon.symbol
                case .text(let text):
                    let scalars = text.value.resolved(language: "en").unicodeScalars.filter { $0 != "\u{FE0E}" && $0 != "\u{FE0F}" }
                    let value = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
                    glyphAction = Capabilities.actions.first { $0.glyphs.contains(value) }
                    if glyphAction == nil, let tile = tile(around: item.frame), Bindings.names(in: value).isEmpty, !value.isEmpty,
                       !seen.contains(where: { Self.inside(tile, $0) && Self.inside($0, tile) }),
                       let action = actionFor(icons: iconSymbols(in: tile), label: value.lowercased(), isTile: true),
                       action.group != "app", !covered(tile, buttons: buttons) {
                        seen.append(tile)
                        planned.append(Planned(frame: tile, action: action, mirror: item.mirror, element: value))
                        continue
                    }
                default:
                    continue
                }
                guard symbol != nil || glyphAction != nil else { continue }
                let tile = tile(around: item.frame)
                let label = labels(in: tile ?? Frame(x: item.frame.x - 20, y: item.frame.y - 20, w: item.frame.w + 40, h: item.frame.h + 40))
                let action = glyphAction ?? actionFor(icons: symbol.map { [$0] } ?? [], label: label, isTile: tile != nil)
                guard let action else { continue }
                // A level widget's icons label the sliders; the header icon of a card isn't a control.
                if ["volume.up", "volume.down", "brightness.up", "brightness.down"].contains(action.id), tile == nil { continue }
                if action.id == "media.open" || action.id == "calendar.open" || action.id == "weather.open" { continue }
                if action.id == "compass.open" || action.id == "reminders.open" { continue }
                let frame = (tile ?? Self.padded(item.frame)).clamped(width: canvas.width, height: canvas.height)
                if covered(frame, buttons: buttons) { continue }
                if seen.contains(where: { Self.inside(frame, $0) && Self.inside($0, frame) }) { continue }
                seen.append(frame)
                planned.append(Planned(frame: frame, action: action, mirror: item.mirror, element: symbol ?? "glyph"))
            }
            add(planned)
        }

        /// A tap area at least 36 units on each side.
        static func padded(_ frame: Frame) -> Frame {
            let width = max(frame.w, 36)
            let height = max(frame.h, 36)
            return Frame(x: frame.x + frame.w / 2 - width / 2, y: frame.y + frame.h / 2 - height / 2, w: width, h: height)
        }

        /// Adds tap areas; an `open.app` button under one of them is replaced by them.
        mutating func add(_ planned: [Planned]) {
            guard !planned.isEmpty else { return }
            spec.layers.removeAll { layer in
                guard case .button(let button) = layer.content, button.action == .openApp else { return false }
                return planned.contains { Self.inside($0.frame, layer.frame) }
            }
            for item in planned {
                let button = ButtonLayer(action: ButtonLayer.Action(rawValue: item.action.id), arg: arg(for: item))
                spec.layers.append(Layer(frame: item.frame, mirror: item.mirror, content: .button(button)))
                if !changes.contains(where: { $0.hasSuffix("→ \(item.action.id)") && $0.hasPrefix("switch") }) {
                    log("control \(item.element)", item.action.id)
                }
            }
        }

        /// Actions that need a value get a field for it (a Shortcut named after the tile).
        mutating func arg(for item: Planned) -> String? {
            guard let kind = item.action.argFieldKind else { return nil }
            var index = 1
            let base = kind == .shortcut ? "shortcut" : kind == .url ? "link" : "value"
            while spec.field("\(base)\(index)") != nil { index += 1 }
            let key = "\(base)\(index)"
            let label = item.action.title
            let value: LocalizedText? = kind == .shortcut ? .plain(item.element) : kind == .text ? .plain("") : nil
            spec.fields.append(FieldSpec(key: key, type: kind, label: label, default: value))
            return "{{field.\(key)}}"
        }

        // MARK: The whole card

        /// A card with nothing tappable opens what it shows.
        mutating func card() {
            let map = ["compass": "compass.open", "qibla": "compass.open", "media": "media.open", "weather": "weather.open",
                       "calendar": "calendar.open", "reminders": "reminders.open", "timer": "timer.toggle", "stopwatch": "stopwatch.toggle"]
            guard !buttons.contains(where: { $0.action != "open.app" }),
                  // The card is about what it shows most: a sleep card's temperature doesn't open the weather.
                  let prefix = topics.best(of: ["compass", "qibla", "timer", "stopwatch", "media", "calendar", "reminders", "sleep", "steps", "focus", "weather"]),
                  let id = map[prefix], let action = Capabilities.action(id) else { return }
            let whole = Frame(x: 0, y: 0, w: canvas.width, h: canvas.height)
            spec.layers.removeAll { if case .button(let button) = $0.content { button.action == .openApp } else { false } }
            spec.layers.append(Layer(frame: whole, content: .button(ButtonLayer(action: ButtonLayer.Action(rawValue: action.id)))))
            log("whole card", action.id)
        }

        /// A field whose text became a live value would only clutter the editor.
        mutating func dropUnusedFields() {
            let used = Set(DataRequirements.bindingNames(in: spec).map { $0.trimmingCharacters(in: .whitespaces) })
            spec.fields.removeAll { replacedFields.contains($0.key) && !used.contains("field.\($0.key)") }
        }
    }
}

extension Frame {
    /// Moved and shrunk to fit inside `width` × `height`.
    func clamped(width: Double, height: Double) -> Frame {
        let w = min(self.w, width)
        let h = min(self.h, height)
        return Frame(x: min(max(x, 0), width - w), y: min(max(y, 0), height - h), w: w, h: h)
    }
}
