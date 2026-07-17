# Security & Failure-Point Review — 1000-Person Beta

**Date:** 2026-07-01
**Scope:** iOS app (`RunningLog/`), backend (`supabase/`), web (`web/`), ML service (`ml-service/`)
**Audience:** solo founder, non-engineer, preparing to open a 1000-person beta

---

## How to read this

You don't need to fix everything before launch. This report is ranked by
what can actually hurt you in a beta: **leaking a user's private data**,
**an unbounded bill**, and **things silently breaking for everyone**. The
first five items are the ones to clear before you send the invites. The
rest can wait or be watched.

The good news first: the backend has clearly been through real security
work. Auth is enforced correctly in most places, the coach portal is
locked down, the ML service is well-built, no secrets are committed to
git, and RLS (the database's per-user access rules) is on for every
table. The problems below are specific gaps, not a systemic mess.

Severity key: **Critical** = private data exposed or a launch-blocker ·
**High** = fix before or right at launch · **Medium** = fix during beta ·
**Low** = hygiene / later.

---

## The launch checklist (do these five first)

| # | Severity | What | Why it matters for 1000 users |
|---|---|---|---|
| 1 | Critical | Voice recordings are in a **public** storage bucket | Anyone with a link can download any user's voice memos — health data — with no login |
| 2 | High | Rate limiting turns **off silently** if one config var is missing | Your Gemini/LLM bill becomes unbounded; a single user (or bug) can run it up |
| 3 | High | A server-grade **Vital API key ships inside the iOS app** | Extractable from any install; anyone can hit Vital as you |
| 4 | High | `compute-workout-features` has **no auth check** | Any logged-in user can read and overwrite another user's workout data |
| 5 | High | Everyone defaults to **UTC**, so 1000 users get their Daily Read at the same instant | Simultaneous burst of ~1000 LLM calls + US users get "morning" notes at 1am |

---

## Critical

### C1 — Voice memos live in a public bucket (private health data exposed)

The `training-memos` storage bucket was created `public = true`
(`supabase/migrations/20260126_storage_policies.sql:2-4`) and **no later
migration reverts it** (verified — there is no `public = false` anywhere
in `supabase/migrations/`). Audio is served through the public URL path
(`upload-voice-memo/index.ts` returns `getPublicUrl`, and iOS reads it via
`getPublicURL` in `Workouts/VoiceLogViewModel.swift`).

A public bucket serves files over `/storage/v1/object/public/...`, which
**bypasses the per-user access rules entirely.** Anyone who obtains or
guesses a memo URL — and those URLs get stored in the database, could show
up in logs, error reports, or coach screens — can download any athlete's
raw voice recordings forever, no login required. File paths start with the
user's ID, so knowing a user narrows the guessing.

There's a second, related problem the codebase already knows about: the
"anyone can overwrite or delete any memo" write policies were never
scoped. The repo's own migration
`20260609233540_drop_public_storage_list_policies.sql` (lines 17-22) says
so in a comment and defers the fix — it's still open.

**Fix:** flip the bucket to private (`public = false`), switch iOS/web to
short-lived **signed URLs** (`createSignedUrl`), and ship the owner-scoped
UPDATE/DELETE policies. The read policies are already correctly
owner-scoped, so they'll start being enforced the moment the bucket is
private. This is the single most important item in this document.

---

## High

### H1 — Rate limiting fails *open* (unbounded LLM cost)

Rate limiting depends on Upstash Redis being configured. If the
`UPSTASH_REDIS_URL` / `_TOKEN` environment variables aren't set on your
production edge functions, `_shared/rateLimit.ts` (around lines 175-177,
30-37) **silently disables all rate limiting and allows every request.**
The circuit breaker also fails open after a few Redis errors.

Every LLM path — post-run analysis (fires once *per synced workout*),
Daily Read, memo transcription, plan parsing, reschedule — is then
uncapped per user action. A new user's first HealthKit sync can trigger
~30 back-to-back Gemini calls; multiply by 1000 signups in a week and
that's your whole model bill, with no ceiling and no alert.

**Fix before launch:** (1) confirm the Upstash vars are actually set in
prod; (2) add a hard monthly spend cap — the helper `enforceMonthlyCap`
already exists in `rateLimit.ts`; (3) make the "no Redis configured" path
fail *loud* (log an error) instead of silently allowing everything.

### H2 — Vital API secret key ships inside the iOS app

`RunningLog/Secrets.xcconfig` holds `VITAL_API_KEY = sk_us_...`, which
gets injected into `Info.plist` and sent as a header at runtime
(`Health/VitalManager.swift`). It's gitignored, but it's baked into every
build — a server-grade `sk_` key is trivially extractable from any
installed app. (It's currently a *sandbox* key, which limits the blast
radius today, but the pattern is wrong for production.) The single shared
`VITAL_USER_ID` also means every install reads the same Vital account.

**Fix:** move all Vital calls behind an edge function so the `sk_` key
never leaves your server; rotate the exposed key; give each athlete their
own Vital user. The Supabase URL + anon key in that same file are fine to
ship — those are meant to be public.

### H3 — `compute-workout-features` has no auth (cross-user read + write)

`supabase/functions/compute-workout-features/index.ts` (verified: lines
~322-343) reads `user_id` straight from the request body with **no auth
check** — no JWT verification, no service-role gate — and it's not listed
in `config.toml`. With just the anon key and any `user_id`, a caller can
read another athlete's full training history and **overwrite** their
`workout_type` and `workout_notes`. Its sibling function
`correct-workout-structure` does this correctly; this one was missed.

**Fix:** add one line at the top —
`requireAuthOrServiceRole(req, body.user_id, corsHeaders)` — matching the
pattern already used elsewhere.

### H4 — Everyone defaults to UTC (Daily Read burst + wrong-time notes)

There's no code anywhere that writes `athlete_settings.timezone` (a known
open item in your own notes), so every athlete is treated as UTC. The
Daily Read cron (`20260615220000_daily_coaching_reads_cron.sql`) fires for
athletes whose *local* hour is 6am — but since all are UTC, **all ~1000
fire on the same tick**, each triggering a Gemini call that (being
service-role) skips the rate limits. US users also get their "morning"
read at 10pm–2am local.

**Fix:** ship a timezone writer (capture it from the device on iOS), or as
a quick interim, jitter the dispatch across the hour so 1000 calls don't
land simultaneously.

### H5 — Check-in voice upload is likely broken for everyone

`Workouts/VoiceLogViewModel.swift` (`uploadCheckIn`, ~lines 216-224)
uploads directly to the storage bucket via the client SDK — the exact path
documented as failing system-wide since 2026-06-02. Voice memos were moved
to the `upload-voice-memo` edge function; check-ins were not. This is a
functional bug, not a security one, but it means a feature is probably
dead in the current build.

**Fix:** route `uploadCheckIn` through the same `uploadVoiceMemoAudio()`
edge-function path the memos use.

---

## Medium

### M1 — `vital-stream` web route doesn't check workout ownership (IDOR)

`web/src/app/api/vital-stream/route.ts` authenticates the user but never
verifies the requested `workoutId` belongs to them, and
`web/src/lib/vital.ts` fetches against a single global `VITAL_USER_ID`. An
authenticated user could enumerate workout IDs and pull another user's
stream/GPS/heart-rate data. Narrow, but real.

**Fix:** before calling Vital, look up the workout scoped to
`.eq("user_id", user.id)` and 404 if it isn't theirs; make the Vital user
per-athlete.

### M2 — Failed background jobs are silent; crashed batches get stranded

The outbox/drain system (`drain-coachable-moment-jobs`) is well-designed —
retries, backoff, coalescing — but two gaps matter at scale: jobs that
exhaust their retries sit as `status='failed'` with **no alert** (invisible
to a solo founder), and there's no recovery for jobs stranded
`in_progress` by a worker crash/timeout (the code comment admits this).
Under load this *will* happen.

**Fix:** add a scheduled "stale in_progress" sweep and a weekly "any failed
jobs?" alert query so you find out without watching the DB.

### M3 — LLM spend alert is a notification, not a cap

`20260609233529_daily_llm_spend_alert.sql` sends a daily Slack trend — it
does not stop spending. Pair it with the hard cap from H1.

### M4 — Weather enrichment quietly queries a table that doesn't exist

`post-run-reconciliation` and `reconcile-log` still read the removed
`user_profiles` table for home lat/lon; the error is swallowed, so weather
enrichment silently no-ops for workouts without GPS. Repoint these to
`athlete_settings`.

### M5 — Live secrets sitting in plaintext on disk (not committed)

`supabase/functions/.env.local`, `ml-service/.env`, `web/.env.local`, and
`RunningLog/Secrets.xcconfig` contain real-format Gemini, Vital, and
Supabase **service-role** keys. All verified gitignored and never
committed — good. But they're live credentials in plaintext; if the repo
folder is ever backed up to the cloud, synced, or shared with a
contractor, they leak. Your own `web/.env.example` already has a TODO to
rotate the anon + Vital keys before launch.

**Fix:** rotate these before beta as hygiene; never include them in any
copy of the repo you share.

### M6 — No size cap on voice-memo uploads

`upload-voice-memo` accepts unbounded base64 audio and buffers the whole
thing in memory. A large upload can hit edge limits or be used to run up
cost. Add a max payload check.

---

## Low / informational

- **iOS token storage is correct** — sessions are in the Keychain, not
  UserDefaults. Optional hardening: use the
  `...ThisDeviceOnly` accessibility class.
- **~46 `print()` statements remain** in the iOS app, some printing user
  UUIDs and pace/zone debug data (none dump raw health streams). These are
  visible in device consoles — sweep them to `os.Logger` with privacy
  annotations before beta.
- **`blog_posts` lets any authenticated user author a post** — low impact
  for a running app, but if the blog is customer-visible it's a
  defacement vector. Gate authoring to an admin role.
- **No SQL injection found.** Edge functions use the parameterized query
  builder throughout.
- **`athlete-state.ts` per-workout cost is acceptable** at 1000 users —
  queries are parallel, window-bounded, and indexed, with a 60-min cache.
  The thing to watch is the per-workout post-run-analysis loop (governed
  by H1's rate limits).
- **The 2-year HealthKit back-fill isn't built yet.** When you build it,
  design it to *skip* post-run analysis and per-workout stream fetches for
  historical workouts, or it'll go quadratic.

---

## What's already done right (so you don't second-guess it)

- Coach portal auth: middleware redirects unauthenticated users, and every
  coach page re-checks the session and the coach→athlete relationship. No
  coach-to-coach data leakage found.
- The legacy `/coach` route is fully removed and redirects to
  `/coach-portal`.
- The ML service is well-hardened: JWT on every endpoint, per-user
  ownership checks, non-wildcard CORS, no debug mode, pinned dependencies,
  runs as non-root.
- Service-role keys are never shipped to any client bundle.
- CORS fails closed in production; the shared auth helper does
  constant-time comparison and enforces that the body's `user_id` matches
  the caller's token.
- `coachable_moments` correctly has no client insert policy (service-role
  only), per your own hard rule.

---

## Suggested sequence

**This week (before invites):** C1 → H1 → H3 → H2 → H4. C1 and H3 are each
roughly a one-file change; H1 is a config check plus a cap; H2 and H4 are
larger but launch-relevant.

**During the beta:** H5, M1, M2, M4, then the rest of the Medium items.

**Ongoing hygiene:** M5 key rotation, the `print()` sweep, and the Low
items.

You built the beta to learn from real users — this list is about making
sure a data leak or a runaway bill isn't one of the lessons.
