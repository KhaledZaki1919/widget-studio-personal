import SwiftUI

/// First-run introduction (brief §7.1, M6): what the app does, how to add a widget to the home
/// screen, permissions (M6.1) and privacy. Shown once, skippable, reopenable from Settings.
/// `permissionsOnly` is the one-page version existing users see once after updating.
struct OnboardingView: View {
    var permissionsOnly = false
    let onFinish: () -> Void
    @State private var page = 0
    private var pages: Int { permissionsOnly ? 1 : 4 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pages - 1 {
                    Button("onboarding.skip", action: onFinish)
                        .accessibilityIdentifier("ax.onboarding.skip")
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal)

            TabView(selection: $page) {
                if permissionsOnly {
                    PermissionsPage().tag(0)
                } else {
                    WhatPage().tag(0)
                    HowToAddPage().tag(1)
                    PermissionsPage().tag(2)
                    PrivacyPage().tag(3)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pages - 1 ? LocalizedStringKey("onboarding.next") : "onboarding.start")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .accessibilityIdentifier(page < pages - 1 ? "ax.onboarding.next" : "ax.onboarding.start")
        }
        .background(Color(uiColor: .systemBackground))
        // A container element, so this identifier doesn't replace the buttons' own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ax.onboarding")
    }
}

/// One page: a visual, a title, a body and optional rows.
private struct OnboardingPage<Visual: View, Rows: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let visual: Visual
    @ViewBuilder let rows: Rows

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                visual
                    .frame(maxHeight: 260)
                    .padding(.top, 8)
                Text(title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 14) { rows }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }
}

private struct Row: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text).font(.callout)
        } icon: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 28)
                .accessibilityHidden(true)
        }
    }
}

private struct WhatPage: View {
    var body: some View {
        OnboardingPage(title: "onboarding.what.title", message: "onboarding.what.body") {
            LogoMark(onDark: true)
                .frame(width: 150, height: 150)
                .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color(red: 0.055, green: 0.055, blue: 0.055)))
        } rows: {
            Row(symbol: "square.grid.2x2", text: "onboarding.what.templates")
            Row(symbol: "slider.horizontal.3", text: "onboarding.what.edit")
            Row(symbol: "sparkles", text: "onboarding.what.ai")
        }
    }
}

private struct HowToAddPage: View {
    var body: some View {
        OnboardingPage(title: "onboarding.add.title", message: "onboarding.add.body") {
            HomeScreenDemo()
        } rows: {
            Row(symbol: "1.circle.fill", text: "onboarding.add.step1")
            Row(symbol: "2.circle.fill", text: "onboarding.add.step2")
            Row(symbol: "3.circle.fill", text: "onboarding.add.step3")
        }
    }
}

private struct PrivacyPage: View {
    var body: some View {
        OnboardingPage(title: "onboarding.privacy.title", message: "onboarding.privacy.body") {
            Image(systemName: "lock.shield")
                .font(.system(size: 96, weight: .light))
                .accessibilityHidden(true)
        } rows: {
            Row(symbol: "person.crop.circle.badge.xmark", text: "onboarding.privacy.account")
            Row(symbol: "key", text: "onboarding.privacy.byok")
            Row(symbol: "iphone", text: "onboarding.privacy.device")
            Row(symbol: "chart.bar.xaxis", text: "onboarding.privacy.analytics")
        }
    }
}

/// A tiny home screen: icons wiggle, the "+" appears, and a widget drops in. Static (the last
/// step) with Reduce Motion.
private struct HomeScreenDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                screen(phase: 2)
            } else {
                PhaseAnimator([0, 1, 2, 2]) { phase in
                    screen(phase: phase)
                } animation: { _ in .spring(duration: 0.7) }
            }
        }
        .frame(width: 150, height: 250)
        .accessibilityElement()
        .accessibilityLabel(Text("onboarding.add.visual"))
    }

    private func screen(phase: Int) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.25), lineWidth: 3)
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .padding(5)
                        .background(Circle().fill(Color(uiColor: .systemBackground)))
                        .opacity(phase >= 1 ? 1 : 0)
                        .scaleEffect(phase >= 1 ? 1 : 0.3)
                }
                .frame(height: 24)
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.055, green: 0.055, blue: 0.055))
                        .overlay(alignment: .bottomTrailing) {
                            Circle().fill(Color(red: 0.886, green: 0.137, blue: 0.102)).frame(width: 18, height: 18).padding(10)
                        }
                        .overlay(alignment: .topLeading) {
                            Text(verbatim: "10:09").font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(.white).padding(10)
                        }
                }
                .frame(width: 110, height: 110)
                .opacity(phase == 2 ? 1 : 0)
                .scaleEffect(phase == 2 ? 1 : 1.25)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: 4), spacing: 6) {
                    ForEach(0..<8, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 22, height: 22)
                            .rotationEffect(.degrees(phase == 1 ? (index.isMultiple(of: 2) ? 4 : -4) : 0))
                    }
                }
            }
            .padding(14)
        }
    }
}
