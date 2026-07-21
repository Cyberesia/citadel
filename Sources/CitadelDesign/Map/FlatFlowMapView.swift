import SwiftUI

struct FlatFlowMapView: View {
    let arcs: [FlowArc]
    let origin: GeoPoint
    @Binding var viewport: MapViewport

    var body: some View {
        GeometryReader { geometry in
            let mapRect = MapLayout.mapRect(in: geometry.size)
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    Canvas { context, size in
                        let rect = MapLayout.mapRect(in: size)
                        var labelOccupied: [CGRect] = []
                        drawEarthMap(in: &context, viewport: viewport, mapRect: rect)
                        drawVignette(in: &context, mapRect: rect)
                        drawGrid(in: &context, viewport: viewport, mapRect: rect)
                        drawMapLabels(in: &context, viewport: viewport, mapRect: rect,
                                      occupied: &labelOccupied)
                        drawArcs(in: &context, viewport: viewport, mapRect: rect,
                                 phase: timeline.date.timeIntervalSinceReferenceDate,
                                 occupied: &labelOccupied)
                        drawOrigin(in: &context, viewport: viewport, mapRect: rect,
                                   phase: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }

                ScrollWheelZoomView(
                    onZoom: { delta, anchor in
                        var next = viewport
                        next.applyZoom(delta: delta, anchor: anchor, mapRect: mapRect)
                        viewport = next
                    },
                    onPan: { delta in
                        var next = viewport
                        next.pan = CGSize(width: next.pan.width + delta.width,
                                          height: next.pan.height + delta.height)
                        next.clamp()
                        viewport = next
                    }
                )
            }
        }
    }

    // MARK: - Draw layers

    private func drawEarthMap(in context: inout GraphicsContext, viewport: MapViewport, mapRect: CGRect) {
        // The texture must follow the SAME viewport transform as the arcs/labels,
        // otherwise zoom only moves the overlay and the map stays put.
        let topLeft = GeodesicMath.project(GeoPoint(latitude: 90, longitude: -180),
                                           viewport: viewport, mapRect: mapRect)
        let bottomRight = GeodesicMath.project(GeoPoint(latitude: -90, longitude: 180),
                                               viewport: viewport, mapRect: mapRect)
        let drawRect = CGRect(x: topLeft.x, y: topLeft.y,
                              width: bottomRight.x - topLeft.x,
                              height: bottomRight.y - topLeft.y)

        // Clip to the static letterbox so the texture never bleeds into the margins.
        var earthCtx = context
        earthCtx.clip(to: Path(mapRect))

        if let earth = EarthMapTexture.image {
            earthCtx.draw(Image(nsImage: earth), in: drawRect)
            earthCtx.fill(Path(mapRect), with: .color(.black.opacity(0.18)))
        } else {
            earthCtx.fill(Path(drawRect), with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.08),
                    Color(red: 0.06, green: 0.07, blue: 0.14),
                ]),
                startPoint: CGPoint(x: drawRect.minX, y: drawRect.minY),
                endPoint: CGPoint(x: drawRect.maxX, y: drawRect.maxY)
            ))
        }
    }

    private func drawVignette(in context: inout GraphicsContext, mapRect: CGRect) {
        context.fill(Path(mapRect), with: .radialGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0.50),
                .init(color: .black.opacity(0.60), location: 1.0),
            ]),
            center: CGPoint(x: mapRect.midX, y: mapRect.midY),
            startRadius: 0,
            endRadius: max(mapRect.width, mapRect.height) * 0.72
        ))
    }

    private func drawGrid(in context: inout GraphicsContext, viewport: MapViewport, mapRect: CGRect) {
        var grid = Path()
        for lat in stride(from: -60.0, through: 60.0, by: 30) {
            var line = Path(); var started = false
            for lon in stride(from: -180.0, through: 180.0, by: 8) {
                let p = GeodesicMath.project(GeoPoint(latitude: lat, longitude: lon),
                                             viewport: viewport, mapRect: mapRect)
                if started { line.addLine(to: p) } else { line.move(to: p); started = true }
            }
            grid.addPath(line)
        }
        context.stroke(grid, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
    }

    private func drawMapLabels(
        in context: inout GraphicsContext,
        viewport: MapViewport,
        mapRect: CGRect,
        occupied: inout [CGRect]
    ) {
        for place in MapLabels.visible(zoom: viewport.zoom) {
            let pt = GeodesicMath.project(place.point, viewport: viewport, mapRect: mapRect)
            guard mapRect.insetBy(dx: -20, dy: -20).contains(pt) else { continue }

            let fontSize: CGFloat = place.kind == .country
                ? max(11, min(13, 11 + viewport.zoom * 0.2))
                : max(10, min(12, 10 + viewport.zoom * 0.15))
            let estW = CGFloat(place.name.count) * fontSize * 0.52
            let labelR = CGRect(x: pt.x - estW/2, y: pt.y - fontSize/2,
                                width: estW, height: fontSize + 2)
            if occupied.contains(where: { $0.insetBy(dx: -6, dy: -3).intersects(labelR) }) { continue }
            occupied.append(labelR)

            context.draw(
                Text(place.name)
                    .font(.ps(fontSize, weight: place.kind == .country ? .semibold : .regular))
                    .foregroundColor(.white.opacity(place.kind == .country ? 0.52 : 0.72)),
                at: pt, anchor: .center
            )
        }
    }

    private func drawOrigin(
        in context: inout GraphicsContext,
        viewport: MapViewport, mapRect: CGRect, phase: TimeInterval
    ) {
        let c = GeodesicMath.project(origin, viewport: viewport, mapRect: mapRect)
        guard mapRect.insetBy(dx: -20, dy: -20).contains(c) else { return }

        for offset in [0.0, 1.1] {
            let t = CGFloat((phase + offset).truncatingRemainder(dividingBy: 3.0) / 3.0)
            let r = 5 + t * 18
            context.stroke(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2)),
                with: .color(PrismTheme.accent.opacity(Double((1 - t) * 0.55))),
                lineWidth: 1.5
            )
        }
        context.fill(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)),
                     with: .color(PrismTheme.accent.opacity(0.25)))
        context.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                     with: .color(PrismTheme.accent))
        let youSize: CGFloat = 12 * AppFontScale.current
        let youW = CGFloat("You".count) * youSize * 0.56
        let youRect = CGRect(x: c.x - youW / 2, y: c.y - 22 - youSize / 2,
                             width: youW, height: youSize + 2)
        drawPillLabel(in: &context, text: "You", size: youSize,
                      rect: youRect, textColor: PrismTheme.accent)
    }

    // MARK: - Arcs

    private func drawArcs(
        in context: inout GraphicsContext,
        viewport: MapViewport,
        mapRect: CGRect,
        phase: TimeInterval,
        occupied: inout [CGRect]
    ) {
        let bounds = mapRect.insetBy(dx: -140, dy: -140)

        for arc in arcs {
            let from = GeodesicMath.project(arc.origin, viewport: viewport, mapRect: mapRect)
            let to   = GeodesicMath.project(arc.destination, viewport: viewport, mapRect: mapRect)
            guard bounds.contains(from) || bounds.contains(to) else { continue }

            let col   = arc.strokeColor
            let base  = Color(red: col.red, green: col.green, blue: col.blue)

            let chord = hypot(to.x - from.x, to.y - from.y)
            let lift  = min(chord * 0.34, 90.0 / max(0.5, viewport.zoom))
            let ctrl  = CGPoint(x: (from.x + to.x) / 2,
                                y: (from.y + to.y) / 2 - lift)

            var path = Path()
            path.move(to: from)
            path.addQuadCurve(to: to, control: ctrl)

            // Subtle bloom — thin core + soft halo
            context.stroke(path, with: .color(base.opacity(0.06)),
                           style: StrokeStyle(lineWidth: arc.lineWidth * 4.5, lineCap: .round))
            context.stroke(path, with: .color(base.opacity(0.16)),
                           style: StrokeStyle(lineWidth: arc.lineWidth * 1.8, lineCap: .round))
            context.stroke(path, with: .color(base.opacity(0.62)),
                           style: StrokeStyle(lineWidth: max(0.6, arc.lineWidth * 0.75), lineCap: .round))

            for offset in [0.0, 1.1] {
                // Seed from destination so refresh/reorder doesn't jump the pulse.
                let seed = abs(arc.destination.latitude * 0.17 + arc.destination.longitude * 0.09)
                let rp = CGFloat(((phase * 0.38 + seed + offset)
                    .truncatingRemainder(dividingBy: 3.0)) / 3.0)
                let rr = 4 + rp * 16
                context.stroke(
                    Path(ellipseIn: CGRect(x: to.x - rr, y: to.y - rr, width: rr*2, height: rr*2)),
                    with: .color(base.opacity(Double(1 - rp) * 0.45)),
                    lineWidth: 0.9
                )
            }

            context.fill(Path(ellipseIn: CGRect(x: to.x - 6, y: to.y - 6, width: 12, height: 12)),
                         with: .color(base.opacity(0.18)))
            context.fill(Path(ellipseIn: CGRect(x: to.x - 3, y: to.y - 3, width: 6, height: 6)),
                         with: .color(base.opacity(0.92)))
            context.stroke(Path(ellipseIn: CGRect(x: to.x - 3, y: to.y - 3, width: 6, height: 6)),
                           with: .color(.white.opacity(0.45)), lineWidth: 0.6)

            let seed = abs(arc.destination.latitude * 0.13 + arc.destination.longitude * 0.07)
            let t = CGFloat((phase * 0.22 + seed).truncatingRemainder(dividingBy: 1.0))
            let pulse = quadBezier(from: from, control: ctrl, to: to, t: t)

            for step in 0..<5 {
                let ti = max(0, t - CGFloat(step) * 0.028)
                let tp = quadBezier(from: from, control: ctrl, to: to, t: ti)
                let a  = (1.0 - CGFloat(step) / 5.0) * 0.5
                let r  = max(1.2, 2.8 - CGFloat(step) * 0.35)
                context.fill(Path(ellipseIn: CGRect(x: tp.x - r, y: tp.y - r, width: r*2, height: r*2)),
                             with: .color(.white.opacity(a)))
            }
            context.fill(Path(ellipseIn: CGRect(x: pulse.x - 3.5, y: pulse.y - 3.5, width: 7, height: 7)),
                         with: .color(.white.opacity(0.92)))

            let labelSize = 12 * AppFontScale.current
            let estW = CGFloat(arc.label.count) * labelSize * 0.56
            let candidates: [(CGPoint, UnitPoint)] = [
                (CGPoint(x: to.x + 12, y: to.y - 6), .leading),
                (CGPoint(x: to.x - 12, y: to.y - 6), .trailing),
                (CGPoint(x: to.x, y: to.y - 16), .center),
                (CGPoint(x: to.x, y: to.y + 14), .center),
            ]
            for (anchor, unit) in candidates {
                let labelR = CGRect(
                    x: anchor.x - (unit == .trailing ? estW : (unit == .leading ? 0 : estW/2)),
                    y: anchor.y - labelSize/2,
                    width: estW,
                    height: labelSize + 2
                )
                guard !occupied.contains(where: { $0.insetBy(dx: -5, dy: -2).intersects(labelR) }) else {
                    continue
                }
                occupied.append(labelR)
                drawPillLabel(in: &context, text: arc.label, size: labelSize,
                              rect: labelR, textColor: .white.opacity(0.95))
                break
            }
        }
    }

    /// Dark rounded "badge" behind a label — matches the 3D globe pill style.
    private func drawPillLabel(
        in context: inout GraphicsContext,
        text: String, size: CGFloat, rect: CGRect, textColor: Color
    ) {
        let padX: CGFloat = 8, padY: CGFloat = 4
        let pill = rect.insetBy(dx: -padX, dy: -padY)
        let shape = Path(roundedRect: pill, cornerRadius: pill.height / 2, style: .continuous)
        context.fill(shape, with: .color(.black.opacity(0.55)))
        context.stroke(shape, with: .color(.white.opacity(0.16)), lineWidth: 1)
        context.draw(
            Text(text).font(.ps(size / AppFontScale.current, weight: .semibold))
                .foregroundColor(textColor),
            at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center
        )
    }

    // MARK: - Math

    private func quadBezier(from: CGPoint, control: CGPoint, to: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u*u*from.x + 2*u*t*control.x + t*t*to.x,
            y: u*u*from.y + 2*u*t*control.y + t*t*to.y
        )
    }
}
