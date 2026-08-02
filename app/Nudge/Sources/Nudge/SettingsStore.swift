import Foundation

/// The master on/off switch (PRD docs/PRD.md §6, P0 #2). When off,
/// Notification/PreToolUse payloads are dropped in AppDelegate before any
/// gating or UI happens — Claude Code falls back to its own normal
/// terminal prompt, exactly as if Nudge weren't installed at all.
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private let enabledKey = "nudge.enabled"

    private(set) var isEnabled: Bool {
        didSet { NotificationCenter.default.post(name: .nudgeEnabledChanged, object: nil) }
    }

    private init() {
        if defaults.object(forKey: enabledKey) == nil {
            defaults.set(true, forKey: enabledKey)
        }
        isEnabled = defaults.bool(forKey: enabledKey)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
        isEnabled = enabled
    }

    func toggle() {
        setEnabled(!isEnabled)
    }
}

extension Notification.Name {
    static let nudgeEnabledChanged = Notification.Name("nudge.enabledChanged")
}
