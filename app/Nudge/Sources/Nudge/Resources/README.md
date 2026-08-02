# Companion artwork spec

Drop animated GIFs here with these exact filenames and the companion picks
them up automatically on next launch — no code changes needed. Anything
missing just falls back to the current emoji, so the app works fine before
and during art production.

## Files needed (5 moods)

| Filename | When it shows | What it should feel like |
|---|---|---|
| `idle.gif` | Nothing pending — companion is just sitting there | Calm, resting, maybe a slow breathing/blinking loop |
| `asking.gif` | Waiting on your Yes/No for a normal (non-risky) request | Attentive, curious — "well?" |
| `alert.gif` | Waiting on Yes/No for something flagged risky (`rm -rf`, force-push, etc.), or a risky heads-up | Concerned/alarmed — reinforces the red accent stripe already shown alongside it |
| `question.gif` | Claude asked *you* a question (not a permission ask) | Curious, thinking — there's an answer to go type, no decision to make here |
| `notify.gif` | General FYI heads-up (e.g. "Claude's been idle waiting on you") | Friendly, casual |

## Format

- **Animated GIF**, looping infinitely (loop count 0) — `NSImageView.animates
  = true` plays it automatically using the GIF's own frame timing, so no
  particular frame rate is required, just don't make individual frames so
  slow it reads as static.
- **Square canvas.** The display slot is small (~48×44pt) but this Mac's
  screen is Retina — export at **128×128px minimum** (256×256 is fine too)
  so it stays crisp scaled down, not blurry scaled up. Non-square art gets
  letterboxed to fit rather than stretched, so it doesn't have to be
  pixel-perfect square, just roughly so.
- **Transparent background.** GIF only supports 1-bit (on/off) transparency,
  not smooth alpha — so edges against the transparent area will be hard
  rather than softly anti-aliased. Design with that in mind (a clean
  silhouette reads better than fine feathered edges that'll get a harsh
  cutout).
- Keep loops short — under ~2 seconds — since these play continuously
  whenever that mood is on screen.

## Reference

`claude-menubar-buddy` (MIT-licensed, github.com/spyza008/claude-menubar-buddy)
uses this exact technique — worth a look at their `Resources/*.gif` files
for a sense of scale/style if you want a starting point, though it's your
own character here, not theirs.
