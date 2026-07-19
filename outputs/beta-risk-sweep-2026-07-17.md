# Beta Risk Sweep — 2026-07-17 (follow-on to the 2026-07-15 audit)

A second code-level pass hunting for risks the 2026-07-15 audit did **not**
already cover. Three parallel passes (backend / iOS / web+ML+ops), every
finding verified against current code; RLS and RPC findings additionally
verified against **live production `pg_policies` / `pg_proc`**, not migration
files (several file-level flags turned out to be superseded).

Severity: **P0** blocks beta · **P1** embarrassing / likely hit · **P2** debt.

---

## RESOLVED in this sweep

### R1. Anon-key RLS holes across 5 live tables + 5 SECURITY DEFINER RPCs
**FIXED (pending `supabase db push`)** — `20260717140000_close_anon_rls_holes.sql`
(+ in-place fix to the still-unpushed `20260717130000_create_coach_workout_reads.sql`).

The 2026-07-15 audit flagged this pattern on `athlete_settings` only (#11). It
was systemic. Confirmed live in prod via `pg_policies`:

| Table | Cmds | Exposure |
|---|---|---|
| `athlete_settings` | SELECT/INSERT/UPDATE | home_lat/home_lon + timezone of any athlete |
| `coachable_moments` | SELECT/UPDATE | all synthesized injury/mood/load observations; status mutable |
| `coach_athlete_relationships` | INSERT | self-enroll a coach onto any athlete |
| `athlete_plan_subscriptions` | INSERT | forge a subscription naming any athlete |
| `usage_tracking` | INSERT | inject usage/billing rows |
| `coach_workout_reads` | SELECT | same hole; not yet in prod (fixed at source) |

Plus SECURITY DEFINER RPCs with `anon=EXECUTE` (PostgREST-callable):
`dedupe_recent_training_logs` (**not user-scoped, bypasses RLS → global delete
sweep**), `merge_voice_orphan_into_run`, `backfill_workout_insights`,
`enqueue_daily_reads`, `increment_subscriber_count`. Revoked from
anon+authenticated; service_role/cron retain access (verified `subscribe-to-plan`
uses the service-role key).

### False positives worth recording (do not re-investigate)
Subagents flagged `ai_insights` (as P0), `race_intel`, and `workout_features`
as anon-open by reading their **CREATE** migrations. Live `pg_policies` shows
all three are correctly locked to `user_id = auth.uid()` + service_role — a
later tightening pass superseded the original policies. **Lesson: audit RLS
against live `pg_policies`, not migration files.**

---

## Still open — verified real

### 1. IDOR on web `/api/vital-stream` — cross-user GPS + HR leak (P1)
`web/src/app/api/vital-stream/route.ts:22-28`, `web/src/lib/vital.ts:81-84,8`
The `id` param is validated only as `z.string().min(1)` — no check that the
workout belongs to the caller — then passed to Vital with the server-side
`VITAL_API_KEY`. All users share one hardcoded `VITAL_USER_ID`, so workout IDs
are not tenant-partitioned. A beta user can enumerate IDs and pull another
runner's per-second lat/lng (home address) + HR + power.
**Fix:** resolve the workout ID to a `training_logs` row owned by `user.id`
before calling Vital.

### 2. Second plaintext production service-role key (P1)
`web/.env.local:6-8` — a live `SUPABASE_SERVICE_ROLE_KEY` (full RLS bypass) +
`VITAL_API_KEY` in cleartext. Distinct from the known ml-service/.env (#25).
Gitignored / not in git history (checked), so disk-only, but the
`.env.example` note claiming "already rotated 2026-04-14" is contradicted.
**Fix:** rotate the service-role key (treat as burned); confirm no shared-disk
exposure. Vital key is sandbox (lower blast radius).

### 3. "Cut" LLM edge functions still live and auto-deploying (P1)
`supabase/functions/{custom-plan-builder,form-check-analysis,biomechanics-analysis}/index.ts`
(full handlers, not stubs) + leftover `strava-test-pull`. `deploy.yml:78-84`
deploys every directory with no allow-list, so the LLM-generative endpoints
that were **deliberately cut** for cost/safety (per CLAUDE.md "Recent
decisions") reach prod and are invokable by any JWT holder — unbudgeted
generation + prompt-injection surface.
**Fix:** delete the dirs and `supabase functions delete` them from prod, or
410-stub them; add a deploy allow-list.

### 4. iOS offline queue — cross-account voice-memo leak (P1)
`RunningLog/Services/OfflineQueue.swift:255-311`; sign-out at
`AuthManager.swift:209`. Queued uploads bake in **no user id** — the owner is
resolved at *drain* time from `AuthManager.shared.currentUserId`, and sign-out
never purges the queue or on-disk audio. User A records offline → signs out →
User B signs in on the same TestFlight device → reconnect drains A's memo into
**B's** account/storage path.
**Fix:** stamp `userId` into the payload at enqueue; verify-or-drop at drain;
purge queue + audio on sign-out.

### 5. iOS duplicate `auto_sync` rows from concurrent sync (P1)
`RunningLog/Services/WorkoutSyncService.swift:16-17,44,93,156`. Launch `.task`
(`RunningLogApp.swift:183`) and the Workouts tab (`WorkoutsView.swift:117`) each
spin a **fresh** `WorkoutSyncService`; the `!isSyncing` guard is per-instance.
On cold launch both read the dedup set before either inserts → duplicated
`training_logs`, double-counted mileage + ACWR.
**Fix:** shared sync actor/singleton, or upsert on `(user_id, vital_workout_id)`
(the partial-unique index from `20260613230000` already exists — the launch
path just isn't using an upsert).

### 6. iOS auth token-refresh recovery is dead code (P1)
`RunningLog/Services/AuthManager.swift:122-183`. `handleRefreshFailure` /
`queueRefreshOnReconnect` are never called; the `authStateChanges` switch has
no refresh-failure branch. The documented "offline → keep session; online →
retry once else sign out" path is inert — the same class of bug that
previously stranded voice-memo uploads.
**Fix:** subscribe to the SDK refresh-failure signal and invoke
`handleRefreshFailure`.

### 7. iOS check-in upload uses a storage path the app declares broken (P1)
`RunningLog/ViewModels/VoiceLogViewModel.swift:260-267`. `uploadCheckIn` uploads
directly via `supabase.storage.from("training-memos").upload(...)` — the exact
direct-storage path RLS-rejected since 2026-06-02 (why voice memos route
through the `uploadVoiceMemoAudio` edge function per the sibling comment at
:74-78). Every check-in fails its first attempt; the enqueue then mislabels it
as a "voice memo" (`OfflineQueue.swift:72` hardcodes `type:"voiceLog"`).
**Fix:** route check-in audio through the same edge function.

### 8. Strava OAuth tokens plaintext + client-readable (P2)
`20260429100000_strava_credentials.sql:20-21,46-50`. `access_token`/
`refresh_token` are plaintext TEXT with `FOR ALL USING (user_id = auth.uid())`,
so the client can SELECT raw tokens. Only the service-role edge function needs
them.
**Fix:** service-role-only policy (no client SELECT); encrypt / Vault the tokens.

### 9. iOS delete-before-insert with no atomicity → run/note loss (P2)
`VoiceLogViewModel.swift:363-371` (`saveManualNotes`) and `:131-140`. Both delete
the existing `auto_sync` row **before** inserting the replacement, no
transaction. If the insert throws (offline/5xx/RLS), the original run row is
gone; `saveManualNotes`'s catch only reports — no re-insert, no enqueue.
**Fix:** insert first, delete the dup only after insert succeeds.

### 10. GitHub Actions script injection in `record-evals.yml` (P2)
`.github/workflows/record-evals.yml:47-52`. `inputs.prompt` is interpolated
straight into a shell `run:` step in a job holding `GEMINI_API_KEY` +
`contents:write` + `pull-requests:write`. Insider/lateral-movement risk
(needs repo-write to dispatch).
**Fix:** pass via `env:` and reference `"$PROMPT"`.

### 11. ML service exposes `/docs` + `/openapi.json` unauthenticated (P2)
`ml-service/app/auth.py:27`. Full API surface enumerable by anyone reaching the
Railway URL. Recon surface, not a direct leak.
**Fix:** `docs_url=None, openapi_url=None` when `ENV=production`, or auth-gate.

### 12. Third-party GitHub Actions pinned to mutable tags while holding prod DB secrets (P2)
`deploy.yml:56,66`, `drift-detector.yml:40` (`supabase/setup-cli@v1`),
`record-evals.yml:56` (`peter-evans/create-pull-request@v6`). A retagged action
runs inside a job with `SUPABASE_ACCESS_TOKEN` / `SUPABASE_DB_PASSWORD`.
**Fix:** pin at least the third-party actions to full commit SHAs.

### 13. iOS uncancelled polling loops racing `loadHistory` (P2)
`VoiceLogViewModel.swift:150-220,304-325`. Each upload spawns detached poll
tasks (20×3s) never stored/cancelled on teardown, each firing `loadHistory()`
with no ordering → stale journal, flicker, queries running after the view is
gone.
**Fix:** hold poll tasks, cancel on disappear; serialize `loadHistory`.

### 14. iOS heavy HealthKit stream building on the MainActor (P2)
`WorkoutSyncService.swift:16` (`@MainActor`) + `HealthKitManager.buildExternalStreams:393`.
Full ~1 Hz GPS route (7,000+ pts for a long run) + HR, JSON-encoded on the main
actor for up to 30 workouts at launch → jank/hangs; multi-MB `external_streams`
JSONB per row (batch insert size risk at `:156`).
**Fix:** build streams off the main actor; downsample the route.

### 15. `config.toml` references three non-existent functions; no config-drift guard (P2)
`supabase/config.toml` — `[functions.assess-fitness]`, `[functions.log-manual-workout]`,
`[functions.log-training]` have no function directory. Inert today (omissions
default to `verify_jwt=true`, the safe direction) but latent misconfig.
**Fix:** remove dead stanzas; add a config-vs-dirs check to drift-detector.

### 16. iOS StadiaRouteMap ships with an empty API key (P2)
`RunningLog/.../StadiaRouteMap.swift:38,49`. `apiKey = ""` → every route map in
the beta renders the no-key fallback. Blank feature for all users if maps are
meant to ship.

---

## Checked & cleared (so nobody re-investigates)
- Edge-function JWT auth is real (signature-validated via `supabase.auth.getUser`,
  timing-safe service-role compare) despite widespread `verify_jwt = false`.
- CORS fails closed (throws if `ALLOWED_ORIGIN` unset in prod).
- No dynamic-SQL injection in migrations/RPCs; `body_mentions` RLS is correct;
  `debug_coach_log` denies all non-service access.
- Hot-path composite indexes exist (`training_logs(user_id, workout_date)`,
  `scheduled_workouts(user_id, date)`, partial-unique `(user_id, vital_workout_id)`).
- Web: coach athlete-detail pages properly gated behind an active subscription
  before the service-role read; middleware uses `getUser()` (not `getSession`);
  no open redirects; CSP nonce-based, no `unsafe-inline`; security headers set;
  only `dangerouslySetInnerHTML` is DOMPurify-wrapped; `next@16.1.6` past
  CVE-2025-29927; ML endpoints enforce ownership + bound `days` via Pydantic.
- `ai_insights` / `race_intel` / `workout_features` RLS correct in prod (see
  False positives above).

---

## Suggested order (cheapest-first)
1. `db push` R1 (already written) + `db push` batch review (also picks up
   `athlete_avatars`, `coach_workout_reads`). **Blocking.**
2. Rotate the `web/.env.local` service-role key (#2). Minutes.
3. Delete/stub the cut LLM functions + deploy allow-list (#3). Small.
4. Auth-scope `/api/vital-stream` to the caller's workouts (#1). Small.
5. iOS: stamp userId into the offline queue + purge on sign-out (#4);
   upsert the auto_sync path (#5); wire refresh-failure handling (#6);
   route check-in through the edge function (#7). One iOS PR.
6. P2 batch: Strava token policy (#8), atomic note save (#9), CI hardening
   (#10, #12), ML docs off in prod (#11), config-drift (#15).
