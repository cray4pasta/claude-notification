#!/bin/bash
# Fire-and-forget forwarder for SessionStart, SessionEnd, and Notification
# hooks: forwards the JSON payload already on stdin to Nudge's local Unix
# socket, and doesn't wait for or care about a response (these hook types
# can't gate anything in Claude Code — see spike/M0-findings.md §4).
#
# If Nudge isn't running, this is a silent no-op: Claude Code's own
# behavior is completely unaffected either way.

SOCK="${NUDGE_SOCKET_PATH:-$HOME/.nudge/nudge.sock}"

if [ -S "$SOCK" ]; then
  # -w5: safety cap only. Nudge's socket server closes the connection as
  # soon as it has parsed one complete JSON object (no need to wait for a
  # response here), so this normally returns almost immediately.
  nc -U -w5 "$SOCK" >/dev/null 2>&1 || true
else
  cat >/dev/null
fi

exit 0
