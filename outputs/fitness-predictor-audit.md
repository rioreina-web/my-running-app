# Fitness predictor audit (May 2026)

Read alongside `RunningLog/RunningLog/Analysis/FitnessPredictorService.swift`,
`supabase/functions/fitness-predictor/index.ts`, and
`supabase/functions/_shared/prompts/fitness-predictor.v1.ts`. This is the
first of three artifacts: audit → scenarios → prompt v2.

## TL;DR

The thing the iOS app actually runs is a ~600-line Swift method called
`generateLocalPrediction`. It is doing real coaching work — race-anchor
detection, training-anchor fallback, a decay model calibrated to a 31:20
10K runner, pace-segment validation, trend-aware maintenance factor. It is
not the naive thing the "AI advises, never acts" framing might lead you to
expect.

The LLM edge function (`fitness-predictor/index.ts` + the `fitness-predictor.v1`
prompt) is parallel infrastructure that nothing on iOS calls. The iOS service
hardcodes `generateLocalPrediction` on line 94 with a "always use local for
now - fast and free" comment. The edge function may serve a web predictor
that doesn't exist yet, or it may be a sketch from before the local engine
landed. **Today, no production traffic touches the LLM prompt.** This audit
treats the local engine as the primary system and the LLM path as something
we should re-purpose, not extend in place.

The deterministic confidence-tier + range layer added this morning (migration
`20260511170000`) lives in two places: iOS computes tier from anchor +
structured-data presence (`FitnessPredictorService.swift:765-796`); the edge
function computes tier from "recent race ≥10K within 8 weeks OR ≥2 MP workouts
within 6 weeks" (`index.ts:70-102`). They use overlapping but not identical
rules. Worth aligning before either ships further.

## Path A — the production iOS local predictor

### What it gets right

**Anchor hierarchy is the right shape.** Race anchor first; if the race is
>6 weeks old and a fresher training anchor exists, prefer the training
anchor; otherwise plan goal; otherwise decayed snapshot baseline; otherwise
return nil rather than fabricate (`L376-423`, `L734-738`). Refusing to
predict when there's no signal is exactly the discipline CLAUDE.md asks for
and the empty-state design promises.

**The maintenance-factor decay is the most coach-shaped piece in the
system** (`L554-612`). It encodes: base detraining at 0.3%/week, fully
offset by ~50min/wk of quality AND ~40mi/wk of volume. Quality matters more
than volume (65/35 split). Sharp volume drop adds extra decay; trending-up
quality + volume can push the prediction slightly faster (capped at
0.2%/wk). The numbers are calibrated against a worked 31:20 10K runner in
inline comments, which is the right way to ground constants — every
adjustment can be sanity-checked against a real archetype.

**Pace-segment validation has a volume threshold** (`L614-679`). It blends
the anchor-derived estimate with actual recent hard efforts, but only above
4 hard miles in 14 days and ≥3 segments. This kills the "2×200m strides
skewed the prediction" failure mode.

**`detectTrainingAnchors` trusts only the Observer's parsed_structure**
(`L1052-1099`), with the segment-label fallback explicitly disabled because
labels misfire (a 7:38/mi easy long run getting tagged "race_pace" on a 5:03
10K runner). That's a hard-won decision; preserve it.

### Where it falls short

**1. Environmental context is entirely missing.** Heat, humidity, wind,
hills, altitude — none of it enters the model. A 5:20/mi tempo on an 85°F
day and a 5:20/mi tempo on a 50°F day get equal weight. A coach reading the
voice log would discount the hot one by 10–20 sec/mi. Voice logs already
mention this stuff verbatim ("brutal heat today," "altitude is killing
me"), but nothing in the predictor reads those mentions. This is the single
biggest blind spot.

**2. The marathon prediction is mechanically equivalent to the 10K
prediction.** Everything flows through `PaceCalculator.getEquivalentTime`
from the 10K anchor (`L744-754`). If a runner has a fast 5K, sparse
long-run mileage, and no MP work, the marathon prediction inherits the 5K's
confidence. The range is currently a flat percentage of the point estimate
(1.5/3.0/5.0% per tier), so the marathon range scales with the 10K
confidence, not with marathon-specific evidence. A coach would say "I can
see your speed but I have no signal on your marathon endurance — that
prediction is much wider than the 10K."

**3. Niggles and mood don't enter the model.** The system reads voice logs
for pace mentions and `parsed_structure`, but not for fatigue. A two-week
streak of mood:tired or repeated calf-niggle mentions should widen the
prediction (especially the marathon) and pull the point estimate down —
"the engine is hotter than the tach says." We don't need the predictor to
*interpret* the niggle (CLAUDE.md is careful about that), only to widen its
uncertainty when one is present.

**4. Recency is binary, not continuous.** A race anchor is preferred unless
it's >6 weeks old, in which case a recent training anchor takes over
(`L382-388`). But a 5-week-old race and a 2-week-old tempo should *blend* —
they're both informative. The current code picks one.

**5. Trend logic moves the point estimate but not the confidence tier.**
If volume trend is 0.4 (huge drop) and stimulus trend is 0.2, the decay
model adds extra detraining — but the tier still reads "high" if a race
exists. When the regime is shifting that fast, the decay constants are
operating outside the range they were calibrated for, and the range should
widen too. Stability of trend should feed into tier.

**6. The goal-pace anchor doesn't sanity-check against current fitness.**
If plan goal is 3:00 marathon but actual stimulus + race history say 3:20,
the plan goal still feeds in as a fallback anchor. The predictor should
never let the goal mask the truth — it should report current fitness, then
flag the gap. Coach would say "your plan goal is 3:00 but your current
fitness reads 3:20 — let's talk."

**7. The "improving / maintaining" data-source tag** (`L681-687`) **is the
most coach-like signal in the whole system, but it's not surfaced to the
prediction shape.** The UI shows "fitness profile (improving)" but the
structured `confidence_tier + range` ignores it. Improving should tighten
the range slightly; sharp detraining should widen it.

**8. Sparse-data behavior cliff.** Below the signal threshold, the
predictor returns nil and the UI shows EmptyPredictionState. That's correct
discipline. But the `data_depth` 1 and 2 states (1+ run, 7+ days of data)
deserve coach-shaped output: "I can see you ran twice this week — too
early to predict your marathon, but here's what would let me." The current
behavior is binary: predict or nil.

## Path B — the LLM edge function

The function itself (`fitness-predictor/index.ts`) is a clean little
endpoint. The hardening this morning — deterministic `computeConfidenceTier`
and `rangeFromTier`, the LLM does not get a vote on confidence (`L265-279`) —
is exactly right. The prompt is the weak link.

### What `fitness-predictor.v1` does well

Spells out the equivalence math: "From 10K pace, calculate: Mile (~12%
faster), 5K (~4% faster), Half (~5.5% slower), Marathon (~10.5% slower)."
Correct order-of-magnitude; Riegel at ~1.06 would give slightly different
numbers but Haiku can do this and the result is fine.

Guards against the most common LLM failure mode: "Easy runs are 60-90
sec/mi slower than race pace - don't use them directly." Good.

JSON-only output. Forces the function shape.

### Where v1 falls short

**1. It's pure math wearing a coach costume.** No instruction to weigh
voice logs against workouts. No instruction to consider environmental
context. No instruction to discount fatigue signal. The prompt asks Haiku
to be a calculator.

**2. Voice logs are nearly wasted.** "Voice log pace mentions are valuable
- weight them heavily" — but the prompt never tells the model *how*. And
pace mentions are the weakest possible voice signal. The richer signal —
"felt awful, dragging from rep 3," "first run back from a calf strain,"
"altitude getting to me" — has no instruction attached.

**3. The model is asked to emit confidence then it gets overridden.**
`L262` parses `"confidence": "Low"` from the response and `L267-279`
overwrites the tier deterministically. The LLM is wasting tokens on
something we throw away. Drop the field from the prompt.

**4. No internal-consistency check.** The model can emit a 5K of 19:00 and
a 10K of 41:00 — implied Riegel ratio violates physiology. Coaches notice
instantly; LLMs don't. Either fix in post (derive 4 distances from one
anchor in the edge function, as the Swift path does) or instruct the model
to anchor on one distance and convert from there.

**5. No data-depth awareness.** Same prompt for a runner with 2 runs and a
runner with 90 days of structured workouts. CLAUDE.md says `data_depth`
gates editorial register — the predictor should too. At depth 0/1, the
right answer is "not enough signal yet, here's what would help."

**6. The plan-context line is fed in but the prompt never instructs the
model to compare actual fitness to goal.** Same blind spot as the Swift
code. Goal becomes background noise, not a coachable comparison.

**7. Stale model (Haiku 3.5).** `claude-3-5-haiku-20241022`. If this path
becomes live, swap to a newer Haiku — but only after the prompt is worth
running.

## The deterministic tier + range layer

The migration this morning is the right idea. Two issues to flag:

**iOS and edge-function tier rules don't match.** iOS at `L765-796` derives
tier from "race exists" → high; "anchor exists" → medium; "structured data
exists" → medium; etc. The edge function at `index.ts:70-102` derives tier
from "recent race ≥10K within 8 weeks OR ≥2 MP workouts within 6 weeks" →
high. Different rules for the same column. If both paths ever write to
`fitness_snapshots.confidence_tier`, the field will mean two things.
Reconcile to a single rule, ideally documented in one place both
implementations point to.

**Range is a flat percentage of point estimate, independent of distance.**
1.5% on a marathon = ~3 min; 1.5% on a mile = ~5 sec. Mile fitness is much
more volatile than marathon fitness and the range should be *wider in pace
terms*, not narrower. Conversely, the marathon range should *widen* when
marathon-specific evidence (MP work, long-run quality) is thin — even if
overall 10K confidence is high. The intuition: the further the prediction
extrapolates from the anchor distance, the wider it should get.

## Coach gaps, organized by the three themes you flagged

### Recency + trend weighting
- Replace the binary "race vs. training anchor" pick with a recency-weighted
  blend. A 5-week-old race and a 2-week-old tempo are both informative;
  weight by `1 / (1 + weeks_ago)` or similar.
- Let trend direction shift the confidence tier, not just the point
  estimate. Stable trends (≈1.0) tighten the range. Fast-moving trends
  (>1.3 or <0.7) widen it.
- When the runner is clearly improving (volumeTrend > 1.15 AND stimulusTrend
  > 1.0 AND weeklyStimulusMinutes ≥ 30 — the existing build-phase
  detector), the prediction should expose that as a separate field
  (`trend: "improving"`) and the UI should show it.

### Context discounting
- Read a closed-vocabulary set of environmental keywords from voice logs
  (heat, humidity, altitude, hills, wind, sick, low-sleep) — mirror the
  Niggles design.
- Discount the *inference* from a workout pace, not the *anchor* itself.
  A 5:20 tempo in 85°F still happened — it just means current fitness is
  faster than that pace suggests.
- Surface the adjustment in `dataSource`: "Based on tempo workout (adj for
  85°F heat)." Coach would say it the same way.

### Fitness calibration accuracy
- Distinguish "training-state prediction" (what the recent work says you
  can do) from "proven recent form" (what your last race says you did).
  When they disagree by >3%, surface both — that's a coachable moment.
- Goal-pace anchor should only feed in at data_depth 0/1. Once there's
  real evidence, real evidence overrides the plan goal.
- Marathon range should widen independently when marathon-specific
  evidence is sparse (≥16mi long runs, ≥4mi MP segments). Don't let
  10K-anchored confidence camouflage the gap.
- Niggle + fatigue signal should widen the range (especially marathon)
  without making any injury claim.

## What the Step 2 scenarios will cover

| # | Scenario | What it tests |
|---|---|---|
| 1 | Depth 0 — new user, 0 runs | EmptyState behavior, no fabrication |
| 2 | Depth 1 — 3 runs, no voice logs | Sparse-anchor refusal vs. low-confidence inference |
| 3 | Depth 2 — 2 weeks mixed easy + 1 tempo | Training-anchor-only path |
| 4 | Depth 2 + 1-week niggle streak | Range widening on fatigue signal |
| 5 | Depth 3 + recent race (≤4 weeks) | High-confidence happy path |
| 6 | Depth 3 + stale race (8 weeks) + recent tempo | Recency blend, not pick-one |
| 7 | Hot-weather tempo block | Context discounting |
| 8 | MP block + long runs, no recent race | Marathon-specific confidence path |
| 9 | Returning from injury (4-week gap) | Detraining decay behavior |
| 10 | Goal pace far from current fitness | Goal-vs-truth conflict surfacing |

## Open questions for you before Step 2

**Q1. What do we do with Path B (the LLM edge function)?** Three options:

  a. **Delete it.** The local engine is good enough; less surface area is
     better.
  b. **Keep it as a narrative layer over Path A.** Path A does the math,
     Path B writes the one-sentence coach summary that goes in
     `fitnessSummary`. This is where LLM judgment helps and arithmetic
     hurts.
  c. **Promote it to a fallback** for when Path A returns nil — the LLM
     can produce a coach-toned "you'd benefit from X" output even with
     sparse data.

My recommendation: (b). The Swift engine should keep owning the numbers;
the prompt should own the narrative. The v2 prompt I write in Step 3 would
be a *summary* prompt, not a re-do of the math.

**Q2. Closed environmental vocabulary scope?** Proposed starting set:
heat, humidity, altitude, hills, wind, sick, low-sleep. Seven entries.
Mirror the Niggles design — closed list, surface verbatim, never invent.

**Q3. Marathon-specific evidence threshold?** Proposed: ≥2 long runs
≥16mi in the last 8 weeks + ≥1 MP segment ≥4mi → narrow the marathon range
(stay at tier's default 1.5/3.0/5.0%). Missing either → multiply the
marathon range by 1.5×. Missing both → multiply by 2×. Reasonable, or do
you want different thresholds?

When you're ready, I'll move to Step 2.
