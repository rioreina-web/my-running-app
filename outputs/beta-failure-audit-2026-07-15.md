# Commercial Beta Failure Audit — 2026-07-15

Code-level audit of where the app will likely fail in a commercial beta
(~50–500 unsupervised TestFlight users). Three parallel passes: Supabase
backend, iOS app, web/ML/ops. Every item verified against current code,
not docs. Severity: **P0** blocks beta · **P1** embarrassing/likely hit ·
**P2** debt.

---

## P0 — fix before any beta invite goes out

### 1. Voice memos live in a PUBLIC storage bucket (health-data leak)
**FIXED 2026-07-15** — `20260715120000_make_user_storage_buckets_private.sql`
flips both buckets private + recreates owner-scoped policies; guardrail
contract test punch list cleared. Pending `supabase db push` from a
committed SHA (hard rule #9).
`supabase/migrations/20260126_storage_policies.sql:2-3` creates
`training-memos` with `public = true`; `20260227_plan_builder_setup.sql:16-17`
does the same for `plan-attachments`. Public buckets serve at
`/storage/v1/object/public/...` and bypass RLS entirely. `upload-voice-memo`
persists `getPublicUrl` results into `training_logs`. Any athlete's raw
voice memos — mood, fatigue, injury disclosures — are downloadable by
anyone with the URL, no login. Confirmed still open in
`production-guardrails.contract.test.ts:208-211`.

### 2. Rate limiting fails OPEN → unbounded Gemini bill
**FIXED 2026-07-15/16** — `enforceFeatureRateLimit`/`enforceMonthlyCap` now
fail closed in production when Upstash env is missing (dev stays
permissive via `shouldEnforceRateLimits`); the four legacy
`if (isRateLimitEnabled())` guards converted; `enforceMonthlyCap` wired
into all 21 pinned LLM functions with a `MONTHLY_LLM_CAPS` table;
contract tests pin all of it. ⚠️ Deploy prerequisite: confirm
`UPSTASH_REDIS_URL`/`UPSTASH_REDIS_TOKEN` are set as function secrets —
if they're missing in prod today, LLM features will 429 loudly (by
design) after redeploy.
`supabase/functions/_shared/rateLimit.ts:326-327` allows everything when
`UPSTASH_REDIS_URL`/`_TOKEN` aren't set; the circuit breaker also fails
open after 3 Redis errors (`:47-56`). `post-run-analysis` fires per synced
workout — a new user's first import can trigger dozens of LLM calls with
no per-user ceiling and no alert. The daily spend alert
(`20260609233529_daily_llm_spend_alert.sql`) notifies; it does not cap.
`enforceMonthlyCap` exists but is wired into only a few functions.

### 3. `compute-workout-features` has no auth — cross-user read AND write
**FIXED 2026-07-15/16** — `requireAuthOrServiceRole` gate added (JWT must
match body user_id; service-role must name it); removed from the
guardrail test's punch list. Bonus finds while closing it:
`correct-workout-structure` was an unlimited Gemini caller (now
rate-capped, "parse" bucket); `shift-day` was gated all along (test
regex couldn't see the DI pattern — regex widened); 3 cut LLM functions
(`biomechanics-analysis`, `form-check-analysis`, `custom-plan-builder`)
are untracked-in-git and pending your deletion call — documented in
`CUT_FUNCTIONS_PENDING_DELETION`.
`supabase/functions/compute-workout-features/index.ts:315-374` takes
`user_id` from the request body with zero auth, reads that user's full
history, and overwrites `workout_type`/`workout_notes`. The anon key ships
in the app, so any beta user can corrupt another athlete's data. Fix is
one line: `requireAuthOrServiceRole(...)` (the pattern
`correct-workout-structure` already uses).

### 4. Deterministic crash-on-launch if Secrets aren't in the archive
**FIXED 2026-07-16** — new "Guard: Secrets.xcconfig applied" build phase
(runs first) fails any build where `SUPABASE_URL`/`SUPABASE_ANON_KEY`
are empty or placeholders, turning the launch crash into a build error.
Bonus: removed `Secrets.xcconfig` from the Resources phase — it was
being copied into the shipped app bundle (nothing reads it at runtime).
Needs one Xcode build on the Mac to confirm (no Swift toolchain here).
`RunningLog/Services/Supabase.swift:86-93` — `fatalError` in global client
init when `SUPABASE_URL` is empty. A TestFlight archive built without
`Secrets.xcconfig` attached = 100% crash at launch for every tester.
Verify the archive configuration before cutting the build.

### 5. Legal docs are unreviewed drafts, unlinked from the product
`docs/legal/privacy-policy.md:3` and `terms-of-service.md:3` both say
"DRAFT — NOT LEGAL ADVICE"; dates, contact email, governing law are
`[TODO]`. The landing footer (`web/src/app/(public)/page.tsx:234-247`) has
no privacy/ToS links. Apple requires a working privacy-policy URL for
TestFlight review, and this is a health-data app. Also: policy names
Resend, stack uses SendGrid (`supabase/config.toml:222-233`).

### 6. Prod lags the repo — deploys are manual and secret-blocked
`.github/workflows/deploy.yml:20-21` is `workflow_dispatch` only and the
required GitHub secrets are not added (`docs/ops-delivery-roadmap-2026-06-10.md:9`).
CI's eval gate is disabled (`ci.yml:144` `if: false`), db-lint no-ops
without a secret (`ci.yml:132-134`), iOS job builds but runs no tests.
Concretely pending: migrations `20260615210000-230000` (athlete_settings +
Daily Read cron — Settings and the morning Coach Read don't exist in prod
until pushed) and `20260703120000/121000` (plan_adjustments vocab — until
applied, every athlete day-move audit row is silently dropped, so
`revert-plan-adjustment` has nothing to undo; `shift-day/index.ts:334-352`
swallows the CHECK failure non-fatally). `shift-day` + `subscribe-to-plan`
also need redeploy or web hits the known 404.

---

## P1 — beta users will hit these; embarrassing

### 7. HealthKit denial is silent — app looks empty and broken
**FIXED 2026-07-16** — `HealthKitManager` gains an honest 5-state
`readState` (HealthKit hides read-denial by design, so the probe checks
whether ANY data is visible: any workout, else steps in last 30d —
steps exist on virtually every iPhone, added to read types).
`requestAuthorization` no longer assumes success = granted. Onboarding
now shows CONNECTED ✓ only when data is actually visible; otherwise
"NO DATA · FIX ↗" with an alert (Open Health app / continue anyway).
Existing-user upgrade path guarded: visible data short-circuits before
the request-status check, so adding the steps type can't un-authorize
current users.
`Health/HealthKitManager.swift:80-83` sets `isAuthorized = true` on any
non-throwing return, but HealthKit doesn't throw on denied *read* access;
`checkAuthorizationStatus()` (`:48-64`) treats "empty result, no error" as
access. Onboarding shows "CONNECTED ✓" (`OnboardingView.swift:148-149`)
even after Don't Allow. Denying user sees empty Trends/Train/Coach forever
with zero explanation. **This will be the #1 "app doesn't work" report.**

### 8. Mic denial → silent empty recordings uploaded as real memos
**FIXED 2026-07-16** — `startRecording` now checks/requests record
permission (`AVAudioApplication`), shows a Settings alert on denial,
and treats a false return from `audioRecorder.record()` as a hard
failure (no timer over dead air, no silent upload). Also fixed the
audit's P2 #19 sibling: VoiceLogView now uses `HealthKitManager.shared`
instead of instantiating a second diverging manager.
`Workouts/VoiceLogView.swift:828-864` never requests record permission and
ignores `audioRecorder?.record()`'s return value. Denied mic → timer runs,
silent .m4a uploads, transcription empty, blank journal entry. Voice is
the core loop; there is no denied-permission branch anywhere in the app.

### 9. The promised 2-year HealthKit backfill doesn't exist
`App/RunningLogApp.swift:174-182` — the only import is
`fetchRecentRunningWorkouts(limit: 30)`; dedup window is 90 days
(`WorkoutSyncService.swift:43`). "Lands in a product that already knows
her" is currently "30 most recent runs." Race auto-detection from history
can't work. Either build it (design it to skip per-workout LLM analysis on
historical rows, or it compounds #2's cost) or reset expectations.

### 10. All athletes are UTC — Daily Read fires at the wrong time, all at once
**FIXED 2026-07-16** — `AthleteSettingsService.syncDeviceTimezone()` (iOS)
upserts `TimeZone.current.identifier` on every launch (per-user cache
skips unchanged writes; retries next launch if the table isn't pushed
yet). H4 guardrail flag flipped to lock it in. Note: prod effect starts
only after the 20260615 migrations are pushed AND the athlete_settings
RLS hole (#11) is fixed in the same push.
Nothing writes `athlete_settings.timezone` (only `max_heart_rate` is
written, `Supabase.swift:274-286`). Once the cron migration is pushed,
every athlete dispatches on the single 06:00-UTC tick — US users get their
"morning" read at 10pm–2am local, and ~all athletes fire simultaneous
service-role `coaching-daily-read` calls that **bypass the rate limiter**.
Date-boundary bugs near local midnight too (`coaching-daily-read/index.ts:335-359`).

### 11. `athlete_settings` RLS reintroduces the anon hole
`20260615210000_create_athlete_settings.sql` policies include
`OR auth.uid() IS NULL` on SELECT/INSERT/UPDATE — an anon-key-only caller
can read/edit any athlete's row, including `home_lat`/`home_lon` (home
GPS). This regresses the March lockdown (`20260313100000:5,47-48`) and
violates hard rule #1. Fix before `db push`.

### 12. `reschedule-plan` ships without its required safety layer
`supabase/functions/reschedule-plan/index.ts:186-208` returns Gemini's
output with no server-side validation against `WORKOUT_CODES_BY_DAY`, no
hard-rule check, and raw athlete free-text interpolated into the prompt
(injection surface). No retry on Gemini failure. Rate limit is 10/day, not
the mandated once-per-day. And per #13, its evals are stubs — the closed-
vocabulary safety currently lives only in the prompt.

### 13. Golden eval families are stubs — unverified safety behavior
All `reschedule-plan.v1/v2` and `coaching-agent-*` cassettes have empty
`recorded_response` (16 stubs). The unrecorded cases are exactly the
safety-baitable ones: `003-push-through-injury-request`,
`001-athlete-self-diagnoses`, `004-pace-prescription-request`. CI only
blocks on *touching* the prompt, so these ship unguarded today. One
`record.ts` run with `GEMINI_API_KEY` (~$0.05) fills them.

### 14. New-user Coach tab is a skeleton forever
**FIXED 2026-07-16** — the no-row/no-error branch now renders
`EmptyStateView` (.setupNeeded, "GENERATE TODAY'S READ" CTA calling
`service.refresh()`, which generates on a miss). data_depth dead code
(P2) still open.
`Coaching/Read/CoachReadView.swift:97-105` renders a redacted placeholder
in the exact brand-new-account state (no read, not loading, no error) —
looks like a permanent loading spinner. Trends handles this correctly
(`TrendsTabView.swift:97-118`); Coach needs the same empty state.
Related: `data_depth` gating (`Shared/AthleteState.swift:14-40`) is dead
code — never called anywhere on iOS.

### 15. Every beta athlete can reach the coach portal and mint a coach account
`web/src/middleware.ts:56-58` has no role check; the sidebar shows "Coach"
to everyone (`sidebar.tsx:34`); `coach-setup-prompt.tsx:44-49` inserts a
`coach_profiles` row from the client, and RLS permits it
(`20260313100000:307`). Not a data leak (coach_id-scoped) but exposes an
unfinished B2B surface to a consumer beta.

### 16. Edge functions have zero error tracking
**FIXED 2026-07-16 (core surface)** — new `_shared/sentry.ts`
(npm:@sentry/deno@10.64.0, fail-soft without a DSN): `captureException` +
`flushSentry` wired into the top-level catches of coaching-agent,
coaching-daily-read, process-training-memo, reschedule-plan,
compute-workout-features, generate-workout-insight, post-run-analysis;
`withSentry` wraps shift-day + upload-voice-memo (no top-level catch).
Requires `supabase secrets set SENTRY_DSN=<backend project DSN>` — use a
separate Sentry project from iOS. Still open: remaining ~30 functions
(wire opportunistically) and a failed-job alert for the outbox drains.
Sentry is wired for web, iOS, and ml-service — but not edge functions
(`_shared/router.ts:70` says so explicitly). When a beta user hits a
failure in `coaching-agent`/`adapt-plan`/`shift-day`, the only signal is
Supabase console logs. Jobs that exhaust retries sit `status='failed'`
with no alert. You will not know your beta is failing.

### 17. ML service fragility (if it matters — see #21)
Corrupt `fitness_model.joblib` → `joblib.load` at import with no
try/except (`predictor.py:60-66,265`) → worker never boots, every endpoint
500s. Model artifact is gitignored, so Railway likely runs heuristic-only
(`/health` reports `model_loaded: false`). Boot hard-exits without
`SUPABASE_JWT_SECRET` (`config.py:24-33`), which the committed `.env`
lacks.

---

## P2 — debt to watch

18. **Ghost `user_profiles` reads remain** in `post-run-reconciliation:149`,
    `reconcile-log:235-237`, `weekly-coaching-report:332` — weather
    enrichment silently no-ops.
19. **Vital sandbox still called** with empty keys
    (`VitalManager.swift:18-20`; called from `WorkoutSyncService.swift:100,315`)
    — dead network calls pinned to a sandbox host. VoiceLogView also
    instantiates a second `HealthKitManager` instead of `.shared`
    (`VoiceLogView.swift:34`), so auth state can diverge.
20. **PII in release logs**: `print()` of user UUID and backend URL
    (`AuthManager.swift:199`, `SignInView.swift:156`). `AuthManager.userId`
    returns `""` pre-auth and callers build storage paths/queries with it
    (`VoiceLogViewModel.swift:257,444`).
21. **ML service has no production caller** — live Railway infra holding a
    service-role key, zero traffic, outside the deploy pipeline. Consider
    pausing it for beta.
22. **Latent force-unwraps** in `VitalWorkoutCharts.swift:478,517` — crash
    if a stream point lacks HR/cadence (masked only because Vital is off).
23. **Supabase auth email throttle**: `email_sent = 2`/hour
    (`config.toml:188`) — a beta invite wave throttles confirmation emails;
    signup email silently fails if `SENDGRID_API_KEY` unset. Password
    minimum is 6 chars with no requirements.
24. **Brand inconsistency**: "Post Run Drip" (landing/legal) vs.
    `heatcheckmile.com` (`config.toml:159`) vs. `app.postrundrip.com`
    (ml-service). Landing sells a solo running log; product contains a
    B2B coach portal.
25. **Live service-role key in plaintext** at `ml-service/.env`
    (gitignored, never committed — verified) — rotate if the machine is
    shared.
26. **Timeouts on defaults**: `callEdgeFunction` uses `URLSession.shared`
    (60s), voice processing polls 60s then silently refreshes — slow
    backend = minute-long spinner with no messaging.

---

## What actually breaks first, in order

A realistic beta user's first hour: install → **crash if Secrets miswired
(#4)** → deny HealthKit → **empty app, no explanation (#7)** → deny mic →
**blank journal entries (#8)** → expect their history → **only 30 runs
(#9)** → open Coach → **skeleton forever (#14)** → meanwhile their voice
memos are **publicly downloadable (#1)**, your **Gemini bill is uncapped
(#2)**, and **you can't see any of it happening (#16)**.

### Suggested fix order (cheapest-first within severity)
1. Flip both buckets private + signed URLs (#1) — one migration.
2. Auth-gate `compute-workout-features` (#3) — one line.
3. Verify Upstash env on deployed functions; wire `enforceMonthlyCap`
   across all LLM endpoints (#2).
4. Strip `OR auth.uid() IS NULL` from athlete_settings policies (#11),
   then do the pending `supabase db push` + redeploy (#6).
5. Verify Secrets.xcconfig in the archive config (#4).
6. Real HealthKit-denied + mic-denied detection and empty states (#7, #8).
7. Record the 16 stub cassettes (~$0.05) and add server-side validation to
   reschedule-plan (#12, #13).
8. Coach tab empty state (#14); decide the backfill story (#9); write an
   `athlete_settings.timezone` writer (#10).
9. Sentry (or equivalent) in edge functions + failed-job alert (#16).
10. Lawyer pass on legal docs + link them from landing and app (#5).
