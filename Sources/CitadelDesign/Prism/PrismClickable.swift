import SwiftUI

#if os(macOS)
import AppKit

private struct PrismClickableModifier: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 15.0, *) {
                content
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            NSCursor.pointingHand.push()
                        case .ended:
                            NSCursor.pop()
                        }
                    }
                    .pointerStyle(.link)
            } else {
                content
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            NSCursor.pointingHand.push()
                        case .ended:
                            NSCursor.pop()
                        }
                    }
            }
        }
    }
}

public extension View {
    /// Hand cursor on hover (macOS). Apply to every tappable control including `Button`.
    func prismClickable() -> some View {
        modifier(PrismClickableModifier())
    }

    /// Hand cursor on segmented pickers and similar controls.
    func prismSegmentedControl() -> some View {
        prismClickable()
    }

    /// Default Prism interaction affordances for shell roots (buttons + toggles).
    func prismGlobalInteraction() -> some View {
        buttonStyle(PrismHandButtonStyle())
            .toggleStyle(PrismHandToggleStyle())
    }
}

/// Plain button style that always shows the hand cursor.
public struct PrismHandButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .prismClickable()
    }
}

/// Plain / borderless controls with hand cursor (replaces `.buttonStyle(.plain)`).
public struct PrismPlainHandButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .prismClickable()
    }
}

/// Toggle style that preserves native checkbox/switch chrome but shows a hand cursor.
public struct PrismHandToggleStyle: ToggleStyle {
    public enum Kind {
        case automatic
        case checkbox
        case `switch`
    }

    private let kind: Kind

    public init(kind: Kind = .automatic) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            nativeToggle(configuration)
        }
        .prismClickable()
    }

    @ViewBuilder
    private func nativeToggle(_ configuration: Configuration) -> some View {
        switch kind {
        case .automatic:
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
        case .checkbox:
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
        case .switch:
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
#else
public extension View {
    func prismClickable() -> some View { self }
    func prismSegmentedControl() -> some View { self }
    func prismGlobalInteraction() -> some View { self }
}

public struct PrismHandButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.88 : 1)
    }
}

public struct PrismPlainHandButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.88 : 1)
    }
}

public struct PrismHandToggleStyle: ToggleStyle {
    public enum Kind { case automatic, checkbox, `switch` }
    private let kind: Kind
    public init(kind: Kind = .automatic) { self.kind = kind }
    public func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) { configuration.label }
    }
}
#endif
