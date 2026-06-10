# Performance Cockpit — Data Inputs Contract

A pre-build inventory of every value the Cockpit (Plate 16) needs.
Each row says **what we need**, **where it should come from**, **whether it
exists today**, and **what to do if it doesn't**.

The plan is to ship the cockpit with placeholders/derivations for any
gap — and to track every gap explicitly here so we know what to backfill
and where.

---

## Section 1 — Header

| Field | Source | Have today? | Gap notes |
|---|---|---|---|
| Today's date | `Date()` (client-side) | ✅ | — |
| Days-to-goal-race / weeks-out string | `viewModel.activePlan.endDate` minus `Date()` | ✅ | — |

---

## Section 2 — KPI Tile #1 · FORM (TSB)

**TSB = Training Stress Balance = CTL − ATL.** Positive = fresh, negative
= accumulating fatigue. The classic Banister/Coggan freshness measure.

| Field | Source | Have today? | Gap notes |
|---|---|---|---|
| Today's TSB value | Computed from CTL − ATL (rolling daily TSS) | ❌ | **HOLE.** No daily TSS rollups stored. Need a `daily_training_load` table or compute on-demand from `workout_features`. |
| Daily TSS per workout | `workout_features.intensity_score` × duration? | ⚠️ partial | Not strictly TSS — `intensity_score` is the closest proxy. Acceptable v1 substitute. |
| 8-day TSB sparkline | Daily TSB over last 8 days | ❌ | Same as above — needs daily rollups. |
| FRESH / READY / TIRED labeling | `tsb >= 5 → FRESH`, `−5..5 → NEUTRAL`, `< −5 → TIRED` | ✅ (logic) | Just needs the value above. |

**v1 substitute:** Until proper TSS lands, derive a "freshness proxy":
`acwr` from `athlete_state` is monotonically related — if ACWR is in the
"productive" band (0.8–1.3) the runner is fresh; >1.3 = tired; <0.8 =
detraining. Map ACWR → TSB-style scalar.

---

## Section 3 — KPI Tile #2 · FITNESS (CTL → projected race time)

**CTL = Chronic Training Load = 42-day rolling avg of daily TSS.** The
"fitness" measure. The cockpit displays its *projected race time*
(more readable than a raw CTL number).

| Field | Source | Have today? | Gap notes |
|---|---|---|---|
| Projected marathon time | `fitness_snapshots.predicted_marathon_seconds` (latest) | ✅ | — |
| 4-week-ago projected marathon time | `fitness_snapshots` 28 days back | ✅ | — |
| Delta string ("−47s vs 4 wk") | Computed from above two | ✅ | — |
| 8-week CTL sparkline | 8 most recent `fitness_snapshots.predicted_marathon_seconds` | ✅ | Snapshots are daily — pick weekly samples. |

**No gap here.** This tile ships fully populated from existing
`fitness_snapshots` data.

---

## Section 4 — KPI Tile #3 · LOAD (ACWR)

**ACWR = Acute:Chronic Workload Ratio.** 7-day load divided by 28-day
rolling average. Already computed and surfaced.

| Field | Source | Have today? | Gap notes |
|---|---|---|---|
| Current ACWR value | `athlete_state.acwr` | ✅ | — |
| 8-week ACWR sparkline | `athlete_state` history? Or recompute from `workout_features` rolling. | ⚠️ | `athlete_state` is denormalized — only current value. **Need to either snapshot weekly OR recompute from `workout_features.acwr` historical rows.** |
| PRODUCTIVE / SPIKE / DETRAINING tag | `0.8 ≤ acwr ≤ 1.3 = PRODUCTIVE`, `> 1.3 = SPIKE`, `< 0.8 = DETRAINING` | ✅ (logic) | — |

**v1 substitute for sparkline:** if `workout_features` doesn't store ACWR
per-week, recompute on-the-fly from per-workout rows. Acceptable.

---

## Section 5 — KPI Tile #4 · STRAIN

**Strain = a single-number summary of yesterday's training stress.**
Whoop calls it "strain"; in TSS-land it's the day's TSS.

| Field | Source | Have today? | Gap notes |
|---|---|---|---|
| Yesterday's strain score | Latest `workout_features.intensity_score` (or per-workout TSS) | ⚠️ partial | `intensity_score` exists but isn't normalized to a 0–10 or 0–21 scale. Need to map it. |
| Workout type label ("TEMPO +35") | `training_logs.workout_type` + `workout_features.intensity_score` delta vs avg | ⚠️ | Workout type yes; the "+35" comparison is new logic. |
| 8-day strain sparkline | Last 8 days' workouts (zero on rest days) | ✅ | Compute client-side from `recentWorkouts`. |

**v1 substitute for "strain score":** use a simple proxy:
`distance_miles × intensity_factor` where intensity_factor is 1.0 for
easy, 1.4 for tempo, 1.8 for threshold, 2.0 for VO2/race. Roughly
matches TSS shape. Map to 0–10 for display.

---

## Section 6 — Fitness Curve · 12 weeks (CTL / ATL / TSB)

The hero chart. Three lines + filled TSB area over 12 weeks.

| Field | Source | Have today? | Gap notes |
|---|---|---|---|
| Weekly CTL values (last 12 wk) | Aggregated from `fitness_snapshots` (CTL is the underlying metric, predicted marathon is its display form) | ⚠️ | We have `predicted_marathon_seconds` but not raw CTL. Can use predicted-time as a proxy (lower = better fitness). |
| Weekly ATL values | Same source, but a 7-day window | ❌ | **HOLE.** ATL isn't stored. Would need to compute from `workout_features` weekly rollups. |
| Weekly TSB values | `CTL − ATL` per week | ❌ | Derived from above. |
| Zero-line for TSB | Constant | ✅ | — |

**v1 substitute:** if we can't get true CTL/ATL/TSB, ship a simpler
"fitness trend" chart — just `predicted_marathon_seconds` over 12 weeks
as a single line, no TSB area. Less impressive but honest. Mark this as
"⚠️ degraded" in code.

---

## Section 7 — Zone Shifts · this week vs 4-wk avg

Five-zone strip showing %-of-volume distribution + delta.

| Field | Source | Have today? | Gap notes |
|---|---|---|---|
| This-week miles per zone | `workout_features.easy_seconds`, `moderate_seconds`, `threshold_seconds`, `hard_seconds` | ⚠️ | Only 4 buckets in `workout_features`, but the cockpit shows 5 (Easy / Steady / Threshold / VO2 / Race). Either re-bucket or accept 4. |
| 4-week-avg miles per zone | Same fields, aggregated over 28 days | ✅ | Compute server-side or client-side. |
| Per-zone % | (zone miles) / (total miles) × 100 | ✅ (computed) | — |
| Delta vs 4-wk avg per zone | Subtraction | ✅ (computed) | — |

**Action:** ship with 4 zones (matching `workout_features`) instead of 5.
Drop "VO2" and "Race" → merge into a single "HARD" bucket.

---

## Section 8 — Race Predictions · 5 distances with deltas

| Field | Source | Have today? | Gap notes |
|---|---|---|---|
| Predicted mile time | `fitness_snapshots.predicted_mile_seconds` | ✅ | — |
| Predicted 5K | `fitness_snapshots.predicted_5k_seconds` | ✅ | — |
| Predicted 10K | `fitness_snapshots.predicted_10k_seconds` | ✅ | — |
| Predicted half | `fitness_snapshots.predicted_half_seconds` | ✅ | — |
| Predicted marathon | `fitness_snapshots.predicted_marathon_seconds` | ✅ | — |
| Per-distance 4-week-ago value | Same fields, snapshot from 28 days back | ✅ | Snapshots are daily — pick by date. |
| Confidence label | `fitness_snapshots.confidence` | ✅ | — |

**No gap. Ships fully.**

---

## Summary — what we have vs what we don't

### Ships fully today (no gaps):
- Header (date, weeks-out)
- KPI Tile #2 — Fitness/CTL → projected marathon time + delta + sparkline
- KPI Tile #3 — Load/ACWR (current value + tag) — sparkline degraded
- Race Predictions strip (all 5 distances, deltas, confidence)

### Ships with v1 substitutes (acceptable degradation):
- KPI Tile #1 — Form/TSB derived from ACWR proxy
- KPI Tile #4 — Strain derived from `distance × intensity_factor`
- Zone Shifts — 4 zones instead of 5
- Fitness Curve — single-line predicted-marathon trend instead of full CTL/ATL/TSB

### True holes that need backend work later:
- **Daily TSS rollups** — needed for proper CTL / ATL / TSB. Either a
  new `daily_training_load` table populated by the
  `compute-workout-features` edge function, or an on-the-fly aggregation
  in a new edge function `get-fitness-curve`.
- **5-zone breakdown** in `workout_features` (currently 4: easy /
  moderate / threshold / hard). Add `vo2_seconds` and `race_seconds`
  fields, populate from per-step pace classification.
- **Strain score** as a normalized 0–10 metric. Currently
  `intensity_score` is unnormalized.

### Effort to fully populate:
- 1 day to ship v1 with substitutes
- 2–3 days to add the daily TSS rollup + true CTL/ATL/TSB
- 1 day to add the 5-zone breakdown to `workout_features`

The cockpit is shippable today with degraded sparklines and the v1 substitutes,
and progressively gets richer as the backend lands those holes. None of
the holes block the visual layout.

---

## Code wiring plan

The cockpit's data-source layer should live in a new file
`RunningLog/Analysis/PerformanceCockpitData.swift` exposing:

```swift
struct CockpitSnapshot {
    let tsb: Double                       // signed; positive = fresh
    let tsbSparkline: [Double]            // last 8 points
    let projectedMarathonSeconds: Int
    let projectedMarathonDeltaSeconds: Int
    let fitnessSparkline: [Int]           // 8 weekly samples
    let acwr: Double
    let acwrSparkline: [Double]
    let acwrTag: String                   // "PRODUCTIVE" / "SPIKE" / "DETRAINING"
    let strainScore: Double               // 0–10
    let strainSparkline: [Double]
    let strainNote: String                // "TEMPO +35" / "REST" / etc.
    let fitnessCurve: FitnessCurveData    // CTL/ATL/TSB weekly samples (degraded if no TSS)
    let zoneShifts: [ZoneShift]           // 4-zone distribution
    let racePredictions: [RacePrediction] // 5 distances + deltas
}
```

A factory function `CockpitSnapshot.compute(from:)` takes:
- `recentWorkouts: [RunningWorkout]`
- `trainingLogs: [TrainingLog]`
- `fitnessSnapshots: [FitnessSnapshot]`
- `athleteState: AthleteState`
- `equivalentPaces: EquivalentPaces?`

…and returns a fully-populated snapshot, with documented v1
substitutes where data is missing. Each substitution logs `os_log`
once at debug level so we can grep for "[cockpit-substitute]" to find
what's degraded in any given build.
