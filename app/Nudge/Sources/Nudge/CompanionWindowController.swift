import Cocoa

/// One thing the companion currently has to show: either a heads-up it
/// can't act on (from `Notification`), or a real decision it's blocking
/// Claude on (from `PreToolUse`).
enum CompanionItem {
    case info(Summarizer.Summary)
    case ask(id: UUID, Summarizer.Summary)
}

/// Owns the floating "lil guy" window (PRD docs/PRD.md §7). Visuals here
/// are placeholders — a plain rounded panel + emoji face — since the real
/// character design is a separate pass. Behavior is the real thing:
/// docked bottom-right, floats above full-screen apps and follows across
/// Spaces, only visible when a Claude Code session is open AND the master
/// toggle is on, and queues pending items instead of stacking windows.
final class CompanionWindowController: NSObject {
    static let shared = CompanionWindowController()

    private var window: NSPanel!
    private var faceLabel: NSTextField!
    private var bodyLabel: NSTextField!
    private var buttonStack: NSStackView!
    private var yesButton: NSButton!
    private var noButton: NSButton!
    private var openButton: NSButton!
    private var accentView: NSView!

    private var queue: [CompanionItem] = []
    private var currentItem: CompanionItem?
    private var infoDismissTimer: Timer?

    private let panelSize = NSSize(width: 260, height: 150)
    private let margin: CGFloat = 24

    private override init() {
        super.init()
        buildWindow()
    }

    // MARK: - Visibility

    /// Call whenever SettingsStore or SessionTracker state changes.
    func refreshVisibility() {
        let shouldShow = SettingsStore.shared.isEnabled && SessionTracker.shared.hasActiveSessions
        DebugLog.log("refreshVisibility shouldShow=\(shouldShow) enabled=\(SettingsStore.shared.isEnabled) hasActiveSessions=\(SessionTracker.shared.hasActiveSessions)")
        if shouldShow {
            positionWindow()
            window.orderFrontRegardless()
            if currentItem == nil { renderIdle() }
        } else {
            window.orderOut(nil)
        }
    }

    // MARK: - Incoming items

    func enqueue(_ item: CompanionItem) {
        guard SettingsStore.shared.isEnabled else {
            // Toggled off: PreToolUse asks must still get *a* decision so
            // the hook script doesn't hang — defer immediately.
            if case let .ask(id, _) = item {
                PendingRequestStore.shared.resolve(id, decision: .timedOut)
            }
            return
        }
        queue.append(item)
        window.orderFrontRegardless()
        showNextIfNeeded()
    }

    /// Called from AppDelegate when a background-thread wait for this ask
    /// timed out server-side, so the UI doesn't keep showing a stale ask
    /// nobody can act on anymore.
    func expireAsk(id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if case let .ask(currentID, _) = self.currentItem, currentID == id {
                self.currentItem = nil
                self.showNextIfNeeded()
            }
            self.queue.removeAll { item in
                if case let .ask(queuedID, _) = item { return queuedID == id }
                return false
            }
        }
    }

    private func showNextIfNeeded() {
        guard currentItem == nil else { return }
        infoDismissTimer?.invalidate()
        guard !queue.isEmpty else {
            renderIdle()
            return
        }
        let next = queue.removeFirst()
        currentItem = next
        render(next)
    }

    // MARK: - Actions

    @objc private func tappedYes() {
        guard case let .ask(id, _) = currentItem else { return }
        PendingRequestStore.shared.resolve(id, decision: .allow)
        currentItem = nil
        showNextIfNeeded()
    }

    @objc private func tappedNo() {
        guard case let .ask(id, _) = currentItem else { return }
        PendingRequestStore.shared.resolve(id, decision: .deny)
        currentItem = nil
        showNextIfNeeded()
    }

    @objc private func tappedOpenClaude() {
        var cwd: String?
        switch currentItem {
        case let .ask(_, summary), let .info(summary):
            cwd = summary.cwd
        case nil:
            break
        }
        TerminalFocuser.openClaude(cwd: cwd)
        if case let .ask(id, _) = currentItem {
            // Deliberately NOT resolving allow/deny — "deeper look" means
            // the human is taking over in the terminal. Falling through to
            // Claude Code's own prompt there is the safe behavior, so just
            // let this pending request ride out to its timeout.
            _ = id
        }
        currentItem = nil
        showNextIfNeeded()
    }

    // MARK: - Rendering

    private func renderIdle() {
        faceLabel.stringValue = "🙂"
        bodyLabel.stringValue = ""
        bodyLabel.isHidden = true
        buttonStack.isHidden = true
        accentView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
    }

    private func render(_ item: CompanionItem) {
        switch item {
        case let .info(summary):
            faceLabel.stringValue = summary.isQuestion ? "💭" : (summary.isRisky ? "😬" : "💬")
            bodyLabel.stringValue = summary.body
            bodyLabel.isHidden = false
            yesButton.isHidden = true
            noButton.isHidden = true
            openButton.isHidden = false
            buttonStack.isHidden = false
            accentView.layer?.backgroundColor = (summary.isRisky ? NSColor.systemRed : NSColor.controlAccentColor).cgColor
            infoDismissTimer?.invalidate()
            // Questions stay up longer than a passive heads-up — there's
            // an actual answer to go type, not just something to notice.
            infoDismissTimer = Timer.scheduledTimer(withTimeInterval: summary.isQuestion ? 45 : 20, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.currentItem = nil
                self.showNextIfNeeded()
            }
        case let .ask(_, summary):
            faceLabel.stringValue = summary.isRisky ? "⚠️" : "🤔"
            bodyLabel.stringValue = summary.body
            bodyLabel.isHidden = false
            yesButton.isHidden = false
            noButton.isHidden = false
            openButton.isHidden = false
            buttonStack.isHidden = false
            accentView.layer?.backgroundColor = (summary.isRisky ? NSColor.systemRed : NSColor.controlAccentColor).cgColor
        }
    }

    // MARK: - Window setup

    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.maxX - panelSize.width - margin,
            y: frame.minY + margin
        )
        window.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func buildWindow() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false

        let container = NSVisualEffectView(frame: panel.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        panel.contentView = container

        let accent = NSView(frame: NSRect(x: 0, y: 0, width: 4, height: panelSize.height))
        accent.autoresizingMask = [.height]
        accent.wantsLayer = true
        container.addSubview(accent)
        accentView = accent

        let face = NSTextField(labelWithString: "🙂")
        face.font = .systemFont(ofSize: 32)
        face.alignment = .center
        face.frame = NSRect(x: 14, y: panelSize.height - 54, width: 48, height: 44)
        container.addSubview(face)
        faceLabel = face

        let body = NSTextField(wrappingLabelWithString: "")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .labelColor
        body.frame = NSRect(x: 14, y: 44, width: panelSize.width - 28, height: panelSize.height - 100)
        body.autoresizingMask = [.width]
        container.addSubview(body)
        bodyLabel = body

        let yes = NSButton(title: "Yes", target: self, action: #selector(tappedYes))
        let no = NSButton(title: "No", target: self, action: #selector(tappedNo))
        let open = NSButton(title: "Open Claude", target: self, action: #selector(tappedOpenClaude))
        for button in [yes, no, open] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }
        yesButton = yes
        noButton = no
        openButton = open

        let stack = NSStackView(views: [yes, no, open])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.frame = NSRect(x: 14, y: 10, width: panelSize.width - 28, height: 24)
        stack.autoresizingMask = [.width]
        container.addSubview(stack)
        buttonStack = stack

        window = panel
        renderIdle()
    }
}
