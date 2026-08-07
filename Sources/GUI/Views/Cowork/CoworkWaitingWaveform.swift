import SwiftUI

/// Animated “assistant is thinking” indicator (Murmura-class waveform).
struct CoworkWaitingWaveform: View {
    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    drawWaveform(in: size, context: context, time: time)
                }
            }
            .frame(width: 220, height: 44)
            .accessibilityLabel(L10n.assistantResponding)

            Text(L10n.thinkingLabel)
                .font(.ps(10, weight: .medium))
                .foregroundStyle(PrismTheme.textSecondary.opacity(pulseOpacity))
        }
        .padding(.vertical, 4)
    }

    private var pulseOpacity: Double {
        let t = Date().timeIntervalSinceReferenceDate
        return 0.55 + 0.35 * (sin(t * 2.3) + 1) / 2
    }

    private func drawWaveform(in size: CGSize, context: GraphicsContext, time: TimeInterval) {
        let width = max(size.width, 1)
        let midY = size.height / 2
        let columnSpacing: CGFloat = 4
        let columns = max(1, Int(width / columnSpacing))
        let accent = PrismTheme.accentSecondary

        for column in 0...columns {
            let x = CGFloat(column) * columnSpacing
            let progress = Double(x / width)
            let phase = time * 2.8 - progress * 5.5
            let envelope = 0.25 + 0.75 * pow(sin(progress * .pi), 1.4)
            let amplitude = envelope * (0.35 + 0.65 * (sin(phase * 1.7) + 1) / 2)
            let barHeight = max(3, CGFloat(amplitude) * size.height * 0.42)

            var path = Path()
            path.addRoundedRect(
                in: CGRect(x: x, y: midY - barHeight / 2, width: 2.2, height: barHeight),
                cornerSize: CGSize(width: 1.1, height: 1.1)
            )
            context.fill(path, with: .color(accent.opacity(0.55 + 0.45 * amplitude)))
        }
    }
}
