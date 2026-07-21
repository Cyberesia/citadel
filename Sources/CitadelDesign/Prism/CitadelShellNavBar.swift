import SwiftUI

/// Dual-section shell navigation: Fortress (network) + Keep (agents).
public struct CitadelShellNavBar: View {
    @Binding var expandedSection: CitadelNavSection
    @Binding var fortressMode: FortressShellMode
    @Binding var coworkMode: CoworkShellMode
    /// Opens Keep’s in-app guide (only shown while Keep is expanded).
    var onKeepHelp: (() -> Void)?
    /// Opens Fortress’s in-app guide (only shown while Fortress is expanded).
    var onFortressHelp: (() -> Void)?

    public init(
        expandedSection: Binding<CitadelNavSection>,
        fortressMode: Binding<FortressShellMode>,
        coworkMode: Binding<CoworkShellMode>,
        onKeepHelp: (() -> Void)? = nil,
        onFortressHelp: (() -> Void)? = nil
    ) {
        _expandedSection = expandedSection
        _fortressMode = fortressMode
        _coworkMode = coworkMode
        self.onKeepHelp = onKeepHelp
        self.onFortressHelp = onFortressHelp
    }

    public var body: some View {
        HStack(spacing: 8) {
            if expandedSection == .fortress {
                expandedFortressGroup
            } else {
                compactPill(label: L10n.fortress, systemImage: "radar") {
                    expandedSection = .fortress
                }
            }

            if expandedSection == .cowork {
                expandedKeepGroup
            } else {
                compactPill(label: L10n.keep, systemImage: "building.columns.fill") {
                    expandedSection = .cowork
                }
            }
        }
        .animation(PrismMotion.quick, value: expandedSection)
    }

    // MARK: - Fortress

    private var expandedFortressGroup: some View {
        HStack(spacing: 4) {
            ForEach(FortressShellMode.allCases) { mode in
                navButton(
                    label: mode.label,
                    systemImage: mode.systemImage,
                    isSelected: fortressMode == mode,
                    action: {
                        withAnimation(PrismMotion.quick) {
                            fortressMode = mode
                            expandedSection = .fortress
                        }
                    }
                )
            }

            if onFortressHelp != nil {
                fortressGuideButton
            }
        }
        .padding(4)
        .prismGlass(cornerRadius: 22, padding: 0)
        .transition(.scale.combined(with: .opacity))
    }

    private var fortressGuideButton: some View {
        Button {
            onFortressHelp?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.ps(11, weight: .semibold))
                Text(L10n.fortressHelpShort)
                    .font(.ps(12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(PrismTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .strokeBorder(PrismTheme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PrismHandButtonStyle())
        .help(L10n.fortressHelpTitle)
    }

    // MARK: - Keep (spacer)

    private var expandedKeepGroup: some View {
        HStack(spacing: 4) {
            ForEach(CoworkShellMode.primaryCases) { mode in
                navButton(
                    label: mode.label,
                    systemImage: mode.systemImage,
                    isSelected: coworkMode == mode,
                    accent: keepAccentGradient,
                    action: {
                        withAnimation(PrismMotion.quick) {
                            coworkMode = mode
                            expandedSection = .cowork
                        }
                    }
                )
            }

            keepMoreMenu

            if onKeepHelp != nil {
                keepGuideButton
            }
        }
        .padding(4)
        .prismGlass(cornerRadius: 22, padding: 0)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    @State private var keepMoreOpen = false

    private var keepMoreMenu: some View {
        Button {
            keepMoreOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                    .font(.ps(11, weight: .semibold))
                Text(L10n.keepMore)
                    .font(.ps(12, weight: coworkMode.isAdvanced ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(coworkMode.isAdvanced ? Color.white : PrismTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if coworkMode.isAdvanced {
                    Capsule(style: .continuous)
                        .fill(keepAccentGradient)
                        .shadow(color: PrismTheme.accentGlow, radius: 8, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PrismHandButtonStyle())
        .popover(isPresented: $keepMoreOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(CoworkShellMode.advancedCases) { mode in
                    Button {
                        withAnimation(PrismMotion.quick) {
                            coworkMode = mode
                            expandedSection = .cowork
                        }
                        keepMoreOpen = false
                    } label: {
                        Label(mode.label, systemImage: mode.systemImage)
                            .font(.ps(12, weight: coworkMode == mode ? .semibold : .regular))
                            .foregroundStyle(
                                coworkMode == mode ? PrismTheme.textPrimary : PrismTheme.textSecondary
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PrismHandButtonStyle())
                }
            }
            .padding(6)
            .frame(minWidth: 188)
        }
    }

    /// Quiet trailing control inside the Keep glass — same rhythm as nav pills.
    private var keepGuideButton: some View {
        Button {
            onKeepHelp?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.ps(11, weight: .semibold))
                Text(L10n.keepHelpShort)
                    .font(.ps(12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(PrismTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .strokeBorder(PrismTheme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PrismHandButtonStyle())
        .help(L10n.keepHelpTitle)
    }

    private var keepAccentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.55, blue: 0.28),
                Color(red: 0.85, green: 0.35, blue: 0.22)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Shared

    private func compactPill(
        label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(PrismMotion.quick) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.ps(11, weight: .semibold))
                Text(label)
                    .font(.ps(12, weight: .medium))
            }
            .foregroundStyle(PrismTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .strokeBorder(PrismTheme.borderSubtle, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PrismHandButtonStyle())
        .prismGlass(cornerRadius: 22, padding: 0)
        .transition(.scale.combined(with: .opacity))
    }

    private func navButton(
        label: String,
        systemImage: String,
        isSelected: Bool,
        accent: LinearGradient = PrismTheme.accentGradient,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.ps(11, weight: .semibold))
                Text(label)
                    .font(.ps(12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : PrismTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(accent)
                        .shadow(color: PrismTheme.accentGlow, radius: 8, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PrismHandButtonStyle())
    }
}
