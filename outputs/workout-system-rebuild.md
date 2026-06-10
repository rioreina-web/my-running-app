# Workout System Rebuild — Design Decisions

**Status:** Decided May 2026. Source of truth for the rebuild PRs that follow.

## Context

As of May 2026, the codebase has three parallel plan-generation paths that
disagree with each other:

1. `generate-training-plan` — LLM-assisted plan generator backed by a
   Canova-derived workout library (~80 codes like BE_4, RP_6, RSS_2) and a
   four-phase periodization model.
2. `subscribe-to-plan` — materializes coach-authored templates for athletes,
   with auto-fill for easy / recovery / strides days.
3. `reschedule-plan` — LLM-driven schedule rewriter using the same Canova
   vocabulary, organized by a hardcoded Tue/Thu/Sat day structure.

These paths use different vocabularies (Canova percentages of MP speed vs.
the seven-zone race-equivalence pace chart in `workout-helpers.ts`),
disagree on conventions for strides and easy-day allocation, and overlap in
concerning ways. A recent bug audit found `subscribe-to-plan` was producing
half-mile easy days and double-strides weeks. The code review of that bug
surfaced larger consistency problems that won't be fixed by patching one
function.

This document captures the strategic and design decisions made for the v1
rebuild.

## Strategic decisions

### 1. No AI plan generator in v1

`generate-training-plan` and its skeleton+LLM architecture are cut. The
deterministic skeleton, the workout library, and the phase model are
reasonable v2 building blocks but they're not what's right for v1. The
wedge is **coach-authored plans + adaptive scheduling.** AI doesn't
generate plans; coaches do. AI helps adapt them within tight constraints.

### 2. Coach portal becomes the only plan-authoring path

All plans are coach-authored via `web/src/app/(app)/coach-portal/*`.
Templates can be reused across athletes. The athlete's only path to a plan
is subscribing to a coach-authored template. There is no self-coached AI
plan generation in v1.

### 3. `reschedule-plan` becomes deterministic

The LLM is removed. The function does shift-and-insert: move existing
workouts to other days, insert rest days, never invent or swap workouts.
Conversational explanation may still be LLM-generated as a thin display
layer, but the scheduling decisions are deterministic. Coach's intent
(workout type, content, prescribed mileage) is preserved exactly; the
system only rearranges *when.*

### 4. Canova vocabulary moves from code to docs

The workout library, phase model, and pace zone definitions are valuable
institutional knowledge but the wrong shape for v1 code. They get archived
to `docs/training-systems/` as reference markdown. The TypeScript that
encoded them is deleted from live code paths. Future v2 work can reference
these docs without dragging along the dead implementations.

### 5. No coach-specific or proprietary vocabulary

The system uses generic, non-IP-encumbered pace and effort terms (tempo,
threshold, MP, 5K, etc.). It does not structurally support Daniels' T/I/R
labels, Tinman's CV/CS labels, Canova's percentages, or similar
coach-system-specific vocabularies. If an athlete asks the AI assistant
what "T pace" or "VO2max" means in the context of their plan, the AI can
explain — that's a prompt/AI-layer concern, not a schema concern. The
data layer stays clean and consistent across coaches.

## Workout type — closed enum (10 entries)

Used only for scheduling logic. The system uses `workout_type` to decide
what can shift where, what counts as quality, what gets a recovery day
after, etc. Coaches pick from this list when authoring.

| Type | Purpose |
|---|---|
| `long_run` | Weekly long endurance run |
| `tempo` | Sustained sub-threshold to threshold effort |
| `intervals` | Repeats with measured recovery |
| `progression` | Workouts that get faster across the run |
| `fartlek` | Effort-based unstructured or semi-structured intervals |
| `hills` | Effort-anchored repeats on terrain |
| `easy` | Aerobic conversational pace |
| `recovery` | Slower-than-easy, low load |
| `rest` | No running |
| `race` | Race day |

`strides` is **not** a workout type. It is a modifier on `easy` workouts.

## Pace vocabulary — canonical 11-zone enum

Coaches use the system's pace vocabulary. Zones are derived from the
athlete's goal race time via `derivePaceTableFromGoal`. The vocabulary is
race-equivalence anchored — the system avoids physiological zones
(VO2max, CV, AeT) because those are inherently ranges, not single paces,
and trying to schema them creates ambiguity.

| Zone | Anchor |
|---|---|
| `recovery` | Slower than easy, by feel |
| `easy` | ~80% of MP speed |
| `steady` | ~85% of MP speed |
| `moderate` | ~88% of MP speed |
| `tempo` | Sub-threshold (between steady and threshold) |
| `threshold` | ~1-hour race pace, interpolated 10K↔HM |
| `MP` | Goal marathon pace |
| `HM` | Goal half-marathon pace |
| `10K` | Goal 10K pace (race-equivalence) |
| `5K` | Goal 5K pace (race-equivalence) |
| `mile` | Goal mile pace (race-equivalence) |

Aerobic zones (recovery, easy, steady, moderate, tempo) ship as ranges
(±5%). Race-pace zones (threshold, MP, HM, 10K, 5K, mile) ship as exact
single targets per the existing convention in
`web/src/components/coach/workout-helpers.ts`.

Specifically **not included** in the canonical vocabulary: VO2max, CV
(critical velocity), CS, AeT, AnT, T-pace, I-pace, R-pace, M-pace, E-pace,
sweet spot, lactate threshold (the system uses `threshold` instead).
Tempo and threshold overlap conceptually — both exist anyway because both
are useful labels in practice.

## Effort vocabulary — discriminated union

For workouts where pace isn't appropriate (hills, fartlek, strides), the
prescription uses an `effort` field instead of `target_pace`. Three
shapes, one discriminator:

```ts
effort:
  | { type: "race",    value: "sprint" | "mile" | "3k" | "5k" | "10k" | "half" | "marathon" }
  | { type: "percent", value: number }   // 60–100, percentage of max effort
  | { type: "feel",    value: "easy" | "steady" | "fast" }
```

Coaches pick the shape that fits the workout. Athletes see the value
verbatim. The system doesn't translate effort into pace targets. Examples:

- Hills @ mile effort → `effort: { type: "race", value: "mile" }`
- Hills @ 90% max → `effort: { type: "percent", value: 90 }`
- Fartlek with "fast / steady" alternations → segments use
  `{ type: "feel", value: "fast" }` and `{ type: "feel", value: "steady" }`
- Strides (relaxed) → `effort: { type: "feel", value: "easy" }` is wrong;
  strides have their own simpler shape (see below).

## Strides — modifier, not type

Strides decorate an easy workout. They are not a workout themselves.
Coaches don't prescribe "a strides day"; they prescribe "easy run plus
strides."

Schema:

```ts
strides: {
  count: number,                  // typically 4–8
  effort: "relaxed" | "fast"
}
```

Distance is always 100m and is implicit. No duration-based strides. No
"finisher" terminology — display label is just "strides." A workout's
title becomes e.g. `"6 mi easy + 6× strides"`.

`subscribe-to-plan`'s auto-strides logic writes a `strides` modifier onto
one existing easy day per week before a quality workout, rather than
creating a separate `strides` row. Strides only attach to `easy`
workouts — never to tempo, intervals, hills, long runs, or recovery.

## Hills — effort-anchored, first-class type

Hills can't be pace-anchored because gradient changes the effort-to-pace
relationship. Hills have their own prescription shape:

```ts
workout_type: "hills",
workout_data: {
  description: "10 × 30s hills @ mile effort, full recovery",
  reps: 10,
  rep_duration_seconds: 30,        // OR rep_distance_meters: 200
  effort: Effort,                  // discriminated union, see above
  recovery: "full walk down"       // free text
}
```

Either `rep_duration_seconds` or `rep_distance_meters` is set, not both.
The mileage estimator skips hill workouts (or estimates them at a nominal
flat figure — TBD).

## Rest — first-class log entry

Rest days are scheduled rows with `workout_type: "rest"` and
`total_distance_km: 0`. They appear in the training log as "Rest," count
toward "this week is complete" calculations, and can be marked completed
by the athlete.

Per the existing empty-state convention in CLAUDE.md (no em-dashes as
placeholders), a rest day card uses the empty-state component, not a
blank cell with a dash.

The shared analytics utilities (`weeklyAnalytics.ts`, `dataAnalysis.ts`)
should treat rest as *prescribed* (not missed) in compliance and ACWR
math. Any place currently filtering `workout_type !== "rest"` or
`total_distance_km > 0` needs audit — some are correct (rest doesn't
count toward mileage sums), some are bugs (rest treated as missed day).

## `workout_data` JSON shape (polymorphic)

Pace-anchored vs effort-anchored is determined by which fields are
present. No explicit discriminator — keeps existing data
backward-compatible.

**Pace-anchored** (easy, long_run, tempo, intervals, progression,
recovery, race):

```ts
{
  description: string,
  total_distance_km: number,
  target_pace: string,            // e.g. "7:45/mi"
  pace_zone: PaceZone,            // closed enum from above
  strides?: { count: number, effort: "relaxed" | "fast" },
  steps?: WorkoutStep[]
}
```

**Effort-anchored** (hills, fartlek):

```ts
{
  description: string,
  total_duration_minutes?: number,
  reps?: number,
  rep_duration_seconds?: number,
  rep_distance_meters?: number,
  effort: Effort,
  recovery?: string,
  segments?: Array<{ duration_seconds: number, effort: Effort }>
}
```

A zod (or equivalent) schema validator should land alongside the
migration to enforce these shapes for new writes. Existing rows that
don't match are left as-is — the new validator only gates writes from the
coach portal forward.

## What gets cut

| Path | Decision | Replacement |
|---|---|---|
| `supabase/functions/generate-training-plan/` (entire dir) | Delete | Coach-authored templates |
| `supabase/functions/generate-training-plan/deterministic-builder.ts` | Delete | n/a |
| `supabase/functions/_shared/workoutSelection.ts` | Delete | n/a |
| `WORKOUT_LIBRARY` (Canova codes) | Archive to docs, delete code | `docs/training-systems/canova-workout-library.md` |
| `WORKOUT_CODES_BY_DAY` in reschedule-plan | Delete | reschedule becomes deterministic shift+rest |
| iOS `AITrainingPlanService.swift` | Delete | n/a |
| iOS workout-code enum cases in `TrainingPlanModels.swift` | Trim to 10-value vocabulary | n/a |
| iOS `FitnessAssessmentModels.swift` Canova references | Trim | n/a |
| `quality_session_templates` table | Audit; likely delete | n/a |
| Athlete display special cases for `hill_repeats`, `time_trial`, `threshold` in `web/src/app/(app)/plan/page.tsx` | Remove | These become canonical types or get dropped |

## What gets kept and rebuilt

| Path | Change |
|---|---|
| `subscribe-to-plan` | Already fixed (half-mile and strides bugs, May 2026). Future: write strides as modifier on existing easy row instead of separate row. |
| `reschedule-plan` | Rewrite as deterministic shift+insert. Remove Gemini workout-selection call. Remove `WORKOUT_CODES_BY_DAY`. Optionally keep conversational message generation as a thin LLM layer. |
| Coach portal `workout-template-form.tsx` | Update workout type tabs to 10-value vocabulary. Add `fartlek`, `hills`. Remove `strides` (becomes modifier UI on easy). |
| Coach portal `workout-step-editor.tsx` | Add pace-vs-effort toggle per step. Effort sub-form (race picker / percent slider / feel chips). Update mileage estimator to handle effort-only steps. |
| Coach portal `plan-builder-client.tsx` | Update color maps, quick-add buttons, modal workout-builder for new enum. |
| Coach portal strides UI | Modifier on easy: count + relaxed/fast toggle. |
| `derivePaceTableFromGoal` | Produce the 11-zone canonical vocabulary. Add `tempo` as a distinct zone if not already there. Drop `longRun` (deprecated) and `3K` (too close to 5K to matter). |

## PR sequence

### PR 1 — Schema + enum reconciliation + dead code cut

- Migration: add CHECK on `workout_templates.workout_type` (10 values)
- Migration: update `scheduled_workouts.workout_type` CHECK to 10 values
- Backfill: `workout_type: "strides"` rows → `workout_type: "easy"` with
  `workout_data.strides` modifier (count existing rows first; per the
  audit, likely small population)
- Add zod (or equivalent) validator for `workout_data` shapes
- Delete `supabase/functions/generate-training-plan/` (entire directory)
- Delete `supabase/functions/_shared/workoutSelection.ts`
- Delete iOS `AITrainingPlanService.swift`
- Archive Canova vocab to `docs/training-systems/`

Append-only migrations per CLAUDE.md rule #5. RLS unchanged because no
new tables. Low risk because `workout_data` is JSONB and validation is
additive.

### PR 2 — Coach portal step editor + workout types

- Tabs in `workout-template-form.tsx` updated to 10-value vocabulary
  (add `fartlek` + `hills`, remove `strides`)
- Pace-vs-effort segmented control in `workout-step-editor.tsx`
- Effort sub-form components (race picker, percent slider, feel chips)
- Strides modifier UI on easy workouts (count + relaxed/fast)
- Mileage estimator handles effort-only steps (no distance → no
  estimate, show via empty-state component)
- `workout-helpers.ts` updated to expose the trimmed pace vocabulary

Biggest visual surface change. Blast radius: three files in
`components/coach/`. Risk: medium because effort-anchored steps are a
new UI pattern.

### PR 3 — Plan builder + cleanup

- `plan-builder-client.tsx` color maps, quick-add buttons, modal updated
- Decide and act on `quality_session_templates` (delete or keep)
- Remove athlete-side display special cases in
  `web/src/app/(app)/plan/page.tsx`
- Athlete pace chart UI updated for trimmed vocabulary

### PR 4 (separate sequence) — Reschedule-plan rewrite

- Replace Gemini call with deterministic shift+insert
- Type-preserving constraints (tempo stays tempo)
- Day-agnostic (no Tue/Thu/Sat assumption)
- Optional: thin LLM layer for conversational explanation only
- Add eval coverage when the eval harness lands (per CLAUDE.md rule #3)

## Open items / followups

- **AI translation prompts.** When an athlete asks the AI assistant "what
  is CV?" or "what does T pace mean in this plan?", the AI should answer
  with the equivalent in the canonical vocabulary. To be specified in the
  AI assistant system prompts. Out of scope for the schema PRs.
- **Eval harness.** Per CLAUDE.md rule #3, prompt changes can't ship
  without eval coverage. The conversational layer in reschedule-plan
  needs eval coverage when added. This is the broader P0 blocker called
  out in `outputs/production-readiness-rundown.md`.
- **Hills mileage estimation.** Hills don't have distance per se. The
  athlete weekly mileage chart needs a decision: estimate hills at a
  fixed nominal distance, exclude from totals, or count rep_distance_meters
  × reps if available.
- **Fartlek prescription shape.** Both structured `segments` and free-text
  `description` are supported (one or both populated). Worth a coach UX
  test to see which is preferred in practice.
- **`quality_session_templates` table.** Audit-flagged as orphan if the
  two-lane canvas is cut. PR 3 needs an explicit decision.
- **Backfill scope for strides.** No athletes use AI-generated plans
  currently. The strides backfill (`workout_type: "strides"` →
  `workout_type: "easy"` + modifier) may still hit production rows from
  earlier coach-authored templates — count before backfilling, write a
  reversible backfill in case.
- **Pace-vocabulary drift between iOS and web.** `derivePaceTableFromGoal`
  has parallel implementations in
  `web/src/components/coach/workout-helpers.ts`,
  `supabase/functions/_shared/paces.ts`, and
  `RunningLog/Workouts/PaceCalculator.swift`. When the trimmed vocabulary
  lands, all three must move together (per CLAUDE.md note on this).

## Files involved

For PR 1 (schema + cuts):
- `supabase/migrations/<new>_workout_type_vocabulary.sql` (new)
- `supabase/migrations/20260312_coach_training_plans.sql` (reference only)
- `supabase/migrations/20260227_plan_builder_setup.sql` (reference only)
- `supabase/functions/_shared/workoutSelection.ts` (delete)
- `supabase/functions/generate-training-plan/` (delete entire directory)
- `RunningLog/RunningLog/Training/AITrainingPlanService.swift` (delete)
- `RunningLog/RunningLog/Models/TrainingPlanModels.swift` (trim)
- `RunningLog/RunningLog/Models/FitnessAssessmentModels.swift` (trim)

For PR 2 (step editor):
- `web/src/components/coach/workout-template-form.tsx`
- `web/src/components/coach/workout-step-editor.tsx`
- `web/src/components/coach/workout-helpers.ts`

For PR 3 (plan builder):
- `web/src/components/coach/plan-builder-client.tsx`
- `web/src/components/coach/workout-template-card.tsx`
- `web/src/app/(app)/plan/page.tsx`

For PR 4 (reschedule):
- `supabase/functions/reschedule-plan/index.ts`
- `supabase/functions/_shared/prompts/reschedule-plan.v1.ts`
- `RunningLog/RunningLog/Training/RescheduleService.swift`
- `RunningLog/RunningLog/Training/RescheduleSheet.swift`

For archive (PR 1 includes these as new files):
- `docs/training-systems/canova-workout-library.md` (new)
- `docs/training-systems/phase-model.md` (new)
- `docs/training-systems/canova-pace-zones.md` (new)
