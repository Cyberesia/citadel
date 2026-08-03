import SwiftUI

struct FortressSuspectsView: View {
    @EnvironmentObject var fortress: FortressViewModel
    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: CitadelShellRouter
    @State private var expandedID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)
            if fortress.suspectFindings.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { fortress.refreshSuspects() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.suspectsTitle)
                    .font(.ps(18, weight: .bold))
                    .foregroundStyle(PrismTheme.textPrimary)
                Text(L10n.suspectsSubtitle)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textTertiary)
            }
            Spacer()
            Text("\(fortress.suspectFindings.count)")
                .font(.ps(13, weight: .semibold).monospacedDigit())
                .foregroundStyle(PrismTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(PrismTheme.accent.opacity(0.15))
                .clipShape(Capsule())
            Button {
                fortress.refreshSuspects()
            } label: {
                Label(L10n.refresh, systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrismHandButtonStyle())
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.ps(40))
                .foregroundStyle(PrismTheme.signalAllow)
            Text(L10n.suspectsEmptyTitle)
                .font(.ps(15, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
            Text(L10n.suspectsEmptyBody)
                .font(.ps(12))
                .foregroundStyle(PrismTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(fortress.suspectFindings) { finding in
                    findingCard(finding)
                }
            }
            .padding(16)
        }
    }

    private func findingCard(_ finding: SuspectFinding) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                severityBadge(finding.severity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.resolvedTitle())
                        .font(.ps(13, weight: .semibold))
                        .foregroundStyle(PrismTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(finding.familyName) → \(finding.remoteLabel)\(finding.remotePort > 0 ? ":\(finding.remotePort)" : "")")
                        .font(.ps(11))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
                Spacer(minLength: 0)
            }

            if expandedID == finding.id {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.suspectsWhy)
                        .font(.ps(11, weight: .semibold))
                        .foregroundStyle(PrismTheme.textTertiary)
                    ForEach(finding.resolvedReasons(), id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .padding(.top, 5)
                            Text(reason)
                                .font(.ps(12))
                                .foregroundStyle(PrismTheme.textSecondary)
                        }
                    }
                }
                .padding(10)
                .background(PrismTheme.surfaceMuted.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                Button(L10n.suspectsWhy) {
                    withAnimation(PrismMotion.quick) {
                        expandedID = expandedID == finding.id ? nil : finding.id
                    }
                }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(11, weight: .medium))

                Spacer()

                PrismActionChip(title: L10n.allow, systemImage: "checkmark", kind: .allow) {
                    fortress.allowSuspect(finding)
                }
                PrismActionChip(title: L10n.deny, systemImage: "xmark", kind: .deny) {
                    fortress.denySuspect(finding)
                }
                Button {
                    fortress.focusSuspect(finding)
                    router.fortressMode = .activity
                } label: {
                    Text(L10n.suspectsShowInActivity)
                        .font(.ps(11, weight: .medium))
                }
                .buttonStyle(PrismHandButtonStyle())
            }
        }
        .padding(14)
        .background(PrismTheme.surface.opacity(0.4))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(severityColor(finding.severity).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func severityBadge(_ severity: SuspectSeverity) -> some View {
        Text(severityLabel(severity))
            .font(.ps(10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(severityColor(severity))
            .clipShape(Capsule())
    }

    private func severityLabel(_ s: SuspectSeverity) -> String {
        switch s {
        case .alert: return L10n.suspectSeverityAlert
        case .watch: return L10n.suspectSeverityWatch
        case .info: return L10n.suspectSeverityInfo
        }
    }

    private func severityColor(_ s: SuspectSeverity) -> Color {
        switch s {
        case .alert: return PrismTheme.signalDeny
        case .watch: return PrismTheme.accent
        case .info: return PrismTheme.accentSecondary
        }
    }
}
