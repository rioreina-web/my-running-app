# System Design — Post Run Drip

**Scope:** As-is architecture + target state, optimized for current early stage (<1K users). The goal is to fix what's fragile now and lay just enough foundation so growth to ~10K doesn't force a rewrite. Nothing in here recommends premature scale engineering.

**Source material:** Code walk of `RunningLog/`, `web/`, `supabase/`, `ml-service/`, plus `production-readiness-report.docx` (April 13, 2026) and `claude-code-prompts.md`.

---

## 1. Requirements

### Functional (observed from code)
- Users authenticate (Sign in with Apple on iOS, Supabase Auth on web) and get a per-user coaching experience.
- iOS client ingests workouts from **HealthKit** and **Vital/Junction API**, dedupes them, and writes `training_logs` to Supabase (with offline queue + auto-sync on reconnect).
- Users can voice-log check-ins and training memos; transcription is server-side.
- AI coaching agent produces chat responses, weekly reports, race intel, injury early warnings, plan generation, and post-run analysis via 36 Supabase Edge Functions.
- Web app is the "browser dashboard" with training history, coaching, plans, and a Sanity-backed public blog.
- ML service exists but is **parked** until there's enough data (≥30 users × 60 days) — iOS currently uses a local heuristic for fitness prediction.

### Non-functional (current stage)
- **Scale:** <1K users. Design for 10× growth without rearchitecture; do not design for 100K.
- **Latency:** p95 CRUD <500ms is fine. LLM first-token <3s is acceptable.
- **Availability:** 99.5% target. Planned downtime OK. No multi-region.
- **Cost ceiling:** keep infra <$200/mo until paid tier users meaningfully exist. LLM spend is the variable to watch, not infra.
- **Privacy:** health data — treat it seriously even without HIPAA (no PHI sharing with third parties, encryption in transit, least-privilege DB access).

### Constraints
- Small team, likely 1–2 engineers. Optimize for operational simplicity.
- Stack already committed: Swift (iOS), Next.js (web), Supabase (backend), Python/XGBoost (ML). Don't propose replacing any of these.
- Four production-readiness blockers must be resolved before growth marketing: secrets, rate limiting, ML auth, Supabase dev-mode config.

---

## 2. As-Is Architecture

### Component map

```
┌─────────────────────────────────┐        ┌─────────────────────────────────┐
│  RunningLog iOS (SwiftUI)       │        │  web (Next.js 16, App Router)   │
│                                 │        │                                 │
│  • HealthKit (read)             │        │  • Supabase SSR client          │
│  • Vital/Junction API           │        │  • Middleware auth + CSP        │
│  • SwiftData local cache        │        │  • 5 server API routes          │
│  • OfflineQueue + NetworkMonitor│        │  • Sanity CMS (blog)            │
│  • Keychain (auth tokens)       │        │  • Upstash Redis (rate limit)   │
│  • Local fitness heuristic      │        │  • Sentry                       │
└────────────┬────────────────────┘        └──────────────┬──────────────────┘
             │ PostgREST + Auth JWT                       │ PostgREST + SSR JWT
             │                                            │ + calls to Edge Fns
             ▼                                            ▼
   ┌────────────────────────────────────────────────────────────────────────┐
   │                     Supabase (managed, single region)                  │
   │                                                                        │
   │  ┌──────────────────────────┐    ┌──────────────────────────────────┐ │
   │  │ Postgres (51 migrations) │    │ Edge Functions (Deno, TS) × 36   │ │
   │  │  • training_logs         │◄───┤  Coaching:                       │ │
   │  │  • training_plans        │    │   coaching-agent, weekly-report  │ │
   │  │  • scheduled_workouts    │    │   post-run-analysis, block-review│ │
   │  │  • coaching_feedback     │    │  Plan:                           │ │
   │  │  • conversations / docs  │    │   custom-plan-builder, parse-*   │ │
   │  │  • injuries, biomech     │    │  ML feature prep:                │ │
   │  │  • fitness_snapshots     │    │   compute-workout-features       │ │
   │  │  • user_memories         │    │   fitness-predictor (heuristic)  │ │
   │  │  • content_library       │    │   injury-analysis, injury-early  │ │
   │  │  • 43+ RLS policies      │    │  Media:                          │ │
   │  │    (hardened Mar 2026)   │    │   biomechanics-analysis          │ │
   │  └──────────────────────────┘    │   form-check-analysis, transcribe│ │
   │  ┌──────────────────────────┐    │  Admin/debug: admin-sql (unauth)│ │
   │  │ Auth (GoTrue), Storage,  │    └──────────────┬───────────────────┘ │
   │  │ Realtime                 │                   │ LLM providers        │
   │  └──────────────────────────┘                   ▼                      │
   └────────────────────────────────────────┬────────────────────────────────┘
                                            │
                          ┌─────────────────┴──────────────────┐
                          ▼                                    ▼
              ┌───────────────────────┐              ┌─────────────────────┐
              │ Anthropic / Gemini /  │              │ ml-service (parked) │
              │ Groq (LLM routing)    │              │ FastAPI on Railway  │
              └───────────────────────┘              │ XGBoost + heuristics│
                                                     └─────────────────────┘
```

### Data flow — "log a run"

1. HealthKit or Vital hands iOS a new workout.
2. `WorkoutSyncService` dedupes against a 90-day window of `training_logs` and inserts via PostgREST (JWT scoped to user).
3. A Postgres trigger (or `post-run-analysis` Edge Fn called from iOS) kicks off `compute-workout-features`, which writes JSONB into `training_logs.extracted_data`.
4. On demand, the web dashboard reads `training_logs` via SSR; on a coaching session, `coaching-agent` reads recent logs + conversation history and produces a response through the multi-model router.
5. Weekly, `weekly-coaching-report` aggregates into `weekly_coaching_reports`.

### Observed strengths
- **RLS hardening** is recent and thorough (`20260313100000_lock_down_rls.sql`). `auth.uid()` is the authorization boundary, not application code. This is the single biggest thing already done right.
- **iOS offline path** is real — `OfflineQueue` + `NetworkMonitor` drain on reconnect.
- **Rate limiting** exists on the coaching agent via Upstash Redis + circuit breaker (this is better than most apps of this size).
- **Multi-model routing** for cost (Groq for simple, Gemini Flash for complex) is the right pattern for LLM spend.
- **ML service is parked** — the team correctly deferred productionizing it.
- **Content boundary is clean:** public blog (Sanity) is separate from authenticated dashboard.

### Observed tensions and risks
Pulled from the readiness report and code inspection, ordered by severity:

1. **Secrets sprawl.** Vital API key in iOS Bundle and web `.env.local`; Supabase anon key in iOS binary (acceptable but assumes RLS is airtight); Gemini key inside Edge Fns. A rotation today would touch three repos and an App Store release.
2. **ML service auth is absent.** Endpoints take `user_id` from the request body and CORS is `["*"]`. Since the service is parked, this is latent — but it's wired in Railway, so anyone who finds the URL hits `/predict-fitness` for free. **Take it down or lock it down, now.**
3. **Edge functions with `verify_jwt = false`.** `admin-sql` and (per the prompt list) `coaching-agent` have this disabled for debugging. Any edge function that reads user-scoped data should enforce JWT.
4. **Six web API routes without rate limits.** `/api/coach` and `/api/weekly-report` have limits; the rest (`/api/assign-plan`, `/api/vital-stream`, `/api/retry-processing`) don't. LLM cost and DB write abuse exposure.
5. **`SUPABASE_SERVICE_ROLE_KEY` used in web API routes with user JWT forwarded.** If this is the server-side-with-forwarded-JWT pattern, it's correct; if routes use service role to bypass RLS, a logic bug turns into a tenant leak. Needs audit.
6. **Supabase config is in development mode.** `site_url = localhost`, SMTP = inbucket, email confirmations off. Works for dev, **blocks any new-user flow** in production.
7. **iOS failure handling.** Silent SwiftData save failures (OfflineQueue), a failed token refresh signs the user out, and there's a known force-unwrap crash risk in `WorkoutSyncService`. All hit the happy path in dev; all show up with real users on flaky networks.
8. **Hardcoded Supabase URL in Postgres trigger functions.** Makes environment promotion (staging/prod) fragile.
9. **Missing indexes.** `coaching_feedback(user_id, created_at)` and `goal_outcomes(user_id, created_at)` are flagged in the readiness report.
10. **CSP allows `unsafe-inline` / `unsafe-eval`.** Middleware injects nonce-based CSP per request — good — but the policy still has escape hatches.
11. **Blog renders HTML with `dangerouslySetInnerHTML`.** `isomorphic-dompurify` is present; confirm it's actually in the render path.
12. **Coupling risk: 36 edge functions.** Not a problem today, but `coaching-agent`, `weekly-coaching-report`, `post-run-analysis`, and `block-review` all duplicate "fetch recent training_logs + shape context for LLM." Extract a shared context-builder soon.

---

## 3. Target Architecture (lean, early-stage)

The target keeps the same components. What changes is **hygiene, secrets, and one strategic refactor** around the coaching pipeline. Explicitly rejecting: queues, new services, multi-region, self-hosting, a new ML platform.

```
iOS ─── Supabase (Postgres + 36 Edge Fns + Auth + Storage) ─── LLM providers
 │                       │
 │                       ├─ _shared/coaching-context    ← new shared module
 │                       ├─ _shared/secrets (Vault-backed) ← new
 │                       ├─ _shared/rate-limit (unified) ← existing, extended
 │                       └─ ml-service                  ← parked but locked down
 │
web ─── same Supabase, same Edge Fns
 │
Sanity (public blog, unchanged)
```

### 3.1 Secrets — single source of truth

**Target:** all secrets live in Supabase Vault or 1Password Secrets Automation. No secrets in:
- iOS Bundle (except the Supabase **anon** key and public identifiers — allowed)
- web `.env.local` committed anywhere
- Edge Function source

**Mechanism:**
- iOS calls an authenticated `/vital-token` Edge Function that mints short-lived tokens via the stored Vital key. The key never leaves Supabase.
- Edge Functions read LLM keys from Supabase env vars; those env vars are set from Vault/1Password via CI, never committed.
- One runbook document tracks what each secret is, where it's stored, and when it was last rotated.

This is the **highest-leverage change** and is mostly process work, not code.

### 3.2 ML service — two options, pick one this week

**A. Take it down** until the data threshold is hit. Remove the Railway deployment, keep the repo. This is the lean recommendation.

**B. Lock it down.** Require Supabase JWT on every endpoint (`PyJWT` is already in `requirements.txt`), drop `user_id` from the request body and read it from the token's `sub` claim only, set CORS to the specific web origin and no other, run as non-root (already doing this), rate-limit per user.

Don't leave it in the current state.

### 3.3 Edge Functions — close the auth gaps

- `verify_jwt = true` on every function except ones that are legitimately unauthenticated (webhooks with their own signature verification).
- `admin-sql` is either deleted or moved behind a service-role check + IP allowlist + audit log.
- Audit every route that uses `SUPABASE_SERVICE_ROLE_KEY` to confirm it's the "server action with user JWT forwarded" pattern, not "bypass RLS." Document the rule in `_shared/README.md`.

### 3.4 Rate limiting — extend existing pattern

Upstash Redis already works on `/api/coach`. Apply the same middleware to the other five web API routes. Per-user limits, keyed by Supabase JWT sub:

```
/api/coach            20/min   (existing)
/api/weekly-report     5/min   (existing)
/api/assign-plan      10/min   (add)
/api/vital-stream     60/min   (add — ingestion, higher)
/api/retry-processing  5/min   (add)
```

Do the same inside Edge Functions that are called directly from iOS.

### 3.5 Coaching context — extract a shared module

Four Edge Functions shape "recent training logs + user goals + conversation history" for LLM prompts. Extract `supabase/functions/_shared/coaching-context.ts` with a single `buildContext(userId, options)` function. Benefits: one place to test, one place to change prompt-visible schema, one place to add caching.

Pair it with a semantic cache (already present on `coaching-agent`) applied uniformly.

### 3.6 Supabase config — move to production mode

A checklist, not a design:
- Point `site_url` at the real domain.
- Configure real SMTP (Resend or Postmark — Resend has cleanest Supabase integration).
- Enable email confirmation.
- Production Supabase project distinct from dev; migrations run via CI against both.
- Hardcoded Supabase URLs in trigger functions → read from Postgres GUC or a config table.

### 3.7 iOS robustness — small, surgical fixes

- `OfflineQueue` save failures log to Sentry and surface a toast.
- Refresh-token failure attempts a silent re-auth once before signing out.
- Remove force-unwraps in `WorkoutSyncService`; add a `RunningLogTests` case for the null-Vital-response path.
- Feature-flag the `fitness-predictor` Edge Fn → iOS can switch from local heuristic to server prediction when ML is ready, without an App Store release.

### 3.8 Database — two indexes and a plan for audit

- Add the two missing indexes (`coaching_feedback`, `goal_outcomes` on `(user_id, created_at)`).
- Keep daily `pg_stat_statements` checks in a weekly review; add indexes reactively.
- At <1K users, don't denormalize or partition anything.

### 3.9 Observability — what to watch, lean

Already have Sentry + Upstash. Add:
- **LLM cost dashboard**: sum `llm_requests.cost_cents` per user per day. Alert on any user >$5/day (abuse or bug).
- **Sync lag**: time between `training_log.created_at` on iOS and first `extracted_data` write. p95 >60s means a pipeline is broken.
- **Edge Function error rate**: Sentry is enough.
- **Uptime**: single uptime monitor hitting a `/health` edge function.

Not needed yet: APM, log aggregation platform, tracing. Add when a real incident reveals a gap.

---

## 4. Scale and Reliability — what breaks, and when

| Load level | What stays the same | What changes |
|---|---|---|
| <1K users (now) | Everything in the target above | Nothing beyond target |
| 1K–10K | Same architecture | Watch Edge Function execution time (cold starts), consider Postgres read replica if read-heavy dashboards bite |
| 10K–100K | Same architecture still works | Move `coaching-agent` to a durable workflow (Inngest or Supabase queue) so long LLM calls don't tie up Edge Fn slots; productionize ML service; add proper APM |
| 100K+ | Would require revisit | Out of scope for this doc |

**Reliability posture today:** single-region Supabase + managed Vercel + parked Python service. Acceptable for the current stage. PITR backups on Supabase Pro are the main recovery lever — confirm they're enabled.

---

## 5. Trade-offs

| Decision | Chose | Alternative | Why this choice at this stage |
|---|---|---|---|
| Secrets layer | Supabase Vault + 1Password | AWS Secrets Manager | Already in-stack; no new vendor |
| ML service v1 | **Take down** | Lock down + keep running | Service has no users; keeping it running is pure risk surface |
| LLM provider strategy | Keep multi-model router | Consolidate to Anthropic | Cost structure is working; don't change what works |
| Offline strategy | Keep custom `OfflineQueue` | Adopt PowerSync/WatermelonDB | Existing code works; migration cost > benefit at this scale |
| Coaching context | Extract shared module | Leave as-is | 4+ edge fns duplicating context-building is the one real coupling pain today |
| Queue for LLM calls | **None** | Inngest/SQS | Not needed; Edge Fns handle current volume. Revisit at 10K users |
| Edge Fn splitting (36 is a lot) | **Keep** | Consolidate into fewer fns | Each fn has a clear job; merging creates more coupling than it removes |
| Observability | Sentry + one dashboard | Full APM stack | Overkill for <1K users |

### Explicit non-goals at current stage
- Multi-region, replication, or failover beyond Supabase defaults.
- Moving any workload off Supabase.
- Productionizing the ML service.
- Replacing Sanity, Vercel, or Upstash.
- A real-time collaborative feature in coaching.
- Building custom analytics.

---

## 6. Migration path — 3 weeks of engineering

### Week 1 — Stop the bleeding
- [ ] Decide ML service fate (take down — recommended — or lock down). Ship it same day.
- [ ] Enable `verify_jwt` on every edge fn that reads user data; delete or gate `admin-sql`.
- [ ] Add rate limiting to the remaining 3 web API routes.
- [ ] Audit `SUPABASE_SERVICE_ROLE_KEY` usage; document the rule.

### Week 2 — Secrets + prod config
- [ ] Vault + 1Password source of truth; rotate every credential once the pipeline is in place.
- [ ] iOS `/vital-token` Edge Fn; remove Vital key from Bundle.
- [ ] Supabase prod project: real SMTP, real `site_url`, email confirmation on.
- [ ] Remove hardcoded Supabase URLs from trigger functions.
- [ ] Add the two missing indexes.

### Week 3 — Resilience + coaching refactor
- [ ] iOS: Sentry on OfflineQueue failures, graceful token refresh, remove force-unwraps, add the regression test.
- [ ] `_shared/coaching-context.ts`: extract, cover with tests, migrate the 4 fns.
- [ ] LLM cost dashboard + per-user anomaly alert.
- [ ] CSP hardening (remove `unsafe-inline` / `unsafe-eval` — may require refactoring any inline handlers).

After that, normal feature work resumes. The architecture should not need a revisit until 10K users.

---

## 7. Open questions

1. **Does the web's server-side `SUPABASE_SERVICE_ROLE_KEY` usage forward the user's JWT** (correct pattern) or bypass RLS (risky)? I need to look at `/api/coach/route.ts` to confirm.
2. **ML service:** take it down or lock it down? (I recommend down.)
3. **Revenue/tier model:** `user_profiles.tier` exists — is it wired to anything yet? Changes whether cost controls are urgent.
4. **iOS TestFlight users today** — roughly how many, and are any paying or on a waitlist? Affects the urgency of the prod-config switch.
5. **Do edge-function logs currently ship to Sentry**, or only application errors? Determines the observability gap.
6. **Is there a staging Supabase project**, or is dev == prod right now?
7. **Is PITR enabled** on the Supabase project? If not, turn it on today — it's a few dollars per month of insurance.

---

## 8. What I'd revisit as the system grows

- **At ~5K users:** add an Inngest-style durable workflow for `coaching-agent` so a 30-second LLM call doesn't block an Edge Fn slot. Begin tracking per-function p95 latency.
- **At ~10K users:** productionize the ML service. By then the 30-users × 60-days data threshold will be met, and you'll have real feedback loops for `fitness-predictor` and `injury-early-warning`. Move off the local iOS heuristic.
- **At ~10K users:** consider Supabase read replicas if any dashboard query dominates.
- **At any size, if you add teams/coaches as a real persona:** the `coach ↔ athlete` RLS is already in place (March 2026 migration); what's missing is a coach-facing UX surface. The data model won't need changes.
- **If health-data regulation becomes a concern** (HIPAA, GDPR health categories): the single biggest impact is data residency. Supabase region choice is a one-way door, so validate before scaling internationally.

---

*End of document.*
