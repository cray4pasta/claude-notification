import Foundation

/// Plain-file logging for manual verification. The unified system log
/// (NSLog/os_log) redacts dynamic string content as `<private>` by
/// default, which makes it useless for confirming *what* happened, only
/// *that* something happened. This writes straight to a file instead.
enum DebugLog {
    private static let path = NSHomeDirectory() + "/.nudge/debug.log"
    private static let lock = NSLock()

    static func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
