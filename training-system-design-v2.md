# Training System v2 — Design

**Status:** Design proposal, for decision.
**Author:** Claude, with Rio.
**Scope:** Training subsystem only — plan, schedule, execution, and coaching as it touches training. Does not touch auth, blog, payments, transcription, or injury-analysis pipelines.
**Target user:** BQ-aspiring runner, 50-70 mpw, wants structure + autonomy.

---

## 1. Why we're redesigning

The current training system fails for structural reasons, not polish reasons:

1. **Entities are tangled.** `training_plans` → `scheduled_workouts` pins every workout to a date at creation. There is no layer for "the coach's intent this week" separate from "the athlete's decision about what day." You cannot build flexibility on top of this without restructuring the core tables.

2. **The coach is blind to the plan.** `coaching-agent` reads memories, profile, goals, and injuries. It does not read `scheduled_workouts` or `training_plans` in a grounded way. Every coaching response is essentially ungrounded.

3. **Seven context builders compete.** `buildThisWeekContext`, `buildTrainingPeriodDocument`, `buildProfileContext`, `buildInjuryContext`, `buildMemoryContext`, `buildAthleteProfileContext`, `stateToPromptContext`. They overlap, compress aggressively, and the signal is lost before the model sees it.

4. **Seven creation UIs.** `WorkoutGeneratorView`, `WorkoutTemplateEditorView`, `WorkoutTemplateLibraryView`, `WorkoutChatSheet`, `CustomPlanBuilderView`, `PlanGeneratorSheet`, `AIPlanChatSheet`. No unified model of "here is how an athlete creates or edits a workout."

5. **No feedback loop closes.** Voice memos capture qualitative data. Workouts capture quantitative data. Nothing joins actual execution to planned target with weather and pace adjustment applied, and nothing feeds that reconciliation back into next week's plan.

6. **Corrections don't stick.** The memory write-path appends; it doesn't supersede. Stale facts keep surfacing in context, which is why athletes feel "the coach doesn't know me."

The incremental path costs the same as the redesign but leaves the tangles in place. We should redesign.

---

## 2. Design principles

1. **Separation of intent from execution.** The coach commits to *what* a week should contain. The athlete commits to *when*. These are different tables, not the same table with a nullable date.
2. **One source of truth per concern.** One context builder. One pace context. One state object.
3. **Everything the coach says is cited.** Every recommendation references a specific workout, week, or metric. If the data isn't there, the coach says so instead of generalizing.
4. **Corrections are first-class writes.** When an athlete corrects the coach, that fact supersedes prior beliefs atomically. No append-only memory.
5. **Weather is a property of every pace.** A target pace is a function of temperature + dew point. The model, the UI, and the coach all use the adjusted value — never the raw one in isolation.
6. **AI is a front-end to structured operations, not a free-form reasoner.** The coach proposes actions (reschedule, swap, regenerate). The athlete confirms. Actions are structured writes, not prose.
7. **A BQ runner can see exactly what's going to happen.** Every layer is inspectable. No black boxes in coaching advice.

---

## 3. Data model (v2)

### Core entities

```
user_goals                    (exists)
  └── training_plans          (exists, simplified)
       └── plan_weeks         (NEW) — one row per week, carries intent
            ├── quality_sessions  (NEW) — 1-3 per week, assigned_date nullable
            └── easy_fills        (NEW) — athlete-scheduled easy/recovery runs
                 │
                 ▼
training_logs                 (exists, extended with weather + reconciliation)
  └── workout_reconciliations (NEW) — join of log ↔ planned target
       │
       ▼
coaching_events               (NEW) — single timeline of coach actions/learnings
```

### New tables

**`plan_weeks`**
```sql
id uuid pk
plan_id fk → training_plans
week_number int
start_date date          -- monday of this week
phase text               -- 'base' | 'build' | 'peak' | 'taper' | 'race' | 'recovery'
intent_md text           -- coach's one-paragraph intent for this week, human-readable
target_volume_miles numeric
target_quality_count int -- usually 2-3
target_recovery_days int -- usually 2-3
status text              -- 'draft' | 'active' | 'complete'
notes text
created_at, updated_at
```

**`quality_sessions`**
```sql
id uuid pk
plan_week_id fk → plan_weeks
kind text                -- 'threshold' | 'intervals' | 'long_run' | 'tempo' | 'race_simulation' | 'fartlek'
name text                -- coach's human name: "Progression long run"
purpose_md text          -- one sentence: "build lactate clearance"
structure_json jsonb     -- canonical workout shape (segments, paces, reps)
pace_reference_distance text -- '5K' | '10K' | 'half' | 'marathon' | 'mile' — NEVER methodology letters
priority int             -- 1 = immovable, 2 = preferred, 3 = flex
assigned_date date nullable -- the two-lane magic: null = athlete hasn't placed yet
completed_log_id fk → training_logs nullable
status text              -- 'pending' | 'scheduled' | 'completed' | 'skipped' | 'swapped'
created_at, updated_at
```

**`easy_fills`**
```sql
id uuid pk
plan_week_id fk → plan_weeks
date date
target_distance_miles numeric
target_pace_label text   -- 'easy' | 'recovery' | 'moderate'
completed_log_id fk → training_logs nullable
status text              -- 'planned' | 'completed' | 'skipped'
created_at, updated_at
```

**`workout_reconciliations`**
```sql
id uuid pk
training_log_id fk → training_logs unique
quality_session_id fk → quality_sessions nullable
easy_fill_id fk → easy_fills nullable
target_pace_seconds_per_mile numeric
actual_pace_seconds_per_mile numeric
weather_forecast_jsonb jsonb     -- what we expected
weather_actual_jsonb jsonb       -- what it was
adjusted_target_pace_seconds numeric -- weather-adjusted target
adjusted_pace_delta_seconds numeric  -- (actual − adjusted_target)
hit_target boolean                -- computed: within tolerance of adjusted target
notes_json jsonb                  -- structured notes from the log
created_at
```

**`coaching_events`**
```sql
id uuid pk
user_id fk → auth.users
event_type text  -- 'correction' | 'override' | 'suggestion_accepted' | 'suggestion_rejected' | 'learning'
subject_type text -- 'quality_session' | 'plan_week' | 'fact' | 'goal'
subject_id uuid
summary text     -- "Athlete said no hamstring issue anymore"
payload_jsonb jsonb
supersedes_event_id uuid nullable -- correction chain: this replaces that
created_at
```

### Changes to existing tables

**`training_plans`** — add `current_phase text`, `current_week_number int`. Deprecate/remove workout-date-specific columns if any.

**`training_logs`** — add `reconciliation_id fk` for easy joining, `weather_actual_jsonb` (if not on reconciliation table).

**`scheduled_workouts`** — **DEPRECATED** in v2. Replaced by quality_sessions + easy_fills. A denormalized *view* `v_scheduled_workouts` provides backward compatibility for iOS/web during migration.

**`user_memories`** — keep, but all writes flow through `coaching_events` and project into memories with supersedes semantics.

---

## 4. Service architecture

Reduce 36 edge functions to ~10 opinionated ones, grouped by domain:

### Plan domain
- **`plan.create`** — conversational intake (current `custom-plan-builder`) but outputs `training_plans` + `plan_weeks` + `quality_sessions` (without `assigned_date`). Easy fills auto-generated. PDF parsing stays.
- **`plan.regenerate_week`** — given a `plan_week_id` and a reason ("athlete missed 3 quality sessions," "goal updated"), regenerate that week and rippling weeks.
- **`plan.phase_check`** — cron, promotes week status (active/complete) and computes current phase.

### Schedule domain (called from iOS/web)
- **`schedule.place_quality`** — athlete drags a quality session onto a date. Validates (no hard-day stacking, adequate recovery) and writes `assigned_date`.
- **`schedule.fill_easy`** — athlete adds an easy run on a day. Writes `easy_fills`.
- **`schedule.reschedule`** — move a placed quality session. Runs validation. Emits a coaching event if the move triggers a concern.
- **`schedule.swap`** — swap two days (e.g., Wednesday intervals ↔ Thursday easy).

### Execution domain
- **`log.reconcile`** — triggered on `training_logs` insert. Joins log to nearest quality_session or easy_fill by date, fetches weather, computes adjusted pace, writes `workout_reconciliations`. Emits a coaching event if delta > threshold.
- **`log.classify`** — uses the structured data already extracted by `process-training-memo` to determine what kind of workout was actually run (useful when athlete didn't flag a planned workout).

### Coach domain
- **`coach.respond`** — unified chat. Single context builder (see §5). Single rate limiter. Returns prose + optional structured action proposal (diff, not replacement).
- **`coach.weekly_review`** — cron, Sunday 8pm local. Reads the past week + next week's forecast. Emits a "Coach's Note" card with one decision (`hold` / `soften` / `swap_quality` / `flag_review`) and reasoning.
- **`coach.intervention`** — reactive, fires when a `coaching_events` pattern emerges (3 missed sessions, injury mention, pace drift > threshold). Pushes proactive message to athlete.

### Shared services
- **`_shared/weather`** — server-side Open-Meteo fetcher (port of `WeatherService.swift`), cached in `weather_cache`. Used by log.reconcile, coach.weekly_review, schedule validators.
- **`_shared/pace_context`** — single source for computing paces. Takes {goal, race_distance, current_fitness, weather} → adjusted paces. Used everywhere: iOS, web, edge functions.
- **`_shared/coach_context`** — ONE builder. Takes `user_id` + `conversation_id`, returns structured JSON of everything the coach needs: active plan, current week intent, next 7 days of placed + unplaced sessions, last 14 days of reconciled logs, active goals with days-to-race, active injuries, recent memories (with supersedes applied).
- **`_shared/memory`** — writes via `coaching_events`, reads via a projection query that applies supersedes. No more append-only drift.

### Deprecated in v2
- `adaptive-workout` — replaced by `plan.regenerate_week` + `coach.intervention`.
- `fitness-predictor` (edge fn) — keep iOS heuristic until ML service is ready.
- All 7 context-builder helpers in `_shared/` — collapsed into `coach_context`.
- `admin-sql` — take down (security gap identified in production-readiness report).

---

## 5. The coaching layer

### Single context builder

```ts
// _shared/coach_context.ts
interface CoachContext {
  athlete: { name, pronouns, tier, timezone };
  goal: { race_distance, target_time, date, days_until } | null;
  plan: {
    phase, current_week_number, total_weeks,
    this_week: {
      intent_md,
      quality_sessions: QualitySessionSummary[],
      easy_fills: EasyFillSummary[],
      volume_target_miles, volume_so_far_miles,
    },
    next_week: { intent_md, quality_preview: string };
  } | null;
  recent_execution: ReconciledWorkoutSummary[]; // last 14 days
  pace_targets: { easy, marathon, half, ten_k, five_k, mile }; // weather-adjusted for today
  active_injuries: InjurySummary[];
  memories: MemorySummary[]; // supersedes applied, ≤20 most relevant
  recent_corrections: CorrectionSummary[]; // last 5 corrections from coaching_events
  forecast_7d: DailyForecast[];
}
```

Every field has a clear source. Total payload budget: 3000 tokens. If it doesn't fit, we evict in order: oldest reconciliations → least-relevant memories → older forecast days. Never evict the plan, the goal, or recent corrections.

### Prompt structure

```
[VOICE_RULES]  — existing, keep. Still bans "impressive/journey/amazing."
[GROUNDING_RULES] — NEW
  - Every recommendation must cite a specific workout, week, or metric from the context.
  - If the answer requires data not in the context, say so. Do not generalize.
  - Use pace labels anchored to race distances (5K/10K/half/marathon). Never use methodology letters.
[OPINION_RULES] — NEW
  - Have a point of view. Disagree when evidence supports it.
  - When the athlete proposes a change, evaluate it against the plan intent and the recent execution. Say yes, say no with reasoning, or offer a better option.
  - Silence is not neutral. If you have no opinion, the context wasn't sufficient — say that.
[CONTEXT_JSON]  — from coach_context
[CONVERSATION_HISTORY] — last N messages, summarized if > 8
[USER_MESSAGE]
```

### Structured action proposals

When the coach suggests a change, it returns structured JSON alongside prose:

```json
{
  "prose": "Tuesday's forecast hits 87°F...",
  "proposed_actions": [
    {
      "kind": "reschedule",
      "subject_id": "<quality_session_id>",
      "from_date": "2026-04-21",
      "to_date": "2026-04-22",
      "reason": "forecast_heat",
      "confidence": "high"
    }
  ]
}
```

iOS/web render this as: prose + "Apply" / "Reject" / "Modify" buttons. Apply calls `schedule.reschedule` with the proposed params. Reject writes a `coaching_events` row. Modify opens the day sheet.

This is the **glass-box coach**: you see what it wants to do, you click once to accept, it never writes silently.

### Correction loop

When the athlete says "I'm not injured, I was tapering":

1. `coach.respond` detects a correction via a dedicated sub-classifier (or explicit "that's wrong" trigger).
2. Writes a `coaching_events` row: `event_type='correction'`, `subject_type='fact'`, `supersedes_event_id=<prior event that established the now-wrong fact>`.
3. On the next `coach_context` build, the projection applies supersedes and the corrected fact replaces the stale one — for all future responses.

No more ghost memories.

---

## 6. UX architecture

### The day sheet is the workshop

Tap any day in `WeekCalendarView` → bottom sheet with **three tabs**:

1. **Template** — filterable list of saved templates (personal + public). One tap drops a template onto this day. Pace preview uses today's adjusted paces.
2. **Build** — shorthand text input with live parser. Type `6x800 @ 5K pace / 90s jog`, see structured card below. Save.
3. **Chat** — conversational with the coach, scoped to this day + week. Coach can propose structured diffs that apply in one tap.

Deprecated: `WorkoutGeneratorView`, `WorkoutTemplateLibraryView` as standalone navigation, `AIPlanChatSheet` as a separate sheet (merged into Chat tab of day sheet). `CustomPlanBuilderView` stays — it's a different surface (create a new plan), not a workout.

### The week view shows two lanes

- **Quality (coach's lane):** shows the week's placed quality sessions with day-of-week chips. Unplaced sessions float at the top as a pool — drag onto a day to place.
- **Container (athlete's lane):** shows easy fills, total volume, recovery days. Athlete edits inline.

Visual rule: quality sessions have a subtle "locked" treatment (coach icon). Easy fills are plain.

### Shorthand parser

New edge function `parse_workout_shorthand`. Grammar (distance-anchored, methodology-agnostic):

```
<workout>  ::= <segment> ("," <segment>)*
<segment>  ::= [<count> "x"] <distance> ["@" <pace_ref>] ["/" <recovery>]
<distance> ::= "400m" | "800m" | "1600m" | "1mi" | "2mi" | "5K" | "10K" | "half" | "marathon" | <number>"mi"
<pace_ref> ::= "easy" | "MP" | "marathon pace" | "half pace" | "10K pace" | "5K pace" | "mile pace"
<recovery> ::= <duration> | <distance> [jog|walk|rest]
```

Examples that must parse:
- `2mi wu, 6x800 @ 5K pace / 90s jog, 2mi cd`
- `3x(4x400 @ mile pace / 200 jog) / 800 jog between sets`
- `Progressive 10mi: 6mi easy, 2mi @ MP, 2mi @ half pace`

Parser runs live on the Build tab (300ms debounce). Output is the same `structure_json` shape used everywhere.

### One PaceContext everywhere

Kill `@AppStorage("paceChart_selectedDistance")` and `@AppStorage("paceChart_goalTimeSeconds")`. Replace with a single `PaceContext` struct derived from {active goal, current fitness estimate, today's forecast}. Template editor, day sheet, chat, week view all read from it. No divergent pace displays.

---

## 7. Migration path

### Phase 0 — Prep (1 week)
- Feature flag scaffold: `training_v2_enabled` per user, default off.
- Add all new tables (`plan_weeks`, `quality_sessions`, `easy_fills`, `workout_reconciliations`, `coaching_events`). No data yet.
- Build `_shared/weather`, `_shared/pace_context`, `_shared/coach_context`. Do not wire them in yet.
- Build `v_scheduled_workouts` view that reads from v2 tables and presents v1 shape. Exists but nothing reads from it yet.

### Phase 1 — Coaching layer (1 week)
- New `coach.respond` that uses `coach_context` end-to-end. A/B against old `coaching-agent` for flagged users only.
- New prompt with GROUNDING_RULES and OPINION_RULES.
- Structured-action proposal rendering in iOS chat.
- Correction loop wired through `coaching_events` + supersedes projection.
- **Success gate:** hand-grade 20 coach responses against the rubric. Must clear 4.0/5.0 before moving on.

### Phase 2 — Plan data model (1-2 weeks)
- `plan.create` writes into v2 tables.
- Migration script: for every active `training_plans` row, generate `plan_weeks` + `quality_sessions` (pre-placed) + `easy_fills` from existing `scheduled_workouts`. Quality sessions get `assigned_date` copied from old rows, so nothing appears to move for the user.
- iOS and web read from `v_scheduled_workouts` view — no UI change yet.

### Phase 3 — Two-lane UI (2 weeks)
- `WeekCalendarView` rewrite with quality lane + container lane.
- Day sheet with Template / Build / Chat tabs.
- Shorthand parser.
- `schedule.place_quality`, `schedule.fill_easy`, `schedule.reschedule` wired to UI.

### Phase 4 — Reconciliation + weekly review (1 week)
- `log.reconcile` fires on training_logs insert.
- `coach.weekly_review` cron runs Sunday nights, produces "Coach's Note" card.
- Weather-adjusted pace becomes the default display everywhere.

### Phase 5 — Cutover (1 week)
- `training_v2_enabled` default on.
- Deprecate old context builders, `adaptive-workout`, `admin-sql`.
- Mark v1 edge functions for deletion after 30 days of no calls.

Total: ~7 weeks of focused work. Shippable value at the end of every phase (phase 1 alone is a huge trust upgrade).

---

## 8. Explicit non-goals

- Multi-athlete coaching surface (AthleteRosterView) — decide its fate separately. If staying, plan_weeks and quality_sessions can be re-keyed by athlete_id later.
- Human-coach-in-the-loop marketplace — design pressure only, not in scope.
- Custom ML models (race prediction, injury risk with validated bounds) — parked ML service stays parked until ~10K users.
- Real-time collaborative editing of plans.
- Offline writes to quality_sessions — read-only offline on v2 initially; re-add offline writes after the data model settles.
- Replacing Supabase, Vercel, or Expo.

---

## 9. Open decisions I need from you

1. **Scope confirmation.** Training subsystem only — yes? Or does "better system" include reworking the coach's non-training surfaces (race intel, block review, weekly report)?
2. **Backwards compatibility for existing users.** Current plans — do we migrate them (phase 2) or invite users to recreate? Migration is more work but preserves data and trust.
3. **Multi-athlete future.** `AthleteRosterView` exists. Design for single-athlete-per-account and extend later, or design multi-athlete from the start? Major schema implication (add `athlete_id` to everything now vs. migrating later).
4. **Tier gating.** Should any v2 features (weather-adjusted pace, weekly review, shorthand parser) be paid-tier only, or all free? Affects marketing framing.
5. **Coach's voice — where on the spectrum.** We said "guide, pushes back when evidence supports it." Do you want the OPINION_RULES to lean strong (more pushback, occasional disagreement) or soft (suggestions only)? This is a tone decision that lives in the prompt.
6. **Proactive messaging.** `coach.intervention` can push messages to the athlete without being asked. Do we want that at all in v2, or is chat-only safer?

---

## 10. What this buys you

- **The coach becomes credible.** Every response is grounded in specific data. Corrections stick. Advice has a point of view. The glass-box model makes the coach trustworthy to a BQ runner.
- **The two-lane scheduling stops fighting the data model.** Quality vs. container is a real architectural primitive, not a UI hack.
- **Weather becomes invisible infrastructure.** Every pace is adjusted. Forecast drives scheduling suggestions. It stops being a "feature" and starts being a property of the system.
- **Workout creation collapses to one workshop.** Seven UIs become one sheet with three tabs. The shorthand parser gives power users what they actually want.
- **36 edge functions become ~10.** Every function has a clear job. Cost per coaching response drops because context is built once instead of seven times.
- **You have a system you can reason about.** Debugging, onboarding new engineers, adding features — all become tractable.

---

*End of design. Next step: decide on the open questions in §9, then Phase 0 can start.*
