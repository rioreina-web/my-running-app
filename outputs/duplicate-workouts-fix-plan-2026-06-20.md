# Duplicate workouts & the empty rep sheet — fix plan

**Date:** 2026-06-20
**Status:** Plan, pre-implementation. No code or data changed yet.
**Trigger:** A workout opened to "No rep-level splits for this run — it reads
as a steady effort" when it should have shown a full rep-by-rep sheet.

---

## 1. TL;DR

The same physical run can land in `training_logs` **two or three times** —
once from Strava, once from HealthKit (`auto_sync`), once from a voice log —
because each writer only dedupes against *its own* source. Only the Strava
copy carries GPS lap data (`running_workout_laps`), so only it can draw a rep
chart. The workout list and the rep sheet do **not** dedupe, so a lap-less
copy is shown and is tappable. Tapping it opens a sheet that finds zero reps
and prints the misleading "reads as a steady effort" message — which implies
the run was easy when really the splits just live on a different copy of the
same run (or were never captured).

This is a **known, partially-addressed** problem. The code already contains
three dedup implementations; none of them is applied to the rep surface, and
none of them stops the duplicate rows from being written in the first place.

---

## 2. Root cause, precisely

Two independent gaps stack up:

**Gap A — the app keys display on workout *type*, but split data depends on
workout *source*, and nothing reconciles the two.** A voice-logged interval
session is `workout_type = interval` (correct) but `source = voice_log` (no
laps). It passes the type filter in `WorkoutsAndRepsSection`, becomes a
tappable row, and opens a rep sheet built for data it doesn't have.

**Gap B — duplicates are created at write time and never merged.** Each writer
dedupes only against itself:

- `strava-sync` (`supabase/functions/strava-sync/index.ts`) checks for an
  existing row by `vital_workout_id` so it won't re-import the *same Strava
  activity* twice — but it does not check whether a `voice_log` or `auto_sync`
  row already exists for that run.
- The HealthKit/`auto_sync` writer (`RunningLog/Services/WorkoutSyncService.swift`)
  and the voice writer (`upload-voice-memo` / `process-training-memo` /
  `VoiceLogViewModel.swift`) do the same within their own lanes.

So one run accumulates parallel rows that differ in timestamp and source but
describe the same activity.

### What already exists (and why it doesn't save us)

There are **three** dedup implementations in the repo, all read-time or
display-time, none at the writer, and none on the rep surface:

| Implementation | Language | Where it's used | Covers the rep sheet? |
|---|---|---|---|
| `dedupBySourcePriority` (`_shared/shared/dedup.ts`) | TS | analytics builders `buildLoadMetrics`, `buildBlocks` | No |
| `dedupedByPhysicalWorkout` (`App/LogDedup.swift`) | Swift | `TrainingTabView.summedMiles`, `TrainingPaceAnalysisSection` (totals + pace chart) | No |
| `vital_workout_id` unique check (`strava-sync`) | TS | Strava re-import guard only | No |

`LogDedup.swift`'s own header says it best: *"NOT a substitute for backend
dedup. WorkoutSyncService still needs to stop creating the duplicates in the
first place; this just keeps the display honest while that lands."* That
backend fix never landed — this plan lands it.

The two source-priority ladders also disagree on numbers (dedup.ts:
strava 4 / auto_sync 3 / voice_log 2 / check_in 1; LogDedup: strava 3 /
auto_sync 2 / voice_log 1). Same ordering, but duplicated logic that can
drift. Consolidating them is part of the fix.

---

## 3. Evidence (from your data, 2026-06-20)

- Strava sync began **2026-03-25**; voice logs go back to **2026-01-17**.
  Every quality run before late March has no Strava counterpart to pull splits
  from — those lap-less rows are *genuine standalone records*, not duplicates.
- Of your recent quality workouts, the ones with no laps are exactly the
  `voice_log` / `auto_sync` rows; every `strava` row has laps. The split is
  clean along source.
- **How many rows are true duplicates is currently uncertain.** A loose match
  (whole-mile bucket) over-counts genuine doubles days (warm-up + main + cool-
  down). A tight match (±0.1 mi, same calendar day) under-counts timezone-
  split runs (e.g. a run at 00:11 UTC is the prior evening locally, so the
  Strava and HealthKit copies fall on different calendar dates). **Phase 3
  must measure this properly with the real matching rule before any deletion.**

---

## 4. The merge rule (shared by all three phases)

Every phase needs one agreed definition of "same run" and "which copy wins."
Define it once, reuse it everywhere.

**Two rows are the same physical run when** they share a calendar day (with a
tolerance that crosses midnight to catch timezone splits — match on a
±90-minute *start-time* window rather than raw calendar date where start time
is available) **and** distance within 0.2 mi **and** duration within 2 min.
This mirrors `dedupBySourcePriority`, plus the timezone tolerance it lacks.

**The canonical (kept) row is the highest-priority source:** `strava` >
`auto_sync` > `voice_log` > `check_in`. Strava wins because it carries laps +
streams.

**Crucially, keeping the Strava row must not lose the voice signal.** The
voice copy may hold the qualitative fields the product is built on. When
collapsing, carry these from the retired voice/auto_sync row onto the
canonical row if the canonical row's are empty:

`notes`, `cleaned_notes`, `workout_notes`, `mood`, `felt_rpe`, `rpe_tags`,
`rpe_pull_quote`, `transcript_url`, `parsed_structure`.

So the operation is **merge-then-retire**, never blind delete.

---

## 5. Phase 1 — UI (safe, no data touched)

Goal: stop the symptom you hit today. Ship-able on its own, reversible, zero
data risk.

1. **Fix the empty-state copy** in `WorkoutRepReceiptView.swift` (the
   `loaded && reps.isEmpty` branch, ~line 254). Distinguish the two reasons
   reps can be empty:
   - Has GPS source but genuinely no rep structure → keep a "steady effort"
     style message.
   - No GPS data at all (voice_log / no laps) → say so plainly, e.g. *"No GPS
     splits — this run was logged by voice"*, and surface the voice
     transcript / notes / mood instead of a blank chart.
   Per repo hard rule #8, this is an empty-state surface — use the empty-state
   component pattern (eyebrow + plain-prose nudge), not an em-dash placeholder.
2. **Gate the rep sheet / make the list dedupe-aware.** In
   `WorkoutsAndRepsSection` (`load()`, lines ~106-120), apply the same
   physical-workout dedup the Training tab already uses so the canonical
   (lap-bearing) copy is the one listed and tapped. A voice-only run still
   shows in the journal, but it shouldn't be the row that opens an empty rep
   chart.
3. **Apply `dedupedByPhysicalWorkout` to the tappable Log feed**, not just the
   mileage totals — today totals are deduped but the row list isn't, which is
   how a duplicate stays tappable.

Acceptance: every workout row that opens the rep sheet either shows a real
chart or a source-appropriate message; no run shows "steady effort" solely
because its splits live on another copy.

## 6. Phase 2 — Ingestion (the real root cause; medium risk)

Goal: stop creating new duplicates. After this lands, the display dedup
becomes a safety net rather than the only line of defense.

1. **Promote the merge rule (§4) into a shared backend helper** — extend
   `_shared/shared/dedup.ts` from an in-memory collapse into a write-time
   "find existing canonical row for this run" lookup.
2. **At each writer, look before inserting:**
   - `strava-sync`: before inserting a new activity, look for an existing
     `voice_log` / `auto_sync` row for the same run. If found, **update that
     row in place** to Strava (attach laps/streams, set `source = strava`,
     preserve voice fields per §4) instead of inserting a parallel row.
   - `WorkoutSyncService` (HealthKit `auto_sync`) and the voice path: before
     inserting, if a higher-priority row already exists for the run, attach to
     it / annotate it rather than inserting.
3. **Consolidate the two source-priority ladders** (dedup.ts vs LogDedup.swift)
   so backend and client agree. One ordering, ideally one source of truth the
   Swift side mirrors.
4. **Repo discipline:** new/changed edge-function logic follows
   `_shared/{auth,cors}.ts` patterns and ships with unit tests
   (`dedup.test.ts` already exists — extend it). No prompt files are touched
   by this work, so the eval-coverage CI gate does not apply; if that changes,
   add cassettes first (hard rule #3, and `.github/scripts/check_eval_coverage.py`).

Acceptance: a run that exists on Strava and HealthKit and voice produces
exactly **one** `training_logs` row, Strava-sourced, with the voice notes
preserved.

## 7. Phase 3 — Historical cleanup (highest risk; production data migration)

Goal: collapse the duplicates already in the table, losslessly. Do this
**last**, after Phase 2 stops new ones, so you clean a closed set.

1. **Identify, then review — do not auto-delete.** Write a *read-only* query
   using the §4 matching rule (including the timezone-crossing window) to list
   candidate duplicate clusters. Eyeball the list. This is also where the "how
   many?" question finally gets a real answer. Expect a small number, not
   hundreds.
2. **Merge-then-retire** each confirmed cluster: copy voice fields (§4) onto
   the canonical Strava/`auto_sync` row, then retire the duplicate.
3. **Repoint foreign keys before retiring a row.** At least `body_mentions`
   references `training_log_id` (niggles), and `running_workout_laps`,
   `workout_features`, and `workout_reconciliations` reference `workout_id`.
   A duplicate that owns niggles must hand them to the canonical row first, or
   the niggle timeline loses entries. Audit all FKs into `training_logs`
   before writing the migration.
4. **Prefer soft-retire over hard delete** for the first pass — e.g. a
   `superseded_by uuid` column — so the operation is auditable and reversible.
   A hard delete can follow once you trust the result.
5. **Repo rules are strict here:**
   - Append-only migration, named `YYYYMMDDHHMMSS_descriptive.sql`
     (hard rule #5).
   - Any new column ships with RLS in the same migration
     (hard rule #1, `docs/conventions/rls-checklist.md`).
   - Reaches prod **only** via `supabase db push` from a committed SHA — no
     dashboard SQL editor, no MCP `apply_migration` against prod (hard rule
     #9). The ledger has diverged before; don't reopen that.
   - Take a backup / snapshot of `training_logs` before running it.

Acceptance: one row per physical run; mileage totals drop to the true value;
no niggle or lap data orphaned.

---

## 8. Suggested sequencing

1. **Phase 1** first — it's safe, reversible, and fixes what you actually saw.
   Ship it alone.
2. **Phase 2** next — stops the bleeding so cleanup is a one-time job.
3. **Phase 3** last — clean a now-closed set, carefully, behind a backup.

Phases 1 and 2 can proceed in parallel if you want; Phase 3 should wait for 2.

## 9. Open decisions for you

- **Voice-only runs (pre-Strava, or days you didn't run with Strava):** keep
  showing them in the journal with their transcript, just without a rep chart?
  (Recommended yes — they're real training history.)
- **Soft-retire vs. hard-delete** in Phase 3 — start reversible, or go
  straight to delete once verified?
- **Priority of `auto_sync` vs `voice_log`** when no Strava row exists: today
  both ladders rank HealthKit above voice. Confirm that's right for *your*
  data (HealthKit distance vs. what you said out loud).
