import SwiftUI

struct MetricSparkline: View {
    let values: [Int64]
    var tint: Color = PrismTheme.accent

    var body: some View {
        GeometryReader { geo in
            let pts = normalizedPoints(in: geo.size)
            if pts.count >= 2 {
                Path { path in
                    path.move(to: pts[0])
                    for p in pts.dropFirst() { path.addLine(to: p) }
                }
                .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 28)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2, size.width > 0, size.height > 0 else { return [] }
        let maxV = max(values.max() ?? 1, 1)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let x = CGFloat(i) * step
            let y = size.height - (CGFloat(v) / CGFloat(maxV)) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}
