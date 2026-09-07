# Production Review — Findings Ledger (2026-06-22)

First execution pass of `production-code-review-plan-2026-06-22.md`. Covers
Phase 0 (machine sweep), Phase 1 (security & data loss), Phase 2 (AI safety),
Phase 3 (correctness hotspots). Every finding has file:line or advisor
evidence. Severity = blast radius, not effort.

**Bottom line:** RLS coverage, service-role-key containment, and the four
athlete-state P0 fixes are in good shape. Two issues **block beta**: an
unsecured ghost table, and the reschedule flow writing plan changes directly
(violating "AI never acts"). A cluster of HIGHs around AI safety should be
fixed before real athletes rely on the coaching surfaces.

## Severity counts

| Severity | Count | Meaning |
|---|---|---|
| BLOCKER | 2 | Must fix before any real user |
| HIGH | 6 | Fix before athletes rely on the surface |
| MEDIUM | 8 | Schedule soon; not launch-gating |
| LOW / known debt | 5 | Log and move on |

---

## BLOCKERS

**B1 — `public._csv_export_tmp` is world-readable/writable (RLS disabled, ghost table).**
Security advisor `rls_disabled_in_public`, level ERROR/critical. The table is
*not in any migration* (0 references in `supabase/migrations/`) — it was
created ad-hoc in prod, so it also violates hard rule #9. Anyone with the anon
key can read or modify every row. It looks like a leftover CSV-export scratch
table (1 row).
*Fix:* `DROP TABLE public._csv_export_tmp;` via a committed migration (confirm
nothing reads it first). Do not just enable RLS-without-policy.

**B2 — reschedule-plan writes plan changes directly, bypassing the "AI never acts" guardrail.**
Hard rule: AI advises, never acts; reschedule must write to `plan_adjustments`
with `auto_applied:false` (no auto-apply). The edge function does zero DB
writes (`supabase/functions/reschedule-plan/index.ts`) — correct — but the iOS
client then writes suggestions straight onto `ScheduledWorkout` rows via
`planService.updateWorkout` (`RunningLog/.../RescheduleService.swift:171-217`),
defaulting `isApproved=true` (`:81`). No `plan_adjustments` row, no
`auto_applied` flag, no audit/revert trail; a user applies all AI suggestions
in one tap.
*Fix:* route applies through `plan_adjustments` (`auto_applied:false`) and keep
the revert trail, per `outputs/plan-mutations-and-race-design.md`.

---

## HIGH

**H1 — Preview LLM model on the most safety-sensitive surface.**
`gemini-3.1-pro-preview` (×9) powers the user-facing Daily Read
(`supabase/functions/coaching-daily-read/index.ts:232`). Preview models can
change behavior or be withdrawn without notice. *Fix:* pin to a GA model.

**H2 — Legacy `injuries.ts` self-assigns numeric severity, violating the niggles rule.**
`_shared/injuries.ts:71-78` `estimateSeverity()` coerces the athlete's words
into a 1–10 score ("can't walk" → 9) — directly against "quote verbatim, never
assess severity." It's live: `_shared/memory.ts:316-324` calls it on every
INJURY-tagged chat, writing numeric severity that then feeds AI context
(`injuries.ts:194`) and the injury-early-warning prompt. *Fix:* stop coercing
severity; surface verbatim quotes only, per `body_mentions` design.

**H3 — `injury-early-warning.v1` recommends actions / medical evaluation.**
`_shared/prompts/injury-early-warning.v1.ts:25-29` gives "concrete actionable
suggestions" and recommends medical eval for severity ≥5 — crosses from
detection-not-diagnosis into advice, and is driven by H2's self-assigned
severity. Also has no eval cassette (see H6). *Fix:* constrain to observation;
add the `insight-safety.ts` post-filter that the workout-insight path already
uses.

**H4 — Single-point, seconds-precision predictions (hard rule #7).**
`race-readiness.v1.ts:60` emits a single `target_time` with no range and is
live (`race-readiness/index.ts:264`). `fitness-predictor.v1.ts` emits bare
`H:MM:SS` race times (orphan prompt — no edge function — but still registered
in `prompt-library.ts:77`). *Fix:* add range+confidence to race-readiness;
delete or fix the orphan fitness-predictor prompt.

**H5 — Three inline prompts bypass the eval-gate entirely (hard rule #3).**
`extract-rpe/index.ts:75`, `generate-training-plan/index.ts` (`SKELETON_SYSTEM_PROMPT`),
`parse-training-plan/index.ts:99` define prompts inline — no `_shared/prompts/`
entry and no cassette, so the CI gate never even applies. *Fix:* migrate to
`prompt-library.ts` and add cassettes.

**H6 — Live prompts with no eval coverage.**
Beyond H3, these are live and uncovered: `race-readiness.v1`, `race-intel.v1`,
`weekly-coaching-report.v1`, `parse-training-week.v1`, `coaching-agent-proactive.v1`.
The CI gate only fires when a `_shared/prompts/` file changes, so untouched
uncovered prompts ship silently. *Fix:* record cassettes for the live set.

---

## MEDIUM

**M1 — SECURITY DEFINER functions callable by `anon`/`authenticated` via RPC.**
Advisor flags ~14, incl. mutation/trigger fns: `dedupe_recent_training_logs`,
`backfill_workout_insights`, `enqueue_daily_reads`, `sync_workout_laps_from_streams`,
`fn_weekly_plan_rebalance`, `trigger_voice_log_processing`. An anon caller can
invoke these. Migrations already `REVOKE` for ~10 objects but not all. *Fix:*
`REVOKE EXECUTE ... FROM anon, authenticated` on the operational ones.

**M2 — Three SECURITY DEFINER views expose internal LLM cost/usage.**
`daily_usage`, `daily_cost_estimate`, `yesterday_llm_spend` (advisor ERROR).
They run as creator, bypassing the caller's RLS. *Fix:* make SECURITY INVOKER
or revoke from the API roles.

**M3 — `debug_coach_log` is a debug table in prod.**
Created in `20260609233553_tighten_insert_rls_and_debug_log.sql`; RLS enabled
but no policy (locked to service role), 28 rows. Low exposure but shouldn't be
in prod. *Fix:* drop or gate behind an env flag.

**M4 — Pace constant drift between edge and web/iOS.**
`_shared/paces.ts:63-72` truncates `RACE_DISTANCE_MI` to 4 dp; web
(`workout-helpers.ts:394-403`) and iOS (`PaceCalculator.swift:11-16`) use full
precision. Sub-second today, but these files are required to be "in lockstep."
*Fix:* use identical full-precision constants.

**M5 — The pace cross-language parity test doesn't exist.**
`paces.ts:171` and `athlete-state.test.ts:171` both cite
`_shared/cross-language-pace-contract.test.ts` — no such file exists. That's
the guard that would catch M4. *Fix:* write it (assert web≡edge≡iOS constants).

**M6 — athlete-state rebuild race only partially serialized.**
`athlete-state.ts:469-475` (self-documented): the advisory lock covers only the
claim RPC, not the rebuild body; after a ~3s stall a second concurrent rebuild
can run (last-write-wins). No test covers the claim/poll branch (the fake RPC
always returns null). Bounded/self-healing. *Fix:* add a contention test;
consider serializing the rebuild body later.

**M7 — Two stale-model references / drift.**
`process-check-in/index.ts:8` comment says `gemini-2.0-flash-lite` but the call
uses `gemini-2.0-flash` (`:174`); the comment at `:8` also notes it "was
gemini-2.5-flash." Plus Groq models (`llama-3.1-8b-instant`, `llama-3.3-70b-versatile`)
in router/coaching-agent add provider sprawl. *Fix:* reconcile comments;
document the intended model per call (ties to tech-debt item #1).

**M8 — Auth hardening toggles off.**
Leaked-password protection disabled (advisor WARN); `vector` extension in the
`public` schema. *Fix:* enable HaveIBeenPwned check; move `vector` to its own
schema when convenient.

---

## LOW / known debt

- **L1 — ~25 functions with mutable `search_path`** (advisor WARN). Standard
  hardening; set `search_path` on each. Not launch-gating.
- **L2 — Performance advisor not captured** this pass (output too large; temp
  file expired). At 200–1000 users it's mostly missing FK indexes — re-run
  `get_advisors(type:performance)` and triage before scaling, not before beta.
- **L3 — Drift detectors need a live Supabase connection.** `check_function_drift`
  / `check_migration_drift` failed locally (expect `/tmp/remote_*.json` from the
  CLI). They run in CI; just confirm CI is green.
- **L4 — 9 design-token violations** (`check_design_tokens.py`), all in
  `TrainingAnalyticsViewModel.swift` (hardcoded hex). Ratchet rule, cosmetic.
- **L5 — Eval coverage check passed** for touched prompts, but coverage is
  partial overall (see H5/H6). Not a regression; a gap.

---

## What's solid (verified, no action)

- **RLS coverage:** 49 of 50 public tables have RLS enabled (only B1's ghost
  table is the exception). Hard rule #1 essentially holds.
- **Service-role key containment (hard rule #4):** no service key in the iOS
  bundle; in web it's confined to server-only `api/*` routes via
  `lib/env.server.ts` (with an eslint guard), never `NEXT_PUBLIC_`. No hardcoded
  JWT service keys anywhere. `coachable_moments` has no client INSERT policy —
  only coach-view, coach-update, service-role-full.
- **Niggles primary path:** the live detector (`athlete-state.ts:942-1062`) uses
  a closed vocabulary, requires a nearby severity word, quotes verbatim, and
  doesn't diagnose. Parse/insight prompts forbid diagnosis and have a runtime
  safety filter (`insight-safety.ts`). (The violation is the *legacy* path, H2.)
- **athlete-state P0 fixes:** R3 (tenant leak), R6 (all four formerly-null
  fields), R7 (pace zones from PaceEngine), and `formatPace` rounding are each
  backed by real, exercising tests. R4 is real in code but its framing is
  overstated (see M6).
- **Pace math:** race-equivalence ratios, MP-speed ratios, and the one-hour-pace
  LT interpolation match across all three implementations (only M4's distance
  constants drift).
- **reschedule-plan server side:** constrained to `WORKOUT_CODES_BY_DAY`,
  rate-limited, no free generation. (The gap is the client write path, B2.)

---

## Recommended fix order

1. **B1** — drop the ghost table (minutes, removes a live data-exposure hole).
2. **B2** — route reschedule applies through `plan_adjustments`.
3. **H1** — pin Daily Read off the preview model.
4. **H2 + H3** — stop severity coercion and the action-recommending injury prompt (one workstream).
5. **H4** — range+confidence on race-readiness; kill the orphan predictor prompt.
6. **H5 + H6** — bring inline/live prompts under the eval gate.
7. **M1–M2** — revoke anon EXECUTE; fix the SECURITY DEFINER views.
8. Everything else → log into `TASKS.md` as known debt.

## Updated go/no-go gate

Ship beta when B1, B2, H1, H2, H3, H4 are closed and B1's RLS hole is confirmed
gone via a clean security-advisor run. The remaining HIGH/MEDIUM items are
fast-follows, not gates.
