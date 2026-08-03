import CoreGraphics
import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct ExtractedPalette: Sendable, Equatable {
    public var primary: Color
    public var secondary: Color
    public var accent: Color

    public static let defaultPalette = ExtractedPalette(
        primary: PrismTheme.surface,
        secondary: PrismTheme.dominantMid,
        accent: PrismTheme.accent
    )

    /// Blends a photo-derived palette with the calm default so the UI never floods red/orange.
    public func tempered(blend photoWeight: CGFloat = 0.22) -> ExtractedPalette {
        let base = Self.defaultPalette
        let w = min(max(photoWeight, 0), 0.4)
        return ExtractedPalette(
            primary: blend(base.primary, primary, w),
            secondary: blend(base.secondary, secondary, w * 0.9),
            accent: blend(base.accent, accent, w * 0.75)
        )
    }

    private func blend(_ a: Color, _ b: Color, _ weight: CGFloat) -> Color {
        let w = Double(weight)
        #if os(macOS)
        guard let ca = NSColor(a).usingColorSpace(.deviceRGB),
              let cb = NSColor(b).usingColorSpace(.deviceRGB) else { return a }
        let r = ca.redComponent * (1 - w) + cb.redComponent * w
        let g = ca.greenComponent * (1 - w) + cb.greenComponent * w
        let bl = ca.blueComponent * (1 - w) + cb.blueComponent * w
        return Color(red: r, green: g, blue: bl)
        #else
        return a
        #endif
    }
}

public enum ColorExtractor {
    public static func extract(from url: URL?) async -> ExtractedPalette {
        guard let url,
              FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [kCGImageSourceThumbnailMaxPixelSize: 64, kCGImageSourceCreateThumbnailFromImageAlways: true] as CFDictionary
              ) else {
            return .defaultPalette
        }

        let width = cgImage.width
        let height = cgImage.height
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return .defaultPalette }

        let bpp = cgImage.bitsPerPixel / 8
        var rSum: CGFloat = 0, gSum: CGFloat = 0, bSum: CGFloat = 0
        var count: CGFloat = 0
        let step = max(1, min(width, height) / 8)

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let offset = (y * cgImage.bytesPerRow) + (x * bpp)
                guard offset + 2 < CFDataGetLength(data) else { continue }
                let r = CGFloat(ptr[offset]) / 255
                let g = CGFloat(ptr[offset + 1]) / 255
                let b = CGFloat(ptr[offset + 2]) / 255
                rSum += r; gSum += g; bSum += b
                count += 1
            }
        }
        guard count > 0 else { return .defaultPalette }

        let r = rSum / count
        let g = gSum / count
        let b = bSum / count
        let raw = ExtractedPalette(
            primary: Color(red: r * 0.5, green: g * 0.5, blue: b * 0.7),
            secondary: Color(red: r * 0.65, green: g * 0.55, blue: b * 0.75),
            accent: Color(red: min(1, r * 0.5 + 0.15), green: min(1, g * 0.5 + 0.12), blue: min(1, b * 0.5 + 0.2))
        )
        return raw.tempered()
    }
}
