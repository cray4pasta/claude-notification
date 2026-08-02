# Nudge (M1 build)

A menu bar agent + floating companion widget that intercepts Claude Code's
`PreToolUse` hook, shows you a plain-language summary, and lets you
approve/deny right there — without opening the terminal. See
[docs/PRD.md](../docs/PRD.md) for the full spec and
[spike/M0-findings.md](../spike/M0-findings.md) for the hook contract this
is built on.

## Notification banners: two dead ends, then `osascript`

The original plan used native `UNUserNotificationCenter` banners. Testing
on this machine found that macOS hard-denies local notification
authorization for any app that isn't signed with a real Apple Developer
identity (`UNErrorCodeNotificationsNotAllowed`, no permission prompt even
shown) — confirmed for both the modern and legacy (`NSUserNotificationCenter`)
notification APIs, and there's no signing identity on this machine
(`security find-identity -v -p codesigning` → 0 identities).

The floating companion window doesn't need either — it's Nudge's own UI, no
OS permission required — so that became the primary interactive surface
regardless. But a real OS banner is still useful as a supplementary
catch-your-eye signal (shows across Spaces/full-screen apps, has a sound,
survives even if the companion window hasn't been noticed), so
[`NotificationManager.swift`](Nudge/Sources/Nudge/NotificationManager.swift)
now fires one via `osascript -e 'display notification ...'` instead — an
idea borrowed from
[claude-menubar-buddy](https://github.com/spyza008/claude-menubar-buddy),
which hits the same signing wall and solves it the same way. AppleScript's
`display notification` posts under the OS's own identity, needs no
entitlement or bundle at all, and isn't deprecated — but it also has no
click-through/action-button callback, so it's fire-and-forget only. That's
fine here since the companion window is still where Yes/No/Open Claude
actually happen.

**Companion visuals are a placeholder** (an emoji face + a text bubble) —
the real character design is a separate pass.

## Rate-limit awareness

The menu bar dropdown shows your current 5-hour and weekly usage
percentage (e.g. `Usage — 5h: 24% · Weekly: 7%`), refreshed every 30s.
[`UsageStats.swift`](Nudge/Sources/Nudge/UsageStats.swift) reads this
straight out of `~/Library/Application Support/Claude/plan-usage-history.json`
— the same file Claude Desktop already writes for its own "Plan usage"
panel — so there's no extra polling or API call involved. Another idea
lifted from claude-menubar-buddy, which reflects the same numbers as its
pet's mood; we don't have a mood system, so it's plain text in the menu
instead. Shows "Usage: unavailable" if the file's missing or the most
recent sample doesn't have both numbers — e.g. before Claude Desktop's
own usage panel has run at least once.

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

**The `command` paths must stay wrapped in escaped double quotes**
(`"\"/path/with a space/script.sh\""`), not bare strings. Claude Code
runs `command` hooks through a shell, and this repo's own path — `Claude
notification` — has a space in it; a bare unquoted path silently splits
mid-string (`sh: /Users/you/Claude: No such file or directory`, exit
127) and Claude Code treats that as a non-blocking hook error, so it
just proceeds normally with **no visible failure** and nothing ever
reaches Nudge. This is exactly what happened during initial testing —
looked identical to "Nudge isn't receiving anything" from every other
angle (Desktop vs. Terminal, resumed vs. fresh session) until reproduced
directly with `sh -c "<unquoted command>"`.

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
