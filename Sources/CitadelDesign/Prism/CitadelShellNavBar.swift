import SwiftUI

/// Dual-section shell navigation: Sentinel (network) + Keep (agents).
public struct CitadelShellNavBar: View {
    @Binding var expandedSection: CitadelNavSection
    @Binding var sentinelMode: SentinelShellMode
    @Binding var coworkMode: CoworkShellMode

    public init(
        expandedSection: Binding<CitadelNavSection>,
        sentinelMode: Binding<SentinelShellMode>,
        coworkMode: Binding<CoworkShellMode>
    ) {
        _expandedSection = expandedSection
        _sentinelMode = sentinelMode
        _coworkMode = coworkMode
    }

    public var body: some View {
        HStack(spacing: 8) {
            if expandedSection == .sentinel {
                expandedSentinelGroup
            } else {
                compactPill(label: L10n.sentinel, systemImage: "radar") {
                    expandedSection = .sentinel
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

    // MARK: - Sentinel

    private var expandedSentinelGroup: some View {
        HStack(spacing: 4) {
            ForEach(SentinelShellMode.allCases) { mode in
                navButton(
                    label: mode.label,
                    systemImage: mode.systemImage,
                    isSelected: sentinelMode == mode,
                    action: {
                        withAnimation(PrismMotion.quick) {
                            sentinelMode = mode
                            expandedSection = .sentinel
                        }
                    }
                )
            }
        }
        .padding(4)
        .prismGlass(cornerRadius: 22, padding: 0)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Keep

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
