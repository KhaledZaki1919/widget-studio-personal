import Foundation

/// How much of a design is wired (ADR-027): the eval's score, and the ids the tests compare.
public enum WiringScore {
    /// Every binding and action id a spec uses.
    public static func ids(in spec: WidgetSpec) -> Set<String> {
        var ids = Set(DataRequirements.bindingNames(in: spec).map { $0.trimmingCharacters(in: .whitespaces) })
        for layer in spec.allLayers {
            if case .button(let button) = layer.content { ids.insert(button.action.rawValue) }
            // An analog clock is live with no binding; the eval calls it "clock".
            if case .analogClock = layer.content { ids.insert("clock") }
        }
        return ids
    }

    /// The share of `expected` ids the spec has (each entry may list alternatives with "|"), 0…1.
    public static func score(_ spec: WidgetSpec, expected: [String]) -> Double {
        guard !expected.isEmpty else { return 1 }
        return Double(hits(spec, expected: expected).count) / Double(expected.count)
    }

    public static func hits(_ spec: WidgetSpec, expected: [String]) -> [String] {
        let present = ids(in: spec)
        return expected.filter { entry in entry.split(separator: "|").contains { present.contains(String($0)) } }
    }
}
