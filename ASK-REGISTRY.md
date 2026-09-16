# The analyzer registry — every training principle, every analytic

*Authored 2026-08-05. Companion to `ASK-APPLY.md` (architecture) and
`ask-prototype.html` (surface).*

This is the scope document. `ASK-APPLY.md` says *how* Ask works;
this says *what it can answer*, and — more usefully — what it can answer
**today** versus what needs building.

---

## 0 · The headline

A 40-concept audit of the codebase against the standard endurance-training
analytics space returned:

| | Count | What it means |
|---|---|---|
| **Computed today** | **29** | Named function or column exists. |
| **Partial** | **8** | Some of it exists; usually the combining step is missing. |
| **Absent, data OK** | **2** | Not computed, but the schema supports building it. |
| **Absent, no data** | **1** | Not captured at all. |

*(Those 40 concepts expand into 50 analyzers in §2 — some concepts split, e.g.
"sleep trends" becomes a self-reported analyzer that ships today and a
device-biometric one that is blocked. §3 has the analyzer-level totals.)*

**Ask is not an analytics project. It is a distribution project.** The
overwhelming majority of this already runs — inside `athlete_state` builders,
inside rule evaluators, inside `fitnessPrediction` — and never reaches the
athlete as an answerable question. Ask is the surface that exposes it.

Two findings worth acting on independently of Ask:

1. **Four recovery concepts are blocked on one unwritten branch.**
   `daily_biometrics` is migrated, RLS'd, indexed — and empty, because
   `vital-webhook` has no daily-sleep branch. `detectorsC` and the recovery
   surfaces downstream are already scaffolded and returning all-hidden by
   design. HRV trend, resting-HR trend, sleep-duration trend and the
   overnight factor of the readiness composite are **one integration away,
   not four builds.**
2. **Five "missing" analytics are one line of arithmetic each.** Long-run
   share, polarization index, race-pace specificity, hard-day spacing
   variance, and consistency streak all have both operands persisted. These
   are the cheapest analytics in the product's history.

---

## 1 · Status vocabulary

| Status | Meaning | Cost |
|---|---|---|
| **WRAP** | Math exists and is tested. The analyzer is a fact-line adapter over it. | ~40 LOC + a registry line |
| **JOIN** | Both operands persisted. Needs the combining expression. | ~40 LOC + ~10 LOC of math |
| **BUILD** | New math. Data in the schema supports it. | A real module + tests |
| **BLOCKED** | Data isn't captured. Ingest first. | Pipeline work, then WRAP |

---

## 2 · The registry, by training principle

### I · Progressive overload — *is the load rising at a rate I can absorb?*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `volume_trend` | How has my mileage moved? | `weeklyAnalytics.ts:aggregateWeeklyLoad` · `buildLoadMetrics` rolling 7/28d | WRAP |
| `load_balance` | Am I ramping too fast? | `weeklyAnalytics.ts:calculateACWR` · `workout_features.acwr` | WRAP |
| `monotony_strain` | Is my training too samey? | `workout_features.monotony_7d` / `.strain_7d` | WRAP |
| `session_load` | How hard was that, really? | `workloadScore.ts:sessionLoadFromIntensity` · `training_logs.stress_load` | WRAP |
| `ramp_rate` | Is this week's jump normal for me? | `ComputedMetrics.volumeChangePct` · `LoadDistribution.load_trend` | WRAP |
| `long_run_share` | Is my long run too big a slice of the week? | `longRunMiles` ÷ `totalMiles` — **both persisted, never divided** | JOIN |

### II · Intensity distribution — *is the mix right?*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `zone_minutes` | Where did my time actually go? | `workout_features.{easy,moderate,threshold,hard}_seconds` → `zone_pct_7d` | WRAP |
| `quality_share` | How much of my week is quality? | `quality-volume.ts:qualityMilesForLog` (MP-anchored) | WRAP |
| `easy_discipline` | Are my easy days actually easy? | `athlete-state.ts` pattern `easy_discipline` (easy < 65%) | WRAP |
| `polarization` | Am I polarized, pyramidal, or muddled? | `zone_pct_7d` exists; `assessQualityVolume` only checks 80/20 on *run counts*. Needs a named distribution index over minutes. | JOIN |
| `system_volume` | Am I getting enough volume at LT / MP / 5K? | `fast-segment-trends.ts:SystemVolume` vs `SYSTEM_WORK_VOLUME_MILES` | WRAP |

### III · Specificity — *is my training the race I'm running?*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `race_pace_specificity` | How much of my work is at goal pace? | `active_goals[].gap_vs_current_sec_per_mile` and zone volume both exist but are **never joined** | JOIN |
| `long_run_progression` | Are my long runs getting race-ready? | `fitnessPrediction.ts:longRunReadiness` gives a *level*; the trend over the block is missing | JOIN |
| `terrain_match` | Does my terrain match the course? | `running_workout_laps.total_elevation_gain` · `pace-grade-adjustment.ts` | BUILD |
| `race_sim` | Have I rehearsed the demand? | Long runs with embedded MP/HMP work, from `parsed_structure` | BUILD |

### IV · Durability — *does it hold at the end?*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `fade` | Do I fade in the back half of long runs? | `signature/types.ts:AthleteDay.longRunFadeSecPerMile` · `athlete_state.execution[].fade_pct` | WRAP |
| `decoupling` | Is my HR drifting less than it used to? | `fitnessSignal.ts:sessionDecouplingPct` · `DecouplingTrend` · per-second `trends-insights/streams.ts` | WRAP |
| `durability_curve` | How does my pace hold past 90 minutes? | `hr_drift_pct` + fade exist per session; a duration-indexed curve does not | BUILD |

### V · Adaptation — *is any of this working?*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `zone_trend` | Is my LT / MP / 5K pace improving? | `fast-segment-trends.ts:analyzeFastSegmentTrends` → `SystemTrend`, conditions-neutralized | WRAP |
| `efficiency` | Metres per heartbeat — moving? | `fitnessSignal.ts:EfficiencyTrend` · `workout_features.hr_pace_efficiency` | WRAP |
| `race_projection` | What am I on track to run? | `fitnessPrediction.ts:generateFitnessPrediction` + `confidence_tier` | WRAP |
| `block_compare` | Is this block better than the last one? | `builders/buildBlocks.ts` (6×28d) · `rules/buildVsLastCycle.ts` | WRAP |
| `detraining` | What did that layoff cost me? | `fitnessPrediction.ts:detectDetraining` · ACWR < 0.6 band | WRAP |
| `velocity_duration` | What's my critical speed? | Distance-time data is in `running_workout_laps` + `external_streams`, unindexed. **No CS/D' model anywhere.** | BUILD |

### VI · Recovery — *am I absorbing it?*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `readiness` | Push or pull today? | `builders/buildReadiness.ts` → `push\|hold\|pull` + drivers | WRAP |
| `hard_day_spacing` | Am I leaving enough between hard days? | `recovery_read.avg_days_between_hard` · `workout_features.hours_since_last_hard` | WRAP |
| `rpe_trend` | Is the same work feeling harder? | `extract-rpe` → `training_logs.felt_rpe` · `LifeContext.avg_rpe_7d` | WRAP |
| `rpe_vs_pace` | Effort up, pace flat — or the reverse? | `felt_rpe` and zone pace both persisted; never correlated | JOIN |
| `sleep_self_report` | Does rough sleep show up in my running? | `buildLifeContext.ts:LifeContext.sleep` · `daily_checkins.sleep_quality` | WRAP |
| `hr_zones` | What are my HR zones doing? | `athlete_settings.max_heart_rate` + Swift `rr_zones(maxHR:)` are **client-side only**; no server HR-zone model, no HR-reserve/Karvonen anywhere | BUILD |
| `hrv_trend` | What is my HRV doing? | `daily_biometrics.hrv_rmssd` — **table empty, no writer** | BLOCKED |
| `overnight_recovery` | Sleep duration, resting HR, overnight load | `daily_biometrics.{sleep_total_min,resting_hr,hr_lowest}` — **same blocker** | BLOCKED |

### VII · Consistency — *am I actually doing it?*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `compliance` | Am I hitting the plan? | `weeklyAnalytics.ts:calculateCompliance` + `calculatePaceCompliance` | WRAP |
| `missed_sessions` | What have I been skipping? | `rules/missedWorkouts.ts` · `ComputedMetrics.restDays` | WRAP |
| `streak` | How consistent have I been? | Run dates persisted; **no streak counter exists in TS or Swift** | JOIN |
| `gap_analysis` | What do my breaks look like? | `detectDetraining` covers the fitness cost; gap *pattern* is new | BUILD |

### VIII · Periodization — *does this block have a shape?*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `phase` | What phase am I in? | `builders/buildTrajectory.ts:derivePhase` → base/build/peak/recovery/off_season | WRAP |
| `week_shape` | Is my week structured, or just seven runs? | `signature/grammar.ts` `b2b_quality` + hard-day spacing exist; **no day-role or hard-easy alternation model** | JOIN |
| `taper` | Am I tapering correctly? | "Taper" is a plan label only — `derivePhase` never returns it, no detector exists. `scheduled_workouts` + volume history support one. | BUILD |

### IX · Conditions — *was it me, or was it the day?*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `heat_normalize` | Was that pace real, or the dew point? | `pace-heat-adjustment.ts:adjustPace` · persisted per lap | WRAP |
| `heat_season` | What has this summer cost me? | Same engine, aggregated across the block | WRAP |
| `grade_normalize` | How much did the hills cost? | `pace-grade-adjustment.ts:gradeAdjustRun` (Minetti) | WRAP |
| `conditions_log` | What were the conditions that day? | `fetch-workout-weather` → `training_logs.weather_actual` | WRAP |

### X · The body — *what is it telling me?*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `niggle_timeline` | Where has the calf shown up? | `bodyVocabulary.ts:findBodyAreaMentions` · `body_mentions` · `niggle_recurrence` | WRAP |
| `niggle_vs_load` | Do my niggles follow load spikes? | `rules/loadSpikePlusInjury.ts` · `injury-early-warning` · `ml-service/app/injury_risk.py` | WRAP |
| `mood_trend` | How has my mood moved? | `builders/buildMoodTrend.ts` | WRAP |
| `mood_vs_load` | Does my mood track the load? | `athlete-state.ts` `life_load` pattern · `signature/grammar.ts` outcomes | WRAP |

### XI · Comparison — *the cross-cutting lens*

| Analyzer | The question | Source | Status |
|---|---|---|---|
| `compare_session` | How does this session stack up? | `workoutComparison.ts:findBestComparison` / `compareWorkouts` | WRAP |
| `segmentation` | What did this session break into? | `workoutSegmentation.ts:segmentFromLaps` | WRAP |
| `best_sessions` | My best LT sessions this year | `fast-segment-trends.ts` ranked over `KeySessionMetrics` | JOIN |

---

## 3 · Totals

**50 analyzers.** 33 WRAP · 8 JOIN · 7 BUILD · 2 BLOCKED.

| Principle | Analyzers | WRAP | JOIN | BUILD | BLOCKED |
|---|---|---|---|---|---|
| I · Progressive overload | 6 | 5 | 1 | — | — |
| II · Intensity distribution | 5 | 4 | 1 | — | — |
| III · Specificity | 4 | — | 2 | 2 | — |
| IV · Durability | 3 | 2 | — | 1 | — |
| V · Adaptation | 6 | 5 | — | 1 | — |
| VI · Recovery | 8 | 4 | 1 | 1 | 2 |
| VII · Consistency | 4 | 2 | 1 | 1 | — |
| VIII · Periodization | 3 | 1 | 1 | 1 | — |
| IX · Conditions | 4 | 4 | — | — | — |
| X · The body | 4 | 4 | — | — | — |
| XI · Comparison | 3 | 2 | 1 | — | — |
| **Total** | **50** | **33** | **8** | **7** | **2** |

**82% of the registry is reachable without writing new analytics** — and the
JOIN tier is a day's work, not a quarter's.

The two weakest principles are worth naming. **Specificity has no WRAP
analyzer at all** — the product knows the goal and knows the training, and has
never once joined them. **Periodization is one WRAP deep** (`phase`), which is
why the block never quite reads as a block. If you want one thing to fix that
isn't on the phasing critical path, it's specificity: `race_pace_specificity`
is a JOIN, and it answers the single most load-bearing question a
goal-chasing runner has.

---

## 4 · Revised phasing

`ASK-APPLY.md` §8 phased on architecture. This re-phases on **coverage**,
which is the more honest axis now that the registry is real.

| Phase | Ships | Analyzers | Why here |
|---|---|---|---|
| **A** | Registry scaffold, `narration-guard.ts` lift, `ask` endpoint, chips only, behind a flag | 3 pilots — `compare_session`, `zone_trend`, `load_balance` | Proves the contract on the three with the deepest math. Chips can't be misrouted, so A can't embarrass you. |
| **B** | Layer 0 router, free text, ambiguity chips, prose fallthrough, `analysis_queries` logging | +15 WRAP, one from each principle group | Breadth before depth. The rail must read as complete rather than lopsided toward pace, or the vocabulary doesn't land. |
| **C** | Charts, follow-up chips, contextual rail, semantic cache | +15 WRAP (the remainder) | Full WRAP coverage — 33 analyzers. This is the version that feels like the product you described. |
| **D** | The arithmetic tier | 8 JOIN — `long_run_share`, `polarization`, `race_pace_specificity`, `long_run_progression`, `rpe_vs_pace`, `streak`, `week_shape`, `best_sessions` | Cheapest analytics in the product's history. Consider pulling `race_pace_specificity` forward into B — see §3. |
| **E** | New math | 7 BUILD — `velocity_duration`, `taper`, `durability_curve`, `terrain_match`, `race_sim`, `gap_analysis`, `hr_zones` | Each is a real module with tests. Sequence by what athletes actually asked in `analysis_queries`. |
| **—** | *Independent of Ask* | 2 BLOCKED | Write the `vital-webhook` daily-sleep branch. Unblocks `hrv_trend` + `overnight_recovery` **and** `detectorsC` **and** the readiness composite's overnight factor. |

**Phase E is the one to sequence from data, not intuition.** By the time you
get there you'll have months of `analysis_queries` rows telling you which of
the five people actually try to ask.

---

## 5 · Two structural notes

**On `velocity_duration` (critical speed).** This is the single highest-value
BUILD in the list, and the one most likely to be a trap. The distance-time
data is in `external_streams` as unindexed JSONB — a CS/D' fit over it means
either extracting a mean-maximal-pace table per workout into a new column, or
paying the JSONB scan on every query. **Do the extraction.** It belongs in
`compute-workout-features` alongside the existing rollups, not in the analyzer.
The analyzer should read a column, never parse a stream.

**On hard rule #2 and the shape of these questions.** Several analyzers sit
close to the medical line — `niggle_vs_load`, `readiness`, `overnight_recovery`,
`durability_curve`. The registry contract holds: they report *what the data
shows*, never *what it means for the body*. `readiness` may return `pull`
because that value already exists in `buildReadiness`; it may not return
"take a rest day." The `tone` field still has no `'bad'` value, and
`ask-narration` is a golden-family prompt with recorded cassettes for exactly
this reason.
