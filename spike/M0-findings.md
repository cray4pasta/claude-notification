# M0 Spike Findings: `PreToolUse` / `Notification` hook contract

**Claude Code version tested against:** 2.1.220
**Source:** official docs, `code.claude.com/docs/en/hooks.md` and `hooks-guide.md`
**Date:** 2026-08-01

## Verdict

**Full inline gating (the core mechanic the PRD depends on) is achievable.** A `PreToolUse` hook can return an `allow`/`deny` decision and Claude Code will skip its own terminal permission prompt entirely for that call. This confirms the architecture in [docs/PRD.md](../docs/PRD.md) §4/§9 as designed — no fallback to "notify + deep link only" needed for M1.

## 1. `PreToolUse` hook input (stdin, JSON)

```json
{
  "session_id": "abc123",
  "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/directory",
  "permission_mode": "default",
  "effort": { "level": "medium" },
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test",
    "description": "Run tests",
    "timeout": 120000,
    "run_in_background": false
  },
  "tool_use_id": "toolu_01ABC123...",
  "agent_id": "subagent-uuid",
  "agent_type": "Explore"
}
```

- `tool_input` shape varies per tool (`command` for Bash, `file_path` for Edit/Write, `url` for WebFetch, etc.) — the plain-language summarizer (PRD §6, #5) needs a per-tool-type mapping, not one generic parser.
- `agent_id`/`agent_type` only show up when the call comes from a subagent.
- `cwd` + `session_id` are what "session identification" (PRD §6, #8) hangs off of.

## 2. `PreToolUse` hook output (stdout, JSON)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Approved via Nudge",
    "updatedInput": { "command": "..." },
    "additionalContext": "..."
  }
}
```

| `permissionDecision` | Effect |
|---|---|
| `allow` | Skips the terminal prompt, runs the tool. Can still be overridden by org-level managed deny rules (not a concern for personal use). |
| `deny` | Tool is blocked, never runs. `permissionDecisionReason` is shown to Claude so it can adapt. |
| `ask` | Falls through to the normal terminal prompt. |
| `defer` | Normal permission flow; only meaningful in non-interactive (`-p`) mode. |

Alternative mechanism: exiting the hook script with code `2` and writing a reason to **stderr** also blocks the call, without needing the JSON shape. Exit `0` with no JSON = defer to normal flow. Any other exit code = non-blocking error, tool proceeds anyway, first stderr line shown to user as a warning.

## 3. Blocking behavior

Claude Code **blocks and waits** for the hook process to exit — default timeout **600 seconds**. This is the load-bearing fact for the whole design: the hook script can sit there waiting on a human response relayed over a local socket from the menu bar app, well within that window. Exact behavior *at* the 600s timeout isn't spelled out in the docs (presumably falls back to the normal prompt) — worth confirming empirically if we ever see it in practice, but not blocking for M1.

## 4. `Notification` hook

Fires on: `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`.

Fire-and-forget — its exit code/output never affects whether Claude proceeds. Good fit for the M1 "Claude is waiting on you" idle alert (PRD §10, M1), useless for gating.

## 5. `settings.json` config

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/path/to/hook.sh", "timeout": 600 }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "*",
        "hooks": [ { "type": "command", "command": "/path/to/notify.sh" } ]
      }
    ]
  }
}
```

- Matcher: exact tool name (`"Bash"`), alternation (`"Edit|Write"`), regex (`"^Read"`), MCP wildcard (`"mcp__github__.*"`), or `"*"`/omitted for all tools.
- Can additionally filter with an `if` field using permission-rule syntax (e.g. only fire on `Bash(rm *)`) to skip spawning the hook process entirely for calls we don't care about.
- Global (`~/.claude/settings.json`) or project-scoped (`.claude/settings.json`, committable).

## 6. Open caveats (not blocking, worth remembering)

- Behavior exactly at hook timeout expiry isn't documented — assume it falls back to the normal prompt, verify empirically later.
- Managed org policy (deny/ask rules) can override a hook's `allow` — irrelevant on a personal machine, matters if this is ever run somewhere with org policies.
- Full hook-script environment variable list isn't exhaustively documented (`${CLAUDE_PROJECT_DIR}` etc. are confirmed to exist).

## Next step

See `spike/log-payload-hook.sh` — a no-op hook that just logs the exact stdin payload for a real tool call on this machine, to sanity-check the schema above before building the socket/menu-bar plumbing.
