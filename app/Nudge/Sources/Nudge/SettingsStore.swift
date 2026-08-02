import Foundation

/// The master on/off switch (PRD docs/PRD.md §6, P0 #2). When off, incoming
/// hook payloads are dropped silently — Claude Code's own terminal prompts
/// are untouched either way, since M1 doesn't gate anything (that's M2).
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
