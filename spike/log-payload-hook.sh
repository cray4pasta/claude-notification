#!/bin/bash
# M0 spike: no-op PreToolUse hook. Logs the exact stdin payload Claude Code
# sends, then always defers to the normal permission flow (exit 0, no JSON).
# Nothing about your Claude Code sessions changes until you register this in
# settings.json (see spike/settings.example.json) — safe to leave unregistered.

LOG_FILE="${CLAUDE_NOTIFICATION_SPIKE_LOG:-/tmp/claude-pretooluse-spike.jsonl}"

input=$(cat)
printf '%s\n' "$input" >> "$LOG_FILE"

# Defer: no JSON on stdout, exit 0 -> Claude Code falls back to its normal
# terminal prompt exactly as if this hook didn't exist.
exit 0
