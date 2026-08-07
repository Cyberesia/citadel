import SwiftUI

struct BreadcrumbBar: View {
    let focus: MonitorFocus
    let streams: [NetworkStream]
    let onPop: () -> Void
    let onJumpAll: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            crumb(L10n.allApps, isCurrent: focus == .all, action: onJumpAll)
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, item in
                Image(systemName: "chevron.right")
                    .font(.ps(9, weight: .semibold))
                    .foregroundStyle(PrismTheme.textTertiary)
                crumb(item, isCurrent: index == crumbs.count - 1, action: onPop)
            }
            Spacer()
            if focus != .all {
                Button(L10n.back, action: onPop)
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(PrismTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var crumbs: [String] {
        switch focus {
        case .all:
            return []
        case .family(let id):
            let name = streams.first { $0.process.familyID == id }?.process.familyName ?? id
            return [name]
        case .role(let familyID, let role):
            let name = streams.first { $0.process.familyID == familyID }?.process.familyName ?? familyID
            return [name, role.label]
        case .host(let familyID, let hostKey):
            let name = streams.first { $0.process.familyID == familyID }?.process.familyName ?? familyID
            let label = streams.first { $0.process.familyID == familyID && $0.remoteKey == hostKey }?.remoteDisplayName
                ?? hostKey
            return [name, label]
        case .stream(let id):
            if let s = streams.first(where: { $0.id == id }) {
                return [s.process.familyName, s.remoteDisplayName]
            }
            return [L10n.stream]
        }
    }

    private func crumb(_ title: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ps(11, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? PrismTheme.textPrimary : PrismTheme.textSecondary)
                .lineLimit(1)
        }
        .buttonStyle(PrismHandButtonStyle())
    }
}
