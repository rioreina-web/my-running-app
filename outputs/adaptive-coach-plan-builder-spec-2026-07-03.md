# Adaptive Training Plan Builder for Coaches — Feature Spec

**Date:** 2026-07-03
**Status:** Draft for review
**Decision note:** This spec deepens coach surfaces, reversing the 2026-05-28
deprioritization. Rio confirmed on 2026-07-03 that coach-athlete dyads are an
active investment again. The canonical coach surface is the **web coach
portal** (`web/src/app/(app)/coach-portal/*`). The legacy `(app)/coach` route
stays slated for removal.

---

## 1. The seven requirements

1. Plans built around **key sessions** (long runs; workouts: intervals, tempo-pace work, fartleks)
2. **Schedule adaptation** — athlete quality-day preferences (Tue/Sat vs Wed/Sun)
3. **Mileage as a range** — "40–50 miles this week"
4. **Easy day moves** with a quick reason (work, fatigue, conflict)
5. **Coach mid-block rewrites** — e.g. rewrite 4 weeks after a sickness
6. **Readable coaching instructions** on every workout
7. **Feedback loop** for coaches inside the plan

## 2. What already exists (verified in code)

The repo has most of the skeleton. This spec is mostly *wiring and finishing*,
not greenfield.

| Piece | Where | State |
|---|---|---|
| Adaptive plan type (coach authors quality days + mileage range; easy days auto-fill) | `plan_templates.plan_type`, `plan-builder-client.tsx` (~1100 LOC) | **Working** |
| Weekly mileage range | `weeks[i].targetMilesMin/Max` in builder; `weekly_mileage_targets` column | Range works; ramp column unused |
| Day-role skeleton (Tue=speed, Sat=long) | `plan_templates.day_structure` column | **Column exists, never written or read** |
| Phase config (base/build/specific/taper) | `plan_templates.phase_config`; orphaned `adaptive-plan-config.tsx` component | Holds only `paceAnchor` today |
| Athlete schedule prefs (quality dows, long-run dow, rest dows, volume ramp) | `athlete_plan_subscriptions` (migration `20260425200000`) | **Working**, read by `subscribe-to-plan` |
| Materializer (fills easy days per athlete, personalizes paces, weights recovery days) | `subscribe-to-plan/index.ts` (1255 LOC) | Working; ignores coach pace anchor |
| Athlete moves a day | `shift-day` edge fn — same-week swap, green tier | **Working** |
| Mutation ledger with tiers + reasons | `plan_adjustments` (+ `tier`, `reason_code`, `reason_text`, `week_number` from `20260424100000`) | **Working** |
| Green/yellow/red boundary model | `docs/athlete-plan-ux.md` §5 | Designed, partially built |
| Constrained AI reschedule | `reschedule-plan` (closed `WORKOUT_CODES_BY_DAY` library, `auto_applied:false`, once/day) | Working, needs eval coverage |
| Adaptation rules engine | `adapt-plan` + `_shared/adaptation-rules.ts` | Working |
| Per-day coach rationale columns | `scheduled_workouts.rationale_short/rationale_full` | **Columns exist; `generate-day-rationale` fn never built** |
| Coach→athlete notes | `coach_notes` + `coach-note-composer.tsx` | Working |
| Advice feedback (thumbs) | `coaching_feedback` / `coaching_adjustments` | Working, aimed at AI advice not plans |
| Block review (end of mesocycle) | `block-review` edge fn | Working, athlete-facing |

Key references: `adaptive-plan-builder-rework.md` (repo root — coach-side gaps
and §6 restructure proposal), `docs/athlete-plan-ux.md` (athlete-side tier
model), `docs/handover-adaptive-plan-day-picking.md`.

## 3. Requirement-by-requirement gap analysis

### R1 — Built around key sessions ✅ mostly exists

The adaptive plan type is already key-session-first: the coach authors only
quality sessions; the materializer fills easy volume around them.

**Gaps to close:**
- **Wire `day_structure`.** Coach sets the weekly skeleton once at plan level
  ("Tue = speed, Thu = medium, Sat = long, Mon = rest") via a chip picker in
  a new "Plan setup" header section. Per-week grids prefill from it; coach
  only fills in the actual workout content. (Rework doc §6A, next-step (d).)
- **Wire phase config per week** (base/build/specific/taper). Un-orphan
  `adaptive-plan-config.tsx`. Kills the bogus iOS `weeksUntilRace`-derived
  phase label.
- **Workout labels follow the 10-zone taxonomy** (CLAUDE.md): key sessions
  are labeled by pace zone (`MP 7 mi`, `LT 6 mi`, `5K 5×1km`), plus `Long` /
  `Long wo`. A fartlek is a structured workout whose steps carry zone targets.

### R2 — Athlete schedule preferences ✅ mostly exists

`preferred_quality_dows` + `long_run_dow` + `rest_dows` already exist and the
materializer respects them: coach's 2 quality sessions land on the athlete's
picked days (Tue/Sat athlete gets Tue/Sat; Wed/Sun athlete gets Wed/Sun) from
the same template.

**Gaps to close:**
- **Coach-side visibility + override.** The coach portal athlete detail page
  should show each athlete's schedule prefs, and let the coach edit them
  (writes to `athlete_plan_subscriptions`, then re-materializes future weeks).
- **Coach default skeleton** (R1's `day_structure`) becomes the fallback when
  the athlete sets no preference.

### R3 — Mileage as a range ✅ exists, needs ramp tooling

`targetMilesMin/Max` per week already drives the easy-fill budget.

**Gaps to close:**
- **Ramp sketch tool** in Plan setup: editable per-week bar chart with fill
  helpers ("linear 40→55 over 8 wks", "down week every 4th at −20%",
  "taper last 2 wks to 60%"). Writes both `weeks[i].targetMilesMin/Max` and
  `weekly_mileage_targets` (finally using the column).
- **Display convention:** the range is the number everywhere ("40–50 mi").
  Consistent with hard rule #7's range-over-point philosophy.

### R4 — Move days easily, with a quick reason ✅ exists, needs reason UX

`shift-day` already does same-week swaps at green tier and writes the ledger.

**Gaps to close:**
- **Reason picker.** `shift-day` currently hardcodes `reason_code:
  "shift_day"`. Add a closed reason vocabulary + optional free text:
  `work | fatigue | schedule_conflict | weather | travel | feeling_good |
  other`. iOS move sheet = drag/tap target day + one-tap reason chip. Two
  taps total; reason optional but one-tap cheap.
- **Cross-week moves** stay yellow tier (flagged to coach) per the existing
  tier table; same-week stays green. No change to the boundary model.
- **Coach sees the moves**: adjustments feed on the coach portal athlete
  page — "Tue quality → Wed (work)" — powered by existing `plan_adjustments`
  rows. Read-only list, newest first, tier-colored.

### R5 — Coach mid-block rewrites ❌ the main build

Today the builder edits **templates**; nothing lets a coach edit a specific
athlete's **live plan**. This is the centerpiece of this spec.

**Design: "Edit live plan" on the coach portal athlete page.**

- **Scope selector:** coach picks a week range (e.g. W7–W10, future-only;
  past weeks are immutable history).
- **Two edit modes:**
  1. **Manual** — the same week-grid editor as the builder, but operating on
     the athlete's materialized `scheduled_workouts`. Coach can drop mileage
     ranges, swap key sessions, insert rest/recovery weeks.
  2. **Assisted rewrite** — coach states what happened ("flu, zero running
     for 10 days") + intent ("rebuild gently, keep the race date"); the
     system proposes a rewritten block using the *same constrained approach
     as `reschedule-plan`* (closed workout library, athlete's pace profile,
     ACWR-safe ramp back). **Never auto-applies** — coach reviews the diff
     week-by-week and confirms. AI advises, coach acts (core principle).
- **Apply path:** a new service-role edge function `rewrite-block` —
  validates the diff, updates future `scheduled_workouts`, writes one
  `plan_adjustments` row per changed week with a new
  `trigger_type: 'coach_rewrite'` + `reason_code` (`sickness | injury_niggle
  | race_change | life_event | performance | other`) + before/after payload
  (reversible per existing ledger contract), and re-triggers rationale
  generation (R6) for the rewritten weeks.
- **Athlete notification:** rewritten weeks show a "Coach updated W7–W10 —
  sickness recovery" banner; tapping shows the coach's note.
- **Guardrails:** future weeks only; race-week edits require explicit
  confirm; all writes via service-role fn (hard rule #4 pattern); if the
  assisted path ships an LLM prompt, it lands in `_shared/prompt-library.ts`
  with eval cassettes first (hard rule #3, CI-enforced).

### R6 — Readable coaching instructions ⚠️ half-built

Columns exist (`rationale_short`, `rationale_full`), the generating function
was designed (`docs/athlete-plan-prompts.md` AP-4) but never built.

**Design — coach words first, AI fallback:**
- **Coach-authored instructions win.** The builder and live-plan editor get a
  plain-language instruction field per workout ("Settle into MP by mile 2.
  If HR drifts past 165, back off — this one's about rhythm, not heroics").
  Stored on the workout; shown verbatim, attributed to the coach.
- **`generate-day-rationale`** (build per AP-4) backfills `rationale_short`
  for days the coach didn't annotate — the athlete's one-line "why today"
  subtitle. Never overwrites coach text. Prompt via prompt-library + evals.
- **Rendering:** iOS day view shows instruction as body prose under the
  structured steps — plain paragraph, no bullets-of-bullets. Voice per
  design system: warm, no jargon-dressed-as-authority, never explains math.

### R7 — Feedback for coaches in the plan ⚠️ pieces exist, loop doesn't

Existing: voice logs already reconcile against scheduled workouts
(`reconcile-log`), RPE extraction exists, `coach_notes` go coach→athlete,
`coachable_moments` flag patterns.

**Design — close the loop at two grains:**
- **Per-workout:** after a key session completes/reconciles, the athlete's
  quick take (RPE + one-tap feel: `nailed_it | solid | struggled | cut_short`
  + optional comment — prefilled from the voice log when one exists) attaches
  to the `scheduled_workouts` row. New nullable columns
  (`athlete_feedback JSONB`, `athlete_feedback_at`), athlete-writable on own
  rows only (RLS).
- **Coach view:** the athlete's plan calendar in the portal shows
  planned-vs-actual per day with the feedback chip; a **week strip** rolls up
  compliance % (already computed in athlete-state), mileage vs range, and
  key-session outcomes. This is the coach's "how is the plan landing?" view
  and the direct input to R5 rewrites.
- **Coach replies** use existing `coach_notes`, threaded to a specific
  workout via a nullable `scheduled_workout_id` reference — one small
  migration, reuses the whole notes pipeline.

## 4. Data model changes (small — mostly wiring)

New migrations (append-only, RLS in same migration, naming convention):

1. `plan_adjustments`: extend `trigger_type` CHECK with `'user_action'` and
   `'coach_rewrite'`; extend `action_type` with `'rewrite_block'`.
   **Note (found during build):** `shift-day` was already inserting
   `trigger_type='user_action'`, which the CHECK rejected — athlete
   day-move audit rows have been silently failing since April. Shipped as
   `20260703120000_plan_adjustment_vocab_for_coach_plans.sql`.
2. `scheduled_workouts`: add `coach_instruction TEXT`,
   `athlete_feedback JSONB`, `athlete_feedback_at TIMESTAMPTZ`. RLS: athlete
   updates feedback cols only (column-guard trigger, same pattern as
   `plan_adjustments`); coach instruction written via service-role fn.
3. `coach_notes`: add nullable `scheduled_workout_id UUID` reference.
4. ~~Fix legacy RLS~~ — **already done:** the Feb "Allow all" policies on
   `training_plans` / `scheduled_workouts` were replaced in
   `20260313100000_lock_down_rls.sql`. No action needed.

Deliberately **not** new tables: the ledger, subscriptions, notes, and
feedback tables all exist.

## 5. Edge functions

| Function | Action |
|---|---|
| `rewrite-block` | **New.** Service-role apply path for R5. Validates, writes workouts + ledger, fires rationale regen. |
| `generate-day-rationale` | **New** (design exists at `docs/athlete-plan-prompts.md` AP-4). Prompt-library + eval cassettes before ship. |
| `shift-day` | Extend: accept `reason_code`/`reason_text` from the closed vocabulary. |
| `subscribe-to-plan` | Extend: read `day_structure` + `weekly_mileage_targets`; use coach `paceAnchor` as fallback when athlete has no pace profile (known gap). Fix the 0-vs-1-indexed `dayOfWeek` heuristic while in there. |
| `submit-workout-feedback` | **New, small.** Validates + writes athlete feedback (or do it client-side under the column-guard RLS; decide at build time). |

## 6. Coach portal UI

1. **Plan setup section** in builder header: day-role skeleton picker, ramp
   sketch, phase tagging, shape flags (`rest_day_of_week`,
   `auto_strides_on_pre_quality`, `recovery_after_long_run` — all three
   currently have no UI). Rework doc §6A.
2. **Per-week simplification:** with a skeleton set, weeks show only quality
   slots (by role) + mileage readout + notes. Rework doc §6B.
3. **Athlete plan view** (athlete detail page): live calendar,
   planned-vs-actual, feedback chips, week strips, adjustments feed,
   schedule-prefs editor.
4. **Edit live plan** flow: scope selector → manual grid or assisted rewrite
   → diff review → confirm.

Design-system: Post Run Drip tokens, `Eyebrow`/empty-state components, coral
as punctuation. No em-dash placeholders (hard rule #8).

## 7. iOS touches (smaller)

- Move-day sheet: reason chips (R4).
- Day view: coach instruction prose + rationale subtitle (R6).
- Post-workout feedback prompt after key sessions (R7).
- "Coach updated your plan" banner + diff summary (R5).

## 8. Phasing

| Phase | Scope | Value |
|---|---|---|
| **A — Wire what exists** — ✅ **shipped 2026-07-03** (pace-anchor fallback found already done; RLS found already fixed; bonus: fixed the silent plan_adjustments audit-insert failure) | day_structure + skeleton picker, ramp tool, shape-flag UI + phase tagging, shift-day reasons + web reason chips | R1, R2, R3, R4 done |
| **B — Live plan editing** (~1–2 wks) | Athlete plan view in portal, manual edit + `rewrite-block`, adjustments feed, athlete banner | R5 (manual), coach visibility |
| **C — Instructions** (~1 wk) | Instruction fields, `generate-day-rationale` + evals, iOS rendering | R6 |
| **D — Feedback loop** (~1 wk) | Per-workout feedback, week strips, threaded coach notes | R7 |
| **E — Assisted rewrite** (after B+C) | Constrained AI block rewrite w/ diff review, eval cassettes first | R5 (assisted) |

Each phase ships independently. A alone makes the current builder markedly
better.

## 9. Decisions (2026-07-03, Rio)

1. **Assisted rewrite engine: constrained library.** Extend
   `reschedule-plan`'s closed-library approach for `rewrite-block`.
2. **Feedback: available on any run, prompted only after key sessions.**
   Every completed run carries a passive feedback affordance in the day
   view; the active post-run prompt fires for quality sessions and long
   runs only. Don't nag.
3. **Phase A greenlit** 2026-07-03.

## 10. Still-open questions

1. **Default quality-day count** — 2 or 3 per week when the coach doesn't
   specify? (Rework doc Q1; suggest 2.)
2. **Cross-week athlete moves** — keep yellow (flagged) or allow green within
   ±2 days across a week boundary?
3. **Does Maya get this too?** The same `rewrite-block` + reasons machinery
   could power self-coached block resets later — worth keeping the API
   athlete-agnostic even though the UI is coach-only for now.
