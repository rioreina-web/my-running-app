# Security risks, failure risks, and 1000-user readiness

Companion to `outputs/tech-debt-audit-2026-05.md`. Date: 2026-05-12.

## TL;DR

The app is in better shape than its reputation. Auth is real: every
edge function checks the JWT, the ml-service validates the Supabase
JWT in middleware against the `sub` claim, the service-role key is
confined to server-side code, RLS was locked down on 2026-03-13, and
rate limiting is enforced on the four highest-cost web routes via a
pinned contract test. Failure paths are also more mature than expected:
there's an outbox/queue with retries and exponential backoff for
coach-insight LLM dispatch, a stuck-records cleanup cron, transcribe
has three-provider fallback (Groq → OpenAI → Gemini), and the scale
indexes for 20k users are already in place.

What's actually exposed for a 1000-user push falls into **five real
risks**:

1. **No provider-side billing cap on Gemini** — a runaway, a prompt
   regression, or a malicious user could spend unbounded $ before the
   in-code daily cap fires.
2. **`ALLOWED_ORIGIN` falls back to `*`** if the env var is unset.
3. **JWT secret is shared (HS256)** between Supabase and the ml-service
   — any compromise of the ml-service env compromises auth signing.
4. **No documented backup/restore drill** — Supabase Pro backs up
   nightly, but no one has ever tested a restore.
5. **No per-user rate limit on the LLM-heavy path** in edge functions
   (web has it; edge does not consistently). One pathological user can
   burn the daily budget.

Plus the three carry-overs from the tech-debt audit that are now
also failure risks at scale: no eval harness, no CI, no synthesis
trigger.

---

## Security: what's good

| Surface | Posture | Evidence |
|---|---|---|
| JWT auth on edge functions | Verified per request | `supabase/functions/_shared/auth.ts` — `getAuthenticatedUser` decodes Bearer, calls `supabaseClient.auth.getUser(token)`, returns 401 on failure |
| ml-service auth | JWT middleware on every non-public path | `ml-service/app/auth.py` — verifies HS256, audience=`authenticated`, issuer, sets `request.state.user_id` from `sub` |
| Service-role key handling | Server-only | Found in 14 edge functions + 4 web `api/` routes + `web/src/lib/env.ts` — **never** in iOS Swift or web client React. Correct boundary. |
| RLS lockdown | Real, dated 2026-03-13 | `20260313100000_lock_down_rls.sql` drops every `USING(true)` and `auth.uid() IS NULL` fallback policy by name; 9 migrations use `vault.decrypted_secrets` for secrets |
| Web API rate limits | Pinned by contract test | `web/tests/rate-limit.contract.test.mjs` — coach 20/min, assign-plan 10/min, weekly-report 5/min, retry-processing 5/min |
| ml-service rate limits | Per-user via `slowapi` | `Limiter(key_func=_rate_limit_key)` uses JWT `sub`; `@limiter.limit("10/minute")` on prediction endpoints |
| Coach RLS recursion fix | `SECURITY DEFINER` helper | `current_coach_id()` from `20260311120000_fix_coach_rls_recursion.sql`; convention enforced in `CLAUDE.md` |
| Error monitoring | Wired everywhere | Sentry in iOS (`SentryService.swift`), web (`instrumentation.ts`), ml-service (`sentry-sdk[fastapi]==2.16.0`) |

## Security: what's exposed

### S1. CORS falls back to `*` if `ALLOWED_ORIGIN` is unset
**File:** `supabase/functions/_shared/cors.ts`

```ts
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "*";
```

If the env var isn't set in production, every edge function happily
accepts cross-origin requests from anywhere. Combined with bearer-token
auth this is **not** an immediate breach (the request still needs a
valid JWT), but it lifts the cost of CSRF-style abuse from "must run
on the app domain" to "anywhere."

**Fix:** make `ALLOWED_ORIGIN` a required env in production. Crash on
boot if it's missing in non-dev `SUPABASE_ENV`. Or set it server-side
and remove the fallback. 30 minutes of work.

### S2. JWT secret is symmetric (HS256) and shared with ml-service
**File:** `ml-service/app/auth.py`

```py
payload = jwt.decode(token, SUPABASE_JWT_SECRET, algorithms=["HS256"], ...)
```

Supabase signs JWTs with a project-wide secret; the ml-service holds a
copy to verify. If the ml-service container is breached (env exfil,
Sentry leak, vulnerable Python dep), the attacker can forge JWTs for
any user in the project. RS256 with a public verification key would
make ml-service breach contained.

**Fix:** medium-term. Supabase supports rotating to RS256 JWTs and
publishing JWKS. Worth doing before headcount on the project grows.
For now: lock down ml-service env, get Sentry scrubbing on, and verify
`requirements.txt` deps aren't yanked.

### S3. Service-role key is referenced in `web/src/lib/env.ts`
**File:** `web/src/lib/env.ts` and four `web/src/app/api/*/route.ts` files.

This is fine **only** if those route handlers run server-side in
Next.js (they do — `app/api/`). But the existence of the key in a
file named `env.ts` is a misclick-from-disaster pattern. One developer
imports `env` from a client component and ships a service-role key to
the browser bundle.

**Fix:** rename to `env.server.ts`, mark the file with
`import "server-only"` at the top, and add an ESLint rule banning
client imports of it. Cheap.

### S4. `parse-*` and `coaching-agent` accept long user-controlled
strings into LLM prompts
The four `parse-*` functions and `coaching-agent` build prompts that
include athlete-supplied free text (workout descriptions, chat
messages). Standard prompt-injection surface. The mitigations that
exist — closed body-part vocabulary in the niggles classifier, closed
`WORKOUT_CODES_BY_DAY` library in `reschedule-plan` — are good. The
mitigations that *don't* exist yet are an eval harness that catches
"the LLM diagnosed an injury after a user paste of medical text," and
output validation against a schema.

**Fix:** roll into the eval harness work from the tech-debt audit.

### S5. No documented PII handling for audio uploads
Voice logs upload to Supabase Storage; transcripts persist. There's no
docs/legal page covering retention, deletion-on-request, or whether
audio is ever sent to third parties (Groq / OpenAI / Gemini all see
the audio or transcript). Counsel work, but it's the same workstream
as the legal-docs TODOs from the tech-debt audit.

---

## Failure modes: what's good

| Path | Resilience | Evidence |
|---|---|---|
| `coach_insight` LLM dispatch | Outbox + retries + backoff | `20260508140000_coach_insight_outbox.sql` + `drain-coach-insight-jobs` runs every minute, batch 40, parallel 10, retries 3×, backoff 2^n × 30s capped 30min |
| Stuck audio processing | Cron cleanup | `cleanup_stuck_processing` resets >5min `processing` rows to `failed`; `cleanup_stale_pending` for >30min orphans |
| Transcribe provider failure | Three-provider fallback | `transcribe/index.ts` tries Groq → OpenAI → Gemini |
| LLM cost runaway | In-code daily budget cap | `dailyBudgetExceeded()` in `generate-workout-insight/index.ts`; `COACH_INSIGHT_DAILY_BUDGET` env var |
| Query performance at scale | Composite indexes | `20260312200000_add_scale_indexes.sql` ("Composite indexes for scale (20k+ users)"); `20260416100000_add_coach_composite_indexes.sql` |
| Operator visibility on LLM pipeline | `coach_insight_status` column | `pending` / `generated` / `failed` / `skipped` — distinguishes NULL states |

## Failure modes: what's exposed

### F1. The in-code LLM cost cap is the weakest cost defense
**File:** `supabase/functions/generate-workout-insight/index.ts`, lines
58, 146, 291. `TASKS.md` already documents this:

> The current `dailyBudgetExceeded()` check in
> `generate-workout-insight/index.ts` is the weakest layer of cost
> protection — it lives inside the same code that could be buggy.

A retry storm, a prompt regression that 10×s token usage, or a
compromised service-role key could spend orders of magnitude past the
cap before anyone notices, because the cap fires only *after* a call
completes. The provider-side billing cap (Google Cloud Billing →
Budgets) is the only real defense.

**Fix:** the open task in `TASKS.md`. Set a Google Cloud billing
budget on the Gemini project at $50/mo with auto-disable at 110%. Add
a daily Slack alert for spend. 1 day of work, mostly waiting on Cloud
Console permissions.

### F2. No backup/restore drill
Supabase Pro backs up daily and supports PITR with the add-on. There's
no evidence in `docs/deploy/` of anyone ever having restored a
backup. A real restore takes ~30 minutes if you've done one, ~6 hours
if you haven't.

**Fix:** in a Supabase branch, restore last night's backup, verify the
schema and a known user's data, document the runbook in
`docs/deploy/restore-runbook.md`. 4 hours.

### F3. No edge-function-side per-user rate limit on LLM calls
The web `api/` routes have per-route, per-user rate limits via the
contract test. The edge functions have `_shared/rateLimit.ts` invoked
in ~10 places, but it's not consistently per-user. A single user could
abuse the iOS app's direct edge function calls to burn LLM budget that
the web rate limit would have stopped.

**Fix:** standardize edge-fn rate limiting on per-`user_id` keys,
align limits with the web pins. 1–2 days.

### F4. pg_net failures are fire-and-forget
**Evidence:** 39 `pg_net` invocations across migrations. `pg_net` is
async; if a call fails, the request lives in `net.http_response`
briefly and then is gone. No DLQ for trigger-fired HTTP calls.

The outbox pattern fixes this for `coach_insight`. The other 8 cron
and trigger calls (`generate-workout-insight` via outbox now ✓,
`reconcile-log`, `weekly-plan-review`, weather forecast, weekly
reports, voice auto-process) don't have the same protection.

**Fix:** the highest-stakes one — voice auto-process — should adopt
the same outbox pattern. Lower-stakes (weather, weekly review) can
keep fire-and-forget and rely on cron re-runs. Plan a 1-week project.

### F5. The synthesis trigger gap is now a *correctness* failure mode
From the tech-debt audit: `evaluate-coachable-moment` has no
`training_logs` trigger. At 1000 users this manifests as athletes
seeing zero coachable moments after most runs, because the synthesis
pillar only fires from cron. One-migration fix.

### F6. Cron job concentration on Supabase
Six cron jobs scheduled in Postgres (`pg_cron`). All bound to one
Supabase project. If Supabase has an outage during the
`drain-coach-insight-jobs` window, jobs queue fine, but if it's during
the weekly-report cron, the report just doesn't go out and there's no
catch-up logic on the next tick.

**Fix:** add an idempotent "missed runs" check to each cron job — if
the prior expected run didn't happen, run it now. Or accept this; it's
a Supabase-availability bet that's reasonable for v1.

---

## 1000 users: what actually has to happen

Two layers: **infrastructure capacity** (the boring stuff that already
mostly works) and **operational readiness** (the stuff that doesn't).

### Capacity check — back-of-envelope

Assumptions: 1,000 DAU, ~60% active any given day, average 1 run + 4
voice logs per week per active user.

| Resource | Volume/day | Headroom |
|---|---|---|
| `training_logs` inserts | ~860/day | Trivial. Indexes cover. |
| Voice transcribe calls | ~340/day | Groq Whisper free tier 100 req/min. Bursts the only risk; outbox handles. |
| `coach_insight` LLM calls | ~860/day @ ~$0.0004 | **~$10/mo** total Gemini spend. |
| `coaching-agent` chat calls | ~5,000/week ≈ 700/day at higher token | ~$20–40/mo |
| Edge function invocations | ~3–5/user/day → 3–5k/day, ~150k/mo | Supabase Pro: free up to 2M/mo |
| Postgres connections | ~50 concurrent peak | Pooler handles 200; direct 60. **Verify pooler is on.** |
| Database size | ~1.2 GB at 1k users with 6mo history | Supabase Pro 8 GB. Fine. |
| Storage (audio) | 1k users × 5 logs/wk × 200 KB × 6mo ≈ 26 GB | Supabase Pro 100 GB. Fine. |
| ml-service load | ~10 RPM steady, peaks 100 RPM | Railway 1-cpu fine; verify horizontal scale config. |

**Conclusion: no infrastructure constraint binds at 1000 users.** The
work isn't capacity, it's operational gates.

### Pre-1000 readiness checklist

Sequenced by what blocks first. Total: ~3 engineering weeks.

#### Week 1 — money, identity, blast radius

- [ ] **Gemini provider-side billing cap.** Google Cloud Billing →
  Budget at $50/mo, auto-disable at 110%. Eliminates F1.  *0.5d*
- [ ] **Slack alert for daily Gemini spend.** `pg_cron` + `pg_net` to
  webhook. Operator sees the trend even before the cap fires.  *0.5d*
- [ ] **Require `ALLOWED_ORIGIN` env in production.** Remove the `*`
  fallback in `_shared/cors.ts`. Eliminates S1.  *0.5d*
- [ ] **Rename `env.ts` → `env.server.ts`, add `server-only` import,
  ESLint rule** banning client imports. Eliminates the misclick path
  in S3.  *0.5d*
- [ ] **Stand up CI** (from tech-debt audit #2). Without it, every fix
  below is one careless push away from being undone.  *1.5d*

#### Week 2 — correctness gates

- [ ] **Eval harness scaffold** (tech-debt audit #1). Cover
  `coaching-agent`, `injury-analysis`, niggles classifier,
  `reschedule-plan`. Wires into CI.  *5d*
- [ ] **Synthesis trigger migration** (tech-debt audit #4). One
  migration, mirrors the existing `trigger_workout_insight` pattern
  for `evaluate-coachable-moment`. Closes F5.  *0.5d*
- [ ] **Per-user edge-fn rate limits on LLM paths.** Standardize on
  `user_id` keying across the ~10 functions already using
  `_shared/rateLimit.ts`. Match the web limits. Closes F3.  *1.5d*

#### Week 3 — operational readiness

- [ ] **Backup restore drill** + runbook in `docs/deploy/`. Closes F2.
  *0.5d*
- [ ] **Verify Supabase pooler is enabled** and Next.js `api/` routes
  use the pooler connection string, not the direct one. Without this
  you hit the 60-conn ceiling around 200 concurrent users.  *0.5d*
- [ ] **Voice auto-process → outbox pattern.** Adopt the same outbox
  pattern that's already protecting `coach_insight` for the audio
  pipeline. Closes F4 for the highest-stakes case.  *3d*
- [ ] **On-call rotation + Sentry alerting.** Sentry is wired; nobody
  is configured to receive its alerts. Add a Slack channel and a
  rotation for the first month.  *0.5d*
- [ ] **PII handling docs** in `docs/legal/` — audio retention,
  third-party processors, deletion-on-request. Same workstream as the
  legal-doc TODOs.  *Counsel.*

### What you do **not** have to do for 1000 users

These are the ones it's tempting to do and aren't earning their cost:

- Split `coaching-agent` (1,811 LOC) and `generate-training-plan`
  (2,078 LOC). Wait until the eval harness exists; refactoring under
  test is much cheaper.
- Migrate to RS256 JWTs. The shared-secret risk (S2) is real but the
  blast radius at 1k users is bounded by what one breached ml-service
  container can do. Schedule for the 10k-user prep.
- Horizontal-scale ml-service. One Railway dyno handles the projected
  load with margin.
- Collapse the `parse-*` cluster. Hygiene, not safety.
- Build a status page. At 1k users the audience is too small to
  justify it; an email distribution list works.

---

## Single-page summary

**Security:** auth is real, RLS is real, secrets are server-side. The
five exposures are CORS-fallback, shared JWT secret, a misclick path
on `env.ts`, prompt-injection surface in user-text-into-LLM, and
missing PII docs. None are open-front-door issues. All are fixable
inside two weeks.

**Failure modes:** the outbox/retry pattern is the right answer and
it's been applied to the highest-volume path. The remaining six
exposures are cost-cap-in-code instead of provider-side, no backup
drill, inconsistent per-user rate limits on edge-fn LLM paths, fire-
and-forget pg_net for non-critical jobs, the synthesis-trigger gap,
and cron concentration. The first three matter; the rest can wait.

**For 1000 users:** capacity isn't the problem at all. Gemini cost is
~$30–60/mo. Supabase Pro covers everything else with multiples of
headroom. The work is operational: provider-side billing cap, CI, eval
harness, backup drill, on-call rotation, and the synthesis trigger
migration. **~3 engineering weeks, no infra spend over $100/mo.**
