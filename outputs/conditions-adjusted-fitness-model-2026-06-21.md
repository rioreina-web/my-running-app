# Conditions-Adjusted Fitness Model — "True Fitness Through the Elements"

**Date:** 2026-06-21
**Status:** Proposed (design)
**Owner:** TBD
**Related:** `supabase/functions/_shared/fitnessSignal.ts` (current signal),
`supabase/functions/_shared/pace-grade-adjustment.ts` (grade, new),
`supabase/functions/_shared/pace-heat-adjustment.ts` (heat, exists),
`outputs/grade-adjusted-pace-plan-2026-06-21.md`,
`outputs/fitness-signal-pace-at-hr-2026-06-15.md`

---

## 1. Goal in one paragraph

Today's fitness signal reads **raw pace ÷ heart rate** ("same pace, lower HR
over weeks = fitter"). Heat and hills corrupt that read: they slow pace **and**
raise HR on the same effort, so a hot or hilly session shows up as a fitness
*dip* that isn't real. We want a signal that reflects **true fitness** — the
athlete's underlying engine — by reading every session *through* the conditions
it was run in, so the trend tracks the body, not the weather or the terrain.

## 2. Decisions locked (2026-06-21)

1. **Pace side: adjust.** Feed the **conditions-adjusted pace** (grade + heat,
   from `combineConditions`) into the efficiency calculation instead of raw pace.
2. **HR side: do NOT model-correct it.** Heat/grade also inflate HR, but
   HR-vs-conditions models are noisy and personal — correcting them invites
   false precision. Instead, **down-weight (and at the extreme, exclude)
   sessions run in hard conditions**, so they can't distort the trend.
3. **Output: a conditions-normalized trend + race prediction.** Keep the
   direction / window / confidence shape (no single "fitness number" — honors
   hard rule #7). The race-equivalent time stays a range + confidence, anchored
   on `confirmed_races`.

## 3. Why the current signal is wrong in conditions

`EF = speed / HR`. On a hot or hilly session, relative to neutral:

| | Effect on EF | Net read |
|---|---|---|
| Pace | slower → speed ↓ → EF ↓ | "less fit" |
| Heart rate | higher → HR ↑ → EF ↓ | "less fit" |

So conditions push EF down from **both** sides. Adjusting only pace lifts the
numerator back but leaves the inflated denominator — which is exactly why we
also down-weight, rather than pretending a pace fix is the whole story.

## 4. The model

### 4.1 Fix the pace side (numerator)
For each work/aerobic bout, replace raw `paceSecPerMile` with the
**conditions-adjusted** pace:

```
adjustedSpeed = combineConditions(rawPace, bout.avgGradePct, sessionHeatPct).speed
```

- Grade per bout from the per-second `grade_smooth` stream (Phase 2 of the grade
  plan) or the lap approximation (Phase 1).
- `sessionHeatPct` from `heat_adjustment_pct(temp_f, dew_point_f)` — already
  computed and stored per lap.
- Bouts then pool into the same easy / threshold / interval buckets as today.

### 4.2 Down-weight the HR contamination (denominator)
Instead of correcting HR, weight each bout's contribution to the pooled EF by a
**conditions-cleanliness weight** `w ∈ [0,1]`:

```
w = w_heat(heat_category) × w_grade(|avgGradePct|)
```

- `w_heat`: 1.0 ideal → ~0.8 warm → ~0.5 hot → ~0.25 very_hot → **0 dangerous**
  (dangerous-heat sessions never count toward a fitness verdict).
- `w_grade`: 1.0 on flat, tapering as average |grade| rises (e.g. → ~0.5 by
  ±4%, → ~0 beyond ±8%), because the steeper the bout, the more the HR side is
  inflated and the less trustworthy the EF.
- Pools accumulate `Σ w·seconds`, `Σ w·hr·seconds`, etc., so clean sessions
  dominate the trend and hard-condition sessions nudge it at most.

Net effect: a hot/hilly week can't manufacture a fake fitness drop. The trend is
built mostly from comparable, low-distortion efforts — the honest backbone.

### 4.3 Output (unchanged shape, conditions-normalized content)
Reuse the existing `EfficiencyTrend` / `FitnessSignal` structures:

- Direction (improving / flat / declining) over a real window, with
  sample-based confidence — now computed on conditions-adjusted, weighted data.
- **Confidence gets a new input: condition coverage.** If the recent window is
  mostly hard-condition (heavily down-weighted) sessions, effective sample size
  is low → confidence drops, and the verdict can say so honestly ("thin clean
  data — mostly hot runs lately").
- The race-equivalent prediction stays a **range + confidence** anchored on
  `confirmed_races`, fed by the conditions-adjusted fitness — never a point time.

## 5. Why not correct HR directly (recording the rationale)
HR response to heat (cardiac drift, dehydration) and to grade is real but
**individual, time-varying, and confounded** (sleep, caffeine, stress, fitness
itself). A generic "subtract N bpm per °F dew point" would add a noisy guess on
top of a measured value and could *create* trends. Down-weighting is the
conservative, honest move: when a session's HR is untrustworthy, we trust it
*less*, we don't invent a correction. (Optional, non-blocking: store an
*estimated* HR-inflation flag for display transparency only — never fed into
the math.)

## 6. Where it lives in code

- **`fitnessSignal.ts`** — extend `SessionInput`/bout handling to carry per-bout
  `gradePct` + session `heatPct` + `heatCategory`; apply `combineConditions` to
  the speed and the weight `w` in `addBouts` / the pools. The public
  `FitnessSignal` shape is unchanged (drop-in for the Read).
- **`pace-grade-adjustment.ts`** — already provides `gradeFactor` /
  `combineConditions`. Add the `w_grade` / `w_heat` weight helpers here (or a
  small sibling `conditions-weight.ts`) so they're unit-testable and shared.
- **`athlete-state.ts`** — when building `fitnessSessions`, attach the
  conditions already sitting on `running_workout_laps` (`temp_f`, `dew_point_f`,
  `heat_category`, grade) so `computeFitnessSignal` receives them.
- **No new table.** Everything composes from columns already on
  `running_workout_laps` (heat) + the grade columns from the grade plan.

## 7. Honesty & guardrails (hard rules)

- **Range + confidence, never a point** (#7): output stays directional; race
  equivalence stays a range.
- **Degrade gracefully:** no HR → bout can't feed EF (already true); no
  weather → `heatPct = 0`, weight from grade only; no elevation → grade
  weight = 1. Treadmill / manual runs simply have neutral conditions.
- **Descriptive, not prescriptive** (#2): the verdict observes ("threshold
  fitness trending up, and that's *after* normalizing for a hot block"), never
  diagnoses or prescribes.

## 8. Phasing

**Phase A — pace-side normalization (ship first)**
1. Wire `combineConditions` into `fitnessSignal.ts` (heat already available;
   grade via Phase 1 lap-approx). Existing tests stay green.
2. Surface "normalized for conditions" in the Read's fitness sentence.

**Phase B — session weighting**
3. Add `w_heat` / `w_grade`, weighted pools, condition-coverage confidence.
4. Calibrate weights (see §9).

**Phase C — grade accuracy + race prediction**
5. Per-second grade (grade plan Phase 2) feeds bout grades.
6. Conditions-adjusted fitness flows into the race-time range.

## 9. Validation / calibration cases

- **Hot-block regression:** a stretch of hot/humid easy runs must NOT register
  as a fitness decline (the original bug). After normalization + weighting, the
  trend should hold flat or follow the clean sessions.
- **Cap 10K (Austin, 2026-04-12):** ~327 ft climb, 70°F/69.4°F dew. As a single
  data point it should read at or above the athlete's true level, not below —
  its raw EF would have dragged the trend down. Reuse the fixture from
  `pace-grade-adjustment.test.ts`.
- **Clean vs dirty equivalence:** a flat/cool tempo and a hot/hilly tempo at the
  same true effort should produce *similar* conditions-adjusted EF (within
  noise), demonstrating the normalization works.

## 10. Open questions

- **Weight curves (`w_heat`, `w_grade`) need calibration values.** Start from
  the table in §4.2; tune so the hot-block case holds flat and clean sessions
  still dominate. One-time sign-off.
- **HR-inflation transparency flag** — show an estimated "HR ran ~X bpm high in
  the heat" for the athlete's understanding, kept strictly out of the math?
  Decision pending.
- **Cross-training / cardiac drift on long runs** — decoupling read already
  exists; confirm it also respects the weighting.
- **Interaction with the grade plan's `DOWNHILL_CREDIT`** — fitness uses the
  same `combineConditions`, so it inherits whatever damping value we lock there.

## 11. Definition of done (Phase A)

- Fitness signal computes on conditions-adjusted pace; hot/hilly sessions no
  longer drag the EF trend down spuriously.
- Hot-block regression case holds flat (not declining).
- Public `FitnessSignal` shape unchanged; Read renders without modification.
- Degrades cleanly with missing HR / weather / elevation.
- Existing `fitnessSignal.test.ts` green; new normalization + weighting tests
  added.
