# Post Run Drip — standing instructions

## Copy

**Never write literary workout titles.** A headline names the session; it does not
editorialise it.

- Banned: `Six by eight hundred, held.` / `Eighteen miles, headwind.` /
  `Called it at three.` — spelled-out numbers plus a mood-word flourish. That is
  the app writing poetry about someone else's run.
- Write instead: `6 × 800m` / `18 miles, long run` / `Cut short at 3 miles`
- Numerals stay numerals. `5 mi`, never "five miles."
- The athlete supplies the feeling, in their own transcribed words. The interface
  supplies the facts.
- No emoji, no cheerleading, no exclamation points.

**No terminal periods on anything that names something** (Sep 2026). Workout titles,
screen headlines and section titles are labels, not sentences: `4 × 2 mi @ threshold`,
`Log Your Run`, `Load and Recovery`. Running prose — the read, captions, body copy,
the athlete's transcribed words — keeps its punctuation.

**Screen and section titles are Title Case; workout titles are not** (Sep 2026, and
this retires the old "no title-case headlines" rule). `Log Your Run`, `Your Week`,
`Race Prediction`, `The Workout` — but `4 × 2 mi @ threshold`, `16 miles, long run`,
`Easy 4.4 miles`, which name what the athlete did in the units they did it in.

**No constructed headlines.** A screen headline says what the screen is. Not
`The week, decided` or `Who needs you today` — `Your Week`, `Your Roster`.

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
