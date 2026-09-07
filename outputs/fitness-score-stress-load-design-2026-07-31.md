# Fitness Score & Per-Workout Stress Load — Design

**Date:** 2026-07-31
**Status:** Phase 1 backend authored (pending `db push` + redeploy + backfill)
**Author:** Rio + Claude

## Problem

Each workout needs to carry its own **cumulative stress load** so the product
can build a real fitness score. Today it doesn't:

- **No per-workout stress value is stored anywhere.** `training_logs` has
  duration, distance, pace, RPE, and JSON segments — but no load column. The
  only per-workout load number
  (`intensity_score × duration`, `weeklyAnalytics.ts:computeWeightedLoadForLog`)
  is computed on the fly and thrown away. Nothing is visible on the workout,
  and nothing downstream can accumulate it. → *"I'm not seeing that in the
  workouts at all."*
- **No cumulative fitness–fatigue model.** The only aggregation is weekly
  ACWR + monotony/strain (now internal-only per WS3). There is no
  exponentially-decayed CTL/ATL/TSB curve — i.e. no "fitness" as accumulated
  load.
- **The two existing "fitness" concepts are disconnected:** the race-time
  predictor (`fitness_snapshots`, VDOT/Riegel off an anchor) does **not**
  consume load; the load metrics feed the coach layer, not the predictor.

## Key design decisions

1. **Stress model = source ladder** (chosen). One value per workout, from the
   best available signal, degrading gracefully across the mixed
   Strava/voice/manual corpus.
2. **Mechanical, not cardiovascular.** `ZONE_WEIGHTS` are explicitly
   "mechanical load"; cross-training is excluded from fitness math because it's
   cardiovascular. So the ladder is **pace-first** (mechanical truth); HR is a
   *fallback proxy for intensity when pace data is thin*, never the preferred
   signal. Cross-training / strength / rest score 0 (`stress_source='excluded'`).
3. **One unit: weighted training-minutes.** TSS/TRIMP/weighted-minutes are
   different scales and cannot be mixed into one CTL curve. Every tier estimates
   the *same* quantity — weighted minutes, anchored to `intensity_score` /
   `ZONE_WEIGHTS` — so the fitness curve is coherent. (This also keeps
   continuity with the value `computeWeightedLoadForLog` already produces.)
4. **CTL/ATL coexist with ACWR, not replace it.** ACWR stays an internal
   injury-risk input. CTL/ATL/TSB is the athlete-facing fitness/fatigue/form lens.

## The stress model (per workout)

Unit: **weighted training-minutes.** `stress_load ≈ intensity × duration_min`,
where `intensity` is on the 1.0–8.0 `ZONE_WEIGHTS` scale (easy=1.0 … mile=8.0).
So a 60-min easy run ≈ 60; a session averaging threshold-ish intensity over
60 min ≈ 180.

**Source ladder** (first that applies wins; recorded in `stress_source`):

| Tier | `stress_source` | Condition | Formula |
|---|---|---|---|
| Excluded | `excluded` | type ∈ {cross_training, strength, rest} | `0` |
| 1 — Pace | `pace` | real intra-workout pace data (rep laps or >1 pace segment) | `intensity_score × duration_min` |
| 2 — RPE | `rpe` | no usable splits, but `felt_rpe` present | `RPE_TO_INTENSITY[rpe] × duration_min` |
| 3 — HR | `hr` | *(reserved)* HR present + athlete HR profile exists | `hr_intensity × duration_min` |
| 4 — Type | `type` | typed but unsplit | `TYPE_FALLBACK_WEIGHTS[type] × duration_min` |
| — | `none` | no duration | `0` |

`RPE_TO_INTENSITY` mirrors the zone ladder: `1–2→1.0, 3→1.25, 4→1.5, 5→2.0,
6→2.5, 7→3.25, 8→4.0, 9→5.5, 10→8.0`.

**HR tier is reserved, not shipped in Phase 1.** A correct TRIMP-style intensity
needs per-athlete HRmax + HRrest, which we don't store. We will **not** fake it
with `220−age` (violates no-hardcoded-defaults + no-hallucination). Ships once
an HR profile exists (HealthKit resting HR + observed max, with consent). Until
then HR-only workouts fall through to RPE or type.

## Phases

### Phase 1 — Persist per-workout `stress_load` *(this pass)*

Make the atomic unit exist and be visible.

- **Migration** `20260731120000_add_stress_load_to_training_logs.sql`:
  `training_logs.stress_load double precision`, `stress_source text`. No new
  table → existing RLS covers it.
- **`compute-workout-features`**: compute `stress_load` from the segmentation it
  already produces (`computeStressLoad`), write it back to `training_logs`.
  Runs on every new workout + `backfill` mode. `felt_rpe` added to the query.
  Column-missing guarded for deploy-order safety.
- **Remaining Phase 1 steps (not yet done):**
  - Run backfill (`{ user_id, backfill: true }`) for existing athletes after
    `db push` + redeploy.
  - Point `computeWeightedLoadForLog` at the stored column (single source of
    truth; keep the on-the-fly compute as fallback).
  - **iOS:** surface `stress_load` on the workout row / detail (Log tab).
    Design register per `data_depth` (a number is fine at depth 2+).

### Phase 2 — Cumulative model (CTL / ATL / TSB)

- Daily EWMA of `stress_load`: **CTL** (42-day = "fitness"), **ATL** (7-day =
  "fatigue"), **TSB = CTL − ATL** ("form"). Standard Banister/Coggan decay
  (α = 1 − e^(−1/τ)), stepped by day (zero-load rest days decay both curves).
- New table `daily_training_load` (user_id TEXT, date, stress_load, ctl, atl,
  tsb) — **RLS in the same migration** (hard rule #1); or store the latest on
  `athlete_state` + a compact series. Extend the nightly
  `compute-fitness-snapshot` cron to roll it forward.
- Keep ACWR/monotony/strain untouched (injury layer).

### Phase 3 — Surface & connect

- CTL fitness-trend curve in the app (Trends tab), race anchors plotted.
- Feed CTL/TSB as *context* into the coach/predictor layer — **not** conflated
  with the race-time predictor. Naming discipline: "load/fitness" (CTL) is a
  distinct concept from the race-time projection and from
  `athlete_state.fitness_signal` (pace-at-HR trend).

## Open questions

- **CTL time constant.** 42/7 is the Coggan default; may want to tune τ for
  runners on this corpus.
- **Where CTL lives** — dedicated `daily_training_load` table vs. `athlete_state`
  fields + series. Table is cleaner for charting history.
- **HR profile** — do we source HRmax/HRrest from HealthKit, or defer the HR
  tier indefinitely and rely on pace+RPE (which already cover most logs)?
- **Backfill of `felt_rpe`** — only exists since 2026-06-11, so the RPE tier
  only helps recent unsplit logs; older unsplit logs use the type fallback.

## Files touched (Phase 1)

- `supabase/migrations/20260731120000_add_stress_load_to_training_logs.sql` (new)
- `supabase/functions/compute-workout-features/index.ts`
  (`computeStressLoad`, `RPE_TO_INTENSITY`, write-back loop, `felt_rpe` in query)
