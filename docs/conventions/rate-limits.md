# Rate limits — conventions

Where per-user rate limits live, what the numbers are, and how to add one
to a new edge function.

## Architecture

Two enforcement layers:

| Layer | Lives in | Key | Purpose |
|---|---|---|---|
| Web API routes (Next.js) | `web/src/lib/rate-limit.ts` + pinned per route | `${user.id}:${tag}` | Caps per-user requests from the browser to api routes that proxy edge functions. See `web/tests/rate-limit.contract.test.mjs`. |
| Edge functions (Deno / Supabase) | `supabase/functions/_shared/rateLimit.ts` | `ratelimit:${feature}:${userId}:${YYYY-MM-DD}` (Upstash Redis) | Caps per-user LLM calls regardless of how the function is reached (iOS direct, web proxy, ml-service). |

The two layers stack. A browser-originated coach chat hits the web rate
limit first (`coach: 20/min`); the request that survives also hits the
edge rate limit (`coaching: 5/day free, 25/day pro`). iOS skips the web
layer and hits the edge directly.

The third layer above both is the **Google Cloud billing cap** on the
Gemini project (W1.1, `docs/deploy/llm-cost-controls.md`). That's the
unconditional ceiling for total spend.

## Edge-function rate limits — per-feature daily caps

Source of truth: `FEATURE_LIMITS` in `supabase/functions/_shared/rateLimit.ts`.

| Feature bucket | Free | Pro | Unlimited | Used by |
|---|---:|---:|---:|---|
| `coaching` | 5 | 25 | 100 | `coaching-agent` |
| `predictor` | 10 | 25 | 100 | `fitness-predictor` |
| `analysis` | 10 | 25 | 100 | `training-analysis` |
| `parse` | 10 | 25 | 100 | `parse-training-plan`, `parse-training-week`, `parse-workout-structure` |
| `injury_analysis` | 5 | 25 | 100 | `injury-analysis`, `injury-early-warning` |
| `plan_builder` | 3 | 10 | 50 | `generate-training-plan` |
| `race` | 10 | 25 | 100 | `race-intel`, `race-readiness` |
| `weekly_review` | 5 | 25 | 100 | `weekly-coaching-report` (`weekly-plan-review` cut 2026-06-10) |
| `post_run` | 20 | 50 | 200 | `post-run-analysis` |
| `voice_memo` | 20 | 50 | 200 | `process-training-memo` |
| `daily_read` | 5 | 25 | 100 | `coaching-daily-read` (manual taps; cron bypasses via service role) |

> `transcribe` bucket + function removed 2026-06-10 — zero callers
> (`process-training-memo` owns transcription). W2.3-follow-up auth
> audit landed, so the "(reserved …)" markers above are now active.
| `reschedule` | 10 | 25 | 100 | `reschedule-plan` |
| `workout_insight` | 20 | 50 | 200 | `generate-workout-insight` (non-service-role path) |
| `check_in` | 10 | 25 | 100 | (reserved for `process-check-in` after auth audit) |

**Pinning principles:**

- User-typed paste flows (`parse`) cap low — wrong paste shouldn't burn the day's budget.
- Conversational chat (`coaching`) is the highest-cost surface; free tier is tight, pro unlocks meaningful use.
- Reads / cheap LLM passes (`predictor`, `race`, `post_run`, `reschedule`) are more generous because users hit them passively.
- Heavy multi-section analyses (`analysis`, `weekly_review`, `plan_builder`) sit in the middle.

## How to add rate limiting to a new edge function

1. Import the helper:

   ```ts
   import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
   ```

2. After the auth check, before any LLM call or expensive work:

   ```ts
   const rlBlocked = await enforceFeatureRateLimit(userId, "your_feature", corsHeaders);
   if (rlBlocked) return rlBlocked;
   ```

   If the function accepts both service-role and user JWT (e.g. mixed-mode triggers + user retries):

   ```ts
   const rlBlocked = await enforceFeatureRateLimit(
     callerUserId,
     "your_feature",
     corsHeaders,
     { isServiceRole },
   );
   if (rlBlocked) return rlBlocked;
   ```

3. Pin the (function, feature) pair in
   `supabase/functions/_shared/rateLimit.contract.test.ts` →
   `LLM_FUNCTIONS_RATE_LIMITED`. CI will then enforce the wiring.

4. If the feature is new, also add it to `FEATURE_LIMITS` in
   `_shared/rateLimit.ts` with `free / pro / unlimited` caps and to
   this doc's table above.

## Helper behavior

`enforceFeatureRateLimit(userId, feature, corsHeaders, opts?)` returns:

- `null` — allowed, proceed.
- `Response` — blocked. The caller should `return` it immediately.

Three short-circuit paths that return `null` (allowed):

1. `opts.isServiceRole === true` — service-role callers bypass user-keyed
   limits. The auth check is the gate for those callers.
2. `isRateLimitEnabled() === false` — Redis env vars not configured (local
   dev). Permissive fallback so `supabase functions serve` works.
3. The user is under their daily cap — normal accept path.

A blocked 429 response includes the standard fields plus a `Retry-After`
header (per RFC 9110) computed to midnight UTC, so iOS / web clients
can show a precise "try again at 12:00 UTC" message.

## What's NOT rate-limited yet

Seven LLM-calling functions accept `user_id` from the request body
**without** a `getAuthenticatedUser` gate. Adding a rate limit without
fixing auth would be cosmetic — anyone could forge a `user_id` and
burn another user's daily quota.

Tracked in `AUTH_PATTERN_AUDIT_PENDING` in
`supabase/functions/_shared/rateLimit.contract.test.ts`:

- `process-check-in` — voice processing trigger fires it
- `post-run-analysis` — training_logs trigger
- `race-intel` — iOS GoalsView calls it
- `race-readiness` — iOS AIInsightsService calls it
- `block-review` — iOS AIInsightsService calls it
- `injury-early-warning` — chained from process-training-memo
- `process-training-memo` — voice-log trigger

These need a proper auth audit before getting per-user rate limits.
Tracked as `W2.3-follow-up` in `TASKS.md`. Until then, the Cloud-billing
cap from W1.1 is the only protection against pathological invocation
of these functions.

## Contract tests that protect this

| Test | Asserts |
|---|---|
| `supabase/functions/_shared/rateLimit.contract.test.ts` | every pinned function calls `enforceFeatureRateLimit` (or legacy `checkFeatureRateLimit`) with the right feature; FEATURE_LIMITS has every pinned feature; the deleted `form_check_analysis` entry is gone; no new LLM-calling function is silently unprotected |
| `web/tests/rate-limit.contract.test.mjs` | every protected web API route uses `enforceRateLimit` with the right tag + limit + window; the auth gate runs before rate-limit; rate-limit runs before any upstream fetch |

Both run in CI on every PR (W1.4).
