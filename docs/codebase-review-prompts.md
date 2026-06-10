# Codebase deep-review prompts — 14-day coverage

Each day is a self-contained prompt you can paste into a fresh Claude
session. Each one is scoped to ~1-3 hours of review work and produces a
concrete artifact — a per-surface review doc you can keep.

The order is deliberate. Days 1-7 cover the **product-critical** systems
(coaching, voice, analysis, pace, plans, workouts, data model). Days 8-13
cover **infrastructure + breadth** (integrations, web pages, edge fns,
migrations, tests, ops). Day 14 is the synthesis.

Skip days that aren't your priority. Re-run any day after major changes.

**File output convention:** every day produces `docs/reviews/<dayN>-<topic>.md`. Same shape, easy to read across.

---

## How to use these

1. Open a fresh Claude session.
2. Copy the prompt for the day verbatim.
3. Paste — it includes everything Claude needs (no prior context).
4. Review the artifact when done. Save to repo.
5. Move on. Don't try to do two days in one session — context budget will hurt you.

Most prompts produce a markdown doc with: severity-ranked findings, what's strong, what's risky, recommended next moves. Same template every time so you can read 14 of them in an hour at the end.

---

## Day 1 — Coaching layer (the AI brain)

**Surface:** `RunningLog/Coaching/*` (10 files), `supabase/functions/coaching-agent/`, `supabase/functions/process-check-in/`, `supabase/functions/process-training-memo/`, `supabase/functions/coaching-feedback/`

**Why first:** the AI coach is the product's headline feature. If it's leaky, hallucinatory, or unsafe, nothing else matters.

```
You're auditing the AI coaching layer of a running-coaching app called
Post Run Drip. The brand promise is "coach-first, AI second" — the AI
should advise, not act, and never tell an athlete to push through pain.

Read in this order:
  1. RunningLog/RunningLog/Coaching/ — every file. Note what each does.
  2. supabase/functions/coaching-agent/ — the LLM brain. Read prompt
     construction, tool/function signatures, response parsing.
  3. supabase/functions/process-check-in/, process-training-memo/,
     coaching-feedback/ — the "how the AI hears the athlete" path.
  4. supabase/functions/_shared/coaching-* if any.

Specifically look for:
  - Safety guardrails: does the prompt prevent the AI from advising
    "push through pain", overriding rest days, or contradicting the
    coach's plan? Look for missing assertions.
  - Tool surface: what can the AI actually do (read-only? write?)
    and is there an audit trail?
  - PII handling: what athlete data goes to the LLM provider? Is
    identifying info stripped? Look at docs/legal/privacy-policy.md
    section 4 for the claim and verify the code matches.
  - Prompt injection: an athlete writing "ignore previous instructions"
    in a voice memo or chat message. What stops it?
  - Cost / abuse limits: per-user rate limiting? cost cap?
  - Brand voice: read 2-3 actual prompt strings. Do they match the
    "warm, direct, measured, no hype" voice the brand calls for?

Save your review to docs/reviews/day1-coaching-layer.md with these sections:
  ## Summary (one paragraph)
  ## Top critical findings (🔴) — file + line refs
  ## Serious findings (🟡)
  ## Minor findings (🟢)
  ## What's strong
  ## Recommended next moves (ranked by ROI, top 3)

Be honest. Don't pad the "what's strong" section to be polite.
```

---

## Day 2 — Voice memo + transcription pipeline

**Surface:** voice-memo capture in iOS (`Coaching/`, `Workouts/` for log entries), `supabase/functions/transcribe/`, `supabase/functions/process-training-memo/`, `Storage` policies for audio files, retention claims in privacy policy.

```
You're auditing the voice memo pipeline of Post Run Drip — the path
from athlete recording audio to transcription to coaching context.

Read in this order:
  1. Find every iOS file that records audio. Grep for AVAudioRecorder
     and AVAudioSession.
  2. supabase/functions/transcribe/ — what STT service is used? Cost?
     Latency target?
  3. supabase/functions/process-training-memo/ — how transcripts feed
     into structured signals (mood, injury, workout).
  4. Any Storage RLS policies for audio file access.
  5. docs/legal/privacy-policy.md §6 (Voice memos and AI coaching).

Specifically look for:
  - Retention: privacy policy says "[TODO: 90 days]". Find the actual
    cleanup mechanism. Is there a cron / scheduled deletion? If not,
    audio is stored forever — that's a privacy bug.
  - Storage access: can user A access user B's audio via direct URL?
    Test by reading the bucket's RLS policies.
  - Failure modes: what happens when transcription fails? Is the
    audio orphaned? Does the user see a useful error?
  - Sentiment / injury extraction: how is structured signal extracted
    from free-form transcripts? Is there a confidence threshold?
    What happens to false positives ("my IT band feels like a million
    bucks today" — does it mistakenly flag injury)?
  - Athlete deletion: when an athlete deletes their account, do their
    audio files get deleted? Storage objects don't cascade
    automatically.
  - Cost per memo: estimate the all-in cost (transcription + downstream
    LLM analysis) per voice memo. Sustainable at 1000 daily users?

Output to docs/reviews/day2-voice-pipeline.md. Same template as day 1.
Pay special attention to retention + storage RLS — those are
GDPR/CCPA-relevant.
```

---

## Day 3 — Analysis layer (fitness, injury, biomechanics)

**Surface:** `RunningLog/Analysis/*` (29 files — the largest iOS dir), `supabase/functions/biomechanics-analysis/`, `injury-analysis/`, `injury-early-warning/`, `form-check-analysis/`, `fitness-predictor/`, `compute-workout-features/`, `training-analysis/`, `weekly-coaching-report/`, `weekly-plan-review/`.

```
You're auditing the analysis layer of Post Run Drip. This is the
"intelligence" that turns raw training data into signals — fitness
predictions, injury warnings, biomechanics, weekly reports.

Read in this order:
  1. Inventory RunningLog/RunningLog/Analysis/ — list all 29 files,
     note what each does in one sentence.
  2. Pick the 5 most consequential ones (likely: FitnessPredictor*,
     WorkoutHistoryAnalyzer, biomechanics-related). Read in depth.
  3. supabase/functions/biomechanics-analysis, injury-*, form-check,
     fitness-predictor, compute-workout-features, training-analysis,
     weekly-coaching-report, weekly-plan-review. List each in a
     sentence; read the 3 most consequential in depth.

Specifically look for:
  - Statistical correctness: ACWR formula, training load math,
    cadence/stride length calculations. Is the math right? Cite
    sources where possible.
  - False-positive risk on injury detection: an injury warning
    that fires too easily breaks athlete trust. What's the threshold?
    Has it been validated against real data?
  - Data dependencies: which features assume HealthKit, which assume
    Strava, which require Vital? What's the graceful-degradation
    story?
  - Cross-platform consistency: if the same metric is computed on iOS
    AND on the server, are they identical? Drift between client and
    server "your fitness index" values is a known reputation risk.
  - Privacy: the LLM-driven analysis (weekly-coaching-report) sends
    what data to the model? Look at the prompt construction.
  - Output stability: if I re-run weekly-coaching-report against the
    same inputs, do I get the same output? Caching / temperature
    control?

Output to docs/reviews/day3-analysis-layer.md. Same template.
For injury detection specifically: write a "false positive scenario"
section with 3 athlete profiles where the system might over-fire.
```

---

## Day 4 — Pace system end-to-end

**Surface:** `RunningLog/Workouts/PaceCalculator.swift`, `RunningLog/Models/PaceModels.swift`, `supabase/functions/_shared/paces.ts`, `web/src/components/coach/workout-helpers.ts`, `supabase/functions/_shared/resolve-pace.ts`, `supabase/functions/recompute-plan-paces/`, `supabase/functions/build-pace-profile/`, `web/src/components/coach/pace-reference-editor.tsx`, plus any callers of `derivePaceTableFromGoal`.

**Note:** This area was partially refactored on 2026-04-24 (see `docs/pace-system-rework.md`). Phase A is complete. Phases B-E are in flight.

```
You're auditing the pace system of Post Run Drip — how race pace
goals turn into per-zone training paces, and how those flow through
plan generation and display.

Read in this order:
  1. docs/pace-system-rework.md — context for the in-flight rework.
  2. RunningLog/RunningLog/Workouts/PaceCalculator.swift — iOS canonical.
  3. RunningLog/RunningLog/Models/PaceModels.swift — NamedPace + zones.
  4. supabase/functions/_shared/paces.ts — server canonical.
  5. web/src/components/coach/workout-helpers.ts (look for derivePaceTableFromGoal).
  6. supabase/functions/_shared/resolve-pace.ts — step-level resolver.
  7. supabase/functions/recompute-plan-paces — refresh path.
  8. supabase/functions/build-pace-profile — fitness snapshot → profile.
  9. web/src/components/coach/pace-reference-editor.tsx — coach's anchor editor.

Specifically look for:
  - Source-of-truth audit: pace-system-rework.md §1 lists 8 sources.
    Are any deprecated sources still being read by current code?
    Grep for: athlete_state.pace_zones, user_profiles.easy_pace_*.
  - iOS ↔ server math equivalence: take 5 reference race times
    (2:20 marathon, 3:00 marathon, 4:00 marathon, 1:25 half,
    18:00 5K). Compute the full 12-zone ladder using BOTH iOS
    PaceCalculator AND server _shared/paces.ts. Do they match
    within 1 second? Build a comparison table.
  - Threshold/HM collapse: VDOT-style systems treat them as one
    zone. Are all callers consistent?
  - Zone-name drift between iOS NamedPace and web PaceZone (the
    rework doc Phase D flag).
  - Missing readers: who calls paceTableFromProfile? Does it cover
    every place that needs paces?
  - Tolerance display: does iOS show ranges (e.g. 5:50–5:54 for
    tempo) and does it match the 1%/2%/5% spec from
    pace-system-rework.md?

Output to docs/reviews/day4-pace-system.md. Include the
5-reference-time comparison table as a deliverable.
```

---

## Day 5 — Plan generation, adaptation, and the loop

**Surface:** `supabase/functions/subscribe-to-plan/`, `adapt-plan/`, `reconcile-log/`, `reschedule-plan/`, `revert-plan-adjustment/`, `update-plan-goal/`, `recompute-plan-paces/`, `weekly-plan-rebalance` (cron), the `plan_adjustments` migration, the trigger functions `invalidate_athlete_state_on_training_log` and `claim_athlete_state_rebuild`.

```
You're auditing the heart of the adaptive training system in Post
Run Drip — the loop that adjusts plans based on what the athlete
actually does. The architecture is:

  athlete logs run → reconcile-log → adapts plan → plan_adjustments
                                  ↓
                            triggers Postgres → adapt-plan
                                  ↓
                       writes scheduled_workouts changes

Read in this order:
  1. supabase/migrations/*plan_adjustments*.sql — the ledger table.
  2. supabase/migrations/*invalidate_athlete_state*.sql — the trigger.
  3. supabase/migrations/*athlete_state_rebuild_claim*.sql — advisory locks.
  4. supabase/functions/reconcile-log/ — entry point.
  5. supabase/functions/adapt-plan/ — adjustment generator.
  6. supabase/functions/reschedule-plan/ — bigger restructures.
  7. supabase/functions/revert-plan-adjustment/ — undo path.
  8. supabase/functions/recompute-plan-paces/ — pace refresh.
  9. supabase/functions/update-plan-goal/ — goal change.
 10. supabase/functions/weekly-plan-rebalance (cron schedule).

Specifically look for:
  - Idempotency: if reconcile-log runs twice for the same training_log,
    does it produce duplicate adjustments?
  - Race conditions: athlete logs two runs in 30 seconds — can
    triggers + edge functions deadlock? The advisory lock pattern is
    designed for this; verify it's actually used everywhere.
  - Cascade safety: an adjustment that affects week N+1 — does it
    correctly cascade to week N+2 if needed?
  - Auto-apply vs propose: which adjustments auto-apply, which
    require athlete acknowledgment? Is the policy consistent?
  - Audit trail: every adjustment writes a plan_adjustments row.
    Does every adjustment-emitter actually do this, or are some
    silent?
  - Test coverage: which of these edge functions have tests?
    Which don't?
  - Rollback safety: revert-plan-adjustment — does it correctly undo?
    What if multiple adjustments stacked since the one being reverted?

Output to docs/reviews/day5-adaptive-loop.md. Diagram the
adjustment flow as a Mermaid sequence in the doc — useful for
future-you.
```

---

## Day 6 — Workout authoring (coach + AI builder + parser)

**Surface:** `web/src/components/coach/plan-builder-client.tsx`, `web/src/components/coach/workout-step-editor.tsx`, `web/src/components/coach/workout-template-form.tsx`, `web/src/components/coach/workout-helpers.ts`, `RunningLog/Workouts/WorkoutTemplateEditorView.swift`, `RunningLog/Coaching/WorkoutChatSheet.swift`, `RunningLog/Coaching/AIPlanChatSheet.swift`, `supabase/functions/parse-workout-shorthand/`, `supabase/functions/parse-workout-structure/`, `supabase/functions/parse-training-week/`, `supabase/functions/parse-training-plan/`, `supabase/functions/generate-training-plan/`.

**Note:** This area had a major fix on 2026-04-25 (the AI Workout Builder structured-step bug). See `docs/build-adaptive-plan-suspension.md` for context.

```
You're auditing the workout authoring stack of Post Run Drip — every
path that produces a structured workout (coach editor, AI chat
modifications, plan import, parser).

Read in this order:
  1. docs/build-adaptive-plan-suspension.md — the suspended path.
  2. web/src/components/coach/workout-step-editor.tsx — coach's editor.
  3. web/src/components/coach/workout-helpers.ts — pace ladder + types.
  4. web/src/components/coach/plan-builder-client.tsx — coach's plan
     wrapper.
  5. RunningLog/Workouts/WorkoutTemplateEditorView.swift — iOS editor.
  6. RunningLog/Coaching/WorkoutChatSheet.swift — single-workout AI chat.
  7. RunningLog/Coaching/AIPlanChatSheet.swift — full-plan AI chat.
  8. The parse-* family of edge functions.
  9. supabase/functions/generate-training-plan — workout-code-driven
     deterministic step builder.

Specifically look for:
  - Structured intervals: does every authoring path correctly emit
    `repeats` + `recovery` for interval workouts? Test with a
    "10x1km w/ 90s recovery" input through each path.
  - Pace zone consistency: does the editor's PaceZone enum match
    the parser's recognized zones, the iOS NamedPace enum, and the
    server's PaceZone type?
  - Description ↔ steps coherence: in the AI Workout Builder, is the
    description string ever generated independently from steps? If
    yes, when do they drift?
  - Parser coverage: parseIntervals — what input formats does it
    recognize? Build a test matrix of 20 real coach phrasings:
      "5x800 @ 5K"
      "6x800m @ 5K w/ 90s jog"
      "3x1mi at HM pace, 0.25mi rec"
      "10x400 with 200 jog"
      "2x3mi at 104% w/ .5mi float"
      "fartlek 8x3min on 2min off"
      ... etc
    Which fail and what does the fallback produce?
  - Schema versioning: workout_data has schema_version: "v3". What's
    the upgrade path? Is there code handling v1/v2?

Output to docs/reviews/day6-workout-authoring.md. Include the
20-input parser test matrix as a deliverable table.
```

---

## Day 7 — Athlete data model + RLS + tenant isolation

**Surface:** every `supabase/migrations/*.sql`, `RunningLog/Models/*` (16 files), `RunningLog/Auth/*` (2 files), `web/src/lib/supabase/`, RLS policies.

```
You're auditing the data model and tenant isolation of Post Run Drip.
The single biggest risk is athlete A seeing athlete B's data. The
codebase had a tenant-leak fix in early 2026 (HOTFIX-H.1) — verify
no regressions.

Read in this order:
  1. List every supabase/migrations/*.sql file. Note its purpose
     in one line.
  2. Read the 5 most consequential migrations (auth, RLS, plan_adjustments,
     athlete_state, scheduled_workouts).
  3. RunningLog/RunningLog/Models/ — every file. Note relationships
     between types.
  4. RunningLog/RunningLog/Auth/ — sign-in / token handling.
  5. web/src/lib/supabase/ — client setup, auth helpers.
  6. Search for "service_role" in edge functions — service-role usage
     bypasses RLS, so every use is a potential leak risk.

Specifically look for:
  - RLS coverage: every user-data table needs RLS. List tables
    without RLS or with permissive policies.
  - Service-role bypass: every edge function that uses service_role
    must do its own authorization (not delegate to RLS). Is each
    one doing this correctly?
  - Foreign key cascades: when a user is deleted, what cascades?
    Are there orphan tables that retain PII?
  - Coach-athlete access: a coach should see their athletes' data
    but only via the coach_athlete_relationships join. Verify this
    in the coach-portal queries.
  - Token leakage: are JWTs accidentally logged anywhere? Search
    for "authorization" in console.log calls.
  - Idempotency tokens: any place where the same request can be
    replayed (e.g., subscribing to a plan twice)?

Output to docs/reviews/day7-data-model-rls.md. Include a
"tables without RLS" list as a critical-findings table.
```

---

## Day 8 — Health integrations (HealthKit + Strava + Vital)

**Surface:** `RunningLog/Health/*`, `RunningLog/Services/*` (9 files), iOS HealthKit setup, Strava OAuth flow, Vital integration, `supabase/functions/strava-test-pull/`, any Vital webhook/stream paths.

```
You're auditing the third-party data integrations of Post Run Drip:
Apple HealthKit, Strava, and Vital. Each is a source of athlete
training data, and each has different failure modes.

Read in this order:
  1. RunningLog/RunningLog/Health/ — HealthKit setup.
  2. RunningLog/RunningLog/Services/ — sync layer.
  3. iOS Strava OAuth flow (likely in Services or Auth).
  4. Vital integration paths.
  5. supabase/functions/strava-test-pull/, vital-stream API route.

Specifically look for:
  - Permission scopes: HealthKit asks for X/Y/Z — is it asking for
    the minimum needed? (App Store reviewers flag over-asking.)
  - Token refresh: Strava + Vital tokens expire. Is there refresh
    logic? What happens when refresh fails?
  - Rate limits: Strava's API has rate limits. How is the app
    behaving? Do we cache?
  - Duplicate detection: athlete logs a run on Apple Watch, syncs
    via HealthKit, also has Strava connected. Does the run get
    written twice to training_logs?
  - Data freshness: when does the app pull fresh data? Is there
    a manual refresh? How long can stale data persist?
  - Error UI: when a sync fails, what does the athlete see?
  - Airplane / offline: does logging a workout offline + syncing
    later work?
  - Privacy disclosures: privacy-policy.md §3.2 lists these vendors.
    Is the actual data flow narrower than what the policy claims?
    (Wider = privacy bug.)

Output to docs/reviews/day8-health-integrations.md.
```

---

## Day 9 — Web app pages outside /plan

**Surface:** `web/src/app/(app)/{analysis,coach,coach-portal,dashboard,export,goals,injuries,library,log,pace-chart,predictor,settings}/` — every page I haven't touched. Also `web/src/app/(public)/blog/`, `web/src/app/studio/` (Sanity), `web/src/app/api/*`.

```
You're auditing the web app of Post Run Drip — every page and route
EXCEPT /plan and /coach-portal/plans (which were reviewed earlier).

Read in this order:
  1. List every directory under web/src/app/(app)/ — note what each
     route does in one sentence.
  2. List every API route under web/src/app/api/ — same.
  3. For each /(app)/{dir}/page.tsx — read it and note the data
     queries, complexity, who it's for.
  4. web/src/app/studio/ — Sanity CMS embed. Verify access control.
  5. web/src/app/(public)/ — anything public-facing.
  6. web/src/components/charts/, blog/, layout/ — supporting components.

Specifically look for:
  - Auth checks: every (app)/ route should require authentication.
    Verify each does (server-side check, not just middleware).
  - Loading + error states: does each page handle no-data /
    fetch-error gracefully?
  - Mobile responsiveness: I focused iOS on mobile. The web pages —
    are they usable on a phone or are they desktop-only?
  - Component reuse: is each page reinventing card / button / table,
    or pulling from web/src/components/ui/?
  - Sanity Studio access: the /studio route — who can access it?
    Is the access list locked down?
  - SEO + public surface: anything publicly indexable that
    shouldn't be?
  - Performance: any page making 5+ sequential queries that should
    be a single query?

Output to docs/reviews/day9-web-pages.md. Include a route-level
inventory as a table.
```

---

## Day 10 — Edge function inventory (the long tail)

**Surface:** every edge function in `supabase/functions/` NOT covered by days 1, 2, 3, 5, 6, 8 above. Likely list: `adaptive-workout`, `block-review`, `build-athlete-profile`, `build-pace-profile`, `fetch-workout-weather`, `ingest-documents`, `parse-workout-structure`, `post-run-analysis`, `post-run-reconciliation`, `process-check-in`, `race-intel`, `race-readiness`, `shift-day`, `transcribe`, `update-plan-goal`.

```
You're inventorying the edge function long-tail of Post Run Drip.
Days 1-9 covered the high-stakes ones. This day is breadth — touch
every remaining edge function so we have full coverage.

Read in this order:
  1. List every directory in supabase/functions/. Mark which are
     already covered in days 1-9 and which are new for this pass.
  2. For each new function, read 30 seconds: top-of-file comment,
     handler signature, what it returns. Note its purpose.
  3. Identify the 3 most consequential of the long-tail and read
     them in depth.

Specifically look for:
  - Orphan functions: any edge function that's never called from
    iOS or web? (Grep for the function name across the codebase.)
  - Cost outliers: any function that calls an LLM with no rate
    limit, no cache, no input bounds?
  - Auth pattern consistency: every function should use
    _shared/auth.ts. Find any that DIY their auth check.
  - Test coverage: which functions have tests? Which don't?
  - Schema evolution: any function using `pg-boss`, queues, or
    background jobs? Document them.

Output to docs/reviews/day10-edge-fn-inventory.md. Include a
table: function name | LOC | called by | tests? | cost class
(none / low / medium / high LLM spend).
```

---

## Day 11 — Migrations + DB schema integrity

**Surface:** every `supabase/migrations/*.sql` file (67 of them as of 2026-04-25). Plus the live schema if you can dump it.

```
You're auditing the Postgres schema and migration history of Post
Run Drip. 67 migrations have run on prod. Focus: schema integrity,
index coverage, missing constraints, deprecated columns.

Read in this order:
  1. Run `ls supabase/migrations/ | wc -l` to confirm count.
  2. List every migration. Note its purpose in one line.
  3. If you can: dump the live schema (psql \d on each table) and
     compare against the migration history.
  4. Identify the 10 most recent migrations and read each in full.

Specifically look for:
  - Missing indexes: every foreign key SHOULD have an index, every
    column used in a WHERE clause likely should. List tables likely
    missing them.
  - Missing UNIQUE constraints: any "should never duplicate" rule
    that's enforced in code instead of DB?
  - Deprecated columns still present: pace-system-rework.md flagged
    user_profiles.easy_pace_*, etc. Are they still in the schema?
    Are they being read?
  - RLS policy coverage: cross-check against day 7's findings.
  - Trigger graph: list every trigger and what it fires. Look for
    cycles or cascades that could lock-storm.
  - Migration discipline: any migration that reverses a previous one
    (forward-only convention is right, but reverses signal a flip-flop)?
  - JSONB schema versioning: workout_data has schema_version. Other
    JSONB columns — do they version too?

Output to docs/reviews/day11-schema-migrations.md. Include a
"missing indexes" table and a "deprecated-but-still-present
columns" table.
```

---

## Day 12 — Tests, observability, and ops

**Surface:** all `*.test.ts`, `*.test.swift`; logging in edge functions; Sentry / monitoring setup; `docs/deploy.md`; CI configs in `.github/`, `Vercel.json`, `supabase/config.toml`.

```
You're auditing the testing, observability, and deployment ops of
Post Run Drip. Code quality is high but the ops layer is the soft
underbelly.

Read in this order:
  1. find . -name "*.test.ts" -o -name "*.test.swift" — list every
     test file. Note what it covers.
  2. Edge functions — pick 5 random ones. What's their logging
     story? structured logs? errors to Sentry? just console?
  3. docs/deploy.md — the runbook.
  4. .github/ workflows — CI/CD, if any.
  5. supabase/config.toml — local vs prod config.
  6. iOS — XCTest, snapshot tests, build configs.

Specifically look for:
  - Test coverage gaps: every edge function with non-trivial logic
    SHOULD have a test. Which don't?
  - Sentry setup: does the iOS app initialize Sentry? Does the web?
    Do edge functions report errors anywhere except console?
  - Sourcemap upload: are stack traces useful in production?
  - CI status: is there a build-on-PR? Lint? Type-check?
  - Deploy gates: anything that prevents a bad deploy from going to
    prod (manual approval, smoke test)?
  - Rollback: deploy.md describes rollback for each surface. Has
    anyone tested the rollback path recently?
  - Feature flags: any kill-switch infrastructure? GrowthBook,
    LaunchDarkly, env vars?
  - Cost monitoring: is there a Supabase bill check, an LLM spend
    dashboard, anything?

Output to docs/reviews/day12-tests-ops.md. Include a "what
breaks if Rio is unreachable for 7 days" stress-test paragraph
at the end.
```

---

## Day 13 — Build config, secrets, and CI/CD

**Surface:** Xcode project files, `package.json`, `tsconfig.json`, `next.config.*`, `.env*` example files, `.github/workflows/`, Vercel/Supabase config, secrets management.

```
You're auditing the build pipeline, secret management, and
CI/CD setup of Post Run Drip.

Read in this order:
  1. iOS: find every .xcconfig, Info.plist, and entitlements file.
     What environments does the app build for?
  2. Web: package.json, tsconfig.json, next.config.ts/js,
     vercel.json (if present).
  3. .github/workflows/ — every CI job.
  4. Supabase: config.toml, function-level config in
     supabase/functions/*/config.json.
  5. Look for .env.example or similar — what env vars are required?
  6. grep for hardcoded secrets: search "sk_", "supabase_anon_",
     "ANTHROPIC", "OPENAI", "STRAVA_CLIENT" in committed files.

Specifically look for:
  - Hardcoded secrets: anything that should be env-injected but
    is committed?
  - Mismatched dev/prod config: anywhere that env-specific values
    aren't separated cleanly.
  - Build-time vs runtime config: is anything pulling secrets at
    build time when it should be runtime?
  - CI/CD: PR checks, merge gates, deploy approval gates.
  - Versioning: is iOS using semver? Are versions consistent
    between Info.plist, package.json, and any release notes?
  - Plugin / dependency audit: any deps with critical CVEs?
    (Run `npm audit` if you can; mention what you'd run on iOS.)
  - Apple Developer setup: any TestFlight / App Store issues
    documented?

Output to docs/reviews/day13-build-cicd.md. Include a "secrets
that need rotating" list if any are found.
```

---

## Day 14 — Synthesis + the 30-day punchlist

**Surface:** all 13 prior review docs.

```
You're the final-day reviewer of Post Run Drip. Days 1-13 produced
13 review documents in docs/reviews/. Your job is synthesis: read
all 13, find cross-cutting patterns, produce a prioritized punchlist
that Rio can work from for the next 30 days.

Read in this order:
  1. docs/reviews/day1 through day13 — every line.
  2. docs/codebase-review-2026-04.md — the earlier holistic read.
  3. docs/competitive-brief-2026-04.md — the market context.

Then write docs/reviews/day14-synthesis.md with these sections:

  ## Cross-cutting themes (3-5)
    Patterns that appeared in 3+ days. Name each, cite which days,
    explain why it matters.

  ## The 30-day punchlist
    Top 20 things to fix, in priority order. Each item:
      - 1-line description
      - File / area
      - Severity (🔴 / 🟡 / 🟢)
      - Time estimate
      - Why it matters
    Rank by ROI (impact ÷ effort), not by severity alone.

  ## What's actually solid
    The 5 things that don't need work and that Rio should defend
    against premature optimization.

  ## The "you'd be embarrassed if it shipped" list
    Things that would make a serious athlete or a hired engineer
    cringe. Be brutally honest.

  ## Bus-factor risks
    Code that ONLY Rio understands. What documentation would help
    a second engineer come up to speed? List specific docs to write.

  ## What I would NOT do
    Tempting refactors that should be resisted. Rationale.

This is the most important document of the 14-day review. Take
your time. Cite specific files and line numbers. Don't generalize.
```

---

## Optional Day 15 (after fixes) — Verification pass

After you've worked the punchlist for 30 days, re-run any of the
days that touched fixed surfaces. Compare the new findings against
the old. If a critical issue is gone, document it. If a new one
emerged, prioritize.

---

## Cadence suggestion

- **Sprint 1 (week 1):** Days 1, 2, 3 — coaching + voice + analysis. Most product-critical.
- **Sprint 2 (week 2):** Days 4, 5, 6 — pace + adaptive loop + workout authoring. Most code-critical.
- **Sprint 3 (week 3):** Days 7, 8, 9 — data + integrations + web. Most leverage-critical.
- **Sprint 4 (week 4):** Days 10, 11, 12, 13 — long tail + ops. Most ops-critical.
- **Day 14:** synthesis + punchlist.
- **Sprint 5 (week 5):** work the top 5 punchlist items.
- **Day 15:** verify.

Don't try to do 14 days in 14 calendar days. 2-3 per week is realistic
without burning out.

---

*Last updated 2026-04-25. Re-run the relevant day after major surface
changes.*
