import SwiftUI

public struct PrismGlass: ViewModifier {
    var cornerRadius: CGFloat
    var padding: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(cornerRadius: CGFloat = 24, padding: CGFloat = 0) {
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        let padded = content.padding(padding)

        if reduceTransparency {
            padded
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(PrismTheme.surface)
                        .shadow(color: PrismTheme.dominantDeep.opacity(0.5), radius: 12, y: 4)
                )
        } else if #available(macOS 26.0, iOS 26.0, *) {
            padded
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(PrismTheme.glassStrokeGradient, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: PrismTheme.dominantDeep.opacity(0.55), radius: 24, y: 12)
                .shadow(color: PrismTheme.accentGlow.opacity(0.2), radius: 32, y: 4)
        } else {
            padded
                .background(PrismFrostedGlassBackground(cornerRadius: cornerRadius))
        }
    }
}

/// Frosted glass fallback when Liquid Glass API is unavailable.
private struct PrismFrostedGlassBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PrismTheme.surfaceElevated.opacity(0.55),
                            PrismTheme.surface.opacity(0.72),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.20),
                            .white.opacity(0.04),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(PrismTheme.glassStrokeGradient, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: PrismTheme.dominantDeep.opacity(0.65), radius: 22, y: 10)
        .shadow(color: PrismTheme.accentGlow.opacity(0.22), radius: 28, y: 4)
    }
}

public extension View {
    func prismGlass(cornerRadius: CGFloat = 24, padding: CGFloat = 12) -> some View {
        modifier(PrismGlass(cornerRadius: cornerRadius, padding: padding))
    }

    /// Floating panel chrome for popovers and compact pickers.
    func prismPopoverChrome(width: CGFloat, maxHeight: CGFloat = 420) -> some View {
        frame(width: width)
            .frame(maxHeight: maxHeight)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PrismTheme.surface.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        PrismTheme.accent.opacity(0.07),
                                        PrismTheme.surfaceMuted.opacity(0.55),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(PrismTheme.glassStrokeGradient, lineWidth: 1)
                    }
            }
            .shadow(color: PrismTheme.dominantDeep.opacity(0.55), radius: 22, y: 10)
            .shadow(color: PrismTheme.accentGlow.opacity(0.18), radius: 28, y: 4)
    }

    /// Sheet / modal background aligned with Prism liquid glass.
    func prismSheetChrome(minWidth: CGFloat? = 720, minHeight: CGFloat? = 520) -> some View {
        background {
            ZStack {
                PrismTheme.dominantMid
                LinearGradient(
                    colors: [
                        PrismTheme.accent.opacity(0.10),
                        PrismTheme.surfaceMuted.opacity(0.88),
                        PrismTheme.dominantDeep.opacity(0.95),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
        .modifier(PrismSheetFrameModifier(minWidth: minWidth, minHeight: minHeight))
    }
}

private struct PrismSheetFrameModifier: ViewModifier {
    let minWidth: CGFloat?
    let minHeight: CGFloat?

    func body(content: Content) -> some View {
        if let minWidth, let minHeight {
            content.frame(minWidth: minWidth, minHeight: minHeight)
        } else if let minWidth {
            content.frame(minWidth: minWidth)
        } else if let minHeight {
            content.frame(minHeight: minHeight)
        } else {
            content
        }
    }
}

public struct PrismSelectableRow: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    public init(title: String, subtitle: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.ps(11, weight: .semibold))
                        .foregroundStyle(PrismTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.ps(9))
                            .foregroundStyle(PrismTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.ps(12, weight: .semibold))
                    .foregroundStyle(isSelected ? PrismTheme.accent : PrismTheme.textTertiary.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? PrismTheme.accentSoft : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PrismPlainHandButtonStyle())
    }
}

// MARK: - Activity banner

/// Status line with vertical roller swaps + soft shimmer (Keep activity / streaming).
public struct PrismRollingShimmerText: View {
    public let text: String
    public var font: Font
    public var color: Color
    public var lineLimit: Int
    public var shimmer: Bool

    @State private var displayed: String
    @State private var rollToken = 0
    @State private var shimmerPhase = false
    @State private var marqueePhase = false
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    public init(
        text: String,
        font: Font = .system(size: 11, weight: .medium),
        color: Color = PrismTheme.textPrimary,
        lineLimit: Int = 1,
        shimmer: Bool = true
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.lineLimit = lineLimit
        self.shimmer = shimmer
        _displayed = State(initialValue: text)
    }

    public var body: some View {
        GeometryReader { proxy in
            let needsMarquee = textWidth > proxy.size.width + 4
            ZStack(alignment: .leading) {
                rollerLine(displayed)
                    .id(rollToken)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
                    .offset(x: needsMarquee && marqueePhase ? -(textWidth - proxy.size.width) : 0)
                    .animation(
                        needsMarquee
                            ? .easeInOut(duration: max(2.4, Double(textWidth / 42))).repeatForever(autoreverses: true)
                            : .default,
                        value: marqueePhase
                    )
                    .background(
                        Text(displayed)
                            .font(font)
                            .lineLimit(1)
                            .fixedSize()
                            .hidden()
                            .background(
                                GeometryReader { textProxy in
                                    Color.clear.preference(key: PrismTextWidthKey.self, value: textProxy.size.width)
                                }
                            )
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipped()
            .onAppear {
                containerWidth = proxy.size.width
                if shimmer { shimmerPhase = true }
                if needsMarquee { marqueePhase = true }
            }
            .onChange(of: proxy.size.width) { _, width in
                containerWidth = width
                marqueePhase = textWidth > width + 4
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: lineHeight)
        .onPreferenceChange(PrismTextWidthKey.self) { width in
            textWidth = width
            marqueePhase = width > containerWidth + 4
        }
        .onChange(of: text) { _, newValue in
            guard newValue != displayed else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                displayed = newValue
                rollToken &+= 1
            }
            marqueePhase = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                marqueePhase = textWidth > containerWidth + 4
            }
        }
        .accessibilityLabel(text)
    }

    private var lineHeight: CGFloat { lineLimit >= 2 ? 32 : 16 }

    @ViewBuilder
    private func rollerLine(_ value: String) -> some View {
        Text(value)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: true, vertical: false)
            .overlay {
                if shimmer {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.34),
                                PrismTheme.accentSecondary.opacity(0.22),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(proxy.size.width * 0.42, 56))
                        .offset(x: shimmerPhase ? proxy.size.width : -proxy.size.width * 0.42)
                        .animation(
                            .linear(duration: 1.55).repeatForever(autoreverses: false),
                            value: shimmerPhase
                        )
                        .blendMode(.plusLighter)
                    }
                    .mask(
                        Text(value)
                            .font(font)
                            .lineLimit(lineLimit)
                            .fixedSize(horizontal: true, vertical: false)
                    )
                    .allowsHitTesting(false)
                }
            }
    }
}

private struct PrismTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Inline loading banner with animated ring — use for background Keep operations.
public struct PrismActivityBanner: View {
    public let icon: String
    public let message: String
    public var compact: Bool

    @State private var spin = false

    public init(icon: String, message: String, compact: Bool = false) {
        self.icon = icon
        self.message = message
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            ZStack {
                Circle()
                    .stroke(PrismTheme.accent.opacity(0.18), lineWidth: 2)
                    .frame(width: ringSize, height: ringSize)
                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(
                        AngularGradient(
                            colors: [
                                PrismTheme.accent.opacity(0.15),
                                PrismTheme.accent,
                                PrismTheme.accentSecondary,
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.05).repeatForever(autoreverses: false), value: spin)
                Image(systemName: icon)
                    .font(.ps(compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(PrismTheme.accentSecondary)
            }
            .onAppear { spin = true }

            PrismRollingShimmerText(
                text: message,
                font: .ps(compact ? 10 : 11, weight: .medium),
                color: PrismTheme.textPrimary,
                lineLimit: 1,
                shimmer: true
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 7 : 10)
        .background {
            RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                .fill(PrismTheme.surface.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    PrismTheme.accent.opacity(0.10),
                                    PrismTheme.surfaceMuted.opacity(0.45),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                        .strokeBorder(PrismTheme.glassStrokeGradient, lineWidth: 1)
                }
        }
        .shadow(color: PrismTheme.accentGlow.opacity(0.12), radius: 14, y: 4)
    }

    private var ringSize: CGFloat { compact ? 22 : 28 }
}

// MARK: - Dropdown field

public struct PrismDropdownOption<Value: Hashable>: Identifiable, Hashable {
    public let value: Value
    public let title: String
    public var subtitle: String?
    public var disabled: Bool

    public var id: Value { value }

    public init(value: Value, title: String, subtitle: String? = nil, disabled: Bool = false) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
        self.disabled = disabled
    }
}

/// Form-style single-select dropdown — replaces native macOS `Picker` menus in Keep sheets.
public struct PrismDropdownField<Value: Hashable>: View {
    let label: String?
    @Binding var selection: Value?
    let options: [PrismDropdownOption<Value>]
    var placeholder: String
    var leadingIcon: String?

    @State private var isOpen = false

    public init(
        label: String? = nil,
        selection: Binding<Value?>,
        options: [PrismDropdownOption<Value>],
        placeholder: String = "—",
        leadingIcon: String? = nil
    ) {
        self.label = label
        self._selection = selection
        self.options = options
        self.placeholder = placeholder
        self.leadingIcon = leadingIcon
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(PrismTheme.textSecondary)
            }

            Button { isOpen.toggle() } label: {
                HStack(spacing: 8) {
                    if let leadingIcon {
                        Image(systemName: leadingIcon)
                            .font(.ps(11, weight: .semibold))
                            .foregroundStyle(PrismTheme.accentSecondary)
                            .frame(width: 16)
                    }
                    Text(selectedTitle)
                        .font(.ps(12, weight: .medium))
                        .foregroundStyle(selection == nil ? PrismTheme.textTertiary : PrismTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.ps(9, weight: .bold))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(PrismTheme.surfaceMuted.opacity(0.42))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(PrismTheme.borderSubtle, lineWidth: 1)
                        }
                }
            }
            .buttonStyle(PrismHandButtonStyle())
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                dropdownPanel
                    .prismPopoverChrome(width: 320, maxHeight: 360)
            }
        }
    }

    private var selectedTitle: String {
        guard let selection else { return placeholder }
        return options.first(where: { $0.value == selection })?.title ?? placeholder
    }

    private var dropdownPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options) { option in
                    PrismSelectableRow(
                        title: option.title,
                        subtitle: option.subtitle,
                        isSelected: selection == option.value
                    ) {
                        guard !option.disabled else { return }
                        selection = option.value
                        isOpen = false
                    }
                    .opacity(option.disabled ? 0.45 : 1)
                }
            }
        }
    }
}

/// Non-optional binding variant of `PrismDropdownField`.
public struct PrismDropdownFieldRequired<Value: Hashable>: View {
    let label: String?
    @Binding var selection: Value
    let options: [PrismDropdownOption<Value>]
    var leadingIcon: String?

    public init(
        label: String? = nil,
        selection: Binding<Value>,
        options: [PrismDropdownOption<Value>],
        leadingIcon: String? = nil
    ) {
        self.label = label
        self._selection = selection
        self.options = options
        self.leadingIcon = leadingIcon
    }

    public var body: some View {
        PrismDropdownField(
            label: label,
            selection: Binding(
                get: { selection },
                set: { if let value = $0 { selection = value } }
            ),
            options: options,
            leadingIcon: leadingIcon
        )
    }
}
