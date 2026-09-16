# The fitness model — five signals, one estimate

2026-08-17. Written as the answer to "clean this up": the prediction pipeline
already contained four of the five signals it should rest on, scattered across
three files and two months of hotfixes. This doc is the map, plus the one
signal that was missing (HR efficiency) and where it now lives.

**The model in one sentence:** a demonstrated race sets the anchor; training
volume decides how fast the anchor is allowed to fade; measured key sessions
may move the estimate — freely toward *faster*, only with corroboration toward
*slower*; every pace on every path is heat-neutralized before it is compared
to anything; and HR efficiency is the corroboration.

Signals compose sequentially — nothing averages against the race:

```
neutral race anchor
  → decay          (volume-gated, ≤2% while training is continuous)
  → training blend (zone signal; fast: age-scaled cap · slow: EF-gated cap)
  → curve damping  (evidence accumulates, one day cannot swing the line)
  → per-distance conversion + bands + tier (+ lifetime PRs alongside)
```

## Where each signal lives

| # | Signal | Home | Mechanism |
|---|---|---|---|
| 1 | **Baseline** | `fitnessPrediction.ts` anchor selection (~1360) | Races → conditions-normalized (`raceNormalization.ts`) 10K-equivalent; age-weighted selection (0.2%/wk) so an old flattered race can't anchor forever |
| 2 | **Training volume** | same file, decay block (~1560) | `maintenanceFactor` (stimulus + volume credit + quality-density floor) sets decay/week; continuous training caps total decay at 2%; collapse opens the detraining path |
| 3 | **Key sessions** | `trainingZoneSignal.ts` (2026-08-17, replaced Riegel) | Reads `parsed_structure.blocks` only (the trusted parse — never `pace_segments` labels, never voice-log race-pace claims); prices continuous work against the athlete's own pace/duration curve |
| 4 | **Heat / humidity** | `pace-heat-adjustment.ts`, applied inside #1, #3, #5 | Races normalize via lap weather; zone-signal reps neutralize per-rep (rep-length scaled); EF pools price distance at neutral pace. A lens over every path, not a signal of its own |
| 5 | **HR efficiency** | `fitnessSignal.ts` (84d EF pools) → **EF gate** in the blend (NEW) | Heat-neutral pace-per-beat trend arbitrates the one claim nothing else could check: "the athlete got slower" |

## The EF gate (what was added today)

The training blend's two directions were symmetric in code and asymmetric in
evidence. *Faster*-than-anchor rests on work the athlete measurably ran.
*Slower*-than-anchor is an inference — and training paces slow for reasons
that are not fitness: August dew points, a down week, prescribed-easy blocks.
That asymmetry is how a 31:20 10K + held 66 mpw read as a 33:39 10K
(2:36:55 marathon, 2026-08-17): six hot threshold sessions priced slow and
dragged a raced anchor the full age-scaled 6%.

Now the slow direction needs a second witness:

| EF verdict | Slow displacement cap |
|---|---|
| **held** (flat/improving) | 1.5% — the fresh-race cap, regardless of anchor age |
| **declining** | age-scaled cap, unchanged (up to 6%) |
| **null** (no evidence) | age-scaled cap — athletes without HR keep pre-gate behavior |

The gate only ever *tightens*; the fast direction is untouched. When it binds,
`data_source` appends `+ efficiency held` so the row explains itself.

**Verdict arbitration** (`efficiencyVerdict`, exported): strongest-evidence
bucket wins — ranked by recent sample count, ties to higher confidence;
eligible only at medium+ confidence with ≥4 samples in both windows. A
3-sample declining threshold read does not outvote a 20-sample flat easy read.
Rationale: thin quality weeks are exactly when the model most needs the
aerobic evidence it does have.

**Scope guard:** EF here is an 8–12-week longitudinal trend over heat-neutral
pools. EF as a *daily readiness* signal was tested and retired (2026-08-07,
behavioural masking). This use is deliberately not that; do not extend it
toward readiness.

**Plumbing:** `compute-fitness-snapshot` reads `athlete_state.fitness_signal`
(written by `rebuild-athlete-state`, heat-aware since v14 2026-08-17) and maps
`efficiency[]` → `PredictionInput.efficiencySignal`. The read is a day stale
by cron order (snapshot 03:30, rebuild 04:00) — immaterial for a trend this
slow. Missing row / null → gate inert.

## Invariants worth defending

- **A demonstrated race is a floor the model must argue with, not a data
  point it averages away.** Anything that moves the estimate slower than the
  decayed anchor must name its evidence (today: EF decline, volume collapse,
  detraining).
- **Prescribed work is not maximal work.** Reps run at a prescribed pace are
  evidence *of* that pace, not of a ceiling — the reason Riegel died and the
  reason slow reps alone can't drag the anchor.
- **Every comparison happens in neutral air.** If a new path compares paces
  without going through `pace-heat-adjustment.ts`, it will rediscover the
  August problem.
- **Signals modulate; they do not average.** The 50/50 blend of measured race
  against inferred training was the original sin here.

## Verification

- `fitnessPrediction.test.ts` — 48/48, including: the live regression (aging
  race + held volume + slow reps + live EF payload ⇒ ≤1.5% slow drag),
  declining-EF ≡ no-EF (gate only tightens), fast direction untouched,
  verdict arbitration edge cases.
- `deno check` clean on `fitnessPrediction.ts` + `compute-fitness-snapshot`.

## Still open (deliberately not this change)

- **iOS renders no PR next to the projection** (hard rule #7). The server has
  shipped `lifetimePRs` on every prediction since 2026-07-17; the 2:37 screen
  would have been self-evidently wrong with `PR 2:22:43` beside it. iOS change.
- **The iOS on-device writer** still writes competing `race (10K)` snapshot
  rows (no `· v2`) — the curve damps only against its own rows
  (`fitnessCurve.isOwnSnapshot`), but the table keeps both opinions. iOS change.
- **Race confirmation**: all five anchor races are `source='detected',
  confirmed_at=NULL`. The model's whole baseline rests on unconfirmed rows;
  the confirm/dismiss flow exists (`race_candidate` tagging) and wants UI.
- **EF-declining currently changes nothing vs no-EF.** By design this round
  (gate only tightens). If a future change wants declining EF to *deepen*
  decay, it needs its own evidence bar and tests.

Deploy: `compute-fitness-snapshot` (reads the signal, passes it through) —
`fitnessPrediction.ts` rides along in its bundle. `rebuild-athlete-state`
needs nothing.
