# Race Performances — Feature Plan

**Status:** Draft / planning, May 2026
**Owner:** TBD
**One-liner:** The athlete's confirmed race history becomes the AI's fitness
ground-truth — anchoring pace zones, predictions, and coachable-moment
reasoning, validated continuously by current training data.

---

## Why this matters

Today the system anchors everything off `goal_time`: pace zones, marathon
prediction, ACWR context, plan templates. A goal time is an aspiration, not
a measurement. For a new user with no goal set, the AI is operating with
zero fitness signal until 21 days of base data accrue.

A confirmed race in the recent past collapses that uncertainty. A 1:32 half
from 6 weeks ago tells the AI more about this athlete's current fitness than
21 days of easy aerobic running. The race-equivalence ratio table in
`derivePaceTableFromGoal` already exists — it just needs an empirical anchor
instead of an aspirational one.

This is also the cleanest fix for the new-user "AI has no idea who I am"
problem flagged in `outputs/new-user-action-plan.md`. An athlete who connects
HealthKit during onboarding gets her last 12 months of races auto-detected,
confirms them, and jumps from `data_depth: 0` to a working fitness model
immediately.

---

## What's already in the codebase

This feature is less greenfield than it looks. A codebase review surfaced
substantial existing infrastructure:

- **`athlete_state.confirmed_races`** — JSONB array of
  `{ date, distance, finish_time_seconds, official, event_name }`. Added in
  a May 2026 migration. Not yet consumed by most surfaces.
- **`fitness-predictor` edge function** — uses Claude Haiku, returns
  range + confidence tiers (HIGH/MEDIUM/LOW) for 5K through marathon. Has
  confidence logic that already promotes HIGH for recent race ≥10K within
  8 weeks — but infers from `workoutType === "Race"` on training logs,
  *not* from `confirmed_races`.
- **`paceTableFromProfile`** in `_shared/paces.ts` — already pluggable;
  picks "goal race or first-available pace as anchor." Adding race-anchor
  selection is a small refactor.
- **`fitness_snapshots` table + `athlete_state.fitness_trend`** —
  trajectory enum exists: `building | peaking | maintaining | returning |
  declining`. Plus `fitness_vs_6mo_ago_seconds`. The "fitness identity"
  concept is half-built.
- **`computeDataDepth()`** in `_shared/athlete-state.ts` — already has a
  goal-based fast-path. Adding a race-based fast-path is one branch.
- **No coachable-moment rules read race history.** All four current rules
  are race-blind. The three new rules proposed below are net-new.
- **No LLM prompts inject race context** — even though `confirmed_races`
  exists. Largest leverage point for near-zero-cost improvement.

**Implication:** v1 is mostly a wire-up project, not a build-from-scratch.
The schema, the predictor, and the pace-zone math already exist. What's
missing is letting them talk to each other through `confirmed_races`.

---

## Product decisions (May 2026 design session)

These ten decisions resolve the design ambiguities. Implementation must
honor them.

1. **Goal vs. race conflict → show both views.** When recent race fitness
   contradicts goal time, the athlete and coach see both pace tables side
   by side ("goal pace" vs. "current fitness pace") and choose which to
   train against. AI does not pick.

2. **Staleness → adaptive to training quality.** A race stays a HIGH-
   confidence anchor only while current training (especially MP-zone work)
   validates the implied fitness. If recent MP workouts drift slower than
   the anchor predicts, the anchor demotes — even if the race is recent.

3. **Onboarding → HealthKit sync first, confirm races second.** New users
   connect HealthKit before being asked to type anything. The classifier
   surfaces candidate races from the last 12 months. The athlete confirms,
   edits, or dismisses. **This promotes the auto-suggest classifier from
   v1.1 to v1** — it's how onboarding works.

4. **Anchor visibility → quiet, available on tap.** Workout cards show the
   pace (e.g., "Tempo 5mi @ 7:18"). A small "why this pace?" link expands
   to reveal the anchor and the race-equivalence math. Coach view stays
   more explicit by default.

5. **Multi-race anchoring → best context-adjusted race = ceiling,
   current training validates.** Not a weighted blend. The race with the
   highest implied fitness (after context adjustment) becomes the
   ceiling. Current training data confirms or demotes that ceiling.
   Rationale: a bad race doesn't erase fitness; a great race demonstrates
   a fitness ceiling.

6. **Race context → downweights implied fitness signal.** Effort flag
   (A-race / B-race / training) and conditions tags (heat, cold, hills,
   wet) reduce the anchor weight. A 3:48 marathon in 90°F heat tagged
   "B-race" might imply 3:35 fitness, not 3:48. Context is structured,
   not just notes.

7. **Drift detection → tell the athlete directly.** When current training
   drifts slower than the anchor predicts (per decision 2), Today shows
   a nudge: *"Your recent MP work has been running slower than your
   April half-marathon predicts. Want to recalibrate zones?"* In coached
   mode the nudge includes a "talk to your coach" affordance; in
   self-coached mode the athlete can recalibrate themselves.

8. **Time-trial vs. race → separate suggestion category.** Fast efforts
   that lack race signals (Tuesday morning, no race tag, no race name)
   get flagged as *possible time trials*, not races. Athletes confirm
   the category. TTs and races stay distinct in the schema; both feed
   fitness reasoning but with different weight defaults.

9. **Authorship → athlete wins on own data, coach gets notified.** If a
   coach enters a race during intake and the athlete later edits it
   (gun time vs. chip time, conditions, etc.), the athlete's edit
   sticks. The coach sees a notification and can revert if needed.
   Athletes own the source of truth on their own bodies.

10. **Post-race → auto-confirm when signals are strong.** When HealthKit
    race-event tag is present + distance matches a canonical race
    distance + workout falls in the goal-race window, the system
    auto-confirms overnight and updates the anchor. Athlete sees a
    confirmation on Today and can correct if wrong. Lower-signal races
    still go through the confirm card flow.

---

## Data model

### v1: extend `confirmed_races` JSONB

The existing `athlete_state.confirmed_races` JSONB array works for v1.
Extend its shape:

```ts
type ConfirmedRace = {
  // existing
  id: string                  // UUID, added so edits are addressable
  date: string                // ISO date
  distance_meters: number     // canonical or near-canonical distance
  distance_label: '5K' | '10K' | 'HM' | 'M' | 'ULTRA' | 'OTHER'
  finish_time_seconds: number
  official: boolean
  event_name?: string

  // new for v1 (per decisions 6, 8, 9, 10)
  category: 'race' | 'time_trial'
  effort_flag?: 'A' | 'B' | 'training'
  conditions?: Array<'hot' | 'cold' | 'wet' | 'humid' | 'hilly' | 'flat' | 'altitude'>
  notes?: string
  source: 'manual' | 'auto_suggested_confirmed' | 'auto_confirmed' | 'coach_entered'
  source_workout_id?: string  // HealthKit/training_log row this was lifted from
  authored_by: 'athlete' | 'coach'
  last_edited_by: 'athlete' | 'coach'
  edit_history?: Array<{ at: string; by: 'athlete' | 'coach'; field: string; from: any; to: any }>
  computed_anchor_weight: number  // 0.0–1.0, derived from effort_flag + conditions
  is_active: boolean          // soft-delete
}
```

**Why JSONB rather than a new table:** the existing surface already
exists, the predictor doesn't yet read from it, and an athlete has on
the order of 5–20 races a year — small enough that JSONB is fine. A
proper relational `race_performances` table is the right v1.5 move when
auto-suggest reaches enough volume to justify the migration cost and we
need richer query patterns (e.g., coach-roster-wide race calendars).

### v1 migration: validation queue (separate)

The auto-suggest review flow needs its own table — JSONB is wrong for a
queue:

```sql
CREATE TABLE race_suggestions (
  id UUID PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_workout_id TEXT NOT NULL,
  suggested_category 'race' | 'time_trial' NOT NULL,
  suggested_distance_label TEXT NOT NULL,
  suggested_distance_meters NUMERIC NOT NULL,
  suggested_finish_time_seconds INTEGER NOT NULL,
  classifier_confidence NUMERIC NOT NULL,  -- 0.0–1.0
  status 'pending' | 'confirmed' | 'dismissed' | 'reclassified' NOT NULL,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
```

Hard rule compliance (`CLAUDE.md`): RLS in the same migration. Athlete
SELECTs / UPDATEs own rows; coach SELECTs roster rows via
`current_coach_id()`. Suggestions are inserted only by the service-role
nightly classifier — no client INSERT policy.

---

## Entry: three-tier confidence model

All paths converge on `confirmed_races`. The tiers differ in how much
athlete confirmation is required.

### Tier 1 — Auto-confirm (decision 10)

Conditions, all required:
- HealthKit `HKWorkoutEventTypeRace` marker present, OR workout name
  contains a race-like string match
- Distance within 0.5% of a canonical race distance
- Workout date within `goal_race.date ± 2 days` (if a goal race exists)

Action: nightly job writes directly to `confirmed_races` with
`source: 'auto_confirmed'`, surfaces a "we confirmed this — correct?"
card on Today the next morning.

### Tier 2 — Auto-suggest race candidate

Conditions:
- Distance within 1.5% of a canonical race distance
- Pace materially faster than trailing 30-day median for similar
  distance (>2 SD), OR HealthKit race tag present
- Outside the goal-race window OR no goal set

Action: row written to `race_suggestions` with `status: 'pending'`.
Surfaces in onboarding queue and in Train > Profile as "Was this a race?"
candidates.

### Tier 3 — Suggest as possible time trial (decision 8)

Conditions:
- Fast effort (>2 SD faster than trailing 30-day median for the distance)
- No HealthKit race tag
- Distance near canonical but no other race signals (weekday, no race name)

Action: row written to `race_suggestions` with
`suggested_category: 'time_trial'`. Surfaces as "Looks like a hard effort —
was this a time trial?" Athlete can confirm as TT, reclassify as race,
or dismiss.

### Manual entry path

Always available from Train > Profile. Same fields as the JSONB shape.
Writes with `source: 'manual'`, `authored_by: 'athlete'`.

### Coach-entered path

During coached-mode intake, the coach can fill in athlete history.
Writes with `source: 'coach_entered'`, `authored_by: 'coach'`. Athlete
can edit per decision 9.

---

## Anchor selection (decision 5)

Pseudocode for the anchor picker. Lives in `_shared/paces.ts` as a new
function `selectFitnessAnchor()`, called by `paceTableFromProfile`.

```ts
function selectFitnessAnchor(
  races: ConfirmedRace[],
  goalRace: GoalRace | null,
  recentTrainingPaces: WorkoutPaceSample[]
): { anchor: AnchorSource; validated: boolean; confidence: 'HIGH' | 'MEDIUM' | 'LOW' } {

  // 1. Filter to active, non-archived races within staleness window
  const candidates = races.filter(r =>
    r.is_active &&
    daysAgo(r.date) <= 180 &&   // hard cap at 6 months
    canonicalDistance(r.distance_label)
  )

  if (candidates.length === 0) {
    return { anchor: goalRace, validated: false, confidence: 'LOW' }
  }

  // 2. Compute context-adjusted implied fitness per race (decision 6)
  //    e.g., 3:48 marathon in heat + B-race might imply 3:35
  const adjusted = candidates.map(r => ({
    race: r,
    impliedFitnessSecPerMile: adjustForContext(r),
  }))

  // 3. Pick the race implying the highest fitness
  const best = adjusted.reduce((a, b) =>
    a.impliedFitnessSecPerMile < b.impliedFitnessSecPerMile ? a : b
  )

  // 4. Validate with current training (decision 2)
  const validation = validateAnchorAgainstTraining(best, recentTrainingPaces)
  // returns { holds: bool, driftSecPerMile: number }

  // 5. Confidence tier
  let confidence: 'HIGH' | 'MEDIUM' | 'LOW' = 'LOW'
  if (validation.holds && daysAgo(best.race.date) <= 56) confidence = 'HIGH'
  else if (validation.holds) confidence = 'MEDIUM'
  else if (daysAgo(best.race.date) <= 56) confidence = 'MEDIUM' // recent but drifting
  else confidence = 'LOW'

  return { anchor: best.race, validated: validation.holds, confidence }
}
```

`adjustForContext()` is a small structured function — not LLM — that
applies fixed multipliers. E.g.:

| Tag | Multiplier on implied fitness |
|---|---|
| `B-race` effort | -1.5% (faster implied) |
| `training` effort | -3% |
| `hot` conditions | -1% per 10°F above 60°F |
| `humid` | -0.5% |
| `hilly` | -1.5% |
| `wet` | -0.5% |

Multipliers stack. Final adjustment capped at ±5% to prevent overfitting.
Document these in the function and review with coaches before launch.

`validateAnchorAgainstTraining()` checks the most recent N MP-zone or
LT-zone workouts and compares actual paces to anchor-implied targets.
Drift > 3% sustained over 3+ workouts → anchor demotes (decision 7
fires the nudge).

---

## Placement in the IA

The 4-tab nav (Today / Voice / Train / Coach) is fixed. Race performances
live within it per decision 4.

### Today tab — anchor as quiet context

At `data_depth >= 2`, workout cards show pace targets with a small "why
this pace?" link. Tap reveals:

> *"MP zone (7:18/mi) calibrated to your 1:32 half from April 4. Today's
> tempo sits at race pace."*

When the AI detects drift (decision 7), Today shows a nudge:

> *"Your recent MP work has been running slower than your April half
> predicts. Want to recalibrate?"*

Nudge respects `data_depth` — at depth 1, simpler language; at depth 3,
the full editorial register applies.

### Train tab — Profile section (new)

A new "Profile" section alongside Pace Zones and the plan view. Contains:

- **Fitness anchor** — the currently selected anchor race, with implied
  fitness and validation status
- **Goal race** (if set)
- **Recent race performances** — the active list, most recent first,
  with effort flags and conditions
- **Time trials** — separate sub-list
- **Pace zones** — derived from the anchor

The Profile section is the athlete's "fitness identity" — the source of
truth that everything else derives from.

### Coach tab — coach-visible only in coach view

When the athlete is in coached mode, the coach sees the same data in the
coach portal. The coach view shows authorship metadata explicitly (per
decision 9): "Coach entered 1:42 · Athlete corrected to 1:40."

### Onboarding flow (decision 3)

```
Welcome
  ↓
Connect HealthKit  ← required for v1 onboarding
  ↓
Classifier runs in background (≤15s) on last 12 months
  ↓
"We found these races — confirm or correct"
  - 4/12/2026 · Half-marathon · 1:32:04   [confirm] [edit] [dismiss]
  - 2/8/2026  · 10K · 41:30                [confirm] [edit] [dismiss]
  ↓
Optional: "Anything we missed?" → manual entry
  ↓
"What are you training for?" — goal race (skippable)
  ↓
Done. Today is populated.
```

For athletes without HealthKit data, fallback to manual entry. Onboarding
shouldn't block on auto-detect.

---

## Integration points — how this ties into everything

This is the "ties into everything" part. Most of the work is wiring
`confirmed_races` and the new anchor selector into surfaces that already
exist.

### 1. Pace zone derivation (`paceTableFromProfile`)

Today: anchors off goal race or first-available pace.
Change: call `selectFitnessAnchor()` first; if it returns a race anchor,
use that; otherwise fall back to goal time.

Must mirror across the three implementations (per `CLAUDE.md`):
- `web/src/components/coach/workout-helpers.ts`
- `supabase/functions/_shared/paces.ts`
- `RunningLog/Workouts/PaceCalculator.swift`

The race-equivalence ratio math is unchanged. Only the anchor selection
is new.

### 2. `fitness-predictor` edge function

Today: confidence inferred from `workoutType === "Race"` on training logs.
Change: read `athlete_state.confirmed_races` directly. Promotes confidence
to HIGH when a recent canonical race exists *and* training validates the
anchor (calls `selectFitnessAnchor()`). Bumps the prediction range
narrower per `outputs/marathon-prediction-honesty.md`.

### 3. `data_depth` race-based fast-path

Today: `hasActiveGoal && workoutCount >= 1` promotes to depth 3.
Change: add `hasValidatedRaceAnchor` as an equivalent promoter. One
confirmed recent race + 1+ training run jumps the athlete to depth 3
on day one. New branch in `computeDataDepth()`.

### 4. LLM prompt context injection

The largest leverage point. `generate-workout-insight`, `reschedule-plan`,
and `fitness-predictor` all currently skip `confirmed_races`. Add a
shared `formatRaceContext()` helper that produces a 2–3 sentence summary
for inclusion in any prompt:

> *"Athlete's current fitness anchor: 1:32 half-marathon on April 4
> (40 days ago, A-race, validated by 4 of the last 5 MP-zone workouts).
> Implied marathon range: 3:15–3:19, HIGH confidence."*

Add this to system or user prompts where fitness reasoning matters.
Cost: near zero. Benefit: AI commentary stops being fitness-blind.

### 5. Coachable moment rules (3 new)

All three are net-new — no existing rule reads race history.

- **`paceTargetMismatch`** — fires when scheduled workout pace is
  materially out of line with what the validated anchor predicts.
  Surfaces to coach: *"Athlete's plan calls for MP at 7:00, but their
  validated anchor predicts MP closer to 7:18."*
- **`fitnessRegressionFlag`** — fires when a recent race is materially
  slower than a >6-months-prior race beyond the normal seasonal envelope.
  Coach-only.
- **`peakFitnessWindowOpening`** — fires when the validated anchor
  trajectory + workout pace trend suggest the athlete is approaching
  peak fitness for their goal race.

### 6. Drift nudge (decision 7)

New surface on Today. Reads from `selectFitnessAnchor()` output —
specifically the `validated: false` case. Renders the nudge with
appropriate copy for `data_depth` and coached vs. self-coached mode.

### 7. ACWR contextualization

Today: ACWR interpretation is purely numeric in
`loadSpikePlusInjury` rule.
Change: when ACWR spike falls in a 14-day pre-race or 7-day post-race
window (read from `confirmed_races`), suppress or de-prioritize the
alert. Race calendar explains the spike.

### 8. Voice log fatigue contextualization

Today: `lowMoodStreak` rule fires on 3 consecutive low-mood voice logs.
Change: suppress when within 7 days post-race. Fatigue is expected.

### 9. Plan template selection

Today: templates select on goal distance + goal time + weeks remaining.
Change: templates also accept a `current_fitness_anchor` parameter.
Improves template fit for athletes whose goal is aspirational vs.
current fitness.

### 10. Coach portal intake

When an athlete joins a coach, the coach instantly sees the 12-month
race history in the athlete's profile view. Replaces or supplements the
typical intake questionnaire.

### 11. Niggles temporal correlation

When a new niggle is reported within 14 days of a confirmed race, the
coach view surfaces the temporal context: *"Athlete reports left knee
niggle. Note: marathon completed 11 days ago."* No diagnosis. Honors
`outputs/body-mentions-design.md`.

---

## Phasing

### v1 (this build)

- Extend `confirmed_races` JSONB shape (decisions 6, 8, 9, 10 fields)
- New `race_suggestions` table + RLS
- Auto-suggest classifier (nightly job, 3-tier confidence model)
- Auto-confirm path for race-day matches
- `selectFitnessAnchor()` function with context adjustment + training
  validation
- `paceTableFromProfile` wired to use selector (web, edge, iOS)
- `fitness-predictor` reads `confirmed_races` directly
- `data_depth` race-based fast-path
- Train > Profile section
- Today: anchor "why this pace?" tap + drift nudge
- Onboarding: HealthKit-first flow with confirm queue
- `formatRaceContext()` helper + injected into existing prompts

### v1.1

- Three new coachable-moment rules
  (`paceTargetMismatch`, `fitnessRegressionFlag`, `peakFitnessWindowOpening`)
- ACWR taper/recovery contextualization
- `lowMoodStreak` post-race suppression
- Coach portal: race history in athlete intake
- Authorship audit log surface in coach view

### v1.2

- Plan template selector accepts `current_fitness_anchor`
- Niggles temporal correlation surfacing
- Possibly promote `confirmed_races` JSONB to a `race_performances` table
  (only if query patterns justify the migration cost)

### v1.5

- Key workouts as fitness signal (definition TBD)
- Coach-roster-level race calendars (requires the table promotion)

---

## Open questions still to resolve

Most prior open questions are now resolved by the ten product decisions.
What remains:

1. **Context-adjustment multipliers** — the table in the anchor selection
   section is a starting point. Coaches should review and tune before
   launch. Suggest: pre-launch session with 2–3 coaches.
2. **Auto-confirm threshold tuning** — Tier 1 conditions are written
   conservatively (race tag + ±0.5% distance + goal window). Watch
   false-positive rate in v1, loosen if too few qualify.
3. **JSONB → table promotion criteria** — what counts as "query patterns
   justify the migration"? Suggest: when coaches start requesting
   roster-wide race calendars or attrition analysis.
4. **What does drift detection look like in coached mode specifically?**
   Decision 7 says "tell athlete directly with 'talk to your coach'
   affordance." Open: does the coach also get a parallel notification,
   or is the athlete-to-coach handoff manual?
5. **Eval harness coverage for the new LLM context injection.** Per
   `CLAUDE.md`, prompt changes require eval harness coverage — currently
   TBD. Race-context injection should land with the harness or in a
   feature-flagged rollout.

---

## Hard rules this feature must honor

Pulled from `CLAUDE.md`:

1. RLS in the same migration as `race_suggestions`. Use
   `current_coach_id()` for coach-scoped policies.
2. `TIMESTAMPTZ` for timestamps. `TEXT` for `user_id`. `UUID` for primary keys.
3. Migrations append-only.
4. Auto-suggest/auto-confirm inserts go through service-role edge functions.
5. Marathon prediction surfaces using race data show range + confidence,
   never a point estimate. Round to whole minutes.
6. AI commentary on race performances does not diagnose, recommend
   stopping training, or make medical claims. Defers to the coach.
7. No em-dashes as empty-state placeholders.
8. Pace-zone math changes mirror across web, edge, iOS.
9. Prompt changes (especially `formatRaceContext()` injection) require
   eval harness coverage or feature-flagged rollout.
10. `selectFitnessAnchor` is a pure function. Testable, deterministic,
    no LLM. Same input → same output.

---

## Next steps

1. Get this plan reviewed by coaches (decision 6 multipliers, drift
   detection copy, anchor-validation thresholds)
2. Schema migration draft for `race_suggestions` + extended
   `confirmed_races` shape
3. Build `selectFitnessAnchor()` as a pure function with unit tests
4. Wire `paceTableFromProfile` across the three implementations
5. Auto-suggest classifier as a standalone Deno script first; validate
   recall/precision on existing user data before wiring to onboarding
6. Train > Profile UI mock — separate doc
7. Drift nudge copy (depth 1, 2, 3 variants × coached/self-coached
   variants) — separate doc
