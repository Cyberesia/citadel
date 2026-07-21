import SwiftUI
import AppKit

/// Global, app-wide font scale factor. `Font.ps(...)` multiplies every explicit
/// font size by this value so text scales homogeneously across all windows.
enum AppFontScale {
    static let minimum: CGFloat = 0.8
    static let maximum: CGFloat = 1.6

    static var current: CGFloat = {
        let stored = UserDefaults.standard.object(forKey: "appFontScale") as? Double
        return stored.map { clamp(CGFloat($0)) } ?? 1.0
    }()

    static func clamp(_ v: CGFloat) -> CGFloat { Swift.min(maximum, Swift.max(minimum, v)) }

    static func dynamicTypeSize(for scale: CGFloat) -> DynamicTypeSize {
        switch scale {
        case ..<0.85: return .xSmall
        case ..<0.95: return .small
        case ..<1.05: return .large
        case ..<1.15: return .xLarge
        case ..<1.25: return .xxLarge
        case ..<1.35: return .xxxLarge
        case ..<1.45: return .accessibility1
        case ..<1.55: return .accessibility2
        default:      return .accessibility3
        }
    }
}

extension Font {
    static func ps(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size * AppFontScale.current, weight: weight, design: design)
    }
}

enum AppIcon {
    static func resolve(bundleId: String? = nil, path: String? = nil, name: String? = nil) -> NSImage? {
        let workspace = NSWorkspace.shared
        if let bundleId, !bundleId.isEmpty,
           let url = workspace.urlForApplication(withBundleIdentifier: bundleId) {
            return workspace.icon(forFile: url.path)
        }
        if let path, !path.isEmpty {
            var appPath = path
            if let range = appPath.range(of: ".app/", options: .backwards) {
                appPath = String(appPath[..<range.upperBound])
            }
            if FileManager.default.fileExists(atPath: appPath) {
                return workspace.icon(forFile: appPath)
            }
        }
        if let name, !name.isEmpty {
            let dirs = [
                "/Applications",
                "\(NSHomeDirectory())/Applications",
                "/System/Applications",
                "/Applications/Utilities",
                "/System/Applications/Utilities"
            ]
            for dir in dirs {
                let candidate = "\(dir)/\(name).app"
                if FileManager.default.fileExists(atPath: candidate) {
                    return workspace.icon(forFile: candidate)
                }
            }
        }
        return nil
    }
}

enum CitadelFormat {
    static func bytes(_ n: Int64) -> String {
        let b = Double(n)
        if b < 1024 { return "\(Int(b)) B" }
        if b < 1024 * 1024 { return String(format: "%.1f KB", b / 1024) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.1f MB", b / 1024 / 1024) }
        return String(format: "%.2f GB", b / 1024 / 1024 / 1024)
    }

    static func bytesPerSec(_ n: Int64) -> String { "\(bytes(n))/s" }

    static func compactCount(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.1fk", Double(n) / 1000) }
        return String(format: "%.1fM", Double(n) / 1_000_000)
    }
}

struct StatusChip: View {
    let text: String
    let color: Color
    let icon: String?

    init(_ text: String, color: Color = PrismTheme.accent, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.ps(9, weight: .bold))
            }
            Text(text).font(.ps(10, weight: .semibold))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.18))
        .foregroundColor(color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
    }
}

struct GlassPanel<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
        content()
            .background(PrismTheme.surfaceMuted.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PrismTheme.borderSubtle, lineWidth: 0.5)
            )
    }
}
