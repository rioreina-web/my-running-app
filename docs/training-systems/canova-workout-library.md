# Canova Workout Library — Archived Reference

**Status:** Archived May 2026. Not in active use. Preserved as v2 reference.

## Context

This is the complete workout library that powered `generate-training-plan`
(now cut) and was referenced by `reschedule-plan` (being rebuilt). Each
workout is identified by a code (e.g., `BE_4`, `RP_6`, `RSS_2`) and
characterized by:

- **Workout type** — long_run, workout, easy, rest, strides, race
- **Pace percentage** — % of marathon pace (MP) speed, per Canova's framework
- **Focus area** — Endurance, Specific Speed, Alternations, etc.
- **Recovery type** — Steady State, Continuous, Float, Jog, Walk

The library is marathon-coded. Half-marathon, 10K, and 5K codes were
referenced but not fully populated. See `canova-pace-zones.md` for the
pace system context and `phase-model.md` for how this library was sequenced.

## 0.80 — Basic Endurance (BE)

Easy aerobic running at 80% of MP speed. Conversational pace.

| Code | Name | Description | Distance (mi) |
|---|---|---|---|
| BE_1 | 10mi Easy | 10mi easy at 80% | 10 |
| BE_2 | 12mi Easy | 12mi easy at 80% | 12 |
| BE_3 | 15mi Easy | 15mi easy at 80% | 15 |
| BE_4 | 18mi Easy | 18mi easy at 80% | 18 |
| BE_5 | 20mi Easy | 20mi easy at 80% | 20 |
| BE_6 | 22mi Easy | 22mi easy at 80% | 22 |
| BE_7 | 24mi Easy | 24mi easy at 80% | 24 |
| BE_8 | 2hr Rolling Hills | 2 hrs easy over rolling hills at 80% | 16 |

## 0.85 — General Endurance (GE)

Moderate aerobic running at 85% of MP speed. Steady-state and progressions.

| Code | Name | Description | Distance (mi) |
|---|---|---|---|
| GE_1 | 10mi Moderate | 10mi moderate at 85% | 10 |
| GE_2 | 12mi Moderate | 12mi moderate at 85% | 12 |
| GE_3 | 15mi Moderate | 15mi moderate at 85% | 15 |
| GE_4 | 18mi Moderate | 18mi moderate at 85% | 18 |
| GE_5 | 20mi Moderate | 20mi moderate at 85% | 20 |
| GE_6 | 22mi Moderate | 22mi moderate at 85% | 22 |
| GE_7 | 1hr Progression | 1hr progression (80% > 90%) | 8 |
| GE_8 | 90min Progression | 90 min progression (80% > 90%) | 11 |
| GE_9 | 2hr Progression | 2hr progression (80% > 90%) | 16 |
| GE_10 | 20mi Progression | 20mi progression (80% > 90%) | 20 |

## 0.90 — Race-Supportive Endurance (RSE)

Steady-state at 90% of MP speed; sub-threshold work. Includes alternations.

| Code | Name | Description | Distance (mi) |
|---|---|---|---|
| RSE_1 | 8mi Steady State | 8mi steady at 90% | 8 |
| RSE_2 | 10mi Steady State | 10mi steady at 90% | 10 |
| RSE_3 | 12mi Steady State | 12mi steady at 90% | 12 |
| RSE_4 | 15mi Steady State | 15mi steady at 90% | 15 |
| RSE_5 | 18mi Steady State | 18mi steady at 90% | 18 |
| RSE_6 | 20mi Progression | 20mi progression (85% > 92%) | 20 |
| RSE_7 | 10x1km Alternations | 10x1km @ 95% / 1km @ 85% (20km total) | 16 |
| RSE_8 | 8x1mi Alternations | 8x1mi @ 95% / 1mi @ 85% (16mi total) | 16 |
| RSE_9 | 20mi Progression | 20mi progression (85% > 95%) | 20 |
| RSE_10 | 15mi @ 90–95% | 15mi steady at 90% > 95% | 15 |

## 0.95 — Race-Specific Endurance (RCE)

Continuous or alternation work at 95% of MP speed. Race simulation.

| Code | Name | Description | Distance (mi) |
|---|---|---|---|
| RCE_1 | 10mi @ 95% | 10mi continuous at 95% | 10 |
| RCE_2 | 12mi @ 95% | 12mi continuous at 95% | 12 |
| RCE_3 | 15mi @ 95% | 15mi continuous at 95% | 15 |
| RCE_4 | 18mi 90>95% | 18mi continuous, 90% > 95% | 18 |
| RCE_5 | 4x3mi @ 95% | 4x3mi @ 95% w/ 1mi @ 85% float | 16 |
| RCE_6 | 4x4mi @ 95% | 4x4mi @ 95% w/ 1mi @ 85% float | 20 |
| RCE_7 | 5x3mi @ 95% | 5x3mi @ 95% w/ 1mi @ 85% float | 19 |
| RCE_8 | 15k/10k/5k Progression | 15km @ 90% + 10km @ 95% + 5km @ 100% | 19 |

## 1.00 — Race Pace (RP)

Marathon pace work. Continuous or alternation patterns.

| Code | Name | Description | Distance (mi) |
|---|---|---|---|
| RP_1 | 10mi @ MP | 10mi continuous at MP | 10 |
| RP_2 | 12mi @ MP | 12mi continuous at MP | 12 |
| RP_3 | 10x1mi @ MP | 10x1mi @ MP w/ .5mi @ 90% float | 14 |
| RP_4 | 5x2mi @ MP | 5x2mi @ MP w/ .5mi @ 85% float | 14 |
| RP_5 | 6x2mi @ MP | 6x2mi @ MP w/ 1mi @ 90% float | 17 |
| RP_6 | 4x3mi @ MP | 4x3mi @ MP w/ 1mi @ 85% float | 16 |
| RP_7 | 5x3mi @ MP | 5x3mi @ MP w/ .5mi @ 85% float | 17 |
| RP_8 | 2x5mi @ MP | 2x5mi @ MP w/ 1mi @ 85% float | 12 |
| RP_9 | 3x5mi @ MP | 3x5mi @ MP w/ 1mi @ 90% float | 18 |
| RP_10 | 2x6mi @ MP | 2x6mi @ MP w/ 1mi @ 85% float | 14 |
| RP_11 | 10x1km @ 102% | 10x1km @ 102% w/ 1km @ 95% float | 16 |
| RP_12 | 8x2km @ MP | 8x2km @ MP w/ 1km @ 90% float | 18 |
| RP_13 | 10x2km @ MP | 10x2km @ MP w/ 1km @ 85% float | 21 |
| RP_14 | 6x3km @ MP | 6x3km @ MP w/ 1km @ 90% float | 16 |
| RP_15 | 4x4km @ MP | 4x4km @ MP w/ 1km @ 85% float | 13 |
| RP_16 | 5x4km @ MP | 5x4km @ MP w/ 1km @ 90% float | 17 |
| RP_17 | 4x5km @ MP | 4x5km @ MP w/ 1km @ 85% float | 16 |
| RP_18 | 5x5km @ MP | 5x5km @ MP w/ 1km @ 90% float | 20 |
| RP_19 | MP Descending Ladder | 7-6-5-4-3-2km @ MP w/ 1km @ 85% | 21 |

## 1.05 — Race-Specific Speed (RSS)

Fartlek and threshold-to-CV work at 104–107% of MP speed.

| Code | Name | Description | Distance (mi) |
|---|---|---|---|
| RSS_1 | 8x3' Steady | 8x3' steady w/ 2' moderate at 105% | 12 |
| RSS_2 | 6x6' Fartlek | 6x6' steady w/ 3' easy at 105% | 10 |
| RSS_3 | 12x2' Fartlek | 12x2' fast w/ 2' easy at 105% | 10 |
| RSS_4 | 10x3' Fartlek | 10x3' steady w/ 2' moderate at 105% | 10 |
| RSS_4b | 10x3'/3' Alternation | 10x3' fast w/ 3' moderate at 105% | 10 |
| RSS_5 | 10x800m @ 107% | 10x800m @ 107% w/ 1' rest | 10 |
| RSS_6 | 10x1km @ 107% | 10x1km @ 107% w/ 1' rest | 12 |
| RSS_7 | 6xMile @ 107% | 6 x mile @ 107% w/ 1' rest | 12 |
| RSS_8 | 3x2mi @ 106% | 3x2mi @ 106% w/ .5mi float @ 80% | 10 |
| RSS_9 | 12x1km @ 106% | 12x1km @ 106% w/ 1' rest | 13 |
| RSS_10 | 8xMile @ 105% | 8 x mile @ 105% w/ 1' rest | 14 |
| RSS_11 | 3/2/1mi Cutdown | 3mi/2mi/1mi @ 105%/107%/110% w/ .5mi float | 10 |
| RSS_12 | 2x3mi @ 104% | 2x3mi @ 104% w/ .5mi float | 9 |
| RSS_13 | 7mi Progression | 7mi progression at 97% > 105% | 11 |
| RSS_14 | 3x2mi @ 105% | 3x2mi @ 105% w/ .5mi float @ 85% | 9 |
| RSS_15 | 2x4mi @ 105% | 2x4mi @ 105% w/ .5mi float @ 85% | 12 |
| RSS_16 | 6xMile @ 105% | 6 x mile @ 105% w/ 1' float | 12 |
| RSS_17 | 4xMile @ 105% | 4 x mile @ 105% w/ 2' rest | 10 |
| RSS_18 | 2x3mi @ 105% | 2x3mi @ 105% w/ .5mi float @ 85% | 9 |
| RSS_19 | 7mi Progression 97>103% | 7mi progression at 97% > 103% | 11 |

## 1.10 — Race-Supportive Speed (RSPS)

VO2max work at 110% of MP speed. Track intervals.

| Code | Name | Description | Distance (mi) |
|---|---|---|---|
| RSPS_1 | 12x400m @ 110% | 12x400m @ 110% w/ 1' rest | 7 |
| RSPS_2 | 8x800m @ 110% | 8x800m @ 110% w/ 90s rest | 9 |
| RSPS_3 | 3x4x800m @ 110% | 3 sets of 4x800m @ 110% w/ 1' rest, 4' set rest | 10 |
| RSPS_4 | 12x600m @ 110% | 12x600m @ 110% w/ 200m float | 9 |
| RSPS_5 | 8x1000m @ 110% | 8x1000m @ 110% w/ 2' jog | 10 |
| RSPS_6 | 5xMile @ 110% | 5 x mile @ 110% w/ 2.5' jog | 11 |
| RSPS_7 | 6x1200m @ 110% | 6x1200m @ 110% w/ 2' jog | 14 |
| RSPS_8 | 3x4x800m @ 108% | 3 sets of 4x800m @ 108% w/ 1' rest, 400m set jog | 10 |

## 1.15 — Mechanical Speed (GS — "General Speed")

Neuromuscular work at 115% of MP speed. Hill sprints, strides, short reps.

| Code | Name | Description | Distance (mi) |
|---|---|---|---|
| GS_1 | 12x200m @ 115% | 12x200m @ 115% w/ 200m jog | 7 |
| GS_2 | 12x300m @ 115% | 12x300m @ 115% w/ 200m float @ 80% | 7 |
| GS_3 | 10x400m @ 115% | 10x400m @ 115% w/ 200m jog | 6 |
| GS_4 | 12x400m @ 115% | 12x400m @ 115% w/ 400m jog | 8 |
| GS_5 | Hill Sprints 10sec | 8 x 10s steep hill sprints, full recovery | 6 |
| GS_6 | Fast Strides 100m | 8 x 100m fast strides | 5 |
| GS_7 | Hill Sprints 15sec | 10 x 15s steep hill sprints, full recovery | 6 |
| GS_8 | Hill Sprints 8x15s | 8 x 15s hill sprints, full recovery | 6 |

## Special codes

| Code | Name | Description |
|---|---|---|
| FARTLEK | 8x3' Steady + 2' Easy | Generic fartlek session |
| EASY | Easy Run | Easy conversational pace, 70–75% |
| REST | Rest Day | No running |
| STRIDES | Easy Run + Strides | Easy run + 4–6 x 100m strides at 115% |
| RACE | Race Day | Goal race |

## Focus areas

The library tagged each workout with a focus area used by the LLM-driven
selection logic to vary stimulus week-to-week:

- `Endurance` — aerobic capacity building
- `Alternations` — switching between paces continuously
- `Race Simulation` — sustained efforts at goal pace or near
- `Specific Speed` — threshold and VO2max work
- `Speed` — VO2max and faster
- `Fartlek` — semi-structured intervals
- `Progression` — pace increases through the workout
- `Specific Alternations` — alternation at race pace
- `Progression Alternations` — descending or ascending ladders
- `Neuromuscular` — strides, hill sprints, sub-maximal speed
- `Recovery` — rest, easy
- `Race Simulation` — race-pace continuous work

## Recovery types

How recovery is structured between reps or segments:

- `Steady State` — continuous run, no interval recovery (long runs, easies)
- `Continuous` — work continues at lower pace (e.g., 90% → 85%)
- `Float` — active recovery at a moderate pace between reps
- `Jog` — slow jog between reps
- `Walk` — walking recovery (hill sprints, short reps)

## Why this was archived

The Canova vocabulary clashed with the v1 race-equivalence pace chart
(Easy/Steady/MP/HM/LT/10K/5K/Mile in `web/src/components/coach/workout-helpers.ts`).
The two systems use different reference frames — Canova is anchored to
MP speed, race-equivalence is anchored to the athlete's race pace at each
distance. They don't translate cleanly without coach judgment.

The v1 strategic decision (May 2026) was to move to coach-authored plans
and cut algorithmic plan generation. The Canova library is preserved here
as a reference for any future v2 work that revisits algorithmic generation.

See `outputs/workout-system-rebuild.md` for full context.
