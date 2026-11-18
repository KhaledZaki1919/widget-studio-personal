import Foundation

/// The post-pass steps of the product rules (ADR-028). A percent, ring, bar or dot grid takes the
/// binding its nearest label names, never a default: with no label and no topic it stays static and
/// `DesignRules` lists it. A row of weather icons follows each day. A frozen mood or illustration
/// becomes a state layer from the catalog. Ported in `AutoWireRules.kt`, same vectors.
extension AutoWire.TextShape {
    /// `Year 53%` → `Year`; nil unless a label comes before the percent.
    public static func percentLabel(_ text: String) -> String? {
        guard matches(text, "^.*[^0-9٠-٩\\s]\\s*[0-9٠-٩]{1,3}\\s*[%٪]$") else { return nil }
        return text.replacingOccurrences(of: "\\s*[0-9٠-٩]{1,3}\\s*[%٪]$", with: "", options: .regularExpression)
    }

    /// The number of a percent replaced by a binding, in either language's digits.
    static func replacingPercent(_ text: String, with id: String) -> String {
        text.replacingOccurrences(of: "[0-9٠-٩]{1,3}(?=\\s*[%٪]$)", with: "{{\(id)}}", options: .regularExpression)
    }

    static func isDayName(_ text: String) -> Bool {
        let word = text.lowercased()
        return shortDays.contains(word) || weekdays.contains(word)
    }

    static func isToday(_ text: String) -> Bool {
        ["today", "now", "اليوم", "الآن"].contains(text.lowercased())
    }
}

extension AutoWire.Run {
    /// Shares whose topic can be read off the whole card, strongest first on a tie.
    static let shareTopics = ["media", "volume", "brightness", "battery", "steps", "timer", "tasks", "year", "month", "week"]

    /// The label a layer carries: its text, or a field's own default and label.
    func words(of layer: Layer) -> String {
        guard case .text(let text) = layer.content else { return "" }
        var parts = text.value.allValues.filter { Bindings.names(in: $0).isEmpty }
        for name in text.value.allValues.flatMap(Bindings.names(in:)) {
            guard case .field(let key)? = Bindings.Name(name), let field = spec.field(key) else { continue }
            parts += field.label.allValues + (field.default?.allValues ?? [])
        }
        return parts.joined(separator: " ").lowercased()
    }

    func icons(of layer: Layer) -> [String] {
        guard case .icon(let icon) = layer.content else { return [] }
        if let raw = Bindings.soleBinding(icon.symbol) { return Capabilities.binding(raw)?.icons ?? [] }
        return [icon.symbol]
    }

    /// Text and icons around a layer, nearest first; children of its own stack always count.
    func neighbors(of item: AutoWire.Found, reach: Double = 60) -> [AutoWire.Found] {
        let distance = { (frame: Frame) -> Double in
            let dx = max(max(item.frame.x - (frame.x + frame.w), frame.x - (item.frame.x + item.frame.w)), 0)
            let dy = max(max(item.frame.y - (frame.y + frame.h), frame.y - (item.frame.y + item.frame.h)), 0)
            return hypot(dx, dy)
        }
        return AutoWire.walk(spec.layers).filter { other in
            guard other.path != item.path else { return false }
            switch other.layer.content {
            case .text, .icon: break
            default: return false
            }
            let sameStack = item.path.count > 1 && other.path.count > 1 && item.path[0] == other.path[0]
            return sameStack || distance(other.frame) <= reach
        }.sorted { distance($0.frame) < distance($1.frame) }
    }

    /// Time shares last: "Daily steps" is about steps.
    private func shares(kind: String) -> [Capability] {
        let all = Capabilities.bindings.filter { $0.isShare && $0.ai && !$0.keywords.isEmpty && (kind == "text" || $0.layers.contains(kind)) }
        return all.filter { $0.group != "time" } + all.filter { $0.group == "time" }
    }

    private func match(_ candidates: [Capability], words: String, icons: [String]) -> Capability? {
        candidates.first { capability in
            capability.keywords.contains { AutoWire.Keyword.occurs($0, in: words) } || !capability.icons.filter(icons.contains).isEmpty
        }
    }

    /// What the nearest label names: the layer's own words first, then its neighbors in order.
    func namedShare(for item: AutoWire.Found, kind: String, own: String = "") -> String? {
        let candidates = shares(kind: kind)
        if let found = match(candidates, words: own.lowercased(), icons: []) { return found.id }
        for other in neighbors(of: item) {
            if let found = match(candidates, words: words(of: other.layer), icons: icons(of: other.layer)) { return found.id }
        }
        return nil
    }

    /// The binding for a share on this layer, or nil when nothing says what it is: never a default.
    func shareBinding(for item: AutoWire.Found, kind: String, own: String = "") -> String? {
        if let named = namedShare(for: item, kind: kind, own: own) { return named }
        let topicsToTry = kind == "text" ? Self.shareTopics.filter { $0 != "media" } : Self.shareTopics
        guard let prefix = topics.best(of: topicsToTry) else { return nil }
        return shares(kind: kind).first { AutoWire.Topics.prefix($0.id) == prefix }?.id
    }

    /// Whether the design shows any value of this topic.
    func showsTopic(_ prefix: String) -> Bool {
        DataRequirements.bindingNames(in: spec).contains { AutoWire.Topics.prefix($0.trimmingCharacters(in: .whitespaces)) == prefix }
    }

    /// Whether anything near the layer speaks of this capability.
    func isNamed(_ capability: Capability, near item: AutoWire.Found, own: String = "") -> Bool {
        if capability.keywords.contains(where: { AutoWire.Keyword.occurs($0, in: own.lowercased()) }) { return true }
        return neighbors(of: item).contains { other in
            capability.keywords.contains { AutoWire.Keyword.occurs($0, in: words(of: other.layer)) } || !capability.icons.filter(icons(of: other.layer).contains).isEmpty
        }
    }

    /// The share a layer shows, when it shows exactly one.
    func boundShare(of layer: Layer) -> (capability: Capability, kind: String)? {
        var value: String?
        var kind = "text"
        switch layer.content {
        case .text(let text): value = text.value.resolved(language: "en")
        case .ring(let ring):
            value = ring.progress
            kind = "ring"
        case .progressBar(let bar):
            value = bar.progress
            kind = "progressBar"
        case .dotGrid(let grid):
            value = grid.values
            kind = "dotGrid"
        default: break
        }
        guard let value else { return nil }
        let bound = Bindings.names(in: value).compactMap { Capabilities.binding($0) }.filter(\.isShare)
        guard bound.count == 1 else { return nil }
        return (bound[0], kind)
    }

    /// A label that names another share wins: a "Year" percent never shows the battery.
    mutating func correctShares() {
        for item in AutoWire.walk(spec.layers) {
            guard let (current, kind) = boundShare(of: item.layer) else { continue }
            let own = words(of: item.layer)
            guard let better = namedShare(for: item, kind: kind, own: own), better != current.id,
                  !isNamed(current, near: item, own: own) else { continue }
            update(item.path) { layer in
                let (from, to) = ("{{\(current.id)}}", "{{\(better)}}")
                switch layer.content {
                case .text(var text):
                    let values = text.value.allValues.map { $0.replacingOccurrences(of: from, with: to) }
                    text.value = .localized(en: values[0], ar: values[values.count - 1])
                    layer.content = .text(text)
                case .ring(var ring):
                    ring.progress = to
                    layer.content = .ring(ring)
                case .progressBar(var bar):
                    bar.progress = to
                    layer.content = .progressBar(bar)
                case .dotGrid(var grid):
                    grid.values = to
                    layer.content = .dotGrid(grid)
                default: break
                }
            }
            log("\(current.id) beside another label", better)
        }
    }

    // MARK: Forecast rows

    /// Three or more weather icons in a row are days: each follows its own day, and the labels and
    /// temperatures under it follow too. A first column called Today shows today.
    mutating func forecastRows() {
        let weather = Set(Capabilities.binding("weather.symbol")?.icons ?? [])
            .union(["cloud.drizzle.fill", "cloud.heavyrain.fill", "cloud.bolt.rain.fill", "cloud.snow.fill", "cloud.fog.fill", "moon.fill", "moon.stars.fill"])
        let items = AutoWire.walk(spec.layers).filter { item in
            if case .icon(let icon) = item.layer.content { return weather.contains(icon.symbol) }
            return false
        }
        var rows: [[AutoWire.Found]] = []
        for item in items {
            if let index = rows.firstIndex(where: { abs($0[0].frame.y + $0[0].frame.h / 2 - item.frame.y - item.frame.h / 2) <= 12 }) {
                rows[index].append(item)
            } else {
                rows.append([item])
            }
        }
        for row in rows where row.count >= 3 {
            let days = row.sorted { $0.frame.x < $1.frame.x }.prefix(7)
            let step = (days[days.startIndex + 1].frame.x - days[days.startIndex].frame.x)
            let rowY = days[days.startIndex].frame.y + days[days.startIndex].frame.h / 2
            let texts = AutoWire.walk(spec.layers).filter { item in
                guard case .text(let text) = item.layer.content, text.live == nil else { return false }
                return Bindings.names(in: text.value.resolved(language: "en")).isEmpty && abs(item.frame.y + item.frame.h / 2 - rowY) <= 70
            }
            func column(_ icon: AutoWire.Found) -> [AutoWire.Found] {
                let middle = icon.frame.x + icon.frame.w / 2
                return texts.filter { abs($0.frame.x + $0.frame.w / 2 - middle) < step / 2 }.sorted { $0.frame.y < $1.frame.y }
            }
            let startsToday = column(days[days.startIndex]).contains { AutoWire.TextShape.isToday(text($0).trimmingCharacters(in: .whitespaces)) }
            for (index, icon) in days.enumerated() {
                let day = startsToday ? index : index + 1
                guard day <= 6 else { break }
                let symbol = day == 0 ? "weather.symbol" : "forecast.\(day).symbol"
                update(icon.path) { layer in
                    guard case .icon(var changed) = layer.content else { return }
                    changed.symbol = "{{\(symbol)}}"
                    layer.content = .icon(changed)
                }
                log("forecast icon", symbol)
                var temperatures = 0
                for item in column(icon) {
                    let value = text(item).trimmingCharacters(in: .whitespaces)
                    if AutoWire.TextShape.isDayName(value), day > 0 {
                        let id = "forecast.\(day).day"
                        setText(item.path, en: "{{\(id)}}", ar: "{{\(id)}}", was: value, id: id)
                    } else if AutoWire.TextShape.isTemperature(value) {
                        let part = temperatures == 0 ? "hi" : "lo"
                        temperatures += 1
                        let id = day == 0 ? "weather.\(part)" : "forecast.\(day).\(part)"
                        setText(item.path, en: "{{\(id)}}°", ar: "{{\(id)}}°", was: value, id: id)
                    }
                }
            }
        }
    }

    // MARK: State sets

    /// A frozen face or dot drawing on a card about something that changes becomes a state layer.
    mutating func stateSets() {
        faces()
        for item in AutoWire.walk(spec.layers) {
            switch item.layer.content {
            case .text(let content):
                let scalars = content.value.resolved(language: "en").unicodeScalars.filter { $0 != "\u{FE0E}" && $0 != "\u{FE0F}" }
                let value = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty, let set = Capabilities.stateSets.first(where: { $0.glyphs.contains(value) }),
                      set.topic.map(topics.has) ?? false else { continue }
                swap(item, for: set, color: content.color)
            case .dotGrid(let grid):
                guard grid.rows >= 8, grid.cols >= 8, Bindings.soleBinding(grid.values) == nil, !Self.isFillPattern(grid),
                      let set = artSet(for: item) else { continue }
                swap(item, for: set, color: grid.onColor)
            default:
                break
            }
        }
    }

    /// The drawn set this layer stands for: the only one the card is about, or the nearest.
    func artSet(for item: AutoWire.Found) -> StateSet? {
        let drawn = Capabilities.stateSets.filter { set in
            guard case .dotGrid? = set.variants.first?.layers.first?.content, let topic = set.topic else { return false }
            return topics.has(topic)
        }
        if drawn.count <= 1 { return drawn.first }
        return drawn.first { set in
            Capabilities.bindings.contains { capability in
                AutoWire.Topics.prefix(capability.id) == set.topic && isNamed(capability, near: item)
            }
        }
    }

    private mutating func swap(_ item: AutoWire.Found, for set: StateSet, color: String) {
        let states = StatesLayer(set: set.id, color: color)
        if item.path.count == 1 {
            update(item.path) { $0.content = .states(states) }
        } else {
            // A stack child: keep its space, and draw the set at the top level over it.
            update(item.path) { $0.content = .spacer(SpacerLayer()) }
            insertDrawn([Layer(frame: item.frame, mirror: item.mirror, content: .states(states))])
        }
        log("frozen \(set.topic ?? "")", set.id)
    }

    /// A round head with small round eyes, drawn from shapes, on a battery card.
    private mutating func faces() {
        guard topics.has("battery"), let set = Capabilities.stateSet("battery.mood") else { return }
        for (index, layer) in spec.layers.enumerated() {
            guard let parts = Self.faceParts(of: index, in: spec.layers) else { continue }
            var head = layer
            var color = "@fg"
            if case .shape(let shape) = layer.content { color = shape.stroke?.color ?? shape.fill ?? color }
            head.content = .states(StatesLayer(set: set.id, color: color))
            spec.layers[index] = head
            for part in parts.sorted(by: >) { spec.layers.remove(at: part) }
            log("frozen face", set.id)
            return
        }
    }

    /// The indexes of the pieces inside a head, when the layer at `index` is one.
    static func faceParts(of index: Int, in layers: [Layer]) -> [Int]? {
        let head = layers[index]
        guard case .shape(let shape) = head.content, shape.kind == .circle, head.frame.w >= 36, abs(head.frame.w - head.frame.h) <= 4 else { return nil }
        let inside = layers.indices.filter { other in
            guard other != index, case .shape(let piece) = layers[other].content, layers[other].when == nil else { return false }
            return piece.fill != nil || piece.stroke != nil ? AutoWire.Run.inside(layers[other].frame, head.frame) && layers[other].frame.w < head.frame.w * 0.6 : false
        }
        let eyes = inside.filter { other in
            guard case .shape(let piece) = layers[other].content, piece.kind == .circle else { return false }
            return layers[other].frame.w <= head.frame.w * 0.3
        }
        return eyes.count >= 2 ? inside : nil
    }
}
