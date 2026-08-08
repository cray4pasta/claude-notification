import Foundation

/// Persists "always allow" rules the user has explicitly granted by tapping
/// the companion's Always Allow button.
///
/// Deliberately narrow scope: (project cwd, tool name, exact command/target)
/// — the PRD's v1 design kept a human in the loop for every request on
/// purpose (docs/PRD.md §12), so this is the first carve-out and it's kept
/// as tight as practical. Saying yes to `npm test` in one project never
/// silently covers `rm -rf`, a different command, or the same command in a
/// different project.
final class AlwaysAllowStore {
    static let shared = AlwaysAllowStore()

    private let defaults = UserDefaults.standard
    private let key = "nudge.alwaysAllowRules"
    private var rules: Set<String>

    private init() {
        rules = Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// \u{1} (unit separator) as the delimiter, not a printable character
    /// that could plausibly appear in a cwd path or shell command and
    /// cause two different rules to collide into the same key.
    private func ruleKey(cwd: String?, toolName: String?, detail: String?) -> String {
        "\(cwd ?? "")\u{1}\(toolName ?? "")\u{1}\(detail ?? "")"
    }

    func isAlwaysAllowed(cwd: String?, toolName: String?, detail: String?) -> Bool {
        rules.contains(ruleKey(cwd: cwd, toolName: toolName, detail: detail))
    }

    func alwaysAllow(cwd: String?, toolName: String?, detail: String?) {
        rules.insert(ruleKey(cwd: cwd, toolName: toolName, detail: detail))
        defaults.set(Array(rules), forKey: key)
    }
}
