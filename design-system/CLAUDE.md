# Post Run Drip — standing instructions

## Copy

**Never write literary workout titles.** A headline names the session; it does not
editorialise it.

- Banned: `Six by eight hundred, held.` / `Eighteen miles, headwind.` /
  `Called it at three.` — spelled-out numbers plus a mood-word flourish. That is
  the app writing poetry about someone else's run.
- Write instead: `6 × 800m.` / `18 miles, long run.` / `Cut short at 3 miles.`
- Numerals stay numerals. `5 mi`, never "five miles."
- The athlete supplies the feeling, in their own transcribed words. The interface
  supplies the facts.
- No emoji, no cheerleading, no exclamation points, no title-case headlines.

## Type roles (locked)

Display Instrument Sans · Label Schibsted Grotesk · Prose Crimson Pro ·
Data Inter · Mono JetBrains. Italic mono is the athlete; roman mono is the machine.
Never set AI output in Crimson, and never in italic.

**No licensed faces.** Neue Haas Grotesk and Akzidenz-Grotesk are out for good:
the licences cost more than this project can carry and the free downloads are rips.
Do not reintroduce them, and do not wire up a font file whose licence is unclear.
Instrument Sans was chosen on measurement (+3.1% width vs Haas at 46px/700).

## Directions

Direction I lives in `colors_and_type.css` (`--*`). Direction II "Broadsheet"
lives in `broadsheet/broadsheet.css` (`--bs-*`). Do not mix their tokens.
