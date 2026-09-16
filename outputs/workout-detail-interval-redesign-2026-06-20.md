# Workout Detail — Interval Session redesign (2026-06-20)

Recreating the uploaded "TEMPO · rep-by-rep" screen, aligned to **Post Run
Drip** and the canonical decisions in `CLAUDE.md`. Maps to
`WorkoutDetailScreen.jsx` ↔ `RunningLog/Workouts/WorkoutDetailPlate23.swift`
(Plate 23). This is the **interval/rep variant** of that screen — the
existing Plate 23 covers a steady run with telemetry; this adds the
rep-by-rep breakdown.

---

## 1. What's wrong with the original (and why)

The screenshot is clear and well-organized, but it breaks four house rules:

1. **`TEMPO` / "threshold session" is off-taxonomy.** Per `CLAUDE.md`,
   *"Tempo" and "Threshold" are dropped as ambiguous — the zone IS the
   workout label.* These reps run ~5:09–5:17/mi (avg work **5:13/mi**),
   which is this athlete's threshold band. The label should be the
   pace-zone: **`LT`**. The structural pattern (`2×(2K+2×1K)`) stays as
   the headline.
2. **The bar colors are correct — keep them, render as a continuous
   spectrum.** These are NOT a decorative rainbow. They're
   `PaceSpectrum` (`RunningLog/Workouts/PaceSpectrum.swift`), the
   "color == pace" source of truth: a green→plum ramp (slow → fast)
   whose ten stops map to the canonical 10-zone taxonomy — Easy `#6B8068`,
   Moderate `#8C9A57`, Steady `#B0A048`, MP `#C4873A`, **HMP `#D4592A`
   (the coral anchor, mid-ramp)**, LT `#C0492E`, 10K `#B23A2E`,
   5K `#9E3144`, 3K `#7E3A6B`, Mile `#6B4A8A`. The design system
   explicitly permits color to encode data **on data surfaces** (same
   ramp as the Volume × Pace chart). So the "one coral as punctuation"
   rule governs *chrome/accents*, not this chart. The only real fix:
   make the legend + bars read as a smooth **spectrum** (continuous
   `color(at:)` interpolation, not ten hard steps), and honor the
   existing `PACE COLOR` toggle that falls back to single-coral bars
   when the athlete turns encoding off.
3. **The chart axis is inverted and unlabeled.** Y runs 5:00 (top) →
   5:30 (bottom), so a *taller* bar is *faster* — legible only after
   study. Fix the encoding and label it.
4. **No editorial / observation layer.** Post Run Drip screens carry a
   short italic read of the data (feeling/observation, never a
   directive). The original is pure dashboard.

Plus two known iOS drift items to *not* repeat: eyebrows must be **mono**
(not PT Serif), and **no SF Symbol icons / emoji** anywhere.

---

## 2. The redesigned screen — region by region

Warm paper (`--paper #F5F3F0`), black ink, one coral. iPhone width
(~390pt). Top to bottom:

### A. Plate strip (header rail)
`PlateStrip surface="WORKOUT · INTERVAL SESSION" fig="FIG. 23"` — mono,
`--t-meta` (11px), tracked `0.14em`, `--ink-2`. Same rail as every plate.

### B. Title block
- **Eyebrow** (mono, `drip-eyebrow`, `--ink-2`): `TUESDAY · LT SESSION`
- **Headline** (Crimson Pro 700, `--t-display-l` 32px, `--ink`):
  `2K · 1K · 1K · 2K · 1K · 1K`
- **Dek** (PT Serif *italic*, 13px, `--ink-2`):
  *2 × (2K + 2×1K) threshold rehearsal · 5.0 mi work*

The coral "TEMPO" capsule from the original is removed. The label now
lives in the eyebrow as `LT`, ink-colored — coral is spent elsewhere
(see §3).

### C. Headline stat strip (4 columns)
Reuse the existing 4-stat strip pattern from `WorkoutDetailScreen.jsx`
(mono numerals, `tabular-nums`, hairline column dividers). The **one
coral value** in this cluster is AVG WORK — it's the number that defines
the session.

| Label | Value | Unit | Sub |
|---|---|---|---|
| **AVG WORK** *(coral)* | `5:13` | /mi | LT band |
| WORK | `5.0` | mi | 6 reps |
| AVG HR | `169` | bpm | Z4 |
| SPREAD | `10` | s | rep-to-rep |

### D. Rep-by-rep chart — "REP BY REP"
`Section eyebrow="REP BY REP" eyebrowRight="6 REPS · WORK"`.

- Six vertical bars, one per rep, **baseline = slowest**, height ∝ speed,
  with an explicit label so the encoding is unambiguous:
  small mono caption under the legend — `SHORTER REST ↑   FASTER →`
  is *not* needed; instead label the axis: a single mono tick at the
  fast end and a dashed **AVG** reference line (ink-3) with an `AVG`
  tag, exactly as the original had — keep that, it's good.
- **Color = pace, as a spectrum.** Each bar is filled by `PaceSpectrum`
  via `color(forPaceSec:slowSec:fastSec:)` — slowest rep green, fastest
  rep plum, coral (`#D4592A`) landing naturally at the HMP point of the
  ramp. Render it as a true gradient ramp, not ten discrete swatches.
  Keep the `PACE · SLOW → FAST` legend but draw it as a smooth gradient
  bar (use `PaceSpectrum.gradient`). Keep the dashed **AVG** reference
  line (ink-3).
- When `PACE COLOR` is toggled off, bars fall back to a single coral
  fill (per the `PaceSpectrum.swift` design note) — that's the only
  context where the "one coral" treatment applies here.

### E. Rep table
Columns **REP · SPLIT · REST**, mono `tabular-nums`, `--rule` hairline
dividers between rows (no zebra fill — editorial = flat).

- Left chip per row: a 10px square. Ink for all rows; **coral only on
  the standout row** (same rep highlighted in the chart). One coral mark,
  echoed across chart + table = the "punctuation" doing double duty.
- Quote the splits verbatim (mirror the Niggles "quote verbatim"
  instinct): show real `6:34 / 3:12 / 3:12 / 6:37 / 3:12 / 3:14` and
  rests `2:05 / 1:12 / 1:09 / 2:20 / 1:07 / 0:04`.
- Optional 4th column `/MI` (per-rep pace) in `--ink-3` if it fits
  without crowding; drop on narrow screens.

### F. Observation line (the editorial layer)
One PT Serif *italic* line under the table, `--ink`, citing ≥1 number
(the `data_depth ≥ 2` rule). Observation, **never** prescription —
AI advises, never acts; no "you should…", no "next time run…".

> *"Ten seconds covered all six reps — the 2K floats sit right on the
> 1K efforts. Even from the gun, steady at the line."*

If you want a soft question (Coach-voice posture), keep it to one and
make it reflective, not directive: *"Did the closing 1K feel like a
reach, or like there was more there?"*

### G. Footer — leave as the stat strip, or fold into C
The original's bottom strip (AVG WORK / WORK / AVG HR / SPREAD) is now
the **headline** strip (C). Don't duplicate it at the bottom. End the
screen on the observation line + generous bottom padding (`--space-6`).

---

## 3. Color budget — two different rules for two surface types

Your system draws a line the original screen already respects:

- **Data surfaces** (the rep chart D, the rep-table chips E): color
  **encodes pace**, via `PaceSpectrum` (green→plum, coral at HMP). This
  is allowed and correct. Each bar and each row chip is colored by that
  rep's pace. Coral appears wherever a rep lands at HMP — it's earned by
  the data, not placed by hand.
- **Chrome / accents** (eyebrows, stat values, links): here the "one
  coral per cluster, used like punctuation" rule applies. In the stat
  strip (C), the single coral value is `AVG WORK` — everything else ink.

So coral shows up in two roles on this screen (a pace-band on the chart
*and* the AVG WORK stat), and that's fine because one is data, one is
chrome. Don't add a *third*, hand-placed coral accent competing in the
chrome layer.

---

## 4. Type & token cheat-sheet (use these exact vars)

- Page bg `--paper` · cards `--card` · rules `--rule`
- Ink `--ink` / meta `--ink-2` / captions `--ink-3`
- Accent `--coral` (#D4592A) — the only one
- Eyebrows: `--font-mono`, 11px, `letter-spacing:0.12em`, uppercase,
  `--ink-2` (this is the drift fix — **not** PT Serif)
- Headline: `--font-display` (Crimson Pro) 700, 32px
- Dek / observation: `--font-body` (PT Serif) italic, 13px
- All numerals: `--font-mono`, 600, `font-variant-numeric: tabular-nums`
- Spacing on the 8pt scale (`--space-*`); no off-grid 14/22 values
- Empty cells (e.g. missing HR): `EmptyStateView`, **never** an em-dash

---

## 5. Notes for whoever builds the Swift version

- This is the **interval variant** of `WorkoutDetailPlate23.swift`. The
  rep-by-rep chart + table are new; the title block and stat strip reuse
  existing patterns in that file.
- Bars: a simple `HStack` of `Capsule`/`RoundedRectangle` heights driven
  by `(repPace - slowest) / (fastest - slowest)`. AVG line is an overlaid
  `Rectangle` at the avg fraction, dashed.
- The "standout rep" is a derived property, not hardcoded — default to
  the closing work rep; expose so design can switch to "fastest."
- Pace-zone label comes from the zone engine, not a stored "Tempo"
  string. Verify against `derivePaceTableFromGoal` / `PaceCalculator`.

---

## 6. Copy-paste build prompt

Paste this into Claude (or any AI builder) to generate a single-file HTML
mockup at iPhone size. It bakes in the rules above so you get a
Post-Run-Drip-correct screen, not a generic one.

---

> Build a **single self-contained HTML file** — a mobile app screen mockup
> at iPhone width (390px, centered on a neutral backdrop). It's a running
> **interval workout detail** screen for a fitness app. Follow this design
> system exactly; restraint is the whole point.
>
> **Design system — "Post Run Drip":** warm paper background `#F5F3F0`,
> rich ink text `#1A1815`, secondary gray `#6B6560`, light gray `#9B9590`,
> thin rules `#E8E4E0`. **Exactly one accent color, coral `#D4592A`,** used
> like punctuation — at most one coral element per visual cluster. Fonts:
> Crimson Pro (serif) for the big headline; PT Serif for italic dek and
> observation lines; a monospace font for all eyebrows, labels, and
> numbers (load from Google Fonts: Crimson Pro, PT Serif, and a mono like
> IBM Plex Mono). All numerals use `tabular-nums`. Flat — no drop shadows
> except a faint card edge. 8px spacing grid.
>
> **Screen content, top to bottom:**
> 1. A thin mono header rail: `WORKOUT · INTERVAL SESSION` left,
>    `FIG. 23` right — uppercase, letter-spacing 0.14em, gray.
> 2. Title block: mono gray eyebrow `TUESDAY · LT SESSION`; then a large
>    Crimson Pro headline `2K · 1K · 1K · 2K · 1K · 1K`; then a PT Serif
>    *italic* gray dek `2 × (2K + 2×1K) threshold rehearsal · 5.0 mi work`.
> 3. A 4-column stat strip with hairline dividers, mono numerals:
>    **AVG WORK `5:13` /mi** (this value in coral), **WORK `5.0` mi**,
>    **AVG HR `169` bpm**, **SPREAD `10` s**.
> 4. Section labeled (mono eyebrow) `REP BY REP` on the left,
>    `6 REPS · WORK` on the right. Below it, six vertical bars, one per
>    rep, where bar height represents pace (taller = faster). Splits in
>    order: 2K=6:34, 1K=3:12, 1K=3:12, 2K=6:37, 1K=3:12, 1K=3:14. Draw a
>    horizontal **dashed** gray reference line at the session average with
>    a small `AVG` tag. **Color each bar by its pace using a continuous
>    spectrum** — the slowest rep green, the fastest rep plum-purple,
>    interpolating through these ordered stops (slow→fast):
>    `#6B8068, #8C9A57, #B0A048, #C4873A, #D4592A, #C0492E, #B23A2E,
>    #9E3144, #7E3A6B, #6B4A8A`. Map each rep's pace to a position on
>    that ramp (slowest split = green end, fastest split = plum end).
>    Keep a small legend above the chart drawn as a smooth horizontal
>    gradient swatch of that ramp, labeled `PACE · SLOW → FAST`.
> 5. A rep table with columns `REP · SPLIT · REST`, hairline row
>    dividers, mono tabular numbers, no zebra striping. Each row has a
>    small square chip on the left **colored by that rep's pace using the
>    same spectrum as the chart** (so the table chips echo the bar
>    colors). Rows:
>    `2K  6:34  2:05` / `1K  3:12  1:12` / `1K  3:12  1:09` /
>    `2K  6:37  2:20` / `1K  3:12  1:07` / `1K  3:14  0:04`.
> 6. One PT Serif *italic* observation line in ink, citing a real number,
>    purely observational — no advice, no "you should": *"Ten seconds
>    covered all six reps — the 2K floats sit right on the 1K efforts.
>    Even from the gun, steady at the line."*
> 7. Generous bottom padding.
>
> **Hard rules:** the chart + table chips use the PACE SPECTRUM (color
> encodes pace) — that's a data surface, not decoration. Coral is NOT
> hand-placed there; it only appears where a rep's pace lands at the HMP
> point of the ramp. In the *chrome* layer (stat strip, eyebrows), keep
> one coral accent per cluster — the `AVG WORK` value. Eyebrows and
> labels are mono uppercase, never serif; no emoji, no icon glyphs;
> never use an em-dash as a placeholder for a missing value (if a stat
> were missing, show a small gray "no data" note). Make it feel like a
> restrained editorial running magazine, not a dashboard.

---
