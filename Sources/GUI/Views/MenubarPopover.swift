import SwiftUI

/// Menubar popover: traffic snapshot, recent activity, mode, and shortcuts.
struct MenubarPopoverView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var windows: WindowManager
    let close: () -> Void
    @State private var showModePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            trafficGraph
                .padding(.horizontal, 12)

            Text(L10n.recentNetworkActivity)
                .font(.ps(11, weight: .semibold))
                .foregroundColor(PrismTheme.textSecondary)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)

            recentActivityList

            HStack {
                deniedRow
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            Divider().background(PrismTheme.borderSubtle)

            VStack(alignment: .leading, spacing: 0) {
                Button(action: { close(); windows.showRulesManager() }) {
                    HStack {
                        Text(L10n.manageRules).font(.ps(13))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(PrismPlainHandButtonStyle()).foregroundColor(PrismTheme.textPrimary)

                Button(action: { close(); windows.showNetworkMonitor() }) {
                    HStack {
                        Text(L10n.openActivity).font(.ps(13))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(PrismPlainHandButtonStyle()).foregroundColor(PrismTheme.textPrimary)

                Button(action: { close(); windows.showSettings() }) {
                    HStack {
                        Text(L10n.citadelSettings).font(.ps(13))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(PrismPlainHandButtonStyle()).foregroundColor(PrismTheme.textPrimary)

                Divider().background(PrismTheme.borderSubtle)
                    .padding(.horizontal, 16).padding(.vertical, 4)

                Button(action: { NSApp.terminate(nil) }) {
                    HStack {
                        Text(L10n.quitCitadel).font(.ps(13))
                        Spacer()
                        Text("⌘Q").font(.ps(11)).foregroundColor(PrismTheme.textTertiary)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(PrismPlainHandButtonStyle()).foregroundColor(PrismTheme.textPrimary)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 380, height: 540)
        .background(PrismTheme.dominantGradient)
        .preferredColorScheme(.dark)
        .prismGlobalInteraction()
        .id(state.fontScale)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            ModeButton(mode: state.mode, showing: $showModePicker)
                .popover(isPresented: $showModePicker, arrowEdge: .bottom) {
                    ModePicker(current: state.mode) { m in
                        state.setMode(m)
                        showModePicker = false
                    }
                }
            Spacer()
            Button(action: {}) {
                Image(systemName: "speaker.slash.fill")
                    .font(.ps(14))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(width: 32, height: 32)
                    .background(PrismTheme.signalDeny.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PrismPlainHandButtonStyle())
            Button(action: { close(); windows.showNetworkMonitor() }) {
                Image(systemName: "globe")
                    .font(.ps(14))
                    .foregroundColor(.white.opacity(0.95))
                    .frame(width: 32, height: 32)
                    .background(PrismTheme.signalAllow.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PrismPlainHandButtonStyle())
        }
    }

    private var trafficGraph: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(PrismTheme.surface.opacity(0.45))
            TrafficBarsChart(history: state.trafficHistory)
                .padding(8)
            VStack(alignment: .leading) {
                HStack {
                    Text(CitadelFormat.bytes(state.totalOut))
                        .font(.ps(11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(PrismTheme.trafficUp.opacity(0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                }
                Spacer()
                HStack {
                    Text(CitadelFormat.bytes(state.totalIn))
                        .font(.ps(11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(PrismTheme.trafficDown.opacity(0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                }
                HStack {
                    Text(L10n.fiveMinutesAgo)
                        .font(.ps(10))
                        .foregroundColor(PrismTheme.textTertiary)
                    Spacer()
                    Text(L10n.now)
                        .font(.ps(10))
                        .foregroundColor(PrismTheme.textTertiary)
                }
            }
            .padding(10)
        }
        .frame(height: 160)
    }

    private var recentActivityList: some View {
        VStack(spacing: 0) {
            ForEach(state.topProcesses.prefix(3)) { ps in
                HStack(spacing: 10) {
                    if let icon = ps.icon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "app.dashed").foregroundColor(PrismTheme.textSecondary)
                            .frame(width: 18, height: 18)
                    }
                    Text(ps.name).font(.ps(13))
                        .foregroundColor(PrismTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 5)
            }
        }
    }

    private var deniedRow: some View {
        Button(action: { close(); windows.showNetworkMonitor() }) {
            HStack {
                ZStack {
                    Circle().fill(PrismTheme.signalDeny)
                    Text("\(state.deniedCount)").font(.ps(11, weight: .bold)).foregroundColor(.white)
                }.frame(width: 22, height: 22)
                Text(L10n.recentlyDenied)
                    .font(.ps(13))
                    .foregroundColor(PrismTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(PrismTheme.textTertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 4).padding(.vertical, 4)
        }
        .buttonStyle(PrismPlainHandButtonStyle())
    }
}

struct ModeButton: View {
    let mode: AppMode
    @Binding var showing: Bool

    private static let alertYellow = Color(red: 1.0, green: 0.78, blue: 0.20)

    var body: some View {
        Button(action: { showing.toggle() }) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(modeColor)
                    Image(systemName: modeIcon).font(.ps(11, weight: .bold)).foregroundColor(.white)
                }.frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.mode).font(.ps(10)).foregroundColor(PrismTheme.textTertiary)
                    Text(modeLabel).font(.ps(13, weight: .semibold)).foregroundColor(PrismTheme.textPrimary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(PrismTheme.surface.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PrismPlainHandButtonStyle())
    }

    private var modeColor: Color {
        switch mode {
        case .alert: return Self.alertYellow
        case .silentAllow: return PrismTheme.signalAllow
        case .silentDeny: return PrismTheme.signalDeny
        }
    }

    private var modeIcon: String {
        switch mode {
        case .alert: return "bell.fill"
        case .silentAllow: return "checkmark"
        case .silentDeny: return "xmark"
        }
    }

    private var modeLabel: String {
        switch mode {
        case .alert: return L10n.alertMode
        case .silentAllow: return L10n.silentAllow
        case .silentDeny: return L10n.silentDeny
        }
    }
}

struct ModePicker: View {
    let current: AppMode
    let onPick: (AppMode) -> Void

    private static let alertYellow = Color(red: 1.0, green: 0.78, blue: 0.20)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chevron.left").foregroundColor(PrismTheme.textSecondary)
                Text(L10n.mode).font(.ps(14, weight: .semibold))
                    .foregroundColor(PrismTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(PrismTheme.surface.opacity(0.45))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                pickerRow(.alert, L10n.alertMode, "bell.fill", Self.alertYellow)
                pickerRow(.silentAllow, L10n.silentAllow, "checkmark", PrismTheme.signalAllow)
                pickerRow(.silentDeny, L10n.silentDeny, "xmark", PrismTheme.signalDeny)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 240)
        .background(Color.clear)
    }

    private func pickerRow(_ m: AppMode, _ label: String, _ icon: String, _ color: Color) -> some View {
        Button(action: { onPick(m) }) {
            HStack(spacing: 12) {
                if current == m {
                    Image(systemName: "checkmark").font(.ps(11, weight: .bold))
                        .foregroundColor(PrismTheme.textPrimary)
                        .frame(width: 14)
                } else {
                    Spacer().frame(width: 14)
                }
                ZStack {
                    Circle().fill(color)
                    Image(systemName: icon).font(.ps(11, weight: .bold)).foregroundColor(.white)
                }.frame(width: 22, height: 22)
                Text(label).font(.ps(13)).foregroundColor(PrismTheme.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(PrismPlainHandButtonStyle())
    }
}

struct TrafficBarsChart: View {
    let history: [TrafficSample]
    var body: some View {
        GeometryReader { geo in
            let samples = Array(history.suffix(80))
            let count = max(samples.count, 1)
            let availW = geo.size.width
            let barW = max(2, (availW - CGFloat(count - 1) * 1.5) / CGFloat(count))
            let midY = geo.size.height / 2
            let maxIn = max(1, CGFloat(samples.map { $0.bytesIn }.max() ?? 1))
            let maxOut = max(1, CGFloat(samples.map { $0.bytesOut }.max() ?? 1))
            ZStack(alignment: .center) {
                HStack(alignment: .center, spacing: 1.5) {
                    ForEach(0..<samples.count, id: \.self) { i in
                        let s = samples[i]
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(PrismTheme.trafficUpGradient)
                                .frame(width: barW, height: max(2, CGFloat(s.bytesOut)/maxOut * midY * 0.95))
                            Rectangle()
                                .fill(PrismTheme.trafficDownGradient)
                                .frame(width: barW, height: max(2, CGFloat(s.bytesIn)/maxIn * midY * 0.95))
                        }
                    }
                }
            }
        }
    }
}
