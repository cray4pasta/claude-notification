import Foundation

/// Bridges a `PreToolUse` hook's blocked background thread to the button
/// tap that eventually resolves it on the main thread. The hook script
/// (and Claude Code behind it) is genuinely paused on the other end of a
/// socket connection this whole time (PRD docs/PRD.md §4/§9) — that's what
/// makes "tap yes/no without opening Claude" work.
final class PendingRequestStore {
    static let shared = PendingRequestStore()

    enum Decision {
        case allow
        case deny
        case timedOut
    }

    private final class Entry {
        let semaphore = DispatchSemaphore(value: 0)
        var decision: Decision = .timedOut
    }

    private var entries: [UUID: Entry] = [:]
    private let lock = NSLock()

    func register(_ id: UUID) {
        lock.lock()
        entries[id] = Entry()
        lock.unlock()
    }

    /// Called on the socket's background thread. Blocks until `resolve` is
    /// called for this id, or `timeout` elapses (safety net so a crashed
    /// or ignored request doesn't hang the hook script forever — Claude
    /// Code's own hook timeout is 600s, so this must stay comfortably
    /// under that).
    func waitForDecision(_ id: UUID, timeout: TimeInterval) -> Decision {
        lock.lock()
        let entry = entries[id]
        lock.unlock()
        guard let entry else { return .timedOut }

        let result = entry.semaphore.wait(timeout: .now() + timeout)

        lock.lock()
        let decision = entries[id]?.decision ?? .timedOut
        entries.removeValue(forKey: id)
        lock.unlock()

        return result == .success ? decision : .timedOut
    }

    /// Called on the main thread from a button tap.
    func resolve(_ id: UUID, decision: Decision) {
        lock.lock()
        guard let entry = entries[id] else { lock.unlock(); return }
        entry.decision = decision
        lock.unlock()
        entry.semaphore.signal()
    }
}
