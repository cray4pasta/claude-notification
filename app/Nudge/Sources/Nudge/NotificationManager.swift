import Foundation

/// Fires native macOS notification banners via `osascript -e 'display
/// notification'` instead of any UserNotifications-framework API.
///
/// Why: `UNUserNotificationCenter` hard-denies apps without a real Apple
/// Developer signing identity (confirmed on this machine — see git log),
/// and the legacy `NSUserNotificationCenter` fallback we shipped instead
/// is deprecated. `claude-menubar-buddy` (github.com/spyza008) solves the
/// same problem more simply: AppleScript's "display notification" posts
/// under the OS's own identity and needs no entitlement, signing, or even
/// a real .app bundle at all.
///
/// Trade-off: AppleScript notifications have no click-through/action-button
/// callback (confirmed — osascript's `display notification` is fire-and-
/// forget only). That's fine here: the companion window is the actual
/// interactive surface (Yes/No/Open Claude already live there); this
/// banner is a supplementary catch-your-eye signal for when you're not
/// looking at this Mac's screen at all — e.g. another Space, full-screen
/// app, or a glance from across the room.
enum NotificationManager {
    static func deliver(summary: Summarizer.Summary) {
        let title = summary.isRisky ? "⚠️ \(summary.title)" : summary.title
        let sound = summary.isRisky ? "Basso" : "Glass"
        let script = """
        display notification \(appleScriptString(summary.body)) with title \(appleScriptString(title)) sound name \(appleScriptString(sound))
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }

    /// AppleScript string literal. There's no backslash-escape for a
    /// quote inside an AppleScript string, so — same fix claude-menubar-
    /// buddy uses — swap embedded quotes for single quotes rather than
    /// trying to escape them. Good enough for our own generated summary
    /// text; also closes off the one way this text could otherwise break
    /// out of the string literal into arbitrary AppleScript.
    private static func appleScriptString(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\"", with: "'"))\""
    }
}
