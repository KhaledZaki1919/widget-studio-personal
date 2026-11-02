import Foundation

/// The hand-written test specs (10 from M1, one for the ADR-019 layers, one for M6.1 stacks) in `Resources/TestSpecs` (brief §10, M1). Together they use
/// every layer type, both themes, all three families and both languages. They are bundled, so
/// the widget can show them even without an App Group (ADR-005 device findings).
public enum TestSpecs {
    public typealias Entry = BundledSpecs.Entry

    /// Every bundled test spec, validated, sorted by file name.
    public static func load() -> [Entry] {
        BundledSpecs.load(folder: "TestSpecs")
    }

    /// Only the valid specs.
    public static func all() -> [WidgetSpec] {
        load().compactMap(\.spec)
    }

    public static func spec(id: String) -> WidgetSpec? {
        all().first { $0.id == id }
    }
}

/// `Resources/Spec/widget-spec.v1.schema.json`: the structure of v1 for AI providers with
/// structured output (brief §4.6). `SpecValidator` remains the authority.
public enum SpecSchema {
    public static var url: URL? {
        Bundle.module.url(forResource: "widget-spec.v1.schema", withExtension: "json", subdirectory: "Spec")
    }

    public static func data() -> Data? {
        url.flatMap { try? Data(contentsOf: $0) }
    }
}
