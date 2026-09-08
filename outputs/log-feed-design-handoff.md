# Design handoff — Post Run Drip · Log (main feed)

Redesign the **Log** screen: a runner's home feed. Half training diary, half
cockpit. Editorial running-magazine feel — warm paper, black ink, one coral
accent used like punctuation. Think *NYT Magazine* sports page, not a fitness
tracker.

---

## Brand system (use exactly)

**Fonts**
- Display / headlines / day names: **Crimson Pro** (serif, weight 600–700)
- Body + italic quotes: **PT Serif**
- All uppercase labels, meta lines, and numbers: **monospace** (SF Mono /
  ui-monospace), letter-spacing ~0.12em, tabular numerals

**Color** — warm paper, one accent. Three palettes that never share hues:
blue = pace, warm = mood, coral = alert/punctuation.

| Role | Hex |
|---|---|
| Paper (page) | `#F5F3F0` |
| Card | `#FFFFFF` |
| Elevated | `#FAFAF8` |
| Ink (text) | `#1A1815` |
| Ink-2 (meta) | `#6B6560` |
| Ink-3 (caption) | `#9B9590` |
| Hairline | `#E8E4E0` |
| Coral (accent) | `#D4592A` |
| Mood: energized/positive | `#2D8A4E` / `#4A9E6B` |
| Mood: neutral/tired | `#9B9590` / `#C4873A` |
| Mood: struggling/injured | `#C45A3A` / `#B83A4A` |
| Pace ramp (easy→hard) | `#93B9D6` · `#578FC0` · `#27549B` · `#1A3679` · `#0E1D4E` |

**Rules**
- **Coral appears once per visual cluster, max.** Never a large fill.
- "Within range / good" states are **neutral ink, never green.** Green is
  mood-only. Coral is the only alert.
- Section breaks = an **editorial rule**: `thin line · 3px dot · thin line`.
  Everything else is a 1px hairline. No `<hr>`.
- Cards: white, 12px radius, soft shadow `0 2px 8px rgba(0,0,0,0.06)`, 16px
  padding. No card-inside-card. No gradients, no blur, no emoji.
- **Plate strip** at the very top: a mono, tracked, uppercase bar reading
  `RUNNING LOG — LOG · V1 JOURNAL` (left) and `60 ENTRIES / 07.2026` (right).
- Voice: spare, declarative, second person. Coach notes get a `FROM YOUR
  COACH` eyebrow and a coral left-bar. Empty states = small uppercase eyebrow
  + one plain-prose line (never a dash placeholder).

---

## What's wrong with the current version

1. The feed sits in a narrow **centered** column, so it floats to the right
   with a big empty gutter on the left. Unbalanced.
2. Each entry is very tall and airy — only ~2 fit on screen — and the page
   opens straight into individual runs with **no at-a-glance training state**
   (no weekly mileage, load, mood, or next workout). Reads as mostly empty.

---

## Target layout

### Desktop (≥1024px) — left-anchored, two columns

```
┌ PLATE STRIP  (full width) ─────────────────────────────────────────┐
│ RUNNING LOG — LOG · V1 JOURNAL                       60 ENTRIES · 07.2026 │
├───────────────────────────────────────┬────────────────────────────┤
│ FEED  (reading measure, ~60ch)         │ OVERVIEW RAIL (~300px, sticky) │
│                                        │                            │
│ YOUR TRAINING                          │ THIS WEEK                  │
│ The log.                               │  38 / 40 mi   6 runs       │
│                                        │  7:24 /mi avg  ▁▂▃▅▄▆ spark │
│ ── JULY 2026 · 142 MI · 18 RUNS ──    │ ── rule ──                 │
│                                        │ NEXT UP                    │
│ Monday                        VOICE    │  Boston build · TUE MP 7mi │
│ JUL 6 · TEMPO · 8.1 MI · 7:11/MI · POSITIVE │ ── rule ──            │
│ "Hit splits within two seconds…"       │ MOOD · 7 DAYS  ● ● ● ● ● ● ●│
│ ▌ FROM YOUR COACH  Tempo locked in…    │ ── rule ──                 │
│                                        │ NIGGLES  1 active →        │
│ Sunday                        VOICE    │                            │
│ …                                      │                            │
└───────────────────────────────────────┴────────────────────────────┘
```

- **Anchor the block to the left** of the content area (max width ~1040px).
  The feed is the left column at a comfortable reading measure; the rail is a
  fixed ~300px sticky column. 40px gap. No floating dead space.

### Narrow (<1024px)
Rail collapses into a horizontal **stats strip** (2×2 tiles) directly under the
header; feed below. Never show an empty left gutter.

---

## Overview rail — 4 modules (this is the missing "data")

Each is an uppercase mono eyebrow + content, separated by editorial rules.
All numbers mono/tabular.

1. **THIS WEEK** — weekly mileage vs target (e.g. `38 / 40 mi` — neutral ink;
   coral **only** if over target), run count, avg pace, and a small 7-day
   mileage sparkline (ink line, coral last dot).
2. **NEXT UP** — current plan name + next workout (`Boston build · TUE · MP 7
   mi`). If no plan: empty-state nudge — "No plan running. Your training still
   counts."
3. **MOOD · 7 DAYS** — a row of 7 dots in the week's mood hues. No labels.
4. **NIGGLES** — count of active body-mentions, links out. Coral only if >0.

---

## Feed rows — denser

- Row = a thin **mood-colored left rail** + content. Tighten vertical padding
  so ≥4 rows show above the fold.
- **Day name** in Crimson (e.g. *Monday*). Quality sessions (tempo, intervals,
  long, progression, race) get slightly more weight (thicker rail / larger
  day) so the eye finds them; easy/recovery stay quiet.
- **Meta line** in mono, uppercase, one line:
  `JUL 6 · TEMPO · 8.1 MI · 58:13 · 7:11/MI · POSITIVE`
  (mood folded in here as a colored word, not its own row).
- **Voice-log** shown as an italic PT Serif quote in curly quotes, clamped to
  ~2 lines collapsed.
- **Coach insight** collapsed to 1 line under a `FROM YOUR COACH` eyebrow +
  coral left-bar; full text on expand.
- A `VOICE ▸ 2:34` indicator (coral) marks voice entries; `LOGGED` / `CHECK-IN`
  for others.
- Month breaks are editorial rules that **carry a total**:
  `JULY 2026 · 142 MI · 18 RUNS`.

---

## Sample data (use for the mock)

```
Monday   · Jul 6 · Tempo · 8.1 mi · 58:13 · 7:11/mi · POSITIVE · voice 2:34
  "Hit splits within two seconds either way. Felt smooth through five, then
   the wind picked up on the back stretch. Calf was quiet today."
  FROM YOUR COACH — Tempo locked in — 7:11 average against 7:24 four weeks
   ago. You held the last two miles instead of forcing them.

Sunday   · Jul 5 · Long run · 16.0 mi · 2:04:30 · 7:47/mi · TIRED · voice 3:18
  "Long one. Heavy first three, then it loosened up — last four the strongest."

Friday   · Jul 3 · Recovery · 4.0 mi · 34:12 · 8:33/mi · NEUTRAL · text
  "Easy shakeout. Knee a touch warm first mile, settled by the second."

Rail · THIS WEEK: 38 / 40 mi · 6 runs · 7:24/mi avg
Rail · NEXT UP: Boston build · Tue · MP 7 mi
Rail · MOOD 7d: positive, tired, neutral, positive, positive, energized, tired
Rail · NIGGLES: 1 active (calf)
```

---

## Acceptance checks

- [ ] No empty left gutter at any width — content is left-anchored.
- [ ] Desktop above the fold shows header + all 4 rail modules + ≥4 feed rows.
- [ ] Weekly mileage, next workout, 7-day mood, niggle count all visible without
      scrolling on desktop.
- [ ] Within-range mileage is neutral ink (not green); coral appears at most
      once per cluster.
- [ ] Pace/effort uses the blue ramp; mood uses warm; they never share a hue.
- [ ] Empty states use eyebrow + one-line nudge, no dash placeholder.
```
