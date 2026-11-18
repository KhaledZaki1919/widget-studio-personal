import SwiftUI
import UIKit

// Personal build (docs/personal.md): the app's Material 3 theme for the Mono identity.
//
// Roles, not literals: screens use `M3.<role>`, `M3Type.<role>`, `M3Space`, `M3Shape` and the
// component styles below. Literal values live only in this file.
// - Color: black/white neutrals and one red as `primary`; secondary is neutral, so red stays scarce.
//   Light and dark are separate tone sets (dark containers get lighter, not darker).
// - Type: M3 roles mapped onto iOS text styles, so Dynamic Type keeps working; dot numerals
//   (Doto) only for codes and counts.
// - iOS stays iOS: tab bar, navigation stacks, swipe back, sheets, alerts and system pickers keep
//   their behavior; they only take the roles' colors and type.

// MARK: Color roles

enum M3 {
    // Primary: the Mono red. In dark mode a lighter tone with dark content keeps 4.5:1.
    static let primary = dynamic(0xE2231A, 0xFF5449)
    static let onPrimary = dynamic(0xFFFFFF, 0x2D0001)
    static let primaryContainer = dynamic(0xFFDAD6, 0x7A0A06)
    static let onPrimaryContainer = dynamic(0x410002, 0xFFDAD6)

    // Secondary: neutral (selected chips, tonal buttons, segmented selection).
    static let secondaryContainer = dynamic(0xE3E3E3, 0x353535)
    static let onSecondaryContainer = dynamic(0x1A1A1A, 0xEDEDED)

    // Surfaces, lowest to highest emphasis.
    static let surface = dynamic(0xF9F9F9, 0x0E0E0E)
    static let surfaceContainerLowest = dynamic(0xFFFFFF, 0x080808)
    static let surfaceContainerLow = dynamic(0xF3F3F3, 0x161616)
    static let surfaceContainer = dynamic(0xEDEDED, 0x1C1C1C)
    static let surfaceContainerHigh = dynamic(0xE7E7E7, 0x262626)
    static let surfaceContainerHighest = dynamic(0xE1E1E1, 0x313131)
    static let onSurface = dynamic(0x1A1A1A, 0xF2F2F2)
    static let onSurfaceVariant = dynamic(0x575757, 0xB8B8B8)
    static let outline = dynamic(0x7A7A7A, 0x8E8E8E)
    static let outlineVariant = dynamic(0xCDCDCD, 0x3F3F3F)
    static let inverseSurface = dynamic(0x2E2E2E, 0xE6E6E6)
    static let inverseOnSurface = dynamic(0xF2F2F2, 0x1A1A1A)
    static let inversePrimary = dynamic(0xFFB4AB, 0xC00F0C)

    // Error (real errors and destructive actions only).
    static let error = dynamic(0xBA1A1A, 0xFFB4AB)
    static let onError = dynamic(0xFFFFFF, 0x690005)
    static let errorContainer = dynamic(0xFFDAD6, 0x93000A)
    static let onErrorContainer = dynamic(0x410002, 0xFFDAD6)

    // Extended roles for status (always shown with an icon or text too, never color alone).
    static let success = dynamic(0x1E7A3A, 0x7DD89A)
    static let warning = dynamic(0x8A5300, 0xFFB95C)

    /// A color that follows light/dark mode (and stays correct in `.environment(\.colorScheme)`).
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: uiDynamic(light, dark))
    }

    static func uiDynamic(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) }
    }

    static func ui(_ color: Color) -> UIColor { UIColor(color) }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

// MARK: Type roles (M3 roles on iOS text styles: they scale with Dynamic Type)

enum M3Type {
    static let displaySmall = Font.system(.largeTitle, design: .default, weight: .bold)
    static let headlineMedium = Font.system(.title, design: .default, weight: .bold)
    static let headlineSmall = Font.system(.title2, design: .default, weight: .semibold)
    static let titleLarge = Font.system(.title3, design: .default, weight: .semibold)
    static let titleMedium = Font.system(.headline, design: .default, weight: .semibold)
    static let titleSmall = Font.system(.subheadline, design: .default, weight: .semibold)
    static let bodyLarge = Font.system(.body)
    static let bodyMedium = Font.system(.subheadline)
    static let bodySmall = Font.system(.footnote)
    static let labelLarge = Font.system(.subheadline, design: .default, weight: .medium)
    static let labelMedium = Font.system(.caption, design: .default, weight: .medium)
    static let labelSmall = Font.system(.caption2, design: .default, weight: .medium)

    /// Dot numerals (Doto, bundled): codes, counts, big numbers. Scales with Dynamic Type.
    static func dots(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        Font.custom("Doto-Black", size: size, relativeTo: style)
    }
}

// MARK: Spacing (4-point rhythm) and shape scale

enum M3Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Minimum touch target (M3 48dp; above iOS's 44pt).
    static let target: CGFloat = 48
}

enum M3Shape {
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 28

    static func rounded(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

// MARK: Buttons

/// M3 common buttons. Visible height 40, touch target 48, full-rounded; a 10% state layer when
/// pressed; disabled = onSurface at 12% (container) and 38% (content).
struct M3ButtonStyle: ButtonStyle {
    enum Kind { case filled, tonal, outlined, text, destructive }
    var kind: Kind
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        M3ButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }
}

private struct M3ButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: M3ButtonStyle.Kind
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(M3Type.labelLarge)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? content : M3.onSurface.opacity(0.38))
            .padding(.horizontal, kind == .text ? M3Space.m : M3Space.xl)
            .padding(.vertical, M3Space.s)
            .frame(minHeight: 40)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background {
                Capsule().fill(isEnabled ? container : (hasContainer ? M3.onSurface.opacity(0.12) : .clear))
            }
            .overlay {
                if kind == .outlined {
                    Capsule().strokeBorder(isEnabled ? M3.outline : M3.onSurface.opacity(0.12), lineWidth: 1)
                }
            }
            .overlay { Capsule().fill(content.opacity(configuration.isPressed ? 0.10 : 0)) }
            .frame(minHeight: M3Space.target)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var hasContainer: Bool { kind == .filled || kind == .tonal || kind == .destructive }

    private var container: Color {
        switch kind {
        case .filled: M3.primary
        case .tonal: M3.secondaryContainer
        case .destructive: M3.error
        case .outlined, .text: .clear
        }
    }

    private var content: Color {
        switch kind {
        case .filled: M3.onPrimary
        case .tonal: M3.onSecondaryContainer
        case .destructive: M3.onError
        case .outlined, .text: M3.primary
        }
    }
}

extension ButtonStyle where Self == M3ButtonStyle {
    /// Highest emphasis: one per action group.
    static var m3Filled: M3ButtonStyle { M3ButtonStyle(kind: .filled) }
    static var m3FilledWide: M3ButtonStyle { M3ButtonStyle(kind: .filled, fullWidth: true) }
    static var m3Tonal: M3ButtonStyle { M3ButtonStyle(kind: .tonal) }
    static var m3TonalWide: M3ButtonStyle { M3ButtonStyle(kind: .tonal, fullWidth: true) }
    static var m3Outlined: M3ButtonStyle { M3ButtonStyle(kind: .outlined) }
    static var m3OutlinedWide: M3ButtonStyle { M3ButtonStyle(kind: .outlined, fullWidth: true) }
    static var m3Text: M3ButtonStyle { M3ButtonStyle(kind: .text) }
    static var m3Destructive: M3ButtonStyle { M3ButtonStyle(kind: .destructive) }
}

// MARK: Chips

/// M3 filter chip (selected shows a check mark, not only a color) and assist chip (`selected` nil).
/// Visible height 32, shape small (8), target 48.
struct M3ChipStyle: ButtonStyle {
    var selected: Bool?

    func makeBody(configuration: Configuration) -> some View {
        M3ChipBody(configuration: configuration, selected: selected)
    }
}

private struct M3ChipBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isOn = selected == true
        HStack(spacing: M3Space.s) {
            if isOn {
                Image(systemName: "checkmark").font(M3Type.labelMedium.weight(.bold)).accessibilityHidden(true)
            }
            configuration.label
        }
        .font(M3Type.labelLarge)
        .lineLimit(1)
        .foregroundStyle(isEnabled ? (isOn ? M3.onSecondaryContainer : M3.onSurfaceVariant) : M3.onSurface.opacity(0.38))
        .padding(.horizontal, M3Space.m)
        .frame(minHeight: 32)
        .background(M3Shape.rounded(M3Shape.small).fill(isOn ? M3.secondaryContainer : .clear))
        .overlay {
            if !isOn { M3Shape.rounded(M3Shape.small).strokeBorder(M3.outlineVariant, lineWidth: 1) }
        }
        .overlay(M3Shape.rounded(M3Shape.small).fill(M3.onSurface.opacity(configuration.isPressed ? 0.10 : 0)))
        .frame(minHeight: M3Space.target)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension ButtonStyle where Self == M3ChipStyle {
    static func m3Filter(selected: Bool) -> M3ChipStyle { M3ChipStyle(selected: selected) }
    static var m3Assist: M3ChipStyle { M3ChipStyle(selected: nil) }
}

// MARK: Cards and containers

enum M3CardKind { case filled, outlined, elevated }

struct M3CardModifier: ViewModifier {
    var kind: M3CardKind
    var radius: CGFloat = M3Shape.medium

    func body(content: Content) -> some View {
        content
            .background {
                switch kind {
                case .filled: M3Shape.rounded(radius).fill(M3.surfaceContainerHighest)
                case .outlined: M3Shape.rounded(radius).fill(M3.surface)
                case .elevated:
                    M3Shape.rounded(radius).fill(M3.surfaceContainerLow)
                        .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                }
            }
            .overlay {
                if kind == .outlined { M3Shape.rounded(radius).strokeBorder(M3.outlineVariant, lineWidth: 1) }
            }
            .clipShape(M3Shape.rounded(radius))
    }
}

extension View {
    /// A card: only for a real contained unit (a design, a widget), never around every row.
    func m3Card(_ kind: M3CardKind = .filled, radius: CGFloat = M3Shape.medium) -> some View {
        modifier(M3CardModifier(kind: kind, radius: radius))
    }

    /// Grouped lists and forms on the theme's surface (rows keep iOS's grouped containers).
    func m3List() -> some View {
        scrollContentBackground(.hidden)
            .background(M3.surfaceContainerLow.ignoresSafeArea())
    }

    /// A plain screen background.
    func m3Screen() -> some View {
        background(M3.surface.ignoresSafeArea())
    }

    /// Bottom sheets: extra-large top corners and a low container.
    func m3Sheet() -> some View {
        presentationCornerRadius(M3Shape.extraLarge)
            .presentationBackground(M3.surfaceContainerLow)
    }

    /// An M3 outlined text field container: label stays visible above (never placeholder-only),
    /// focus draws a 2-point primary outline, error an error outline plus text.
    func m3Field(_ label: Text? = nil, supporting: Text? = nil, error: Text? = nil) -> some View {
        modifier(M3FieldModifier(label: label, supporting: supporting, error: error))
    }
}

struct M3FieldModifier: ViewModifier {
    let label: Text?
    let supporting: Text?
    let error: Text?
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: M3Space.xs) {
            if let label {
                label.font(M3Type.labelMedium)
                    .foregroundStyle(error != nil ? M3.error : (focused ? M3.primary : M3.onSurfaceVariant))
            }
            content
                .font(M3Type.bodyLarge)
                .focused($focused)
                .padding(.horizontal, M3Space.l)
                .padding(.vertical, M3Space.m)
                .frame(minHeight: 56)
                .background(M3Shape.rounded(M3Shape.extraSmall).fill(M3.surfaceContainerLowest))
                .overlay {
                    M3Shape.rounded(M3Shape.extraSmall)
                        .strokeBorder(error != nil ? M3.error : (focused ? M3.primary : M3.outline),
                                      lineWidth: focused || error != nil ? 2 : 1)
                }
            if let error {
                Label { error } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(M3Type.bodySmall)
                    .foregroundStyle(M3.error)
            } else if let supporting {
                supporting.font(M3Type.bodySmall).foregroundStyle(M3.onSurfaceVariant)
            }
        }
    }
}

/// A section title in lists and screens (title small, onSurfaceVariant).
struct M3SectionTitle: View {
    let text: Text

    var body: some View {
        text.font(M3Type.titleSmall).foregroundStyle(M3.onSurfaceVariant).textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Empty states: what this means and the next useful action.
struct M3EmptyState<Actions: View>: View {
    let symbol: String
    let title: Text
    let message: Text
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: M3Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(M3.onSurfaceVariant)
                .frame(width: 80, height: 80)
                .background(Circle().fill(M3.surfaceContainerHigh))
                .accessibilityHidden(true)
            title.font(M3Type.titleLarge).foregroundStyle(M3.onSurface).multilineTextAlignment(.center)
            message.font(M3Type.bodyMedium).foregroundStyle(M3.onSurfaceVariant).multilineTextAlignment(.center)
            actions.padding(.top, M3Space.s)
        }
        .padding(M3Space.xl)
        .frame(maxWidth: 480)
    }
}

/// A small status line: icon + text, so state never depends on color alone.
struct M3Status: View {
    enum Tone { case success, warning, error, neutral }
    let tone: Tone
    let text: Text

    var body: some View {
        Label { text } icon: { Image(systemName: symbol) }
            .font(M3Type.bodySmall)
            .foregroundStyle(color)
    }

    private var symbol: String {
        switch tone {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .neutral: "info.circle"
        }
    }

    private var color: Color {
        switch tone {
        case .success: M3.success
        case .warning: M3.warning
        case .error: M3.error
        case .neutral: M3.onSurfaceVariant
        }
    }
}

// MARK: Root

extension View {
    /// The one hook at the app root (`WidgetStudioApp`): tint, system bar appearance.
    func personalTheme() -> some View {
        M3Appearance.install()
        return tint(M3.primary)
    }
}

/// System bars and UIKit controls take the roles' colors and type; behavior stays iOS.
enum M3Appearance {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let onSurface = M3.ui(M3.onSurface)

        // Top app bar: flat on the screen color at rest, a container tone once content scrolls under it.
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.backgroundColor = M3.ui(M3.surfaceContainerLow)
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithOpaqueBackground()
        scrolled.backgroundColor = M3.ui(M3.surfaceContainer)
        scrolled.shadowColor = .clear
        for appearance in [edge, scrolled] {
            appearance.titleTextAttributes = [.foregroundColor: onSurface, .font: scaled(.headline, weight: .semibold)]
            appearance.largeTitleTextAttributes = [.foregroundColor: onSurface, .font: scaled(.largeTitle, weight: .bold)]
        }
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = edge

        // Navigation bar (bottom): container surface, selected item in primary with a filled symbol
        // and a semibold label, unselected in onSurfaceVariant.
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = M3.ui(M3.surfaceContainer)
        tabs.shadowColor = .clear
        for layout in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            layout.normal.iconColor = M3.ui(M3.onSurfaceVariant)
            layout.normal.titleTextAttributes = [.foregroundColor: M3.ui(M3.onSurfaceVariant), .font: scaled(.caption2, weight: .medium)]
            layout.selected.iconColor = M3.ui(M3.primary)
            layout.selected.titleTextAttributes = [.foregroundColor: onSurface, .font: scaled(.caption2, weight: .bold)]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs

        // Segmented buttons: neutral selected container, label type.
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = M3.ui(M3.secondaryContainer)
        segmented.backgroundColor = M3.ui(M3.surfaceContainerHigh)
        segmented.setTitleTextAttributes([.foregroundColor: M3.ui(M3.onSurfaceVariant),
                                          .font: scaled(.subheadline, weight: .medium)], for: .normal)
        segmented.setTitleTextAttributes([.foregroundColor: M3.ui(M3.onSecondaryContainer),
                                          .font: scaled(.subheadline, weight: .semibold)], for: .selected)

        UISwitch.appearance().onTintColor = M3.ui(M3.primary)
        UIPageControl.appearance().currentPageIndicatorTintColor = M3.ui(M3.primary)
        UIPageControl.appearance().pageIndicatorTintColor = M3.ui(M3.outlineVariant)
        UIRefreshControl.appearance().tintColor = M3.ui(M3.primary)
    }

    private static func scaled(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont.systemFont(ofSize: UIFont.preferredFont(
            forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize, weight: weight),
            maximumPointSize: base.pointSize * 2)
    }
}

// MARK: Personal strings

extension Text {
    /// A string from the personal table (`Personal.xcstrings`), so the official catalogs stay untouched.
    init(personal key: LocalizedStringKey) {
        self.init(key, tableName: "Personal")
    }
}
