import SwiftUI

/// Floating allow / deny prompt for paused network flows.
struct ConnectionAlertView: View {
    @EnvironmentObject var state: AppState
    let alert: AppState.PendingAlert
    @State private var remember = true
    @State private var scope: AlertScope = .thisHost
    @State private var duration: AlertDuration = .forever

    enum AlertScope: String, CaseIterable, Identifiable {
        case anyConnection
        case thisHost
        case thisIPandPort
        var id: String { rawValue }

        var label: String {
            switch self {
            case .anyConnection: return L10n.alertScopeAny
            case .thisHost: return L10n.alertScopeHost
            case .thisIPandPort: return L10n.alertScopeIPPort
            }
        }
    }

    enum AlertDuration: String, CaseIterable, Identifiable {
        case forever
        case session
        case oneHour
        case oneDay
        var id: String { rawValue }

        var label: String {
            switch self {
            case .forever: return L10n.alertDurationForever
            case .session: return L10n.alertDurationSession
            case .oneHour: return L10n.alertDuration1h
            case .oneDay: return L10n.alertDuration24h
            }
        }

        var expiresAt: Date? {
            switch self {
            case .forever: return nil
            case .session: return nil // marked via notes + temporary; purged on quit
            case .oneHour: return Date().addingTimeInterval(60 * 60)
            case .oneDay: return Date().addingTimeInterval(60 * 60 * 24)
            }
        }

        var isTemporary: Bool {
            self != .forever
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.ps(34))
                    .foregroundStyle(PrismTheme.accentGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.connection.processName.isEmpty ? L10n.unknownProcess : alert.connection.processName)
                        .font(.ps(17, weight: .bold))
                        .foregroundStyle(PrismTheme.textPrimary)
                    Text(L10n.wantsToConnect)
                        .font(.ps(11))
                        .foregroundStyle(PrismTheme.textSecondary)
                    Text(signingLine)
                        .font(.ps(10))
                        .foregroundStyle(signingColor)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "globe.americas")
                    .foregroundStyle(PrismTheme.trafficDown)
                Text(alert.connection.remoteHost.isEmpty ? alert.connection.remoteIP : alert.connection.remoteHost)
                    .font(.ps(14, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                if alert.connection.remotePort > 0 {
                    Text(":\(alert.connection.remotePort)")
                        .font(.ps(13))
                        .foregroundStyle(PrismTheme.textSecondary)
                }
                Spacer()
            }
            .padding(12)
            .background(PrismTheme.surface.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Toggle(L10n.rememberDecision, isOn: $remember)
                    .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                    .foregroundStyle(PrismTheme.textPrimary)
                Picker(L10n.scope, selection: $scope) {
                    ForEach(AlertScope.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!remember)
                Picker(L10n.duration, selection: $duration) {
                    ForEach(AlertDuration.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!remember)
            }

            HStack {
                Button(L10n.deny) {
                    state.resolveAlert(alert, allow: false, remember: remember, scope: scope, duration: duration)
                }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                Spacer()
                Button(L10n.allow) {
                    state.resolveAlert(alert, allow: true, remember: remember, scope: scope, duration: duration)
                }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
        .prismGlass(cornerRadius: 18, padding: 0)
    }

    private var signingLine: String {
        switch alert.connection.signingStatus {
        case .signedValid:
            if let team = alert.connection.codeTeamID, !team.isEmpty {
                return L10n.signedByTeam(team)
            }
            return L10n.signedValid
        case .signedInvalid:
            return L10n.signedInvalid
        case .unsigned:
            return L10n.unsignedBinary
        case .unknown:
            return L10n.signingUnknown
        }
    }

    private var signingColor: Color {
        switch alert.connection.signingStatus {
        case .signedValid: return PrismTheme.signalAllow
        case .signedInvalid, .unsigned: return PrismTheme.signalDeny
        case .unknown: return PrismTheme.textTertiary
        }
    }
}

struct AlertWindowContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if let alert = state.pendingAlerts.first {
                ConnectionAlertView(alert: alert)
                    .environmentObject(state)
            } else {
                EmptyView()
            }
        }
        .padding(8)
    }
}
