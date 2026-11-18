import SwiftUI
import WidgetKitCore

extension AIError {
    /// What went wrong, in one sentence. `provider` names who is busy.
    func message(provider: AIProviderKind) -> Text {
        if self == .busy { return Text("ai.error.busy \(provider.shortName)") }
        return Text(messageKey)
    }

    private var messageKey: LocalizedStringKey {
        switch self {
        case .noKey: "ai.error.noKey"
        case .invalidKey: "ai.error.invalidKey"
        case .insufficientCredit: "ai.error.credit"
        case .rateLimited: "ai.error.rateLimited"
        case .dailyQuota: "ai.error.dailyQuota"
        case .modelNotFound: "ai.error.model"
        case .refused: "ai.error.refused"
        case .truncated: "ai.error.truncated"
        case .invalidOutput: "ai.error.invalidOutput"
        case .network: "ai.error.network"
        case .providerUnavailable: "ai.error.unavailable"
        case .busy: "ai.error.unavailable"
        case .badRequest: "ai.error.badRequest"
        case .timedOut: "ai.error.timedOut"
        case .cancelled: "ai.error.cancelled"
        }
    }

    /// What the user can do next. `alternative` is the model suggested for rate limits.
    func nextStep(alternative: String) -> Text {
        switch self {
        case .noKey: Text("ai.error.noKey.next")
        case .invalidKey: Text("ai.error.invalidKey.next")
        case .insufficientCredit: Text("ai.error.credit.next")
        case .rateLimited: Text("ai.error.rateLimited.next \(alternative)")
        case .dailyQuota: Text("ai.error.dailyQuota.next \(alternative)")
        case .modelNotFound: Text("ai.error.model.next")
        case .refused: Text("ai.error.refused.next")
        case .truncated: Text("ai.error.truncated.next")
        case .invalidOutput: Text("ai.error.invalidOutput.next")
        case .network: Text("ai.error.network.next")
        case .providerUnavailable: Text("ai.error.unavailable.next")
        case .busy: Text("ai.error.busy.next")
        case .badRequest: Text("ai.error.badRequest.next")
        case .timedOut: Text("ai.error.timedOut.next")
        case .cancelled: Text("ai.error.cancelled.next")
        }
    }

    /// Errors that Settings → AI fixes (key, credit, model).
    var needsSettings: Bool {
        switch self {
        case .noKey, .invalidKey, .insufficientCredit, .modelNotFound, .rateLimited, .dailyQuota: true
        default: false
        }
    }
}

/// An AI error with its next step (brief §5: a clear error, never a spinner forever).
struct AIErrorView: View {
    let error: AIError
    var provider: AIProviderKind = AISettings.load().provider

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                error.message(provider: provider).font(.callout.weight(.semibold))
                error.nextStep(alternative: provider.alternativeModel)
                    .font(M3Type.bodySmall)
                    .foregroundStyle(M3.onSurfaceVariant)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(M3.warning)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ax.ai.error")
    }
}
