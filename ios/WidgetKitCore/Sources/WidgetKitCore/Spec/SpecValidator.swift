import Foundation

/// One problem found in a spec. `path` is JSON-like (`layers[3].font.family`).
public struct SpecIssue: Error, Sendable, Equatable, CustomStringConvertible {
    public let path: String
    public let message: String

    public init(_ path: String, _ message: String) {
        self.path = path
        self.message = message
    }

    public var description: String { path.isEmpty ? message : "\(path): \(message)" }
}

/// Every issue of one failed validation (a `Result` failure must be an `Error`).
public struct SpecIssues: Error, Sendable, Equatable, CustomStringConvertible {
    public let issues: [SpecIssue]

    public init(_ issues: [SpecIssue]) {
        self.issues = issues
    }

    public var description: String { SpecValidator.describe(issues) }
}

/// Validation rules of brief §4.6. Pure Swift, so the app, the widget and the tests share it.
/// `validate` returns the spec with frames clamped to the canvas, or every issue found.
public struct SpecValidator: Sendable {
    public enum Mode: Sendable {
        /// Bundled templates and specs the user edited.
        case standard
        /// AI output (brief §5.1, ADR-018): only `open.app` buttons; time, date, weather, battery,
        /// prayer and steps bindings; text and image fields only; photos only as `user_image`.
        case ai
    }

    public static let maxLayers = 30
    /// Layers counted with the children of stacks (M6.1).
    public static let maxTotalLayers = 60
    public static let maxStackDepth = 3
    public static let maxChildren = 12
    public static let maxTextLength = 200
    public static let fontSizes: ClosedRange<Double> = 6...200
    public static let minAIFontSize: Double = 11

    public let mode: Mode
    /// AI mode only: false skips the text-overlap rule, so the last answer can be repaired
    /// locally instead of failing (`AILayoutFix`, ADR-022).
    public let checksTextOverlaps: Bool

    public init(mode: Mode = .standard, checksTextOverlaps: Bool = true) {
        self.mode = mode
        self.checksTextOverlaps = checksTextOverlaps
    }

    public func validate(data: Data) -> Result<WidgetSpec, SpecIssues> {
        do {
            return validate(try JSONDecoder().decode(WidgetSpec.self, from: data))
        } catch let error as DecodingError {
            return .failure(SpecIssues([Self.issue(from: error)]))
        } catch {
            return .failure(SpecIssues([SpecIssue("", "not valid JSON")]))
        }
    }

    public func validate(_ spec: WidgetSpec) -> Result<WidgetSpec, SpecIssues> {
        var check = Check(spec: spec, mode: mode, checksTextOverlaps: checksTextOverlaps)
        check.run()
        guard check.issues.isEmpty else { return .failure(SpecIssues(check.issues)) }
        var normalized = spec
        let canvas = spec.family.canvas
        for index in normalized.layers.indices {
            normalized.layers[index].frame = normalized.layers[index].frame.clamped(to: canvas)
        }
        return .success(normalized)
    }

    /// Bindings AI output may use: time and date, weather, battery, prayer and Qibla, steps
    /// (not sleep), and text fields. Location, sleep and app data are left out.
    public static func allowsInAI(_ name: Bindings.Name) -> Bool {
        switch name {
        case .builtin(let raw):
            switch name.group {
            case .time, .weather, .device: return true
            // `prayer.next.key` only feeds `when` conditions, which AI output doesn't use.
            case .prayer: return raw != "prayer.next.key"
            case .health: return raw.hasPrefix("steps.")
            default: return false
            }
        case .field: return true
        case .daysUntil: return true   // needs a date field (countdowns, ADR-019)
        case .timezoneTime: return false
        }
    }

    /// Field types AI output may declare.
    public static let aiFieldTypes: Set<FieldSpec.Kind> = [.text, .date, .image]

    /// Readable text for the AI retry ("Your previous reply was not valid: …").
    public static func describe(_ issues: [SpecIssue]) -> String {
        issues.prefix(20).map(\.description).joined(separator: "; ")
    }

    static func issue(from error: DecodingError) -> SpecIssue {
        func path(_ codingPath: [CodingKey]) -> String {
            codingPath.reduce(into: "") { result, key in
                if let index = key.intValue {
                    result += "[\(index)]"
                } else {
                    result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
                }
            }
        }
        switch error {
        case .keyNotFound(let key, let context):
            let parent = path(context.codingPath)
            return SpecIssue(parent, "missing \"\(key.stringValue)\"")
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return SpecIssue(path(context.codingPath), "wrong type")
        case .dataCorrupted(let context):
            let detail = context.debugDescription
            if context.codingPath.isEmpty { return SpecIssue("", "not valid JSON") }
            if detail.contains("Cannot initialize") { return SpecIssue(path(context.codingPath), "unknown value") }
            return SpecIssue(path(context.codingPath), detail)
        @unknown default:
            return SpecIssue("", "invalid spec")
        }
    }
}

/// Spec and template IDs: letters, digits, dots, dashes, underscores; camelCase allowed
/// (`mono.clock.dotAnalog`, TEMPLATES.md). Also keeps file lookups inside the resource folder.
enum SpecValidatorID {
    static func isValid(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
                || $0 == "." || $0 == "-" || $0 == "_"
        }
    }
}

/// Collects issues for one spec.
// swiftlint:disable:next type_body_length
private struct Check {
    let spec: WidgetSpec
    let mode: SpecValidator.Mode
    let checksTextOverlaps: Bool
    var issues: [SpecIssue] = []

    init(spec: WidgetSpec, mode: SpecValidator.Mode, checksTextOverlaps: Bool) {
        self.spec = spec
        self.mode = mode
        self.checksTextOverlaps = checksTextOverlaps
    }

    mutating func fail(_ path: String, _ message: String) {
        issues.append(SpecIssue(path, message))
    }

    mutating func run() {
        if spec.schemaVersion != 1 { fail("schemaVersion", "must be 1") }
        if !Self.isValidID(spec.id) { fail("id", "use letters, digits, dots, dashes or underscores (max 64)") }
        if case .plain = spec.name { fail("name", "needs both \"en\" and \"ar\"") }
        for value in spec.name.allValues { text(path: "name", value, allowBindings: false) }
        checkBackground()
        checkFields()
        if spec.layers.isEmpty { fail("layers", "needs at least one layer") }
        if spec.layers.count > SpecValidator.maxLayers { fail("layers", "at most \(SpecValidator.maxLayers) layers") }
        if spec.allLayers.count > SpecValidator.maxTotalLayers {
            fail("layers", "at most \(SpecValidator.maxTotalLayers) layers counting the children of stacks")
        }
        for (index, layer) in spec.layers.enumerated() {
            checkLayer(layer, path: "layers[\(index)]")
        }
        if mode == .ai && checksTextOverlaps { checkTextOverlaps() }
    }

    /// AI output (M6.1): layers that show text must not cover each other (`SpecLayout`), checked on
    /// the frames as drawn, clamped to the canvas: a list taller than the widget slides up under
    /// the header (eval 2026-11-01).
    mutating func checkTextOverlaps() {
        let canvas = spec.family.canvas
        let drawn = spec.layers.map { layer -> Layer in
            var clamped = layer
            clamped.frame = layer.frame.clamped(to: canvas)
            return clamped
        }
        for (first, second) in SpecLayout.textOverlaps(in: drawn) {
            fail("layers[\(second)]", "its text overlaps layers[\(first)]; put texts that belong together in one stack, or move the frames apart")
        }
    }

    /// Children of a stack (M6.1): a natural size along any axis left at 0, the types a stack
    /// can lay out, and spacers only in vertical and horizontal stacks.
    mutating func checkStack(_ stack: StackLayer, path: String, depth: Int) {
        if depth > SpecValidator.maxStackDepth { fail(path, "stacks nest at most \(SpecValidator.maxStackDepth) deep") }
        count("\(path).children", stack.children.count, in: 1...SpecValidator.maxChildren)
        number("\(path).spacing", stack.spacing, in: 0...100)
        number("\(path).padding", stack.padding, in: 0...100)
        if stack.axis == .grid {
            count("\(path).columns", stack.columns ?? 2, in: 1...8)
        } else if stack.columns != nil {
            fail("\(path).columns", "only grids have columns")
        }
        for (index, child) in stack.children.enumerated() {
            let childPath = "\(path).children[\(index)]"
            let size = child.frame
            if ![size.w, size.h].allSatisfy(\.isFinite) || size.w < 0 || size.h < 0 {
                fail(childPath, "width and height must be positive numbers or absent")
            }
            switch child.content {
            case .text, .icon, .stack:
                break
            case .spacer:
                if stack.axis == .grid { fail(childPath, "grids can't hold spacers") }
            case .shape, .ring, .progressBar, .analogClock:
                // These fill what they're given, so they need a size along the stack's axis.
                if stack.axis == .horizontal ? size.w <= 0 : size.h <= 0 {
                    fail(childPath, stack.axis == .horizontal ? "needs a width inside a horizontal stack" : "needs a height inside this stack")
                }
            default:
                fail("\(childPath).type", "\"\(child.content.typeName)\" can't go in a stack; give it its own frame")
            }
            checkLayer(child, path: childPath, depth: depth)
        }
    }

    static func isValidID(_ id: String) -> Bool {
        SpecValidatorID.isValid(id)
    }

    // MARK: Values

    mutating func color(_ path: String, _ value: String?) {
        guard let value else { return }
        if HexColor.parse(value) == nil && !SpecTokens.isToken(value) {
            fail(path, "color must be #RRGGBB, #RRGGBBAA or a token (@\(SpecTokens.names.joined(separator: ", @")))")
        }
    }

    mutating func number(_ path: String, _ value: Double?, in range: ClosedRange<Double>) {
        guard let value else { return }
        if !value.isFinite || !range.contains(value) {
            fail(path, "must be between \(Self.format(range.lowerBound)) and \(Self.format(range.upperBound))")
        }
    }

    mutating func count(_ path: String, _ value: Int, in range: ClosedRange<Int>) {
        if !range.contains(value) { fail(path, "must be between \(range.lowerBound) and \(range.upperBound)") }
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    /// Length, remote URLs and bindings of a user-visible string.
    mutating func text(path: String, _ value: String, allowBindings: Bool = true, expecting kinds: Set<Bindings.Kind>? = nil) {
        if value.count > SpecValidator.maxTextLength { fail(path, "at most \(SpecValidator.maxTextLength) characters") }
        if Self.containsURL(value) { fail(path, "remote URLs are not allowed in specs") }
        let names = Bindings.names(in: value)
        if !allowBindings && !names.isEmpty {
            fail(path, "bindings are not allowed here")
            return
        }
        for raw in names {
            binding(path: path, raw, expecting: kinds)
        }
    }

    static func containsURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("://") || lower.hasPrefix("www.") || lower.contains(" www.")
    }

    /// Checks one binding name: known, allowed in this mode, field exists, right kind.
    mutating func binding(path: String, _ raw: String, expecting kinds: Set<Bindings.Kind>?) {
        guard let name = Bindings.Name(raw) else {
            fail(path, "unknown binding {{\(raw)}}")
            return
        }
        if mode == .ai, !SpecValidator.allowsInAI(name) {
            fail(path, "binding {{\(raw)}} is not allowed in AI output")
            return
        }
        let kind: Bindings.Kind
        switch name {
        case .field(let key), .timezoneTime(let key), .daysUntil(let key):
            guard let field = spec.field(key) else {
                fail(path, "{{\(raw)}} refers to a missing field")
                return
            }
            switch name {
            case .timezoneTime:
                if field.type != .timezone { fail(path, "{{\(raw)}} needs a timezone field") }
                kind = .text
            case .daysUntil:
                if field.type != .date { fail(path, "{{\(raw)}} needs a date field") }
                kind = .number
            default:
                if mode == .ai, field.type != .text && field.type != .date { fail(path, "AI output may only bind text and date fields") }
                kind = Self.kind(of: field)
            }
        case .builtin:
            if raw.trimmingCharacters(in: .whitespaces) == "counter.progress",
               spec.field("target")?.type != .number {
                fail(path, "{{counter.progress}} needs a number field with key \"target\"")
            }
            kind = name.builtinKind ?? .text
        }
        guard let kinds, !kinds.contains(kind) else { return }
        fail(path, "{{\(raw)}} doesn't give the right kind of value here")
    }

    static func kind(of field: FieldSpec) -> Bindings.Kind {
        switch field.type {
        case .date: .date
        case .number: .number
        case .icon: .symbol
        default: .text
        }
    }

    /// A `when` condition: a known binding, optionally negated or compared with a value.
    mutating func condition(path: String, _ text: String) {
        guard let condition = SpecCondition(text) else {
            fail(path, "use \"{{binding}}\", \"!{{binding}}\" or \"{{binding}} == value\"")
            return
        }
        binding(path: path, condition.binding, expecting: nil)
    }

    /// A value that must be exactly one binding of an allowed kind, or a literal accepted by `literal`.
    mutating func bindingOrLiteral(path: String, _ value: String, kinds: Set<Bindings.Kind>, literal: (String) -> Bool) {
        if let raw = Bindings.soleBinding(value) {
            binding(path: path, raw, expecting: kinds)
        } else if !literal(value) {
            fail(path, "must be a binding like {{…}} or a valid literal")
        }
    }

    // MARK: Parts

    mutating func checkBackground() {
        let background = spec.background
        switch background.type {
        case .solid:
            if background.color == nil { fail("background.color", "required for a solid background") }
            color("background.color", background.color)
        case .gradient:
            let colors = background.colors ?? []
            if !(2...4).contains(colors.count) { fail("background.colors", "a gradient needs 2 to 4 colors") }
            for (index, value) in colors.enumerated() { color("background.colors[\(index)]", value) }
            number("background.angle", background.angle, in: -360...360)
        }
        color("background.outerColor", background.outerColor)
    }

    mutating func checkFields() {
        var keys = Set<String>()
        for (index, field) in spec.fields.enumerated() {
            let path = "fields[\(index)]"
            if !Bindings.isValidKey(field.key) { fail("\(path).key", "letters, digits and underscores, starting with a letter") }
            if !keys.insert(field.key).inserted { fail("\(path).key", "duplicate key \"\(field.key)\"") }
            if mode == .ai, !SpecValidator.aiFieldTypes.contains(field.type) {
                fail("\(path).type", "AI output may only use text and image fields")
            }
            for value in field.label.allValues { text(path: "\(path).label", value, allowBindings: false) }
            for value in field.default?.allValues ?? [] {
                checkDefault(value, of: field, path: "\(path).default")
            }
        }
    }

    /// A default may be localized; each language's value must fit the field type.
    mutating func checkDefault(_ value: String, of field: FieldSpec, path: String) {
        if value.count > SpecValidator.maxTextLength { fail(path, "at most \(SpecValidator.maxTextLength) characters") }
        switch field.type {
        case .date: if FieldValues.date(value) == nil { fail(path, "must be an ISO 8601 date") }
        case .number: if Double(value) == nil { fail(path, "must be a number") }
        case .color: color(path, value)
        // Empty means "not set" (e.g. Day & Zone shows the device zone until the user picks one).
        case .timezone: if !value.isEmpty && TimeZone(identifier: value) == nil { fail(path, "unknown time zone") }
        // A user field may hold a URL (open.url), but a spec's default may not.
        case .url: if !value.isEmpty { fail(path, "URL fields can't have a default") }
        case .icon: if !Icons.isAllowed(value) { fail(path, "\"\(value)\" is not in the icon whitelist") }
        case .text, .city, .shortcut, .image:
            if Self.containsURL(value) { fail(path, "remote URLs are not allowed in specs") }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func checkLayer(_ layer: Layer, path: String, depth: Int = 0) {
        let frame = layer.frame
        // Children (depth > 0) are sized by their stack; `checkStack` checks their sizes.
        if depth == 0, ![frame.x, frame.y, frame.w, frame.h].allSatisfy(\.isFinite) || frame.w <= 0 || frame.h <= 0 {
            fail("\(path).frame", "w and h must be positive numbers")
        }
        number("\(path).opacity", layer.opacity, in: 0...1)
        if let when = layer.when { condition(path: "\(path).when", when) }
        if let rotation = layer.rotation {
            bindingOrLiteral(path: "\(path).rotation", rotation, kinds: [.number]) { value in
                Double(value).map { (-360...360).contains($0) } ?? false
            }
        }

        switch layer.content {
        case .unknown(let type):
            fail("\(path).type", "unknown layer type \"\(type)\"")
        case .text(let text):
            checkText(text, path: path)
        case .image(let image):
            if image.source != "user_image" && !Self.isAssetSource(image.source) {
                fail("\(path).source", "must be \"user_image\" or \"asset:<id>\"")
            } else if mode == .ai, image.source != "user_image" {
                fail("\(path).source", "AI output may only use \"user_image\"")
            }
            number("\(path).cornerRadius", image.cornerRadius, in: 0...200)
        case .shape(let shape):
            if shape.fill == nil && shape.stroke == nil { fail(path, "a shape needs a fill or a stroke") }
            color("\(path).fill", shape.fill)
            if let stroke = shape.stroke {
                color("\(path).stroke.color", stroke.color)
                number("\(path).stroke.width", stroke.width, in: 0...40)
                if let dash = stroke.dash, dash.count > 8 || dash.contains(where: { !(0...100).contains($0) }) {
                    fail("\(path).stroke.dash", "up to 8 lengths between 0 and 100")
                }
            }
            number("\(path).cornerRadius", shape.cornerRadius, in: 0...200)
        case .icon(let icon):
            if let raw = Bindings.soleBinding(icon.symbol) {
                binding(path: "\(path).symbol", raw, expecting: [.symbol])
            } else if !Icons.isAllowed(icon.symbol) {
                fail("\(path).symbol", "\"\(icon.symbol)\" is not in the icon whitelist")
            }
            number("\(path).size", icon.size, in: 4...200)
            color("\(path).color", icon.color)
        case .analogClock(let clock):
            for (key, value) in [("faceColor", clock.faceColor), ("tickColor", clock.tickColor), ("hourColor", clock.hourColor),
                                 ("minuteColor", clock.minuteColor), ("accentColor", clock.accentColor)] {
                color("\(path).\(key)", value)
            }
            if let zone = clock.timezone {
                bindingOrLiteral(path: "\(path).timezone", zone, kinds: [.text]) { TimeZone(identifier: $0) != nil }
                if let raw = Bindings.soleBinding(zone), case .field(let key)? = Bindings.Name(raw), spec.field(key)?.type != .timezone {
                    fail("\(path).timezone", "needs a timezone field")
                }
            }
        case .dotGrid(let grid):
            count("\(path).rows", grid.rows, in: 1...40)
            count("\(path).cols", grid.cols, in: 1...40)
            if grid.rows * grid.cols > 600 { fail(path, "at most 600 dots") }
            number("\(path).dotSize", grid.dotSize, in: 0.5...60)
            number("\(path).gap", grid.gap, in: 0...60)
            color("\(path).onColor", grid.onColor)
            color("\(path).offColor", grid.offColor)
            color("\(path).highlightColor", grid.highlightColor)
            bindingOrLiteral(path: "\(path).values", grid.values, kinds: [.levels]) { SpecLiterals.dotPattern($0) != nil }
        case .dotBars(let bars):
            count("\(path).bars", bars.bars, in: 1...31)
            count("\(path).maxDots", bars.maxDots, in: 1...24)
            bindingOrLiteral(path: "\(path).values", bars.values, kinds: [.levels]) { SpecLiterals.levels($0) != nil }
            color("\(path).color", bars.color)
            color("\(path).offColor", bars.offColor)
            color("\(path).highlightColor", bars.highlightColor)
            for labels in bars.labels?.allValues ?? [] { text(path: "\(path).labels", labels, expecting: [.text]) }
        case .ring(let ring):
            bindingOrLiteral(path: "\(path).progress", ring.progress, kinds: [.number]) { value in
                Double(value).map { (0...1).contains($0) } ?? false
            }
            color("\(path).color", ring.color)
            color("\(path).trackColor", ring.trackColor)
            number("\(path).lineWidth", ring.lineWidth, in: 0.5...60)
        case .forecastRow(let row):
            count("\(path).days", row.days, in: 1...7)
            color("\(path).color", row.color)
        case .calendarMonth(let calendar):
            font(calendar.font, path: "\(path).font")
            font(calendar.effectiveTitleFont, path: "\(path).titleFont")
            font(calendar.effectiveWeekdayFont, path: "\(path).weekdayFont")
            for (key, value) in [("color", calendar.color), ("titleColor", calendar.titleColor), ("weekdayColor", calendar.weekdayColor),
                                 ("weekendColor", calendar.weekendColor), ("todayColor", calendar.todayColor),
                                 ("todayTextColor", calendar.todayTextColor)] {
                color("\(path).\(key)", value)
            }
            for (index, day) in (calendar.weekendDays ?? []).enumerated()
            where !CalendarMonthLayer.weekdayKeys.contains(day.lowercased()) {
                fail("\(path).weekendDays[\(index)]", "use \(CalendarMonthLayer.weekdayKeys.joined(separator: ", "))")
            }
        case .list(let list):
            count("\(path).items", list.items.count, in: 1...ListLayer.maxItems)
            font(list.font, path: "\(path).font")
            for (key, value) in [("color", list.color), ("detailColor", list.detailColor), ("markerColor", list.markerColor),
                                 ("dividerColor", list.dividerColor)] {
                color("\(path).\(key)", value)
            }
            for (index, item) in list.items.enumerated() {
                let itemPath = "\(path).items[\(index)]"
                for value in item.title.allValues { text(path: "\(itemPath).title", value) }
                for value in item.detail?.allValues ?? [] { text(path: "\(itemPath).detail", value) }
                if let icon = item.icon, !Icons.isAllowed(icon) { fail("\(itemPath).icon", "\"\(icon)\" is not in the icon whitelist") }
                color("\(itemPath).color", item.color)
            }
        case .progressBar(let bar):
            bindingOrLiteral(path: "\(path).progress", bar.progress, kinds: [.number]) { value in
                Double(value).map { (0...1).contains($0) } ?? false
            }
            color("\(path).color", bar.color)
            color("\(path).trackColor", bar.trackColor)
            if let segments = bar.segments { count("\(path).segments", segments, in: 1...20) }
            number("\(path).cornerRadius", bar.cornerRadius, in: 0...200)
        case .button(let button):
            checkButton(button, path: path)
        case .stack(let stack):
            checkStack(stack, path: path, depth: depth + 1)
        case .spacer(let spacer):
            if depth == 0 { fail("\(path).type", "a spacer only goes inside a vertical or horizontal stack") }
            number("\(path).minLength", spacer.minLength, in: 0...200)
        }
    }

    mutating func checkText(_ text: TextLayer, path: String) {
        for value in text.value.allValues {
            self.text(path: "\(path).value", value)
        }
        font(text.font, path: "\(path).font")
        color("\(path).color", text.color)
        if let lines = text.maxLines { count("\(path).maxLines", lines, in: 1...10) }
        number("\(path).tracking", text.tracking, in: -10...40)
        if let live = text.live {
            switch live.kind {
            case .time:
                break
            case .timer, .relative:
                guard let target = live.target, let raw = Bindings.soleBinding(target) else {
                    fail("\(path).live.target", "needs a date binding like {{field.date}}")
                    return
                }
                binding(path: "\(path).live.target", raw, expecting: [.date])
            }
        }
    }

    /// A font from the registry, in range; at least 11 pt in AI output.
    mutating func font(_ font: FontSpec, path: String) {
        if !FontRegistry.families.contains(font.family) {
            fail("\(path).family", "unknown font \"\(font.family)\"; use \(FontRegistry.families.joined(separator: ", "))")
        }
        number("\(path).size", font.size, in: SpecValidator.fontSizes)
        if mode == .ai, font.size < SpecValidator.minAIFontSize {
            fail("\(path).size", "at least \(Int(SpecValidator.minAIFontSize))")
        }
    }

    mutating func checkButton(_ button: ButtonLayer, path: String) {
        if mode == .ai, button.action != .openApp {
            fail("\(path).action", "only open.app is allowed in AI output")
            return
        }
        switch button.action {
        case .openURL, .shortcutRun:
            let required: FieldSpec.Kind = button.action == .openURL ? .url : .shortcut
            guard let arg = button.arg, let raw = Bindings.soleBinding(arg),
                  case .field(let key)? = Bindings.Name(raw), let field = spec.field(key), field.type == required
            else {
                fail("\(path).arg", "must be {{field.<key>}} of a \(required.rawValue) field")
                return
            }
        case .counterIncrement, .counterReset, .counterNext, .stopwatchToggle, .openApp:
            if let arg = button.arg, !arg.isEmpty { text(path: "\(path).arg", arg) }
        }
    }

    static func isAssetSource(_ source: String) -> Bool {
        guard source.hasPrefix("asset:") else { return false }
        let id = source.dropFirst("asset:".count)
        return !id.isEmpty && isValidID(String(id))
    }
}
