import SwiftUI

/// Murmura-style auto-retractable reasoning card for assistant chain-of-thought.
struct CoworkThinkingCard: View {
    let text: String
    let isThinking: Bool
    let collapseAfter: Date?
    let persistedExpanded: Bool?
    var onPersistExpanded: (Bool) -> Void = { _ in }
    var onAutoCollapsed: () -> Void = {}

    @State private var isExpanded: Bool
    @State private var shimmerPhase = false

    init(
        text: String,
        isThinking: Bool,
        collapseAfter: Date?,
        persistedExpanded: Bool?,
        onPersistExpanded: @escaping (Bool) -> Void = { _ in },
        onAutoCollapsed: @escaping () -> Void = {}
    ) {
        self.text = text
        self.isThinking = isThinking
        self.collapseAfter = collapseAfter
        self.persistedExpanded = persistedExpanded
        self.onPersistExpanded = onPersistExpanded
        self.onAutoCollapsed = onAutoCollapsed
        _isExpanded = State(
            initialValue: Self.initialExpanded(
                persisted: persistedExpanded,
                isThinking: isThinking,
                collapseAfter: collapseAfter
            )
        )
    }

    private static func initialExpanded(persisted: Bool?, isThinking: Bool, collapseAfter: Date?) -> Bool {
        if let persisted { return persisted }
        if isThinking { return true }
        guard let collapseAfter, !isThinking else { return true }
        return Date().timeIntervalSince(collapseAfter) <= 0.45
    }

    var body: some View {
        Button {
            let next = !isExpanded
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isExpanded = next
            }
            onPersistExpanded(next)
        } label: {
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(PrismTheme.accentSecondary)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: isThinking ? "sparkles" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PrismTheme.accentSecondary)
                            .rotationEffect(.degrees(isExpanded && !isThinking ? 90 : 0))
                        Text(isThinking ? "Reasoning…" : "Reasoning")
                            .font(.ps(10, weight: .semibold))
                            .foregroundStyle(PrismTheme.textSecondary)
                        Spacer(minLength: 8)
                    }

                    if isExpanded {
                        Text(text)
                            .font(.ps(10, design: .monospaced))
                            .foregroundStyle(PrismTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PrismTheme.surfaceMuted.opacity(0.42))
                    .overlay {
                        if isThinking {
                            GeometryReader { proxy in
                                LinearGradient(
                                    colors: [.clear, PrismTheme.accentSecondary.opacity(0.16), .clear],
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
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear {
            shimmerPhase = true
            if isExpanded, persistedExpanded != true {
                scheduleCollapseIfNeeded(collapseAfter)
            }
        }
        .onChange(of: persistedExpanded) { _, newValue in
            guard let newValue, newValue != isExpanded else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isExpanded = newValue
            }
        }
        .onChange(of: isThinking) { _, newValue in
            if newValue {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded = true
                }
                shimmerPhase = true
            }
        }
        .onChange(of: collapseAfter) { _, newValue in
            if isExpanded, persistedExpanded != true {
                scheduleCollapseIfNeeded(newValue)
            }
        }
    }

    private func scheduleCollapseIfNeeded(_ finishedAt: Date?) {
        guard isExpanded, persistedExpanded != true, !isThinking, let finishedAt else { return }
        let delay = max(0, finishedAt.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isExpanded, persistedExpanded != true, !isThinking, collapseAfter == finishedAt else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                isExpanded = false
            }
            onPersistExpanded(false)
            onAutoCollapsed()
        }
    }
}
