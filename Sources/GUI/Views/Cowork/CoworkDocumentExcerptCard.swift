import SwiftUI

/// Indexed document excerpt — Murmura-style collapsible block with think-tag shimmer.
struct CoworkDocumentExcerptCard: View {
    let excerpt: CoworkDocumentExcerpt
    var isShimmering: Bool

    @State private var isExpanded = true
    @State private var shimmerPhase = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(PrismTheme.accentSecondary)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: isShimmering ? "doc.text.magnifyingglass" : "doc.text.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PrismTheme.accentSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(excerpt.filename)
                                .font(.ps(10, weight: .semibold))
                                .foregroundStyle(PrismTheme.textPrimary)
                                .lineLimit(1)
                            Text(isShimmering ? L10n.documentIndexing : L10n.documentIndexed)
                                .font(.ps(9))
                                .foregroundStyle(PrismTheme.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PrismTheme.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }

                    if isExpanded {
                        Text(CoworkDocumentTextExtractor.cleanForDisplay(excerpt.content))
                            .font(.ps(10, design: .monospaced))
                            .foregroundStyle(PrismTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear {
            shimmerPhase = true
            isExpanded = isShimmering
        }
        .onChange(of: isShimmering) { _, active in
            if active {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded = true
                }
                shimmerPhase = true
            } else if isExpanded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isExpanded = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(PrismTheme.surfaceMuted.opacity(0.55))
            .overlay {
                if isShimmering {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, PrismTheme.accentSecondary.opacity(0.18), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(proxy.size.width * 0.45, 80))
                        .offset(x: shimmerPhase ? proxy.size.width : -proxy.size.width * 0.45)
                        .animation(
                            .linear(duration: 1.35).repeatForever(autoreverses: false),
                            value: shimmerPhase
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
    }
}
