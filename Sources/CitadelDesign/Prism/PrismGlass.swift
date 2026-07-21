import SwiftUI

public struct PrismGlass: ViewModifier {
    var cornerRadius: CGFloat
    var padding: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(cornerRadius: CGFloat = 24, padding: CGFloat = 0) {
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        let padded = content.padding(padding)

        if reduceTransparency {
            padded
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(PrismTheme.surface)
                        .shadow(color: PrismTheme.dominantDeep.opacity(0.5), radius: 12, y: 4)
                )
        } else if #available(macOS 26.0, iOS 26.0, *) {
            padded
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(PrismTheme.glassStrokeGradient, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: PrismTheme.dominantDeep.opacity(0.55), radius: 24, y: 12)
                .shadow(color: PrismTheme.accentGlow.opacity(0.2), radius: 32, y: 4)
        } else {
            padded
                .background(PrismFrostedGlassBackground(cornerRadius: cornerRadius))
        }
    }
}

/// Frosted glass fallback when Liquid Glass API is unavailable.
private struct PrismFrostedGlassBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PrismTheme.surfaceElevated.opacity(0.55),
                            PrismTheme.surface.opacity(0.72),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.20),
                            .white.opacity(0.04),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(PrismTheme.glassStrokeGradient, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: PrismTheme.dominantDeep.opacity(0.65), radius: 22, y: 10)
        .shadow(color: PrismTheme.accentGlow.opacity(0.22), radius: 28, y: 4)
    }
}

public extension View {
    func prismGlass(cornerRadius: CGFloat = 24, padding: CGFloat = 12) -> some View {
        modifier(PrismGlass(cornerRadius: cornerRadius, padding: padding))
    }
}
