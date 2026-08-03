import SwiftUI

public struct LivingCanvas<Content: View>: View {
    let palette: ExtractedPalette
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Float = 0

    public init(palette: ExtractedPalette, @ViewBuilder content: @escaping () -> Content) {
        self.palette = palette
        self.content = content
    }

    public var body: some View {
        ZStack {
            baseWash
                .allowsHitTesting(false)
            backdrop
                .allowsHitTesting(false)
            content()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(PrismMotion.reduced(PrismMotion.drift) ?? .default) {
                phase = 1
            }
        }
    }

    /// Stable dark base so selected photos never paint the whole window red.
    private var baseWash: some View {
        PrismTheme.dominantGradient
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var backdrop: some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            meshBackdrop
        } else {
            gradientBackdrop
        }
    }

    @available(macOS 15.0, iOS 18.0, *)
    private var meshBackdrop: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0), .init(0.5, 0), .init(1, 0),
                .init(0, 0.5), .init(0.5 + phase * 0.03, 0.5), .init(1, 0.5),
                .init(0, 1), .init(0.5, 1), .init(1, 1),
            ],
            colors: [
                palette.primary, palette.secondary, palette.accent,
                palette.secondary, palette.primary, palette.secondary,
                palette.accent, palette.secondary, palette.primary,
            ]
        )
        .ignoresSafeArea()
        .opacity(0.38)
        .blendMode(.plusLighter)
    }

    private var gradientBackdrop: some View {
        LinearGradient(
            colors: [palette.primary, palette.secondary, palette.accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .opacity(0.28)
    }
}
