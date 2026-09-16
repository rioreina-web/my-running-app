# Post Run Drip — Design System (Portable Copy)

> *Restraint as foundation, intensity as accent.*

**This is a self-contained second copy of the app's design, snapshotted
2026-07-13.** The canonical source of truth remains `design-system/`
(README + `colors_and_type.css` + `ui_kits/ios_app/`). This copy exists so
the full design can travel in one markdown file — and it folds in the
decisions made *after* the design-system README was written: the
three-palette rule (2026-07-03), the ten-stop blue pace ramp, the 4-tab
beta IA, and the beta screen designs from
`beta-design-overhaul-plan-2026-07-13.md` /
`beta-mockups-2026-07-13.html`. Where this doc and the README disagree,
this doc is newer.

---

## 1. What the product is

A running app for serious athletes — half **diary**, half **cockpit**.
The voice is editorial: *NYT Magazine* sports section, not a fitness
tracker. A runner's data should read like a story, with a coach's voice
running through it. The aesthetic is a *printed running log*: warm
paper, black ink, one coral accent used like punctuation.

Core product principle: **AI advises, never acts.** The human — coach or
athlete — owns every decision.

---

## 2. Voice — "editorial diary, coach in the room"

The voice is the heart of the product. Get this wrong and the visuals
can't save it.

**Tone.** Spare, declarative, no throat-clearing. "Tempo, 8 miles." not
"Today's workout: Tempo run of 8 miles." Coach voice is direct and
second-person: *"Consistent splits, not negative. Let the rhythm
settle."* Diary voice is first-person, past tense, in quotes: *"Felt
good through the warm-up — legs were heavy first mile but loosened
up."* Never cheerlead — no "Great job!", no emoji praise. Observation
over congratulation.

**Casing & punctuation.**

- Section labels: ALL CAPS, tracked, monospaced. `TUESDAY`, `FROM YOUR COACH`.
- Body & display: sentence case. "Marathon block." "Pace, narrated."
- Period after standalone headlines: *"May 5th."*
- Middle dot `·` is the workhorse separator: `8.4 mi · 7:42 / mi · TIRED`.
  Never `|`, `—`, or `/` in those positions.
- En-dash for ranges: `6:24–6:56 / mi`. Em-dash for sentence breaks in
  diary/coach copy. Curly quotes in body copy.
- Lowercase paces and units: `7:42 / mi`, `47 days out`. Numerals always:
  `5 mi`, never "five miles."

**Pronouns.** "You / your" for the athlete in coach voice. First person
only inside quoted voice-log entries. No "we" — the app doesn't talk
about itself.

**Banned.** "AI-powered," "smart," "personalized," "engage," "unlock,"
"discover," "journey," "wellness," "vibes." No exclamation points
outside diary quotes. No emoji anywhere. No filler greetings — the
header is `TUESDAY` over `May 5th.`, never "Good morning, Alex."

**Empty states.** State the absence, then say what fills it: *"No runs
logged yet. When you do, your last entry lands here."* Italic,
secondary color, no illustration. Rendered by the empty-state component
(eyebrow + plain-prose nudge + optional CTA) — **never an em-dash
placeholder** (hard rule).

**Phrasings to lift verbatim.** *"How are you feeling?"* (daily
check-in). *"From your coach"* (eyebrow). *"Mark complete ↗"* (verb +
arrow, underlined coral). *"Not medical advice. If anything gets
sharper, see a clinician."* (quiet, italic, secondary).

**Coach/AI voice posture (The Read).** Feeling first, then workouts,
then mileage. Warm encouragement, never toxic positivity. Reads life
context (weather, sleep, work stress). Carries race anchors and goals
silently — never explains the math. Ends with 1–2 soft questions the
athlete can sit with. Never diagnoses, never prescribes rest, never
recommends stopping training.

---

## 3. Color

### The three-palette rule (2026-07-03) — the governing law

**Blue = pace. Warm = mood. Coral = alert. The three palettes never
share hues.** A "safe zone" band is neutral gray, never green (green is
mood-only). Coral is never a pace fill. A pace chip is never red or
green — pace does not carry judgment.

### Surfaces & ink

| Token | Hex | Use |
|---|---|---|
| `--paper` | `#F5F3F0` | page background — warm newsprint |
| `--paper-elevated` | `#FAFAF8` | warmer white card |
| `--card` | `#FFFFFF` | clean white card |
| `--paper-deep` | `#E8E4DF` | calendar / inset wells |
| `--rule` | `#E8E4E0` | hairline editorial rule |
| `--ink` | `#1A1815` | rich warm black — display & body |
| `--ink-2` | `#6B6560` | warm gray — meta, labels |
| `--ink-3` | `#9B9590` | light warm gray — captions, disabled |

Three text tones, no more.

### Coral — the only accent

| Token | Hex | Use |
|---|---|---|
| `--coral` | `#D4592A` | primary accent |
| `--coral-light` | `#E8764A` | hover lift on dark |
| `--coral-deep` | `#B84420` | pressed state |
| `--coral-wash` | `rgba(212,89,42,0.12)` | capsule fill, tint |

Coral appears as: active-section eyebrow, active-tab dot, "Mark
complete" underline, record button, niggle chips/dots, inline links.
**One coral element per visual cluster, maximum.** If two compete, drop
one to ink-2. Coral is a punctuation mark, not a paint.

### Pace — the ten-stop blue depth ramp

Single hue, darker = faster. Source of truth:
`RunningLog/Workouts/PaceSpectrum.swift`. Token family `paceFast` /
`--pace-fast` (renamed out of the mood namespace from the old
`--mood-speed` plum, which is retired for pace use).

| Zone | Hex | | Zone | Hex |
|---|---|---|---|---|
| Easy | `#93B9D6` | | LT | `#27549B` |
| Moderate | `#74A8CC` | | 10K | `#20448B` |
| Steady | `#578FC0` | | 5K | `#1A3679` |
| MP | `#3F7CB5` | | 3K | `#142964` |
| HMP | `#2F66A8` | | Mile | `#0E1D4E` |

Text-on-light variant for the pale Easy end: `easyText #5E93BE`. The
chip's mono label always carries zone identity — color is
reinforcement, never the only signal. Rationale: pace is one ordered
dimension; a single-hue ramp reads instantly, survives grayscale and
colorblindness, and stays emotionally neutral (an easy run at 9:30 is
correct, not "bad" — a green-to-red ramp would moralize speed and
collide with mood/alert semantics).

### Mood — warm, low-chroma, pill-only

| Mood | Hex |
|---|---|
| energized | `#2D8A4E` |
| positive | `#4A9E6B` |
| neutral | `#9B9590` |
| tired | `#C4873A` |
| struggling | `#C45A3A` |
| injured | `#B83A4A` |

Always a tracked uppercase pill at 12% wash, never a full fill. Mood is
stored as a text label (this closed vocabulary), not a number.

---

## 4. Typography — three families, sharply assigned

| Family | Role |
|---|---|
| **Crimson Pro** (variable serif) | display headlines, button labels: "May 5th.", "Marathon block." |
| **PT Serif** (+ italic, bold) | body copy, italic diary quotes |
| **Monospace** (`SF Mono` / `ui-monospace`) | every uppercase label, eyebrow, stat, plate strip; `tabular-nums` |

Size scale: display 40 / 32 / 24 / 20 px · body 15 / 13 px · meta 11 /
10 px. Tracking: labels `+0.12em`, captions `+0.10em`, plate strip
`+0.14em`. **Type carries the brand** — if only the type were right,
the brand would still read.

---

## 5. Layout, surfaces, motion

- **8pt grid:** 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 56. 24px screen
  padding on iOS; 24px vertical section rhythm.
- **Radii:** pills 999 · cards 12 · buttons 10 · inputs 8 · tight 4.
  Nothing square; nothing rounder than 12 except pills.
- **Cards:** white, 12px radius, 16px padding (24 on hero),
  `0 2px 8px rgba(0,0,0,0.06)` shadow, no border, never card-in-card.
- **Editorial rule** (`line · 3px dot · line`) is the canonical section
  break — a typesetting mark, not an `<hr>`.
- **No gradients, no images-as-background, no textures, no glass/blur.**
  Ink on paper. The only transparency in the system is the 12% wash
  behind pills.
- **Motion:** easeInOut 300ms default; 150ms pill states; 1800ms pulse
  on the record button (the only bounce). Fade-only screen transitions.
- **Borders:** hairlines `1px #E8E4E0`; `1.5px coral` on selected/active;
  the 2px coral-at-50% left bar is *only* for coach blockquotes.
- **Focus:** 2px coral outline, 2px offset. Never a glow.
- **Icons:** stroked, never filled (SF Symbols on iOS; Lucide on web).
  Ink-2 default, coral on the one active element. The only filled glyph
  in the system is the active-tab dot. No emoji, no icon backgrounds.
  Permitted unicode: `·`, `↗`, `→`.

### Named primitives

`Eyebrow` · `PlateStrip` (mono top strip: title left, figure/date
right) · `Section` · editorial rule · `MoodPill` / `MoodRadio` ·
stat card · zone chip (pace-ramp fill + mono label) · niggle chip
(coral outline pill, verbatim body-part) · conditions readout (mono
caption: `74° · DP 68° · HEAT ADJ −9S · +310 FT`) · empty-state
component · `DripTabBar` (dot + uppercase mono label, no icons;
active = filled coral dot).

---

## 6. Information architecture — the beta 4-tab IA

**`LOG · TRENDS · TRAIN · COACH`** — input → overview → detail →
synthesis. (Supersedes the README's 5-tab `LOG · TRAIN · TRENDS ·
COACH · RUNS` and the shipped 7-tab evaluation sprawl.) Plan is not a
tab: it folds into Train's calendar. `activePlan == nil` is a
first-class state — the product is journey-centric, not plan-centric.

The loop every screen serves: athlete speaks (Log) → data lands
(HealthKit → Train) → machine correlates qual × quant (Trends
PATTERNS) → AI narrates and asks (Coach) → human decides, plan adjusts
(Train calendar) → next run tests it.

### Log — the front door
Voice-first: record button + voice/manual toggle on top, the 6-month
training journal scrolling below. Workouts auto-populate from
HealthKit; memos are transcribed; niggle chips and mood pills render
inline on entries. Pure record — no AI annotation inline.

### Trends — the 5-second overview
THIS WEEK strip (effort / fitness / signal cards) → range segmenter →
stacked lanes: weekly volume colored by pace depth, mood dots beneath,
niggle dots in coral → **PATTERNS**: 1–3 AI-surfaced correlations
between the qualitative lane (mood, niggles, memo language) and the
quantitative lanes (workout type, load, heat, climb). Every pattern
cites specific numbers, states confidence, and ends in a soft italic
question. Race prediction always as **range + confidence**
(`3:22 – 3:29 · midpoint 3:25 · MODERATE CONFIDENCE`) — never a
seconds-precision point. Ask bar at bottom hands off to Coach.

### Train — the detail surface, three modes
- **CURRENT** — today's session (plan-aware, pace-zone chip + range)
  above the week as day-rows. Every completed run row carries its
  conditions readout (temp · dewpoint · heat-adj · climb). Week footer
  aggregates: miles, ft climb, hot-run count, heat-adjusted average.
  One quiet recovery observation line (sleep + quoted fatigue
  mentions) — observed, never advised.
- **CALENDAR** — month/block grid: completed days filled with
  pace-depth blue, coach-planned days dashed-outlined, niggle dots
  coral, today ringed coral. Phase tag bar (e.g. `BUILD 2 · 38 → 46
  MPW`). Coach's upcoming week summarized beneath, with the coach's
  reason quotes verbatim. Join Coach's Plan / Import Plan are
  first-class actions here.
- **HISTORY** — Workouts & Reps archive, 80/20 easy-hard split,
  volume × pace histogram, felt-vs-planned, cycle comparisons.

### Coach — The Read
Editorial narrative on demand: plate strip → dateline → 32pt headline →
2–4 observation sentences → italic soft questions → signature →
sources/confidence. Feeling before data. When a human coach is
attached, the Read acknowledges the coach's plan as context — AI
observes, coach decides. Athlete can ask for specific lenses ("how does
this block compare to last cycle?").

### Workout detail — one view, three acts
- **Act 1 (no scroll):** eyebrow (`TUESDAY · QUALITY`) → display date
  with coral period → italic source line → 4-stat strip (distance /
  duration / pace / HR) → **conditions plate** on paper-deep: temp ·
  dewpoint · heat-adj delta · climb. Conditions frame the run before
  any chart.
- **Act 2 (the story):** THE READ paragraph (feeling-first, weaves the
  weather in, never explains math) with mood pill + verbatim memo
  quote → **Workouts & Reps** as the hero table: rep rows with
  pace-ramp zone chips, columns PACE / TARGET / GAP / HR.
- **Act 3 (collapsed):** HR zones, pace trace, cadence, elevation,
  comparison, route as collapsible rows — eyebrow + one-line mono
  summary + chevron. Default-expand only the section most relevant to
  the workout type.

---

## 7. Content-safety and honesty rules (bind every surface)

1. Predictions ship as **range + confidence**, never a point estimate.
2. **Niggles**: closed ~30-entry body-part vocabulary; quote the
   athlete verbatim; surface, never interpret — no diagnoses, no
   "rest/ice," no severity scoring by the system.
3. AI never recommends stopping training or makes medical claims.
4. `data_depth` (0–3) gates the editorial register: plain UI text until
   ~7 days of data; full pull-quote editorial only at 21+ days or a
   set goal. Every pull-quote at depth 2+ cites at least one number.
5. Cross-training displays in the journal but stays out of
   running-fitness math (ACWR, prediction).
6. Race anchor beats goal time for pace zones — goal is direction,
   race is reality.

---

## 8. Logo

"post run drip" in a bold geometric sans (the only non-system typeface),
three lines, a literal drip hanging from the "p" of "drip." Always on
deep ink/black. Never coral, never one line.

---

*— restraint as foundation, intensity as accent*
