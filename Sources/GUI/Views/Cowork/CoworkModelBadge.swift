import SwiftUI

/// Shows model alias, optional technical name, and provider (MLX, Ollama, OpenAI, …).
struct CoworkModelBadge: View {
    let display: CoworkUserFacing.ModelDisplay
    var compact: Bool = false

    var body: some View {
        if compact {
            Text(display.summary)
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)
                .lineLimit(1)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(display.alias)
                    .font(.ps(12, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                    .lineLimit(1)
                if let subtitle = subtitleLine {
                    Text(subtitle)
                        .font(.ps(9, weight: .medium))
                        .foregroundStyle(PrismTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var subtitleLine: String? {
        var parts: [String] = []
        if let technical = display.technical, !technical.isEmpty,
           technical.caseInsensitiveCompare(display.alias) != .orderedSame {
            parts.append(technical)
        }
        if !display.provider.isEmpty { parts.append(display.provider) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
