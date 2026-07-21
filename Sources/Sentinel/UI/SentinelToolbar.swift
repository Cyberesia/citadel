import SwiftUI

struct SentinelToolbar: View {
    @ObservedObject var vm: SentinelViewModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PrismTheme.textTertiary)
                    .font(.ps(11))
                TextField(L10n.searchAppsHosts, text: Binding(
                    get: { vm.options.searchText },
                    set: { text in vm.updateOptions { $0.searchText = text } }
                ))
                .textFieldStyle(.plain)
                .font(.ps(12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(PrismTheme.surface.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 260)

            Picker(L10n.viewLabel, selection: Binding(
                get: { vm.options.listMode },
                set: { mode in vm.updateOptions { $0.listMode = mode } }
            )) {
                ForEach(MonitorViewOptions.ListMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .prismClickable()

            Toggle(L10n.hideHelpers, isOn: Binding(
                get: { vm.options.hideHelpers },
                set: { v in vm.updateOptions { $0.hideHelpers = v } }
            ))
            .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
            .font(.ps(11))
            .prismClickable()

            Toggle(L10n.activeOnly, isOn: Binding(
                get: { vm.options.activeOnly },
                set: { v in vm.updateOptions { $0.activeOnly = v } }
            ))
            .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
            .font(.ps(11))
            .prismClickable()

            Spacer()

            HStack(spacing: 4) {
                ForEach(SentinelMapProjection.allCases) { proj in
                    Button {
                        vm.mapProjection = proj
                    } label: {
                        Image(systemName: proj.systemImage)
                            .font(.ps(11, weight: .semibold))
                            .foregroundStyle(vm.mapProjection == proj ? Color.white : PrismTheme.textSecondary)
                            .padding(7)
                            .background {
                                if vm.mapProjection == proj {
                                    Circle().fill(PrismTheme.accent)
                                }
                            }
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .help(proj.label)
                }
            }

            Menu {
                ForEach(AppMode.allCases, id: \.self) { m in
                    Button {
                        vm.setMode(m)
                    } label: {
                        if vm.mode == m {
                            Label(modeLabel(m), systemImage: "checkmark")
                        } else {
                            Text(modeLabel(m))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                    Text(modeLabel(vm.mode))
                }
                .font(.ps(11, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PrismTheme.surface.opacity(0.4))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .prismClickable()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func modeLabel(_ m: AppMode) -> String {
        switch m {
        case .alert: return L10n.alertMode
        case .silentAllow: return L10n.silentAllow
        case .silentDeny: return L10n.silentDeny
        }
    }
}
