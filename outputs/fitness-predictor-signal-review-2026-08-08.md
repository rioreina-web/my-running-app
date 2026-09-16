# Fitness Predictor — Signal Review & Upgrade Plan (Aug 2026)

**Rev 2 — weekly mileage promoted to a first-class signal.** §2.3 rewritten,
§1/§4/§5 updated to match. Rev 1 is preserved at
`fitness-predictor-signal-review-2026-08-08.v1.md`.

Reviewed against the live server model (`supabase/functions/_shared/fitnessPrediction.ts`,
consumed by `compute-fitness-snapshot`) and its satellite modules
(`fitnessSignal.ts`, `effortModel.ts`, `workloadScore.ts`, `quality-volume.ts`,
`fast-segment-trends.ts`), plus the new `daily_biometrics` and
`daily_checkins.mood` tables. Companion to the May audit
(`fitness-predictor-audit.md`) and redesign (`fitness-predictor-redesign.md`).

## TL;DR

The predictor has come a long way since May: race anchors are age-weighted,
deduped, and read as flat-cool equivalents; laps feed a rest-aware, heat- and
grade-normalized hard-effort pool; long-run endurance shades the marathon;
ranges are distance-aware. The race-effort side of the model is in good shape.

The core finding of this review: **you have already built most of the signals
you asked about — they just don't feed the predictor.** The app now computes
an efficiency score (pace-at-HR, two separate implementations), mature
pace-band trends, a per-workout stress/load design, mood check-ins, and
nightly HRV/resting-HR/sleep ingestion. All of it flows to the coach, the
recovery ledger, or the Trends UI. **None of it flows to
`generateFitnessPrediction`.** The predictor still measures training with the
weakest instrument in the codebase — sparse `pace_segments` effort labels —
and its own comments admit it (the quality-density floor exists precisely
because "labels are sparse/unreliable").

The upgrade is therefore mostly *plumbing, not invention*: route the signals
you already trust into the predictor, with the same evidence-first discipline
the model already enforces (corroborate, cap, widen — never fabricate).

**The single most important instance of that is weekly mileage.** It is the
key training metric — the one number every runner already thinks in, and the
only signal in this document with ~100% coverage from an athlete's first
logged week. EF needs heart rate; mood needs check-ins; biometrics needs a
watch worn overnight. Mileage needs a run. And yet the repo currently holds
**five different definitions of "miles per week"**, the predictor owns the two
worst, and the one it actually uses divides a numerator and a denominator from
two different windows — so depending on which anchor path fired it reads up to
~4× high (the training-anchor and nightly-snapshot paths) or ~3.5× low (the
week after a race). Both are silent, and six branches of the model threshold
on the result. See §2.3. Weekly mileage is therefore not a new feature to
build — it is a number to *fix, unify, and then shape* (level → ramp →
consistency → athlete-relative). That work is hours of correctness plus a
small refactor, it makes every downstream volume threshold in the model mean
what it says, and it is the substrate the CTL/ATL/TSB work needs anyway. It
moves to the front of the queue.

## 1. What the predictor reads today

| Input | Source | Used for |
|---|---|---|
| Confirmed + detected races (all time) | `training_logs.race_result`, note parsing | Anchor (36wk trusted window, 16wk primary), lifetime PRs, speed evidence |
| Race-day laps | `running_workout_laps` | Flat-cool equivalent race pace (heat + Minetti grade, ±5% clamp) |
| Training anchors | `parsed_structure.equivalent_race_pace` (conf ≥ 0.6) | Blend/displace stale race anchor (50/50, 3% floor) |
| Laps, last 21d | `running_workout_laps` | Rest-aware hard-effort pool (heat/grade-normalized, rest penalty 0–2.5%) |
| Pace segments, last 30d | `training_logs.pace_segments` | Stimulus minutes (label-gated), 14-day validation signal (±2% band) |
| **Weekly mileage** | `training_logs.workout_distance_miles`, **not source-deduped**; miles summed over `(anchorDate, 28d]` but divided by *anchor age* (`fitnessPrediction.ts:1341`), plus a second, incompatible 14d-vs-6wk definition inside `detectDetraining` | Maintenance credit (`min(weeklyMiles/40, 1)`, 35% of `maintenanceFactor`), build gate (`volumeTrend > 1.15`), decay bump (`volumeTrend < 0.5`), `marathonVolumeFactor` (up to +6% range below 40 mi/wk), `marathonExtra` (+1% below 30 mi/wk), `lowVolume` detraining trigger (<15 mi/wk or <50% of baseline) |
| Long runs, 10wk | `training_logs` miles | Marathon/half endurance shading (20mi/3×16mi = ready) |
| Prior snapshots | `fitness_snapshots` | Decay-gated baseline fallback, anti-ratchet |
| Plan goal | `training_plans` | Last-resort anchor |
| Weather | `weather_actual`, per-lap temp/dew | Heat normalization (12% cap, rep-length scaled) |

What it does **not** read: heart rate in any form, efficiency trends, band
trends, stress load / CTL, mood, niggles, biometrics, RPE. `thresholdCapacity`
(the 2026-07-24 threshold-from-training signal) is exported but has no caller
in any edge function — confirm whether Swift uses it; server-side it's dead.

## 2. Signal-by-signal assessment

### 2.1 Race efforts — strong, two gaps

What's right: age-weighted selection (0.2%/wk penalty), dedupe
(`dedupeRaces`, 3d/2%), flat-cool equivalents, user exclusions, displacement
cap on training anchors, race-candidate tagging loop.

Gaps:

1. **Non-standard distances are dropped on the floor.** `distanceToRaceType`
   only knows mile/5K/10K/half/marathon. An 8K, 10-miler, or 15K in
   `race_result` returns `null` and the race vanishes from the model
   entirely. Fix: convert any distance ≥ 1mi to a 10K-equivalent via Riegel
   and let it compete for the anchor (tag `raceType: null`, skip the
   per-distance PR display).
2. **Agreement between races is measured nowhere.** Dedupe killed the
   false "multiple agreeing races" inflation, but genuine agreement (two
   races, months apart, within ~1.5% on 10K-equivalent) should *tighten* the
   range — the May redesign called for this and it never landed. One line in
   `rangeFraction`: agreement → −20% on the base fraction.

### 2.2 Training efforts — the label problem

Every training-effort path is gated on effort **labels**:
`hardEffortTypes` for stimulus minutes, `THRESHOLD_EFFORTS` for the (unused)
threshold signal, `HARD_SEGMENT_EFFORTS` for the recovery penalty. The model
itself distrusts them — the quality-density floor and the continuous-training
decay cap both exist to patch label sparsity.

Meanwhile `fast-segment-trends.ts` already defines the label-free version:
fast = MP-and-faster vs the athlete's own anchors (`isQualityPace`), bouts
merged rep-by-recovery, three toggleable pace corrections, per-system volume
with `SYSTEM_WORK_VOLUME_MILES` sanity ranges. And `effortModel.ts` measures
**density** (rest relative to the athlete's own baseline, 0.85–1.35×) — a
strictly better instrument than the predictor's flat 0/1.5/2.5% rest penalty.

Recommendation: make the lap/pace-derived classification primary and labels a
fallback, by feeding the predictor the same bout structure
`analyzeKeySession` builds. The stimulus-minutes computation, the 14-day
validation pool, and the rest penalty all get sharper from one refactor.

### 2.3 Weekly mileage — the key metric, currently measured five ways

Mileage per week is the metric the whole product is organised around: it is
what the athlete reports, what the coach asks for, what the Read prints
(`28d avg: N mpw`), and what six separate branches of the predictor
threshold on. It deserves one definition, computed once, correct. It has
five, and the predictor owns the two worst.

#### The five definitions

| Where | Formula | Deduped? | Window |
|---|---|---|---|
| `builders/buildLoadMetrics.ts:80` | `weeklyAvg28d = rolling28dMiles / 4` | ✅ `dedupBySourcePriority` | fixed 28d |
| `builders/buildBlocks.ts:102` | `weekly_avg_miles = totalMiles / 4` per block | ✅ | fixed 4wk blocks, longitudinal + `year_ago` |
| `weeklyAnalytics.ts:599` | `aggregateWeeklyLoad` → `{miles, minutes, runCount, weightedLoad}` | n/a (caller supplies a week) | true Mon–Sun week (`getLastWeekBounds`) |
| `fitnessPrediction.ts:1341` | `weeklyMiles = (recentMiles + priorMiles) / min(weeksSinceAnchor, 4)` | ❌ | numerator `(anchorDate, 28d]`, **denominator = anchor age** — two different windows |
| `fitnessPrediction.ts:887` | `recentMilesPerWeek = recentMiles / 2` vs coverage-corrected 6wk baseline | ❌ | 14d vs ~16d |

The first three are sound instruments and already run nightly against the same
`training_logs` table. The predictor uses none of them — and its own two
disagree with each other.

#### Bug A — numerator and denominator come from different anchors

```ts
// numerator window: (anchorDate, now] ∩ [fourWeeksAgo, now]
for (const w of workouts) {
  if (!d || d <= anchorDate) continue;              // 1298
  if (d >= twoWeeksAgo)      recentMiles += w.distanceMiles;
  else if (d >= fourWeeksAgo) priorMiles += w.distanceMiles;
}
const weeksSinceAnchor = Math.max(anchorWeeksAgo, 1.0);            // 1338
const weeklyMiles = (recentMiles + priorMiles) / Math.min(weeksSinceAnchor, 4.0); // 1341
```

`anchorDate` (the numerator's start) is set **only when the anchor is a race**
(line 1286–1290); otherwise it stays at `fourWeeksAgo`. `anchorWeeksAgo` (the
denominator) is set by **every** anchor path — race, training anchor, blended,
and snapshot-baseline. When those two disagree, the ratio is not a rate.

Three concrete cases:

- **Training-anchor path** (a recent quality session parsed with
  `equivalent_race_pace`, lines 1245–1254 and 1256–1269). `chosenRace` stays
  null → numerator is the full 28 days. `anchorWeeksAgo` is the age of that
  session — often 3–6 days → denominator clamps to 1.0. **28 days of miles ÷
  1 week ≈ 4× overstatement.** A 30 mi/wk athlete reads as ~120.
- **Snapshot-baseline path** (line 1277–1280, the `fitness profile` fallback).
  `anchorWeeksAgo` comes from the chosen snapshot's `created_at`, and
  snapshots are written *nightly* — so `anchorWeeksAgo ≈ 0.1`, clamps to 1.0,
  and the same 4× overstatement fires **every night, for every athlete on the
  fallback path**.
- **Race inside 7 days.** Here `anchorDate` *is* updated, so the numerator
  correctly truncates to the days since the race — but the denominator still
  floors at 1.0. A race two days ago → 2 days of miles ÷ 1 week ≈ **3.5×
  understatement**, in the week after a goal race when the athlete is most
  likely to be reading the prediction.

For a race anchor older than one week the arithmetic is actually correct —
which is exactly why this has survived: the case the tests were written
around is the case that works.

Consequences, in both directions:

- `volumeCredit = min(weeklyMiles / 40, 1)` pins to 1.0 (overstatement) or
  collapses toward 0 (understatement). It is 35% of `maintenanceFactor`.
- `qualityDensity = hardMiles28 / 4 / weeklyMiles` (line 1390) inherits the
  error in its denominator → the 6% "aerobic-only" penalty and the 15%
  density floor both misfire.
- `marathonVolumeFactor` and `marathonExtra` are pure step functions on
  `weeklyMiles` at 40 and 30 — an inflated number silently **stops the range
  from widening** for a genuinely low-volume marathoner.

Fix: derive the divisor from the numerator's own window
(`daysCovered / 7`, floored at ~0.5 to avoid a divide-by-stub), not from
anchor age. Note `weeklyStimulusMinutes` on line 1339 *is* correctly divided
by `weeksSinceAnchor` — its numerator genuinely accumulates from the anchor
date (line 1315). The miles line is a copy of that divisor onto a numerator
that doesn't share its window.

The iOS Trends side has already reasoned this through, in the still-unapplied
`01-trends-partial-week-and-mood-tiebreak.patch` (see
`APPLY-TRENDS-WEEK-FIXES.md`): *"Dividing by days makes bucket size
irrelevant: a partial week contributes exactly the days it holds and no
more."* Same class of bug, same fix. Worth landing both together — and note
`TrendsSignalBuilder.perDay` does not exist in
`RunningLog/RunningLog/Trends/TrendsSignalModels.swift` yet, so the Trends
partial-week bug is still live too.

#### Bug B — miles are double- and triple-counted

`compute-fitness-snapshot/index.ts` builds `extendedWorkouts` straight off
`training_logs` rows (lines 136–160) with no dedup. `buildLoadMetrics` and
`buildBlocks` both call `dedupBySourcePriority` first, and the comment there
says why: one run lands as up to three rows (Strava auto-sync, HealthKit
`auto_sync`, and the athlete's voice log) with different timestamps.

So for any athlete with two sources connected, `athlete_state.weekly_avg_miles`
and the predictor's `weeklyMiles` are different numbers for the same week —
and the predictor's is the inflated one. Every threshold below it (40, 30, 15)
is absolute miles, so the inflation translates directly into wrong credit and
missing range. Two consumers, one truth: `extendedWorkouts` must go through
`dedupBySourcePriority` at construction.

#### Bug C — detraining reads 30 days when 180 are already in memory

`generateFitnessPrediction` passes `workouts` — the `cutoff30` slice — to
`detectDetraining` (line 1173), while `extendedWorkouts` from the *same query*
holds 180 days (`cutoff180`, index.ts:131). That is why the July 16
`baselineCoveredWeeks` patch exists: the "6wk → 2wk back" baseline can only
ever hold ~16 days of data, so it had to be divided by coverage instead of by
4. The patch is correct but it is treating a self-inflicted wound.

Pass the long array and the baseline becomes real — and a **~25-week weekly
mileage series arrives for free, with no new fetch and no new table.**

#### What's missing: the model has level, but no shape

Fix the three bugs and the predictor knows *how much* the athlete runs. It
still doesn't know the four things a coach actually reads off a mileage chart:

1. **Calendar weeks.** There is no week boundary anywhere in the predictor —
   only rolling 14/28-day windows. Both Monday-first conventions already
   exist (`getLastWeekBounds`, and iOS `calendar.firstWeekday = 2` in
   `WorkoutsView`/`TodayPlate18`/`AnalysisModels`), so this is a formatting
   decision, not a design one. Rolling windows also mean a long run drifting
   from Sunday to Monday silently moves ~20 miles between windows.
2. **Ramp rate.** `volumeTrend = recentMiles / priorMiles` is 14d vs 14d. One
   20-mile long run, or one planned down week, swings it >20%. The build gate
   at `> 1.15` therefore rewards a two-week spike — the exact pattern that
   precedes injury — while a textbook 3-up/1-down block reads as flat and a
   taper reads as decline. A 4-week rolling average vs the prior 4 weeks is
   the same information with a quarter of the noise.
3. **Consistency.** 40 mi/wk as `10/10/10/10` and as `20/20/0/0` are different
   athletes with different fitness, and the model cannot tell them apart.
   Weeks at ≥80% of the 4-week average, out of the last 8, separates them in
   one integer.
4. **Athlete-relative scale.** Every threshold is absolute — the 40 mi/wk
   credit cap, the 30 mi/wk marathon extra, the 15 mi/wk detraining floor. A
   lifetime 25 mi/wk athlete sitting at their own all-time peak is permanently
   capped at 0.63 volume credit; a 90 mi/wk athlete who collapses to 45 still
   reads a perfect 1.0. `buildBlocks` and `year_ago.weekly_avg_miles` already
   sketch the athlete's own distribution — percentile against a trailing
   52 weeks fixes both ends. Keep the absolute floor for the *detraining*
   trigger (15 mi/wk is a physiological floor, not a relative one); make the
   *credit* relative.

Cap saturation is worth calling out separately: above 40 mi/wk the model is
blind to additional volume, and volume is 35% of `maintenanceFactor`. A
70 mi/wk athlete and a 40 mi/wk athlete are indistinguishable to the decay
machinery.

#### Recommended shape

One computed-once input on `PredictionInput`, built from the existing
`aggregateWeeklyLoad` so the predictor, the weekly coaching report and the
Read all quote the same number:

```ts
weeklyVolume: {
  weeks: { weekStart: string; miles: number; runCount: number;
           weightedLoad: number; partial: boolean }[];   // ~25 (180d), Mon-anchored
  current4wkAvg: number;          // deduped, complete weeks only
  prior4wkAvg: number;
  rampRate: number;               // current4wkAvg / prior4wkAvg
  consistency: number;            // weeks ≥ 0.8 × current4wkAvg, of last 8
  percentile: number | null;      // current4wkAvg vs trailing 52wk, null if <26wk history
  longestWeek52: number;
}
```

`partial` matters: the current week is a stub on almost every run of the
nightly job, and comparing a Tuesday to a full week is the Trends bug all over
again. Exclude partial weeks from averages; surface them for display only.

One fetch decision to make: `percentile` and `longestWeek52` need a year, and
`compute-fitness-snapshot` currently reads 180 days (`cutoff180`). Two options
— widen that query to 400 days (it is one indexed read per athlete per night,
and the 2000-row limit already covers it), or read the athlete's own
distribution off `athlete_state.recent_blocks[].weekly_avg_miles` +
`year_ago.weekly_avg_miles`, which are already computed nightly and already
deduped. The second is cheaper and keeps one writer for long-range history;
the first keeps the predictor self-contained. Prefer the second unless
`athlete_state` freshness turns out to lag the snapshot job.

Consumers, each capped, none of them moving the point estimate directly:

| Today | Becomes |
|---|---|
| `volumeCredit = min(weeklyMiles/40, 1)` | `percentile`-based credit; fall back to the 40 mi/wk anchor when history < 26 weeks |
| Build gate `volumeTrend > 1.15` | `rampRate > 1.08` **and** `consistency ≥ 5/8`; same 0.5% unproven-improvement cap |
| `volumeTrend < 0.5` decay bump | `rampRate < 0.7` sustained ≥ 2 weeks |
| `lowVolume` trigger | `current4wkAvg < 15` (absolute floor) **or** below the athlete's own 20th percentile |
| `marathonVolumeFactor`, `marathonExtra` | unchanged formulas — marathon durability *is* absolute — but fed the corrected number |

One new guard the model does not have today: **a taper is not detraining.**
`rampRate < 1` with a goal race inside 3 weeks in `training_plans` must not
fire `lowVolume` or the decay bump. Right now a perfectly executed taper
reads as the athlete falling apart, in the week the prediction matters most.

#### Relationship to CTL/ATL/TSB (step 6)

This is not a competing design — it is the substrate. `aggregateWeeklyLoad`
already returns `weightedLoad` per week, so `weeklyVolume.weeks[].weightedLoad`
is a weekly-grain chronic-load series on day one, and `daily_training_load`
(July 31 design, `fitness-score-stress-load-design-2026-07-31.md`, still
unbuilt — only `20260731120000_add_stress_load_to_training_logs.sql` shipped)
becomes a *resolution upgrade* of an input the predictor already consumes,
rather than a parallel build with its own wiring.

That design's diagnosis still stands ("no fitness–fatigue model; the race-time
predictor does not consume load"), and CTL remains the principled end state:
CTL rising = chronic load building (improvement credit is defensible); CTL
falling = label-free detraining evidence; TSB deeply negative = the athlete is
training-fatigued and recent paces *understate* fitness. Note the conflict to
resolve first: the design doc's `ZONE_WEIGHTS` (mile 8.0) vs `workloadScore.ts`
(mile 5.0) vs `weeklyAnalytics.ts`'s `TYPE_FALLBACK_WEIGHTS` — three weight
tables, and `effortLoad` is a fourth candidate unit — it is computed and
persisted (`compute-workout-features/index.ts:544` →
`training_logs.effort_load`, migration `20260806140000`) but has no reader
anywhere. Pick one unit before building, so the density work isn't stranded
twice.

### 2.4 Efficiency score — built twice, consumed zero times

You have two independent efficiency implementations:

- `fitnessSignal.ts` — EF = speed/HR, easy/threshold/interval buckets,
  28d vs 84d, decoupling. Computed nightly into
  `athlete_state.fitness_signal`. **Known flaws, all documented:** raw pace
  + raw HR (hot blocks read as fitness loss — its own limitation #3), and
  within-bucket composition drift (solved by `toReferencePace` in
  `bandTrends`, never back-ported).
- `fast-segment-trends.ts` — `metersPerBeat`, `hrDriftBpm`,
  `recoveryHrDropBpm`, `decouplingPct`, on conditions-corrected paces.

Neither touches the predictor. This is the single highest-value connection
available, because efficiency is the only signal that can *see fitness change
between races*: the current model can only decay an anchor (capped 2%) or
grant capped improvement (0.5%) off volume trends. Pace-at-HR trending is
direct physiological evidence.

Plan: first implement the conditions-adjusted EF design
(`conditions-adjusted-fitness-model-2026-06-21.md` — decisions already
locked: adjust the pace side, down-weight rather than correct HR, condition
coverage feeds confidence) and back-port reference-pace normalization. Then
wire the resulting signal into the predictor as a **decay/build modifier
with caps**:

- EF improving ≥1.5% with medium+ confidence → raise the unproven-improvement
  cap from 0.5% to ~1.5% total, and tighten ranges one notch.
- EF declining ≥1.5% → allow decay past the 2% continuous-training cap (to
  ~3.5%) even without volume/layoff triggers, and add it as a fourth
  detraining trigger.
- Low confidence or thin clean data → no effect. Never move the point
  estimate directly off EF; it modulates the anchor-projection machinery.

### 2.5 Training in pace bands — mature module, not connected

`bandTrends` (MP / Threshold / 5K / 3K / Mile, anchor-normalized,
work-mile-weighted) is the most sophisticated training-analysis code in the
repo, and the predictor doesn't know it exists. Three uses, in order of value:

1. **Per-distance evidence states** (the May redesign's tight/moderate/wide
   that never shipped): band volume vs `SYSTEM_WORK_VOLUME_MILES` tells you
   whether the half prediction rests on real Threshold work or pure
   extrapolation. Drive per-distance range multipliers from it (the current
   `speedEvidenceMiles` / `qualityDensity` extras are a two-band
   approximation of this).
2. **Band trend as proven improvement**: a rising Threshold band trend line
   (reference-pace normalized, so menu changes don't fake it) is exactly the
   "measured hard-pace signal" the improvement cap comment defers to.
3. **Consolidation**: three band vocabularies now coexist
   (`EffortBucket` ×3, `zoneForPace` ×4, `PaceSystem`/`PaceBand` ×7/5).
   Standardize new predictor work on the fast-segment-trends vocabulary.

### 2.6 Mood — data finally exists; use it for range, not pace

The Aug 6 migration fixed the coverage collapse (60% → 0% of days) by adding
`daily_checkins.mood` (closed 6-value vocabulary). Nothing on the backend
reads it yet. The May audit's position still holds and matches your design
philosophy: mood **widens uncertainty, never moves the point estimate**.

- Subjective trend = trailing 14d of `daily_checkins.mood` +
  `training_logs.mood`: ≥50% of logged days tired/struggling → widen ranges
  ~1.2× (marathon-weighted) and add a corroborating detraining half-trigger.
- Mood improving alongside rising load = adaptation confirmation → permits
  (does not create) the EF/band improvement credits above.
- Gate on coverage: <5 mood days in the window → no effect. Coverage only
  became real this week, so this signal turns itself on as data accrues.

### 2.7 Biometrics — ingestion shipped Aug 4; three concrete uses

`daily_biometrics` (HRV, resting HR, lowest HR, sleep minutes, respiratory
rate; Garmin RMSSD + HealthKit SDNN) currently feeds only the recovery
ledger. For the predictor:

1. **Fitness-growth corroboration (your ask):** 28d resting-HR trend vs
   prior 28d, same-source only. RHR falling ≥3 bpm while volume holds is
   independent evidence of aerobic growth — pair it with the EF signal as a
   two-of-three vote (EF, band trend, RHR) to unlock the higher improvement
   cap. HRV slope is noisier; use it only as a veto (suppressed HRV streak →
   don't grant improvement credit this week).
2. **Acute-state honesty:** HRV suppressed >1 SD below the athlete's own 28d
   baseline for 5+ days, or RHR elevated ≥5 bpm → widen ranges; the engine
   is hotter than the tach says. Never shift the point.
3. **Unblock the `hr` stress tier:** the July 31 doc reserved
   `stress_source='hr'` for lack of an HR profile. That profile now exists —
   `athlete_settings.max_heart_rate` (no server reader today) +
   `daily_biometrics.resting_hr`. TRIMP-style load for pace-less runs makes
   the CTL curve (2.3) complete.

Two safety notes for any new reader: the SDNN-in-`hrv_rmssd` column overload
means every consumer must pin one `source` per comparison window, and
baselines must be per-athlete (the ingestion sanity bands are wide by
design).

## 3. Recommended architecture note

`FitnessPredictorService.swift` (110KB) mirrors the TS model 1:1 by hand.
Every upgrade above doubles in cost if parity is maintained. The server
already writes nightly snapshots per athlete; the app already reads them.
Recommendation: declare the server model authoritative now — iOS renders
`fitness_snapshots` and computes locally only as an offline fallback pinned
at v2 behavior. New signals (EF, bands, biometrics, mood) are server-only
data anyway; parity is already impossible for them. This decision alone
roughly halves the cost of everything below.

The mileage bugs in §2.3 make this decision urgent rather than merely
advisable. Bug A is duplicated **verbatim** in Swift —
`FitnessPredictorService.swift:663`:

```swift
let weeklyMiles = (recentMiles + priorMiles) / min(weeksSinceAnchor, 4.0)
```

— along with `volumeCredit` (line 706), the 1.15 build gate (721), the 0.5
decay bump (729), `marathonVolumeFactor` (977) and the `< 30` marathon extra
(1071). So every fix below is two fixes unless the parity question is settled
first. Bug B is worse for parity: it *cannot* be fixed identically, because
on-device HealthKit deduplication and `dedupBySourcePriority` over
`training_logs` rows are different operations over different data. Either
declare the server authoritative and fix mileage once, or accept that the app
and the server will keep reporting different weekly mileage to the same
athlete on the same day.

## 4. Implementation order

Each step is independently shippable; ordered by value ÷ effort.

0. **Fix the three weekly-mileage bugs** (2.3 A/B/C). Divide by the window,
   not the anchor age; run `extendedWorkouts` through `dedupBySourcePriority`;
   pass the 180-day array to `detectDetraining`. Hours of work, no new data,
   no new tables, no design decisions — and it corrects six existing branches
   of the model at once. Ship this before anything else, because every
   backtest below is measured against a volume signal that is currently wrong
   in a direction that varies with anchor age. **Backtest first to size the
   drift** — expect the fresh-anchor cases to move most.

1. **Unified `weeklyVolume` input** (2.3, "Recommended shape"). One
   Monday-anchored, deduped, partial-week-aware series built on
   `aggregateWeeklyLoad`; swap the six consumers to `rampRate` /
   `consistency` / `percentile` as tabled; add the taper guard. This is the
   step that turns mileage from a level into a shape, and it retires the two
   ad-hoc definitions inside `fitnessPrediction.ts`.

2. **Wire conditions-adjusted EF into the predictor** (2.4). Prereq: the
   already-designed EF fix. New `fitnessSignal` input on `PredictionInput`;
   modifier caps as specified. *This is the headline "can see fitness growth
   between races" feature.*
3. **Band-based evidence states + range multipliers** (2.5.1) using
   `analyzeFastSegmentTrends` output; retire `speedEvidenceMiles` /
   `qualityDensity` extras into it. Add race-agreement tightening (2.1.2).
4. **Mood as range modifier + detraining half-trigger** (2.6). Small,
   self-gating, first backend consumer of `daily_checkins`.
5. **Biometrics growth vote + acute widening** (2.7.1–2). Two-of-three
   improvement vote: EF, band trend, RHR.
6. **`daily_training_load` (CTL/ATL/TSB)** per the July 31 design, with the
   zone-weight conflict resolved and density-aware `effortLoad` as the unit —
   a resolution upgrade of step 1's `weeklyVolume.weeks[].weightedLoad`, not a
   parallel build. Then move the volume credit and build gate from weekly
   percentile to CTL, and add TSB-aware interpretation of the 14-day
   validation signal.
7. **Label-free stimulus refactor** (2.2) — replace `hardEffortTypes`
   gating with bout classification from laps; adopt density multiplier in
   place of the flat rest penalty.
8. **Non-standard race distances** (2.1.1); decide fate of dead
   `thresholdCapacity`.

Steps 0 and 1 are deliberately ahead of the EF work that was #1 in Rev 1.
EF is the higher-ceiling signal, but it is gated on an unshipped design, it
only exists for athletes with HR data, and its modifiers are computed
*relative to* volume-derived credit. Mileage is universal, already collected,
and currently wrong. Fix the ruler before adding instruments to it.

## 5. Guardrails

Keep the properties that make the current model trustworthy, and test them:

- No signal ever fabricates a prediction: every new input is a *modifier* on
  an anchor-derived estimate; `null` anchor still returns `null`.
- Every modifier is capped and its cap has a test (the existing
  `fitnessPrediction.test.ts` pattern; add cases per new signal: EF-up,
  EF-down, EF-low-confidence, mood-thin-coverage, HRV-veto, source-mixing).
- Additivity audit: EF decline + mood + biometrics widening must not
  compound past a global ceiling (suggest range ≤ 8%, decay ≤ 4% total).
- Backtest before shipping each step: replay the last 6 months of a few real
  athletes (the eval-cassette machinery exists) and diff snapshot series —
  the anti-ratchet and honesty fixes from July were all found this way.

Weekly mileage gets its own tests, because every one of these bugs was silent:

- **Anchor invariance.** Fix the logs; vary only the anchor — race 2 days ago,
  training anchor 5 days ago, nightly snapshot, race 20 weeks ago. Assert
  `weeklyMiles == milesInWindow / daysInWindow × 7` in every case. Today those
  four produce wildly different numbers off identical training; this one test
  catches Bug A on both the over- and under-stating sides.
- **Source dedup.** One run logged three times (Strava + HealthKit + voice,
  timestamps a few minutes apart) counts once. Assert against
  `dedupBySourcePriority`'s own fixtures so the two paths can't drift.
- **Cross-module agreement.** For the same athlete and date,
  `weeklyVolume.current4wkAvg` must equal `athlete_state.weekly_avg_miles`
  within 0.1 mi. One number, three readers — pin it in CI, not in review.
- **Partial weeks.** A Tuesday-truncated current week never enters an average
  and never trips a ramp or detraining threshold.
- **Taper.** Goal race 10 days out, mileage at 55% of the 4-week average →
  no `lowVolume` trigger, no decay bump.
- **Shape discrimination.** `10/10/10/10` and `20/20/0/0` produce the same
  `current4wkAvg` but different `consistency`, and only the first satisfies
  the build gate.
- **Ramp realism.** A 3-up/1-down block reads as building, not flat; a single
  20-mile long run does not by itself satisfy the build gate.
