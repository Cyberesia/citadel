import SwiftUI

/// Murmura-style auto-retractable reasoning card for assistant chain-of-thought.
struct CoworkThinkingCard: View {
    let text: String
    let isThinking: Bool
    let collapseAfter: Date?
    let persistedExpanded: Bool?
    /// When false, never auto-collapse (e.g. reply body still empty).
    var allowsAutoCollapse: Bool = true
    var onPersistExpanded: (Bool) -> Void = { _ in }
    var onAutoCollapsed: () -> Void = {}

    @State private var isExpanded: Bool

    private static let liveThinkingCap = 8_000

    private var displayText: String {
        guard isThinking, text.count > Self.liveThinkingCap else { return text }
        return String(text.suffix(Self.liveThinkingCap))
    }

    init(
        text: String,
        isThinking: Bool,
        collapseAfter: Date?,
        persistedExpanded: Bool?,
        allowsAutoCollapse: Bool = true,
        onPersistExpanded: @escaping (Bool) -> Void = { _ in },
        onAutoCollapsed: @escaping () -> Void = {}
    ) {
        self.text = text
        self.isThinking = isThinking
        self.collapseAfter = collapseAfter
        self.persistedExpanded = persistedExpanded
        self.allowsAutoCollapse = allowsAutoCollapse
        self.onPersistExpanded = onPersistExpanded
        self.onAutoCollapsed = onAutoCollapsed
        _isExpanded = State(
            initialValue: Self.initialExpanded(
                persisted: persistedExpanded,
                isThinking: isThinking,
                collapseAfter: collapseAfter,
                allowsAutoCollapse: allowsAutoCollapse
            )
        )
    }

    private static func initialExpanded(
        persisted: Bool?,
        isThinking: Bool,
        collapseAfter: Date?,
        allowsAutoCollapse: Bool
    ) -> Bool {
        if let persisted { return persisted }
        if isThinking { return true }
        if !allowsAutoCollapse { return true }
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
                        Text(isThinking ? L10n.reasoningActive : L10n.thinkingFinished)
                            .font(.ps(10, weight: .semibold))
                            .foregroundStyle(PrismTheme.textSecondary)
                        Spacer(minLength: 8)
                    }

                    if isExpanded {
                        // Plain monospaced like Murmura — never markdown-reparse reasoning (kills 27B FPS).
                        Text(displayText)
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
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear {
            if isExpanded, allowsAutoCollapse, persistedExpanded != true {
                scheduleCollapseIfNeeded(collapseAfter)
            }
        }
        .onChange(of: isThinking) { _, newValue in
            if newValue {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded = true
                }
            } else if isExpanded, allowsAutoCollapse, persistedExpanded != true {
                scheduleCollapseIfNeeded(collapseAfter)
            }
        }
        .onChange(of: persistedExpanded) { _, newValue in
            guard let newValue, newValue != isExpanded else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isExpanded = newValue
            }
        }
        .onChange(of: collapseAfter) { _, newValue in
            if isExpanded, allowsAutoCollapse, persistedExpanded != true, !isThinking {
                scheduleCollapseIfNeeded(newValue)
            }
        }
        .onChange(of: allowsAutoCollapse) { _, allowed in
            if !allowed, !isThinking {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded = true
                }
            }
        }
    }

    private func scheduleCollapseIfNeeded(_ finishedAt: Date?) {
        guard allowsAutoCollapse, isExpanded, persistedExpanded != true, !isThinking, let finishedAt else { return }
        let delay = max(0, finishedAt.timeIntervalSinceNow + 0.45)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard allowsAutoCollapse, isExpanded, persistedExpanded != true, !isThinking, collapseAfter == finishedAt else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                isExpanded = false
            }
            onPersistExpanded(false)
            onAutoCollapsed()
        }
    }
}
