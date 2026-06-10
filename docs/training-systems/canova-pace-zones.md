# Canova Pace Zones — Archived Reference

**Status:** Archived May 2026. Not in active use. Preserved as v2 reference.

## Context

The pace zone system that the now-cut `generate-training-plan` and the
shared `_shared/workoutSelection.ts` operated in. Derived from Renato
Canova's framework: training paces expressed as percentages of marathon
pace (MP) speed.

This is a different reference frame than the v1 canonical vocabulary
(race-equivalence: Easy/Steady/MP/HM/LT/10K/5K/Mile, derived from goal
race times). The two systems describe similar physiological work in
different ways and don't translate without coach judgment.

## The eight zones

| Zone | % of MP speed | Coding prefix | Physiological purpose |
|---|---|---|---|
| 0.70–0.75 | 70–75% | EASY | Easy / recovery — conversational, full aerobic |
| 0.80 | 80% | BE_* (Basic Endurance) | Aerobic base building, long easy runs |
| 0.85 | 85% | GE_* (General Endurance) | Moderate aerobic, steady-state long runs |
| 0.90 | 90% | RSE_* (Race-Supportive Endurance) | Sub-threshold steady-state, marathon-supportive |
| 0.95 | 95% | RCE_* (Race-Critical Endurance) | Just below marathon pace; race simulation |
| 1.00 | 100% | RP_* (Race Pace) | Marathon goal pace |
| 1.04–1.07 | 104–107% | RSS_* (Race-Specific Speed) | Tempo, threshold, half-marathon to 10K range |
| 1.10 | 110% | RSPS_* (Race-Supportive Speed) | VO2max work, 5K-3K range |
| 1.15 | 115% | GS_* (General Speed) | Neuromuscular, strides, hill sprints |

## How the percentages work

The reference point is **marathon pace speed** — the speed (not time) at
which the athlete runs their marathon. All other paces are expressed as
percentages of that speed.

For example, if MP = 7:00/mi (8.57 mph), then:

- 80% (BE) = 6.86 mph = ~8:45/mi (easy pace)
- 85% (GE) = 7.29 mph = ~8:14/mi (moderate)
- 90% (RSE) = 7.71 mph = ~7:47/mi (steady-state)
- 95% (RCE) = 8.14 mph = ~7:22/mi (just below MP)
- 100% (RP) = 8.57 mph = 7:00/mi (MP)
- 105% (RSS) = 9.00 mph = ~6:40/mi (tempo to LT)
- 110% (RSPS) = 9.43 mph = ~6:22/mi (VO2max)
- 115% (GS) = 9.86 mph = ~6:05/mi (neuromuscular)

## How it differs from race-equivalence (v1 system)

The v1 canonical vocabulary anchors paces to race performance at each
distance:

| v1 Zone | Anchored to |
|---|---|
| `easy` | ~80% of MP speed (same anchor, different label) |
| `steady` | ~85% of MP speed |
| `moderate` | ~88% of MP speed |
| `tempo` | Sub-threshold (between steady and threshold) |
| `threshold` | 1-hour race pace, interpolated 10K↔HM |
| `MP` | Goal marathon pace (race-equivalence) |
| `HM` | Goal half-marathon pace (race-equivalence) |
| `10K` | Goal 10K pace (race-equivalence) |
| `5K` | Goal 5K pace (race-equivalence) |
| `mile` | Goal mile pace (race-equivalence) |

Race-equivalence answers "what could you race a 10K in *today*?" — and
sets that as the target. Canova percentages answer "what % of your
marathon pace speed is this workout?" — and trust the marathon pace as
the anchor.

For elite athletes the two systems converge (their MP, HM, 10K, 5K paces
sit at predictable percentages of each other). For non-elite athletes
they diverge meaningfully — a recreational runner whose marathon takes
4+ hours has very different race-distance relationships than someone
running 2:30. The v1 race-equivalence math (in
`workout-helpers.ts:derivePaceTableFromGoal`) was designed specifically
to handle non-elite cases correctly.

See `outputs/workout-system-rebuild.md` "Pace vocabulary" section for
why v1 went race-equivalence.

## How it maps to common training vocabularies

Different coaching systems use different names for similar zones:

| Canova | Daniels (Running Formula) | Tinman | Pfitzinger | Description |
|---|---|---|---|---|
| 70–80% | E (Easy) | Easy | Recovery / general aerobic | Easy aerobic |
| 85% | M (Marathon) — for some | Steady | LT (lactate threshold) lower | Steady-state |
| 90% | M | CV (Critical Velocity) lower | Sub-LT | Sub-threshold |
| 95% | M to T | CV upper | Slightly sub-LT to LT | Just below MP |
| 100% | M | M pace | M pace | Marathon goal pace |
| 105% | T (Threshold) | CV | LT / threshold | Threshold / tempo |
| 110% | I (Interval) / R (Repetition) | VO2max | VO2max | VO2max |
| 115% | R | Neuromuscular | Speed work | Neuromuscular / strides |

These mappings are approximate. Daniels' M pace, for example, is
specifically *current* marathon-equivalent pace from his VDOT tables,
not goal pace — so a Daniels coach prescribing M pace is anchored to
recent race performance, while a Canova coach prescribing 100% MP is
anchored to goal performance. Different reference points, similar
intended effort on the day.

## Notes on alternation patterns

Canova workouts heavily use **alternations** — switching between a
target pace and a slightly slower "float" pace continuously, without
walk recoveries. E.g., `8x1mi @ 95% w/ 1mi @ 85% float`.

The float pace gives partial recovery without the metabolic drop of
walking or stopping. This is distinct from:

- **Jog recovery** — slow jog between reps (e.g., Daniels-style intervals)
- **Walk recovery** — full walking between reps (e.g., hill sprints)
- **Continuous** — no recovery, run continues at the slower pace

Recovery types in the archived workout library (`canova-workout-library.md`):

```
Steady State  — no recovery (long runs)
Continuous    — work continues at lower pace (tempo, progressions)
Float         — active recovery at a moderate pace
Jog           — slow jog between reps
Walk          — walking recovery (hill sprints, short reps)
```

## Why this was archived

Two main reasons:

1. **Pace-system mismatch.** The Canova percentages didn't translate
   cleanly to the v1 race-equivalence pace chart that the athlete-facing
   pace zone UI uses. Two systems on screen at the same time would
   confuse athletes and coaches.

2. **Plan generation deferred.** The pace system was tightly coupled to
   the now-cut algorithmic plan generator (`generate-training-plan`).
   With coaches authoring plans directly, they bring their own pace
   vocabulary — Daniels, Tinman, Canova, freeform — and the system
   doesn't need to know which.

If v2 revisits algorithmic plan generation, this pace system is one
option. See `outputs/workout-system-rebuild.md` for the v1 strategic
direction.
