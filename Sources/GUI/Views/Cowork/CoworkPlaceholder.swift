import SwiftUI

@ViewBuilder
func coworkPlaceholder(icon: String, title: String, subtitle: String) -> some View {
    VStack(spacing: 16) {
        Spacer()
        Image(systemName: icon)
            .font(.system(size: 40))
            .foregroundStyle(PrismTheme.textTertiary)
        Text(title)
            .font(.ps(20, weight: .semibold, design: .rounded))
            .foregroundStyle(PrismTheme.textPrimary)
        Text(subtitle)
            .font(.ps(12))
            .foregroundStyle(PrismTheme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(32)
}
