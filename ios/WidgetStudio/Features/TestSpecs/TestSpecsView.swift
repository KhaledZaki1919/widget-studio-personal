import SwiftUI
import WidgetKitCore

/// M1 gallery: every bundled test spec rendered by the same `SpecView` the widget uses, in
/// Arabic or English, at widget proportions. Invalid specs show their validation issues.
struct TestSpecsView: View {
    @State private var language = RenderContext.preferredLanguage
    private let entries = TestSpecs.load()

    var body: some View {
        List {
            Section {
                Picker("specs.language", selection: $language) {
                    Text(verbatim: "العربية").tag("ar")
                    Text(verbatim: "English").tag("en")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ax.specs.language")
            } footer: {
                Text("specs.footer")
            }
            ForEach(entries, id: \.fileName) { entry in
                Section {
                    switch entry.result {
                    case .success(let spec):
                        SpecPreview(spec: spec, language: language, sample: true)
                            .frame(maxWidth: spec.family == .small ? 200 : .infinity)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("ax.specs.preview.\(spec.id)")
                            // Rebuild the TimelineView when the language changes.
                            .id("\(spec.id).\(language)")
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                            .listRowBackground(Color.clear)
                    case .failure(let failure):
                        Label("specs.invalid", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(M3.error)
                        Text(verbatim: failure.description)
                            .font(.footnote.monospaced())
                    }
                } header: {
                    Text(verbatim: header(entry))
                }
            }
        }
        .m3List()
        .accessibilityIdentifier("ax.specs.list")
        .navigationTitle("specs.title")
        // No layoutDirection override here: forcing RTL on a List inside an LTR app flips its
        // UIKit cells like an image (text, digits and clocks mirrored). The language only changes
        // the specs; SpecView handles RTL itself (ADR-010).
    }

    private func header(_ entry: TestSpecs.Entry) -> String {
        guard let spec = entry.spec else { return entry.fileName }
        return "\(spec.name.resolved(language: language)) · \(spec.family.rawValue)"
    }
}

