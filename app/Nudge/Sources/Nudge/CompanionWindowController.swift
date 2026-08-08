import Cocoa

/// One thing the companion currently has to show: either a heads-up it
/// can't act on (from `Notification`), or a real decision it's blocking
/// Claude on (from `PreToolUse`).
enum CompanionItem {
    case info(Summarizer.Summary)
    case ask(id: UUID, Summarizer.Summary)
}

/// Owns the floating "lil guy" window (PRD docs/PRD.md §7): a cream speech
/// bubble with a character overlapping its bottom-left corner. The
/// character shows a custom animated GIF per mood if one exists in
/// Sources/Nudge/Resources (see the README there for the spec), falling
/// back to a plain emoji otherwise. Behavior: docked bottom-right, floats
/// above full-screen apps and follows across Spaces, only visible when a
/// Claude Code session is open AND the master toggle is on, only actually
/// on screen when there's a real item to show, and queues pending items
/// instead of stacking windows.
final class CompanionWindowController: NSObject {
    static let shared = CompanionWindowController()

    // MARK: - Palette
    //
    // Approximated from the reference mockup by eye — swap these for exact
    // Figma hex values once available; nothing else about the layout below
    // depends on the exact values.
    private static let bubbleColor = NSColor(calibratedRed: 0.965, green: 0.945, blue: 0.902, alpha: 1)
    private static let textColor = NSColor(calibratedRed: 0.145, green: 0.118, blue: 0.098, alpha: 1)
    private static let accentColor = NSColor(calibratedRed: 0.851, green: 0.494, blue: 0.373, alpha: 1)
    private static let riskyColor = NSColor(calibratedRed: 0.780, green: 0.290, blue: 0.220, alpha: 1)
    private static let pillButtonHeight: CGFloat = 30

    private var window: NSPanel!
    private var bubbleView: NSView!
    private var faceLabel: NSTextField!
    private var faceImageView: NSImageView!
    private var bodyLabel: NSTextField!
    private var buttonStack: NSStackView!
    private var yesButton: NSButton!
    private var noButton: NSButton!
    private var alwaysAllowButton: NSButton!
    private var openButton: NSButton!

    private var queue: [CompanionItem] = []
    private var currentItem: CompanionItem?
    private var infoDismissTimer: Timer?

    // Bubble width has to fit 4 buttons in one row (No / Yes / Always
    // Allow / Open Claude): 34+56+110+70 + 3*8(spacing) = 294, plus
    // 20pt padding each side = 334 minimum. The first version of this
    // layout used a much narrower bubble sized for the 3-button reference
    // mockup and didn't budget for our 4th (Open Claude) button at all -
    // it silently overflowed past the window's own edge and got clipped,
    // which looked like a missing button rather than a layout bug.
    private let windowSize = NSSize(width: 442, height: 210)
    private let characterSize = NSSize(width: 130, height: 130)
    private let bubbleFrame: NSRect
    private let margin: CGFloat = 24

    private override init() {
        bubbleFrame = NSRect(x: 86, y: 30, width: 442 - 86 - 16, height: 210 - 30 - 16)
        super.init()
        buildWindow()
    }

    // MARK: - Visibility

    /// Call whenever SettingsStore or SessionTracker state changes.
    ///
    /// Note this only *permits* visibility when a session is active and
    /// Nudge is enabled — it doesn't force the window on screen by itself.
    /// The window only actually appears when there's a real item to show
    /// (see enqueue/showNextIfNeeded); it disappears again the moment
    /// you've resolved everything, rather than lingering with an idle
    /// face the whole session.
    func refreshVisibility() {
        let shouldShow = SettingsStore.shared.isEnabled && SessionTracker.shared.hasActiveSessions
        DebugLog.log("refreshVisibility shouldShow=\(shouldShow) enabled=\(SettingsStore.shared.isEnabled) hasActiveSessions=\(SessionTracker.shared.hasActiveSessions)")
        if shouldShow {
            if currentItem != nil || !queue.isEmpty {
                positionWindow()
                window.orderFrontRegardless()
                showNextIfNeeded()
            }
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
        // Must reposition here, not just in refreshVisibility() - this is
        // the actual first place the window gets shown after a session
        // starts (refreshVisibility no longer positions/shows on its own
        // when nothing's queued yet, which is the normal case right after
        // SessionStart). Skipping this left the window at its raw (0,0)
        // init origin - bottom-left corner - on the very first ask of a
        // session, which is exactly the bug this once masked by always
        // repositioning on every session-start regardless of content.
        positionWindow()
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
            // Nothing left to show — disappear rather than sit there
            // idle. It comes back the instant something new arrives
            // (enqueue orders it front again).
            window.orderOut(nil)
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

    /// Same as Yes for this instance, plus records a rule so future
    /// identical requests (same project, same tool, same exact
    /// command/target) skip the ask entirely — see AlwaysAllowStore.
    @objc private func tappedAlwaysAllow() {
        guard case let .ask(id, summary) = currentItem else { return }
        AlwaysAllowStore.shared.alwaysAllow(cwd: summary.cwd, toolName: summary.toolName, detail: summary.rawDetail)
        DebugLog.log("always-allow recorded cwd=\(summary.cwd ?? "nil") tool=\(summary.toolName ?? "nil") detail=\(summary.rawDetail ?? "nil")")
        PendingRequestStore.shared.resolve(id, decision: .allow)
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

    /// Shows a custom animated GIF for `mood` if you've dropped one into
    /// Sources/Nudge/Resources/ (see the README there for the exact spec),
    /// falling back to the plain emoji otherwise — the companion works
    /// out of the box either way, and upgrades automatically the moment a
    /// matching file shows up.
    private func setMood(_ mood: String, fallbackEmoji: String) {
        if let url = Bundle.module.url(forResource: mood, withExtension: "gif"),
           let image = NSImage(contentsOf: url) {
            faceImageView.image = image
            faceImageView.animates = true
            faceImageView.isHidden = false
            faceLabel.isHidden = true
        } else {
            faceImageView.isHidden = true
            faceLabel.isHidden = false
            faceLabel.stringValue = fallbackEmoji
        }
    }

    /// Sets a sane default look before anything's ever been shown. Not
    /// actually reachable on screen anymore in normal use — the window
    /// only appears when there's a real item (see showNextIfNeeded) — but
    /// kept as the window's cold-init state so labels aren't left in a
    /// blank/undefined state before the first real render() call.
    private func renderIdle() {
        setMood("idle", fallbackEmoji: "🙂")
        bodyLabel.stringValue = ""
        bodyLabel.isHidden = true
        buttonStack.isHidden = true
    }

    private func render(_ item: CompanionItem) {
        switch item {
        case let .info(summary):
            if summary.isQuestion {
                setMood("question", fallbackEmoji: "💭")
            } else if summary.isRisky {
                setMood("alert", fallbackEmoji: "😬")
            } else {
                setMood("notify", fallbackEmoji: "💬")
            }
            bodyLabel.stringValue = summary.body
            bodyLabel.isHidden = false
            yesButton.isHidden = true
            noButton.isHidden = true
            alwaysAllowButton.isHidden = true
            openButton.isHidden = false
            styleOutlinePill(openButton)
            buttonStack.isHidden = false
            infoDismissTimer?.invalidate()
            // Questions stay up longer than a passive heads-up — there's
            // an actual answer to go type, not just something to notice.
            infoDismissTimer = Timer.scheduledTimer(withTimeInterval: summary.isQuestion ? 45 : 20, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.currentItem = nil
                self.showNextIfNeeded()
            }
        case let .ask(_, summary):
            setMood(summary.isRisky ? "alert" : "asking", fallbackEmoji: summary.isRisky ? "⚠️" : "🤔")
            bodyLabel.stringValue = summary.body
            bodyLabel.isHidden = false
            yesButton.isHidden = false
            noButton.isHidden = false
            alwaysAllowButton.isHidden = false
            openButton.isHidden = false
            stylePill(yesButton, fill: summary.isRisky ? Self.riskyColor : Self.accentColor)
            stylePill(alwaysAllowButton, fill: summary.isRisky ? Self.riskyColor : Self.accentColor)
            styleTextLink(noButton)
            styleOutlinePill(openButton)
            buttonStack.isHidden = false
        }
    }

    // MARK: - Button styling
    //
    // Plain isBordered=false NSButtons drawn via their own layer rather
    // than a custom NSButton subclass — simplest way to get a solid pill
    // fill, an outline pill, and a bare colored text link out of the same
    // control type, and easy to re-style on every render() call (e.g. the
    // risky-red swap) without tracking extra state.

    private func stylePill(_ button: NSButton, fill: NSColor) {
        button.wantsLayer = true
        // Fixed, not button.bounds.height/2 - bounds can still be zero the
        // first time this runs, before Auto Layout has resolved the
        // buttons' height constraints (set to Self.pillButtonHeight below).
        button.layer?.cornerRadius = Self.pillButtonHeight / 2
        button.layer?.backgroundColor = fill.cgColor
        button.layer?.borderWidth = 0
        setTitleColor(button, .white, weight: .semibold)
    }

    private func styleOutlinePill(_ button: NSButton) {
        button.wantsLayer = true
        // Fixed, not button.bounds.height/2 - bounds can still be zero the
        // first time this runs, before Auto Layout has resolved the
        // buttons' height constraints (set to Self.pillButtonHeight below).
        button.layer?.cornerRadius = Self.pillButtonHeight / 2
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderColor = Self.textColor.withAlphaComponent(0.35).cgColor
        button.layer?.borderWidth = 1.2
        setTitleColor(button, Self.textColor, weight: .medium)
    }

    private func styleTextLink(_ button: NSButton) {
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderWidth = 0
        setTitleColor(button, Self.accentColor, weight: .semibold)
    }

    private func setTitleColor(_ button: NSButton, _ color: NSColor, weight: NSFont.Weight) {
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12.5, weight: weight)]
        )
    }

    // MARK: - Window setup

    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.maxX - windowSize.width - margin,
            y: frame.minY + margin
        )
        window.setFrame(NSRect(origin: origin, size: windowSize), display: true)
    }

    private func buildWindow() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
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

        let contentView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        panel.contentView = contentView

        // Bubble sits inset from the window's top-right area, leaving room
        // at bottom-left for the character to overlap its corner.
        let bubble = NSView(frame: bubbleFrame)
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = Self.bubbleColor.cgColor
        bubble.layer?.cornerRadius = 28
        bubble.shadow = NSShadow()
        bubble.layer?.shadowColor = NSColor.black.cgColor
        bubble.layer?.shadowOpacity = 0.18
        bubble.layer?.shadowRadius = 14
        bubble.layer?.shadowOffset = NSSize(width: 0, height: -4)
        contentView.addSubview(bubble)
        bubbleView = bubble

        let bodyFrame = NSRect(
            x: 20, y: 52,
            width: bubbleFrame.width - 40,
            height: bubbleFrame.height - 52 - 18
        )
        let body = NSTextField(wrappingLabelWithString: "")
        body.font = .systemFont(ofSize: 15, weight: .semibold)
        body.textColor = Self.textColor
        body.frame = bodyFrame
        bubble.addSubview(body)
        bodyLabel = body

        let yes = NSButton(title: "Yes", target: self, action: #selector(tappedYes))
        let no = NSButton(title: "No", target: self, action: #selector(tappedNo))
        let alwaysAllow = NSButton(title: "Always Allow", target: self, action: #selector(tappedAlwaysAllow))
        let open = NSButton(title: "Open", target: self, action: #selector(tappedOpenClaude))
        for button in [yes, no, alwaysAllow, open] {
            button.isBordered = false
            button.setButtonType(.momentaryChange)
        }
        yesButton = yes
        noButton = no
        alwaysAllowButton = alwaysAllow
        openButton = open

        // Fixed heights so the pill corner radius (height/2) is stable,
        // and explicit widths since borderless buttons don't reserve the
        // bezel padding a normal pill shape needs.
        for (button, width) in [(no, CGFloat(34)), (yes, 56), (alwaysAllow, 110), (open, 70)] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            button.heightAnchor.constraint(equalToConstant: Self.pillButtonHeight).isActive = true
        }

        let stack = NSStackView(views: [no, yes, alwaysAllow, open])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.frame = NSRect(x: 20, y: 16, width: bubbleFrame.width - 40, height: 30)
        bubble.addSubview(stack)
        buttonStack = stack

        // Character overlaps the bubble's bottom-left corner, on top of it
        // in z-order (added to contentView, not bubble, and after bubble
        // so it draws above).
        let faceFrame = NSRect(origin: .zero, size: characterSize)

        let face = NSTextField(labelWithString: "🙂")
        face.font = .systemFont(ofSize: 88)
        face.alignment = .center
        face.frame = faceFrame
        contentView.addSubview(face)
        faceLabel = face

        // .scaleProportionallyUpOrDown letterboxes non-square art instead
        // of distorting it, so custom GIFs don't need to be pixel-exact.
        let image = NSImageView(frame: faceFrame)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.isHidden = true
        contentView.addSubview(image)
        faceImageView = image

        window = panel
        renderIdle()
    }
}
