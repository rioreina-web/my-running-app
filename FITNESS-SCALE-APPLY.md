# FITNESS PREDICTOR — SCALE TO MANY RUNNERS · APPLY

2026-08-24. The model is good for one runner and unproven for everyone else.
This is the plan to change that. Source: audit session 2026-08-24 (findings in
§6). Sequenced by what blocks first — validation → cold start → generalization
→ coverage → population.

Total estimated engineering effort: **~9 focused days**. No new infrastructure spend.

**Effort is not the constraint; evidence is.** The build is ~2 weeks. Real
validation accrues at the rate races happen — 5 on file today — and G3 is gated
on athletes existing, not on work getting done. Two different milestones:
*usable and no longer absurd* (~2 weeks) and *validated* (months). Only the
first is a sprint.

---

## Status as of 2026-08-26 — read this first

**Done, tested, uncommitted, undeployed:** G0.1, G0.3, G0.5, G0.6. 1031 tests
pass in `_shared/`. Live parity re-verified after each change — published
integers match the pre-refactor row except where a new feature intentionally
moved them (floor, curve tilt), and those are logged below.

**Not started: G0.2, G0.4.** G0.4 (PR entry at onboarding, iOS) is the long
pole and the only remaining G0 item that needs a human at Xcode.

**The one finding that reframes everything below:** the model has a single
internal state variable, `estimated10KPace`. Every other distance — mile, 5K,
half, marathon — is `f(10K pace, distance)`, computed once at the very end via
`raceTime()`. There is no independent marathon estimate anywhere in the code.
Consequence: **the model's error at every distance is bounded below by its
error at 10K**, plus whatever the distance-specific conversion adds on top. A
marathon PR can bound the marathon *output* (via the floor) but cannot correct
the 10K *input* — only a 10K anchor does that. See §6.7.

### What to do next, in order

1. **G0.2 — `prediction_scores` v2.** Small, mechanical, unblocks real scoring
   at multiple horizons. Do this before G0.4 so PR-onboarding's effect is
   measurable the same day it ships.
2. **G0.4 — PR entry + confirmation at onboarding (iOS).** The long pole.
   Also the fix for the 10K-centricity finding above — it's the only lever
   that feeds a non-10K measurement into the model at all (via the floor;
   it still can't correct the internal 10K state — see §6.7).
3. **Persist `distanceCurve` on the snapshot + read it from
   `build-pace-profile`.** Not originally scoped as its own item, but §6.6
   below shows it's now required — the predictor and the pace zones
   disagree by 13–49s at half/marathon and will drift further as the curve
   gets more races to fit against. This is the one-source-of-truth bug
   class recurring a fourth time; close it before it's load-bearing.
4. **G1.1 (athlete-relative denominators)** is the next item with real
   generalization value and no dependency on G0.4. Can run in parallel with
   the iOS work if useful.

Everything else in the doc below is unchanged from the original plan except
where marked **DONE** or **REVISED**.

---

## 0 · The three problems, and the one idea that solves all of them

Going from one athlete to many is not mostly a modeling problem. It is:

1. **Cold start** — a defensible number on day one for someone with no race,
   no parsed structure, no history. Today they fall to
   `fastest workout × 0.95`, which the code's own comment measures at eleven
   minutes out.
2. **Generalization** — ~20 behavioural constants tuned on one 66 mpw sub-32
   10K runner. `weeklyMiles / 40` reads an 18 mpw athlete as detraining.
3. **Validation** — `prediction_scores` has one row and it belongs to the
   retired device writer. The shipped model has been scored zero times.

**The architectural idea: partial pooling, applied to every constant.**
`raceCurve.ts` already does this once — it fits a per-athlete Riegel exponent
and shrinks it toward `GENERIC_EXPONENT = 1.06` in proportion to its own
standard error (`EXPONENT_PRIOR_SD = 0.02`), with no minimum-races cliff. That
is the template. Population prior + individual deviation, weighted by evidence:

- a brand-new athlete gets the population value automatically (cold start),
- an athlete with history overrides it in proportion to evidence,
- and every athlete who joins improves the prior for everyone else.

Today those priors are borrowed from Riegel and coaching folklore. At N
athletes they get fitted from our own cohort. **Build the collection for that
now, even though it cannot be fitted yet** — cheap now, expensive to retrofit.

---

## 1 · Gate G0 — before any stranger sees a number  *(~4d)*

**Exit criteria:** leave-one-out replay produces an error table over the 5
existing races; a synthetic easy-runs-only athlete returns `null` rather than a
number; the 2026-08-17 replay shows the PR floor binding.

### G0.1 — Replay / backtest harness  *(1d)* — **DONE 2026-08-24**

`generateFitnessPrediction` is pure with an injectable `now`. That is the whole
asset; use it. New `scripts/replay-fitness.ts`.

For each historical date D: assemble `PredictionInput` from data visible at D,
run the predictor, store result + `diagnostics`. Three correctness rules or the
output is worthless:

- [ ] **Point-in-time by `created_at`, never `workout_date`.** Verified usable
      2026-08-24: `created_at` present on 307/307 rows and never precedes
      `workout_date`. The rule is necessary, not paranoid — median lag 0.36d
      but mean 9.4d, max 708d (the 2-year HealthKit backfill), and **106 of 307
      rows landed >2 days late**. A `workout_date` filter leaks the future on a
      third of the table.
- [ ] **Feed the replay its own snapshot chain**, not stored rows.
      `smoothFitnessPace` makes the model path-dependent — a one-shot
      prediction at D is a different estimator than the one we ship.
- [ ] **Persist `diagnostics` per replay step.** A backtest that stores only the
      output says *that* it was wrong, not *which stage*.

Output: error at horizons 1 / 7 / 14 / 28 / 56 days before each race.

**Result:** `scripts/replay-fitness.ts` + `_shared/fitnessInputs.ts` (assembly
extracted so production and replay share one fetch — a replay with its own
fetch measures a sibling model, not this one). Verified `created_at` usable on
307/307 training_logs, never precedes `workout_date`; necessary because 106 of
307 rows landed >2 days after ingest (max 708d, the HealthKit backfill).
First-ever scores: 2026-02-07 10K (no anchor yet) +2.07% at 1 day out;
2026-04-12 10K (9-week anchor) −1.08% vs neutral. 95/298 replayed steps
abstain. Production parity re-verified after every subsequent change in this
doc — see each item.

**Done when:** leave-one-out over the 5 existing races prints a table.

### G0.2 — `prediction_scores` v2  *(0.25d)*

- [ ] Horizon-parameterized (the current `LIMIT 1` scores only the day-before
      prediction; lead-time growth is the property a coach cares about).
- [ ] `neutral_actual_seconds` — store the conditions-normalized time at
      confirmation rather than normalizing read-side in three places.
- [ ] Keep `is_own_model`; add the real version column from G1.3.

### G0.3 — Wire `raceCurve.ts` into the predictor  *(0.5d)* — **DONE 2026-08-25, REVISED**

Four modules are fully built, fully tested, and imported by **nothing**:

```
                    prod importers    tests
athleteProfiles.ts        0             8
evidenceBlend.ts          0            12
expectedHr.ts             0            14
raceCurve.ts              0            15
```

`raceCurve.ts` is the generalization mechanism sitting unplugged.

- [ ] Replace the fixed-table conversion in `fitnessPrediction.ts` `raceTime()`
      with the fitted + shrunk exponent.
- [ ] **Same shape must flow to `derivePaceTableFromGoal`.** If the predictor
      personalizes the curve and the pace profile does not, zones and
      predictions diverge — the exact bug class the one-source-of-truth
      program has been closing all month.
- [ ] Persist exponent + shrinkage weight on `fitness_snapshots`.

**Done when:** profile 10K pace still equals snapshot 10K pace, and the
calibration athlete's marathon moves ~60s faster (era-clean half→marathon
ratio 2.0789 vs table 2.0940).

**Result — two problems found by building it, not by planning it:**

- **The naive implementation was wrong.** `RACE_RATIOS_TO_10K` is not a
  single-exponent curve — its implied exponent differs per pair (10K→mile
  1.0778, 10K→5K 1.0552, 10K→marathon 1.0623). Converting straight along a
  fitted power law would have moved every distance for every athlete, even at
  the generic exponent, under the banner of personalization. Fixed: the curve
  now **tilts** the table (`T_table(D) · (D/D_10K)^(b_fitted − b_generic)`),
  not replaces it. Generic fit ⇒ tilt exactly 0 ⇒ bit-identical to today.
  Locked in by test (`no curve evidence → predictions are bit-identical to
  the ratio table`).
- **The shrinkage was overconfident at low degrees of freedom.** With the
  4/12 race excluded (see below), 4 points through 3 parameters (intercept,
  slope, drift) fit almost exactly by construction — SE landed at ±0.0008,
  handing the fit 100% weight and moving the marathon 91s. That's an
  overfitting signature, not precision, and the harness cannot currently
  catch it (§6.7 — both scoreable races are 10Ks, the curve's invariant
  point). Extended `raceCurve.ts`'s existing dof=0 guard to dof≤1: falls back
  to the prior scale, landing the same fit at 50% weight, marathon change
  −49s instead of −91s.
- **`SHAPE_MAX_CORRECTION_PCT = 0.025`** excludes any race from the FIT (not
  the anchor, not the PR floor) if it needs a conditions correction above
  2.5% — the shortest race sits at the end of the log-distance axis and
  therefore carries the most leverage on the slope, and the heat model that
  correction runs through is independently known to over-credit ~2×.
  Sensitivity check across input choices moved the marathon 2:25:49 →
  2:28:59 depending on raw-vs-neutral alone.
- **Live effect, post-fix:** 10K unchanged (the origin), half −13s, marathon
  −49s. Provisional, not yet evidence-backed per §6.7 above.
- **Not yet done, and now required:** persist `distanceCurve` on
  `fitness_snapshots` and read it from `build-pace-profile`. Currently the
  predictor and the pace-zone ladder disagree by 13–49s and will diverge
  further as more races accumulate — the one-source-of-truth bug class
  recurring a fourth time. Promoted to next-action #3 above.

### G0.4 — PR entry + confirmation at onboarding  *(1.5d, iOS + server)* — **the long pole**

The only fitness input requiring no device, no sync, and no 28-day wait.
Delivers level, shape, and floor in 60 seconds. Extends
`RACE-CONFIRM-ONBOARDING-APPLY.md`.

- [ ] Write `race_results.conditions` at confirmation (null on every row today).
- [ ] **Normalize once at confirmation and store the neutral time.** Kills the
      >180-day `weatherByDate` window gap for good — a new athlete's imported
      race is usually older than 180 days and currently anchors RAW.
- [ ] Hand-entered PRs with no conditions: ceiling-eligible, shape-ineligible.

### G0.5 — PR plausibility floor  *(0.5d)* — **DONE 2026-08-24**

New pure module `_shared/prFloor.ts`. Every existing guard is relative to the
*anchor*; nothing is relative to the PR, so the estimate can walk arbitrarily
far below a lifetime best while the athlete runs 70 mpw.

```
maxDecline = 0.04                                  base: volume held + quality
           + min(1 - volRatio, 1) * 0.12           volume shortfall vs PR-era
           + (0.10 - qualityDensity) * 0.25        when density < 10%
           + yearsSincePR * 0.008                  stand-in for age-grading
           capped at 0.20
```

- [ ] **Same-distance PR only.** Never the best cross-distance equivalent — see
      §6.3, that construction is a permanent ratchet.
- [ ] Confirmed + conditions-normalized PRs only.
- [ ] **A race always beats the floor.** Bounds inference, never evidence.
- [ ] Append to `data_source` and record inputs in `diagnostics` when it binds.

**Done when:** replay of 2026-08-17 caps 2:36:55 → 2:29:00; today's 32:00
(+2.13% off PR) passes untouched.

**Result:** `_shared/prFloor.ts` + `prFloor.test.ts`, 10 tests including the
2:37 regression directly. Actual clamp on the incident: 2:36:55 → **2:30:13**
(7 min removed; the honest answer was ~2:29, so this makes it not-absurd, not
correct — the stated job of a guard rail). Today's 32:00 passes untouched —
the marathon sits 55s inside its own floor. The age term
(`FLOOR_AGE_PER_YEAR`) is doing more of the work than intended on a 1.6-year
PR; flagged in the module header as needing real age-grading (WMA factors)
before trusting a floor off a PR older than ~3 years.

### G0.6 — Real abstention  *(0.25d)* — **DONE 2026-08-24**

- [ ] Delete the `fastest workout × 0.95` fallback in `fitnessPrediction.ts`.
- [ ] Return `null`, or a low tier with an explicit ask ("tell me a recent race
      or log a hard session").

**Done when:** a synthetic easy-runs-only athlete returns `null`.

**Result:** rung deleted, guarded by test. Unexpected second-order effect
caught only because the harness replays a full chain rather than scoring
single predictions: deleting the rung also **improved** a nearby prediction
it wasn't directly responsible for — Feb 2026's 1-day-out error went +3.35% →
+2.07% — because the deleted guesses had been seeding the curve's damping
prior for days after they fired. A backtest that scored one-shot predictions
would not have shown this.

---

## 2 · Gate G1 — generalization  *(~2.5d)*

**Exit criteria:** no absolute mileage/duration threshold remains in the
prediction path; range calibration measured against G0.1.

### G1.1 — Athlete-relative denominators  *(1d)*

Every absolute threshold asserts all runners are our size:

| today | replace with |
|---|---|
| `weeklyMiles / 40` | athlete's own 8-week median volume |
| `weeklyStimulusMinutes / 50` | own quality baseline |
| build gate `>= 30 min` | own baseline |
| `MARA_READY_LONGRUN_MILES = 20` | relative to own longest 16-week run |
| marathon shade below 40 mpw | own volume percentile |

Fall back to a population value keyed on `experience_level` when history is
thin. This is the single change that most affects whether the model works for
people unlike the calibration athlete.

### G1.2 — Calibrate the ranges  *(0.5d)*

`RANGE_FRACTION[tier]` plus additive fudges is asserted, never estimated. The
band is what athletes act on.

- [ ] Measure coverage against G0.1: what fraction of actuals land inside ±range?
- [ ] Target 68–80%. Adjust `RANGE_FRACTION` to hit it, per tier.

### G1.3 — Real model version  *(0.25d)*

`· v2` is a substring in a text column. The snapshot series moves on deploy
dates, so athlete change and model change are currently inseparable.

- [ ] `model_version` column on `fitness_snapshots`, written from a constant.
- [ ] Backfill historical rows from `data_source` heuristics, labeled as such.

### G1.4 — Invert the asymmetry by training age  *(0.75d)*

"A race is a floor you must argue with" is built for an athlete near their
ceiling. A 55-minute 10K runner improves ~10%/year, which violates both the
0.5% unproven-improvement cap and the 2% continuous-training decay cap. For a
rapidly improving runner a four-month-old race genuinely *is* stale and the
model will be systematically slow.

- [ ] Scale the fast-direction caps by training age / `experience_level`.
- [ ] Leave the slow direction alone — the EF gate's asymmetry stays.

---

## 3 · Gate G2 — coverage  *(~2.5d)*

**Exit criteria:** the synthetic cohort suite passes for every archetype, where
"passes" means a correct number OR an honest abstention — never a wrong number.

### G2.1 — Graceful degradation matrix  *(1d)*

The model assumes GPS + laps + HR + track-style quality + hot climate + 60 mpw.

| missing | breaks | required behavior |
|---|---|---|
| HR | EF gate, drift weighting | inert gate + **wider band** |
| laps | `lapHardnessCap`, quality density | segments only, wider band |
| `parsed_structure` | the entire zone signal | abstain, don't fall through |
| treadmill / no GPS | pace + grade | flag, exclude from anchor |

**Rule:** a missing input widens the band; it never silently changes the number.

### G2.2 — Non-rep quality  *(1d)*

`work_rep` assumes track-style structure. Progression runs, fartlek, and hilly
steady are real quality the zone signal cannot see today.

### G2.3 — Synthetic cohort suite  *(0.5d — partly built)*

**Partly built already**: `athleteProfiles.ts` (8 tests, commit "Synthetic
athlete profiles — and the bug they caught immediately", 2026-08-17) is this
work, unplugged with the other three modules. Extend it rather than start over.

The only way to test the cold start before beta — production has *never* run
without a race anchor (89 snapshots, 100% `race (10K)`).

Archetypes with known ground-truth fitness: 45-min 10K at 20 mpw · 3:30
marathoner at 30 mpw · 5K specialist with no long runs · masters runner ·
injury-interrupted · easy-runs-only. Emit synthetic logs including
`parsed_structure` blocks and weather; compare to ground truth.

---

## 4 · Phase G3 — the population model  *(gated on N, not on time)*

- [ ] **Store `(dose, response)` pairs per block from day one.** `recent_blocks`
      already holds the dose side (6 blocks, 43.6–65.7 mpw). The response side
      is empty.
- [ ] **Benchmark session protocol** — one repeatable effort per block. Breaks
      the reverse-causality loop, because today's candidate response measure
      (EF) is made of the same runs as the dose. ~30 min/month per athlete.
- [ ] **Fit priors from our own cohort**: generic exponent, decay rates by
      training age, maintenance weights.
- [ ] **Per-athlete heat calibration**, shrunk toward population — regress
      neutral-pace residuals on dew point. This is what
      `patterns.heat_sensitivity` currently only *pretends* to be (§6.2).
- [ ] **Dose-response with partial pooling.** Not identifiable per-athlete;
      identifiable across a cohort.

---

## 5 · Ops track — when load arrives, not now  *(~3d)*

"Good for a lot of runners" includes "works reliably for a lot of runners," and
the incident history says that is the harder half.

- [ ] **LLM cost/throughput.** `parse-workout-structure` is one LLM call per
      workout. 1,000 athletes × 5 runs/wk = 20k+ calls/wk. A credit outage
      already killed the pipeline at n=1, masked as a generic 502.
- [ ] **Cron isolation.** Jobs running longer than their interval saturated
      Postgres and 401'd every user-JWT edge function — full outage at one
      athlete. Scales badly by construction.
- [ ] **Deploy drift.** 41/55 functions once ran stale code (worst 112d). The
      content-drift CI check exists; wire it to block.
- [ ] **Absurdity alarm.** Flag any prediction outside the PR floor, or moving
      >3% day-over-day. Would have caught the 2:37 the morning it happened.

### Monitoring once there are runners

Not a single MAPE. Error distributions **per cohort** — beginner/advanced,
race/no-race, HR/no-HR, hot/cold climate. The aggregate hides exactly the
groups we are failing. Plus abstention rate by cohort, so "40% of beginners get
low confidence" is a decision we make rather than discover.

---

## 6 · Findings from the 2026-08-24 audit (expensive to rediscover)

**6.1 — The four orphaned modules.** 49 tests, zero production importers. See
G0.3. `raceCurve.ts`'s fitted exponents (half b=1.051, marathon b=1.053) were
independently reproduced from raw race data during the audit — the math is
right, it is only unplugged.

**6.2 — `patterns.heat_sensitivity` is a mirror, not a measurement.** Its
evidence string ("8 hot runs averaged 3.7% heat slowdown") averages
`heat_adjustment_pct` — the adjustment `pace-heat-adjustment.ts` *applied*
(`athlete-state.ts:1684`). Feeding it back teaches the model its own prior and
reports the agreement as evidence. Same trap for `fitness_vs_6mo_ago_*` and
anything downstream of `fitness_snapshot_id`: `athlete_state` already contains
the predictor's output. **Rule: the predictor may consume measurements, never
reflections.** `field_provenance` is the right gate and nothing checks it.

**6.3 — The PR floor ratchet.** A floor built from the best *cross-distance*
10K-equivalent gives 29:55 for the calibration athlete — driven by a 5K from a
different era carrying a suspect 41s heat credit. That floor sits faster than
they have ever run at 10K and would pin today's correct 32:00 as "implausibly
slow." Cross-distance conversion always flatters. Same-distance only.

**6.4 — Era contamination in shape fitting.** PR pairs 13 months apart charge
fitness change to shape: the naive all-PR marathon ratio overstates the effect
by ~53s vs the era-clean half→marathon pair. Gate pairs to ~16 weeks.

**6.5 — The predictor reads one column of the brain.**
`compute-fitness-snapshot/index.ts:299` selects `fitness_signal` and nothing
else, while `athlete_state` carries `experience_level`, `execution`
(fade_pct / hr_drift_pct per session), `data_gaps`, and `recent_blocks`.
`trainingZoneSignal.ts` says in its own header that `hrDrift` is "reported, not
applied" — the next stage was never written. Two sessions at 5:18 and 5:20 with
8.3% vs −0.6% HR drift are currently weighted identically.

**6.6 — Tuning on the test point.** The 2:37 fix was verified as "raw model
309.26 vs prior 309.03 — the new code agrees with the old answer." Agreement
with a prior belief is confirmation, not validation. This is the habit G0.1
exists to replace.

---

**6.6 — `raceCurve.ts` and `build-pace-profile` now disagree, the same seam
as before.** Live delta after G0.3: half −13s, marathon −49s between the
predictor's curve-tilted numbers and the profile's table-only ladder. The
divergence grows every time a new race gives the fit more evidence. This is
the identical failure mode `FITNESS-MODEL-APPLY.md`'s one-source-of-truth
program closed three times already (anchor selection, heat normalization,
pace ladder derivation) — reopened by this session's own change and not yet
reclosed. Fix is promoted to next-action #3 at the top of this doc.

**6.7 — The model has one internal number, and every distance inherits its
error.** `estimated10KPace` is the sole state variable through anchor
selection, decay, the training blend, and curve damping — 24 references in
`fitnessPrediction.ts`. Mile, 5K, half, and marathon are each `f(10K pace,
distance)`, computed once at the end via `raceTime()`. No independent
estimate for any other distance exists anywhere in the pipeline.

Two consequences, one helpful and one not:

- The PR floor and endurance shading can still bound a non-10K OUTPUT (as
  designed in G0.5), but nothing today can correct the 10K INPUT except a
  10K anchor. A marathon PR only ever clamps from outside.
- It's why `raceCurve`'s dof-guard defect (§ G0.3 above) is invisible to the
  replay harness: `RACE_KM.tenK` is the curve's conversion origin, so the
  tilt is identically 1.0 there by construction, and both of the athlete's
  scoreable races are 10Ks. **The harness cannot see error in the one
  parameter most likely to be wrong until a half or marathon is on file to
  score against.** Not a bug in the harness — a real coverage hole that only
  G0.4 (which gives the athlete a place to enter a non-10K PR) or waiting
  for a non-10K race can close.

## 7 · Constants — asserted vs fitted

92 distinct numeric literals in `fitnessPrediction.ts`; ~20 are behavioural.
Provenance today:

| constant | value | provenance |
|---|---|---|
| `maintenanceFactor` weights | 0.65 / 0.35 | **asserted** |
| volume credit denominator | 40 mi/wk | **asserted** → G1.1 |
| stimulus denominator | 50 min/wk | **asserted** → G1.1 |
| base decay | 0.003/wk | **asserted** |
| unproven-improvement cap | 0.5% | **asserted** → G1.4 |
| continuous-training decay cap | 2% | **asserted** → G1.4 |
| `PLAUSIBLE_RATIO_MIN/MAX` | 0.86 / 1.10 | **asserted** |
| `LAP_HARDNESS_FACTOR` | 1.12 | derived from MP ratio + tolerance |
| `MARA_MAX_ENDURANCE_PENALTY` | 0.12 | **asserted** (calibration dial) |
| `RANGE_FRACTION[tier]` | per tier | **asserted** → G1.2 |
| `GENERIC_EXPONENT` | 1.06 | population (Riegel) → G3 refit |
| `EXPONENT_PRIOR_SD` | 0.02 | prior spread, stated → G3 refit |
| `THRESHOLD_TO_10K` | 0.95 | **asserted** (marked tunable) |
| heat model | — | **measured, known to over-credit ~2×** |

Everything marked **asserted** is currently unfalsifiable. G0.1 is what makes
each one a measurement instead of an argument.

---

## 8b · Distance-native compute (2026-08-27, follow-up to G0.3)

Raised directly by the user: "I don't want this built around 10K" + "for a
lot of people it's going to be half/marathon" — which is also just the
calibration athlete's own persona (3:28 marathon PB chasing a 3:16 BQ).
Scoped via AskUserQuestion to "the predictor's core representation," not a
product-wide rebuild.

**The math clarified the actual bug before any code changed.** Decay/blend/
damping are pure multiplicative scalars — operating on them in "10K space"
vs "native space" gives IDENTICAL final numbers, provided the conversion
basis is consistent. So a full state-variable rename would have changed
zero outputs on its own. The three places conversion basis was NOT
consistent, found by working through the algebra:

1. **Anchor ranking used the generic ratio table, not the athlete's fitted
   curve** — `convertPace()` in `scoredRaces` ran before `distanceCurve` was
   even computed. A marathoner's races got ranked against each other using
   population averages, not their own shape.
2. **The additive 50/50 blends** (training-displaces-stale-race,
   training-plus-fitness-profile) add two paces together — the one operation
   where conversion order actually matters, and both operands inherited (1).
3. **`trainingZoneSignal.ts`'s `buildFitnessCurve` priced every training
   session against a curve built from the generic table**, regardless of the
   athlete's fitted exponent — a marathoner's threshold work was judged
   against a 10K-typical fatigue curve.

**Fixed**, verified by 4 new tests directly (`trainingZoneSignal.test.ts`):
- `distanceCurve`/`curveTilt` computation moved from just-before-`raceTime()`
  to immediately after `detectedRaces` is finalized — available in time for
  ranking.
- `convertPace()` and `detectTrainingAnchors()` take an optional `curveTilt`,
  default 0 (bit-identical to prior behavior for every existing caller until
  updated).
- `buildFitnessCurve` takes `(seedPaceSecPerMile, seedDistanceKey = "tenK",
  curveTilt = 0)` — same tilt mechanism as `raceTime()`, so a marathon-seeded
  curve is genuinely shaped like a marathon curve, not a relabeled 10K one.
  Test: seeding 550 s/mi as marathon vs. mislabeling it as a 10K moves the
  curve's own MP point by 52s — mislabeling is not free.
- `ZoneEstimate.tenKEquivalent` / `WeightedZoneSignal.tenKPace` renamed to
  `equivalentPace` (+ `distanceKey` carried through) — the old names claimed
  a 10K statement when the value was usually the anchor's real distance.

**What did NOT change, deliberately:** `estimated10KPace` stays a
10K-denominated number for decay/damping/persistence. This is correct, not
a leftover — once ranking and blending are curve-correct, 10K is a legitimate
stable comparison CURRENCY across days (the same way a thermometer reporting
in Celsius doesn't claim bodies are "naturally" Celsius). The bug was never
"10K is used as a unit," it was "10K is the ONLY thing computed toward,
using the wrong conversion basis at two specific junctions." Confirmed by
the math: the fix is multiplicatively equivalent to fully re-deriving the
state in native-distance space, without the schema/persistence-layer risk
that a real rename would have carried.

**Cannot be end-to-end verified against this athlete's data.** Both
scoreable races are 10Ks, so neither bug (1) nor (2) had anything to
disambiguate — replay is byte-identical pre/post. This is the same coverage
hole named in §6.7: closes only when a non-10K race lands (G0.4, or time).

## 8 · Ordering constraint

```
G0.1 replay ──┬──> G0.5 PR floor ──> G1.2 ranges ──> G1.1 constants
              ├──> G0.3 raceCurve
              └──> G2.3 synthetic cohort ──> G2.1 degradation
G0.4 PR onboarding ──> G0.5 (needs confirmed + normalized PRs)
ops track: parallel throughout
```

**G0.1 gates everything.** Every phase after it is a tuning exercise, and
tuning without scoring is how the 2:37 happened.
