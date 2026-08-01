# M0 spike

Findings: [M0-findings.md](M0-findings.md)

## How to try the payload logger yourself

This hook is a safe no-op — it just appends whatever Claude Code sends it to
a log file, then always defers to the normal permission prompt. Nothing
about how Claude Code behaves changes, other than a log line getting
written each time a tool call is about to happen.

**Don't register it in the session you're currently talking to Claude in** —
settings changes need a fresh session to take effect, and editing hook
config for your active session mid-conversation is exactly the kind of
"modify things out from under yourself" move worth avoiding. Try it in a
new terminal / new Claude Code session instead.

1. Copy the relevant bit of `settings.example.json` into `~/.claude/settings.json`
   (merge with whatever's already there — don't overwrite), or into a
   project's `.claude/settings.json` if you'd rather scope it to one repo.
2. Start a **new** Claude Code session in that project.
3. Ask it to do something that needs a tool call (e.g. "run `ls`").
4. Check `/tmp/claude-pretooluse-spike.jsonl` — you should see the exact
   JSON payload Claude Code sent, one line per tool call.
5. Compare it against the schema in [M0-findings.md](M0-findings.md) §1.

When you're done, remove the hook entry from `settings.json` again.
