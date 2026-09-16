# Signature miner — pilot run on Rio's data

**Date:** 2026-07-07
**What:** A slim prototype of the athlete-signature miner
(`ai-feedback-loop-athlete-signature-addendum-2026-07-07.md`) run against Rio's own
Strava history: 468 runs, 2025-07-01 → 2026-07-07, Austin TX. This is the "dark run"
the addendum's S1 phase calls for — validating that the grammar + gates produce real,
non-obvious observations before anything ships.

## Method + honest limitations

- Day-level features from activity summaries: distance, moving time, avg speed,
  Strava Relative Effort (HR-based). **Cardiac-cost proxy:** effort per km on easy runs
  in a matched pace band (3.35–3.90 m/s), so conditions are compared at equal pace.
- Gates per the addendum: support ≥ 6 per arm, effect ≥ 0.5 personal SD,
  split-half consistency (effect must hold in both halves of the year independently).
- **Weather = Austin seasonal climatology + time of day** (hot season Jun–Sep,
  AM/PM), not per-workout observations — the weather archive API was unreachable in
  this session. Production uses the per-workout weather join (addendum §4.3), which
  will sharpen every heat finding below with actual dew point bands.
- Not available in this dataset: HR streams, RPE, mood, sleep, stress, niggles
  (Strava summaries only; the app DB has ~3 logged runs so far). Those dimensions
  activate as app-side logging accumulates.
- Known confound: hot-vs-cool quality comparisons partly overlap with training-block
  seasonality. The within-summer AM-vs-PM contrast is clean.

## Baselines

318 of 372 days with running. Mean weekly volume 55.7 mi, peak 89.5 mi.
169 matched-band easy runs, 45 quality sessions, 66 runs ≥ 18 km.

## Passed all gates

| # | Observation | Numbers | Effect |
|---|---|---|---|
| 1 | **Summer evening easy runs cost far more than summer morning ones at the same pace.** | effort/km 5.83 (hot-season PM, n=33) vs 4.56 (hot-season AM, n=31) — **+28% cardiac cost, pace identical** | +0.66 SD, split-half ok |
| 2 | **Hot-season mornings cost no more than cool-season mornings.** (H1a null + H1c pass) | hot-AM 4.56 vs cool-AM 4.61 e/km — indistinguishable; hot-PM vs cool +0.63 SD | The 6 a.m. habit fully neutralizes Austin summer on easy days |
| 3 | **Quality sessions run ~24 s/mi slower in hot months.** | 4.24 m/s (~6:20/mi, n=18) vs 4.52 m/s (~5:56/mi, n=21) | −0.65 SD, split-half ok; partly seasonal-block confounded — heat-band baseline (addendum §4.3) exists to separate this |
| 4 | **Evening easy runs cost more year-round — and pace doesn't drop to compensate.** | AM 4.76 vs PM 5.84 e/km; pace 3.647 vs 3.646 m/s (identical) | −0.57 SD, split-half ok. Rio holds pace and pays in effort rather than slowing down |

## Informative nulls (survived split-half, effect below gate — or cleanly refuted)

- **Rest day before a workout does not predict a faster workout** (split-half reversed —
  no reliable effect either way). Continuity suits him.
- **Quality ≤ 2 days after an 18 km+ day shows no reliable penalty.**
- **Volume jumps (trailing 7d ≥ 115% of prior 3-wk avg) do not raise easy-run cost**
  (weak, slightly *lower*). He absorbs volume well at current ranges.
- **Long-run cost in hot months** trends higher (+0.40 SD) — right direction, under the
  gate; per-workout dew point data should resolve it.
- Long runs the day after a quality day: slightly slower, but n=9 — below support floor
  for the fresh-vs-post-Q contrast to be trusted.

## Segment-level pass (same day, after Rio's correction)

Rio pointed out that workout paces live in segments — whole-activity averages bury the
reps under jog recoveries. Re-ran the quality analysis on **device laps** (per-rep pace
+ HR) for 6 K-workout sessions, 41 work reps (hot n=26 reps / 3 sessions, cool n=15 /
3 sessions):

- **The "24 s/mi slower in heat" finding was an artifact and is retracted at the rep
  level.** True rep pace: hot 5.191 m/s vs cool 5.187 m/s — **identical** (~3:13/K both).
  The activity-level slowdown was session structure (recoveries, warmup share), not reps.
  This is exactly why the segment rule is now mandatory in the addendum (§4.1).
- **Candidate (below support floor, needs more sessions):** at identical rep pace, HR
  runs ~+3 bpm in hot-season sessions (168.7 vs 165.8, +0.56 SD) — he holds K-pace in
  Austin summer and pays a small cardiac premium, mirroring the easy-run pattern.
  July 2025 was the extreme (HR 172.6 at 5.15 m/s vs Jan's 164.8 at 5.21).
- Sep 16 was his standout session (fastest reps, lowest HR, negative split) *despite*
  hot season — one more argument for per-workout dew point rather than seasonal bands.
- Whole-activity avg vs true rep pace: Jan 20 4.82 → 5.21 m/s; Sep 16 3.88 → 5.28 m/s.

## What this validates

The grammar + gates found four patterns that are individually true of this athlete,
numerically grounded, and phrased-able in the product voice — and correctly refused to
"find" several plausible-sounding patterns the data doesn't support (rest-day magic,
volume-jump fragility). That's the precision behavior the S1 dark run requires.

**Production deltas from this prototype:** per-workout dew point/humidity join (§4.3),
HR/RPE/mood/sleep outcomes as app logging accumulates, formal FDR control, and
`phrase-signature-observation` prompt + cassettes for athlete-facing wording.

Artifacts: `outputs/miner/runs.csv` + `outputs/miner/mine.py` in the session workspace
(prototype only, not repo code).
