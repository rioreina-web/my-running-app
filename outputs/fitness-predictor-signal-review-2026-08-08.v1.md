# Fitness Predictor — Signal Review & Upgrade Plan (Aug 2026)

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

## 1. What the predictor reads today

| Input | Source | Used for |
|---|---|---|
| Confirmed + detected races (all time) | `training_logs.race_result`, note parsing | Anchor (36wk trusted window, 16wk primary), lifetime PRs, speed evidence |
| Race-day laps | `running_workout_laps` | Flat-cool equivalent race pace (heat + Minetti grade, ±5% clamp) |
| Training anchors | `parsed_structure.equivalent_race_pace` (conf ≥ 0.6) | Blend/displace stale race anchor (50/50, 3% floor) |
| Laps, last 21d | `running_workout_laps` | Rest-aware hard-effort pool (heat/grade-normalized, rest penalty 0–2.5%) |
| Pace segments, last 30d | `training_logs.pace_segments` | Stimulus minutes (label-gated), 14-day validation signal (±2% band) |
| Volume | `training_logs` miles | Maintenance credit (40 mi/wk cap), marathon volume factor, detraining triggers |
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

### 2.3 Volume — a ratio where a curve should be

Volume today is three crude reads: recent-2wk vs prior-2wk miles (with known
window-coverage patches), a 40 mi/wk maintenance cap, and the marathon
floor. There is no longitudinal load model — the July 31 stress-load design
(`fitness-score-stress-load-design-2026-07-31.md`) diagnosed exactly this
("no fitness–fatigue model; the race-time predictor does not consume load")
and its Phase 2 (`daily_training_load` with CTL 42d / ATL 7d / TSB) is still
unbuilt.

CTL is the principled replacement for both the maintenance factor's volume
credit and the volume-trend build gate: CTL rising = chronic load building
(improvement credit is defensible); CTL falling = detraining evidence that
doesn't depend on labels; TSB deeply negative = the athlete is
training-fatigued and recent paces *understate* fitness (today the model
reads a heavy block as slow paces and can only be rescued by the ±2%
validation band). Note the design doc's `ZONE_WEIGHTS` (mile 8.0) conflicts
with `workloadScore.ts` (mile 5.0) — reconcile before building, and decide
whether `effortLoad` (density-aware, currently orphaned) is the unit, so the
density work isn't stranded twice.

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

## 4. Implementation order

Each step is independently shippable; ordered by value ÷ effort.

1. **Wire conditions-adjusted EF into the predictor** (2.4). Prereq: the
   already-designed EF fix. New `fitnessSignal` input on `PredictionInput`;
   modifier caps as specified. *This is the headline "can see fitness growth
   between races" feature.*
2. **Band-based evidence states + range multipliers** (2.5.1) using
   `analyzeFastSegmentTrends` output; retire `speedEvidenceMiles` /
   `qualityDensity` extras into it. Add race-agreement tightening (2.1.2).
3. **Mood as range modifier + detraining half-trigger** (2.6). Small,
   self-gating, first backend consumer of `daily_checkins`.
4. **Biometrics growth vote + acute widening** (2.7.1–2). Two-of-three
   improvement vote: EF, band trend, RHR.
5. **`daily_training_load` (CTL/ATL/TSB)** per the July 31 design, with the
   zone-weight conflict resolved and density-aware `effortLoad` as the unit;
   then swap the maintenance factor's volume credit and build gate to CTL,
   and add TSB-aware interpretation of the 14-day validation signal.
6. **Label-free stimulus refactor** (2.2) — replace `hardEffortTypes`
   gating with bout classification from laps; adopt density multiplier in
   place of the flat rest penalty.
7. **Non-standard race distances** (2.1.1); decide fate of dead
   `thresholdCapacity`.

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
