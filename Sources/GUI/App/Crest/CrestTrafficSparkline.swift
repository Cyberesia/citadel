import SwiftUI

/// Slim dual-channel traffic sparkline for Crest — finer than the menubar popover chart.
struct CrestTrafficSparkline: View {
    let history: [TrafficSample]
    let currentIn: Int64
    let currentOut: Int64

    private var samples: [TrafficSample] {
        let slice = Array(history.suffix(48))
        if slice.isEmpty {
            return [TrafficSample(timestamp: Date(), bytesIn: 0, bytesOut: 0)]
        }
        return slice
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .trailing, spacing: 3) {
                Text("↓ \(CitadelFormat.bytesPerSec(currentIn))")
                    .font(.ps(10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PrismTheme.trafficDown)
                Text("↑ \(CitadelFormat.bytesPerSec(currentOut))")
                    .font(.ps(10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PrismTheme.trafficUp)
            }
            .frame(minWidth: 64, alignment: .trailing)

            chart
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PrismTheme.surface.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(PrismTheme.borderSubtle.opacity(0.7), lineWidth: 0.5)
                )
        )
    }

    private var chart: some View {
        GeometryReader { geo in
            let list = samples
            let count = max(list.count, 1)
            let gap: CGFloat = 1.0
            let barW = max(1.5, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            let midY = geo.size.height / 2
            let maxIn = max(1, CGFloat(list.map(\.bytesIn).max() ?? 1))
            let maxOut = max(1, CGFloat(list.map(\.bytesOut).max() ?? 1))
            let amp = midY - 1.5

            ZStack {
                // Soft midline
                Rectangle()
                    .fill(PrismTheme.borderSubtle.opacity(0.55))
                    .frame(height: 0.5)
                    .position(x: geo.size.width / 2, y: midY)

                HStack(alignment: .center, spacing: gap) {
                    ForEach(Array(list.enumerated()), id: \.offset) { _, sample in
                        let upH = max(1.2, CGFloat(sample.bytesOut) / maxOut * amp)
                        let downH = max(1.2, CGFloat(sample.bytesIn) / maxIn * amp)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Capsule(style: .continuous)
                                .fill(PrismTheme.trafficUpGradient)
                                .frame(width: barW, height: upH)
                                .opacity(0.9)
                            Capsule(style: .continuous)
                                .fill(PrismTheme.trafficDownGradient)
                                .frame(width: barW, height: downH)
                                .opacity(0.95)
                            Spacer(minLength: 0)
                        }
                        .frame(width: barW, height: geo.size.height)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
