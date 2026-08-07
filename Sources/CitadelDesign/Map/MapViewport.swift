import Foundation
import SwiftUI

/// Zoom/pan state for the flat equirectangular map (2:1 aspect).
struct MapViewport: Equatable {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 8

    mutating func clamp() {
        zoom = min(Self.maxZoom, max(Self.minZoom, zoom))
        pan = clampedPan(for: pan, zoom: zoom)
    }

    mutating func applyZoom(delta: CGFloat, anchor: CGPoint, mapRect: CGRect) {
        let oldZoom = zoom
        zoom = min(Self.maxZoom, max(Self.minZoom, zoom * delta))
        guard oldZoom != zoom else { return }
        let center = CGPoint(x: mapRect.midX, y: mapRect.midY)
        let ratio = zoom / oldZoom
        pan.width = (pan.width + anchor.x - center.x) * ratio - (anchor.x - center.x)
        pan.height = (pan.height + anchor.y - center.y) * ratio - (anchor.y - center.y)
        clamp()
    }

    private func clampedPan(for pan: CGSize, zoom: CGFloat) -> CGSize {
        // Pan range grows with zoom so you can reach every edge of the zoomed map.
        // Roughly half the extra size the zoom introduces, plus a small base margin.
        let slack = 80 + (zoom - 1) * 700
        return CGSize(
            width: min(slack, max(-slack, pan.width)),
            height: min(slack, max(-slack, pan.height))
        )
    }
}

enum MapLayout {
    static let aspect: CGFloat = 2   // equirectangular is 2:1

    /// Aspect-FILL: the 2:1 map always covers the whole container (poles or
    /// edges cropped as needed) so there are never black letterbox bars.
    static func mapRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = max(size.width / aspect, size.height)
        let bw = aspect * scale
        let bh = scale
        return CGRect(x: (size.width - bw) / 2,
                      y: (size.height - bh) / 2,
                      width: bw, height: bh)
    }
}
