import SwiftUI

struct CoworkConfirmationSheet: View {
    @EnvironmentObject var cowork: CoworkState

    var body: some View {
        if let confirmation = cowork.activeConfirmation {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(PrismTheme.accent)
                    Text(confirmation.title ?? L10n.permissionRequired)
                        .font(.ps(13, weight: .semibold))
                        .foregroundStyle(PrismTheme.textPrimary)
                    Spacer()
                    if cowork.pendingConfirmations.count > 1 {
                        Text(L10n.confirmationQueuePosition(queueIndex, cowork.pendingConfirmations.count))
                            .font(.ps(10, weight: .bold))
                            .foregroundStyle(PrismTheme.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(PrismTheme.surfaceMuted.opacity(0.7))
                            .clipShape(Capsule())
                    }
                }

                Text(confirmation.description)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    ForEach(confirmation.options) { option in
                        Button(option.label) {
                            Task { await cowork.respondToConfirmation(option: option) }
                        }
                        .buttonStyle(PrismHandButtonStyle())
                        .font(.ps(11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            option.value.contains("deny") || option.value.contains("reject")
                                ? AnyShapeStyle(PrismTheme.surfaceMuted.opacity(0.7))
                                : AnyShapeStyle(PrismTheme.accentGradient)
                        )
                        .clipShape(Capsule())
                    }
                    if confirmation.options.contains(where: { $0.value.contains("allow") }) {
                        Button(L10n.alwaysAllow) {
                            if let allow = confirmation.options.first(where: { $0.value.contains("allow") }) {
                                Task { await cowork.respondToConfirmation(option: allow, alwaysAllow: true) }
                            }
                        }
                        .buttonStyle(PrismHandButtonStyle())
                        .font(.ps(10))
                    }
                }
            }
            .padding(14)
            .prismGlass(cornerRadius: 16, padding: 0)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var queueIndex: Int {
        guard let active = cowork.activeConfirmation,
              let idx = cowork.pendingConfirmations.firstIndex(where: { $0.callID == active.callID }) else { return 1 }
        return idx + 1
    }
}
