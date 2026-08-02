#!/bin/bash
# PreToolUse hook: forwards the JSON payload on stdin to Nudge, then BLOCKS
# waiting for Nudge to write back a permission-decision JSON on the same
# connection — Nudge itself is waiting on a human tapping Yes/No on the
# companion widget this whole time (see spike/M0-findings.md §2/§3).
#
# Whatever comes back on the socket is forwarded verbatim to this script's
# own stdout, which IS Claude Code's hook-output contract: a
# hookSpecificOutput.permissionDecision JSON means allow/deny; no output at
# all (Nudge not running, or nobody responded before the timeout) means
# "defer" — Claude Code falls back to its own normal terminal prompt. This
# script must never be the thing that blocks a decision from happening.

SOCK="${NUDGE_SOCKET_PATH:-$HOME/.nudge/nudge.sock}"

if [ -S "$SOCK" ]; then
  # -w260: safety cap, comfortably above Nudge's own 240s wait
  # (AppDelegate.gateTimeout) and comfortably under Claude Code's 600s
  # default hook timeout.
  nc -U -w260 "$SOCK"
else
  cat >/dev/null
fi

exit 0
