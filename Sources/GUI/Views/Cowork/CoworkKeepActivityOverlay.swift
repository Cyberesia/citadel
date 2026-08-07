import SwiftUI

struct KeepBackgroundActivity: Identifiable, Equatable {
    let id: String
    let icon: String
    let message: String
}

/// Floating stack of descriptive loading banners for in-flight Keep operations.
struct CoworkKeepActivityOverlay: View {
    @EnvironmentObject var cowork: CoworkState

    var body: some View {
        let items = cowork.keepBackgroundActivities
        if !items.isEmpty {
            VStack(spacing: 6) {
                ForEach(items) { item in
                    PrismActivityBanner(icon: item.icon, message: item.message, compact: items.count > 1)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: items)
        }
    }
}

extension CoworkState {
    /// Derived from busy flags — no manual bookkeeping required in every call site.
    var keepBackgroundActivities: [KeepBackgroundActivity] {
        var items: [KeepBackgroundActivity] = []

        if coreStatus == .starting {
            items.append(.init(id: "core", icon: "sparkles", message: L10n.coreStarting))
        }
        if isLoadingCatalog {
            items.append(.init(id: "catalog", icon: "tray.full", message: L10n.loadingKeepCatalog))
        }
        if isScanningAgents {
            items.append(.init(id: "scan-agents", icon: "sparkle.magnifyingglass", message: L10n.scanningAgents))
        }
        if !checkingAgentIDs.isEmpty {
            let n = checkingAgentIDs.count
            items.append(.init(
                id: "health-check",
                icon: "checkmark.seal",
                message: n == 1 ? L10n.checkingAgentHealth : L10n.checkingAgents(n)
            ))
        }
        if isRemoteBusy {
            items.append(.init(id: "remote", icon: "antenna.radiowaves.left.and.right", message: L10n.enablingRemoteAccess))
        }
        if isTeamBusy, let message = teamActivityMessage, !message.isEmpty {
            items.append(.init(id: "team", icon: "person.3.sequence", message: message))
        }
        if isLoadingOllamaModels {
            items.append(.init(id: "ollama", icon: "cpu", message: L10n.loadingModels))
        }
        if isSending {
            items.append(.init(id: "sending", icon: "paperplane", message: L10n.sendingMessage))
        } else if isStreaming {
            items.append(.init(id: "streaming", icon: "ellipsis.bubble", message: L10n.agentWorking))
        }

        return items
    }
}
