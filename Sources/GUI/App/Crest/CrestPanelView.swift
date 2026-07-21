import SwiftUI
import AppKit

/// Compact Prism recover panel shown from the Crest hotspot.
struct CrestPanelView: View {
    @ObservedObject var state: AppState
    var windows: WindowManager
    var cowork: CoworkState?
    var reason: MenubarOcclusion.Report.Reason
    var hasNotch: Bool
    var onOpenCitadel: () -> Void
    var onOpenMenubar: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.ps(18, weight: .semibold))
                    .foregroundStyle(PrismTheme.accentGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.citadelCrest)
                        .font(.ps(13, weight: .semibold))
                        .foregroundStyle(PrismTheme.textPrimary)
                    Text(subtitle)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.textSecondary)
                }
                Spacer(minLength: 8)
            }

            CrestTrafficSparkline(
                history: state.trafficHistory,
                currentIn: state.currentIn,
                currentOut: state.currentOut
            )

            HStack(spacing: 8) {
                crestButton(L10n.tray, systemImage: "menubar.arrow.up.rectangle") {
                    onOpenMenubar()
                }
                crestButton(L10n.sentinelActivity, systemImage: "globe.americas.fill") {
                    onOpenCitadel()
                    windows.showNetworkMonitor()
                    onDismiss()
                }
                crestButton(L10n.sentinelRules, systemImage: "list.bullet.rectangle") {
                    onOpenCitadel()
                    windows.showRulesManager()
                    onDismiss()
                }
                crestButton(L10n.sentinelSettings, systemImage: "gearshape") {
                    onOpenCitadel()
                    windows.showSettings()
                    onDismiss()
                }
                if cowork != nil {
                    crestButton(L10n.keep, systemImage: "bubble.left.and.bubble.right") {
                        onOpenCitadel()
                        windows.showCowork()
                        onDismiss()
                    }
                }
            }

            if !pinnedApps.isEmpty {
                Divider().overlay(PrismTheme.borderSubtle)
                Text(L10n.quickOpen)
                    .font(.ps(10, weight: .semibold))
                    .foregroundStyle(PrismTheme.textTertiary)
                HStack(spacing: 8) {
                    ForEach(pinnedApps, id: \.self) { bundleID in
                        Button {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            }
                            onDismiss()
                        } label: {
                            if let icon = AppIcon.resolve(bundleId: bundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            } else {
                                Image(systemName: "app")
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .buttonStyle(PrismPlainHandButtonStyle())
                        .help(bundleID)
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PrismTheme.dominant.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(PrismTheme.borderSubtle, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        )
        .preferredColorScheme(.dark)
        .prismGlobalInteraction()
    }

    private var subtitle: String {
        switch reason {
        case .underNotch:
            return L10n.crestUnderNotch
        case .atRiskNearNotch:
            return L10n.crestAtRisk
        case .menuBarOverflow:
            return L10n.crestOverflow
        case .missingButton:
            return L10n.crestMissing
        case .visible:
            return hasNotch ? L10n.crestHoverNotch : L10n.crestTopCenter
        }
    }

    private var pinnedApps: [String] {
        UserDefaults.standard.stringArray(forKey: "citadel.crest.pinnedBundleIDs") ?? []
    }

    private func crestButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.ps(13, weight: .semibold))
                Text(title)
                    .font(.ps(10, weight: .medium))
            }
            .foregroundStyle(PrismTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(PrismTheme.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PrismPlainHandButtonStyle())
    }
}
