import SwiftUI

/// Floating allow / deny prompt for paused network flows.
struct ConnectionAlertView: View {
    @EnvironmentObject var state: AppState
    let alert: AppState.PendingAlert
    @State private var remember = true
    @State private var scope: AlertScope = .anyConnection
    @State private var duration: AlertDuration = .forever

    enum AlertScope: String, CaseIterable, Identifiable {
        case anyConnection = "any connection"
        case thisHost = "this host"
        case thisIPandPort = "this IP and port"
        var id: String { rawValue }
    }

    enum AlertDuration: String, CaseIterable, Identifiable {
        case forever = "Forever"
        case session = "Until quit"
        case oneHour = "1 hour"
        case oneDay = "24 hours"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.ps(34))
                    .foregroundStyle(PrismTheme.accentGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.connection.processName.isEmpty ? "Unknown" : alert.connection.processName)
                        .font(.ps(17, weight: .bold))
                        .foregroundStyle(PrismTheme.textPrimary)
                    Text("wants to connect to")
                        .font(.ps(11))
                        .foregroundStyle(PrismTheme.textSecondary)
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
                    ForEach(AlertScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(!remember)
                Picker(L10n.duration, selection: $duration) {
                    ForEach(AlertDuration.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(!remember)
            }

            HStack {
                Button(L10n.deny) { state.resolveAlert(alert, allow: false, remember: remember) }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                Spacer()
                Button(L10n.allow) { state.resolveAlert(alert, allow: true, remember: remember) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
        .padding(20)
        .frame(width: 440)
        .prismGlass(cornerRadius: 24, padding: 0)
        .preferredColorScheme(.dark)
    }
}

struct AlertOverlayContainer: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ZStack {
            if let alert = state.pendingAlerts.first {
                Color.black.opacity(0.45).ignoresSafeArea()
                ConnectionAlertView(alert: alert).environmentObject(state)
            }
        }
    }
}

struct AlertWindowContent: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Group {
            if let alert = state.pendingAlerts.first {
                ConnectionAlertView(alert: alert).environmentObject(state)
            } else {
                Color.clear.frame(width: 440, height: 1)
            }
        }
        .id(state.fontScale)
    }
}
