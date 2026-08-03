import SwiftUI

struct CoworkUsageChip: View {
    let usage: CoworkTokenUsage?

    var body: some View {
        if let usage, usage.totalTokens > 0 {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.ps(9, weight: .semibold))
                Text("\(usage.totalTokens.formatted()) \(L10n.tokens)")
                    .font(.ps(9, weight: .semibold))
            }
            .foregroundStyle(PrismTheme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PrismTheme.surfaceMuted.opacity(0.45))
            .clipShape(Capsule())
            .help("Input \(usage.inputTokens) · Output \(usage.outputTokens)")
        }
    }
}

private extension Int {
    func formatted() -> String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.1fk", Double(self) / 1_000) }
        return "\(self)"
    }
}
