import Foundation

/// Tracks which Claude Code sessions are currently open, via SessionStart/
/// SessionEnd hooks, so the companion window only shows up "when Claude is
/// open" as opposed to being visible all the time.
final class SessionTracker {
    static let shared = SessionTracker()

    private var activeSessionIDs: Set<String> = []
    private let lock = NSLock()

    /// Always called on the main thread.
    var onChange: (() -> Void)?

    var hasActiveSessions: Bool {
        lock.lock(); defer { lock.unlock() }
        return !activeSessionIDs.isEmpty
    }

    func sessionStarted(_ id: String?) {
        guard let id else { return }
        lock.lock()
        activeSessionIDs.insert(id)
        lock.unlock()
        notifyChange()
    }

    func sessionEnded(_ id: String?) {
        guard let id else { return }
        lock.lock()
        activeSessionIDs.remove(id)
        lock.unlock()
        notifyChange()
    }

    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }
}
