import SwiftUI

struct FortressSummaryBar: View {
    @ObservedObject var vm: FortressViewModel
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 16) {
            statusPill

            protectionPill

            Divider().frame(height: 20).opacity(0.3)

            metric(icon: "arrow.down", value: FortressFormat.bytesPerSec(vm.currentIn), tint: PrismTheme.trafficDown)
            metric(icon: "arrow.up", value: FortressFormat.bytesPerSec(vm.currentOut), tint: PrismTheme.trafficUp)

            Divider().frame(height: 20).opacity(0.3)

            metric(icon: "network", value: "\(vm.streams.count)", tint: PrismTheme.textSecondary)
            metric(icon: "square.stack.3d.up", value: "\(vm.tree.count)", tint: PrismTheme.textSecondary)

            if !vm.pendingAlerts.isEmpty {
                Divider().frame(height: 20).opacity(0.3)
                Label(
                    L10n.t(
                        "\(vm.pendingAlerts.count) alert\(vm.pendingAlerts.count == 1 ? "" : "s")",
                        "\(vm.pendingAlerts.count) alerte\(vm.pendingAlerts.count == 1 ? "" : "s")"
                    ),
                    systemImage: "bell.fill"
                )
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(PrismTheme.accent)
            }

            Spacer()

            if vm.isDemoMode {
                Button(L10n.exitDemo) { vm.exitDemo() }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(PrismTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PrismTheme.accentSoft)
                    .clipShape(Capsule())
            }

            Text(modeLabel)
                .font(.ps(11, weight: .medium))
                .foregroundStyle(PrismTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(PrismTheme.surface.opacity(0.4))
                .clipShape(Capsule())
        }
        .font(.ps(11, weight: .medium))
        .foregroundStyle(PrismTheme.textPrimary)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .prismGlass(cornerRadius: 999, padding: 0)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
            Text(statusLabel)
                .foregroundStyle(PrismTheme.textSecondary)
        }
    }

    private var protectionPill: some View {
        HStack(spacing: 6) {
            Image(systemName: protectionIcon)
                .foregroundStyle(protectionTint)
            Text(state.protectionStatusLabel)
                .foregroundStyle(PrismTheme.textSecondary)
                .lineLimit(1)
        }
        .help(L10n.protectionHelp)
    }

    private var protectionIcon: String {
        switch state.netExtStatus {
        case .active: return "checkmark.shield.fill"
        case .needsApproval, .activating: return "hourglass"
        default: return "shield.slash"
        }
    }

    private var protectionTint: Color {
        switch state.netExtStatus {
        case .active: return .green
        case .needsApproval, .activating: return PrismTheme.accent
        default: return PrismTheme.textTertiary
        }
    }

    private var statusIcon: String {
        if vm.isDemoMode { return "sparkles" }
        if vm.helperConnected { return "bolt.fill" }
        if vm.isRunning { return "eye.fill" }
        return "bolt.slash.fill"
    }

    private var statusTint: Color {
        if vm.isDemoMode { return PrismTheme.accent }
        if vm.helperConnected { return .green }
        if vm.isRunning { return PrismTheme.accent }
        return PrismTheme.textTertiary
    }

    private var statusLabel: String {
        if vm.isDemoMode { return L10n.t("Demo", "Démo") }
        if vm.helperConnected { return L10n.helperActive }
        if vm.isRunning { return L10n.localFortress }
        return L10n.t("Idle", "Inactif")
    }

    private var modeLabel: String {
        switch vm.mode {
        case .alert: return L10n.alertMode
        case .silentAllow: return L10n.silentAllow
        case .silentDeny: return L10n.silentDeny
        }
    }

    private func metric(icon: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).monospacedDigit()
        }
    }
}
