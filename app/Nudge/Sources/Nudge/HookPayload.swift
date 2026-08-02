import Foundation

/// Matches the JSON Claude Code sends on stdin to a hook. Field set is a
/// superset across `SessionStart`, `SessionEnd`, `Notification`, and
/// `PreToolUse` — confirmed against Claude Code 2.1.220 docs, see
/// spike/M0-findings.md. `toolInput` is left as raw JSON since its shape
/// varies per tool (Bash gets `command`, Edit/Write get `file_path`, etc).
struct HookEvent: Decodable {
    let sessionId: String?
    let cwd: String?
    let hookEventName: String?

    // Notification-only
    let notificationType: String?
    let message: String?

    // PreToolUse-only
    let toolName: String?
    let toolInput: [String: JSONValue]?
    let toolUseId: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
        case notificationType = "notification_type"
        case message
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
    }
}

/// Minimal untyped JSON box so `tool_input` (whose shape varies per tool)
/// can round-trip through Decodable without a bespoke type per tool.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        self = .null
    }

    var stringValue: String? {
        if case let .string(v) = self { return v }
        return nil
    }
}
