# Handover: Adaptive Plan — Day Picking & Weekly Shape

**For:** Claude cowork (product / UX design)
**Owner:** rioreina
**Date authored:** 2026-04-20
**Status:** Pre-design. Product problem identified, not yet scoped for build.

---

## 1. The problem in one sentence

When an athlete subscribes to a training plan, the plan assigns every workout
to a specific date — but the athlete has no way to express preferences like
"my long run is Saturday," "I can't run Fridays," or "move this week's tempo
to Wednesday, I've got a conflict Tuesday." The plan is take-it-or-leave-it;
real life doesn't work that way.

## 2. Why this matters

The whole promise of the product is an **adaptive** training plan. Adaptation
today means: paces shift with fitness, workouts swap type based on signals
(fatigue, injury mentions). It does NOT mean: shape the week around the
athlete's life. That's a gap runners notice immediately and compare
unfavorably to manual coach relationships where the human coach asks "what
days work for you?" on day one.

## 3. Who the user is

- **App user = the running athlete.** Reads the app daily. Expects paces and
  days to make sense for their actual week.
- **Author user = a top-tier running coach** (the product owner) whose voice
  the AI should reflect. This coach thinks in terms of:
  - Quality days (tempo, intervals, race-pace work) = 1-3 per week
  - Long run = 1 per week, usually a weekend
  - Easy days = fill between quality + long run
  - Rest/recovery = true rest or light shakeout
  - Athletes have life constraints — kids, jobs, gym days, religious days off
- The coach does not want runners prescribed in half-miles for easy runs
  ("10 mile easy" not "9.5 mile easy"). Intervals/tempos/long runs can land
  on fractional distances because their math does.

## 4. Current system state

### DB (Supabase Postgres)

- `training_plans` — one row per plan the athlete is subscribed to.
  Has `name`, `target_race_distance`, `target_time_seconds`, `status`,
  `start_date`, `end_date`. **No column capturing weekly-shape preferences.**
- `scheduled_workouts` — one row per day of the plan. Has `date`,
  `workout_type` (easy / tempo / intervals / long_run / recovery /
  progression / strides / race / rest), `workout_data` (JSON body with
  name, steps, paces), `status` (scheduled / completed / skipped / swapped).
  **`date` is already free — any row can be moved to a different date.**
- `athlete_state` — DCO with rolling metrics. Unrelated to day-picking but
  adaptation reads from it.

### Plan generation paths (4 entry points, overlapping)

1. **`custom-plan-builder` edge fn** — conversational LLM authoring
   (Claude). User says "I want a marathon plan in 16 weeks," Claude asks
   a minimal round of questions and emits a week-by-week plan as JSON.
   This is where day-picking plumbing would land first.
2. **`parse-training-plan` / `parse-training-week`** — user pastes their
   coach's plan as text; LLM structures it into workouts.
3. **`generate-training-plan`** — legacy hardcoded template library
   (Canova-style). Fixed block sequences.
4. **`subscribe-to-plan`** — takes a plan template and assigns dates
   starting from today. The template → dates mapping is where a weekly
   shape would be consulted.

### Adaptation path

- `adapt-plan` edge fn runs when:
  - A training log triggers post-workout reconciliation
  - Sunday cron fires for the weekly rebalance
  - iOS explicitly requests adaptation
- It modifies `scheduled_workouts` rows — may swap workout_data, insert
  recovery, skip days. **Currently has no concept of protected days
  (e.g., "never touch Saturday long runs").**

### iOS screens (today)

- **Training Dashboard** — list of upcoming workouts, grouped by week.
- **Day Detail Sheet** — open a single day to see/edit its workout.
  Has Edit/Done buttons; editing is step-level, not day-shape-level.
- **Pace Chart tab** — shows the athlete's pace zones (5K, 10K, HM, MP,
  Easy). Derived from fitness snapshot. Orthogonal to day-picking but
  useful mental model for how the athlete thinks about paces.

### What's missing entirely

- No "pick your template" screen at plan creation.
- No drag-to-reorder or swap-with-another-day interaction on the weekly view.
- No DB column or JSON field capturing "the athlete wants quality on Tue/Thu,
  long run Saturday."
- No concept in `adapt-plan` of "protect the athlete's preferred shape."

## 5. Prior product decisions to respect

These come from direct conversations with the owner-coach; do not override
without confirming:

1. **Easy run distances are whole miles.** Never 9.5, 4.5, etc.
   Intervals / tempo / long runs can be fractional. (Already enforced in
   `custom-plan-builder` as of 2026-04-20.)
2. **Paces are goal-anchored, not current-fitness-anchored** — when a race
   goal is set. If no goal, fall back to current-fitness zones.
3. **No Daniels or Pfitzinger RAG.** The coach is themselves a top coach;
   the product should reflect their voice, not textbook methodology.
4. **No race auto-inference.** Don't tag a workout as a race without
   explicit user declaration; bias toward false negatives.
5. **No hardcoded pace defaults.** All paces from real athlete data.
6. **Training plan is optional.** Predictions and state work without one.

## 6. Design questions to answer

The design brief for this feature needs to resolve these explicitly.

### Q1. How does an athlete express their weekly shape?

Options, ordered by athlete effort:

- **(a) Pre-set templates** — "5 days / weekend long run," "6 days / mid-week
  quality," "7 days / doubles." Pick one at plan creation.
- **(b) Grid picker** — a Mon-Sun row, tap each cell to mark as Quality /
  Long run / Easy / Rest. Free-form but bounded.
- **(c) Voice input** — "I usually run 5 days, long on Saturday, quality
  Tuesday and Thursday." LLM extracts.
- **(d) Hybrid** — start from a preset, then tweak the grid.

Which does the coach-author prefer for their athletes? Different athlete
segments (returning beginners vs competitive masters) may want different
entry points.

### Q2. What granularity of preference?

- Just the shape of a typical week (Mon = rest, Tue = quality, ...) —
  simple. Applies every week of the plan.
- Per-phase (base vs build vs peak) — more nuanced but complex UX.
- Per-week override — cover one-off weeks (travel, holiday). Needed later,
  not MVP.

### Q3. What happens when the athlete's preference conflicts with coaching best practice?

Example: athlete picks Mon = quality AND Tue = quality (back-to-back hard
days). Coach's voice says no — hard days should sandwich easy/rest days.

Options:
- Hard block — UI won't let them pick two quality days in a row.
- Soft warn — UI says "this is risky, coach recommends a day between hards.
  Proceed anyway?"
- Silent accept — plan honors whatever the athlete asked for.

### Q4. How does this interact with `adapt-plan`?

When the adapter moves a workout (e.g., athlete missed Tuesday's tempo due
to low readiness), does it:
- Reschedule to the nearest available day respecting the template
  (quality on quality days, easy on easy days)?
- Break the template freely if needed for recovery?
- Ask the athlete?

The template becomes a constraint the adapter must learn about.

### Q5. Swap-within-week interaction

Different shapes:
- **Drag-and-drop** — athlete drags Tuesday's tempo card to Wednesday.
  Wednesday's workout slides to Tuesday (swap).
- **Tap-and-hold menu** — long-press a workout, get "Move to…" sheet.
- **Edit mode** — a dedicated edit toggle, reorder rows.

iOS-native convention is probably drag-and-drop in a weekly list view, with
a tap-and-hold affordance for discoverability.

### Q6. What about rest days the athlete specifies as non-run?

Many runners cross-train (bike, lift, swim). Should the template support
a "cross-train" marker alongside rest? Out of scope for MVP, but worth
flagging for the data model.

### Q7. When does the template get asked about?

- Once, at plan creation — simple. Regeneration needed to change.
- Editable any time — more flexible, but triggers re-adaptation cascades.

Default to once-at-creation + a single "regenerate with new template" escape
hatch later.

## 7. Scope of the MVP (suggested)

What ships in v1:

- Weekly template picker at plan creation (one screen, ~5-10 presets +
  a "customize" grid for advanced users).
- Template stored on `training_plans` as a JSONB column
  (e.g., `{"mon":"rest","tue":"quality","wed":"easy","thu":"quality",...}`).
- `custom-plan-builder` prompt receives the template and respects it.
- `subscribe-to-plan` places workouts onto the right days per the template.
- iOS weekly view shows the current shape; read-only in v1.

What waits for v2:

- Per-week swap-and-drag interaction on the calendar.
- `adapt-plan` learning about the template (for v1, the plan goes
  off-template when adapting; athlete can't lean on it).
- Per-phase templates (different shape in build vs peak).
- Cross-train markers.
- Voice input for template ("I run Tue Thu Sat").

## 8. Out of scope

Explicitly don't design:

- Changing the pace resolver (separate work — see
  `ml-service/README.md` and pace-chart discussions).
- New workout types.
- Weather-driven day moves.
- Multi-athlete coach dashboards.
- Team/club features.

## 9. Success criteria

The feature ships successfully if:

1. A new athlete at plan creation can say "long run is Saturday, quality
   Tuesday and Thursday," and every week of the generated plan honors it.
2. The athlete opens week 2 and sees quality on Tue and Thu, long on Sat —
   not scattered.
3. If the athlete hates the shape, they can regenerate with a different
   template in under 30 seconds.
4. Zero athletes report "the plan put my hard day on Friday when I can't
   run Fridays" within 2 weeks of launch.

## 10. Inputs Claude cowork should ask for

Before designing, request:

- **A walkthrough of the iOS plan creation flow as it exists today** —
  screens, fields, transitions. Owner can screenshot.
- **The owner's opinions on Q1-Q4 above** — especially how prescriptive vs
  permissive the template should be.
- **Example weekly shapes from three archetypal athletes**: (a) busy masters
  runner, (b) competitive young athlete, (c) comeback runner. Owner probably
  has strong instincts here.
- **Design system reference** — the iOS app has a `drip` token system (fonts,
  colors) already established. New screens should match.

## 11. File map for reference

Key code the designer may want eng to show:

```
supabase/functions/custom-plan-builder/index.ts    ← LLM authoring
supabase/functions/subscribe-to-plan/index.ts      ← date assignment
supabase/functions/adapt-plan/index.ts             ← runtime rescheduling
supabase/functions/_shared/athlete-state.ts        ← DCO (context)
supabase/migrations/20260204110000_create_scheduled_workouts.sql

RunningLog/RunningLog/Training/TrainingDashboardView.swift
RunningLog/RunningLog/Training/DayDetailSheet.swift
RunningLog/RunningLog/Training/JoinCoachPlanSheet.swift
RunningLog/RunningLog/Workouts/WorkoutDetailView.swift
```

## 12. What we're NOT changing as part of this feature

Flagged so the designer doesn't accidentally scope-creep:

- The pace vocabulary on workout steps (being unified separately).
- The goal-anchored vs fitness-anchored pace choice (separate decision).
- Adaptation triggers (injury signals, fatigue, weather).
- Coaching-chat / AI-coach conversations.

---

## One-paragraph summary for cowork

> We need day-picking UX for the adaptive training plan. Today plans lock
> every workout to a fixed date with no input from the athlete about which
> days are quality, easy, long-run, or rest. Design a weekly-template
> picker for plan creation that captures the athlete's preferred shape,
> plumbs it through the LLM authoring prompt, and shows up in the plan
> that gets generated. Defer per-week swaps and adaptation-awareness to
> v2. Respect the coach-author's voice (no Daniels/Pfitzinger textbook
> language) and the rule that easy runs are whole miles. Answer Q1–Q7
> above before handing back an interaction design.
