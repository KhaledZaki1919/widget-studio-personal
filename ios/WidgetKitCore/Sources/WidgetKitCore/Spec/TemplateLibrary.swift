import Foundation

/// Spec JSON files bundled in a resource folder, each validated on load.
public enum BundledSpecs {
    public struct Entry: Sendable {
        public let fileName: String
        public let result: Result<WidgetSpec, SpecIssues>

        public var spec: WidgetSpec? { try? result.get() }
    }

    /// Every `.json` in `folder`, sorted by file name.
    public static func load(folder: String) -> [Entry] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: folder) ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let result: Result<WidgetSpec, SpecIssues>
            if let data = try? Data(contentsOf: url) {
                result = SpecValidator().validate(data: data)
            } else {
                result = .failure(SpecIssues([SpecIssue("", "unreadable file")]))
            }
            return Entry(fileName: url.lastPathComponent, result: result)
        }
    }
}

/// The default "Mono" template library (TEMPLATES.md), bundled in `Resources/Templates`, so the
/// app and the widget can offer every template without an App Group (ADR-005, ADR-011).
public enum TemplateLibrary {
    public static func load() -> [BundledSpecs.Entry] {
        BundledSpecs.load(folder: "Templates")
    }

    /// The valid templates in library order: by category, then by catalog order within it.
    public static func all() -> [WidgetSpec] {
        let specs = load().compactMap(\.spec)
        return SpecCategory.allCases.flatMap { category in
            specs.filter { $0.category == category }.sorted { order($0.id) < order($1.id) }
        }
    }

    public static func template(id: String) -> WidgetSpec? {
        try? load(id: id).get()
    }

    /// Loads and validates only `Templates/<id>.json`: what a widget timeline needs, without
    /// decoding the other 27 templates (ADR-012).
    public static func load(id: String) -> Result<WidgetSpec, SpecIssues> {
        guard SpecValidatorID.isValid(id),
              let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Templates") else {
            return .failure(SpecIssues([SpecIssue("", "template \(id) is not in the library")]))
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failure(SpecIssues([SpecIssue("", "template \(id) can't be read")]))
        }
        return SpecValidator().validate(data: data)
    }

    /// Templates that fit a widget of `size` (own size or smaller, never shrunk), in library order.
    public static func fitting(_ size: SpecFamily) -> [WidgetSpec] {
        all().filter { $0.family.rank <= size.rank }
    }

    /// The template a new widget of `size` shows before the user picks one.
    public static func defaultID(for size: SpecFamily) -> String {
        switch size {
        case .small: "mono.clock.digital"
        case .medium: "mono.weather.forecast"
        case .large, .xlarge: "mono.prayer.day"
        }
    }

    public static func templates(in category: SpecCategory) -> [WidgetSpec] {
        all().filter { $0.category == category }
    }

    /// Library order: `SpecCategory` order, then TEMPLATES.md order within each category.
    /// Ids not listed sort last, by id.
    static let catalogOrder = [
        "mono.clock.analog", "mono.clock.dotAnalog", "mono.clock.digital", "mono.date.big", "mono.date.dayZone", "mono.year.dots",
        "mono.weather.hiLo", "mono.weather.temp", "mono.weather.forecast", "mono.weather.art", "mono.location.coords",
        "mono.steps.streak", "mono.steps.month", "mono.sleep.week",
        "mono.prayer.next", "mono.prayer.day", "mono.qibla",
        "mono.focus.today", "mono.countdown.red", "mono.countdown.trip", "mono.stopwatch",
        "mono.photo.square", "mono.photo.circle", "mono.photo.halftone", "mono.music.card",
        "mono.tiles.pills2", "mono.tiles.pills4", "mono.tiles.round", "mono.tiles.hero", "mono.media.player", "mono.control.center", "mono.battery.mood",
        "mono.counter.tasbeeh", "mono.timer.focus",
        "mono.tasks.small", "mono.tasks.medium", "mono.tasks.large",
    ]

    static func order(_ id: String) -> String {
        catalogOrder.firstIndex(of: id).map { String(format: "%03d", $0) } ?? "999\(id)"
    }
}
