# Nudge (M1 build)

A menu bar agent + floating companion widget that intercepts Claude Code's
`PreToolUse` hook, shows you a plain-language summary, and lets you
approve/deny right there — without opening the terminal. See
[docs/PRD.md](../docs/PRD.md) for the full spec and
[spike/M0-findings.md](../spike/M0-findings.md) for the hook contract this
is built on.

## Why there's no macOS notification banner

The original plan used native `UNUserNotificationCenter` banners. Testing
on this machine found that macOS hard-denies local notification
authorization for any app that isn't signed with a real Apple Developer
identity (`UNErrorCodeNotificationsNotAllowed`, no permission prompt even
shown) — confirmed for both the modern and legacy (`NSUserNotificationCenter`)
notification APIs. There's no signing identity on this machine
(`security find-identity -v -p codesigning` → 0 identities), so instead of
blocking on that, Nudge draws its own floating window (the "companion") —
no OS permission needed, since it's just Nudge's own UI.

**Companion visuals are a placeholder** (an emoji face + a text bubble) —
the real character design is a separate pass.

## How it works

- **`SessionStart` / `SessionEnd` hooks** (fire-and-forget) tell Nudge when
  a Claude Code session opens/closes. The companion window is only visible
  when at least one session is open *and* the menu bar toggle is on.
- **`Notification` hook** (fire-and-forget, can't gate anything) shows an
  informational bubble — e.g. "Claude has been waiting on you" — with just
  an "Open Claude" button.
- **`PreToolUse` hook** (blocking) is the real gating path: Claude Code
  pauses, the hook script hands the request to Nudge and waits; the
  companion shows the plain-language ask with Yes / No / Open Claude;
  whichever you tap resolves the hook, and Claude proceeds or is blocked
  without ever showing its own terminal prompt.
- If Nudge isn't running, or you tap nothing before the timeout, the hook
  produces no output and Claude Code **falls back to its normal terminal
  prompt** — nothing is ever silently blocked.
- **`AskUserQuestion` calls are a special case.** They arrive via
  `PreToolUse` like anything else, but they're Claude asking *you*
  something, not asking permission to act — there's no sensible Yes/No for
  "should I use date-fns or Luxon?". These are auto-allowed immediately
  (no wait, no delay to the terminal) while still showing up on the
  companion as a heads-up with the actual question text, so you know
  Claude's waiting on an answer even if you're on another screen.

## Build & run

```bash
./scripts/build-app.sh
open build/Nudge.app
```

The menu bar icon (a bell) has an on/off toggle and Quit. `LSUIElement` is
set, so there's no Dock icon.

## Installing the hooks

**Don't register these in the session you're currently talking to Claude
in** — settings changes need a fresh session, and editing your active
session's hook config mid-conversation is worth avoiding. Try this in a
**new** terminal / new Claude Code session instead.

Merge [`settings.example.json`](settings.example.json) into
`~/.claude/settings.json` (global) or a project's `.claude/settings.json`
(scoped) — don't overwrite whatever's already there. Update the script
paths if you move this repo.

## Manual testing without clicking anything

Screen capture / display access wasn't available in the environment this
was built in, so the interactive Yes/No tap itself couldn't be verified
visually — only the plumbing around it. Two things that helped:

1. **`~/.nudge/debug.log`** — plain-text trace of every hook event Nudge
   receives and every decision it makes (the system log redacts message
   content as `<private>` by default, so this is more useful than
   `Console.app` for Nudge specifically).
2. **`NUDGE_GATE_TIMEOUT`** env var — overrides the 240s default wait for a
   `PreToolUse` decision, so you can test the full timeout round-trip in a
   few seconds instead of 4 minutes:
   ```bash
   open -a build/Nudge.app --env NUDGE_GATE_TIMEOUT=5
   ```

To simulate a hook firing without a real Claude Code session:

```bash
echo '{"session_id":"s1","cwd":"'"$PWD"'","hook_event_name":"SessionStart"}' \
  | nc -U -w5 ~/.nudge/nudge.sock

echo '{"session_id":"s1","cwd":"'"$PWD"'","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"},"tool_use_id":"t1"}' \
  | nc -U -w280 ~/.nudge/nudge.sock
```

The second command blocks (that's expected — it's holding the connection
open exactly like a real Claude Code hook would) until you tap something
on the companion, or it times out.

**You should visually confirm the companion actually appears and the
buttons work** the first time you run this for real — that part of the
loop wasn't testable from here.

## Known limitations (M1)

- "Open Claude" activates iTerm/Terminal generally, not the exact
  window/tab for a given session — there's no session→window registry yet
  (PRD docs/PRD.md §6 P0 #9 is still open).
- No queueing UI polish beyond FIFO — multiple pending asks show one at a
  time in arrival order.
- No risk-based default focus (PRD P1 #10), no do-not-disturb (P1 #11), no
  history log (P2 #15) yet.
- Companion window position is fixed bottom-right; not yet
  user-configurable.
