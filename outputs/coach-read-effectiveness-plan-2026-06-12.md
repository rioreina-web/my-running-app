# Coach Read — effectiveness overhaul plan

**Date:** 2026-06-12
**Author:** working session with Rio
**Status:** PROPOSED — awaiting sign-off before implementation
**Scope:** the daily "Read" surface on the Coach tab — edge function
`coaching-daily-read`, prompt `daily-read.v2`, and the iOS
`Coaching/Read/*` views.

---

## Why this exists

The Read currently ships facts that are wrong, contradictory, or
un-grounded. A single screen shows the same run three different ways,
labels workouts with a taxonomy the product retired on 2026-05-28, and
prints paces straight from a legacy free-text column without ever
touching the pace engine. The narrative is LLM prose that the
edge-function validator checks only for *citation-id existence* — never
for whether the claims about those workouts are true.

This plan makes the Read trustworthy across four fronts the user asked
for: **data correctness, sharper prose, real grounding/validation, and
a finished UI.**

---

## What's actually broken (root-cause map)

### A. Data correctness

1. **Retired taxonomy.** `EvidenceChip.coachReadTypeLabel`
   (`EvidenceChip.swift:156-174`) hardcodes `TEMPO`, `THRESHOLD`,
   `INTERVAL`, etc. Per CLAUDE.md (2026-05-28), *"Tempo" and "Threshold"
   are dropped as ambiguous — the zone IS the workout label* (MP / HMP /
   LT / 10K / 5K / 3K / Mile + Easy/Moderate/Steady/Long). Nothing maps
   the legacy `training_logs.workout_type` string onto the 10-zone
   system, so the Read displays a vocabulary the rest of the product
   abandoned.

2. **Four competing title/label functions.** The same run resolves
   differently depending on which view renders it:
   - `EvidenceChip.coachReadTypeLabel` — eyebrow label from `workout_type`
   - `EvidenceChip.coachReadDisplayTitle` — first line of `workout_notes`
     (which is often a *parsed plan structure string*, e.g.
     "Tempo: 10 minutes @ ~3:17/km (splits…)" — km units, prescriptive)
   - `CoachReadView.workoutTitle` — `distance + workout_type.capitalized`
     ("6.6 mi Interval")
   - `TrainingLog.workoutTypeLabel` — yet another switch, returns nil on
     unknown types
   Result: the "TUE · INTERVAL" card's eyebrow says INTERVAL, its title
   says "Tempo: …", and its detail sheet says "6.6 mi Interval." Three
   identities, one workout.

3. **Paces are raw column dumps, not computed.** `coachReadMetaLine`
   prints `workout_pace_per_mile` verbatim ("7:30/mi"); the km splits
   leak from a parsed plan note. The pace engine (`pace-engine.ts`,
   `computePaceZones`) and the rich `pace_segments` (effort-classified
   GPS data already on the row) are never used.

### B. Prose quality

4. **Point predictions.** "current predicted 1:12:48" violates hard
   rule #7 (range + confidence, never a point estimate; seconds are a
   math artifact). The prompt *says* "ranges with confidence" but
   nothing strips a point estimate if the model emits one.

5. **Injury-advice drift.** Headline "monitor knee health" + "Keep
   monitoring those knees closely" edges past surface-don't-interpret
   (hard rule #2, Niggles spec). The Read should report the mention, not
   prescribe vigilance.

6. **Echoes bad source data.** Because the context block hands the model
   the legacy label + raw pace ("tempo · 5.8mi @ 7:30/mi"), the prose
   faithfully repeats "a tempo run at 7:30/mi." Garbage in, garbage
   narrated.

### C. Grounding / validation

7. **Validator checks IDs, not claims.** `validateCitations`
   (`index.ts:719`) confirms a cited workout id exists, then stops. It
   never checks that "44.7 miles this week," "53.6 mpw 28-day average,"
   or "7:30/mi tempo" match the underlying rows. The model can cite a
   real workout and still describe it wrong.

8. **Volume/average numbers are unverifiable.** The context block feeds
   per-run lines but no precomputed aggregates, so weekly volume and the
   28-day average in the prose are the model's own arithmetic — not
   computed server-side and not checked.

### D. UI completion

9. **Detail sheet is a stub.** `workoutDetailSheet`
   (`CoachReadView.swift:344-374`, flagged `Minimal v1`) renders a title
   + `cleanedNotes ?? notes` only — so "5.8 mi Tempo" shows a title over
   a blank body when neither field is set, and never shows splits, pace,
   segments, or mood.

10. **Dateline vs. byline mismatch.** Header "THU · JUN 11" (from
    `readDate`) vs. byline "FRI 8:19 AM" / "posted Friday" (from
    `generatedAt`) — two different days on one masthead.

---

## Proposed fixes (phased)

### Phase 1 — Taxonomy + unified workout presentation (iOS, no prompt risk)

The highest-leverage, lowest-risk fix. All client-side; no eval gate.

- **Build one canonical mapper** `WorkoutPresentation` (new file under
  `Coaching/Read/` or `Shared/`) that takes a `TrainingLog` and returns
  a single `{ label, title, metaLine }`, derived in priority order:
  1. `parsed_structure` / `pace_segments` when present (real zone data)
  2. `workout_type` mapped through a **legacy → 10-zone translation
     table** (tempo→MP or HMP by pace, threshold→LT, interval→reps zone,
     etc.) — explicit, with a documented fallback
  3. distance + zone label as last resort
- **Delete the three other functions** (`coachReadTypeLabel`,
  `coachReadDisplayTitle`, `CoachReadView.workoutTitle`,
  `TrainingLog.workoutTypeLabel` usage in the Read path) and route every
  Read view through the one mapper. Card eyebrow, card title, and detail
  sheet now agree by construction.
- **Stop sourcing titles from `workout_notes`** (those are parsed plan
  strings / km splits). Titles come from the mapper.
- **Compute pace through the engine**, not the raw column: format the
  meta line from `pace_segments` or the distance/duration the row
  actually holds, in mi, never echoing km plan-splits.

*Open decision:* the legacy→zone table needs a source of truth. Options:
reuse `derivePaceTableFromGoal`'s zone names and classify each run's
average pace into a zone, or keep `workout_type` but relabel via a fixed
dictionary. Recommend the former (real classification) — flagged in Open
Questions.

### Phase 2 — Server-side aggregates + claim validation (edge function)

Make the numbers true before the model ever sees them.

- **Precompute aggregates** in `buildDailyReadContext` using the
  existing `dataAnalysis.ts` / `weeklyAnalytics.ts` helpers (ACWR,
  volume, 28-day average already live there). Inject them as explicit
  context lines ("This week volume: 44.7 mi. 28-day avg: 53.6 mpw.
  ACWR: 0.83.") so the model quotes computed numbers instead of doing
  its own math.
- **Extend `validateCitations` → `validateClaims`:** after generation,
  re-derive any numeric the prose asserts about a cited workout (pace,
  distance, date) and either (a) strip/flag a sentence whose numbers
  don't match the row within tolerance, or (b) at minimum log a
  mismatch metric. Full sentence-level fact-check is hard; start with
  the structured numbers we already inject (volume, average, predicted
  range) and assert the prose matches them.
- **Kill point predictions at the seam:** post-process the prose for
  `H:MM:SS`-precision finish times and the predicted-time field; require
  the range+confidence shape (reuse `FitnessPredictorService` /
  `fitness-predictor.v1` output). A bare point estimate gets rejected or
  rounded to the range.

### Phase 3 — Prompt v3 (gated on eval harness, per hard rule #3)

CI fails any `_shared/prompts/` change without
`_evals/cassettes/<prompt>/` coverage. So:

- **Author `daily-read.v3.ts`** (keep v2 importable for A/B). Changes:
  - Feed it the *new* zone labels and computed aggregates from Phase 1–2,
    and instruct it to use zone vocabulary, never "tempo/threshold."
  - Tighten the niggle rule to surface-don't-monitor: report the mention
    and (in COACHED/SELF modes) stop; no "keep monitoring" directives.
  - Reinforce range-only predictions with an explicit negative example
    ("never '1:12:48'; always '1:11–1:14, MEDIUM'").
- **Record cassettes** in `_evals/cassettes/daily-read.v3/` covering:
  Maya self-coached happy path, COACHED_MODE no-program, niggle-mention
  (must not prescribe), thin-data LOW confidence, prediction (must be
  range). Run via `_evals/record.ts` with `GEMINI_API_KEY`.
- Manual review against `docs/coaching/principles.md` until cassettes
  are green.

### Phase 4 — Finish the UI

- **Real detail sheet:** the app already has a per-workout pace
  visualization — `WorkoutDetailPlate23` / `WorkoutDetailView` render
  splits and pace from `pace_segments`, and `PaceChartView` /
  `PaceZonesService` hold the athlete zone table. The Read's
  `Minimal v1` stub should reuse these instead of a blank sheet — show
  distance, computed pace, the splits/segments chart, mood, and the
  athlete's verbatim memo. Empty body never renders a lone title.
  - **Model-bridge caveat:** the rich detail views are keyed on
    `RunningWorkout`; the Read holds `TrainingLog`. Either bridge
    `TrainingLog → RunningWorkout` (preferred — reuses the real pace
    chart) or fetch the `RunningWorkout` by id at sheet-present time.
    This is the one non-trivial piece of Phase 4.
- **Fix the masthead:** dateline and byline both derive from the same
  date (the Read's `read_date`), or the byline explicitly reads "posted
  <generatedAt>" with the dateline as the read's *subject* day —
  decide one and apply consistently.

---

## Files in scope

**Edge / prompt**
- `supabase/functions/coaching-daily-read/index.ts` (context aggregates,
  claim validation, prediction guard)
- `supabase/functions/_shared/prompts/daily-read.v3.ts` (new)
- `supabase/functions/_shared/prompts/daily-read.v2.ts` (kept for A/B)
- `supabase/functions/_evals/cassettes/daily-read.v3/*` (new)
- reuse: `_shared/dataAnalysis.ts`, `_shared/weeklyAnalytics.ts`,
  `_shared/pace-engine.ts`

**iOS**
- `RunningLog/Coaching/Read/EvidenceChip.swift`
- `RunningLog/Coaching/Read/CoachReadView.swift`
- `RunningLog/Coaching/Read/SourcesPanel.swift`
- new `WorkoutPresentation` mapper
- reuse: `Workouts/WorkoutDetailSheet.swift` / `HistoryDetailSheet.swift`

---

## Guardrails this plan respects

- **Hard rule #3** — prompt v3 ships only with eval cassettes; CI
  enforces it. Phase 3 is gated, Phases 1/2/4 are not prompt changes.
- **Hard rule #7** — predictions become range+confidence; point-estimate
  guard added at the validation seam.
- **Hard rule #2 / Niggles spec** — surface-don't-interpret tightened in
  the prompt and not contradicted in the UI.
- **Pace taxonomy** — single source of truth via the pace engine /
  `derivePaceTableFromGoal` zone names; no new ladders.

---

## Suggested sequencing

Phase 1 first (visible win, no risk), then Phase 2 (truth before prose),
then Phase 4 (UI, parallelizable), then Phase 3 last (gated, slowest).
Phases 1–2 alone fix most of what's visibly wrong in the screenshots.

---

## Open questions for sign-off

1. **Legacy→zone classification:** classify each run's *actual* average
   pace into a zone (most accurate, more work), or a fixed
   `workout_type`→label dictionary (fast, less accurate)? *Recommend
   classification.*
2. **Claim validation strictness:** strip mismatched sentences
   (aggressive, risks choppy prose) vs. log-and-flag only (safe, slower
   to fix)? *Recommend start with log-and-flag on structured numbers,
   strip only point predictions.*
3. **Scope of this pass:** all four phases now, or land Phases 1–2 and
   schedule 3–4 separately? Phase 3 needs `GEMINI_API_KEY` for cassette
   recording — confirm it's available in this environment or defer.
4. **Coach Read deprioritization tension:** CLAUDE.md says coach-client
   work is deprioritized for Maya, but the Read IS Maya's surface
   (Coach tab, on-demand). Confirming this is in-scope Maya work, not
   the deprioritized coach-portal work. *Assuming yes.*
