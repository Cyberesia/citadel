import SwiftUI

/// 60 / 30 / 10 color system for Prism UI.
/// - **60%** dominant field (background wash)
/// - **30%** secondary surfaces (panels, sidebars, glass)
/// - **10%** high-intensity accent (selection, CTAs, focus)
public enum PrismTheme {
    // MARK: 60% — dominant

    public static let dominant = Color(red: 0.06, green: 0.055, blue: 0.08)
    public static let dominantMid = Color(red: 0.09, green: 0.08, blue: 0.11)
    public static let dominantDeep = Color(red: 0.04, green: 0.035, blue: 0.05)

    // MARK: 30% — secondary surfaces

    public static let surface = Color(red: 0.17, green: 0.15, blue: 0.22)
    public static let surfaceElevated = Color(red: 0.24, green: 0.21, blue: 0.30)
    public static let surfaceMuted = Color(red: 0.13, green: 0.12, blue: 0.16)
    public static let borderSubtle = Color.white.opacity(0.10)
    public static let borderStrong = Color.white.opacity(0.18)

    // MARK: 10% — accent (high contrast)

    /// Primary pop color — coral-orange (use sparingly).
    public static let accent = Color(red: 1.0, green: 0.44, blue: 0.26)
    public static let accentSecondary = Color(red: 1.0, green: 0.72, blue: 0.35)
    public static let accentGlow = accent.opacity(0.42)
    public static let accentSoft = accent.opacity(0.16)

    // MARK: Text

    public static let textPrimary = Color.white.opacity(0.94)
    public static let textSecondary = Color.white.opacity(0.62)
    public static let textTertiary = Color.white.opacity(0.40)

    public static var dominantGradient: LinearGradient {
        LinearGradient(
            colors: [dominant, dominantMid],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: Traffic semantics (inbound rust · outbound gold)

    public static let trafficDown = accent
    public static let trafficUp = accentSecondary
    public static let signalAllow = Color(red: 0.28, green: 0.78, blue: 0.45)
    public static let signalDeny = Color(red: 0.95, green: 0.30, blue: 0.30)

    public static var trafficDownGradient: LinearGradient {
        LinearGradient(
            colors: [trafficDown.opacity(0.95), trafficDown.opacity(0.65)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public static var trafficUpGradient: LinearGradient {
        LinearGradient(
            colors: [trafficUp.opacity(0.75), trafficUp.opacity(0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public static var glassStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                borderStrong,
                accent.opacity(0.55),
                surfaceElevated.opacity(0.6),
                borderSubtle,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

public extension View {
    /// Applies the global accent tint for prominent controls.
    func prismAccentTint() -> some View {
        tint(PrismTheme.accent)
    }
}
