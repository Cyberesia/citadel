import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum PrismMotion {
    public static let quick = Animation.spring(response: 0.32, dampingFraction: 0.86)
    public static let smooth = Animation.spring(response: 0.48, dampingFraction: 0.88)
    public static let drift = Animation.easeInOut(duration: 8).repeatForever(autoreverses: true)

    public static func reduced(_ animation: Animation) -> Animation? {
        #if os(macOS)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return nil
        }
        #else
        if UIAccessibility.isReduceMotionEnabled {
            return nil
        }
        #endif
        return animation
    }
}
