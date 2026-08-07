import Foundation

enum CoworkToolCallStatus: String, Hashable, Sendable {
    case pending, running, completed, error, canceled

    init(raw: String?) {
        switch raw?.lowercased() {
        case "success", "completed", "finish", "finished": self = .completed
        case "error", "failed", "failure": self = .error
        case "canceled", "cancelled": self = .canceled
        case "pending": self = .pending
        case "executing", "running", "confirming", "processing": self = .running
        default: self = .running
        }
    }
}

struct CoworkNormalizedToolCall: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let status: CoworkToolCallStatus
    let description: String?
    let input: String?
    let output: String?
}

enum CoworkToolCallNormalizer {
    static func normalize(_ message: CoworkMessage) -> [CoworkNormalizedToolCall] {
        switch message.type {
        case "tool_group":
            return normalizeToolGroup(message)
        case "tool_call", "acp_tool_call":
            if let single = normalizeSingleToolCall(message) { return [single] }
            return []
        default:
            return []
        }
    }

    private static func normalizeToolGroup(_ message: CoworkMessage) -> [CoworkNormalizedToolCall] {
        guard let items = message.content?.json?.arrayValue else { return [] }
        return items.compactMap { normalizeGroupItem($0) }
    }

    /// Normalizes a live `message.stream` WebSocket payload (before the message is persisted).
    static func normalize(streamType: String, msgID: String, json: CoworkJSONValue) -> [CoworkNormalizedToolCall] {
        switch streamType {
        case "tool_group":
            let items = json.arrayValue ?? json.objectValue?["content"]?.arrayValue ?? []
            return items.compactMap { normalizeGroupItem($0) }
        case "tool_call", "acp_tool_call":
            guard let obj = json.objectValue else { return [] }
            let name = obj["name"]?.stringValue ?? obj["title"]?.stringValue ?? "tool"
            let callID = obj["call_id"]?.stringValue ?? obj["toolCallId"]?.stringValue ?? msgID
            let status = CoworkToolCallStatus(raw: obj["status"]?.stringValue)
            let input = (obj["args"] ?? obj["input"])?.prettyPrinted()
            let output = (obj["result"] ?? obj["output"] ?? obj["result_display"])?.prettyPrinted()
            return [CoworkNormalizedToolCall(
                id: callID,
                name: name,
                status: status,
                description: obj["description"]?.stringValue,
                input: input,
                output: output
            )]
        default:
            return []
        }
    }

    private static func normalizeGroupItem(_ item: CoworkJSONValue) -> CoworkNormalizedToolCall? {
        guard let obj = item.objectValue else { return nil }
        let name = obj["name"]?.stringValue ?? "tool"
        let callID = obj["call_id"]?.stringValue ?? UUID().uuidString
        let status = CoworkToolCallStatus(raw: obj["status"]?.stringValue)
        let desc = obj["description"]?.stringValue
        let input = obj["confirmationDetails"]?.prettyPrinted() ?? desc
        let output = obj["result_display"]?.prettyPrinted()
        return CoworkNormalizedToolCall(id: callID, name: name, status: status, description: desc, input: input, output: output)
    }

    private static func normalizeSingleToolCall(_ message: CoworkMessage) -> CoworkNormalizedToolCall? {
        guard let content = message.content else { return nil }
        let name = content.toolName ?? content.json?.objectValue?["name"]?.stringValue ?? "tool"
        let callID = content.callID ?? message.msgID ?? message.id ?? UUID().uuidString
        let status = CoworkToolCallStatus(raw: content.status ?? message.status)
        let input = content.argsJSON?.prettyPrinted() ?? content.inputJSON?.prettyPrinted()
        let output = content.resultJSON?.prettyPrinted() ?? content.textBody
        return CoworkNormalizedToolCall(
            id: callID,
            name: name,
            status: status,
            description: content.description,
            input: input,
            output: output
        )
    }
}
