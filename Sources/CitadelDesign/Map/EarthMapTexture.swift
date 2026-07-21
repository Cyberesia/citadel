import AppKit
import SwiftUI

enum EarthMapTexture {
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cachedImage: NSImage?

    static var image: NSImage? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedImage { return cachedImage }

        if let url = Bundle.main.url(forResource: "earth-dark", withExtension: "jpg", subdirectory: "Textures"),
           let image = NSImage(contentsOf: url) {
            cachedImage = image
            return image
        }
        if let url = Bundle.main.url(forResource: "earth-dark", withExtension: "jpg"),
           let image = NSImage(contentsOf: url) {
            cachedImage = image
            return image
        }
        return nil
    }

    static var swiftUIImage: Image? {
        guard let image else { return nil }
        return Image(nsImage: image)
    }
}
