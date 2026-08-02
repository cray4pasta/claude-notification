import Foundation
import AppKit

/// Best-effort "Open Claude" jump-to-session (PRD docs/PRD.md §6 P0 #7).
///
/// M1 scope: bring the terminal app to the front so you land back where
/// Claude Code is running. It does NOT target the exact tab/window for a
/// given `cwd` yet — that needs a real session registry (tracking which
/// terminal window owns which Claude Code session_id), which is out of
/// scope until multi-session support lands (PRD §6 P0 #9, §10 M3).
enum TerminalFocuser {
    static func openClaude(cwd: String?) {
        if isRunning(bundleID: "com.googlecode.iterm2") {
            activate(bundleID: "com.googlecode.iterm2")
            return
        }
        activate(bundleID: "com.apple.Terminal")
    }

    private static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func activate(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("Nudge: no running app found for \(bundleID)")
            return
        }
        app.activate(options: [.activateAllWindows])
    }
}
