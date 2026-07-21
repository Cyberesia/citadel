import SwiftUI

/// Root Sentinel experience — independent of classic NetworkMonitorView.
struct SentinelShellView: View {
    @EnvironmentObject var vm: SentinelViewModel

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            BreadcrumbBar(
                focus: vm.focus,
                streams: vm.streams,
                onPop: { vm.popFocus() },
                onJumpAll: { vm.setFocus(.all) }
            )
            SentinelToolbar(vm: vm)
            Divider().opacity(0.25)

            HStack(spacing: 0) {
                SentinelNavTree(vm: vm)
                    .frame(width: 260)
                    .background(PrismTheme.surfaceMuted.opacity(0.35))

                Divider().opacity(0.3)

                SentinelMapPane(
                    arcs: vm.arcs,
                    origin: vm.mapOrigin,
                    projection: $vm.mapProjection
                )
                .padding(10)

                Divider().opacity(0.3)

                SentinelInspector(vm: vm)
                    .frame(width: 300)
                    .background(PrismTheme.surfaceMuted.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let alert = vm.pendingAlerts.first {
                alertBanner(alert)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if vm.isDemoMode {
            banner(
                icon: "sparkles",
                title: L10n.sentinelDemo,
                subtitle: L10n.sentinelDemoSubtitle,
                actionTitle: L10n.exitDemo,
                action: { vm.exitDemo() }
            )
        } else if vm.helperConnected {
            banner(
                icon: "bolt.fill",
                title: L10n.helperActive,
                subtitle: L10n.helperActiveSubtitle,
                actionTitle: nil,
                tint: .green
            )
        } else if vm.isRunning {
            banner(
                icon: "eye.fill",
                title: L10n.localSentinel,
                subtitle: L10n.helperOfflineBanner,
                actionTitle: L10n.loadDemo,
                action: { vm.loadDemo() }
            )
        } else {
            banner(
                icon: "bolt.slash.fill",
                title: L10n.sentinelIdle,
                subtitle: L10n.startingTelemetry,
                actionTitle: L10n.loadDemo,
                action: { vm.loadDemo() }
            )
        }
    }

    private func banner(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String?,
        action: (() -> Void)? = nil,
        tint: Color = PrismTheme.accent
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                Text(subtitle)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PrismTheme.accentSoft)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PrismTheme.surface.opacity(0.25))
    }

    private func alertBanner(_ alert: SentinelAlert) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill").foregroundStyle(PrismTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.connectionRequest)
                    .font(.ps(11, weight: .semibold))
                Text("\(alert.stream.process.name) → \(alert.stream.remoteHost.isEmpty ? alert.stream.remoteIP : alert.stream.remoteHost)")
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(L10n.deny) { vm.resolveAlert(alert, allow: false, remember: false) }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(11, weight: .semibold))
                .foregroundStyle(PrismTheme.signalDeny)
            Button(L10n.allow) { vm.resolveAlert(alert, allow: true, remember: false) }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(11, weight: .semibold))
                .foregroundStyle(PrismTheme.signalAllow)
            Button(L10n.rememberDeny) { vm.resolveAlert(alert, allow: false, remember: true) }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(10, weight: .medium))
            Button(L10n.rememberAllow) { vm.resolveAlert(alert, allow: true, remember: true) }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(10, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PrismTheme.accent.opacity(0.12))
    }
}
