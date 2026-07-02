# Implementation plan — Life Context slice (audit fix #1) + fitness-snapshot check (fix #3)

**Date:** 2026-07-02
**Goal:** make athlete-state consume the qualitative signal the voice-memo pipeline already extracts (sleep, stress, fatigue, illness, travel, motivation, felt_vs_looked, RPE), so the Coach Read can actually do "feeling first, reads life context." Plus the one-hour prod check that the fitness backbone is alive.

Each step is independently shippable and has a "done when." Steps 1–5 are code; step 0 is verification; steps 6–7 are review + deploy. Rough total: 2–4 working sessions.

---

## Step 0 — Verify before building (no code)

**0a. Is anything writing `fitness_snapshots`?** Run against prod (read-only):

```sql
select count(*) as rows,
       count(distinct user_id) as users,
       max(created_at) as newest,
       min(created_at) as oldest
from fitness_snapshots;

select user_id, count(*) as n, max(created_at) as latest
from fitness_snapshots
group by user_id order by latest desc limit 10;
```

Also grep `ml-service/` for the writer and whatever schedules it. **Done when** we know the cadence (or confirm it's dead — which becomes its own fix, out of scope here).

**0b. How populated is `extracted_data` in practice?**

```sql
select count(*) filter (where extracted_data is not null) as with_data,
       count(*) as total
from training_logs
where source in ('voice_log','voice_memo','check_in')
  and created_at > now() - interval '90 days';

select key, count(*) from training_logs,
  lateral jsonb_object_keys(extracted_data) as key
where extracted_data is not null
  and created_at > now() - interval '90 days'
group by key order by count(*) desc;
```

**Done when** we know which fields actually show up, so the builder is designed around real coverage, not the prompt's wish-list. (If almost nothing populates, fix the memo prompt/write path first — cheaper than building a reader for empty data.)

---

## Step 0 — FINDINGS (run 2026-07-02 against prod `aqdijapxmjqaetursrde`)

**0a — fitness_snapshots: the writer is the iOS app, and it's gone quiet.**
34 rows total across what is really **one athlete** (the same UUID appears in lower- and upper-case — a user_id casing bug — plus 3 junk rows with an empty user_id). Snapshots ran ~2–3/week March 31 → June 12, then **nothing for 20 days**. The only writer in the codebase is `RunningLog/Analysis/FitnessPredictorService.swift:997` (client-side insert); `ml-service` only *reads* the table. Consequences: snapshot cadence depends on someone opening the app and hitting that code path; `fitness_trend` is currently comparing stale data; the 6-month comparison window will often be empty; and the casing bug can split one athlete's history into two identities.
→ **New work item (milestone 2):** move snapshot writing server-side (cron or post-`compute-workout-features` hook), normalize `user_id` casing, delete the empty-user rows. Not a blocker for this plan.

**0b — extracted_data: the pipeline works, but prod is running an old prompt.**
31 of 37 voice logs (84%) in the last 90 days carry `extracted_data`, and 100% carry mood — the write path is healthy. But the keys present are only the OLD schema (`workout_type`, `effort_level`, `rpe` ×13, `weather` ×10, `sleep_quality` ×8, `fueling`, `running_partners`...). The coach-critical life fields in the repo's current prompt — `felt_vs_looked`, `work_stress`, `life_stress`, `fatigue`, `travel`, `illness`, `motivation`, `sleep_hours`, `soreness` — appear **zero times**. The deployed `process-training-memo` predates the current `process-training-memo.v1.ts`.
→ **New Step 0.5 (blocker for full value):** redeploy `process-training-memo` from the current repo so new memos start carrying the life fields. Per hard rule #3, this is a prompt change — do the step-6 principles review on its output before/at deploy. The builder (step 3) must tolerate historical rows that only have the old keys — which 0b confirms is *all* rows today, so early Reads will lean on `sleep_quality`/`rpe`/`weather` until new memos accumulate.

---

## Step 1 — Migration: `athlete_state.life_context` column

New file `supabase/migrations/<timestamp>_athlete_state_life_context.sql`, modeled on `20260615000000_athlete_state_fitness_signal.sql`:

```sql
alter table athlete_state add column if not exists life_context jsonb;
```

No RLS changes (existing table, existing policies). Append-only per hard rule #5; reaches prod only via `supabase db push` from a committed SHA per hard rule #9.

**Done when** the migration parses and applies cleanly on a local/branch database.

## Step 2 — Read `extracted_data` in the rebuild

`supabase/functions/_shared/athlete-state.ts` — add `extracted_data` to the 28-day recent-logs select (line ~511). Nothing else changes yet.

**Done when** existing tests in `_shared/athlete-state.test.ts` still pass (the extra column is inert until step 3).

## Step 3 — New builder: `buildLifeContext.ts`

New file `supabase/functions/_shared/builders/buildLifeContext.ts` — a pure function (same style as `buildMoodTrend`), input = the 28-day logs (now carrying `extracted_data`), output:

```ts
interface LifeContext {
  // recency-first trails, small and prompt-friendly
  sleep:      { poor_mentions_7d: number; mentions_28d: number; last: { date: string; quality: string; hours: number | null } | null };
  fatigue:    Array<{ date: string; label: string }>;          // last 5
  stress:     { work_high_7d: number; life_high_7d: number; any_high_28d: number; last_mention: string | null };
  illness:    { active: boolean; detail: string | null; date: string | null };  // mention within 10d = active
  travel:     { recent: boolean; detail: string | null; date: string | null };  // within 7d
  motivation: { low_7d: number; last: string | null };
  felt_vs_looked: Array<{ date: string; value: string }>;      // last 4, quality sessions weighted
  avg_rpe_7d: number | null;
  summary: string | null;   // one compressed line, e.g. "sleep poor ×3 this week · work stress high · felt harder than it looked twice"
}
```

Design rules: verbatim-adjacent (store the athlete's labels, never reinterpret), null-heavy tolerance (most memos populate 2–3 fields), and no medical language — `illness.detail` is the athlete's own phrase ("fighting a cold"), per hard rule #2.

**Done when** unit tests pass: fixture logs with sparse/dense/absent `extracted_data`, plus a no-memos athlete returning an all-null object.

## Step 4 — Wire into state + prompt

1. Add `life_context: LifeContext | null` to the `AthleteState` interface; call the builder in `rebuildAthleteState`; add to the state literal.
2. New section in `stateToPromptContext` — priority 3 (same tier as vibe/recent runs; droppable under budget, unlike injuries):

```
Life context (from voice memos — feeling first; reference, don't diagnose):
  Sleep: poor ×3 this week (last: Mon, ~5h)
  Work stress: high (mentioned Tue, Thu)
  Felt vs looked: "harder than it looks" on 2 of last 4 quality days
→ Read paces through this lens. Never prescribe rest or treatment; ask soft questions.
```

3. Add an honest `data_gaps` entry when the slice is empty but runs exist: `NO LIFE SIGNAL — "No memos mentioning sleep, stress, or how the body felt in 2+ weeks."` And a permanent gap while hole 6 stands: `NO RECOVERY DATA — "I can't see sleep or HR recovery from a device — only what you tell me."`

**Done when** `stateToPromptContext` renders the section for a fixture state, `athlete-state-prompt-budget.test.ts` is updated with the new section's cost, and the section drops cleanly under a finite budget.

## Step 5 — Two pattern rules

In the patterns block of `rebuildAthleteState` (after the existing six):

- **`life_load`** — ≥3 memos in 14d with (work/life stress high OR sleep poor) AND mood in {tired, struggling}: *"Training is colliding with life load right now — rough sleep and work stress keep showing up alongside tired runs."* Evidence: the dates + counts. Confidence: medium at ≥3, low at 2.
- **`effort_mismatch`** — ≥2 of last 4 `felt_vs_looked` values are "harder than it looks": *"Paces are costing more than they show — the same numbers have felt harder lately."* This is the early-overreach tell a human coach prizes.

**Done when** unit tests cover firing and non-firing cases for both.

## Step 6 — Voice + safety review (hard rule #3)

This changes prompt *content* even though no file in `_shared/prompts/` is touched, so the CI eval gate won't fire. Do the manual equivalent: generate 3–5 Daily Reads for test athletes (one with heavy life-load, one with illness mentions, one with empty slice) and check against `docs/coaching/principles.md` — feeling before data, no diagnosis or rest prescriptions triggered by illness/stress fields, anchors silent, soft questions. Add an eval cassette for `coaching-daily-read` if its stub is among the 10 needing athlete-side inputs — this work produces exactly those inputs.

**Done when** reviewed reads pass the checklist and at least one cassette is recorded.

## Step 7 — Deploy

`supabase db push` from the committed SHA (migration), deploy the touched edge functions, then invoke `rebuild-athlete-state` for a test user and inspect the row's `life_context` and the rendered prompt. The existing invalidation trigger (`20260420200000_invalidate_athlete_state_on_training_log.sql`) already refreshes state on new memos — no freshness work needed.

---

**Out of scope (separate plans):** niggle classifier rewrite (audit #2), memories-from-memos (audit #4), HealthKit backfill (audit #5). Step 0a's findings decide whether "fix the snapshot writer" jumps the queue.

---

## STATUS — 2026-07-02 (code complete; deploy pending)

| Step | Status |
|---|---|
| 0a/0b verification | ✅ Done — findings above |
| 0.5 memo-function redeploy | ⬜ Deploy action (see runbook) |
| 1 migration | ✅ `supabase/migrations/20260702100000_athlete_state_life_context.sql` |
| 2 extracted_data in select | ✅ `athlete-state.ts` recent-logs query |
| 3 builder | ✅ `_shared/builders/buildLifeContext.ts` + 9 unit tests |
| 4 state + prompt + gaps | ✅ `life_context` field, P3 prompt section, `NO LIFE SIGNAL` / `NO RECOVERY DATA` gaps |
| 5 pattern rules | ✅ `life_load` + `effort_mismatch`, covered by 2 end-to-end rebuild tests |
| 6 principles review | ⬜ Do at deploy: generate 3–5 Reads (heavy life-load / illness / empty slice) and check against `docs/coaching/principles.md` |
| 7 deploy | ⬜ Runbook below |

Test results: 28/28 pass across `buildLifeContext.test.ts` (9), `athlete-state.test.ts` (12, incl. 2 new end-to-end), `athlete-state-prompt-budget.test.ts` (7, incl. 2 new). Full `_shared/` suite: 289/290 — the 1 failure is **pre-existing and unrelated** (`rateLimit.contract.test.ts`: `correct-workout-structure` and `ingest-manual-workout` call LLMs without pinned rate limiting — worth its own small fix).

### Deploy status update — verified against prod 2026-07-02 (later same day)

- ✅ Migration applied — `athlete_state.life_context` column exists in prod.
- ✅ Step 0.5 moot — the deployed `process-training-memo` (v65, ~June 18) already emits the new life fields; real memos from June 17–29 carry `fatigue`, `felt_vs_looked`, `motivation`, `effort_level`.
- ✅ Builder extended (effort trail + `hard_7d`, check-in `stress_level` folding) — 31/31 tests green.
- ✅ `compute-fitness-snapshot` edge function created 2026-07-02 (milestone-2 snapshot writer started; verify it's scheduled).
- ⬜ **REMAINING: `rebuild-athlete-state` (v4, June 13) and `coaching-daily-read` (v11, June 16) still run pre-life-context bundles.** State rows are invalidated; `life_context` is null in prod. Deploy those + `coaching-agent`, force a rebuild, run the step-6 principles review.

### Deploy runbook (run from a Claude Code session or terminal with Supabase auth)

```bash
# 1. Commit (the tree carries other pending work — review what you include)
git add supabase/migrations/20260702100000_athlete_state_life_context.sql \
        supabase/functions/_shared/builders/buildLifeContext.ts \
        supabase/functions/_shared/builders/buildLifeContext.test.ts \
        supabase/functions/_shared/athlete-state.ts \
        supabase/functions/_shared/athlete-state.test.ts \
        supabase/functions/_shared/athlete-state-prompt-budget.test.ts \
        outputs/athlete-state-knowledge-audit-2026-07-02.md \
        outputs/life-context-implementation-plan-2026-07-02.md \
        outputs/beta-roadmap-2026-07-02.md
git commit -m "athlete-state: life_context slice from memo extracted_data (audit fix #1)"

# 2. Migration — hard rule #9: db push only, never dashboard SQL / MCP apply
supabase db push

# 3. Step 0.5 — redeploy the memo function so new memos carry the life fields
supabase functions deploy process-training-memo

# 4. Redeploy the state's heaviest consumers (they bundle _shared/ at deploy)
supabase functions deploy coaching-daily-read coaching-agent rebuild-athlete-state

# 5. Verify: force a rebuild for a test user, inspect the row
#    (life_context should be null until a post-deploy memo lands — expected;
#    data_gaps should include NO RECOVERY DATA)
#    then record a memo mentioning sleep/stress and rebuild again.

# 6. Step 6 principles review on the first generated Reads before announcing.
```

Note: the other ~10 edge functions that import athlete-state keep working undeployed (the new column is additive; their bundled `stateToPromptContext` simply won't render the new section until each is next deployed).
