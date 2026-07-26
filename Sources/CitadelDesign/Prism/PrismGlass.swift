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

    /// Floating panel chrome for popovers and compact pickers.
    func prismPopoverChrome(width: CGFloat, maxHeight: CGFloat = 420) -> some View {
        frame(width: width)
            .frame(maxHeight: maxHeight)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PrismTheme.surface.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        PrismTheme.accent.opacity(0.07),
                                        PrismTheme.surfaceMuted.opacity(0.55),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(PrismTheme.glassStrokeGradient, lineWidth: 1)
                    }
            }
            .shadow(color: PrismTheme.dominantDeep.opacity(0.55), radius: 22, y: 10)
            .shadow(color: PrismTheme.accentGlow.opacity(0.18), radius: 28, y: 4)
    }

    /// Sheet / modal background aligned with Prism liquid glass.
    func prismSheetChrome(minWidth: CGFloat? = 720, minHeight: CGFloat? = 520) -> some View {
        background {
            ZStack {
                PrismTheme.dominantMid
                LinearGradient(
                    colors: [
                        PrismTheme.accent.opacity(0.10),
                        PrismTheme.surfaceMuted.opacity(0.88),
                        PrismTheme.dominantDeep.opacity(0.95),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
        .modifier(PrismSheetFrameModifier(minWidth: minWidth, minHeight: minHeight))
    }
}

private struct PrismSheetFrameModifier: ViewModifier {
    let minWidth: CGFloat?
    let minHeight: CGFloat?

    func body(content: Content) -> some View {
        if let minWidth, let minHeight {
            content.frame(minWidth: minWidth, minHeight: minHeight)
        } else if let minWidth {
            content.frame(minWidth: minWidth)
        } else if let minHeight {
            content.frame(minHeight: minHeight)
        } else {
            content
        }
    }
}

public struct PrismSelectableRow: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    public init(title: String, subtitle: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.ps(11, weight: .semibold))
                        .foregroundStyle(PrismTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.ps(9))
                            .foregroundStyle(PrismTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.ps(12, weight: .semibold))
                    .foregroundStyle(isSelected ? PrismTheme.accent : PrismTheme.textTertiary.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? PrismTheme.accentSoft : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PrismPlainHandButtonStyle())
    }
}
