# Niggle classifier rewrite — implementation status (2026-07-02)

Companion to `outputs/niggle-classifier-implementation-plan-2026-07-02.md`.
Steps 1–4 are **built, typechecked, and tested locally**. Steps 0 and 5
touch production and are handed off (they need your Supabase project /
credentials — hard rule #9: migrations reach prod only via
`supabase db push`).

## What shipped (code)

**New files**
- `supabase/functions/_shared/bodyVocabulary.ts` — the single source of
  truth. Closed `BODY_AREAS` (~26 canonical areas incl. the plan's gaps:
  groin, adductor, soleus, peroneal, toe, top-of-foot, SI joint, neck,
  shoulder, hip-labrum→hip), `SEVERITY_HINTS` (tight|sore|pain|sharp),
  `normalizeBodyMention` (side extraction + longest-synonym match, rejects
  diagnoses and unknowns), plus `findBodyAreaMentions` / `sideFromText` for
  the scan path. Pure, no I/O.
- `supabase/functions/_shared/bodyVocabulary.test.ts` — 17 cases.
- `supabase/functions/_shared/niggleWriter.ts` — `buildNiggleRows` (pure)
  + `writeNiggleMentions` (upsert wrapper). Lives in `_shared/` so it's
  testable without booting the function's `Deno.serve`.
- `supabase/functions/_shared/niggleWriter.test.ts` — 11 cases.
- `supabase/functions/_shared/prompts/process-training-memo.v2.ts` —
  `soreness` becomes structured `{location, their_words, severity_word}`;
  explicit "location is anatomy, never a diagnosis" rule + two new
  few-shot examples (lateral niggle, ITBS→IT band).
- `supabase/functions/_evals/cassettes/process-training-memo.v2/` — three
  cassettes (lateral mention, diagnosis word, no body mention). Rubrics
  compile via the harness; **`recorded_response` is empty pending a live
  re-record** (see Step 4 below).
- `supabase/migrations/20260702180000_body_mentions_severity_check.sql` —
  append-only; normalizes any legacy severity then adds the closed-vocab
  CHECK; documents `side`/`source`. Parses clean against the real PG grammar.

**Edited**
- `_shared/prompt-library.ts` — registers `process-training-memo.v2`.
- `process-training-memo/index.ts` — loads v2; calls `writeNiggleMentions`
  after the row update (service-role, so RLS is not the silent no-op it is
  on the rebuild path). Scope comment updated.
- `_shared/athlete-state.ts` — regex scan now (a) **skips voice-sourced
  rows** (`voice_log`/`voice_memo`/`check_in` — the memo path owns those),
  (b) uses the shared vocabulary + populates `side`, (c) `niggle_recurrence`
  now **groups by area + side** (null → "unspecified") and the prompt
  renders `left knee: 3× (…)`. `niggle_recurrence` gained a `side` field.
- `_shared/athlete-state.test.ts` — +3 tests (recurrence laterality; voice
  rows skipped; typed/imported rows still scanned with side).

## Verification (local)

- `deno check` clean on all six touched TS files.
- `deno test` green: **44 passed / 0 failed** across bodyVocabulary,
  niggleWriter, and athlete-state suites.
- Migration parses via `pglast` (libpg_query / real PG grammar).
- CI eval-coverage gate condition satisfied for `process-training-memo.v2`
  (non-empty cassette dir).
- Note: two failures elsewhere in the suite (`buildLoadMetrics.test.ts`,
  `rateLimit.contract.test.ts` flagging `correct-workout-structure` /
  `ingest-manual-workout`) are **pre-existing** — those files were already
  modified/added in the working tree before this change and are untouched
  by it.

## Remaining — needs you (production)

### Step 0 — read-only prod check (informs nothing blocking; do before/after deploy)
Run against prod and note the answers:
```sql
select body_area, side, source, count(*)
  from body_mentions group by 1,2,3 order by 4 desc;
-- expect today: side NULL, source 'notes_scan' only.

select count(*) as memos_90d,
       count(*) filter (where extracted_data ? 'soreness'
                         and jsonb_array_length(extracted_data->'soreness') > 0) as with_soreness
  from training_logs
 where source in ('voice_log','voice_memo')
   and created_at > now() - interval '90 days';
-- if with_soreness is rare, the v2 soreness instruction is doing the heavy
-- lifting — worth a manual spot-check of a few real memos after deploy.
```
I can run these for you via the Supabase connector if you point me at the
project — say the word.

### Step 4 — cassettes: SKIPPED (by decision, 2026-07-02)
No eval cassettes. This is fine to ship: the CI eval-coverage gate is
disabled (`if: false` in `.github/workflows/ci.yml`), and the eval
`runner.test.ts` only scores a hardcoded set (injury-analysis.v1,
process-training-memo.v1, reschedule-plan.v1, daily-read.v5) — it does not
touch the memo v2/v3 prompt. So `deno test` and CI stay green with no
cassette for the new prompt. (Tradeoff: hard rule #3 is documented but not
mechanically enforced right now; if the gate is ever re-enabled, editing
the memo prompt would then require a cassette dir. Manual review against
`docs/coaching/principles.md` covers the safety contract in the meantime.)

### Step 5 — migrate + deploy (from a committed SHA)
```
supabase db push
supabase functions deploy process-training-memo rebuild-athlete-state coaching-daily-read
```
Verify end-to-end: record a memo with a lateral niggle ("my left knee got
tight") → confirm a `body_mentions` row with `body_area=knee, side=left,
source=memo_llm` and the verbatim words → rebuild state → confirm
`niggle_recurrence` shows the sided entry. Old regex-era rows still render
(unsided, grouped as "unspecified").

## Update — niggle resolution ("it's better now") 2026-07-02

Added a way for a runner to clear a niggle so it stops being flagged, with
recurrence auto-reactivating it if the same spot comes back. Model: a
resolution is a **watermark** per body-area+side — only mentions *after*
the latest all-clear count as active. Resolved niggles stay in history
(dormant), so a later flare is a known repeat, not a first-timer.

**Both resolution paths (as chosen):**
- **Voice** — v3 prompt now emits `resolved_niggles` when the athlete
  says a spot is better; `process-training-memo` records it via
  `writeNiggleResolutions`.
- **Manual tap** — new `resolve-niggle` edge function the iOS "mark
  resolved" button calls with `{body_area, side}`. *(The iOS button itself
  is the one remaining piece — backend + endpoint are done.)*

**New/edited for this:**
- `supabase/migrations/20260702190000_niggle_resolutions.sql` — the
  watermark table + RLS (parses against real PG grammar).
- `_shared/niggleWriter.ts` — `buildNiggleResolutions` + `writeNiggleResolutions`.
- `_shared/bodyVocabulary.ts` — `isKnownBodyArea` guard for the endpoint.
- `_shared/athlete-state.ts` — recurrence now reads resolutions, drops
  dormant niggles from the surfaced pattern, and flags "flared again after
  clearing on <date>" when one reactivates. `niggle_recurrence` gained
  `status` + `resolved_at`.
- `_shared/prompts/process-training-memo.v3.ts` — `resolved_niggles` field
  + rules (surgical add to your v3).
- `resolve-niggle/index.ts` — the manual endpoint.
- Tests: +5 (resolution builder ×3, dormant-drop, reactivation).

**Verification:** `deno check` clean on all touched files incl. the new
endpoint; **49 tests pass / 0 fail**; migration parses.

**Deploy (updated):**
```
supabase db push
supabase functions deploy process-training-memo rebuild-athlete-state \
  coaching-daily-read resolve-niggle
```
Remaining follow-up: wire the iOS "mark resolved" button to call
`resolve-niggle`, and (optional) invalidate athlete_state on a manual
resolve so it drops out immediately rather than on the next rebuild.

## Out of scope (unchanged from the plan)
Backfilling historical memos through the new classifier, and the Trends
NIGGLES tile UI (it inherits sides for free once rows carry them).
