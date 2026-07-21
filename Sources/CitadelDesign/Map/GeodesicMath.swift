import Foundation
import SceneKit

enum GeodesicMath {
    static func unitVector(_ point: GeoPoint) -> SIMD3<Double> {
        let lat = point.latitude * .pi / 180
        let lon = point.longitude * .pi / 180
        return SIMD3(
            cos(lat) * cos(lon),
            sin(lat),
            -cos(lat) * sin(lon)
        )
    }

    static func spherePoint(_ point: GeoPoint, radius: Float) -> SCNVector3 {
        let unit = unitVector(point)
        return SCNVector3(
            Float(unit.x) * radius,
            Float(unit.y) * radius,
            Float(unit.z) * radius
        )
    }

    // MARK: - Globe (SceneKit) — texture-aligned convention
    //
    // SCNSphere maps an equirectangular texture so that longitude 0 (the image's
    // horizontal centre) faces +Z, with the seam (±180°) at -Z. To place markers
    // that line up with the texture we must use:  x=cosLat·sinLon, y=sinLat, z=cosLat·cosLon.

    static func globeUnit(_ point: GeoPoint) -> SIMD3<Double> {
        let lat = point.latitude * .pi / 180
        let lon = point.longitude * .pi / 180
        return SIMD3(
            cos(lat) * sin(lon),
            sin(lat),
            cos(lat) * cos(lon)
        )
    }

    static func globePoint(_ point: GeoPoint, radius: Float) -> SCNVector3 {
        let u = globeUnit(point)
        return SCNVector3(Float(u.x) * radius, Float(u.y) * radius, Float(u.z) * radius)
    }

    static func globeArcPoints(from: GeoPoint, to: GeoPoint, segments: Int, radius: Float) -> [SCNVector3] {
        let start = globeUnit(from)
        let end = globeUnit(to)
        guard segments > 0 else { return [] }
        return (0...segments).map { index in
            let t = Double(index) / Double(segments)
            let u = slerp(start, end, t)
            return SCNVector3(Float(u.x) * radius, Float(u.y) * radius, Float(u.z) * radius)
        }
    }

    static func slerp(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
        let dot = min(max(simd_dot(a, b), -1.0), 1.0)
        if dot > 0.9995 {
            return simd_normalize(a + (b - a) * t)
        }
        let theta = acos(dot)
        let sinTheta = sin(theta)
        let w1 = sin((1 - t) * theta) / sinTheta
        let w2 = sin(t * theta) / sinTheta
        return simd_normalize(a * w1 + b * w2)
    }

    static func greatCirclePoints(from: GeoPoint, to: GeoPoint, segments: Int, radius: Float) -> [SCNVector3] {
        let start = unitVector(from)
        let end = unitVector(to)
        guard segments > 0 else { return [] }
        return (0...segments).map { index in
            let t = Double(index) / Double(segments)
            let unit = slerp(start, end, t)
            return SCNVector3(
                Float(unit.x) * radius,
                Float(unit.y) * radius,
                Float(unit.z) * radius
            )
        }
    }

    /// Equirectangular projection into a 2:1 map rectangle.
    static func project(_ point: GeoPoint, in mapRect: CGRect) -> CGPoint {
        let x = mapRect.minX + (point.longitude + 180) / 360 * mapRect.width
        let y = mapRect.minY + (90 - point.latitude) / 180 * mapRect.height
        return CGPoint(x: x, y: y)
    }

    static func project(_ point: GeoPoint, viewport: MapViewport, mapRect: CGRect) -> CGPoint {
        let base = project(point, in: mapRect)
        let center = CGPoint(x: mapRect.midX, y: mapRect.midY)
        return CGPoint(
            x: (base.x - center.x) * viewport.zoom + center.x + viewport.pan.width,
            y: (base.y - center.y) * viewport.zoom + center.y + viewport.pan.height
        )
    }

    static func flatArcPoints(
        from: GeoPoint,
        to: GeoPoint,
        segments: Int,
        viewport: MapViewport,
        mapRect: CGRect
    ) -> [CGPoint] {
        let start = unitVector(from)
        let end = unitVector(to)
        guard segments > 0 else { return [] }
        return (0...segments).map { index in
            let t = Double(index) / Double(segments)
            let unit = slerp(start, end, t)
            let lat = asin(unit.y) * 180 / .pi
            let lon = atan2(-unit.z, unit.x) * 180 / .pi
            return project(GeoPoint(latitude: lat, longitude: lon), viewport: viewport, mapRect: mapRect)
        }
    }
}
