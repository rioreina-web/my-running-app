# Implementation plan — Niggle classifier rewrite (audit fix #2)

**Date:** 2026-07-02
**Goal:** replace the regex-only body-mention detection with LLM classification at memo-processing time, so niggle patterns are real: closed ~30-part vocabulary, left/right tracking, verbatim quotes. Kills the current failure mode where "left knee" and "right knee" merge into one false "pattern" — the kind of confidently-wrong observation hard rule #2 exists to prevent.

**Context.** The `body_mentions` table (migration `20260612130000`) already has a `side` column — designed for laterality, never populated, because the only writer today is the regex scan inside `rebuildAthleteState` (athlete-state.ts, "Possible-injury scan" block): ~20 keywords, no sides, notes-text only, 30-day lookback, and it silently no-ops under RLS on the anon path. Meanwhile the memo pipeline's LLM already extracts `soreness: ["left knee", "calves"]` into `extracted_data` — the athlete's own words, with sides — and nothing consumes it. Note: CLAUDE.md references `outputs/body-mentions-design.md` for the original spec; that file is absent from the repo — this plan re-derives the contract from the table schema's comments and hard rule #2.

**Contract (unchanged):** detection, not diagnosis. Closed vocabularies for body_area and severity_hint. Verbatim quotes, never coerced. Surface patterns; never name a condition, never recommend an action.

Each step is independently shippable with a "done when."

---

> **STATUS 2026-07-02:** Steps 1–4 are built, typechecked, and tested
> locally (44 tests green; migration parses against the real PG grammar).
> Step 0's queries and Step 5's deploy touch production and are pending
> your Supabase project/credentials. Full runbook + findings template:
> `outputs/niggle-classifier-implementation-status-2026-07-02.md`. Step-0
> query answers are still TO RECORD (needs prod access).

## Step 0 — Verify current data (read-only, ~15 min)

1. What's in `body_mentions` now? `select body_area, side, source, count(*) from body_mentions group by 1,2,3;` — expect side always null, source always `notes_scan`.
2. How often do real memos populate `extracted_data.soreness`? Count over the last 90 days. If it's rare, the memo prompt's soreness instruction may need strengthening in step 2 (more explicit examples), not just consuming.

**Done when** both answers are recorded at the top of this doc.

## Step 1 — Shared vocabulary module: `_shared/bodyVocabulary.ts`

One source of truth both writers use, pure functions, no I/O:

- `BODY_AREAS` — closed list, ~30 entries. The current regex 20 (achilles, calf, shin, knee, hamstring, quad, glute, hip, piriformis, lower back, back, foot, arch, plantar, heel, ankle, IT band, hip flexor…) plus the gaps: groin, adductor, soleus, peroneal, toe, top of foot, SI joint/sacrum, neck, shoulder, hip labrum → hip. Each entry: canonical key + accepted synonyms ("itbs" is NOT a synonym — diagnoses are rejected, not mapped; "IT band" the location is fine).
- `SEVERITY_HINTS` — closed: `tight | sore | pain | sharp` with the word-mapping table from the current scan.
- `normalizeBodyMention(raw: string): { body_area: string; side: "left"|"right"|null } | null` — maps free text ("left knee", "R achilles", "my right calf") to the closed vocabulary; returns **null for anything unmappable** (e.g. "subtalar joint" maps to ankle only if the synonym table says so; unknown terms are dropped, never invented).
- Unit tests: synonym mapping, side extraction (left/right/L/R/both), rejection of diagnoses ("ITBS", "tendinitis" as *area* input), rejection of unknown terms, case/whitespace tolerance.

**Done when** `deno test _shared/bodyVocabulary.test.ts` passes with ≥15 cases.

## Step 2 — Memo pipeline becomes the classifier + writer

1. **Prompt change** (`_shared/prompts/process-training-memo.v1.ts` → bump to v2): extend the `soreness` instruction to emit structured objects: `[{ "location": "left knee", "their_words": "knee felt cranky after mile 8", "severity_word": "cranky" }]`. Keep it the athlete's framing; explicitly instruct: never output a diagnosis or condition name.
   ⚠ This file lives in `_shared/prompts/` — **the CI eval gate fires** (hard rule #3). Cassette work is step 4, and must land in the same PR.
2. **Writer** in `process-training-memo/index.ts` after analysis: run each soreness entry through `normalizeBodyMention` + severity mapping; upsert valid ones to `body_mentions` with `training_log_id`, `side`, `verbatim_quote` (their_words, ≤400 chars), `source: "memo_llm"`. The function runs service-role, so RLS is not the problem it is on the rebuild path. Unmappable entries are logged and dropped — the closed vocabulary is enforced in code, not trusted to the LLM.
3. `volume_context` stays null on this path (it's a rebuild-time computation; the recurrence view doesn't need it).

**Done when** a test memo mentioning "right calf was tight" produces a `body_mentions` row with `body_area: calf, side: right, severity_hint: tight, source: memo_llm` and the verbatim words.

## Step 3 — Athlete-state adjustments (demote the regex, surface the side)

1. **Skip voice rows in the regex scan** — in the possible-injury scan, skip logs whose `source` is `voice_log`/`voice_memo`/`check_in`: the memo path now owns those. The regex remains the backfill for *typed* manual notes and Strava descriptions. (The unique index on `(user_id, training_log_id, body_area)` already prevents double-writes; this avoids double-*detection* semantics drifting.)
2. **Regex writer adopts the shared vocabulary** — replace the inline `bodyParts` array with `BODY_AREAS` synonyms and populate `side` when the nearby text says left/right.
3. **Recurrence groups by area + side** — `niggle_recurrence` keys on `body_area + side` (null side groups separately as "unspecified"), and the prompt line renders it: `left knee: 3× (…)`. Update the niggle prompt section and the `body_mentions` history read accordingly.
4. Tests: extend `athlete-state.test.ts` — left knee ×2 + right knee ×1 must yield two recurrence entries, not one three-count entry.

**Done when** those tests pass and the regex scan provably skips memo-sourced rows.

## Step 4 — Eval cassette + principles review (hard rule #3, CI-enforced)

1. Update/re-record the `process-training-memo` cassette(s) in `_evals/cassettes/process-training-memo/` for the v2 prompt (`_evals/record.ts` with `GEMINI_API_KEY`). Include at least: a memo with a lateral mention, a memo using a diagnosis word ("my ITBS is back" → verbatim quote preserved, area mapped to IT band, no diagnosis emitted by the system), and a memo with no body mentions.
2. Manual review against `docs/coaching/principles.md`: generated Reads referencing niggles must quote, count, and locate — never diagnose, never prescribe.

**Done when** CI's eval-coverage gate passes and the diagnosis-word case behaves correctly.

## Step 5 — Migration (small) + deploy

1. Migration: none strictly required (`side` and `source` columns exist). Optional hygiene in the same PR: backfill `side` to null-safe default and add a `check (severity_hint in ('tight','sore','pain','sharp'))` constraint — append-only migration per hard rule #5.
2. Deploy order: `supabase db push` (if the optional migration is included) → `supabase functions deploy process-training-memo rebuild-athlete-state coaching-daily-read`.
3. Verify: record a memo with a lateral niggle; confirm the `body_mentions` row, then rebuild state and confirm `niggle_recurrence` shows the sided entry.

**Done when** the live path works end-to-end and old regex-era rows still render (unsided, grouped as "unspecified").

---

**Effort estimate:** 1–2 focused sessions. Step 1 and step 3 are mechanical; step 2's prompt change plus step 4's cassettes are where the care goes.

**Out of scope:** backfilling historical memos through the new classifier (possible later — re-run stored `cleaned_notes` through `normalizeBodyMention`; decide after seeing how much history matters to the Trends niggle tile), and the Trends NIGGLES tile UI (already reads `body_mentions` via `trends-timeline`; it inherits sides for free once rows carry them).

**Claude Code hand-off prompt:**
> Execute outputs/niggle-classifier-implementation-plan-2026-07-02.md step by step. Run step 0's queries first and record findings in the doc. All tests green before each step's commit; the step-4 eval cassettes are mandatory before deploying the prompt change (CI enforces this).
