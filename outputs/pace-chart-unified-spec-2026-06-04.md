# Pace Chart Unified Spec

**Last updated:** 2026-06-04
**Status:** Section 1 (pace zone convention) is LOCKED. Sections 2-8
are draft / open for design. Once complete, becomes the source of
truth for the web + iOS pace chart cleanup work in Phase 2.
**Companion to:**
- `outputs/phase-2-race-anchoring-plan-2026-06-04.md`
- `outputs/maya-product-roadmap-2026-05-28.md`
- `outputs/maya-data-aware-journey-2026-05-28.md`

This doc defines the single canonical spec that both `web/src/app/(app)/pace-chart/`
and `RunningLog/Workouts/PaceChartView.swift` must follow. Today the
two surfaces drift from each other in band convention, zone count,
display structure, and editorial design. This spec ends the drift.

---

## 1. Pace zone convention — LOCKED 2026-06-04

The Post Run Drip pace zone taxonomy is **10 zones** total: 3 effort
zones expressed as ranges, plus 7 race-pace zones expressed as
single precise targets.

### The 10 zones

| Zone | Type | Definition |
|---|---|---|
| **Easy** | Effort range | 70% – 80% MP speed |
| **Moderate** | Effort range | 80% – 90% MP speed |
| **Steady** | Effort range | 90% – 100% MP speed (top exclusive) |
| **MP** | Race-pace single target | Exactly 100% MP speed (the anchor itself) |
| **HMP** | Race-pace single target | Half marathon race pace (race-equivalence) |
| **LT** | Race-pace single target | 1-hour race pace (interpolated 10K↔HM) |
| **10K** | Race-pace single target | 10K race pace (race-equivalence) |
| **5K** | Race-pace single target | 5K race pace (race-equivalence) |
| **3K** | Race-pace single target | 3K race pace (race-equivalence) |
| **Mile** | Race-pace single target | Mile race pace (race-equivalence) |

### Key principles

**Exclusive boundaries — no overlap, no gaps.** The %-MP-speed line
from 70% to 100% is divided into exactly three effort ranges:

```
  Easy           Moderate          Steady           MP
  70% — 80%      80% — 90%         90% — 100%       100%
  └──────────────┴─────────────────┴──────────────────●
  (range)        (range)           (range)         (single target)
```

A pace at exactly 80% MP speed is in **Moderate** (closed-bottom).
A pace at exactly 100% MP speed is in **MP** (Steady is open at top).
A pace at 99% MP speed is in **Steady**.

**Below 70% MP speed is not a workout zone.** It's recovery walking,
shake-out jog, cool-down, post-race shuffle. The pace chart doesn't
display anything below 70%.

**LongRun and Recovery are workout types, not pace zones.**
- Long run (`Long`) is a long-duration workout typically done at
  Easy or Moderate pace.
- Long run workout (`Long wo`) is a long run with embedded race-
  pace references (e.g. "last 6 miles steady" or "build to MP").
- Recovery is non-running activity (cross-train, walk, very slow
  jog) — captured in the journal as a separate entry type, not as
  a pace zone.

**Race-pace zones are single targets, not ranges.** MP, HMP, LT,
10K, 5K, 3K, Mile are each a precise pace derived from race-
equivalence math anchored on the athlete's race anchor (or goal
time as fallback). They aren't "ranges with a midpoint" — they're
the pace at which the athlete would race that distance.

### Maya's pace zones (race-anchored, Houston 3:28 → MP = 7:56/mi)

| Zone | Pace /mi |
|---|---|
| Easy | 9:55 – 11:20 |
| Moderate | 8:49 – 9:55 |
| Steady | 7:56 – 8:49 (touches MP at top) |
| MP | 7:56 |
| HMP | ~7:20 *(estimate; real value from race-equivalence)* |
| LT | ~7:00 *(estimate)* |
| 10K | ~6:43 *(estimate)* |
| 5K | ~6:14 *(estimate)* |
| 3K | ~5:59 *(estimate)* |
| Mile | ~5:35 *(estimate)* |

Estimates above are placeholders. Actual values come from
`equivalentRacePaceSecPerMile` once Maya's confirmed Houston race is
plugged in (Sub-task A makes this possible).

### Math implementation

**For the 3 effort zones, the range is computed as:**
```
fastPace = MP_speed / fastRatio   // top of zone (faster pace)
slowPace = MP_speed / slowRatio   // bottom of zone (slower pace)
```

Where:
- Easy: fastRatio = 0.80, slowRatio = 0.70
- Moderate: fastRatio = 0.90, slowRatio = 0.80
- Steady: fastRatio = 1.00, slowRatio = 0.90 (top is exclusive — see below)

`MP_speed` is in units of (1 / sec/mi). In practice, `MP_pace` is in
sec/mi, so `fastPace_sec_per_mile = MP_pace_sec_per_mile / fastRatio`.

**The "top exclusive" rule for Steady:** When *classifying* a workout's
pace into a zone, a pace of exactly MP belongs to **MP**, not Steady.
When *displaying* the Steady range to the athlete, the fast end is
shown as MP itself (or MP - 1 sec/mi to avoid visual collision). UI
convention: Steady range displays as e.g. "7:57 – 8:49" (fast end is
1 sec/mi slower than MP for readability).

**For race-pace zones:** Each is a single target computed from the
anchor race via the race-equivalence ratio table in
`workout-helpers.ts` and `_shared/paces.ts`. The math is shared; the
ratios are anchored at 10K = 1.00 (Riegel-style).

### Drops from current code

- **Recovery** (current ratio 0.65 / 0.70) — drop as a zone. It's
  not a training zone; it's a non-zone activity.
- **LongRun** (current ratio 0.80) — drop as a zone. It's a workout
  type, not a pace zone.

These are removed from `TRAINING_MP_SPEED_RATIO` and
`TRAINING_MP_SPEED_RANGE` in both `paces.ts` (server) and
`workout-helpers.ts` (web). Any caller that currently expects them
returns to using Easy / Moderate / Steady.

### What changes in code

- `_shared/paces.ts`: `TRAINING_MP_SPEED_RATIO` updates to:
  ```
  easy: 0.75,    // midpoint of 70-80
  moderate: 0.85, // midpoint of 80-90
  steady: 0.95,  // midpoint of 90-100
  ```
  (Note: midpoint kept for back-compat with single-pace callers; the
  full range is exposed via a new `TRAINING_MP_SPEED_RANGE` export.)
- `workout-helpers.ts`: same as above. Both files use identical
  values. Drop `recovery` and `longRun` from the ratio table.
- `TRAINING_MP_SPEED_RANGE` becomes the canonical structure for UI:
  ```
  easy: { fastRatio: 0.80, slowRatio: 0.70 }
  moderate: { fastRatio: 0.90, slowRatio: 0.80 }
  steady: { fastRatio: 1.00, slowRatio: 0.90 }
  ```
  Identical on both sides.
- The 12-zone `derivePaceTableFromGoal` return shape drops `recovery`
  and `longRun` keys — becomes 10-zone exactly.
- iOS `PaceCalculator.swift` needs the equivalent training-zone
  derivation (verify or add).

---

## 2. Where pace charts are today — audit

### Web: `web/src/app/(app)/pace-chart/`

- **Files:** `page.tsx` (server entry, 1.4 KB), `pace-chart-client.tsx`
  (client component, 29 KB / ~770 lines).
- **Anchor modes:** `current` (from fitness snapshot), `projected`
  (from training trajectory), `goal` (from user's stated goal),
  `custom` (athlete-entered race time).
- **Data sources:** `PaceProfile` (per-distance race paces with
  confidence), `FitnessSnapshot` (predicted times).
- **Display structure:** training zone ranges (uses
  `TRAINING_MP_SPEED_RANGE`) + race-pace single targets.
- **Drift from spec:** uses web's `TRAINING_MP_SPEED_RATIO`
  (0.95 / 0.85 / 0.80 / 0.75 / 0.65) — different from server. Has
  Recovery and LongRun as displayed zones.

### iOS: `RunningLog/Workouts/PaceChartView.swift` + `PaceChartViewModel.swift`

- **Sections:** Goal Race Section, Weather Adjustment Section, Race
  Paces Section, Training Paces Section, Info Section.
- **Anchor:** loads goal from athlete profile; loads engine zones
  separately.
- **Weather adjustment:** native feature, web doesn't have it.
- **Drift from spec:** likely uses different ratios from web AND
  server. Has weather adjustment that web lacks. Doesn't surface
  race anchor as first-class.

### Drift summary

- **Different ratios on web vs server.** Maya sees different easy
  paces on coach-portal vs. iOS app for the same goal.
- **iOS may have its own implementation.** Audit needed.
- **Different display structures.** iOS has 5 sections; web has 4
  anchor modes. No unified mental model.
- **Race anchor not surfaced anywhere.** Even after Sub-task A
  populates `confirmed_races`, neither chart displays the anchor as
  the basis.
- **Weather adjustment lives only on iOS.** Coach-portal users have
  no equivalent.

---

## 3. Mode / anchor model — DRAFT, needs design

*This section is a placeholder. Open design question for the next
working session.*

Proposed: Replace web's 4 anchor modes (`current` / `projected` /
`goal` / `custom`) with a single race-anchor-first model:

- **Default mode:** anchored on Maya's most recent qualifying race
  (`confirmed_races` after recency-weighting). Race name + date
  displayed.
- **Goal mode:** athlete taps to switch to "show me my goal paces"
  — anchored on `goal_time` instead.
- **Custom mode:** athlete enters a hypothetical race time. Useful
  for "what if I ran a 1:30 half?"
- **Projected mode:** drops out. The fitness snapshot prediction
  was the basis of "projected" mode but that's now subsumed by the
  fitness range tile on Trends; pace chart sticks to race-anchored
  reality, not predicted fitness.

iOS adopts the same model. No "engine zones" vs. "goal context" split.

*Open questions:*
- What does the mode switcher look like in the UI?
- Should the mode switcher be on both web and iOS or hidden behind
  a settings affordance?
- When the athlete has no race anchor, what's the default?
  (Probably: goal mode if goal is set; otherwise empty state nudging
  her to enter a race or set a goal.)

---

## 4. Race anchor as first-class — DRAFT

*Placeholder. Open design question.*

When the pace chart is open, the athlete should see, at a glance,
*what her zones are anchored on*. Something like:

```
PACE ZONES · v1
ANCHORED ON: Houston Marathon 3:28:14 · Jan 21 2026
```

Tap-to-change: opens race history, lets her switch anchor to a
different race or to goal time.

This is the editorial framing — *"these zones are real, computed
against an actual race you ran."* Not generic "based on goal time"
where the goal time is aspirational.

*Open questions:*
- How is the anchor displayed when there are multiple recent races?
  (e.g., Houston Jan + an October half marathon — which is the
  default anchor? Recency-weighted per Q20 decision.)
- What's the UX for switching the anchor?

---

## 5. Editorial design — DRAFT

*Placeholder. Open design question.*

Both surfaces should follow Post Run Drip — warm paper, editorial
typography, mono for labels, hairlines for dividers, plate strip at
top, coral as punctuation.

Web's current pace chart has *some* design language but isn't fully
editorial. iOS uses Drip color tokens and SF Symbols but drifts from
the visual spec (mono caption renders in serif instead of mono per
the design-parity-audit-2026-05-20 doc).

Specific design decisions to make:
- Pace zone display: tile cards? Range-bar visualization?
  Hairline-separated list? Different for effort zones vs. race-pace
  zones.
- How to show the race anchor prominently.
- Confidence indicators (where they apply): consistent visual
  treatment.
- Edit affordance (athlete tweaks anchor or per-distance pace).

---

## 6. Confidence indicators — DRAFT

*Placeholder. Open design question.*

Today: per-distance confidence labels on web (HIGH / MEDIUM / LOW).
iOS shows different framing. Should unify.

Confidence applies to race-pace zones (each has a separate
`*_pace_confidence` field on `athlete_pace_profiles`) and to the
race anchor itself (recent race = high confidence; goal-anchored =
low confidence by definition; 2-year-old race = lower confidence
than recent).

Per CLAUDE.md hard rule #7: predictions ship with range + confidence,
never a single point. The pace chart's race-pace zones are *single
targets* (per section 1), but the confidence is still surfaced.

*Open questions:*
- Confidence at the anchor level vs. per-zone — which is shown?
- Visual treatment (color tier? mono label? icon?).

---

## 7. Weather adjustment — DRAFT

*Placeholder. Open design question.*

iOS has a Weather Adjustment Section that adjusts displayed paces
based on heat / humidity. Web doesn't.

Coach call needed:
- Ship weather adjustment on both?
- Drop it from iOS to match web (simpler, less surface)?
- Keep only on iOS and add to web?

If kept: should be cross-platform identical math. Probably reads
from the workout's actual weather data (per the journey doc's life-
context capture).

---

## 8. Implementation notes — per platform

*Placeholder. Filled in as design lands.*

### Web implementation notes
- Server entry: `web/src/app/(app)/pace-chart/page.tsx`
- Client: `pace-chart-client.tsx` (29 KB / ~770 lines)
- Reads from: `athlete_pace_profiles`, `fitness_snapshots`,
  `user_goals`
- Will need to also read: `athlete_state.confirmed_races` (Sub-task A)

### iOS implementation notes
- View: `RunningLog/Workouts/PaceChartView.swift`
- ViewModel: `PaceChartViewModel.swift`
- Uses `PaceCalculator.swift` for math
- Needs verification: does iOS use the same band convention as
  server post-fix? If not, add equivalent math.

---

## Open questions

1. **Section 2-7 designs.** Mode/anchor model, race anchor surfacing,
   editorial design, confidence indicators, weather adjustment.
   Working through in next session.
2. **What does "100% top exclusive" actually look like in code?** Use
   `< 1.0` ratio in classification logic? Or compare against
   `Math.abs(ratio - 1.0) < 0.001` for floating-point safety? Engineering
   detail to lock during implementation.
3. **What happens to existing data with workouts classified as
   `recovery` or `longRun` pace zone today?** Migration question — do
   we re-classify, or just stop using the values going forward?

---

## Sequence relative to Phase 2

- **A. Fix TODO in athlete-state.ts** — done 2026-06-04.
- **B. Pace chart cleanup** — this spec.
  - Section 1: LOCKED 2026-06-04.
  - Sections 2-8: design + implementation in the ~2 weeks added to
    Phase 2 timeline.
  - Server + web ratio updates ship early (paired with Section 1's
    code changes).
- **C. Wire confirmed_races into paceTableFromProfile** — unblocked,
  not dependent on the rest of the spec. Can run in parallel.
- **D. Wire confirmed_races into fitness-predictor** — unblocked.
- **E. Race-entry UX** — moved to Phase 4.
- **F. Race-aware coachable-moment rule** — unblocked.
- **G. Eval cassette coverage** — runs alongside D.
- **H. iOS sync check** — folds into Section 8 of this spec.

---

## How to use this doc

- **Section 1 is locked.** Web, server, and iOS pace zone math must
  match this exactly. Any deviation is a bug.
- **Sections 2-8 are open design.** Don't ship code that affects
  them until each section is locked.
- **Implementation order:** Section 1 code changes first (small,
  isolated). Sections 2-8 designed before any UI work.
