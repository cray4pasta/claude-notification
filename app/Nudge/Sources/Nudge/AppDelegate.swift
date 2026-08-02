import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var toggleMenuItem: NSMenuItem!
    private var usageMenuItem: NSMenuItem!
    private var usageRefreshTimer: Timer!
    private var socketServer: SocketServer!

    /// Matches claude-menubar-buddy's cadence — Claude Desktop doesn't
    /// update plan-usage-history.json more often than that, so polling
    /// faster would just be wasted work.
    private static let usageRefreshInterval: TimeInterval = 30

    /// Comfortably under Claude Code's 600s default PreToolUse hook
    /// timeout (spike/M0-findings.md §3), leaving headroom for the human
    /// to actually see and tap the companion. Overridable via env var for
    /// manual testing (see app/README.md) so a full timeout round-trip
    /// doesn't require waiting 4 real minutes.
    private static let gateTimeout: TimeInterval = {
        if let override = ProcessInfo.processInfo.environment["NUDGE_GATE_TIMEOUT"],
           let seconds = Double(override) {
            return seconds
        }
        return 240
    }()

    static let socketPath = NSHomeDirectory() + "/.nudge/nudge.sock"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon

        buildStatusItem()
        NotificationCenter.default.addObserver(
            self, selector: #selector(enabledChanged),
            name: .nudgeEnabledChanged, object: nil
        )
        SessionTracker.shared.onChange = { [weak self] in self?.refreshCompanionVisibility() }

        startSocketServer()
        refreshCompanionVisibility()

        refreshUsage()
        usageRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.usageRefreshInterval, repeats: true
        ) { [weak self] _ in self?.refreshUsage() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
        usageRefreshTimer?.invalidate()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Nudge")
        }

        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "Listening for Claude Code", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        usageMenuItem = NSMenuItem(title: UsageStats.menuTitle(for: .init(fiveHourPct: nil, weeklyPct: nil)), action: nil, keyEquivalent: "")
        usageMenuItem.isEnabled = false
        menu.addItem(usageMenuItem)
        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(
            title: "Nudge Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        toggleMenuItem.state = SettingsStore.shared.isEnabled ? .on : .off
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Nudge", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        SettingsStore.shared.toggle()
    }

    @objc private func enabledChanged() {
        toggleMenuItem.state = SettingsStore.shared.isEnabled ? .on : .off
        if let button = statusItem.button {
            button.appearsDisabled = !SettingsStore.shared.isEnabled
        }
        refreshCompanionVisibility()
    }

    private func refreshCompanionVisibility() {
        CompanionWindowController.shared.refreshVisibility()
    }

    private func refreshUsage() {
        // File I/O off the main thread; only the menu title update hops back.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snapshot = UsageStats.snapshot()
            let title = UsageStats.menuTitle(for: snapshot)
            DispatchQueue.main.async {
                self?.usageMenuItem.title = title
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startSocketServer() {
        socketServer = SocketServer(socketPath: Self.socketPath)
        socketServer.onPayload = { [weak self] data in
            self?.handleHookPayload(data)
        }
        do {
            try socketServer.start()
        } catch {
            NSLog("Nudge: failed to start socket server: \(error)")
        }
    }

    /// Runs on a background thread. For PreToolUse, this call itself
    /// blocks (via PendingRequestStore) until the human responds, which is
    /// the whole point — the caller is a socket connection Claude Code's
    /// hook script is holding open.
    private func handleHookPayload(_ data: Data) -> Data? {
        guard let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
            NSLog("Nudge: received payload that didn't match the expected hook schema")
            return nil
        }

        DebugLog.log("received hook_event_name=\(event.hookEventName ?? "nil") session=\(event.sessionId ?? "nil")")

        switch event.hookEventName {
        case "SessionStart":
            SessionTracker.shared.sessionStarted(event.sessionId)
            DebugLog.log("session started; hasActiveSessions=\(SessionTracker.shared.hasActiveSessions)")
            return nil

        case "SessionEnd":
            SessionTracker.shared.sessionEnded(event.sessionId)
            DebugLog.log("session ended; hasActiveSessions=\(SessionTracker.shared.hasActiveSessions)")
            return nil

        case "Notification":
            let summary = Summarizer.summarizeNotification(event)
            DebugLog.log("notification enqueued: \(summary.body)")
            NotificationManager.deliver(summary: summary)
            DispatchQueue.main.async {
                CompanionWindowController.shared.enqueue(.info(summary))
            }
            return nil

        case "PreToolUse":
            return handlePreToolUse(event)

        default:
            DebugLog.log("unrecognized hook_event_name: \(event.hookEventName ?? "nil")")
            return nil
        }
    }

    /// Tools that ask the human something rather than requesting
    /// permission to act. These get surfaced but never gated — see
    /// Summarizer.summarizeQuestion.
    private static let questionToolNames: Set<String> = ["AskUserQuestion"]

    private func handlePreToolUse(_ event: HookEvent) -> Data? {
        if let toolName = event.toolName, Self.questionToolNames.contains(toolName) {
            let summary = Summarizer.summarizeQuestion(event)
            DebugLog.log("PreToolUse question surfaced (not gated): \(summary.body)")
            NotificationManager.deliver(summary: summary)
            DispatchQueue.main.async {
                CompanionWindowController.shared.enqueue(.info(summary))
            }
            return encodeDecision("allow", reason: "Question tool — surfaced, not gated")
        }

        let summary = Summarizer.summarizeToolUse(event)
        let id = UUID()
        PendingRequestStore.shared.register(id)
        DebugLog.log("PreToolUse ask enqueued id=\(id) tool=\(event.toolName ?? "nil") body=\(summary.body) risky=\(summary.isRisky) timeout=\(Self.gateTimeout)s")

        NotificationManager.deliver(summary: summary)
        DispatchQueue.main.async {
            CompanionWindowController.shared.enqueue(.ask(id: id, summary))
        }

        let decision = PendingRequestStore.shared.waitForDecision(id, timeout: Self.gateTimeout)
        DebugLog.log("PreToolUse decision id=\(id) decision=\(decision)")

        switch decision {
        case .allow:
            return encodeDecision("allow", reason: "Approved via Nudge")
        case .deny:
            return encodeDecision("deny", reason: "Denied via Nudge")
        case .timedOut:
            DispatchQueue.main.async {
                CompanionWindowController.shared.expireAsk(id: id)
            }
            // No output -> Claude Code defers to its own normal prompt.
            return nil
        }
    }

    private func encodeDecision(_ decision: String, reason: String) -> Data? {
        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }
}
