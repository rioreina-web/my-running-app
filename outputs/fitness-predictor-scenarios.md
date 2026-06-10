# Fitness predictor scenarios (May 2026)

Companion to `fitness-predictor-audit.md`. Ten scenarios across the
`data_depth` ladder plus the edges the audit flagged. Each scenario is
concrete enough to run through the predictor by hand (or as a fixture once
the eval harness lands).

**Conventions used throughout:**

- "Today" = `2026-05-11` (matches the system date).
- Default archetype: **Sarah**, mid-30s, ~45 mi/wk peak, training for sub-3:15
  marathon. Pre-block fitness markers: 10K ~38:30 (6:11/mi), 5K ~18:30 (5:57/mi).
  Marathon pace = 7:26/mi. We hold the archetype steady so the scenarios
  compare cleanly. Variants use a different persona only when the gap
  requires it (new user, beginner, returning-from-injury).
- All times shown unrounded for prediction reasoning; the renderer rounds
  to whole minutes per CLAUDE.md hard rule #7.
- "Expected output" describes the **coach-shaped behavior we want**, not
  the current production output. "What today's predictor gets wrong"
  captures the gap.
- Marathon-specific endurance score (MSE) per the rubric we agreed: 0.0–1.0
  scalar combining long-run criterion (≥2 LRs ≥18mi in 6wk) and MP-work
  volume × max-single-session. MSE = 1.0 → marathon range × 1.0; MSE = 0.0
  → marathon range × 2.0; linear interpolation between.

---

## Scenario 1 — Depth 0 — new user, zero data

**Persona.** Brand-new account. Sarah just installed the app. Empty.

**data_depth.** 0 (new account, <1 run, <1 voice log)

### Inputs

- Workouts (30d): none
- Voice logs (30d): none
- Plan: none
- Snapshots: none

### Expected coach reasoning

There is no fitness signal. Predicting anything is fabrication. The right
move is to show the empty state and tell the user what would unlock a real
prediction — log a run, record a voice note about a hard workout, or import
a recent race.

### Expected predictor output

- **Output:** `null` prediction. UI renders `EmptyPredictionState`.
- **Empty-state copy (plain prose, no em-dashes per hard rule #8):**
  > *Eyebrow:* "WHEN YOU'RE READY"
  >
  > Connect Apple Health or record a voice log about a recent workout. One
  > hard effort or race is enough to start.
  >
  > *CTA:* "Connect Apple Health" / "Record a voice log"

### What today's predictor gets wrong

Nothing. This case is handled correctly. Listed for coverage and to lock the
contract: no prediction means no prediction, never a sample/default.

---

## Scenario 2 — Depth 1 — three easy runs, no voice logs

**Persona.** Sarah, week 1 of using the app. Connected HealthKit. Three easy
runs synced from Apple Health. No voice logs yet, no plan set up.

**data_depth.** 1 (1+ run, 0 voice logs, <7 days of data)

### Inputs

- Workouts (30d):
  - 2026-05-05: Easy Run, 5.0mi @ 8:42/mi
  - 2026-05-07: Easy Run, 4.0mi @ 8:38/mi
  - 2026-05-10: Easy Run, 6.0mi @ 8:35/mi
- Voice logs (30d): none
- Plan: none
- Snapshots: none

### Expected coach reasoning

Three easy runs in a week tells me Sarah runs ~15 mi/wk and her easy pace
is around 8:35–8:45. That's not fitness signal — it's volume signal. I have
no idea what her 5K speed is, what her threshold is, what her marathon
endurance looks like. Easy pace alone is 60–90 sec/mi slower than race pace
and the gap is highly variable between runners.

I should not predict race times from easy runs. I should ask for a hard
effort, a tempo, or import a recent race.

### Expected predictor output

- **Output:** `null` prediction. UI renders `EmptyPredictionState` with
  depth-1 copy.
- **Empty-state copy:**
  > *Eyebrow:* "ALMOST THERE"
  >
  > Three easy runs synced. Easy pace doesn't tell me your race speed — log
  > a tempo, a hard interval session, or a recent race time and I'll have
  > something to work with.
  >
  > *CTA:* "Record a workout note"

### What today's predictor gets wrong

The local engine's last-resort fallback (`L723-727`) is "fastest workout × 0.95"
when there's no anchor and no training signal. With three easy runs, the
fastest is 8:35/mi → 10K prediction of 8:09/mi (~50:40 10K). That's a
fabricated number anchored to data that has no relation to race fitness.
The hardcoded `0.95` is a magic number that breaks at every fitness level
(a beginner running 8:35 easy can't run 8:09 for a 10K; an elite running
6:30 easy can race a 10K at 5:00).

**Recommendation:** delete the "fastest workout × 0.95" fallback. Below the
anchor threshold, return nil. The 0.95 line was probably added to keep the
UI from showing empty state too aggressively; the better fix is depth-1
empty-state copy that tells the user what to log.

---

## Scenario 3 — Depth 2 — two weeks, one tempo

**Persona.** Sarah, two weeks in. Logged a structured tempo on Wednesday
plus easy runs around it. No plan yet, no race history.

**data_depth.** 2 (≥7 days, ≥1 voice log, but <21 days and no goal set)

### Inputs

- Workouts (30d):
  - 2026-04-28: Easy Run, 5.0mi @ 8:35/mi
  - 2026-04-30: Tempo, 7.0mi total (2mi WU @ 8:30, 3mi tempo @ 6:30, 2mi CD @ 8:30)
  - 2026-05-02: Long Run, 10.0mi @ 8:00/mi
  - 2026-05-04: Easy Run, 5.0mi @ 8:30/mi
  - 2026-05-07: Speed Work, 6.0mi (warmup + 8×400m @ 1:35 + cooldown)
  - 2026-05-09: Long Run, 12.0mi @ 7:55/mi
  - 2026-05-10: Easy Run, 4.0mi @ 8:40/mi
- Voice logs (30d):
  - 2026-04-30, mood:positive, parsed_structure {type:tempo, equivalent_race_pace:half@6:35/mi, confidence:0.82}:
    "3 at tempo, holding 6:30 felt sustainable but working. Could have done a 4th mile."
  - 2026-05-07, mood:energized, parsed_structure {type:interval, equivalent_race_pace:5K@6:00/mi, confidence:0.78}:
    "400s at 1:35, last 2 were 1:33. Legs popped today."
  - 2026-05-09, mood:positive: "12 miler felt smooth. Stayed under 8 the whole way."
- Plan: none
- Snapshots: none

### Expected coach reasoning

Two anchors here, both training-derived, both fresh. Tempo says half-marathon
pace is around 6:30–6:35 (≈ 1:25–1:26 half). 400s at 1:35 say 5K speed is
around 6:00/mi (≈ 18:36 5K). These are internally consistent — Riegel from
5K@18:36 gives half ≈ 1:25:30, half@1:25:30 gives 5K ≈ 18:30. Sarah's
fitness reads "mid-pack competitive recreational runner."

No race anchor, no marathon-specific evidence yet (longest run is 12mi),
and only 2 weeks of structured data. Confidence: **medium**. Marathon
prediction should widen meaningfully because the long-run criterion is
unmet (0 of the required ≥2 long runs ≥18mi) and MP work is zero. MSE ≈
0.0 → marathon range × 2.0.

### Expected predictor output

- **Anchor:** Observer parsed_structure — tempo (2026-04-30, confidence
  0.82) and interval (2026-05-07, confidence 0.78). Recency-blend the two:
  both within 2 weeks, weight roughly equal.
- **Estimated 10K pace:** ~6:11/mi (38:30)
- **Tier:** medium (1.5%/3.0%/5.0% ranges become 3.0% base)
- **Predictions (point ± range):**
  - Mile: 5:20 ± 0:10
  - 5K: 18:36 ± 0:35
  - 10K: 38:30 ± 1:10
  - Half: 1:25:30 ± 2:35
  - **Marathon: 2:59:00 ± 11:00** (range doubled — MSE = 0.0)
- **dataSource:** "Training anchors (1 tempo, 1 interval)"
- **summary:** "Based on your tempo Apr 30 and intervals May 7. Marathon
  range is wide because I haven't seen a long run over 16mi or any
  marathon-pace work yet. Two long runs at 18+mi and a few miles at MP
  would tighten the marathon estimate."

### What today's predictor gets wrong

The local engine picks one anchor (most recent) rather than blending. The
marathon range uses the same 3% as the 5K range — so it'd show ~5:30
window on the marathon instead of the ~11:00 the evidence warrants. UI
gives no hint that the marathon is the soft spot in the prediction.

---

## Scenario 4 — Depth 2 + niggle streak

**Persona.** Same training data as Scenario 3, but the voice logs from the
last 10 days are flagging a left calf niggle plus mood:tired.

**data_depth.** 2

### Inputs

Same workouts as Scenario 3, with one substitution and added voice logs:

- 2026-05-02: Long Run, 10.0mi @ 8:00/mi (replaced — completed 8mi instead of planned 12)
- Additional voice logs:
  - 2026-05-02, mood:tired: "Cut it short at 8. Left calf is grumbling. Not
    sharp, just there. Ice tonight."
  - 2026-05-04, mood:tired: "Easy 5. Calf still tight on the first mile."
  - 2026-05-07, mood:neutral: "400s went fine but the warmup was rough. Calf
    is hovering."
  - 2026-05-09, mood:tired: "12 felt longer than 12. Legs heavy."
  - 2026-05-10, mood:tired: "Sleep was bad. Easy 4 to shake out."

Body mentions classifier hits: 3× "calf" (left) over 7 days.

### Expected coach reasoning

Same training stimulus as Scenario 3, but the engine is hotter than the
tach says. Three calf mentions in 7 days is a niggle streak — not an
injury, not my call to diagnose, but it tells me Sarah is running closer to
her ceiling than the pace numbers suggest. Marathon (most fatigue-sensitive
race) gets widened further. 10K and below stay similar — short races are
less sensitive to chronic fatigue.

Important: the *point estimate* should not change much. The fitness signal
is what it is. The *range* widens because uncertainty is higher when fatigue
is masking the picture. And the summary should mention the niggle without
recommending action.

### Expected predictor output

Same point estimates as Scenario 3, but:

- **Tier:** medium (unchanged)
- **Marathon range multiplier:** 2.0 × 1.25 (niggle bump) = 2.5×, so
  marathon range ~13:45 instead of 11:00
- **dataSource:** "Training anchors (1 tempo, 1 interval) — range widened
  for recent fatigue signal"
- **summary:** "Based on your tempo and intervals. Your voice logs from the
  last week mention left calf 3 times and mood:tired. I've widened the
  prediction range because chronic fatigue makes the picture less certain.
  Coach will see this in their feed too."

### What today's predictor gets wrong

The current predictor reads no fatigue signal at all. The prediction in
Scenario 4 comes out identical to Scenario 3. A coach reading the same data
would never make that mistake.

---

## Scenario 5 — Depth 3 + recent race (the happy path)

**Persona.** Sarah, 21 days of structured data, race on April 19 (3 weeks
ago), training peaking for Chicago.

**data_depth.** 3 (≥21 days of data AND goal set)

### Inputs

- Workouts (30d, abridged):
  - 2026-04-19: **Race, 10K, 6.21mi @ 6:13/mi → 38:35** (validated by voice log)
  - 2026-04-21: Easy Run, 4.0mi @ 8:30/mi
  - 2026-04-23: Tempo, 8.0mi (2WU + 4mi @ 6:30 + 2CD)
  - 2026-04-26: Long Run, 16.0mi @ 7:50/mi (last 3mi @ 7:00)
  - 2026-04-28: Easy Run, 6.0mi @ 8:30/mi
  - 2026-04-30: Track, 7.0mi (12×400m @ 1:32)
  - 2026-05-02: Long Run, 14.0mi @ 7:55/mi
  - 2026-05-04: Easy Run, 5.0mi @ 8:30/mi
  - 2026-05-06: MP Workout, 12mi (3WU + 6mi @ 7:26 + 3CD)
  - 2026-05-08: Easy Run, 6.0mi @ 8:25/mi
  - 2026-05-10: Long Run, 18.0mi @ 7:45/mi (last 6mi @ 7:25)
- Voice logs:
  - 2026-04-19: "10K race today, 38:35. Even splits, last K was 3:48. Pushed."
  - 2026-04-23: "Tempo 4 @ 6:30 felt comfortable. Could have gone 5."
  - 2026-04-30: "12x400 @ 1:32. Solid. Recovery short."
  - 2026-05-06: "6 at marathon pace, 7:26 felt like training pace. Good signal."
  - 2026-05-10: "18 miler, finished strong. Last 6 at MP felt like work but in control."
- Plan: Chicago Marathon 2026-10-12 (22 weeks out), goal 3:15:00, currently week 16/26
- Snapshots: 2026-04-19 prediction logged — 10K 38:35 HIGH, marathon 3:01 HIGH

### Expected coach reasoning

Race anchor 3 weeks old at 38:35, training has been progressing well since.
MP work showing (6mi @ 7:26 on May 6, last 6mi of 18mi long run also at
~7:25). Long-run criterion fully met: 18mi on May 10, 16mi on Apr 26 — 2
LRs ≥16mi in 6wk. With the 18mi threshold we agreed, **strictly only 1 of 2
qualifies** (16mi run doesn't clear 18mi). MP work is meaningful: 6mi at MP
in one workout, 6mi at MP at the end of the 18mi long run, ~12mi total at
MP in 14 days, max session 6mi. Solid moderate signal.

Confidence: **high** (recent race + ≥2 MP workouts in 6 weeks). Marathon
range: MSE ≈ 0.65 (long-run criterion half-met, MP work moderate) →
multiplier ≈ 1.25.

### Expected predictor output

- **Anchor:** 10K race Apr 19 (38:35), 3 weeks ago
- **Tier:** high (1.5% base range)
- **Predictions (point ± range):**
  - Mile: 5:21 ± 0:05
  - 5K: 18:40 ± 0:17
  - 10K: 38:35 ± 0:35
  - Half: 1:25:42 ± 1:17
  - **Marathon: 3:01:00 ± 4:00** (1.5% × 1.25× multiplier ≈ 1.9% → ±3:30 rounded to 4:00)
- **dataSource:** "10K race Apr 19, 38:35 (3 weeks ago) + marathon-pace work
  May 6 and May 10"
- **summary:** "Based on your 10K (38:35, 3 weeks ago) and recent MP work.
  3:01–3:09 marathon range, midpoint 3:05. Goal is 3:15 — you're tracking
  ahead of plan."

### What today's predictor gets wrong

The current local engine handles this case well — it's calibrated to this
shape of data. Two subtle gaps remain:

1. The "tracking ahead of plan" comparison is in the right ballpark in the
   `dataSource` string for plan-anchored predictions, but it's missing when
   the anchor is a race. Surface it.
2. The 1 of 2 long runs ≥18mi gap (the May 10 18-miler counts, the April
   26 16-miler doesn't) should slightly widen the marathon range. Current
   code uses a flat 1.5% so the marathon range is ~2:30 — the evidence
   warrants ~4:00.

---

## Scenario 6 — Depth 3 + stale race + recent tempo

**Persona.** Same Sarah, but the race was further back and the marathon block
has continued. Tests recency blending vs. pick-one.

**data_depth.** 3

### Inputs

- Workouts (180d, race detection window):
  - 2026-03-15: **Race, Half Marathon, 13.1mi @ 6:43/mi → 1:28:00**
- Workouts (30d):
  - 2026-04-19 onward: same as Scenario 5 (no race; the Apr 19 entry in
    Scenario 5 is replaced by an Easy Run here)
  - 2026-05-06: MP Workout, 12mi (3WU + 6mi @ 7:26 + 3CD)
  - 2026-05-10: Long Run, 18.0mi @ 7:45/mi (last 6mi @ 7:25)
- Voice logs:
  - 2026-03-15: "Half marathon today, 1:28. Pushed the last 5K. Negative split."
  - (otherwise same as Scenario 5)
- Plan: same (Chicago, 3:15 goal)
- Snapshots: 2026-03-15 prediction logged — half 1:28 HIGH, marathon 3:05 HIGH

### Expected coach reasoning

Half marathon 8 weeks ago at 1:28:00 says marathon-equivalent ~3:05. Recent
training is consistent with that or slightly better — MP work at 7:26 felt
controlled, 18-miler finished with 6mi at MP. The race is "stale" by the
current >6 weeks threshold, but it's not irrelevant; it's the only proven
race-distance effort and it's only 2 weeks past the threshold. A coach
would blend, not pick.

Recency-weighted blend, e.g. weight = 1/(1+weeks_ago):

- Half (8wk) → weight 1/9 = 0.11
- Tempo (4wk equivalent, Apr 23) → weight 1/5 = 0.20
- MP work (May 6, 1wk ago) → weight 1/2 = 0.50
- 18mi w/ MP finish (May 10, today) → weight 1/1 = 1.00

Normalize and weight the equivalent-10K paces. The blend should land within
a few seconds of the race-implied 6:09/mi 10K pace, with marginal narrowing
from converging training signal.

### Expected predictor output

- **Anchor:** blended (race 8wk + 2 MP signals last 14 days)
- **Tier:** high (recent race ≥10K within 8 weeks borderline — see Q below)
- **Predictions (point ± range):**
  - 10K: 38:20 ± 0:35
  - Half: 1:25:00 ± 1:13
  - Marathon: 2:59:00 ± 3:30 (MSE ~0.7 → multiplier ~1.2)
- **dataSource:** "Half marathon Mar 15 (8 weeks ago) blended with recent
  marathon-pace work"
- **summary:** "Recent MP work is consistent with your half from March.
  Range tight on the half and below; marathon stays slightly wider because
  it's been a long block and conditions on race day matter."

### What today's predictor gets wrong

The local code's binary >6 weeks switch (`L382-388`) makes the half anchor
unavailable. The training anchor takes over alone — and a single 6mi MP
segment is a weaker anchor than a proven half. The prediction probably
swings toward the training-anchor-only value, throwing away the race
signal. Also: the `computeConfidenceTier` in the edge function would tier
this **medium** because the race is 8 weeks old (the threshold says ≤8
weeks); iOS would tier it **high** because the half existed. The
mismatch is exactly the issue flagged in the audit.

**Decision needed:** is the threshold "≤8 weeks" inclusive or exclusive,
and should it match between iOS and edge? Suggest aligning to: race-anchor
contributes to "high" if ≤10 weeks, with contribution weight decaying
linearly from 1.0 at 0 weeks to 0.0 at 12 weeks.

---

## Scenario 7 — Hot-weather tempo block (context discounting)

**Persona.** Sarah, mid-July training block. The MP workout that should
feel comfortable felt brutal — heat is the reason.

**data_depth.** 3

### Inputs

- Workouts (30d):
  - 2026-05-04: Easy Run, 6.0mi @ 8:35/mi
  - 2026-05-06: MP Workout, 12mi (3WU + 6mi @ 7:45 + 3CD) — note: 19 sec/mi
    slower than goal
  - 2026-05-08: Easy Run, 5.0mi @ 8:40/mi
  - 2026-05-10: Long Run, 18.0mi @ 8:00/mi (slower than usual)
- Voice logs:
  - 2026-05-06, mood:struggling, parsed_structure {type:tempo, equivalent_race_pace:half@7:00/mi, confidence:0.50}:
    "Heat was brutal today. 92°F at 8am. MP felt like LT. Backed off to 7:45
    to survive. Cool weather and this is a 7:25 day."
  - 2026-05-08, mood:tired: "Easy 5 in the heat. Just couldn't get going."
  - 2026-05-10, mood:positive: "Long run 18mi. Started at 5am to beat the
    heat. Felt good when it was cool, but the back half was hot."
- Plan: Chicago Marathon, goal 3:15
- Snapshots: 2026-04-19 prediction — 10K 38:35 HIGH (pre-heat block)

### Expected coach reasoning

The May 6 MP workout looks like a meaningful fitness regression — 7:45/mi
average where the goal was 7:26/mi. Without context, that's a sign the
training-state estimate should drop. **With context**, this is heat. Sarah
herself said "cool weather and this is a 7:25 day." A coach would discount
the workout pace by ~15–20 sec/mi for 92°F conditions (rule of thumb: heat
costs ~1.5–2% per 10°F above ~60°F).

The fitness inference should *not* drop materially. The range should widen
slightly to reflect ambiguity (we don't *know* how Sarah will perform in
cool weather; we're inferring).

### Expected predictor output

- **Anchor:** previous 10K race (Apr 19, ~3 weeks ago in this version) +
  heat-adjusted MP workout
- **Predictions:** similar to Scenario 5 — point estimates within ±5 sec/mi
- **dataSource:** "10K race Apr 19 + marathon-pace workout May 6 (adjusted
  for 92°F heat)"
- **summary:** "Your May 6 MP workout was slower than goal, but you noted
  92°F heat — I've adjusted for that and your fitness estimate hasn't
  shifted much. Range is slightly wider because cool-weather pace is an
  inference, not a measurement."

### What today's predictor gets wrong

Two failure modes possible:

1. **Local engine path:** the MP workout's parsed_structure has
   `equivalent_race_pace: half@7:00/mi, confidence: 0.50`. The Observer
   *did* widen its confidence because the runner described conditions, but
   nothing downstream reads the mood or notes. The 7:45/mi pace becomes a
   data point that drags the anchor blend slightly slower. The prediction
   shifts in the wrong direction (slower fitness inferred from a hot
   workout).
2. **No surface that tells the user "I saw the heat note."** Even if the
   numbers happen to come out OK, the user has no signal that the system
   noticed. A coach would say it explicitly.

**This scenario is the strongest case for environmental keyword extraction.**

---

## Scenario 8 — MP block, no recent race (marathon-specific path)

**Persona.** Sarah is 8 weeks into the marathon build. Lots of long runs and
MP work, but the last race was 5 months ago. Tests whether the predictor
correctly *narrows* the marathon range when marathon-specific evidence is
strong, even without a recent race anchor.

**data_depth.** 3

### Inputs

- Workouts (180d):
  - 2025-12-15: Race, 10K, 6.21mi @ 6:18/mi → 39:08 (5 months ago — stale)
- Workouts (30d):
  - 2026-04-15: Long Run, 18.0mi @ 7:50/mi (last 6mi @ 7:30)
  - 2026-04-19: MP Workout, 14mi (3WU + 8mi @ 7:26 + 3CD)
  - 2026-04-22: Tempo, 8mi (2WU + 4mi @ 6:35 + 2CD)
  - 2026-04-26: Long Run, 20.0mi @ 7:55/mi (last 8mi @ 7:30)
  - 2026-04-30: Track, 6mi (8×800m @ 3:05)
  - 2026-05-03: Long Run + MP, 22mi (10mi easy + 10mi @ 7:26 + 2mi CD)
  - 2026-05-06: Easy Run, 6.0mi @ 8:35/mi
  - 2026-05-09: Long Run, 18.0mi @ 7:50/mi (last 6mi @ 7:25)
- Voice logs:
  - All confirming structured MP work with high parsed_structure confidence
- Plan: Chicago Marathon, goal 3:15

### Expected coach reasoning

This is a marathon-specific training block textbook page. Three long runs
≥18mi in the last 4 weeks (Apr 15, Apr 26, May 9; plus a 22mi on May 3 with
10 at MP). Total MP volume in last 6 weeks: ~32 miles. Max single MP
session: 10mi (May 3). Long-run criterion: comfortably met (≥2 ≥18mi in
6wk). MP-work strength signal: high.

Race anchor is stale (5 months). But the marathon-specific evidence is so
strong that the marathon prediction can be tight even without a recent
race. The 10K prediction, on the other hand, should be wider — Sarah hasn't
done short-fast work in months. Marathon-specific predictions can be more
confident than short-race predictions here. **This is the inverse of the
default flat-percentage rule.**

MSE ≈ 0.95. Marathon range multiplier ≈ 1.05 (essentially no widening).

### Expected predictor output

- **Anchor:** blend of training anchors (10mi @ MP, 8mi @ MP, multiple LRs
  with MP finishes) + stale race as floor
- **Tier:** medium (no recent race; multiple MP workouts in 6 weeks → high
  per edge function rule, but no race anchor → medium per iOS rule)
- **Predictions (point ± range):**
  - 10K: 38:30 ± 1:30 (wider — no recent speed work)
  - Half: 1:25:00 ± 2:00
  - **Marathon: 3:15:00 ± 2:30** (MSE 0.95 + tier medium 3.0% base ≈ 3.1% →
    ~6 min / 2 = ±3:00, then *× 1.05 multiplier* — wait, this should be
    *narrower* than the flat rule. See "tier vs. distance" note below.)
- **dataSource:** "Marathon-pace work (10mi May 3, 8mi Apr 19) and three
  long runs ≥18mi in the last 4 weeks"
- **summary:** "Your marathon fitness is the most measured signal in your
  data right now. The 10K/half predictions are wider because you haven't
  done short-fast work in a while."

### What today's predictor gets wrong

The flat-percentage range rule does the wrong thing here. Marathon range =
3% of 3:15:00 = ±5:50; 10K range = 3% of 38:30 = ±1:09. But the evidence
points the other way — marathon should be tighter (±2:30 or so), 10K
wider (±1:30+). The rule that the marathon range scales independently from
the 10K range — driven by the MSE score — is exactly what this scenario
exists to validate.

**Tier vs. distance note:** the v2 design should let the *marathon range
multiplier* go below 1.0× when MSE is very strong AND tier is anchored
mostly by marathon-specific evidence. Cap at 0.75× to avoid over-confidence.

---

## Scenario 9 — Returning from injury (4-week gap)

**Persona.** Sarah was 2 weeks into a marathon block, then a calf strain
shut her down for 4 weeks. She's now 2 weeks back, easing in.

**data_depth.** 3 (snapshots exist; current activity is sparse)

### Inputs

- Workouts (180d):
  - 2026-03-08: **Race, 10K, 6.21mi @ 6:13/mi → 38:35**
- Workouts (30d):
  - 2026-03-10 through 2026-04-05: **4-week gap, zero runs**
  - 2026-04-08: Walk-jog, 3.0mi @ 11:00/mi
  - 2026-04-11: Easy Run, 3.0mi @ 9:30/mi
  - 2026-04-14: Easy Run, 4.0mi @ 9:15/mi
  - 2026-04-17: Easy Run, 4.0mi @ 9:00/mi
  - 2026-04-21: Easy Run, 5.0mi @ 8:50/mi
  - 2026-04-25: Easy Run, 5.0mi @ 8:45/mi
  - 2026-04-28: Easy Run, 6.0mi @ 8:40/mi
  - 2026-05-02: Easy Run, 6.0mi @ 8:35/mi
  - 2026-05-05: Easy Run, 6.0mi @ 8:30/mi
  - 2026-05-09: Easy Run, 7.0mi @ 8:30/mi (first comfortable run)
- Voice logs:
  - 2026-04-08: "First run back. Calf held up. 11min/mi walk-jog."
  - 2026-04-21: "5 miles easy felt good. No calf signal."
  - 2026-05-09: "7 today. Felt like a real run for the first time."
- Plan: Chicago Marathon, goal 3:15 (last touched before injury)
- Snapshots: 2026-03-08 prediction — 10K 38:35 HIGH, marathon 3:01 HIGH

### Expected coach reasoning

The 10K race in early March is still proof of past fitness, but Sarah has
been out for 4 weeks and back for 5 weeks of easy-only running. Detraining
is real. The local engine's decay model is calibrated to a runner with
*some* stimulus; here we have a 4-week zero followed by 5 weeks of zero
quality. That's outside the regime the constants were tuned for.

What I actually know:
- Past 10K fitness was 38:35 (~6:13/mi)
- 9 weeks elapsed since proof, with a 4-week zero and 5 weeks of easy
- No quality work has been done; the maintenance factor is near zero
- Easy pace has progressed 11:00 → 8:30 over 5 weeks, which is a healthy
  comeback curve, not stagnation

Detraining math (loose): VO2max declines ~7% in 3-4 weeks of zero training,
recovers faster than it dropped if you ramp sensibly. After 4 weeks zero +
5 weeks easy-only, I'd estimate fitness is back to ~85-90% of pre-injury.
That's a real fitness signal — but it's a *prior*, not a measurement.
Range should widen sharply to reflect that.

### Expected predictor output

- **Anchor:** decayed snapshot baseline (last HIGH snapshot Mar 8 + decay
  factor for the gap)
- **Tier:** **low** (anchor is stale, no current quality work — even
  though a "race exists," it's not actionable evidence of current fitness)
- **Predictions (point ± range):**
  - 10K: ~41:00 ± 2:30 (5% range)
  - Marathon: 3:15:00 ± 16:00 (5% × 2.0 MSE multiplier — long-run and MP
    criteria both unmet)
- **dataSource:** "Pre-injury 10K (March) adjusted for 4-week break + 5
  weeks of easy-only running. Range widened — no recent quality work to
  measure current fitness."
- **summary:** "You're back, which is the win. I don't have current
  quality work to measure fitness sharply — that's why the range is wide.
  A tempo or interval session in the next 2 weeks would tell us where you
  actually are."

### What today's predictor gets wrong

The detraining decay (`L344-350`, `L611`) gets applied because there's a
snapshot baseline, but the *tier* stays at the snapshot's recorded
confidence ("High" or "Medium" from the past). It should drop to **low**
when the maintenance factor is near zero for >4 weeks — even the constants
are no longer trusted. Also: the range stays flat-percentage, so the
marathon range comes out way too narrow given the comeback context.

---

## Scenario 10 — Goal pace far from current fitness

**Persona.** Sarah's goal is 3:00 marathon (set when she signed up
optimistically). Her actual fitness reads 3:18. Tests whether the predictor
masks the gap or surfaces it.

**data_depth.** 3

### Inputs

Same training data as Scenario 5 (recent 10K race at 38:35, plus MP work
suggesting marathon ~3:01-3:05), but:

- Plan: Chicago Marathon, goal **3:00:00**, currently week 16/26

### Expected coach reasoning

Goal is 3:00. That requires ~6:52/mi marathon pace. Sarah's recent MP
workouts have been at 7:26/mi — that's the pace she labels "MP" in her
voice logs, and it matches her plan-derived marathon pace. Her 10K at 38:35
projects to ~3:01. Her training is *consistent with a 3:01-3:05 marathon*,
not 3:00. The goal is 1-5 minutes off her current trajectory.

A coach wouldn't say "you can't hit 3:00." A coach would say "the data
points to 3:01-3:09; 3:00 is at the edge of what your current fitness
supports, and only if conditions cooperate." That's honest.

The predictor must show *current fitness*, not let the goal anchor it.

### Expected predictor output

- **Anchor:** 10K race Apr 19 + recent MP work (same as Scenario 5)
- **Predictions:** same point estimates as Scenario 5 (the goal does not
  change the math)
- **dataSource:** "10K race Apr 19, MP work May 6/May 10"
- **summary:** "Your current fitness reads 3:01-3:09 marathon. Your goal
  is 3:00. The goal is at the edge of what your training supports —
  achievable on a great day, not the median outcome. Worth a chat with
  your coach about whether the plan needs more MP volume or whether 3:01-
  3:05 is the right target."

### What today's predictor gets wrong

The current local engine handles this correctly in spirit (it uses the race
anchor, not the goal, when a race exists). But the *summary text* doesn't
articulate the goal-vs-truth gap. A user looking at the prediction would
see "3:01 marathon, HIGH CONFIDENCE" and "Goal: 3:00" in two separate UI
slots and might miss the implication. The summary line should explicitly
name the gap.

Stronger failure case: if there were *no* race anchor and the plan goal
fed in as the fallback anchor (`L408-413`), the prediction would absorb
the unrealistic goal. The fix: plan goal as anchor should only fire at
data_depth 0/1, and even then with a tier ceiling of "medium." Once real
evidence exists, real evidence wins.

---

## Cross-scenario summary

| # | Tier | MSE | Key gap exposed |
|---|---|---|---|
| 1 | (null) | n/a | No fabrication on empty |
| 2 | (null) | n/a | Don't infer from easy runs (delete 0.95 fallback) |
| 3 | medium | 0.0 | Marathon range must widen independently |
| 4 | medium | 0.0 | Niggle/fatigue widens range |
| 5 | high | ~0.65 | Goal-vs-current comparison surfaced |
| 6 | high* | ~0.7 | Recency blend, not pick-one; tier alignment iOS↔edge |
| 7 | high | ~0.95 | Environmental keyword extraction & adjustment |
| 8 | medium | ~0.95 | Distance-specific range can go *below* 1.0× when evidence warrants |
| 9 | **low** | 0.0 | Tier must drop on extended low-stimulus regime |
| 10 | high | ~0.65 | Goal gap surfaced in summary text, never masking truth |

\* Scenario 6 tier depends on whether the recency rule is borderline-inclusive.

## What the v2 prompt has to do (preview of Step 3)

Based on these scenarios, the v2 prompt — repositioned as the **narrative
layer** over Path A's numbers (per the disposition we agreed) — needs to:

1. Take Path A's structured output (anchor, point estimates, tier, MSE,
   trend signal, niggle/fatigue flag, environmental notes) and produce a
   2-4 sentence coach summary.
2. Always cite at least one specific number per the data_depth pull-quote
   rule.
3. Surface the goal-vs-current gap when one exists.
4. Surface the distance with the widest range (the "soft spot") and what
   would tighten it.
5. Never recommend stopping, diagnosing, or treating — defer to the coach.
6. Never invent data not in the input.

The arithmetic stays in Swift. The prompt's job is to talk like a coach
about numbers it didn't compute.

When you're ready, I'll move to Step 3.
