import SwiftUI
import UIKit

/// Onboarding page (M6.1): explains and requests location and Health right here, shows the
/// result, and can be skipped. The in-context notices (ADR-020) stay as the fallback.
struct PermissionsPage: View {
    @Environment(LiveDataModel.self) private var live
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 80, weight: .light))
                    .padding(.top, 8)
                    .accessibilityHidden(true)
                Text("permissions.title")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("permissions.body")
                    .foregroundStyle(M3.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                PermissionCard(symbol: "location.fill", title: "permissions.location.title", reason: "permissions.location.reason",
                               state: locationState, action: locationAction)
                    .accessibilityIdentifier("ax.permissions.location")
                PermissionCard(symbol: "heart.fill", title: "permissions.health.title", reason: "permissions.health.reason",
                               state: healthState, action: healthAction)
                    .accessibilityIdentifier("ax.permissions.health")
                Text("permissions.later")
                    .font(M3Type.bodySmall)
                    .foregroundStyle(M3.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var locationState: PermissionCard.State {
        switch live.authorization {
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        case .denied, .restricted: .denied
        default: .notAsked
        }
    }

    private var healthState: PermissionCard.State {
        if live.isHealthReadable { return .allowed }
        return live.healthAsked ? .askedNoData : .notAsked
    }

    /// iOS shows the Health prompt only once; after that, access is changed in the Health app.
    private func healthAction() {
        if live.healthAsked, let url = URL(string: "x-apple-health://") {
            openURL(url)
        } else {
            Task { await live.requestHealth() }
        }
    }

    private func locationAction() {
        if live.authorization == .notDetermined {
            live.requestLocation()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

private struct PermissionCard: View {
    enum State { case notAsked, allowed, denied, askedNoData }

    let symbol: String
    let title: LocalizedStringKey
    let reason: LocalizedStringKey
    let state: State
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title).font(M3Type.titleMedium)
            } icon: {
                Image(systemName: symbol).foregroundStyle(M3.primary).accessibilityHidden(true)
            }
            Text(reason).font(M3Type.bodySmall).foregroundStyle(M3.onSurfaceVariant)
            HStack {
                status
                Spacer()
                switch state {
                case .notAsked:
                    Button("permissions.allow", action: action)
                        .buttonStyle(.m3Tonal)
                        .accessibilityIdentifier("ax.permissions.allow")
                case .denied:
                    Button("settings.openSystemSettings", action: action).buttonStyle(.m3Outlined)
                case .askedNoData:
                    Button("permissions.askAgain", action: action).buttonStyle(.m3Outlined)
                case .allowed:
                    EmptyView()
                }
            }
        }
        .padding(M3Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .m3Card(.filled)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .notAsked:
            Text("settings.status.notAsked").font(M3Type.bodySmall).foregroundStyle(M3.onSurfaceVariant)
        case .allowed:
            Label("settings.status.allowed", systemImage: "checkmark.circle.fill").font(M3Type.bodySmall).foregroundStyle(M3.success)
        case .denied:
            Label("settings.status.denied", systemImage: "xmark.circle.fill").font(M3Type.bodySmall).foregroundStyle(M3.warning)
        case .askedNoData:
            Text("permissions.health.noData").font(M3Type.bodySmall).foregroundStyle(M3.onSurfaceVariant)
        }
    }
}
