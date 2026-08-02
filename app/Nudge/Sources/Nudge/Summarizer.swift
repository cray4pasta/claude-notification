import Foundation

/// Turns a raw hook payload into something a human can glance at from
/// across the room. Deliberately simple template matching — no extra API
/// call, no added latency (PRD docs/PRD.md §9).
enum Summarizer {
    struct Summary {
        let title: String
        let body: String
        let isRisky: Bool
        let rawDetail: String?
        let cwd: String?
    }

    private static let riskyKeywords = [
        "rm -rf", "--force", " -f ", "sudo", "drop table", "delete from",
        "prod", ".env", "secret", "credential", "password", "api key",
        "force-push", "force push",
    ]

    private static func isRisky(_ text: String) -> Bool {
        let lower = text.lowercased()
        return riskyKeywords.contains { lower.contains($0) }
    }

    private static func projectName(fromCwd cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "Claude Code" }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "Claude Code" : name
    }

    // MARK: - Notification hook (informational only, can't gate)

    static func summarizeNotification(_ event: HookEvent) -> Summary {
        let projectName = projectName(fromCwd: event.cwd)
        let rawMessage = event.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let risky = rawMessage.map(isRisky) ?? false

        let body: String
        switch event.notificationType {
        case "permission_prompt":
            body = rawMessage.map { "Claude wants to: \(cleaned($0))" } ?? "Claude needs your OK to continue."
        case "idle_prompt":
            body = "Claude has been waiting on you for a bit."
        case "agent_needs_input":
            body = "Claude needs input from you to keep going."
        default:
            body = rawMessage.map(cleaned) ?? "Claude has an update for you."
        }

        return Summary(title: projectName, body: body, isRisky: risky, rawDetail: rawMessage, cwd: event.cwd)
    }

    // MARK: - PreToolUse hook (gate-able)

    static func summarizeToolUse(_ event: HookEvent) -> Summary {
        let projectName = projectName(fromCwd: event.cwd)
        let input = event.toolInput ?? [:]

        let (body, detail): (String, String?)
        switch event.toolName {
        case "Bash":
            let command = input["command"]?.stringValue ?? "a command"
            body = "run: \(command)"
            detail = command
        case "Edit", "Write":
            let path = (input["file_path"]?.stringValue).map { ($0 as NSString).lastPathComponent } ?? "a file"
            body = "edit \(path)"
            detail = input["file_path"]?.stringValue
        case "WebFetch":
            let url = input["url"]?.stringValue ?? "a URL"
            body = "fetch \(url)"
            detail = url
        case "Read":
            let path = (input["file_path"]?.stringValue).map { ($0 as NSString).lastPathComponent } ?? "a file"
            body = "read \(path)"
            detail = input["file_path"]?.stringValue
        default:
            let name = event.toolName ?? "a tool"
            body = "use \(name)"
            detail = nil
        }

        let riskyCheck = detail ?? body
        return Summary(
            title: projectName,
            body: "Claude wants to \(body).",
            isRisky: isRisky(riskyCheck),
            rawDetail: detail,
            cwd: event.cwd
        )
    }

    /// Light cleanup of Claude Code's own prompt text: strip a leading
    /// "Allow " and a trailing "?" so it reads as a statement.
    private static func cleaned(_ message: String) -> String {
        var text = message
        if text.hasPrefix("Allow ") {
            text = String(text.dropFirst("Allow ".count))
        }
        if text.hasSuffix("?") {
            text = String(text.dropLast())
        }
        return text
    }
}
