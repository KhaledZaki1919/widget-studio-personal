import Network
import Observation
import SwiftUI
import UIKit
import WidgetKitCore

/// Whether the phone is online (M6), for the offline notice in Create from image.
@MainActor
@Observable
final class NetworkStatus {
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "widgetstudio.network"))
    }

    deinit {
        monitor.cancel()
    }
}

/// A short notice with an icon, a message and an optional action button.
struct NoticeRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(M3Type.titleSmall)
                    Text(message).font(M3Type.bodySmall).foregroundStyle(M3.onSurfaceVariant)
                }
            } icon: {
                Image(systemName: symbol).foregroundStyle(M3.warning).accessibilityHidden(true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.m3Outlined)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: M3Shape.medium, style: .continuous).fill(M3.surfaceContainerHigh))
        .accessibilityElement(children: .combine)
    }
}

/// Missing location or Health access for a spec that needs it (M6): what it's for and a button
/// that asks (first time) or opens the app's page in Settings.
struct PermissionNotices: View {
    let spec: WidgetSpec
    @Environment(LiveDataModel.self) private var live
    @Environment(\.openURL) private var openURL

    var body: some View {
        let groups = DataRequirements.groups(for: spec)
        VStack(spacing: 10) {
            if !groups.isDisjoint(with: [.weather, .prayer, .location]) && !live.isLocationAllowed {
                NoticeRow(symbol: "location.slash", title: "notice.location.title", message: "notice.location.body",
                          actionTitle: live.authorization == .notDetermined ? "settings.location.allow" : "settings.openSystemSettings",
                          action: {
                              if live.authorization == .notDetermined { live.requestLocation() } else { openSettings() }
                          })
                    .accessibilityIdentifier("ax.notice.location")
            }
            if groups.contains(.health), !healthOK {
                NoticeRow(symbol: "heart.slash", title: "notice.health.title", message: "notice.health.body",
                          actionTitle: "settings.health.allow", action: { Task { await live.requestHealth() } })
                    .accessibilityIdentifier("ax.notice.health")
            }
        }
    }

    private var healthOK: Bool {
        if case .success? = live.inputs.health { return true }
        return false
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
