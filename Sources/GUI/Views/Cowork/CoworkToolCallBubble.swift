import SwiftUI

struct CoworkToolCallBubble: View {
    let tool: CoworkNormalizedToolCall
    @State private var expanded = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    statusDot
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.name)
                            .font(.ps(12, weight: .semibold))
                            .foregroundStyle(PrismTheme.textPrimary)
                        if let description = tool.description, !description.isEmpty {
                            Text(description)
                                .font(.ps(10))
                                .foregroundStyle(PrismTheme.textSecondary)
                                .lineLimit(expanded ? nil : 1)
                        }
                    }
                    Spacer()
                    if tool.input != nil || tool.output != nil {
                        Button { expanded.toggle() } label: {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.ps(10, weight: .bold))
                                .foregroundStyle(PrismTheme.textTertiary)
                        }
                        .buttonStyle(PrismHandButtonStyle())
                    }
                }

                if expanded {
                    if let input = tool.input, !input.isEmpty {
                        toolSection("Input", input)
                    }
                    if let output = tool.output, !output.isEmpty {
                        toolSection("Output", output)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PrismTheme.surfaceMuted.opacity(0.55))
            )
            Spacer(minLength: 24)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch tool.status {
        case .completed: return PrismTheme.signalAllow
        case .error: return PrismTheme.signalDeny
        case .running: return PrismTheme.accentSecondary
        case .canceled: return PrismTheme.textTertiary
        case .pending: return PrismTheme.textTertiary.opacity(0.6)
        }
    }

    private func toolSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.ps(9, weight: .bold))
                .foregroundStyle(PrismTheme.textTertiary)
            Text(body)
                .font(.ps(10, design: .monospaced))
                .foregroundStyle(PrismTheme.textSecondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct CoworkTipsBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PrismTheme.signalDeny)
            Text(message)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PrismTheme.signalDeny.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CoworkInfoBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(PrismTheme.accentSecondary)
            Text(message)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PrismTheme.accentSoft.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
