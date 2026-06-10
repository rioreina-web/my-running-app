# Adaptive Plan Loop — Execution Prompts

**Companion to:** `adaptive-plan-loop-design.md`
**Purpose:** Copy-pasteable prompts for Claude Code (or similar) to execute the design, phase by phase.
**How to use:** Execute in order. Each prompt is self-contained — the agent does not need to read the full design unless explicitly referenced. Dependencies are called out in each prompt header. After each prompt, review the diff before running the next.

---

## Phase 1 — Kill the "115%" crime (~1 week)

Goal: every pace displayed to a user is `M:SS/mi`, never a percentage. All paces resolved from a single source of truth at generation time.

---

### Prompt 1.1 — Create `athlete_pace_profiles` table

**Dependencies:** none (start here).
**Files to create:** new migration in `supabase/migrations/`.

> Create a new Supabase migration named `<timestamp>_athlete_pace_profiles.sql` that adds a table `athlete_pace_profiles` with: `id uuid primary key default gen_random_uuid()`, `user_id uuid not null references auth.users(id) on delete cascade`, `goal_race_distance text` (nullable, one of: 'mile','5K','10K','half','marathon'), `goal_time_seconds int` (nullable), and six pace groups each with three columns (seconds numeric, confidence text check in 'high','medium','low', source_date timestamptz): `easy_*`, `marathon_*`, `half_*`, `ten_k_*`, `five_k_*`, `mile_*`. Also add `based_on_snapshot_id uuid references fitness_snapshots(id)`, `generated_at timestamptz not null default now()`, `updated_at timestamptz not null default now()`. Enforce `unique (user_id)`. Add RLS: users can select/update/insert their own row; service role full access. Add an updated_at trigger. Do NOT populate any rows yet — that's Prompt 1.3.

---

### Prompt 1.2 — Create `AthletePaceProfile` Swift struct

**Dependencies:** none.
**Files to create:** `RunningLog/RunningLog/Models/AthletePaceProfile.swift`.

> Create a new Swift file at `RunningLog/RunningLog/Models/AthletePaceProfile.swift`. Define a `Codable, Equatable` struct `AthletePaceProfile` with fields: `userId: UUID`, `goalRaceDistance: String?`, `goalTimeSeconds: Int?`, and six `Pace` fields (`easy`, `marathon`, `half`, `tenK`, `fiveK`, `mile`). Nested `struct Pace: Codable, Equatable` has `secondsPerMile: Double`, `confidence: Confidence`, `sourceDate: Date`. Add `enum Confidence: String, Codable { case high, medium, low }`. Add `generatedAt: Date` and `basedOnSnapshotId: UUID?`. Match the column names in `athlete_pace_profiles` via `CodingKeys` using snake_case (e.g., `case easyPaceSeconds = "easy_pace_seconds"`). Include a helper method `pace(for distance: String) -> Pace?` that returns the right pace struct given "5K", "10K", "half", "marathon", "mile", "easy".

---

### Prompt 1.3 — Backend: derive profile from fitness_snapshot + user_goals

**Dependencies:** 1.1.
**Files to create:** `supabase/functions/build-pace-profile/index.ts` + shared helper.

> Create a new Supabase edge function at `supabase/functions/build-pace-profile/index.ts`. Input: `{ user_id }` from POST body, authenticated via JWT. Logic: (a) fetch the latest `fitness_snapshots` row for the user and the latest `user_goals` row; (b) port the `computePaceZones` function from `supabase/functions/adaptive-workout/index.ts` lines 58-89 into a new file `supabase/functions/_shared/pace-zones.ts` and import it; (c) compute all six paces in seconds/mile; (d) set `confidence = 'high'` for paces derived from direct snapshot predictions, `'medium'` for cascaded ones (e.g., marathon from half × 1.06), `'low'` if only one source distance available; (e) upsert into `athlete_pace_profiles` with `user_id` as the conflict target. Return the upserted row. Enforce `verify_jwt = true`. If the user has no fitness_snapshot, return 404 with a clear "no fitness data available" message. Add this function to the auth allowlist.

---

### Prompt 1.4 — iOS service to fetch and cache the profile

**Dependencies:** 1.2, 1.3.
**Files to create:** `RunningLog/RunningLog/Services/AthletePaceProfileService.swift`.

> Create `RunningLog/RunningLog/Services/AthletePaceProfileService.swift`. Define an `@Observable class AthletePaceProfileService` singleton (`static let shared`). It has a published `var profile: AthletePaceProfile?`, a `func refresh() async throws` that calls `build-pace-profile` edge function via the existing Supabase client and stores the result in memory, and `func paceSeconds(for referenceDistance: String) -> Double?` that returns the cached pace. On app launch (via `RunningLogApp` or equivalent) call `refresh()` once. After any `training_logs` insert call `refresh()` on a 30-second debounce. Do not persist to SwiftData — always fetch fresh. Log errors to `Log` category `paceProfile`.

---

### Prompt 1.5 — Schema change to `scheduled_workouts.workout_data`

**Dependencies:** 1.1.
**Files to create:** new migration.

> Create a migration `<timestamp>_resolve_scheduled_workout_paces.sql`. This migration defines the new JSONB shape for each step inside `scheduled_workouts.workout_data[].steps`. The new shape drops `pacePercentage` and adds `target_pace_seconds_per_mile numeric`, `target_pace_seconds_high numeric` (nullable), `pace_reference text` (values: 'easy','marathon','half','10K','5K','mile', nullable), `resolved_from_snapshot_id uuid`, `resolved_at timestamptz`. Since `workout_data` is JSONB, write a `pl/pgsql` function `resolve_step_paces(data jsonb, profile jsonb) returns jsonb` that transforms each step. Then run a one-time UPDATE across all `scheduled_workouts` rows joining them to `athlete_pace_profiles` by user_id (via the linked training_plans row) and transforms each `workout_data`. For steps where `pacePercentage` exists, compute `seconds_per_mile = goal_race_pace_seconds × (100 / pacePercentage)` and stamp it. Any step without `pacePercentage` AND without `paceSecondsPerKm` gets `pace_reference = 'easy'` and the profile's easy pace. Leave the old `pacePercentage` column in JSONB alongside the new fields for one release (safety), then drop in a follow-up migration.

---

### Prompt 1.6 — Plan generation writes resolved paces

**Dependencies:** 1.1, 1.3, 1.5.
**Files to modify:** `supabase/functions/custom-plan-builder/index.ts`, `supabase/functions/parse-workout-structure/index.ts`, `supabase/functions/parse-training-week/index.ts`.

> In each of these three edge functions, change the LLM system/user prompts and the output schema so the model outputs `target_pace_seconds_per_mile` and `pace_reference` instead of `pacePercentage`. Specifically: instruct the model "Output paces as integer seconds per mile (e.g., 385 for 6:25/mi). Do NOT output percentages. Reference paces using race distances only: 'easy', 'marathon', 'half', '10K', '5K', 'mile'." Before writing to the database, call `build-pace-profile` for the user to get the current profile, then for any step where the LLM gave a `pace_reference` but no explicit `target_pace_seconds_per_mile`, resolve it by looking up `profile.pace_for(reference)`. Stamp `resolved_from_snapshot_id` and `resolved_at`. If the model outputs both a reference and a specific seconds value, keep the seconds and store the reference as a display label only. Never write `pacePercentage` to new rows.

---

### Prompt 1.7 — Remove `displayPercentage` and its callers

**Dependencies:** 1.5 has run so no codepath relies on percentages.
**Files to modify:** `RunningLog/RunningLog/Models/PaceModels.swift` and every file referencing `displayPercentage`.

> In `RunningLog/RunningLog/Models/PaceModels.swift`, delete the `displayPercentage` computed var on `PaceIntensity` (lines 70-72). Then `grep` the codebase for `displayPercentage` and `.percentage` on `PaceIntensity` instances — for every call site, replace with `formattedPace(forRacePace:)` that receives a real race pace in seconds (from `AthletePaceProfileService.shared.profile`). If a call site has no access to the profile, refactor to pass it in rather than falling back to a percentage display. Build the project and fix every compile error — do not use `??` fallbacks to strings like "N/A"; the correct behavior when profile is unavailable is to display `—` and log an error. Run `swift build` or the iOS test suite and verify no reference to `displayPercentage` remains.

---

### Prompt 1.8 — Remove the percentage fallback in PlannedWorkoutModels

**Dependencies:** 1.7.
**Files to modify:** `RunningLog/RunningLog/Models/PlannedWorkoutModels.swift`.

> In `RunningLog/RunningLog/Models/PlannedWorkoutModels.swift` around line 113, there is a fallback: `return PaceIntensity(percentage: pct)`. Remove this branch entirely. A `PaceIntensity` should only ever be constructed from concrete `paceSecondsPerKm` values. If neither is available after the new schema migration (1.5), return `nil` and let the caller handle it. Also remove line 100 (`pct = step.pacePercentage ?? 80`) — that 80% hardcoded fallback is the source of silent wrong paces. If `paceSecondsPerKm` is absent on a step after migration 1.5, that's a data bug that should be logged and surfaced, not papered over.

---

### Prompt 1.9 — Replace `@AppStorage` pace settings with the profile

**Dependencies:** 1.4.
**Files to modify:** every file using `@AppStorage("paceChart_selectedDistance")` or `@AppStorage("paceChart_goalTimeSeconds")`.

> `grep` the codebase for `paceChart_selectedDistance` and `paceChart_goalTimeSeconds`. Replace every read with a read from `AthletePaceProfileService.shared.profile`. Remove the `@AppStorage` declarations entirely. Views that previously used these should take a `profile: AthletePaceProfile?` parameter or observe the service. Where there's a legacy "goal-setting UI" that writes to these AppStorage keys, redirect it to call a new edge function `update-pace-profile-goal` (if it doesn't exist, skip this for now and add a TODO). Ensure `WorkoutTemplateEditorView.swift` and any other previewer reads from the profile.

---

### Prompt 1.10 — Fix the generator stub workouts

**Dependencies:** 1.4.
**Files to modify:** `RunningLog/RunningLog/Workouts/WorkoutGeneratorViewModel.swift`.

> In `RunningLog/RunningLog/Workouts/WorkoutGeneratorViewModel.swift` lines 276-305 (and any similar hardcoded stubs), the stub workouts use `PaceIntensity(percentage: 92)` etc. Refactor them to resolve against `AthletePaceProfileService.shared.profile`. For example: a step previously at "87% of race pace" should be mapped to "marathon pace" — use `profile.marathon.secondsPerMile` directly and construct `PaceIntensity(paceSecondsPerKm: marathonSeconds * 0.621371)`. Create a small helper `PaceIntensity.forReference(_:in:)` that takes a reference distance string and a profile and returns a concrete PaceIntensity. Where the old percentage maps to a specific named pace, use the mapping: 70% → easy, 87-90% → marathon, 92-95% → half, 97-100% → 10K, 102-105% → 5K, 105%+ → mile. Document this mapping in the helper file.

---

### Phase 1 verification checklist

Before closing Phase 1, confirm:

- [ ] `grep` for `displayPercentage` returns zero matches in Swift.
- [ ] `grep` for `pacePercentage` returns only migration-related references in `_shared` backfill code.
- [ ] `grep` for `@AppStorage("paceChart_` returns zero matches.
- [ ] A freshly generated plan writes `target_pace_seconds_per_mile` to every step.
- [ ] Opening an old plan (pre-migration) displays real paces in m:ss (backfill worked).
- [ ] A user with no `fitness_snapshot` gets a clear "set your goal to see paces" message, not "—" or "115%".

---

## Phase 2 — Reconcile every log (~1 week)

Goal: every training log closes the loop. Target vs. actual with weather adjustment. No plan mutations yet.

---

### Prompt 2.1 — Create `workout_reconciliations` table

**Dependencies:** Phase 1 complete.
**Files to create:** new migration.

> Create migration `<timestamp>_workout_reconciliations.sql` with table `workout_reconciliations`: `id uuid pk`, `user_id uuid not null`, `training_log_id uuid not null unique references training_logs(id) on delete cascade`, `scheduled_workout_id uuid references scheduled_workouts(id)` (nullable — unplanned runs have no match), `target_pace_seconds_per_mile numeric`, `actual_pace_seconds_per_mile numeric`, `weather_forecast_jsonb jsonb`, `weather_actual_jsonb jsonb`, `adjusted_target_pace_seconds numeric`, `adjusted_pace_delta_seconds numeric`, `hit_target boolean`, `tolerance_applied_seconds numeric default 5`, `notes_json jsonb`, `created_at timestamptz default now()`. Add indexes on `(user_id, created_at desc)` and `(scheduled_workout_id)`. RLS: users read their own. Service role writes.

---

### Prompt 2.2 — Port dew-point pace adjustment to TypeScript

**Dependencies:** none (can parallel with 2.1).
**Files to create:** `supabase/functions/_shared/pace-heat.ts`.

> Port `calculateDewPointAdjustment` from `RunningLog/RunningLog/Workouts/PaceCalculator.swift` lines 290-350 to TypeScript in `supabase/functions/_shared/pace-heat.ts`. Match the Swift logic exactly: dewPointMultiplier = 1.0 + max(0, (dewPointF - 55) * 0.003495); compositeScore = tempF + (dewPointF * dpMultiplier); lookup adjustment from the same table in PaceCalculator.swift lines 296-307. Export `adjustPaceForHeat(paceSeconds: number, tempF: number, dewPointF: number): { adjustedSeconds, compositeScore, adjustmentPercent, heatCategory }` and `heatCategoryFromScore(score: number): 'ideal'|'warm'|'hot'|'very_hot'|'dangerous'`. Add a small unit test inside the file using a `//@ts-ignore` in-file assert block that verifies three known inputs from the Swift implementation. Do not add Deno test infrastructure — just assertions that run on import in a dev-mode flag.

---

### Prompt 2.3 — Server-side weather fetcher

**Dependencies:** none.
**Files to create:** `supabase/functions/_shared/weather.ts`, `supabase/migrations/<timestamp>_weather_cache.sql`.

> Create a `weather_cache` table with: `lat_key int`, `lon_key int` (both = `round(coord * 100)`), `hour_key bigint` (= `round(unix_ts / 3600)`), `temperature_f numeric`, `dew_point_f numeric`, `humidity int`, `wind_speed_mph numeric`, `weather_code int`, `fetched_at timestamptz default now()`, primary key `(lat_key, lon_key, hour_key)`. RLS disabled (service-role only access). Then create `supabase/functions/_shared/weather.ts` with a function `fetchWeather({ lat, lon, timestamp, kind: 'forecast' | 'historical' })` that: (a) checks cache, (b) on miss, calls Open-Meteo using the exact URLs from `RunningLog/RunningLog/WeatherService.swift` (lines 189 for forecast, 237 for archive), (c) writes to cache, (d) returns the normalized weather object. No API key required (Open-Meteo is free).

---

### Prompt 2.4 — `reconcile-log` edge function

**Dependencies:** 2.1, 2.2, 2.3.
**Files to create:** `supabase/functions/reconcile-log/index.ts`.

> Create edge function `supabase/functions/reconcile-log/index.ts` triggered by POST `{ training_log_id }`. Logic: (1) load the training_log; (2) try to match to a `scheduled_workouts` row with same user_id and workout_date within ±1 day — if multiple, prefer same date exactly; (3) if match found, extract the aggregate target pace from the workout_data steps (weighted by distance — hard steps only, ignore warmup/cooldown); (4) fetch weather for the log's date/location using `_shared/weather.ts` (location comes from the log's first pace_segment GPS start, or fall back to `user_profiles.home_lat/lon` — add those columns if missing via a small migration); (5) compute weather-adjusted target via `_shared/pace-heat.ts`; (6) compute delta = actual - adjusted_target; (7) set `hit_target = abs(delta) <= tolerance_applied_seconds`; (8) insert into `workout_reconciliations`. If no scheduled_workouts match, still insert a row with `scheduled_workout_id = null` and target paces null — this records weather for the log. Return the reconciliation row.

---

### Prompt 2.5 — Postgres trigger on training_logs insert

**Dependencies:** 2.4.
**Files to create:** new migration.

> Create migration that defines a Postgres trigger function `fn_trigger_reconcile_log()` (language plpgsql, security definer) that uses `pg_net.http_post` to call the `reconcile-log` edge function with the new training_log's id. Attach the trigger to `training_logs` `after insert for each row`. Pass the service-role JWT from a secrets table or `vault.secrets` — do not hardcode. If `pg_net` extension is not enabled, enable it in the same migration. Add a simple guard: if `NEW.user_id is null` or `NEW.workout_duration_minutes is null` skip the call. Also: run a one-time backfill that calls `reconcile-log` for every `training_logs` row from the last 90 days. Use a cursor-based approach to avoid hammering the edge function.

---

### Prompt 2.6 — iOS: show reconciliation in log detail

**Dependencies:** 2.1, Phase 1.
**Files to modify:** `RunningLog/RunningLog/Workouts/WorkoutDetailView.swift` or the equivalent log detail surface.

> In the existing log detail view (find via `grep` for where a `training_log` is displayed in detail), fetch the matching `workout_reconciliations` row and render a new card labeled "Coach reconciliation". Show: target pace (from scheduled_workouts), actual pace, weather conditions (temp + dew point with heat category badge), adjusted target pace, delta, and a one-line verdict: "Nailed it" (within tolerance), "Faster than target" (delta < -5s), "Slower than target" (delta > +5s), "Weather-adjusted — you crushed it" (actual beat adjusted target despite hot conditions). Use existing `HeatCategory` enum for colors/icons. If no reconciliation exists (unplanned run, or backfill still running), show nothing — no error, no placeholder.

---

### Phase 2 verification checklist

- [ ] Running a workout inserts a training_log AND a workout_reconciliations row within 30 seconds.
- [ ] The reconciliation row has weather data populated.
- [ ] The log detail view shows target/actual/delta with weather badge.
- [ ] For backfilled historical logs, reconciliations exist for the last 90 days.
- [ ] If Open-Meteo is temporarily unavailable, reconcile-log still writes a row with null weather (doesn't fail the insert).

---

## Phase 3 — Wire adaptation (~1 week)

Goal: the plan mutates. Every change is visible, cited, reversible.

---

### Prompt 3.1 — Create `plan_adjustments` table

**Dependencies:** Phase 2 complete.
**Files to create:** new migration.

> Create migration `<timestamp>_plan_adjustments.sql` with table `plan_adjustments`: `id uuid pk`, `user_id uuid not null`, `plan_id uuid not null references training_plans(id) on delete cascade`, `trigger_type text not null check in ('pace_over_target','pace_under_target','missed_sessions','race_result','volume_ramp_risk','heat_forecast','weekly_rebalance')`, `trigger_evidence jsonb not null` (array of reconciliation_ids or log_ids), `action_type text not null check in ('reprice_future_paces','reduce_volume','cap_volume','propose_swap','update_fitness','pause_quality')`, `action_payload jsonb not null` (the diff that was applied or proposed), `auto_applied boolean not null`, `applied_at timestamptz default now()`, `acknowledged_by_user_at timestamptz`, `reverted_at timestamptz`, `proposed_until timestamptz` (for proposals that expire if not accepted). Index on `(user_id, applied_at desc)`. RLS: users read and update their own. Users can only set `acknowledged_by_user_at` and `reverted_at`, not other fields.

---

### Prompt 3.2 — `adapt-plan` edge function, rule-based

**Dependencies:** 3.1, Phase 2 complete.
**Files to create:** `supabase/functions/adapt-plan/index.ts`, `supabase/functions/_shared/adaptation-rules.ts`.

> Create two files. First, `supabase/functions/_shared/adaptation-rules.ts` exports pure functions, each taking `{ recent_reconciliations, recent_logs, current_plan, current_profile, forecast_14d }` and returning zero or more `AdaptationProposal`s:
>
> - `rule_paceConsistentlyOver`: if the last 3 hard sessions had `delta_seconds <= 3` and `hit_target = true`, propose `action_type='reprice_future_paces'` with 3s/mi faster across all future hard sessions, `auto_applied=false`.
> - `rule_paceConsistentlyUnder`: if 3 of last 4 hard sessions had `delta_seconds >= 10`, propose `reprice_future_paces` 5-8s/mi slower (scaled by delta magnitude), `auto_applied=true` with notification.
> - `rule_missedSessions`: if >=2 quality sessions skipped in last 7 days, propose `pause_quality` for next 7 days, `auto_applied=true`.
> - `rule_raceResult`: if a training_log has workout_type='race' and a known race distance, propose `update_fitness` using the race time, `auto_applied=true`.
> - `rule_volumeRampRisk`: if weekly volume has grown >10% for 3 consecutive weeks, propose `cap_volume` next week at current, `auto_applied=true`.
> - `rule_heatForecast`: if forecast shows dew point > 68F on 3+ upcoming scheduled quality sessions, propose `propose_swap` to cooler days, `auto_applied=false`.
>
> Then `supabase/functions/adapt-plan/index.ts`: called by `reconcile-log` when deltas warrant, or by Sunday cron. Loads inputs, runs all rules, for each proposal either writes `plan_adjustments` with `auto_applied=true` and applies the diff to `scheduled_workouts`/`fitness_snapshots`, or writes with `auto_applied=false` and `proposed_until = now() + 7 days` (athlete must acknowledge). After applying, call `build-pace-profile` to refresh the profile.

---

### Prompt 3.3 — Wire reconcile-log → adapt-plan

**Dependencies:** 3.2.
**Files to modify:** `supabase/functions/reconcile-log/index.ts`.

> At the end of `reconcile-log`, after inserting `workout_reconciliations`, check if the delta warrants invoking adapt-plan. Trigger conditions (match any): `abs(delta_seconds) > 10`, OR `workout_type = 'race'`, OR cumulative missed sessions in last 7 days >= 2. If any match, invoke `adapt-plan` via internal HTTP POST (same edge function cross-call pattern). Do not wait for the response — fire and forget. Log the trigger reason to Sentry.

---

### Prompt 3.4 — Sunday cron for weekly rebalance

**Dependencies:** 3.2.
**Files to create:** Supabase Cron entry + no new edge function needed.

> Register a Supabase Cron job: every Sunday 20:00 in each user's timezone (approximate using `user_profiles.timezone` — if absent, use 20:00 UTC). For each active training_plan user, invoke `adapt-plan` with `{ user_id, trigger: 'weekly_rebalance' }`. Configure via SQL: `select cron.schedule('weekly-plan-rebalance', '0 20 * * 0', $$<body>$$);`. The `adapt-plan` function already handles the weekly_rebalance branch (write this branch if not present: it runs all rules regardless of recent delta, considers the full week's reconciliations, and projects forecast).

---

### Prompt 3.5 — iOS: "Plan updates" feed

**Dependencies:** 3.1, 3.2.
**Files to create:** `RunningLog/RunningLog/Coaching/PlanAdjustmentsView.swift` and a hook in the main coach surface.

> Create `RunningLog/RunningLog/Coaching/PlanAdjustmentsView.swift`. A view that fetches recent `plan_adjustments` (last 30 days, ordered desc) and renders each as a card. Card content: a verb (from trigger_type: "Updated your pace targets" / "Held volume steady" / "Proposed moving your long run" / etc.), 1-2 sentences of reasoning using `trigger_evidence` (e.g., "Last 3 thresholds came in ahead of target — bumping your 10K estimate 4s/mi"), and two buttons: `[Accept]` (if `auto_applied=false`, applies the payload and sets `acknowledged_by_user_at`; if `auto_applied=true`, just sets `acknowledged_by_user_at`) and `[Revert]` (sets `reverted_at`, reverses the diff via a new `revert-plan-adjustment` edge function — see Prompt 3.6). Add a "Plan updates" tab or section in `CoachTabView`. Show an unread badge count of `plan_adjustments` rows where `acknowledged_by_user_at` is null.

---

### Prompt 3.6 — `revert-plan-adjustment` edge function

**Dependencies:** 3.1.
**Files to create:** `supabase/functions/revert-plan-adjustment/index.ts`.

> Create edge function `revert-plan-adjustment/index.ts`. Input: `{ adjustment_id }`, authenticated. Logic: load the `plan_adjustments` row; if `reverted_at is not null`, return 409 (already reverted); reverse the `action_payload` diff — for `reprice_future_paces` restore previous `target_pace_seconds_per_mile` on affected scheduled_workouts (store the previous values in `action_payload.before` so reverting is lossless); for `update_fitness` restore the prior fitness_snapshots row (mark a new snapshot row "reverted from X"); for `cap_volume` and `pause_quality` just delete the future restrictions. Set `reverted_at = now()` on the adjustment. Return success. If the diff can't be reversed (data model constraint), return 422 with a clear message.

---

### Prompt 3.7 — Deprecate the old `adaptive-workout`

**Dependencies:** 3.2, 3.3 (replacement is working).
**Files to modify:** `supabase/functions/adaptive-workout/index.ts`, any iOS callers.

> In `supabase/functions/adaptive-workout/index.ts`, stop writing to `ai_insights`. Return a `410 Gone` response with a body `{ "deprecated": true, "replacement": "adapt-plan" }`. `grep` the iOS and web codebases for calls to `adaptive-workout`. For each caller: either remove the call (if the new adaptive-plan surface covers it) or redirect to `adapt-plan` (if there's a legitimate on-demand use case). Leave a `TODO(delete-after-2026-05-17)` comment on the old function. Do not delete the file yet — keep it for 30 days of backstop.

---

### Phase 3 verification checklist

- [ ] Running a PR-caliber race in a training log triggers a `plan_adjustments` row of `trigger_type='race_result'`, `action_type='update_fitness'`.
- [ ] Missing 2 quality sessions in a week triggers a `pause_quality` adjustment automatically applied.
- [ ] Consistently hitting target paces for 3 hard sessions triggers a `reprice_future_paces` proposal the athlete must accept.
- [ ] Accepting an adjustment in the UI sets `acknowledged_by_user_at`.
- [ ] Reverting restores the prior `scheduled_workouts` paces exactly.
- [ ] Sunday cron runs and emits at least a weekly_rebalance row (even if action is no-op).
- [ ] `adaptive-workout` returns 410 and no live caller references it.

---

## Shared engineering norms for all prompts

- **Branch hygiene:** one prompt = one branch = one PR. Name branches `phase-1-pace-profile`, `phase-2-reconcile-log`, etc.
- **Migrations:** always `IF NOT EXISTS` on creates; always include a `BEGIN` / `COMMIT` wrapper; never run unguarded `UPDATE` on more than 1000 rows without a progress log.
- **Edge functions:** every new function sets `verify_jwt = true` unless explicitly documented why not. Import shared modules via relative paths, not absolute URLs.
- **iOS:** do not use force-unwraps. Errors log to Sentry + local `Log.<category>`. No new `@AppStorage` keys without a design review — prefer SwiftData or the pace profile service.
- **Testing:** each edge function ships with at least one integration-style test that hits a staging project. iOS: at least one unit test per new service.
- **Deprecations:** never delete in the same PR as the deprecation. Deprecate → wait 30 days → delete.

---

## Quick-start if you're executing solo

Best path: run prompts **1.1, 1.2** in parallel (they're independent), then **1.3** (backend profile service), then **1.4** (iOS service). At that point Phase 1 can proceed strictly serially: **1.5 → 1.6 → 1.7 → 1.8 → 1.9 → 1.10**. Verify the Phase 1 checklist before starting Phase 2. Phase 2 and 3 follow the same pattern.

Expected total: **15-20 PRs across 3 weeks** of focused work for one engineer, or **~10 days** for two engineers working in parallel on Phase 1 and Phase 2 once the data model is in place.

---

*End of prompts. Each prompt is sized to be one PR / one Claude Code session. Feed them in order; stop and review after each.*
