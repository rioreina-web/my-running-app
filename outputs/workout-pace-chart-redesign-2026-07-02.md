# Rep-by-rep pace chart — redesign spec (2026-07-02)

**Surface:** Workout detail → "Rep by rep" chart.
**Design (JSX):** `design-system/ui_kits/ios_app/WorkoutDetailScreen.jsx`
**iOS code:** `RunningLog/Workouts/WorkoutDetailPlate23.swift`

## Problem

The current chart double-encodes pace as **bar height** and **bar color**,
but the two disagree: bars render in muted mauve/purple while the legend is
a green→blue rainbow. The result is unreadable at a glance, and it violates
Post Run Drip's "one coral accent" rule. There are no pace numbers on the
bars, so color must be decoded against a legend that doesn't visually match.

## Decision

Replace the rainbow with a **single-hue coral intensity ramp on an absolute,
zone-anchored scale.** One coral shade per pace zone, fixed app-wide: the
same pace is the same shade on every screen. Darker = faster.

Color answers *"what zone?"*; the on-bar number answers *"exactly how fast?"*

### Why absolute (not per-workout relative)

- **Same pace = same shade, everywhere.** A 5:12 rep looks identical in this
  chart, in history overlays, and in cycle comparisons.
- **Execution quality becomes visible.** A clean session reads as a uniform
  band of one shade ("locked in"). Any rep that breaks zone pops by shade —
  a surge into 10K goes darker, a fade to HMP goes lighter.
- **Colorblind-safe.** The ramp varies by *lightness*, not hue, so it holds
  up under all common color-vision deficiencies.

Accepted tradeoff: reps in the same zone look identical even when a few
seconds apart (5:12 and 5:18 are both "LT"). The on-bar pace number carries
that precision on purpose — the color deliberately doesn't.

## Zone → shade ladder

One shade per zone, slow→fast = light→dark, hue held ~coral (`--coral`
`#D4592A` is the anchor). Ordered by the 10-zone taxonomy.

| Zone | Shade (hex) | Notes |
|---|---|---|
| Easy | `#F4C4A8` | lightest |
| Moderate | `#F1B497` | |
| Steady | `#EDA485` | |
| MP | `#E89373` | |
| HMP | `#E28160` | |
| LT | `#D96A42` | ≈ base `--coral` region |
| 10K | `#C9542A` | |
| 5K | `#B84420` | = `--coral-deep` |
| 3K | `#A2381A` | |
| Mile | `#8B2F14` | darkest |

These are the proposed anchors. Tune against real device rendering on warm
paper, but keep even lightness steps and a single hue. Add these as named
tokens in `design-system/colors_and_type.css` (e.g. `--pace-lt`, `--pace-10k`)
and mirror in `DesignSystem.swift` so JSX and Swift stay in sync.

## Shade assignment

A rep's shade is chosen by **which zone its pace falls into** — not by a
per-second gradient. Classification must read from the same pace table the
rest of the app uses:

- Source: `derivePaceTableFromGoal` (`web/src/components/coach/workout-helpers.ts`)
  / `PaceCalculator.swift` on iOS.
- Anchor priority: `confirmed_races` first, goal time as fallback (per the
  race-anchor rule). Do **not** hardcode boundaries in the chart.
- Aerobic zones (Easy/Moderate/Steady/Long) are ±5% ranges; race-pace zones
  (MP/HMP/LT/10K/5K/3K/Mile) are exact single targets. A rep classifies into
  the zone whose band contains its pace; for exact race-pace targets, use the
  midpoints between adjacent targets as boundaries.

## Bar anatomy & labels

- **Bars grow up from a baseline; taller = faster.** Height and shade both
  encode speed and now agree with each other.
- **Pace label above every bar** (mono, `--ink`), sitting on paper — never
  inside the bar. This keeps text contrast off the mid-tone fills entirely,
  so no WCAG contrast problem.
- **Zone tag** (e.g. `10K`, `HMP`) appears above a rep *only when it differs
  from the session's primary zone.* On-target reps stay clean.
- **Dashed coral line = session average**, labeled `AVG m:ss` at the right.
- **Rep number** below the baseline in `--ink-3`.

## Legend

Show **only the zones present in the current workout**, left→right
slow→fast, each as: swatch + zone label + the pace boundary it represents.
Caption: *"Shade = pace zone, fixed everywhere in the app."* Do not render
the full 10-zone ladder in-chart — a single session spans 1–3 adjacent zones.

## Empty state

No reps / no lap data uses `EmptyStateView` (eyebrow + plain-prose nudge +
optional CTA). **No em-dash placeholders** (hard rule #8).

## Out of scope / follow-ups

- The `HEAT-ADJ`, `ELEV`, `MI/KM` toggles above the chart are unchanged here.
- Define the named shade tokens before implementation so both platforms
  reference them rather than inline hex.
