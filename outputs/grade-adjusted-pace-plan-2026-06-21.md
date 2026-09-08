# Grade-Adjusted Pace + Conditions-Adjusted Pace — Design Plan

**Date:** 2026-06-21
**Status:** Proposed (planning)
**Owner:** TBD
**Related:** `outputs/fitness-signal-pace-at-hr-2026-06-15.md`,
`supabase/functions/_shared/pace-heat-adjustment.ts`,
`supabase/migrations/20260528222217_add_heat_adjusted_pace_to_laps.sql`,
`outputs/athlete-state-v2-coach-grade-2026-06-12.md`

---

## 1. The problem in one paragraph

Today the product corrects pace for **heat** but not for **hills**. A workout's
execution read (fade, pace consistency) and the fitness signal (pace-at-HR
efficiency) all run off raw `avg_pace_sec_per_mile`. That means a hilly tempo
reads as a "fade" and a climb-heavy week reads as an efficiency drop, even when
the athlete ran perfectly to effort. Heat already has a clean fix — a per-lap
adjusted pace stored beside the raw pace, surfaced into `athlete_state`. This
plan extends that exact pattern to **grade**, then **combines grade + heat into
a single "conditions-adjusted pace"** so the coach read and the quant math
both judge effort, not terrain.

## 2. Decisions locked (2026-06-21)

These were confirmed with the product owner before writing this plan:

1. **Reach:** Display the adjusted pace **and feed it into the quant read** —
   execution analysis (fade, CV) and the fitness signal. (Not, in this phase,
   adjusting prescribed targets or pace zones for hilly routes — that's a
   deliberate later scope.)
2. **Model:** **Phased.** Phase 1 = a lap-level approximation from elevation
   data we already store (works on every run, rough). Phase 2 = a per-second
   grade-curve model (accurate, handles up + down, Strava/Garmin only).
3. **Stacking:** **One combined conditions-adjusted pace** — grade and heat
   resolve into a single "what this effort was worth in neutral conditions"
   number, rather than two separate signals the athlete has to reconcile.

## 3. Design principles (carried from the heat work)

- **Adjusted pace is a model, not a measurement.** Always store the adjusted
  value *beside* the raw value, never in place of it. The athlete owns the
  interpretation. (Verbatim the stance in the heat migration header.)
- **Twin source of truth: SQL + TS.** Heat lives as both a Postgres function
  (`heat_adjustment_pct()`) and a TS module (`pace-heat-adjustment.ts`), kept
  in sync. Grade mirrors this so backfill (SQL) and live edge-function compute
  (TS) agree to the decimal.
- **Direction convention matches heat.** Observed paces are adjusted *down* to
  a neutral-equivalent (a hilly 8:00 becomes a faster equivalent flat pace);
  prescribed/target paces, if ever adjusted, go *up*. Same dual convention the
  heat code documents — keep it explicit in every comment and UI label.
- **Honesty over precision (hard rule #7).** No false confidence. When grade
  data is missing or low-resolution, the adjusted value is `null` and the
  system degrades to raw pace rather than guessing.
- **Graceful degradation everywhere.** Manual/HealthKit runs with no elevation
  simply get `null` adjusted pace; nothing breaks.

## 4. What data we actually have (the constraint that drives phasing)

| Source | Field | Granularity | Coverage | Good enough for…|
|---|---|---|---|---|
| `running_workout_laps.total_elevation_gain` | gain only (no loss) | per lap | all imported runs w/ laps | rough lap-level approximation |
| `training_logs.external_streams.streams.grade_smooth` | signed % grade | per second | Strava/Garmin only | accurate energy-cost model |
| `external_streams.streams.altitude` | elevation | per second | Strava/Garmin only | derive grade if `grade_smooth` absent |

The key limitation: **`total_elevation_gain` is gain-only.** It can't tell a
steady climb from a rolling lap, and it ignores the (smaller but real) cost of
downhill. That's exactly why Phase 1 is explicitly an *approximation* and
Phase 2 needs the per-second signed grade stream.

## 5. The model

### 5.1 Phase 2 target model (the "real" one) — define it first

Grade-adjusted pace uses a **published energy-cost-of-running curve** as a
function of gradient. The two standard choices:

- **Minetti et al. (2002)** energy cost polynomial — the academic standard.
- **Strava's GAP curve** — a practical, widely-validated derivative.

**Decision (revised 2026-06-21): do NOT ship raw Minetti.** Validation against a
real race (see §10.1) showed raw Minetti **over-credits downhills** — it treats
fast downhill running as nearly free, because it measures *metabolic cost* and
gentle descents are genuinely cheap metabolically. But that cheap energy does
not convert to proportional speed (turnover cap, eccentric braking, leg
preservation), so on the clock **an uphill slows you more than the matching
downhill speeds you back up.** Raw Minetti misses this asymmetry and will tell
athletes that rolling/loop courses were "neutral" when their legs know they
were not.

The default curve must therefore be **asymmetric — full uphill cost, damped
downhill credit.** Two acceptable implementations:

1. **Damped Minetti (recommended default):** keep Minetti's uphill side; on
   descents count only a fraction of the credit, `gradeFactor = 1 + DOWNHILL_CREDIT
   × (minetti(g)/C0 − 1)` for `g < 0`. Start at `DOWNHILL_CREDIT ≈ 0.5` and tune
   against the calibration case in §10.1.
2. **Strava-style GAP curve:** already flattens downhill benefit for this exact
   reason; use if we'd rather adopt a validated external shape than tune our own.

Expose either as a single function `gradeFactor(gradePct)` returning a multiplier
where `1.0` = flat. Per second:

```
adjustedSec_i = actualSec_i / gradeFactor(grade_i)
```

then aggregate distance-weighted to the lap. Uphill `gradeFactor > 1`
(adjusted pace faster than actual = you earned it); downhill `gradeFactor < 1`
(some of the free speed removed — but **less than Minetti would remove**, per the
damping); steep downhill the credit shrinks further (braking cost). Clamp
gradient to a sane range (≈ −30%…+30%) before lookup.

### 5.2 Phase 1 approximation (ship-now) — derived from the same curve

For a lap we have only average gain over distance. Approximate average gradient:

```
approxGradePct = (total_elevation_gain_m / lap_distance_m) × 100
```

Feed that single average gradient through the **same** `gradeFactor()` to get a
lap multiplier. This is intentionally conservative and gain-only — document it
as "rough, uphill-aware only." Two guards:

- Suppress the adjustment when `approxGradePct` is below a noise floor
  (≈ 1%) — flat runs get no adjustment, avoiding jitter.
- Cap the Phase-1 adjustment magnitude (e.g. ±6%) so a bad-GPS gain spike
  can't manufacture a huge correction.

When Phase 2 lands, the lap-approx path stays as the fallback for runs without
per-second streams. Same `gradeFactor()` underneath → the two phases never
disagree on the curve, only on input resolution.

### 5.3 Combining grade + heat into one conditions-adjusted pace

Both adjustments are multiplicative and independent (terrain cost vs.
thermoregulatory cost), so they compose cleanly:

```
conditionsAdjustedSec = actualSec / gradeFactor(grade) / (1 + heatPct)
```

Equivalently, define `conditionsFactor = gradeFactor(grade) × (1 + heatPct)`
and divide once. Store the combined value **and** keep the two component
factors so the read can attribute ("8:05 actual; 7:46 adjusted — most of that
is the 600 ft of climb, some is the 74°F dew point").

## 6. Schema changes

New migration (append-only; never edit the heat migration). Mirror the heat
column set on `running_workout_laps`:

```sql
ALTER TABLE running_workout_laps
    ADD COLUMN avg_grade_pct                     NUMERIC(5,2),   -- signed, lap avg
    ADD COLUMN grade_adjustment_factor           NUMERIC(6,4),   -- 1.0 = flat
    ADD COLUMN grade_adjusted_pace_sec_per_mile  NUMERIC(8,2),
    ADD COLUMN grade_source                      TEXT
        CHECK (grade_source IN ('stream','lap_approx')),
    -- the combined signal (grade ∘ heat):
    ADD COLUMN conditions_adjusted_pace_sec_per_mile NUMERIC(8,2);
```

Plus a SQL `grade_factor(grade_pct)` function (the Phase-1/SQL twin of the TS
`gradeFactor`), following the exact shape of `heat_adjustment_pct()`. Backfill
`grade_adjusted_pace` and `conditions_adjusted_pace` for existing laps from
`total_elevation_gain` (Phase-1 path) in the same migration, with the same
`ON CONFLICT`/null-guard discipline the heat backfill uses.

RLS: no new policies needed — new columns inherit `running_workout_laps`
policies. (Confirm in the migration that no new table is introduced; hard
rule #1 only bites on new tables.)

## 7. Code changes

### 7.1 New shared module — `_shared/pace-grade-adjustment.ts`
Mirror the structure of `pace-heat-adjustment.ts`:
- `gradeFactor(gradePct): number`
- `adjustPaceForGrade(paceSec, gradePct): GradeAdjustment`
- `combineConditions(paceSec, gradePct, heatPct): ConditionsAdjustment`
- `buildConditionsJson(...)` for any JSONB snapshot we store on
  `training_logs`.

### 7.2 Lap writers
`strava-sync` and the lap-ingest triggers
(`20260613250000_running_workout_laps_ongoing_writer.sql`) populate
`avg_grade_pct` (from per-second `grade_smooth` when present → `grade_source =
'stream'`; else lap-approx → `'lap_approx'`) and the derived adjusted columns.

### 7.3 Feed the quant read — the part that closes the gap
This is the decision that distinguishes this work from the heat baseline
(heat is still only context today). In **`athlete-state.ts`**:

- **Execution block** (`segmentFromLaps`, ~line 1418): segment on
  `conditions_adjusted_pace_sec_per_mile` (fallback raw) so fade %, pace CV,
  and shape are computed on effort, not terrain. Keep raw available for
  display.
- **Fitness signal** (`computeFitnessSignal`, ~line 1449): feed the
  conditions-adjusted pace as the pace side of pace-at-HR. A climb no longer
  looks like lost efficiency.
- **`environment` satellite** (~line 1399): add `avg_grade_pct`,
  `grade_adjusted_pace`, and `conditions_adjusted_pace` beside the existing
  heat fields.
- **New pattern rule** — `hill_sensitivity`, analogous to the existing
  `heat_sensitivity` rule (~line 1501): "Climbing costs you real pace — your
  hilly runs read slower than your fitness," gated on N runs with meaningful
  grade. (Same confidence/evidence shape as the heat rule.)

> Note: feeding adjusted pace into execution/fitness also implicitly upgrades
> the **heat** correction, which today is display-only in the quant path. That
> is intended and is a bonus from doing the combined signal.

### 7.4 Per-run insight + Coach Read
`generate-workout-insight`'s "This run's conditions" block already prints
elevation gain; add the grade-adjusted/conditions-adjusted pace line. The
daily-read prompt gets the new environment fields automatically via
`athlete_state`.

### 7.5 iOS parity
`PaceCalculator.swift` already houses the heat calculator; add the grade twin
there too so on-device display matches the backend, and keep both in sync (the
repo already calls out heat TS↔Swift drift risk).

## 8. Evals & correctness (hard rule #3)

Any prompt that newly references conditions-adjusted pace needs cassette
coverage in `_evals/cassettes/` before shipping. Add fixtures:
- a hilly tempo that should **not** read as a fade once grade-adjusted,
- a flat hot run (heat-only) — regression guard that grade=0 changes nothing,
- a hilly + hot long run exercising the combined factor,
- a manual/no-elevation run — adjusted fields `null`, read degrades to raw.

Unit tests for `gradeFactor()` against published Minetti values (uphill side),
the **downhill-damping behavior** (descents credited less than raw Minetti), and
a SQL-vs-TS parity test (same inputs → same factor to 4 dp), mirroring the heat
test discipline. Include the **§10.1 calibration case** as an integration test:
the reference race must read as a net hill *cost*, not neutral.

## 9. Phasing & sequencing

**Phase 1 — Lap approximation, display + quant (ship first)**
1. `gradeFactor()` TS + SQL twin, with unit + parity tests.
2. Migration: columns + SQL function + Phase-1 backfill from
   `total_elevation_gain`.
3. Lap writers populate `avg_grade_pct` (lap_approx) + adjusted columns.
4. `athlete-state` execution + fitness + environment + `hill_sensitivity`.
5. Insight/read surfacing; eval cassettes; iOS display.

**Phase 2 — Per-second grade curve (accuracy upgrade)**
6. Compute `avg_grade_pct` from `grade_smooth` (fallback `altitude`-derived);
   set `grade_source = 'stream'`.
7. Re-backfill stream-capable runs; lap_approx remains the fallback.
8. Validate Phase-2 vs Phase-1 deltas on a sample; tune clamps.

**Phase 3 (later, explicitly out of this scope)**
Grade-adjusted prescribed targets and hill-aware pace zones ("run this climb by
effort"). Flagged here only so we don't paint ourselves out of it.

## 10. Risks & open questions

### 10.1 Calibration case — Cap 10K (Austin), 2026-04-12

The reference test for any curve we pick. Real data (Strava activity
18014204417 family / race effort `18081526879`), validated 2026-06-21:

- Course: rolling loop, **~327 ft (100 m) climb**, net elevation ≈ 0 (finishes
  where it starts). Actual time **33:02**, raw pace ~5:17/mi.
- Split into climb vs descent: climbing portions ran 5:27/mi (effort-equiv
  ~4:46), descending portions ran 5:05/mi (effort-equiv ~6:07 under raw
  Minetti) — a ~40 s/mi swing that **nets to near zero on the loop**.
- **Net terrain effect by downhill-credit setting:**

  | Downhill credit | Net hill effect |
  |---|---|
  | 100% (raw Minetti) | helped ~14 s ← **wrong** |
  | 70% | cost ~36 s |
  | **50% (recommended default)** | **cost ~63 s** |
  | 30% | cost ~88 s |
  | 0% (uphill only) | cost ~121 s |

- **Acceptance:** the chosen curve must score this race as a **net hill cost of
  roughly 45–90 s** (≈ 7–14 s/mi). Any setting that reports "neutral" or
  "terrain helped" is disqualified. `DOWNHILL_CREDIT ≈ 0.5` is the starting
  point; final value tuned here.
- Heat cross-check (same race, 70°F / 69.4°F dew point via Emy's Calculator):
  composite 142.9 → "hot," ~2.36% → ~45 s. Combined flat-and-cool equivalent
  ≈ **31:00–31:30** vs the 33:02 actual. (Note: that dew point is near-saturated;
  see §10.2 — the heat table likely under-penalizes extreme dew points.)

### 10.2 Risks

- **Gain-only Phase 1 understates rolling terrain and ignores downhill.**
  Mitigation: ship it labeled as approximate; Phase 2 fixes it. Don't let
  Phase-1 numbers leak into anything that implies precision.
- **Bad-GPS elevation spikes.** Mitigation: noise floor + magnitude cap +
  gradient clamp.
- **Curve choice — RESOLVED in principle (2026-06-21):** asymmetric curve
  required (damped-Minetti default, `DOWNHILL_CREDIT ≈ 0.5`, or Strava GAP). Raw
  symmetric Minetti is disqualified — it over-credits downhills (see §5.1, §10.1).
  Remaining sign-off: final `DOWNHILL_CREDIT` value, tuned against §10.1.
- **Heat table likely under-penalizes extreme dew points.** Separate finding
  from the Cap 10K cross-check: a 69°F dew point (near-saturated) scored only
  ~2.36% / ~7 s/mi via Emy's Calculator, which is light for conditions most
  coaches treat as severe. Out of scope for this grade work, but worth a
  follow-up to add more bite to the composite-score table above ~65°F dew point.
- **Combined attribution UX.** Showing one number is cleaner, but the read
  should be able to attribute the split (how much was hills vs heat) — we store
  both component factors to enable that. Confirm the read voice wants the
  attribution sentence.
- **TS↔SQL↔Swift drift** (three copies of the curve). Mitigation: parity tests
  in CI; treat the curve table as a shared constant block copied verbatim.

## 11. Definition of done (Phase 1)

- Hilly tempo no longer registers as a fade in `athlete_state.execution`.
- `environment` carries grade + combined adjusted pace per run.
- `hill_sensitivity` pattern fires on a climber's history.
- Raw pace still stored and displayed everywhere; adjusted shown beside it.
- Manual/no-elevation runs degrade cleanly to raw (no errors, `null` adjusted).
- SQL and TS `gradeFactor` agree to 4 dp; evals green.
