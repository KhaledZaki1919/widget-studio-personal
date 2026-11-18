import SwiftUI
import WidgetKitCore

/// The template library (brief §7.2): category chips and a grid of live previews. Small
/// templates sit two per row, medium ones span the width. Tap → `TemplateDetailView`.
struct LibraryView: View {
    /// Long-pressing the version opens Diagnostics (brief §7.7).
    var onLongPressVersion: () -> Void = {}
    @Environment(AppState.self) private var appState
    @State private var category: SpecCategory?
    private let templates = TemplateLibrary.all()
    private let language = RenderContext.preferredLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: M3Space.xl) {
                createCard
                chips
                ForEach(visibleCategories, id: \.self) { category in
                    section(category)
                }
                Text(verbatim: "Widget Studio \(AppInfo.versionText)")
                    .font(M3Type.bodySmall)
                    .foregroundStyle(M3.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .contentShape(Rectangle())
                    .onLongPressGesture(perform: onLongPressVersion)
                    .accessibilityIdentifier("ax.home.version")
            }
            .padding(.vertical, M3Space.m)
        }
        .m3Screen()
        .accessibilityIdentifier("ax.library.list")
    }

    /// Create from image (M5): an image becomes a widget with the user's own AI key.
    private var createCard: some View {
        Button {
            appState.isCreatingFromImage = true
        } label: {
            HStack(spacing: M3Space.l) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(M3.onPrimaryContainer)
                    .frame(width: 48, height: 48)
                    .background(M3Shape.rounded(M3Shape.large).fill(M3.primaryContainer))
                VStack(alignment: .leading, spacing: M3Space.xs) {
                    Text("create.button").font(M3Type.titleMedium).foregroundStyle(M3.onSurface)
                    Text("create.button.subtitle").font(M3Type.bodyMedium).foregroundStyle(M3.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").foregroundStyle(M3.onSurfaceVariant)
            }
            .padding(M3Space.l)
            // The one elevated card on the screen: the main way to make something new.
            .m3Card(.elevated, radius: M3Shape.large)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ax.library.create")
    }

    private var visibleCategories: [SpecCategory] {
        category.map { [$0] } ?? SpecCategory.allCases.filter { !TemplateLibrary.templates(in: $0).isEmpty }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: M3Space.s) {
                chip(title: Text("library.all"), selected: category == nil, id: "all") { category = nil }
                ForEach(SpecCategory.allCases, id: \.self) { item in
                    chip(title: Text(verbatim: item.title.resolved(language: language)), selected: category == item,
                         id: item.rawValue) { category = item }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(title: Text, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        // M3 filter chips: the selected one shows a check mark, not only a color.
        Button(action: action) {
            title
        }
        .buttonStyle(.m3Filter(selected: selected))
        .accessibilityIdentifier("ax.library.chip.\(id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func section(_ category: SpecCategory) -> some View {
        let items = templates.filter { $0.category == category }
        let small = items.filter { $0.family == .small }
        let wide = items.filter { $0.family != .small }
        return VStack(alignment: .leading, spacing: M3Space.m) {
            Text(verbatim: category.title.resolved(language: language))
                .font(M3Type.titleLarge)
                .foregroundStyle(M3.onSurface)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 16)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                ForEach(small, id: \.id) { cell($0) }
            }
            .padding(.horizontal, 16)
            ForEach(wide, id: \.id) { cell($0).padding(.horizontal, 16) }
        }
    }

    private func cell(_ spec: WidgetSpec) -> some View {
        NavigationLink {
            TemplateDetailView(spec: spec)
        } label: {
            VStack(alignment: .leading, spacing: M3Space.s) {
                SpecPreview(spec: spec, language: language)
                Text(verbatim: spec.name.resolved(language: language))
                    .font(M3Type.labelLarge)
                    .foregroundStyle(M3.onSurface)
                    .lineLimit(2)
            }
            // The preview ignores touches (its buttons must not fire here), so the whole card
            // needs its own hit area.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // One VoiceOver element per template: its name once, its size, and what a tap does.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spec.name.resolved(language: language)))
        .accessibilityValue(Text(TemplateDetailView.sizeName(spec.family)))
        .accessibilityHint(Text("library.template.hint"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("ax.library.template.\(spec.id)")
    }
}
