# Implementation plan — Long-term memory ("it knows you," audit fix #4 / roadmap milestone 4.1)

**Date:** 2026-07-02
**Goal:** after 6 months of memos, the coach doesn't just know the athlete's patterns — it remembers them as a person: durable facts ("trains around night shifts," "hates treadmills," "two kids under five"), quotable moments ("that January 20-miler you called 'the day it clicked'"), and the long training arc ("this time last year you were at 32 mpw"). All athlete-controllable, all sourced from what they actually said.

**Current state (verified in prod 2026-07-02):** `user_memories` exists (id, user_id, category, content, source_conversation_id, extracted_from, importance, expires_at, timestamps) and holds 10 rows — 5 PRs, 3 goals, 2 injuries — all from the regex extractor in `_shared/memory.ts`, which only runs on coaching-agent *chat*, never on memos. Newest row is April. Athlete-state reads top-12 by importance and renders "What I remember about you." The iOS app already has a **Model of You** surface (`RunningLog/Coaching/ModelOfYou/`) — a natural home for memory visibility/control.

**Three kinds of long-term knowing** (this plan builds all three):

| Kind | Example | Mechanism |
|---|---|---|
| Semantic — durable facts & preferences | "night-shift nurse; long runs on Saturdays" | LLM extraction from memos → `user_memories` |
| Episodic — moments worth quoting | "Jan 14: called the trail 20-miler 'the day it clicked'" | New `episode` category with the athlete's verbatim phrase + date |
| Longitudinal — the training arc | "42 mpw now vs 32 mpw this time last year" | Widen block history 24wk → 12mo + a year-ago comparison line |

**Design rules:** athlete's words, never inferred psychology (no "seems anxious about racing"); memory is a privilege the athlete can revoke (view/delete); zero new LLM cost (extraction piggybacks on the existing memo analysis call); consolidation keeps the store small — a coach remembers ~30 things, not 3,000.

---

## Step 0 — Verify + baseline (~30 min, read-only)

1. Confirm memo → analysis call structure in `process-training-memo/index.ts` (one Gemini call whose JSON we extend — no second call).
2. Check `user_memories` RLS policies: today's writes go through service-role paths? Client SELECT exists? DELETE policy for athlete self-service will be needed in step 1.
3. Baseline the 10 existing rows — they stay; new extraction must not duplicate them (the PR rows especially).

**Done when** findings recorded here.

### Step 0 findings (recorded 2026-07-02)

1. **Single Gemini call confirmed.** `process-training-memo/index.ts:729-741` loads
   `process-training-memo.v2`, makes ONE `model.generateContent([...])` call, and
   parses the JSON via `parseJsonResponse` → `validateAnalysis` (`AnalysisResult`
   interface, index.ts:79-86 / 145-174). Extending the prompt's JSON output adds
   **zero** new calls — the new `memory_candidates` array rides in the same
   response, exactly like the niggle `soreness` objects already do. The niggle
   write path (`_shared/niggleWriter.ts`, called at index.ts:883) is the precise
   pattern to mirror: a PURE transform + a thin never-throws I/O wrapper, both in
   `_shared/` so they're unit-testable without booting `Deno.serve`.
2. **RLS.** The memo function's `supabase` client is **service-role**
   (index.ts:21-25, `SUPABASE_SERVICE_ROLE_KEY`) — writes bypass RLS, same as the
   niggle writer. The only *active* policy on `user_memories` today is
   `rls_user_memories_all` (`FOR ALL USING/WITH CHECK user_id = auth.uid()::text`,
   from `20260313100000_lock_down_rls.sql:240-242`), which supersedes the earlier
   "Users can manage own memories" policy (dropped in the same migration).
   *Implication:* athletes can ALREADY select and delete their own rows under
   `FOR ALL`. The Step 1 dedicated DELETE policy is therefore **redundant with the
   FOR ALL grant** — I'll still add it (per plan, and it documents revocability
   intent explicitly for the Model of You surface), but it grants no new capability.
   No client-side INSERT concern: all writes are service-role.
3. **Baseline.** Plan states 10 rows (5 PR, 3 goal, 2 injury), all `chat_regex`
   from `_shared/memory.ts`, newest April. `memory.ts` categories are
   `pr|injury|goal|preference|training|race|personal|agreement|context` — note the
   Step 2 taxonomy (`pr|race|preference|constraint|life|gear|episode`) is
   DIFFERENT: no `injury` (stays in `body_mentions`, hard rule #2), and it renames
   `context`→`life`, adds `constraint|gear|episode`. Dedup in Step 3 must guard the
   legacy PR rows specifically (same `pr` category persists across both extractors).
   Live row count re-verified at deploy (Step 8) via the Supabase MCP / `db push`.
4. **CI eval gate.** `.github/scripts/check_eval_coverage.py` fires when a file
   matching `supabase/functions/_shared/prompts/<name>.ts` is **added or modified**.
   Creating `process-training-memo.v3.ts` (Step 2) therefore REQUIRES
   `_evals/cassettes/process-training-memo.v3/` to exist with ≥1 file. Cassette
   *authoring* (input + rubric, `recorded_response: ""`) satisfies the gate and is
   done here; actual *recording* needs `GEMINI_API_KEY` (`_evals/record.ts`) and is
   a deploy-time/team action (Step 6/8).

## Step 1 — Migration: memory hygiene columns + athlete control

Append-only migration (hard rules #1/#5/#9):

```sql
alter table public.user_memories
  add column if not exists status text not null default 'active',        -- active | archived
  add column if not exists source text,                                   -- chat_regex | memo_llm | consolidation
  add column if not exists memory_date date,                              -- when the remembered thing HAPPENED (episodes)
  add column if not exists last_confirmed_at timestamptz,                 -- most recent re-mention
  add column if not exists mention_count integer not null default 1;

-- Athlete self-service: read own (exists), delete own (new — memory is revocable).
create policy "Users delete own memories" on public.user_memories
  for delete using (user_id = (auth.uid())::text);
```

Backfill existing rows `source = 'chat_regex'`. **Done when** migration validates locally.

## Step 2 — Extraction: extend the memo prompt (zero extra calls)

Extend `process-training-memo` prompt output (v-bump; **CI eval gate fires** — cassettes in step 6) with:

```
"memory_candidates": [{
  "category": "pr" | "race" | "preference" | "constraint" | "life" | "gear" | "episode",
  "content": "one plain sentence, the athlete's framing",
  "their_words": "verbatim phrase worth keeping (episodes only)",
  "durable": true|false,      // false → gets expires_at +60d (transient life context)
  "importance": 1-10
}]
```

Prompt guardrails: only what the athlete actually said; no personality inference, no health speculation (injuries stay in `body_mentions` — not duplicated here); episodes require a genuinely distinctive moment, not every run; return `[]` freely (most memos contain no memory — that's correct).

**Done when** cassette inputs exercise: a memo with a clear durable fact, a memo with an episode-worthy moment, a mundane memo (→ `[]`), and a memo with health speculation bait (→ not extracted).

## Step 3 — Write path: dedup-or-reinforce

In `process-training-memo` after analysis, for each candidate:

1. Normalize; fetch the athlete's active memories in the same category.
2. **Near-duplicate?** (case-insensitive token overlap ≥ 0.7 against existing content — pure function, unit-tested) → don't insert; bump `mention_count`, set `last_confirmed_at`, raise importance by 1 (cap 10). Re-mentioning IS the signal that something matters.
3. Else insert with `source: 'memo_llm'`, `extracted_from` = memo excerpt (≤200 chars), `memory_date` for episodes, `expires_at` +60d when `durable: false`.

**Done when** unit tests cover: fresh insert, reinforcement path (no dup row, importance bumped), transient expiry set, and PR-category dedup against the legacy regex rows.

## Step 4 — Consolidation: the weekly "sleep" job

New edge function `consolidate-memories` + pg_cron (weekly, per athlete with activity):

- Merge remaining near-duplicates (keep oldest id, sum mention_count, max importance).
- Archive (not delete): expired transients; memories not confirmed in 12 months with importance ≤ 4 ("forgetting" is honest — preferences change).
- Cap per category (e.g. 10 active per category, lowest importance archived first).
- Log a one-line audit per change (visible in function logs).

Follows the outbox/cron patterns already in the repo (`drain-*` functions). **Done when** running it twice in a row is a no-op the second time (idempotent), pinned by test.

## Step 5 — Surfacing: smarter selection + episodes with dates

1. **athlete-state selection** — replace "top-12 by importance" with quota-based selection (pure function): up to 3 constraints, 3 preferences, 2 life, 2 PR/race, 2 episodes; within quota by `importance × recency of last_confirmed_at`; `status = 'active'` only.
2. **Prompt render** — episodes get their date and verbatim phrase: `• Jan 14 — their words: "the day it clicked" (trail 20-miler)`. Guidance line: *reference sparingly — one callback per Read at most; never recite the list.*
3. **Year-ago arc** — widen the block-history query 168d → 365d (bounded: +~200 rows), keep prompt at 6 recent blocks, add one line when data reaches back: `This time last year: ~32 mpw, mood mostly neutral.`
4. **data_gap** when an active athlete has < 3 memories: `STILL LEARNING YOU — "I don't know much about your life outside the numbers yet — tell me in your memos."` (Doubles as user education: it teaches athletes that memos feed memory.)

**Done when** prompt-budget tests cover the new sections and the token cost is measured (this plan adds the most prompt weight so far — if the rendered state now routinely exceeds ~1,800 tokens, pick and enforce a finite budget in the same PR; the machinery exists).

## Step 6 — Eval + principles review (hard rule #3)

Record cassettes for the v-bumped memo prompt (step 2 cases). Manual review of 3–5 Reads: callbacks feel warm, not surveilled ("you mentioned the Denver trip" good; reciting their life back at them bad); no memory-based prescriptions; episodes quoted verbatim.

**Done when** CI gate passes + reviewed Reads check out against `docs/coaching/principles.md`.

## Step 7 — Model of You: visibility + control (iOS, small)

Wire `user_memories` (active, non-archived) into the existing Model of You surface: list grouped by category, athlete's words shown, swipe-to-forget (DELETE via the new policy). Ship read+delete only; editing can wait.

**Done when** an athlete can see everything the coach remembers and remove any item — before beta users ever see a memory-informed Read. This step is not optional; memory without visibility is a trust bug.

## Step 8 — Deploy

Commit → `supabase db push` → deploy `process-training-memo`, `consolidate-memories`, `rebuild-athlete-state`, `coaching-daily-read`, `coaching-agent` → schedule the cron → record a memo containing a durable fact → verify the row, the next Read's callback, and the Model of You listing.

---

**Effort:** 3–5 sessions (steps 2–4 are the core; step 7 is the only iOS work).
**Payoff curve:** immediate for new memos; the store becomes noticeably personal after ~3–4 weeks of normal memo habit; the year-ago line unlocks automatically once an athlete crosses 12 months of history (or when HealthKit backfill — milestone 4.2 — lands and supplies it retroactively).
**Depends on:** nothing pending. Plays nicely with the niggle plan (injuries deliberately excluded from memories to avoid double-surfacing).

**Claude Code hand-off prompt:**
> Execute outputs/long-term-memory-implementation-plan-2026-07-02.md step by step. Step 0 verification first, findings recorded in the doc. Steps 2 and 6 change a prompt in _shared/prompts/ — the CI eval gate must pass before deploy. Do not skip step 7 (Model of You visibility); memory ships only with athlete control.

---

## Implementation status (2026-07-02)

Steps 0–7 are **implemented, typechecked, and unit-tested green** (70 passing
tests across the touched suites). Step 8 (prod push) is **team-gated** by hard
rule #9 and is prepared but not executed here. Files landed:

**Migrations (append-only, both parse via real PG parser):**
- `20260702190000_user_memories_hygiene.sql` — adds `status`, `source`,
  `their_words`, `memory_date`, `last_confirmed_at`, `mention_count`; backfills
  `source='chat_regex'` + seeds `last_confirmed_at`; adds "Users delete own
  memories" DELETE policy + a partial active-category index. **Note vs plan:**
  added a `their_words` column the plan's illustrative SQL omitted — episodes
  need the verbatim phrase as a first-class field (the writer inserts it, the
  Read renders it, Model of You quotes it).
- `20260702191000_consolidate_memories_cron.sql` — weekly (`Sun 04:30 UTC`)
  pg_cron fan-out to `consolidate-memories`, mirroring the nightly-snapshot
  cron (dynamic Vault secrets, async `net.http_post` per athlete with active
  memory).

**Backend (Deno/TS):**
- `_shared/prompts/process-training-memo.v3.ts` — v2 + the `memory_candidates`
  field, guardrails (athlete's words only; no psych/health inference; episodes
  distinctive; `[]` freely), and 3 new worked examples (durable facts, episode,
  transient). Registered in `prompt-library.ts`; memo function now loads v3.
- `_shared/memoryWriter.ts` (+ `.test.ts`, 16 tests) — pure `planMemoryWrites`
  (dedup-or-reinforce, token-overlap ≥ 0.7, within-batch collapse, transient
  expiry, episode memory_date) + never-throws `writeMemoryCandidates`. Wired
  into `process-training-memo/index.ts` after the niggle writer.
- `_shared/memoryConsolidation.ts` (+ `.test.ts`, 8 tests) + edge function
  `consolidate-memories/index.ts` — merge near-dups / archive expired +
  stale-low-importance / cap per category; **idempotent** (pinned).
- `_shared/memorySelection.ts` (+ `.test.ts`, 7 tests) — quota selection
  (3 constraint / 3 preference / 2 life / 2 pr·race / 2 episode; gear not
  surfaced) by importance × recency, plus `buildYearAgoArc`.
- `_shared/athlete-state.ts` — active-only memory read (wider columns,
  limit 60), quota-selected + episode + `STILL LEARNING YOU` render, block
  window widened 168→365d (PaceEngine sliced back to 168d so pace zones are
  unchanged), `year_ago` field + "this time last year" line. Prompt-budget
  test measures cost: memory-rich state renders **well under the 1,800-token
  ceiling** (no finite budget needed yet).
- `_shared/memory.ts` — legacy chat-regex path now stamps `source='chat_regex'`.

**iOS (Swift):**
- `RunningLog/Coaching/ModelOfYou/ModelOfYouMemories.swift` — `MemoriesCard`
  summary + `MemoriesListView` (grouped by category, athlete's words + episode
  date, **swipe-to-forget** DELETE via the new RLS policy). Read + delete only.
  Wired into `ModelOfYouView` (folder is a synchronized Xcode group — the new
  file is auto-included). Swift not compiled here (no Linux toolchain); SDK
  calls + Post Run Drip tokens matched to existing compiling code.

**Evals:** `_evals/cassettes/process-training-memo.v3/` — 6 authored cassettes
(durable facts, episode, mundane→[], health-speculation-bait→[], + the two v2
niggle regression guards). Valid JSON; the CI eval-coverage gate would PASS
(dir non-empty for the touched v3 prompt).

### Step 8 — deploy checklist (team executes; hard rule #9)

Prereqs already true: Vault has `supabase_url` + `service_role_key` (the other
crons use them). Order matters — **migrations first**, then functions:

1. Commit everything on a branch; open a PR. Confirm CI eval gate is green
   (v3 cassette dir present).
2. `supabase db push` from the committed SHA (applies the two migrations —
   the `status`/`their_words` columns must exist before the new athlete-state
   read runs).
3. Deploy edge functions: `process-training-memo`, `consolidate-memories`
   (new), `rebuild-athlete-state`, `coaching-daily-read`, `coaching-agent`
   (the last three import the changed `athlete-state.ts`).
4. Verify the weekly cron is scheduled: `SELECT jobname FROM cron.job WHERE
   jobname = 'weekly-consolidate-memories';`
5. **Record the v3 cassettes for real** (needs `GEMINI_API_KEY`):
   `GEMINI_API_KEY=… deno run -A _evals/record.ts process-training-memo.v3`
   then eyeball them, and do the Step 6 manual review of 3–5 Reads against
   `docs/coaching/principles.md` (callbacks warm not surveilled; no
   memory-based prescriptions; episodes quoted verbatim).
6. Smoke test: record a memo containing a durable fact → confirm the
   `user_memories` row (`source='memo_llm'`), the next Read's callback, and the
   Model of You listing; re-mention it → confirm reinforcement (mention_count↑,
   no dup row) rather than a second row.

### Open follow-ups (non-blocking)
- Live cassette recording + human Read review (step 5 above) — needs the API
  key and a person; can't be done from this environment.
- Pre-existing, unrelated: the `rateLimit.contract.test.ts` "no LLM-calling
  function is silently un-rate-limited" test already fails on two untracked
  functions in the tree (`correct-workout-structure`, `ingest-manual-workout`)
  — not touched by this work, flagged for whoever owns them.
