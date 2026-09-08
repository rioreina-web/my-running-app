# The Read — working handoff (2026-06-15)

Context doc for continuing the daily Read / coaching-intelligence work in a
new chat. Repo: `~/my-running-app`. Test user id:
`03857bf3-6276-4634-b3cc-15cc6d0bc653`. Supabase project: `aqdijapxmjqaetursrde`.

## The goal (one line)

Make the daily Read analyze a runner **like a coach** — reconcile objective
signal (pace-at-effort over time, HR, fade, volume) with subjective signal
(sleep, work/family stress, travel, fatigue, mood, how the workout *felt*)
into one fitness verdict with calibrated confidence. Patterns over
months/years, not 14-day windows. AI advises, never prescribes.

## Current state of the Read (what it actually looks like)

Pulled live 06-15 from `daily_coaching_reads`:

> **"Active niggles, readiness is low."**
> Active achilles + knee niggles, readiness 4/10. Past week: 58.2 mi / 8 runs,
> 72.7% easy, 2 quality. Jun 9 threshold faded −11.9% over 5 reps with +5.6% HR
> drift; contrasts Jun 2 threshold (−6.5% fade, 0% drift, 8 reps). Soft question.
> — MEDIUM confidence · model `gemini-2.5-flash` · `cant_see: NO RECENT MOOD`

**Verdict:** much better than the old paragraph — it reads laps now and
compares two sessions over time (real coach move). BUT it's 100% objective,
no subjective ("NO RECENT MOOD"), no fitness verdict, and **it's still running
the OLD prompt** — my new reasoning isn't deployed.

## What's been DONE (landed)

- **Lap-first workout classifier** (`_shared/workoutSegmentation.ts`) — classifies
  by pace zone per lap, not by label on per-mile splits. Wired into
  `compute-workout-features`. Tests 5/5. This is why reps/fades now show.
- **Lap ingestion fixed** — trigger `trg_sync_workout_laps` (migration
  `20260613250000_running_workout_laps_ongoing_writer.sql`) parses laps on
  insert/update of external_streams + global backfill. APPLIED LIVE.
- **Cross-source dedup** — migrations `20260613220000` (one-time heal),
  `...230000` (unique index on user_id+vital_workout_id), `...240000`
  (recurring 30-min sweep). Applied.
- **Token-truncation fixes** — `generate-workout-insight` maxOutputTokens
  100→800; Read router cap was the 502 cause (already 8000).
- **iOS surfaces built** — `Analysis/WorkoutRepChart.swift` (per-rep bar chart,
  HR overlay, zone lines, heat toggle, ANALYSIS + SPLITS cards, type override
  via confirmationDialog); `Training/Analytics/WorkoutsAndRepsSection.swift`
  (quality-workout list → rep chart sheet); THE READ tab →
  `Coaching/ModelOfYou/ModelOfYouView.swift` (cards surface).

## What's WRITTEN but NOT deployed (prompt changes — need deploy + evals)

Both are prompt-file edits only; the live edge functions still run old text.

1. **`_shared/prompts/process-training-memo.v1.ts`** — expanded `extracted_data`
   with the full subjective set: `felt_vs_looked` (easier/about right/harder
   than it looks — the single most coach-relevant field), `work_stress`,
   `life_stress`, `travel`, `fatigue`, `soreness[]` (own words, no diagnosis),
   `illness`, `motivation`, `sleep_hours`. Note added that subjective fields
   matter as much as numbers.
2. **`_shared/prompts/daily-read.v3.ts`** — added directives: LIFE CONTEXT
   (read sleep/travel/work-stress/illness, lead feeling-first), DEPTH
   (compare over time + explain *why* + tie to arc), and FITNESS: judge it
   like a coach (objective × subjective) — pace-at-effort is the key objective
   signal, overlay subjective every time, *reconcile don't report both*,
   calibrate confidence, frame as trajectory. Schema unchanged (stays v3 by
   file convention — only bump version on schema change).
3. **`coaching-daily-read/index.ts`** — `MAX_VOICE_MEMOS` 6→12,
   `VOICE_MEMO_LOOKBACK_DAYS` 14→60 (so the Read sees a real window).

**To ship:** add eval cassettes under `_evals/cassettes/<prompt-name>/`
(CI gate, hard rule #3), then `supabase functions deploy coaching-daily-read`
and `process-training-memo`, then regenerate the cached Read.

## What's MISSING (priority order)

1. **Subjective input isn't flowing.** No voice memos → "NO RECENT MOOD." All
   the new extraction has nothing to extract. *User owns this* — they said
   "I'll start populating them again." Biggest single unlock.
2. **New prompt not deployed** (see above). Needs evals + deploy.
3. **No pace-at-HR / decoupling fitness trend.** The Read can compare two
   sessions' fade but has no "same pace, HR trending down over 8 weeks =
   fitter" rollup. This is the **objective backbone of the fitness verdict** —
   captured per-rep, never aggregated. **HIGHEST-LEVERAGE BUILD; reliable data
   work.** ← recommended next.
4. **Stale block/quality rollups.** `recent_blocks` shows 0 quality despite
   detected workouts → month-over-month comparisons will be wrong until
   re-derived from corrected `workout_features`.
5. **Editable workouts not built.** Spec + mock handed to Xcode agent:
   `outputs/edit-workout-spec-for-xcode-agent.md`, `outputs/edit-workout-mock.html`
   (collapsible "Correct or add detail" → Gemini-parsed describe box; use
   Form+Picker, NOT inline Menu in a sheet).

## Recommended next step

Build **#3 the pace-at-HR fitness signal** (aggregate per-rep pace+HR into a
trend: same pace → HR direction over 4/8/12 weeks, with decoupling). That's
the objective half the new Read prompt already expects, and it's data work
that can be done reliably (vs. blind iOS UI loops). Then #4 (fix stale blocks)
so "compare over time" is true, then deploy the prompts (#2).

## Hard rules to respect (from CLAUDE.md)

- Prompt change ⇒ eval cassette in `_evals/cassettes/<prompt>/` before ship (CI enforced).
- Migrations via `supabase db push` from a committed SHA only — no dashboard/MCP apply to prod.
- Every table ships RLS in same migration. AI never diagnoses/prescribes.
- Predictions = range + confidence, never a point estimate. No em-dash empty states.
- Niggles: closed vocab, quote verbatim, surface-never-interpret.

## Key files

- `supabase/functions/_shared/prompts/daily-read.v3.ts`
- `supabase/functions/_shared/prompts/process-training-memo.v1.ts`
- `supabase/functions/coaching-daily-read/index.ts`
- `supabase/functions/_shared/workoutSegmentation.ts`
- `supabase/functions/compute-workout-features/index.ts`
- `supabase/functions/generate-workout-insight/index.ts`
- `RunningLog/RunningLog/Analysis/WorkoutRepChart.swift`
- `RunningLog/RunningLog/Coaching/ModelOfYou/ModelOfYouView.swift`
- `outputs/edit-workout-spec-for-xcode-agent.md`, `outputs/edit-workout-mock.html`

## Note on division of labor

Two agents on this repo: **this chat (me)** = data/SQL/edge-function/prompt
work via Supabase MCP — reliable. **Opus via Xcode** = SwiftUI compile/tap
loop. Hand interactive iOS UI to the Xcode agent with a spec + HTML mock;
keep data/diagnosis/prompt work here.
