import SwiftUI

/// Compact + expandable conversation token usage (Aisance conversation-usage-summary).
struct CoworkConversationUsageView: View {
    let stats: CoworkConversationUsageStats
    let lastTurn: CoworkTokenUsage?
    @State private var expanded = false

    var body: some View {
        if stats.totalTokens > 0 || (lastTurn?.totalTokens ?? 0) > 0 {
            VStack(alignment: .trailing, spacing: 6) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(.ps(9, weight: .semibold))
                        Text(chipLabel)
                            .font(.ps(9, weight: .semibold))
                        if stats.turnCount > 1 {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.ps(7, weight: .bold))
                        }
                    }
                    .foregroundStyle(PrismTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PrismTheme.surfaceMuted.opacity(0.45))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(helpText)

                if expanded && stats.turnCount > 0 {
                    expandedPanel
                }
            }
        }
    }

    private var chipLabel: String {
        let total = stats.totalTokens > 0 ? stats.totalTokens : (lastTurn?.totalTokens ?? 0)
        return "\(total.formattedCompact()) \(L10n.tokens)"
    }

    private var helpText: String {
        if stats.turnCount > 0 {
            return L10n.usageHelp(stats.totalInputTokens, stats.totalOutputTokens, stats.turnCount)
        }
        if let lastTurn {
            return "Input \(lastTurn.inputTokens) · Output \(lastTurn.outputTokens)"
        }
        return ""
    }

    private var estimatedSessionCost: Double? {
        guard stats.totalInputTokens > 0 || stats.totalOutputTokens > 0 else { return nil }
        let primaryModel = stats.modelCounts.max(by: { $0.value < $1.value })?.key
        guard let primaryModel else { return nil }
        return CoworkCloudModelCatalog.estimatedCostUSD(
            inputTokens: stats.totalInputTokens,
            outputTokens: stats.totalOutputTokens,
            modelID: primaryModel
        )
    }

    private var byokCapNote: String? {
        let limits = CoworkBYOKTokenLimitsStore.load()
        guard let primaryModel = stats.modelCounts.max(by: { $0.value < $1.value })?.key,
              let cap = CoworkBYOKTokenLimitsStore.cap(for: primaryModel, settings: limits) else { return nil }
        return "BYOK cap: \(cap) output tokens / turn"
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                statBlock(title: L10n.totalTokens, value: stats.totalTokens.formattedCompact())
                statBlock(title: L10n.avgPerTurn, value: stats.averageTokensPerTurn.formattedCompact())
                statBlock(title: L10n.turns, value: "\(stats.turnCount)")
            }

            if let cost = estimatedSessionCost {
                statBlock(title: L10n.estimatedCost, value: String(format: "$%.3f", cost))
            }

            if let capNote = byokCapNote {
                Text(capNote)
                    .font(.ps(9))
                    .foregroundStyle(PrismTheme.textSecondary)
            }

            if !stats.modelCounts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.modelsUsed)
                        .font(.ps(9, weight: .semibold))
                        .foregroundStyle(PrismTheme.textSecondary)
                    FlowLayout(spacing: 6) {
                        ForEach(stats.modelCounts.sorted(by: { $0.value > $1.value }), id: \.key) { key, count in
                            tag("\(key) ×\(count)")
                        }
                    }
                }
            }

            if !stats.providerCounts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.providersUsed)
                        .font(.ps(9, weight: .semibold))
                        .foregroundStyle(PrismTheme.textSecondary)
                    FlowLayout(spacing: 6) {
                        ForEach(stats.providerCounts.sorted(by: { $0.value > $1.value }), id: \.key) { key, count in
                            tag("\(key) ×\(count)")
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
        .background(PrismTheme.surfaceMuted.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.ps(8, weight: .semibold))
                .foregroundStyle(PrismTheme.textTertiary)
            Text(value)
                .font(.ps(11, weight: .bold, design: .rounded))
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.ps(8, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(PrismTheme.surface.opacity(0.8))
            .clipShape(Capsule())
    }
}

private extension Int {
    func formattedCompact() -> String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.1fk", Double(self) / 1_000) }
        return "\(self)"
    }
}

/// Simple horizontal flow for usage tags.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
