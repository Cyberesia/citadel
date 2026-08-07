import Foundation

// MARK: - Teams (multi-agent orchestration, plan Phase 5)

struct CoworkTeamAssistant: Identifiable, Decodable, Hashable {
    let slotID: String
    let conversationID: String?
    let role: String
    let assistantBackend: String?
    let assistantName: String
    let status: String?
    let assistantID: String?
    let model: String?
    let pendingConfirmations: Int?

    var id: String { slotID }
    var isLeader: Bool { role == "lead" || role == "leader" }

    enum CodingKeys: String, CodingKey {
        case slotID = "slot_id"
        case conversationID = "conversation_id"
        case role
        case assistantBackend = "assistant_backend"
        case assistantName = "assistant_name"
        case status
        case assistantID = "assistant_id"
        case model
        case pendingConfirmations = "pending_confirmations"
    }
}

struct CoworkTeam: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let workspace: String?
    let workspaceMode: String?
    let leaderAssistantID: String?
    let assistants: [CoworkTeamAssistant]
    let sessionMode: String?
    let createdAt: Double?
    let updatedAt: Double?

    var leader: CoworkTeamAssistant? {
        assistants.first(where: \.isLeader) ?? assistants.first
    }

    var members: [CoworkTeamAssistant] {
        assistants.filter { !$0.isLeader }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, workspace, assistants
        case workspaceMode = "workspace_mode"
        case leaderAssistantID = "leader_assistant_id"
        case sessionMode = "session_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Member spec used when creating a team or adding a slot.
struct CoworkTeamAssistantInput: Encodable {
    let name: String
    let role: String
    let model: String
    let assistantID: String?

    enum CodingKeys: String, CodingKey {
        case name, role, model
        case assistantID = "assistant_id"
    }
}

struct CoworkCreateTeamRequest: Encodable {
    let name: String
    let assistants: [CoworkTeamAssistantInput]
    let workspace: String?
}

struct CoworkTeamRunState: Decodable, Hashable {
    let teamRunID: String?
    let status: String?
    let activeSlotIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case teamRunID = "team_run_id"
        case status
        case activeSlotIDs = "active_slot_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Some builds nest the run under `run`; keep field decoding lenient.
        teamRunID = try? container.decodeIfPresent(String.self, forKey: .teamRunID)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        activeSlotIDs = try? container.decodeIfPresent([String].self, forKey: .activeSlotIDs)
    }

    var isRunning: Bool {
        guard let status else { return false }
        return ["running", "active", "accepted", "started"].contains(status.lowercased())
    }
}

struct CoworkTeamMessageRequest: Encodable {
    let content: String
    var files: [String]?
}
