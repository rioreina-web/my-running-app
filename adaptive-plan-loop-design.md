# Adaptive Plan Loop — Design

**Scope:** The loop from **coach's prescription → athlete's execution → coach's adaptation**. Nothing else.
**Explicit non-goals:** two-lane canvas, workout workshop UI, multi-athlete, weather backend plumbing, ML service, coaching-agent chat quality. Separate work.

---

## 1. The actual bugs (not generic — located in real files)

### Bug A — The "115%" display crime

**Root cause chain, three files:**

1. **Data model stores pace as a percentage.**
   *`RunningLog/RunningLog/Models/PlannedWorkoutModels.swift:32`*
   ```swift
   let pacePercentage: Double?
   ```
   And the AI actually outputs these. From `WorkoutGeneratorViewModel.swift:276-305` — every stub workout step in the generator is hard-coded like:
   ```swift
   PaceIntensity(percentage: 92), notes: "4mi @ 92%"
   ```
   The coach is thinking in "% of race pace," never in minutes:seconds.

2. **Display logic falls back to raw percentage.**
   *`Models/PaceModels.swift:70-72`*
   ```swift
   var displayPercentage: String {
       String(format: "%.0f%%", percentage)
   }
   ```
   And in `PlannedWorkoutModels.swift:113`:
   ```swift
   return PaceIntensity(percentage: pct)  // no actual seconds-per-km attached
   ```
   So when the UI renders this intensity without a `racePaceSeconds` reference passed in, it shows "115%."

3. **Race pace reference is stored in `@AppStorage` and may be stale, missing, or wrong.**
   `@AppStorage("paceChart_selectedDistance")` and `@AppStorage("paceChart_goalTimeSeconds")` — two different places define what "100%" means, neither tied to the athlete's current fitness.

**The athlete sees "115%" whenever the race pace reference is missing. For a BQ athlete, even when it's working ("@ 92% of 3:20 marathon pace"), that's still abstraction they have to do arithmetic on. Unacceptable.**

### Bug B — Plan doesn't adapt

**Root cause, one file:**

*`supabase/functions/adaptive-workout/index.ts:1-6`* — the docstring gives it away:
```
Stores the result in ai_insights with type 'adaptive_workout'.
```

The "adaptive workout" function does not modify the plan. It writes a suggestion to a separate `ai_insights` table. There is no:
- Trigger on `training_logs` insert that fires reconciliation
- Write-back to `scheduled_workouts` to change future paces/volumes
- Update to `fitness_snapshots` when the athlete runs faster/slower than expected
- Update to `training_plans.current_phase` based on actual progression

In other words: **"adaptive" is a suggestion surface, not a plan mutation.** The plan as displayed in `WeekCalendarView` is the same today as it was the day it was generated, regardless of what the athlete actually did.

### Bug C — Paces derived from shaky predictions

*`supabase/functions/adaptive-workout/index.ts:58-89`* — `computePaceZones` takes `fitness_snapshots.predicted_*_seconds` and cascades through fallbacks. If marathon prediction is missing, derive from half × 1.06. If half is missing, derive from 10K × 1.15. Each cascade compounds error.

**And nothing updates `fitness_snapshots` reactively.** If the athlete runs a 10K race in a training run at 41:30, that data point never anchors future pace prescriptions. The snapshot only updates via `fitness-predictor` (heuristic) on explicit trigger — not automatically when a valid race-pace performance happens.

---

## 2. Design principles for the loop

1. **Paces are stored in seconds per mile, not percentages.** Ever. The coach thinks in seconds; the athlete reads seconds; the database stores seconds. Percentage is a generation-time concept, resolved before storage.
2. **There is one source of truth for "the athlete's current paces."** One struct. One query. Every view reads from it. No `@AppStorage` fallbacks.
3. **Every log inserts closes the loop.** When a training log lands, reconciliation runs, and if the delta matters, the plan mutates. Not a suggestion — a mutation.
4. **Adaptation is reversible and cited.** When the plan changes, the athlete sees: what changed, why (which workout, which delta), and can revert in one tap.
5. **Fitness is a live number, not a snapshot.** New performance data that contradicts the current fitness estimate updates it. No staleness.

---

## 3. The data flow, v2

```
┌──────────────────────────┐
│  AthletePaceProfile      │◄──────────── fitness_snapshots
│  (single struct, live)   │              (updated reactively)
│  • goal_race, goal_time  │
│  • current_paces:        │
│    easy / marathon /     │
│    half / 10K / 5K / mi  │
│    (all in sec/mile)     │
│  • confidence per pace   │
└────────────┬─────────────┘
             │ used by...
             ▼
┌──────────────────────────┐
│  Plan generation          │  AI outputs workouts with
│  custom-plan-builder      │  paces ALREADY RESOLVED to
│                           │  seconds/mile, using the
│                           │  profile at generation time
└────────────┬─────────────┘
             │ writes...
             ▼
┌──────────────────────────┐
│  scheduled_workouts       │  step.target_pace_seconds_per_mile
│  (paces stored concrete)  │  step.target_distance
│                           │  step.pace_reference  ("5K pace")
│                           │  ← display label, not computation
└────────────┬─────────────┘
             │ displayed as...
             ▼
┌──────────────────────────┐
│  iOS / web UI             │  "7:35/mi" — never "92%"
│  (pure read, no math)     │  Weather-adjusted on the fly
└────────────┬─────────────┘
             │ athlete runs...
             ▼
┌──────────────────────────┐
│  training_logs insert     │
└────────────┬─────────────┘
             │ triggers...
             ▼
┌──────────────────────────┐
│  reconcile-log (NEW)      │  Reads: log + matching scheduled
│                           │  workout + weather + profile
│                           │  Writes: workout_reconciliation
│                           │  Emits event if delta > threshold
└────────────┬─────────────┘
             │ may trigger...
             ▼
┌──────────────────────────┐
│  adapt-plan (NEW)         │  Reads: recent reconciliations
│                           │  Writes: 
│                           │   1. fitness_snapshots update
│                           │      (if performance invalidates)
│                           │   2. scheduled_workouts mutations
│                           │      (future paces, volumes)
│                           │   3. plan_adjustment record
│                           │      (for athlete review)
└──────────────────────────┘
```

The loop closes. Every loop iteration keeps the athlete's profile live, the plan current, and the adaptations visible.

---

## 4. Specific changes, file by file

### 4.1 Kill percentage-as-storage (data migration)

**Schema change — `scheduled_workouts.workout_data` JSONB:**

Each step loses `pacePercentage`, gains:
```json
{
  "target_pace_seconds_per_mile": 455,       // 7:35/mi
  "target_pace_seconds_high": 463,           // 7:43/mi, range end (optional)
  "pace_reference": "5K pace",               // display label only — "5K pace", "marathon pace", "easy", etc.
  "resolved_from_snapshot_id": "<uuid>",     // which fitness_snapshot was used at generation
  "resolved_at": "2026-04-15T10:00:00Z"
}
```

`pacePercentage` gets removed from the canonical shape. If it sticks around as legacy, treat it as a migration artifact and deprecate.

**Migration:** backfill existing scheduled_workouts by resolving `pacePercentage × current race_pace` at migration time. Mark the resolved_at so we know which data is backfilled vs. freshly generated.

**`RunningLog/RunningLog/Models/PaceModels.swift:70-72`** — delete `displayPercentage`. Nothing should ever display a percentage. If a code path needs one, the code path is wrong.

**`RunningLog/RunningLog/Models/PlannedWorkoutModels.swift:113`** — delete the fallback `return PaceIntensity(percentage: pct)`. If `paceSecondsPerKm` is nil at display time, show `"pace not set"` and log an error — never fall back to a percentage.

### 4.2 AthletePaceProfile — one source of truth

**New Swift struct and backend table.**

Swift:
```swift
// RunningLog/RunningLog/Models/AthletePaceProfile.swift (new)
struct AthletePaceProfile: Codable {
    struct Pace: Codable {
        let secondsPerMile: Double
        let confidence: Confidence  // .high | .medium | .low
        let sourceDate: Date        // when this was last validated by a run
    }
    enum Confidence: String, Codable { case high, medium, low }

    let userId: UUID
    let goalRaceDistance: String?   // "marathon" | "half" | "10K" — nullable
    let goalTimeSeconds: Int?

    let easy: Pace
    let marathon: Pace
    let half: Pace
    let tenK: Pace
    let fiveK: Pace
    let mile: Pace

    let generatedAt: Date
    let basedOnSnapshotId: UUID?
}
```

Backend table:
```sql
-- supabase/migrations/<ts>_athlete_pace_profile.sql
create table athlete_pace_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users,
  goal_race_distance text,
  goal_time_seconds int,
  easy_pace_seconds numeric,
  easy_confidence text,
  easy_source_date timestamptz,
  marathon_pace_seconds numeric,
  marathon_confidence text,
  marathon_source_date timestamptz,
  -- repeat for half, tenK, fiveK, mile
  based_on_snapshot_id uuid references fitness_snapshots,
  generated_at timestamptz not null default now(),
  unique (user_id)  -- one per user, overwritten on update
);
```

**Rules:**
- Kill `@AppStorage("paceChart_selectedDistance")` and `@AppStorage("paceChart_goalTimeSeconds")`. Remove from every file that uses them.
- Every view reads paces from `AthletePaceProfile` (loaded once per session, refreshed after log inserts).
- Weather adjustment is applied at **read time** in the view layer using `PaceCalculator.calculateDewPointAdjustment` (already exists). Storage stays raw.

### 4.3 Plan generation writes resolved paces

**`supabase/functions/custom-plan-builder/index.ts` + `parse-workout-structure/index.ts`:**

Change the LLM prompt so it outputs paces in seconds-per-mile, not percentages. Constrain the output schema:
```json
{
  "steps": [
    {
      "stepType": "active",
      "durationType": "distanceMiles",
      "durationValue": 4.0,
      "target_pace_seconds_per_mile": 375,   // 6:15/mi
      "pace_reference": "5K pace",           // used for display only
      "target_pace_seconds_high": 380        // optional range
    }
  ]
}
```

Before writing to DB, the backend resolves the LLM's nominal "5K pace" reference against the current `athlete_pace_profiles` row and stamps the actual `seconds_per_mile`. The LLM's role is to decide *intent* ("this step is at 5K effort"); the backend converts intent → number using the athlete's current profile.

If the athlete's profile changes mid-plan (they ran a new 10K PR), existing scheduled_workouts keep their stamped paces *unless* the delta is big enough to trigger `adapt-plan` (§4.5).

### 4.4 reconcile-log — the missing trigger

**New edge function: `supabase/functions/reconcile-log/index.ts`**

**Trigger:** Postgres trigger on `training_logs` insert fires this via `pg_net.http_post`.

**Logic:**
1. Load the inserted `training_log` row.
2. Find the matching `scheduled_workouts` row (same user, same date, within ±1 day). If none, tag as "unplanned" and exit.
3. Fetch weather for the log's date/location (Open-Meteo if not cached; port of `WeatherService.swift` to TS in `_shared/weather.ts`).
4. For each pace segment in the log, compute:
   - `actual_pace_seconds_per_mile` (from pace_segments)
   - `weather_adjusted_target` = `PaceCalculator.calculateDewPointAdjustment(target, temp, dewPoint)` ported to TS
   - `delta_seconds` = actual − adjusted_target
5. Write a `workout_reconciliations` row with all the above.
6. If `delta` crosses a threshold (e.g., hit 10K pace target within 3s/mi → "nailed it"; missed by >15s/mi → "struggled"), enqueue `adapt-plan` with reason and metadata.

**Why Postgres trigger + pg_net instead of client-side call:** runs regardless of platform, runs even if the athlete closes the app, single code path.

### 4.5 adapt-plan — the missing mutation

**New edge function: `supabase/functions/adapt-plan/index.ts`**

**Trigger:** called by `reconcile-log` when deltas warrant, plus a Sunday-night cron for weekly rebalancing.

**Inputs:** user_id, triggering reconciliation, last 14 days of reconciliations, current plan, current profile.

**Decision logic (rule-based, not LLM — this is the kind of reasoning LLMs hallucinate on):**

| Signal | Trigger | Action |
|---|---|---|
| Athlete hit pace target consistently (last 3 hard sessions ≤ 3s/mi of adjusted target, RPE ≤ 7) | Pattern detected | Bump fitness_snapshot faster by X sec/mi × confidence weight; re-resolve future scheduled_workouts to tighter paces |
| Athlete missed target consistently (3 of 4 sessions >10s/mi slower, RPE ≥ 8) | Pattern detected | Bump fitness_snapshot slower; soften future paces by same amount; flag for coach chat review |
| Athlete skipped 2+ quality sessions in 7 days | Pattern detected | Hold volume flat next week; do not add new quality until one is completed |
| Athlete logged race result (distance + time + "race" workout_type) | Single event | Update fitness_snapshot immediately from the race; re-resolve all future paces |
| Weather-adjusted target vs. actual is within tolerance | Not a miss | Do nothing; reinforce confidence |
| Dew point > 68 on 3 upcoming hard days in the 10-day forecast | Forecast pattern | Propose schedule swap to cooler-forecast days; do NOT auto-apply, surface to athlete |
| Volume ramp > 10% week-over-week for 3 consecutive weeks | Injury risk | Cap next week volume at current; flag |

**Output:** every change writes a `plan_adjustment` row:
```sql
create table plan_adjustments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  plan_id uuid not null references training_plans,
  trigger_type text not null,            -- 'pace_over_target', 'missed_sessions', 'race_result', etc.
  trigger_evidence jsonb not null,       -- the specific reconciliations or logs that fired this
  action_type text not null,             -- 'reprice_future_paces', 'reduce_volume', 'propose_swap', 'update_fitness'
  action_payload jsonb not null,         -- diff applied
  applied_at timestamptz default now(),
  acknowledged_by_user_at timestamptz,   -- athlete saw the change
  reverted_at timestamptz                -- if athlete reverted
);
```

iOS/web surfaces recent `plan_adjustments` as a feed: "Coach adjusted your plan: after Tuesday's threshold, your 10K pace estimate improved 4s/mi. Next week's workouts repaced accordingly." One-tap [Accept] / [Revert].

### 4.6 Kill the percentage output at the generator

*`RunningLog/RunningLog/Workouts/WorkoutGeneratorViewModel.swift:276-305`* — the stub workouts hard-code `PaceIntensity(percentage: 92)` etc. Rewrite those stubs to resolve against a mock `AthletePaceProfile` and produce seconds-per-mile. This forces the rest of the pipeline to work in real units.

---

## 5. What this buys you

- **No more "115%" anywhere.** Every pace display is minutes:seconds. Every step references a race distance, not a number.
- **Paces are right.** Every pace is resolved against the athlete's current fitness profile at generation time, and re-resolved when fitness changes.
- **Plan actually adapts.** Log → reconcile → (maybe) mutate. The plan moves with the athlete. Changes are visible, cited, and reversible.
- **One source of truth for paces.** `AthletePaceProfile`. Kill the `@AppStorage` fallbacks. Every view reads from the same place.
- **Adaptation logic is rule-based, not LLM-based.** Predictable, debuggable, no hallucinations. The LLM's job is plan *generation*, not plan *math*.

---

## 6. Sequence — 3 phases, ~3 weeks

**Phase 1: Kill the percentage display (1 week)**
- Introduce `AthletePaceProfile` table + Swift struct.
- Backfill from `fitness_snapshots` + `user_goals`.
- Remove `displayPercentage` from `PaceModels.swift`.
- Remove percentage fallback in `PlannedWorkoutModels.swift`.
- Update all pace displays to use `formattedPace(forRacePace:)` with profile data.
- Migration script resolves every existing `scheduled_workouts.workout_data[].pacePercentage` to `target_pace_seconds_per_mile`.
- **Shippable:** users stop seeing "115%" anywhere. Paces are right for the first time.

**Phase 2: Reconcile every log (1 week)**
- Build `reconcile-log` edge fn + Postgres trigger on `training_logs` insert.
- Port `PaceCalculator.calculateDewPointAdjustment` to `_shared/pace-heat.ts`.
- Build `_shared/weather.ts` as server-side Open-Meteo client.
- New `workout_reconciliations` table.
- iOS: surface reconciliation in the log detail view — "You ran 7:38 target 7:35 (adjusted for 72°F). Nailed it."
- **Shippable:** every log now closes the loop. Athletes see weather-adjusted deltas. No plan mutations yet.

**Phase 3: Wire adaptation (1 week)**
- Build `adapt-plan` edge fn with rule-based decision logic.
- New `plan_adjustments` table.
- iOS/web: "Plan updates" feed with accept/revert UI.
- Sunday cron wired for weekly rebalancing.
- Retire `adaptive-workout` (`ai_insights` route) — deprecate, stop writing to it.
- **Shippable:** the plan is now a live artifact. It moves. You can market "your plan adapts to you."

---

## 7. Open questions for you

1. **How urgent is weather integration for Phase 2?** We can do reconciliation without weather first (just raw pace delta) and add weather-adjusted targets in a Phase 2.5. Faster ship vs. complete loop.
2. **When the plan adapts (Phase 3), do we auto-apply or require athlete approval?** My default: structural changes (volume caps, skipped-session pauses) auto-apply with a notification; fitness-driven pace repricing proposes and awaits one-tap approval. Makes the coach feel authoritative but not presumptuous.
3. **What do we do for users on active plans when Phase 1 ships?** Backfill their existing plans (reprice percentage → seconds) or invite regeneration? Backfill is more work but preserves trust.
4. **Is the `AthletePaceProfile` auto-generated from the latest `fitness_snapshot`, or does the athlete explicitly set it via an "update my paces" flow?** I'd say auto-generate, but surface it in Settings with a "manual override" path for when the athlete knows better than the algorithm.

---

*End of design. Phase 1 alone kills the worst UX crime in the product. Three weeks of focused work closes the adaptive loop.*
