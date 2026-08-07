import SwiftUI

enum NetworkMapProjection: String, CaseIterable, Identifiable {
    case flat
    case globe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flat: return "2D"
        case .globe: return "3D"
        }
    }

    var systemImage: String {
        switch self {
        case .flat: return "map"
        case .globe: return "globe.americas.fill"
        }
    }
}

struct NetworkFlowMapView: View {
    let arcs: [FlowArc]
    let origin: GeoPoint
    @Binding var projection: NetworkMapProjection
    @Binding var viewport: MapViewport
    var selectedArcID: UUID?
    @State private var globeAutoRotate = true

    var body: some View {
        GeometryReader { geometry in
            let mapRect = MapLayout.mapRect(in: geometry.size)
            ZStack(alignment: .topTrailing) {
                Group {
                    switch projection {
                    case .flat:
                        FlatFlowMapView(arcs: arcs, origin: origin, viewport: $viewport)
                    case .globe:
                        GlobeSceneView(arcs: arcs, origin: origin, autoRotate: globeAutoRotate)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        projectionToggle
                        if projection == .globe {
                            freezeRotationButton
                        }
                    }
                    if projection == .flat {
                        zoomControls(mapRect: mapRect)
                    }
                }
                .padding(12)
            }
            .overlay(alignment: .bottomLeading) {
                if !arcs.isEmpty {
                    flowLegend
                        .padding(14)
                }
            }
            .overlay {
                if arcs.isEmpty {
                    emptyOverlay
                }
            }
        }
    }

    private func zoomControls(mapRect: CGRect) -> some View {
        let anchor = CGPoint(x: mapRect.midX, y: mapRect.midY)
        return HStack(spacing: 4) {
            mapControlButton(systemImage: "minus") {
                var next = viewport
                next.applyZoom(delta: 0.85, anchor: anchor, mapRect: mapRect)
                viewport = next
            }
            mapControlButton(systemImage: "plus") {
                var next = viewport
                next.applyZoom(delta: 1.15, anchor: anchor, mapRect: mapRect)
                viewport = next
            }
            mapControlButton(systemImage: "arrow.up.left.and.arrow.down.right") {
                viewport = MapViewport()
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(PrismTheme.borderSubtle, lineWidth: 0.5))
    }

    private func mapControlButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.ps(11, weight: .bold))
                .foregroundStyle(PrismTheme.textSecondary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(PrismHandButtonStyle())
    }

    private var freezeRotationButton: some View {
        Button {
            withAnimation(PrismMotion.quick) {
                globeAutoRotate.toggle()
            }
        } label: {
            Image(systemName: globeAutoRotate ? "pause.fill" : "play.fill")
                .font(.ps(11, weight: .bold))
                .foregroundStyle(globeAutoRotate ? PrismTheme.textSecondary : Color.white)
                .frame(width: 32, height: 32)
                .background {
                    if !globeAutoRotate {
                        Circle().fill(PrismTheme.accentGradient)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(Circle().stroke(PrismTheme.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(PrismHandButtonStyle())
        .help(globeAutoRotate ? L10n.freezeRotation : L10n.resumeRotation)
    }

    private var projectionToggle: some View {
        HStack(spacing: 4) {
            ForEach(NetworkMapProjection.allCases) { mode in
                Button {
                    withAnimation(PrismMotion.quick) {
                        projection = mode
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.systemImage)
                            .font(.ps(10, weight: .bold))
                        Text(mode.label)
                            .font(.ps(12, weight: .semibold))
                    }
                    .foregroundStyle(projection == mode ? Color.white : PrismTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        if projection == mode {
                            Capsule(style: .continuous)
                                .fill(PrismTheme.accentGradient)
                        }
                    }
                }
                .buttonStyle(PrismHandButtonStyle())
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(PrismTheme.borderSubtle, lineWidth: 0.5))
    }

    private var flowLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(color: PrismTheme.trafficUp, label: L10n.outbound)
            legendRow(color: PrismTheme.trafficDown, label: L10n.inbound)
            legendRow(color: Color(red: 0.95, green: 0.28, blue: 0.28), label: L10n.denied)
            Text(L10n.activeFlows(arcs.count))
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textTertiary)
            if projection == .flat {
                Text(L10n.mapZoomHint)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
            } else {
                Text(globeAutoRotate ? L10n.mapRotateHint : L10n.mapFrozenHint)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PrismTheme.borderSubtle, lineWidth: 0.5)
        )
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.ps(10, weight: .medium))
                .foregroundStyle(PrismTheme.textSecondary)
        }
    }

    private var emptyOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.ps(34, weight: .semibold))
                .foregroundStyle(PrismTheme.textTertiary)
            Text(L10n.noPublicDestinations)
                .font(.ps(15, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
            Text(L10n.privateVPNMapHint)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(24)
    }
}
