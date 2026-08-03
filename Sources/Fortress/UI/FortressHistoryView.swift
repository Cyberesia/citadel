import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FortressHistoryView: View {
    @EnvironmentObject var state: AppState
    @State private var days = 7
    @State private var processFilter = ""
    @State private var hostFilter = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)
            if state.connectionHistory.isEmpty {
                empty
            } else {
                table
            }
        }
        .onAppear { reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.historyTitle)
                    .font(.ps(18, weight: .bold))
                    .foregroundStyle(PrismTheme.textPrimary)
                Spacer()
                Button(L10n.exportCSV) { exportCSV() }
                    .buttonStyle(PrismHandButtonStyle())
                Button(L10n.refresh) { reload() }
                    .buttonStyle(PrismHandButtonStyle())
            }
            Text(L10n.historySubtitle)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textTertiary)

            HStack(spacing: 12) {
                Picker(L10n.historyPeriod, selection: $days) {
                    Text(L10n.history1d).tag(1)
                    Text(L10n.history7d).tag(7)
                    Text(L10n.history30d).tag(30)
                }
                .frame(width: 160)
                .onChange(of: days) { _, _ in reload() }

                TextField(L10n.historyFilterApp, text: $processFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .onSubmit { reload() }

                TextField(L10n.historyFilterHost, text: $hostFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .onSubmit { reload() }
            }
        }
        .padding(16)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.ps(36))
                .foregroundStyle(PrismTheme.textTertiary)
            Text(L10n.historyEmpty)
                .font(.ps(13))
                .foregroundStyle(PrismTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var table: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(state.connectionHistory) { c in
                    HStack(spacing: 12) {
                        Text(c.processName)
                            .font(.ps(12, weight: .semibold))
                            .frame(width: 140, alignment: .leading)
                            .lineLimit(1)
                        Text(c.remoteHost.isEmpty ? c.remoteIP : c.remoteHost)
                            .font(.ps(12))
                            .foregroundStyle(PrismTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(c.remotePort > 0 ? "\(c.remotePort)" : "—")
                            .font(.ps(11).monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                        Text(c.status.rawValue)
                            .font(.ps(10, weight: .medium))
                            .foregroundStyle(statusColor(c.status))
                            .frame(width: 80, alignment: .leading)
                        Text(c.lastSeen, style: .relative)
                            .font(.ps(10))
                            .foregroundStyle(PrismTheme.textTertiary)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider().opacity(0.15)
                }
            }
        }
    }

    private func statusColor(_ s: Connection.Status) -> Color {
        switch s {
        case .denied: return PrismTheme.signalDeny
        case .allowed, .established: return PrismTheme.signalAllow
        case .pending: return PrismTheme.accent
        case .closed: return PrismTheme.textTertiary
        }
    }

    private func reload() {
        state.loadConnectionHistory(
            days: days,
            processName: processFilter.isEmpty ? nil : processFilter,
            hostQuery: hostFilter.isEmpty ? nil : hostFilter
        )
    }

    private func exportCSV() {
        let rows = state.connectionHistory.map { c -> String in
            let host = c.remoteHost.isEmpty ? c.remoteIP : c.remoteHost
            return "\(c.lastSeen.ISO8601Format()),\(escapeCSV(c.processName)),\(escapeCSV(host)),\(c.remotePort),\(c.status.rawValue),\(c.bytesIn),\(c.bytesOut)"
        }
        let body = "timestamp,process,host,port,status,bytes_in,bytes_out\n" + rows.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "citadel-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url {
            try? body.data(using: String.Encoding.utf8)?.write(to: url)
        }
    }

    private func escapeCSV(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}
