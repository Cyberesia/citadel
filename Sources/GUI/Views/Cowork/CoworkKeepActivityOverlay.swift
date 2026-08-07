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
        } else if activeConfirmation != nil || !pendingConfirmations.isEmpty {
            items.append(.init(id: "confirm", icon: agentActivityIcon, message: agentActivityMessage))
        } else if isStreaming {
            items.append(.init(id: "streaming", icon: agentActivityIcon, message: agentActivityMessage))
        }

        return items
    }

    /// Live status for the activity banner / conversation header while streaming.
    var agentActivityMessage: String {
        _ = streamTick

        if let confirmation = pendingConfirmations.first {
            let detail = (confirmation.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? confirmation.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty {
                return L10n.agentWaitingPermission(Self.shortActivityDetail(detail))
            }
            return L10n.permissionRequired
        }

        if let tool = activeLiveToolCall {
            if let description = tool.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                return L10n.agentWorkingOn(Self.shortActivityDetail(description))
            }
            return L10n.agentRunningTool(Self.friendlyToolName(tool.name))
        }

        if liveStreamSegments.values.contains(where: { $0.isThinkingActive }) {
            return L10n.reasoningActive
        }

        if let name = selectedAssistant?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return L10n.agentNamedWorking(name)
        }

        return L10n.agentWorking
    }

    var agentActivityIcon: String {
        if pendingConfirmations.first != nil { return "hand.raised" }
        if activeLiveToolCall != nil { return "wrench.and.screwdriver" }
        if liveStreamSegments.values.contains(where: { $0.isThinkingActive }) { return "brain" }
        return "ellipsis.bubble"
    }

    private var activeLiveToolCall: CoworkNormalizedToolCall? {
        for msgID in liveToolOrder.reversed() {
            let calls = liveToolCalls[msgID] ?? []
            if let running = calls.last(where: { $0.status == .running || $0.status == .pending }) {
                return running
            }
        }
        return nil
    }

    private static func friendlyToolName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("mcp__") {
            name = String(name.dropFirst(5))
        }
        name = name.replacingOccurrences(of: "__", with: " · ")
        name = name.replacingOccurrences(of: "_", with: " ")
        return name.isEmpty ? "tool" : name
    }

    private static func shortActivityDetail(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 72 else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 69)
        return String(collapsed[..<end]) + "…"
    }
}
