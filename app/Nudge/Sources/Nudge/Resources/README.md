# Companion artwork spec

Drop animated GIFs here with these exact filenames and the companion picks
them up automatically on next launch — no code changes needed. Anything
missing just falls back to the current emoji, so the app works fine before
and during art production.

## Files needed (4 moods)

The companion only appears when there's actually something to show you —
it disappears the instant you resolve it, rather than sitting on screen
idle — so there's no "resting" mood to draw here, just the states that
correspond to something actually being on screen.

| Filename | When it shows | What it should feel like |
|---|---|---|
| `asking.gif` | Waiting on your Yes/No for a normal (non-risky) request | Attentive, curious — "well?" |
| `alert.gif` | Waiting on Yes/No for something flagged risky (`rm -rf`, force-push, etc.), or a risky heads-up | Concerned/alarmed — reinforces the red Yes/Always Allow buttons shown alongside it |
| `question.gif` | Claude asked *you* a question (not a permission ask) | Curious, thinking — there's an answer to go type, no decision to make here |
| `notify.gif` | General FYI heads-up (e.g. "Claude's been idle waiting on you") | Friendly, casual |

## Format

- **Animated GIF**, looping infinitely (loop count 0) — `NSImageView.animates
  = true` plays it automatically using the GIF's own frame timing, so no
  particular frame rate is required, just don't make individual frames so
  slow it reads as static.
- **Square canvas, 130×130pt display slot** — bigger than the original
  small-icon version, since the character now sits overlapping the
  bubble's bottom-left corner (like the reference mockup) rather than as a
  small icon inside it. Export at **260×260px or larger** so it stays
  crisp on this Mac's Retina display. Non-square art gets letterboxed to
  fit rather than stretched.
- **Compose for the overlap.** The character's frame sits at the window's
  bottom-left corner, and the bubble's bottom-left corner sits inset from
  that by about (86pt, 30pt) — so roughly the character's *upper-right*
  third is what visually overlaps the bubble edge (matching the reference:
  head/ears poking up into the bubble corner, body sitting below-left of
  it). Draw with that overlap in mind rather than a centered icon — a
  character sized/posed to fill its full 130×130 frame edge-to-edge will
  read much better here than a small centered figure.
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
