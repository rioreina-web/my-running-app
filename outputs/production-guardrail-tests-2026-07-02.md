# Production guardrail tests — what they are and how to use them

**Date:** 2026-07-02
**Test file:** `supabase/functions/_shared/production-guardrails.contract.test.ts`
**Companion to:** `outputs/beta-security-and-failure-review-2026-07-01.md`

## What this is

Eleven automated tests that watch the specific failure points from the
July 1 security & failure review. They run with the rest of your test
suite — locally and in CI on every pull request — so none of those
problems can quietly come back, and no *new* code can reintroduce the
same class of bug.

The tests don't fix the bugs. They do three things:

1. **Block regressions.** A new edge function without an auth check, a new
   migration that makes a storage bucket public, or new code querying the
   dead `user_profiles` table fails CI immediately.
2. **Lock in fixes.** The rate limiter now fails *closed* (denies requests
   when Redis is missing instead of silently allowing everything). Three
   tests pin that behavior so a future refactor can't undo it.
3. **Keep the punch list honest.** The known-broken items live in the test
   file as `KNOWN_*` lists. The moment you fix one, the matching
   "stale exemption" test fails with a message telling you to delete the
   entry. The list can only shrink.

## How to run them

From the repo root:

```
cd supabase/functions
deno test --allow-all _shared/production-guardrails.contract.test.ts
```

Or just run the whole suite (`deno test --allow-all` in that folder) —
CI already does this on every PR via `.github/workflows/ci.yml`, so no CI
change is needed.

## What each test watches (mapped to the review)

| Review item | Test | What it stops |
|---|---|---|
| C1 | No unexpected public bucket | A migration ever making a user-data bucket public again (voice memos = health data) |
| H1 | Rate limiter fails closed ×3 | Missing Redis config silently disabling rate limits → unbounded LLM bill |
| H3 | Auth gate on every function | New edge functions shipping without a per-user auth check |
| H4 | Timezone writer exists | Shipping the beta with every athlete stuck on UTC |
| H5 | Check-in upload path | The check-in feature staying wired to the dead direct-upload path |
| M4 | No `user_profiles` queries | New code querying a table that doesn't exist (silent feature no-ops) |

## The current punch list (things still broken, pinned in the test file)

- **`training-memos` and `plan-attachments` buckets are public** — fix
  first (review item C1). When a migration flips them private, the test
  will say so.
- **15 edge functions have no shared auth gate**, including
  `compute-workout-features` (the cross-user read/write one, H3). Each
  needs one line: `requireAuthOrServiceRole(req, body.user_id, corsHeaders)`.
- **4 files still query `user_profiles`** — repoint to `athlete_settings`.
- **`uploadCheckIn` (iOS) still uses the broken direct upload** — route it
  through `uploadVoiceMemoAudio()` like memos, then flip
  `CHECKIN_UPLOAD_STILL_DIRECT` to `false` in the test.
- **Nothing writes `athlete_settings.timezone`** — when iOS captures the
  device timezone, flip `TIMEZONE_WRITER_STILL_MISSING` to `false`.

## Two pre-existing test failures you should know about

Running the full suite today shows two failures that existed **before**
these guardrails were added:

1. `rateLimit.contract.test.ts` — `correct-workout-structure` and
   `ingest-manual-workout` call an LLM with **no rate limiting**. This is
   a live cost risk (same family as H1). Wire `enforceFeatureRateLimit`
   into both, or document an exemption in that test.
2. `builders/buildLoadMetrics.test.ts` — a hard-session classification
   test is failing; likely a logic regression worth a look.

## The honest limits of these tests

They're tripwires, not proof of safety. They check that the code *has*
the right guards; they can't prove the guards work end-to-end in prod
(e.g. whether the Upstash env vars are actually set on your deployed
functions — check that in the Supabase dashboard). And they don't fix
anything: the launch checklist from the July 1 review still stands
(C1 → H1 → H3 → H2 → H4 before invites).
