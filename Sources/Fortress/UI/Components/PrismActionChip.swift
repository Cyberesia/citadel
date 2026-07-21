import SwiftUI

/// Subtle Prism action chip — outline + soft fill, never blocky solid slabs.
struct PrismActionChip: View {
    enum Kind {
        case allow
        case deny
        case neutral
        case accent

        var foreground: Color {
            switch self {
            case .allow: return PrismTheme.signalAllow
            case .deny: return PrismTheme.signalDeny
            case .neutral: return PrismTheme.textSecondary
            case .accent: return PrismTheme.accent
            }
        }
    }

    let title: String
    var systemImage: String? = nil
    var kind: Kind = .neutral
    var emphasized: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.ps(10, weight: .semibold))
                }
                Text(title)
                    .font(.ps(11, weight: .semibold))
            }
            .foregroundStyle(kind.foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background {
                Capsule(style: .continuous)
                    .fill(kind.foreground.opacity(emphasized ? 0.18 : 0.10))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(kind.foreground.opacity(emphasized ? 0.45 : 0.28), lineWidth: 1)
            }
        }
        .buttonStyle(PrismHandButtonStyle())
    }
}
