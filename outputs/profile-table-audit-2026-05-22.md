# Step 0 Audit — `user_profiles` & `athlete_profiles` references

**Date:** 2026-05-22
**Scope:** `supabase/functions/`, `web/`, `RunningLog/`, `supabase/migrations/`
**Status:** Inventory only — nothing fixed. This is the punch list for Step 5.

## Production reality check (read this first)

The codebase itself has already documented the bug — in three places, in code comments — and built local workarounds. None of those workarounds reached the edge functions.

- **`web/src/app/(app)/coach-portal/athletes/page.tsx:64`** — explicit comment: *"there's no `user_profiles` table on this DB, so the source of truth is `auth.users.email`."* Web coach-portal switched to admin API.
- **`RunningLog/Shared/LocationProvider.swift:9`** — explicit comment: *"a phantom `user_profiles.home_lat` row that doesn't exist on the server."* iOS switched to CoreLocation as primary source.
- **`supabase/functions/fetch-workout-weather/index.ts:349`** — explicit comment: *"The `user_profiles` table doesn't ship in every env yet, so guard the lookup behind a try/catch and treat any failure as 'no profile row' rather than 500ing."* Defensive try/catch added.

**Translation:** `user_profiles` either doesn't exist in production or isn't populated for most athletes. Three different engineers patched around it locally; the broader cleanup never happened. Every "STATE / EVENT / SETTINGS" recommendation in this audit is *also* a bug fix, not just a migration.

The `athlete_profiles` cache *does* exist (migration `20260316120000_athlete_profiles.sql`) and is actively written by `build-athlete-profile/index.ts`. It's not phantom — just superseded by `athlete_state`.

## Intent legend

- **STATE** → migrate read to `athlete_state` (the Dynamic Context Object / canonical read surface)
- **EVENT** → migrate to event log (discrete facts: injuries, PRs/results, profile mutations)
- **DELETE** → remove; deprecated cache layer or redundant
- **SETTINGS** → out of scope for this migration; device/location/locale config that belongs in a user-settings surface, not state or events

---

## `athlete_profiles` (cached `profile_data` blob — comprehensive historical analysis, rebuilt ≤1×/24h)

| File | Line | Reads | Writes | Intent |
|---|---|---|---|---|
| `_shared/athlete-state.ts` | 355 | `select *` — folds cached blob into state rebuild | — | **DELETE** — `athlete_state` should derive from source tables, not the derived cache. Sever this dependency. |
| `build-athlete-profile/index.ts` | 56 | `profile_data, updated_at` — 24h freshness check | — | **DELETE** — deprecate the whole cache-build function |
| `build-athlete-profile/index.ts` | 175 | — | `upsert {user_id, profile_data, updated_at}` | **DELETE** — only writer; remove with the function |
| `block-review/index.ts` | 95 | `profile_data` | — | **STATE** |
| `coaching-agent/index.ts` | 790 | `profile_data` | — | **STATE** |
| `injury-early-warning/index.ts` | 366 | `profile_data` | — | **STATE** |
| `post-run-analysis/index.ts` | 163 | `profile_data` | — | **STATE** |
| `race-readiness/index.ts` | 113 | `profile_data` | — | **STATE** |
| `training-analysis/index.ts` | 1307 | `profile_data` | — | **STATE** |
| `weekly-coaching-report/index.ts` | 300 | `profile_data` | — | **STATE** |

---

## `user_profiles` (structured columns: PRs, paces, mileage, injuries, home_lat/lon, timezone, preferred_run_time)

| File | Line | Reads | Writes | Intent |
|---|---|---|---|---|
| `_shared/profile.ts` | 147 | `select *` (`getOrCreateProfile`) | — | **STATE** ⚠️ mixed surface — returns attributes **and** settings; callers must be split when migrating |
| `_shared/profile.ts` | 156 | — | `insert {user_id}` (creates empty row) | **DELETE** — empty-row bootstrap of the mixed table goes away; settings row + state init handled separately |
| `_shared/profile.ts` | 454 | `current_injuries` (read-for-merge) | — | **EVENT** — injuries are events, not a mutable array |
| `_shared/profile.ts` | 468 | — | `upsert {user_id, ...updates}` | **EVENT** ⚠️ mixed writer — injury appends → event log; PR/pace mutations → event log (results); only write path into `user_profiles` |
| `injury-analysis/index.ts` | 115 | `current_weekly_mileage, peak_weekly_mileage, years_running, easy_pace_per_mile, tempo_pace_per_mile, cross_training` | — | **STATE** |
| `weekly-coaching-report/index.ts` | 276 | `select *` | — | **STATE** ⚠️ verify field usage — attributes→STATE, injuries field→EVENT, location/tz→SETTINGS |
| `coaching-daily-read/index.ts` | 298 | `timezone` | — | **SETTINGS** |
| `fetch-workout-weather/index.ts` | 235 | `home_lat, home_lon, preferred_run_time` | — | **SETTINGS** |
| `fetch-workout-weather/index.ts` | 358 | `home_lat, home_lon, preferred_run_time` (try/catch guarded) | — | **SETTINGS** |
| `fetch-workout-weather/index.ts` | 437 | `home_lat, home_lon, preferred_run_time` | — | **SETTINGS** |
| `post-run-reconciliation/index.ts` | 131 | `home_lat, home_lon` | — | **SETTINGS** |
| `reconcile-log/index.ts` | 237 | `home_lat, home_lon` | — | **SETTINGS** |

---

## Web & iOS call sites

| File | Line | Reads | Writes | Intent |
|---|---|---|---|---|
| `web/src/app/(app)/settings/page.tsx` | 17 | `display_name, email, unit_preference, created_at` | — | **SETTINGS** — also fails today; settings page likely renders defaults in prod. Repoint to `auth.users` + dedicated settings table when SETTINGS surface lands. |
| `web/src/app/(app)/coach-portal/athletes/page.tsx` | 64 (comment) | — | — | Already worked around — no action. Leave the comment as a tombstone. |
| `RunningLog/Services/DailyReadService.swift` | 257 (comment) | — | — | Comment-only; references `user_profiles.timezone` semantics. Update comment when SETTINGS lands. |
| `RunningLog/Shared/LocationProvider.swift` | 9 (comment) | — | — | Already worked around — no action. Leave as tombstone. |

---

## Migrations referencing these tables (historical — append-only, do not edit)

These exist for archeological context. Per CLAUDE.md migrations are append-only — none of these get modified, but a new "deprecate" migration will be needed at the end of Step 5.

| Migration | Refs | Role |
|---|---|---|
| `20260128_152000_user_profile.sql` | 4 | Creates `user_profiles`. Original PRs/paces/mileage/injuries schema. |
| `20260216_add_auth_security.sql` | 3 | RLS for `user_profiles`. |
| `20260220_fix_remaining_rls.sql` | 3 | More RLS for `user_profiles`. |
| `20260313100000_lock_down_rls.sql` | 5 | Locks down RLS on both `user_profiles` and `athlete_profiles`. |
| `20260316120000_athlete_profiles.sql` | 5 | Creates `athlete_profiles` cache table. |
| `20260416500000_weather_infrastructure.sql` | 6 | Adds `home_lat / home_lon / preferred_run_time` to `user_profiles`. |
| `20260423100000_daily_weather_forecast_cron.sql` | 1 | Cron job references. |
| `20260427100000_scheduled_workout_time_of_day.sql` | 2 | References `preferred_run_time` resolution order. |
| `20260519110000_daily_coaching_reads_cron.sql` | 6 | Cron job that joins on `user_profiles` — **likely broken in prod**, flag for Step 5 verification. |
| `20260519120000_daily_coaching_reads_workout_trigger.sql` | 1 | Trigger reference. |

**Open question for Step 5:** the May 2026 daily-coaching-reads cron explicitly joins `user_profiles`. If the table isn't there, this cron has been silently failing or no-oping since it shipped. Verify with PostgREST logs before declaring "the cleanup is the whole bug."

---

## Not call sites (comments only — no action)

- `build-athlete-profile/index.ts:6` — docstring
- `coaching-daily-read/index.ts:290` — docstring
- `fetch-workout-weather/index.ts:348-349` — inline comment
- `reconcile-log/index.ts:235` — inline comment

---

## Summary & flags for Step 5

- **`athlete_profiles` is a pure cache layer.** 7 reader functions (STATE), 1 builder (`build-athlete-profile`, DELETE), and 1 surprise: `athlete-state.ts:355` reads the cache blob *while building state* — derived-from-derived. **Highest-priority untangle:** `athlete_state` must compute from source tables before the 7 readers can safely repoint to it.
- **`user_profiles` is three tables wearing one coat:** athlete attributes (paces/PRs/mileage → STATE), injuries (→ EVENT), and device/location/locale settings (→ SETTINGS, 6 read sites). The two `_shared/profile.ts` mutators (`getOrCreateProfile`, `updateProfile`) are shared and **mixed** — splitting them is the load-bearing change; every other site is a simple repoint once the surfaces exist.
- **SETTINGS doesn't fit any of the three target buckets.** home_lat/lon, timezone, preferred_run_time are config, not fitness state or events. Forcing them into `athlete_state` would pollute the DCO. **Decision needed:** dedicated settings surface vs. leave in place.

### Counts

- `athlete_profiles`: 10 call sites → 7 STATE, 3 DELETE
- `user_profiles`: 13 call sites in edge functions + 1 in web → 3 STATE, 2 EVENT, 1 DELETE, 8 SETTINGS (⚠️ 3 marked mixed/verify)
- Total actionable call sites: **24**

---

## Sequenced punch list for Step 5

Don't migrate call sites in source-file order. Migrate in dependency order so each step is independently shippable.

### Phase 5a — Sever the derived-from-derived dependency (½ day)

The only step that must come first. `_shared/athlete-state.ts:355` reads `athlete_profiles.profile_data` *while building state*. This is derived-from-derived and blocks every other STATE migration — you can't have callers read `athlete_state` instead of `athlete_profiles` until `athlete_state` itself stops needing `athlete_profiles`.

- Remove the `athlete_profiles` fetch from `_shared/athlete-state.ts`.
- Re-derive whatever it was contributing directly from source tables (`training_logs`, `injuries`, `athlete_pace_profiles`, `user_goals`, `body_mentions`).
- Bump `derivation_version` on `athlete_state`.
- Backfill: re-derive state for all athletes once.

### Phase 5b — Repoint the 7 cache readers (1 day)

Each is a mechanical swap of `.from("athlete_profiles").select("profile_data")` → `getOrBuildAthleteState(supabase, userId)`. Order doesn't matter; do them in one PR so the diff is reviewable as a set.

- `block-review/index.ts:95`
- `coaching-agent/index.ts:790`
- `injury-early-warning/index.ts:366`
- `post-run-analysis/index.ts:163`
- `race-readiness/index.ts:113`
- `training-analysis/index.ts:1307`
- `weekly-coaching-report/index.ts:300`

Eval harness must pass against these scenarios before merge.

### Phase 5c — Delete the cache builder (½ day)

After 5b lands and bakes for a few days with no regression:

- Delete `supabase/functions/build-athlete-profile/` entirely.
- Add migration: drop the cron job (if any) that invokes it.
- Leave the `athlete_profiles` *table* in place for one release cycle; mark deprecated in a comment migration. Drop in a follow-up after one week of no reads.

### Phase 5d — Split `_shared/profile.ts` (1 day)

The load-bearing change. `_shared/profile.ts` is the only writer into `user_profiles` and it conflates attributes + injuries. Split:

- Attribute extractors (`extractProfileData` for PRs/mileage/paces) → emit events to the event log instead of upserting. State derivation picks them up from there.
- Injury extractor → emit injury events (which `injuries` table likely already handles — verify and dedupe).
- `getOrCreateProfile` / `updateProfile` → delete. No replacement; callers either read state or emit events.
- `buildProfileContext` (line 494) → already redundant with `stateToPromptContext`; delete and migrate callers to the prompt builder.

### Phase 5e — Migrate the 3 attribute readers (½ day)

- `injury-analysis/index.ts:115` → read fields from `athlete_state` instead.
- `weekly-coaching-report/index.ts:276` → read from `athlete_state`. Verify which fields it actually uses (it does `select *`); replace with explicit field list.
- `_shared/profile.ts:147` (`getOrCreateProfile` callers) — already handled by 5d deletion.

### Phase 5f — SETTINGS surface decision (separate spec; not blocking)

Eight call sites read settings columns from `user_profiles`. These can keep limping along on try/catch fallbacks until a SETTINGS surface decision is made. Two options:

1. **New `athlete_settings` table** — clean, but new migration + new RLS + new client code. ~2 days.
2. **Move into `auth.users.user_metadata` JSONB** — zero schema work, but harder to query from edge functions. ~½ day.

Recommend option 1 for queryability. Out of scope for this audit; spec separately.

### Phase 5g — Final sunset (½ day)

After all of the above:

- Add a deprecation migration that drops `user_profiles` and `athlete_profiles` from the schema.
- Remove the defensive try/catch comments referencing missing tables.
- Update `CLAUDE.md` to reflect `athlete_state` as the canonical profile surface.
- Run a final grep — should return zero matches outside this audit doc.

---

## Total estimate

| Phase | Effort |
|---|---|
| 5a — sever derived-from-derived | ½ day |
| 5b — repoint cache readers | 1 day |
| 5c — delete cache builder | ½ day (after bake) |
| 5d — split `_shared/profile.ts` | 1 day |
| 5e — migrate attribute readers | ½ day |
| 5f — SETTINGS surface | 2 days (separable) |
| 5g — sunset | ½ day |
| **Total** | **4 dev days + 2 for SETTINGS** |

This is Step 5 of the broader plan; it presupposes Step 1 (eval harness) is live before 5b ships.

---

## Open questions

1. Is `user_profiles` actually missing in prod, or just unpopulated? PostgREST logs would resolve in 10 minutes — grep for `PGRST205` ("table not found") errors on `user_profiles` over the last 7 days. Outcome changes Phase 5g (drop vs. truncate-and-keep).
2. Does the daily-coaching-reads cron job (`20260519110000`) actually run successfully in prod? If it fails on the `user_profiles` join, the May 19 daily-read feature is silently degraded.
3. Is `athlete_state` derivation logic (`getOrBuildAthleteState`) currently complete enough to absorb the data that was flowing through `athlete_profiles.profile_data`? Cross-reference `athlete-state-refactor-design.md` §4 — the P2 cleanup items (R7 pace zones, R8 race history) overlap with this audit's STATE bucket.
4. SETTINGS surface — separate `athlete_settings` table, or `auth.users.user_metadata`? Decide before Phase 5f.
