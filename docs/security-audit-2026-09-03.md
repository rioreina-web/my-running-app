# Security audit and production-readiness plan — 2026-09-03

**Scope.** Every surface in this repo — Postgres/RLS, the 70 edge functions,
the Next.js web app, the iOS app, the parked ML service, CI/CD, and secret
hygiene — audited from the `design/ds-sync` trunk, then **cross-checked
against the live Supabase project** (`aqdijapxmjqaetursrde`) with read-only
queries and by pulling the deployed source of 21 edge functions. Everything
below is stated against what is actually running, not against the repo's
history.

**Audience.** Rio (owner, non-engineer) first; whoever picks up the follow-up
work second. Section 1 is the part to read if you read nothing else.

---

## 1. Executive summary

**The app is in better shape than its repository says, and that is the
problem.** Three months of hardening — private storage buckets, strict
row-level security, account deletion, rate limits that fail closed — was
applied to production and to the `design/ds-sync` branch, while `main` and
the June-era docs still describe a vulnerable system. A fresh audit of `main`
re-finds bugs fixed in July. Worse, the Deploy workflow deploys *every* edge
function from the repo, and for the five busiest functions the repo is
**older than production**. Running it today would roll back live code.

What is genuinely open, in order of how much it matters:

| # | Finding | Severity | Status |
|---|---|---|---|
| 1 | The repo does not match production (prod is 8 migrations and ~5 function versions ahead; `main` is dead). Any deploy or audit from the repo is unsafe until reconciled. | **Critical (process)** | Operator action — §3.1 |
| 2 | `get-pace-zones`: anyone holding the public anon key can read any athlete's pace zones. Confirmed live in prod. | **High** | **Fixed in this PR**; deploy just this one function — §3.2 |
| 3 | Two unauthenticated debug endpoints (`env-probe`, `redis-probe`) are live in prod; `redis-probe` lets anyone hit Redis and can leak the Upstash hostname. | **High** | Operator action: delete both — §3.2 |
| 4 | `process-training-memo`: an athlete who owns a typed note can pass another athlete's storage path and have it transcribed into their own log. Confirmed live. | **High** | **Fixed in this PR**; one-line port to prod's newer source — §3.2 |
| 5 | `coaching-agent`: pre-auth database write on every request; a body flag skips the daily quota; conversation IDs not bound to the caller. | **Medium** | **Fixed in this PR**; port to prod's newer source — §3.2 |
| 6 | Vital (Junction) API key and one shared Vital user ID are shipped inside the iOS app bundle. | **High** | Operator action: revoke + proxy through the existing `vital-connect` edge function — §4.4 |
| 7 | Web: CSP nonce never reached Next.js (policy either blocked hydration or was ignored); `assign-plan` route used the service-role key where the edge function authorizes on the user. | **Medium** | **Fixed in this PR** |
| 8 | No branch protection on the trunk, no dependency/secret scanning, `next@16.1.6` has middleware-bypass advisories, ML service pins a `PyJWT` with seven advisories. | **Medium** | Partly fixed (Dependabot, CI permissions, ML bumps); rest is GitHub settings — §4.6 |
| 9 | Leaked-password protection off; 6-char passwords with no complexity rule; email send limit of 2/hour. | **Medium** | Supabase dashboard — §4.2 |
| 10 | Privacy policy and terms have 28 `[TODO]`s; no HealthKit third-party-sharing consent flow; nothing linked from the web. | **Launch blocker (App Store 5.1.3)** | §5 |

**What is confirmed solid in production** (so you can stop worrying about it):
every table has RLS enabled and strict owner-scoped policies; no
`auth.uid() IS NULL` fallback policies remain; `training-memos`,
`plan-attachments` and `avatars` buckets are private; the service-role key
is not in any client, any committed file, or git history; cron jobs read
secrets from Vault at run time; CORS fails closed; the shared auth helper
compares the service key in constant time; the web app never bundles a
secret; the iOS app keeps its session in the Keychain and has no ATS
exceptions; account deletion exists end-to-end in the trunk.

---

## 2. What changed in this PR

Branch `claude/app-security-audit-3cv8ki`, based on `design/ds-sync` (the
real trunk — see §3.1), not on `main`.

### Edge functions (`supabase/functions/`)

| File | Change | Safe to deploy from this branch? |
|---|---|---|
| `get-pace-zones/index.ts` | Replace "no user JWT ⇒ trust body `user_id`" with `requireAuthOrServiceRole`. Closes the live cross-user read. | **Yes** — branch and prod were byte-identical before this change. |
| `_shared/auth.ts` | Export `timingSafeEqual` so callers stop hand-rolling `===`. | Yes (identical to prod otherwise). |
| `_shared/cache.ts` | Semantic cache scoped per athlete (`user_id` in metadata, `topK: 5`, skip other users' hits). This is **prod's own file**, copied verbatim — the branch was behind. | Yes (it *is* prod). |
| `evaluate-coachable-moment/index.ts` | Constant-time service-key compare. | Yes, but note the branch also carries an undeployed `skip_cause` select — review before deploying. |
| `reconcile-log/index.ts` | Constant-time shared-secret compare. | Yes (branch has a test seam prod lacks; behaviour-equivalent). |
| `process-training-memo/index.ts` | Audio pointer read only from the owned row; the `?? record.audio_url` body fallback is gone. | **No.** Prod runs a newer 1224-line version (v5 prompt, gpt-4o-mini fallback). Port the one line to prod's source (prod line 392) — do not deploy the branch copy. |
| `coaching-agent/index.ts` | Remove the pre-auth `debug_coach_log` insert; `proactive` skips the quota only for service-role callers; bind `conversationId` to the caller before reading history or appending; generic 500 body. | **No.** Prod runs a newer version (pace-readback guard, timezone, degraded handling). Port these four hunks to prod's source. |
| `generate-training-plan/index.ts` | `conversations` rows inserted with `user_id`; reads/updates filtered by owner. | Branch carries undeployed cross-train work; deploy when that ships. |
| `post-run-reconciliation/index.ts` | `requireAuthOrServiceRole`; log fetch scoped to the user. | Not deployed in prod (dark by design). |

### Database

`supabase/migrations/20260903120000_revoke_definer_execute_and_pin_search_paths.sql`
— idempotent; skips objects that don't exist:

- `REVOKE EXECUTE ... FROM anon` on `current_coach_id()`.
- `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated` on twelve
  `SECURITY DEFINER` trigger functions the advisor flags.
- Pin `search_path = public, pg_temp` on eighteen functions with a
  role-mutable search path (advisor lint 0011).

Apply with `supabase db push` per hard rule #9. It clears 30 of the 32
security-advisor warnings; the remaining two are dashboard settings (§4.2).

### Web (`web/`)

- `src/middleware.ts` — the nonce and CSP are now set on the **request**
  headers (`NextResponse.next({ request: { headers } })`), which is how
  Next.js learns the nonce for its own inline scripts. Added
  `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`,
  `upgrade-insecure-requests`. `style-src` uses `'unsafe-inline'` instead of a
  nonce, because a nonce cannot cover `style=""` attributes (every chart emits
  them) and CSP ignores `'unsafe-inline'` once a nonce is present.
  **Verify in a browser after deploy**: no CSP violations in the console on
  `/dashboard`, `/coach-portal/plans`, and `/studio`.
- `src/app/api/assign-plan/route.ts` — forwards the coach's own session token
  (the `shift-day` pattern). The edge function authorizes on the JWT subject;
  the service-role bearer it used before has no subject, so every call was a
  401 — and had the function accepted the key, any signed-in user could have
  assigned plans to any athlete. Contract test updated.
- All 147 web tests pass; `tsc` clean.

### iOS (`RunningLog/`)

- `Services/Supabase.swift` — Keychain item is now
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so the refresh token
  does not migrate via iCloud Keychain or backups to another device.

### CI, dependencies, hygiene

- `.github/workflows/ci.yml`, `deploy.yml` — `permissions: contents: read`.
- `.github/dependabot.yml` — weekly grouped updates for npm, pip, and Actions.
- `ml-service/requirements.txt` — `PyJWT` 2.9.0 → 2.13.0 (seven advisories,
  on the auth path), `python-dotenv` → 1.2.2, `fastapi` → 0.116.1 with
  `starlette >= 0.47.2`. All 16 ML tests pass on the new pins.
- `.gitignore` — `*.pem`, `*.p8`, `*.p12`, `*.mobileprovision`,
  `signing_keys.json`, `supabase/.branches/`, `supabase/snippets/`.
- Deleted `supabase/snippets/Untitled query 356.sql` (a dashboard snippet
  with the well-known local demo service key; bypasses the migration ledger).

### Validation

Web: lint (warnings only, pre-existing), `tsc --noEmit`, 147 tests — green.
ML: 16 tests green on bumped pins. Edge functions: `deno lint` clean; **full
`deno check` could not run here** because the sandbox proxy blocks
`esm.sh` — CI's "Edge functions (Deno)" job is the gate. Migration: SQL
reviewed against the live catalog (every function signature matches
`pg_proc`); not executed.

---

## 3. Operator actions this week

### 3.1 Reconcile the repo with production before any deploy

Measured 2026-09-03:

| | repo `main` | `design/ds-sync` | production |
|---|---|---|---|
| migrations | 99 | 207 | 215 |
| edge functions | 36 | 70 | 60 (+2 debug) |
| last change | 2026-06-11 | 2026-08-30 | 2026-09-02 |

`main` has been dead since June; the nine open PRs target four different
bases. `design/ds-sync` is the de facto trunk and is ~3 days behind prod on
`process-training-memo`, `coaching-agent`, `trends-timeline`,
`parse-workout-structure`, `compute-workout-features`, and is missing prod
files (`trends-timeline/goalPace.ts`, `goalPaceGrid.ts`,
`_shared/pace-guard.ts`, `prompts/process-training-memo.v4/.v5`,
`session-story/`). Prod is missing eight branch-only edits (`delete-account`,
cross-train plan params, `evaluate-coachable-moment` skip-cause, …).

Do, in order:

1. `supabase functions download <slug>` for all 60 prod functions and
   `supabase db pull` from a machine with the CLI; commit as one
   "import production source 2026-09-03" PR onto `design/ds-sync` with no
   behaviour changes. (The `record-evals` gate is disabled, so imported
   prompts will not block CI.)
2. Make `design/ds-sync` the default branch on GitHub, or fast-forward `main`
   to it, and re-base the open PRs. One trunk.
3. Until 1 lands: **never run the Deploy workflow with "deploy all
   functions"**. Deploy single functions only after `diff`-ing against the
   downloaded prod copy.
4. Turn on the drift detector (`drift-detector.yml`) once the GitHub secrets
   exist so this cannot silently recur.

### 3.2 Close the live holes (30 minutes)

```bash
# 1. Delete the unauthenticated debug endpoints (they were "temporary" in June/July)
supabase functions delete env-probe   --project-ref aqdijapxmjqaetursrde
supabase functions delete redis-probe --project-ref aqdijapxmjqaetursrde

# 2. Deploy the one function whose branch copy equals prod + the fix
supabase functions deploy get-pace-zones --project-ref aqdijapxmjqaetursrde

# 3. Verify: anon key + someone else's user_id must now be 401
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "$SUPABASE_URL/functions/v1/get-pace-zones" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" -d '{"user_id":"00000000-0000-0000-0000-000000000000"}'
```

Then port two small edits into the **downloaded prod source** (not the
branch copy) and deploy those:

- `process-training-memo/index.ts` prod line 392: drop `?? record.audio_url`.
- `coaching-agent/index.ts`: delete the `debug_coach_log` "entry-point"
  insert (prod lines 566–580); `!proactive` → `!(proactive && auth.isServiceRole)`
  at line 640; add the `conversations` ownership check after the client is
  created; add `.eq("user_id", userId)` to the two `conversations.update`
  calls and the `conversation_messages` select.

Apply the migration: `supabase db push` from the merged SHA.

### 3.3 Supabase dashboard (15 minutes)

- Authentication → Password: enable **leaked-password protection**; minimum
  length 10; require letters + digits. (`config.toml` mirrors: 6 / none.)
- Authentication → Rate limits: `email_sent` is 2/hour in `config.toml` —
  confirm the hosted value is sane (30+/hour) or confirmation emails will be
  dropped under any real signup traffic.
- Authentication → URL configuration: remove any `localhost` redirect URLs.
- Storage → `content-videos`: fine public; add `allowed_mime_types`
  (`video/mp4`) so it can't host arbitrary files.

### 3.4 GitHub settings (15 minutes)

- Branch protection / ruleset on the trunk: require the four CI jobs, one
  review, no force-push. Require a reviewer on the `production` environment.
- Enable secret scanning + push protection.
- Add the six Actions secrets from `docs/deploy/secrets-inventory.md` so the
  drift detector, db-lint, and smoke tests actually run.

---

## 4. Findings by surface

Severity reflects exploitability against **production as of 2026-09-03**.
"Fixed" means in this PR; "Prod" means the fix must land in prod's source
or dashboard; "Follow-up" means a separate change.

### 4.1 Edge functions

| Sev | Finding | Status |
|---|---|---|
| High | `get-pace-zones` trusts body `user_id` when the token has no subject; anon key qualifies. | Fixed (deploy from branch) |
| High | `process-training-memo` body `audio_url` fallback → transcribe any object in `training-memos` into your own log. 97 legacy objects have guessable bare-filename paths. | Fixed; port to prod |
| High | `env-probe`, `redis-probe`: `verify_jwt=false`, no auth, live. | Prod: delete |
| Med | `coaching-agent` unauthenticated pre-auth write to `debug_coach_log`; logs 30 chars of `Authorization`. | Fixed; port to prod |
| Med | `coaching-agent` `proactive: true` from a user JWT skips the daily quota and monthly cap. Global spend brake still applied. | Fixed; port to prod |
| Med | `coaching-agent` / `generate-training-plan` `conversationId` not bound to caller (history injection into prompt; appending to another user's thread). Needs a UUID guess. | Fixed |
| Med | Cross-tenant semantic cache. | Already fixed in prod 2026-09-01; branch caught up |
| Med | `evaluate-coachable-moment`, `reconcile-log` compared secrets with `===`. | Fixed |
| Med | 23 functions return upstream error text (`err.message`, Strava bodies, Postgres constraint names) to clients. | Follow-up: swap for `internalErrorResponse`; `coaching-agent` done |
| Med | Unbounded client input into prompts: `reschedule-plan` (`plan`, `workouts[]`, `recentHistory[]`), `parse-training-plan` (`imageBase64` — `validateFileSize` exists and is never called), `block-review` (`weeks`), `race-intel` (`location`, `race_date`). | Follow-up: `validateLength`/`validateArrayLength`, cap base64 at 8 MB |
| Med | `process-check-in` auto-applies the model's `plan_action` to `scheduled_workouts` and inserts `injuries` from free-text `soreness_areas`. Conflicts with "AI advises, never acts" and the closed niggles vocabulary. | Follow-up: write `plan_adjustments` with `auto_applied:false`; map through `INJURY_KEYWORDS` |
| Med | `strava-test-pull` OAuth exchange has no `state` binding (login-CSRF); tokens plaintext in `strava_credentials` (RLS owner-only). | Follow-up |
| Low | `debug_coach_log` keeps a full second copy of every chat request and response with no retention. | Follow-up: drop the table or add a 30-day purge |
| Low | `compute-workout-features` prod adds an `isServiceRoleJWT()` claim check that trusts the gateway's signature verification. Fine only while `verify_jwt=true`; document the dependency. | Note |
| Low | `session-story` bundles a stale `_shared/auth.ts` (pre-`lacksSubjectClaim`). | Redeploy with the import |

### 4.2 Database (verified live)

| Sev | Finding | Status |
|---|---|---|
| — | All 75 tables RLS-enabled; no fallback policies; no anon grants; `coachable_moments` service-role insert only; `current_coach_id()` pinned and qualified. | Confirmed safe |
| Med | `current_coach_id()` + 12 definer trigger functions executable by `anon`/`authenticated` (advisor). | Fixed (migration) |
| Med | 18 functions with mutable `search_path`. | Fixed (migration) |
| Med | Leaked-password protection disabled. | Dashboard |
| Low | `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated` would make future RPCs opt-in. Recommended; changes the dev workflow, so decide deliberately. | Decision |
| Low | Six `_backup_*` tables and `training_logs_dedupe_backup` sit in `public` with RLS and no policies (deny-all). Harmless; drop when the dedupe work is closed. | Housekeeping |
| Low | `strava_credentials.refresh_token` is selectable by the owner via PostgREST; no client needs it. | Follow-up: column-level `REVOKE SELECT` |
| — | `docs/conventions/rls-checklist.md` still recommends the `OR auth.uid() IS NULL` fallback that caused the March–July holes. | Follow-up: delete that paragraph |

### 4.3 Web

| Sev | Finding | Status |
|---|---|---|
| High | `next@16.1.6`: three middleware-bypass advisories (the app puts all page auth in middleware), a CSP-nonce XSS, a Server Actions null-origin CSRF. `npm audit --omit=dev`: 1 critical / 21 high / 23 moderate. | Follow-up: `next@16.3.x`, `@sentry/nextjs@10.7x`, `sanity@5.3x`; then `npm audit --audit-level=high` in CI. Dependabot added. |
| Med | CSP nonce never delivered to Next. | Fixed |
| Med | `assign-plan` service-role misuse. | Fixed |
| Med | Any authenticated user can publish to the public `/blog` (`blog_posts` insert policy allows `status='published'`). DOMPurify blocks XSS; phishing/SEO spam is not blocked. | Follow-up: drop the client insert policy (blog is authored in Sanity Studio) |
| Med | Coach role is self-service (`coach_profiles` insert from the client). | Product decision: approval flag checked in `current_coach_id()` |
| Med | Web rate limiter fails **open** when Upstash env is missing (edge limiter fails closed). Vercel `UPSTASH_*` unverified. | Follow-up: throw at import in production |
| Low | `/api/*` and `/monitoring` redirect logged-out callers to `/login` (HTML) instead of 401; Sentry tunnel is blocked for visitors. | Follow-up |
| Low | `coach-portal/athletes*` pages `return null` for non-coaches instead of `redirect()`. | Follow-up |
| Low | Join codes from `Math.random`. | Follow-up: `crypto.getRandomValues` |
| — | No service-role client in the web app; secrets confined to `env.server.ts` (`server-only` + lint + contract test); HSTS, nosniff, frame-ancestors set; the one `dangerouslySetInnerHTML` is DOMPurify'd; no open-redirect surface. | Confirmed safe |

### 4.4 iOS

| Sev | Finding | Status |
|---|---|---|
| High | `VITAL_API_KEY` + one global `VITAL_USER_ID` in `Info.plist`, called directly from the device (`Health/VitalManager.swift`). Anyone with the IPA gets a key valid for the whole Vital account, and every install reads the same person's workouts. | Prod: revoke the key; route through the existing `vital-connect` / `vital_credentials` server path; delete `VitalManager` (HealthKit replaced it for v1) |
| Med | Keychain item accessible after first unlock on any device. | Fixed |
| Med | Privacy manifest exists as a **draft** (`PrivacyInfo.xcprivacy`, 2026-08-24). Its own open question — separate consent for sending HealthKit-derived values to AI providers (Guideline 5.1.3) — is unresolved. | §5 |
| Med | Sign-out leaves `athlete_profile_cache`, pace/goal data, the SwiftData upload queue, unsent `.m4a` recordings and exported FIT/CSV files on disk. Recordings rely on the default file protection. | Follow-up: wipe on sign-out; `.completeFileProtection` on recordings |
| Low | `VoiceLogViewModel` still stores a `getPublicURL` for a private bucket (server parses the path, so it works; playback via that URL cannot). | Follow-up: store the path, sign at playback |
| Low | `AnalysisModels.swift` hand-rolls a request with the anon key to a function that no longer exists (`training-analysis`). | Follow-up: delete |
| Low | Debug logging of user id, lat/lon, and assembled coach prompts in `print`/`os_log` without `#if DEBUG`. | Follow-up |
| Low | `Shannon.mov` (25 MB) and MediaPipe (`SwiftTasksVision`, unused) ship in the bundle. | Follow-up |
| — | Session in Keychain; no ATS exceptions; no URL schemes; Sign in with Apple nonce is SHA-256 of `SecRandomCopyBytes`; HealthKit read-only and minimal; Sentry strips email/name, no screenshots; upload path is `auth.uid()/…` and server-enforced; account deletion wired to `delete-account`. | Confirmed safe |

### 4.5 ML service (parked)

Not deployed; no caller in any client. Auth, ownership, input bounds, CORS,
non-root Docker are all correct. Dependency pins bumped in this PR. If the
Railway project still exists, **delete it** — it held the service-role key and
JWT secret. If ever un-parked: `docs_url=None` in production, generic auth
error strings, `max_request_body_size="never"` for Sentry, and note that
`injury_risk.py` emits prescriptive rest advice (hard rule #2) and
`predictor.py` returns point estimates (hard rule #7).

### 4.6 CI/CD and secrets

| Sev | Finding | Status |
|---|---|---|
| High | No branch protection; CI is advisory. | GitHub settings |
| Med | No Dependabot / audit / secret scanning. | Dependabot added; CI `npm audit`/`pip-audit` steps are a follow-up once the Next bump lands (they would be red today) |
| Med | Workflows lacked `permissions:`; Actions pinned to mutable tags. | Permissions fixed; SHA-pinning follow-up (Dependabot will track) |
| Med | Three migrations still read the service-role key from a DB-level GUC pattern in docs (`supabase/README.md`); live GUC is unset, Vault is in use. | Docs cleanup |
| Low | `record-evals.yml` interpolates `inputs.prompt` into a shell line. | Follow-up: pass via `env:` |
| Low | `SUPABASE_PROJECT_REF` is treated as a secret but is public in eight files; masking it garbles logs. Make it a repo variable. | Follow-up |
| — | No service-role key, API key, private key, or DB password anywhere in the tree or in git history. Only the public anon key was ever committed (February), now removed from HEAD. `.env`, `Secrets.xcconfig`, `.sentryclirc` never committed. No `pull_request_target`; deploy is manual behind the `production` environment. | Confirmed safe |

---

## 5. Launch blockers that are not code

1. **Legal.** `docs/legal/privacy-policy.md` (16 `[TODO]`s) and
   `terms-of-service.md` (12, including the arbitration clause marked
   "lawyer review essential"). Needed before App Store review and before the
   web signup is public. Must state explicitly that HealthKit data is never
   used for advertising or sold, that HealthKit-derived values (heart rate,
   pace, sleep) are sent to Gemini/Groq/OpenAI for coaching, where data is
   stored (Supabase, us-west-2), and the real retention periods. Add
   `/privacy` and `/terms` routes and link them from the landing page,
   login, and the iOS Settings link that already points at
   `postrundrip.com/privacy`.
2. **HealthKit → AI consent.** Apple 5.1.3 requires explicit user consent
   before HealthKit data goes to a third party. The `ai_health_consent`
   migration (2026-08-24) exists; confirm the iOS flow gates every LLM call
   on it.
3. **Supabase prod auth config** — `docs/deploy/h5-supabase-prod-config.md`
   (custom SMTP, confirmations, site URL) is still marked "not yet executed".
4. **Privacy manifest** — promote the draft to final and reconcile with the
   App Store Connect questionnaire.

---

## 6. Phased plan to production

| Phase | Work | Effort | Exit test |
|---|---|---|---|
| **0 · This week** | §3.1 reconcile repo ↔ prod; §3.2 delete probes, deploy `get-pace-zones`, port two edits; §3.3 dashboard; §3.4 GitHub. Merge this PR. | 1–2 days | Drift detector green; anon-key IDOR curl returns 401; advisor shows ≤ 2 warnings. |
| **1 · Next two weeks** | Web: bump Next/Sentry/Sanity, add `npm audit` + `pip-audit` to CI, fail-closed web limiter, blog insert policy, API 401s. Edge: error-body sweep, input caps, `process-check-in` no-auto-apply, Strava `state`. iOS: Vital removal, sign-out wipe, file protection, delete dead callers. | 1 week eng | CI green with audit steps enforced; no `err.message` in any client response. |
| **2 · Before beta invite** | Legal docs finalized and linked; HealthKit-AI consent verified; SMTP + confirmations on prod; privacy manifest final; TestFlight build with account deletion tested end-to-end. | 1 week + lawyer | A stranger can sign up, confirm email, record a memo, delete their account, and nothing of theirs remains in the DB or bucket. |
| **3 · Steady state** | Branch-per-PR preview environments; `ALTER DEFAULT PRIVILEGES` decision; coach approval flag; SHA-pin Actions; quarterly re-run of the advisor + this checklist. | ongoing | — |

---

## 7. How this audit was done

Five parallel reviews (database, edge functions, web, iOS, ML/CI/secrets)
against the repo, followed by live verification: `pg_policies`, `pg_class`,
`pg_proc`, `storage.buckets`, `cron.job`, view options, the Supabase security
advisor, the migration ledger, the deployed-function inventory, and the
deployed source of 21 functions diffed against `design/ds-sync`. Prior work
consulted: `SECURITY-CHANGES.md` (May), PR #5 (`claude/security-priorities-500-users-18s28k`,
August — its `get-pace-zones` fix is reproduced here; its repo/prod drift
memo is superseded by §3.1), `docs/deploy/secrets-inventory.md`,
`docs/ops-delivery-roadmap-2026-06-10.md`.
