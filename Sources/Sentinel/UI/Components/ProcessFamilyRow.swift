import SwiftUI

struct ProcessFamilyRow: View {
    let node: ProcessFamilyNode
    let isSelected: Bool
    let depth: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.ps(11, weight: .semibold))
                .foregroundStyle(node.isAgent ? Color(red: 0.55, green: 0.38, blue: 1.0) : PrismTheme.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(node.title)
                        .font(.ps(12, weight: .medium))
                        .foregroundStyle(PrismTheme.textPrimary)
                        .lineLimit(1)
                    if node.isAgent {
                        Image(systemName: "sparkles")
                            .font(.ps(8))
                            .foregroundStyle(Color(red: 0.55, green: 0.38, blue: 1.0))
                    }
                }
                if let subtitle = node.subtitle {
                    Text(subtitle)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(rateLabel)
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)
                .monospacedDigit()
        }
        .padding(.leading, CGFloat(depth) * 12)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? PrismTheme.accent.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch node.kind {
        case .family: return "app.badge.fill"
        case .roleGroup(let role): return role.systemImage
        case .process: return "cpu"
        case .sites: return "globe"
        case .host: return "link"
        case .stream: return "arrow.left.arrow.right"
        }
    }

    private var rateLabel: String {
        if node.rateTotal > 0 { return SentinelFormat.bytesPerSec(node.rateTotal) }
        if node.bytesTotal > 0 { return SentinelFormat.bytes(node.bytesTotal) }
        return "\(node.connectionCount)"
    }
}

struct StreamRow: View {
    let stream: NetworkStream
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(stream.geo?.displayLabel ?? (stream.remoteHost.isEmpty ? stream.remoteIP : stream.remoteHost))
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                    .lineLimit(1)
                Text("\(stream.protocolName.uppercased()) · :\(stream.remotePort) · PID \(stream.process.pid)")
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(stream.rateTotal > 0
                 ? SentinelFormat.bytesPerSec(stream.rateTotal)
                 : SentinelFormat.bytes(stream.bytesTotal))
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? PrismTheme.accent.opacity(0.16) : Color.clear)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch stream.status {
        case .denied: return PrismTheme.signalDeny
        case .pending: return Color.orange
        default: return PrismTheme.trafficDown
        }
    }
}
