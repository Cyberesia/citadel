import SwiftUI

/// Sentinel map pane — adapts Sentinel arcs into the shared CitadelDesign map views.
struct SentinelMapPane: View {
    let arcs: [SentinelFlowArc]
    let origin: SentinelGeoPoint
    @Binding var projection: SentinelMapProjection
    @State private var viewport = MapViewport()

    private var adaptedArcs: [FlowArc] {
        arcs.map { arc in
            FlowArc(
                id: arc.id,
                origin: GeoPoint(latitude: arc.origin.latitude, longitude: arc.origin.longitude),
                destination: GeoPoint(latitude: arc.destination.latitude, longitude: arc.destination.longitude),
                bytesIn: arc.bytesIn,
                bytesOut: arc.bytesOut,
                bytesInRate: arc.rateIn,
                bytesOutRate: arc.rateOut,
                status: connectionStatus(arc.status),
                label: arc.label,
                subtitle: arc.subtitle,
                processName: arc.processName,
                isAgent: arc.isAgent
            )
        }
    }

    private var adaptedOrigin: GeoPoint {
        GeoPoint(latitude: origin.latitude, longitude: origin.longitude)
    }

    private var adaptedProjection: Binding<NetworkMapProjection> {
        Binding(
            get: {
                switch projection {
                case .flat: return .flat
                case .globe: return .globe
                }
            },
            set: { newValue in
                projection = newValue == .flat ? .flat : .globe
            }
        )
    }

    var body: some View {
        NetworkFlowMapView(
            arcs: adaptedArcs,
            origin: adaptedOrigin,
            projection: adaptedProjection,
            viewport: $viewport
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connectionStatus(_ s: StreamStatus) -> Connection.Status {
        switch s {
        case .allowed: return .allowed
        case .denied: return .denied
        case .pending: return .pending
        case .established: return .established
        case .closed: return .closed
        }
    }
}
