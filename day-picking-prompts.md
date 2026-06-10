# Adaptive Plan — Day Picking & Pace Adjustment — Execution Prompts

**Companion to:** `docs/handover-adaptive-plan-day-picking.md`
**Tag format:** `DP-A.1`, `DP-B.2`, etc. — greppable in commit messages.
**Decisions captured (from design conversation, 2026-04-20):**
- Rhythm-based weekly template (pattern + anchor day), not free-form grid
- Five day-types: `rest`, `easy`, `long_run`, `quality`, `cross_train`
- No hard blocks on back-to-back quality days — coach soft-warns instead
- Drag-and-drop primary interaction with soft-ask for week rotation
- Template editable mid-plan, regenerates current week forward
- Pace adjustments: 2-week warm-up window, then gradual moving average, always soft-asked
- Triggered specific adjustments when 2-of-3 (or 3-of-4 with qualitative signal) quality misses occur
- Coach decides direction, athlete overrides

---

## Phase A — Data model + plan generation (Week 1)

### DP-A.1 — Migration: `weekly_template` JSONB on `training_plans`

**Dependencies:** none (start here).
**Files:** new migration.

> Create migration `<timestamp>_training_plans_weekly_template.sql`. Add `weekly_template JSONB` column to `training_plans`. Nullable for existing rows. Shape of the JSON (document as a comment in the migration):
>
> ```json
> {
>   "rhythm": {
>     "quality_sessions": 2,
>     "gap_days": [3, 3]
>   },
>   "anchor_day": "tuesday",
>   "day_types": {
>     "monday": "easy",
>     "tuesday": "quality",
>     "wednesday": "easy",
>     "thursday": "easy",
>     "friday": "quality",
>     "saturday": "easy",
>     "sunday": "long_run"
>   }
> }
> ```
>
> Day-type enum values: `'rest' | 'easy' | 'long_run' | 'quality' | 'cross_train'`. Day-of-week keys are the single source of truth for which days are cross-train, rest, etc. — no separate arrays.
>
> `rhythm.quality_sessions` counts tempo/interval-style quality only. The long run is always a separate day (one `long_run` entry in `day_types`) and not counted here. `gap_days.length` must equal `quality_sessions`; `sum(gap_days) + 1` equals the number of days between the first and last quality session (wrapping mod 7).
>
> Add a CHECK constraint via a plpgsql trigger (the `pg_jsonschema` extension is not guaranteed on the target project). Trigger validates:
> - `anchor_day` is a valid weekday string
> - Every value in `day_types` is one of the five enum values
> - `day_types` has exactly 7 keys (Mon–Sun)
> - `rhythm.gap_days.length == rhythm.quality_sessions`
>
> RLS inherits from `training_plans` (no new policies needed). Add an index on `(user_id, status)` if one doesn't already exist.

---

### DP-A.2 — Shared TypeScript + Swift types

**Dependencies:** DP-A.1.
**Files:** `supabase/functions/_shared/weekly_template.ts`, `RunningLog/RunningLog/Models/WeeklyTemplate.swift`.

> Create matching type definitions for the weekly_template JSON shape in both TypeScript and Swift.
>
> In `supabase/functions/_shared/weekly_template.ts`:
> ```ts
> export type DayType = "rest" | "easy" | "long_run" | "quality" | "cross_train";
> export type Weekday = "monday" | "tuesday" | "wednesday" | "thursday" | "friday" | "saturday" | "sunday";
>
> export interface WeeklyRhythm {
>   quality_sessions: number;
>   gap_days: number[];        // length = quality_sessions
>   long_run_position: number; // 0-indexed; which quality slot is actually the long run
> }
>
> export interface WeeklyTemplate {
>   rhythm: WeeklyRhythm;
>   anchor_day: Weekday;
>   day_types: Record<Weekday, DayType>;
>   cross_train_days: Weekday[];
>   rest_only_days: Weekday[];
> }
>
> export function rotateAnchor(template: WeeklyTemplate, newAnchor: Weekday): WeeklyTemplate {
>   // Shift EVERY day by the same offset so the whole pattern slides as one.
>   // gap_days stays identical; only day_types entries move.
>   //
>   // Worked example — Tue/Fri/Sun quality, anchor Tuesday → rotate to Wednesday:
>   //   Before: Mon=rest, Tue=quality, Wed=easy, Thu=easy, Fri=quality, Sat=easy, Sun=long_run
>   //   After:  Mon=long_run, Tue=rest, Wed=quality, Thu=easy, Fri=easy, Sat=quality, Sun=easy
>   //   (every day shifted +1; long_run wraps around from Sun to Mon)
>   //
>   // Not this: swapping ONLY the anchor's type (Tue=quality → Wed=quality) would leave
>   // the other quality days and long-run day where they were. That's a "just move
>   // today" operation, not a rotation — see DP-D.2 for that interaction.
> }
>
> export function validateTemplate(template: WeeklyTemplate): string[] {
>   // Returns empty array if valid, or list of error strings.
>   // Checks: gap_days sum = 7, quality_sessions == gap_days.length, etc.
> }
> ```
>
> Mirror the types exactly in Swift (`RunningLog/RunningLog/Models/WeeklyTemplate.swift`) as a `Codable, Equatable` struct with matching `CodingKeys`.

---

### DP-A.3 — `custom-plan-builder` respects the template

**Dependencies:** DP-A.2.
**File:** `supabase/functions/custom-plan-builder/index.ts`.

> The LLM authoring edge function currently emits a week-by-week plan without honoring a template. Modify it to:
>
> 1. Accept an optional `weekly_template` field in the request body matching the TypeScript `WeeklyTemplate` shape from DP-A.2.
> 2. Inject the template into the system prompt with explicit instructions:
>    - "The athlete's preferred weekly shape is: [anchor] = [day], rhythm = [gap_days]"
>    - "Quality sessions must fall on the days marked `quality` in `day_types`"
>    - "Avoid authoring back-to-back quality days — space them with easy or rest. Strides before a quality day are OK; the long run following a quality day is OK."
>    - "Cross-train days are athlete-managed — do NOT prescribe specific workouts on those days"
>
> Note: "avoid authoring" is a proactive constraint on the LLM. It is NOT a hard block on the athlete's picker UI — in DP-C.2 the athlete is allowed to pick back-to-back quality with a soft-warn. The LLM never does so autonomously; the athlete may do so with a nudge.
> 3. Add output validation: after the LLM returns the week structure, verify every quality session lands on a day marked `quality` in the template. If not, re-prompt the LLM with a correction, max 2 retries, then fall back to placing quality sessions on the template-specified days and letting the LLM fill in the workout details.
> 4. Write the `weekly_template` to the `training_plans` row when the plan is created.

---

### DP-A.4 — `subscribe-to-plan` places workouts per template

**Dependencies:** DP-A.2.
**File:** `supabase/functions/subscribe-to-plan/index.ts`.

> When assigning dates to a plan template, consult `training_plans.weekly_template` (if present) to determine which days-of-week get which workout types. Without a template, preserve current behavior (start from today, sequential days).
>
> Specifically:
> - Walk from `start_date` to `end_date` week by week
> - For each week, place quality sessions on days marked `quality` in the template
> - Place long run on the day marked `long_run`
> - Easy runs fill `easy` days; `rest` and `cross_train` days get no running prescription
> - If a week's start doesn't align with the anchor day, rotate the first partial week to match
>
> Add a test that subscribes a 6-week plan with a Tu/Fr/Sun template and asserts every quality workout lands on a Tue/Fri and every long run on a Sun.

---

### DP-A.5 — Backfill default template for existing active plans

**Dependencies:** DP-A.1.
**File:** new migration.

> Create migration `<timestamp>_backfill_weekly_template.sql`. For every `training_plans` row where `status = 'active'` and `weekly_template IS NULL`, infer a default template from the plan's existing `scheduled_workouts`:
>
> 1. Scan the first 2 weeks of scheduled_workouts for this plan
> 2. Identify which day-of-week has each workout type
> 3. Build the JSON shape from DP-A.2 with inferred rhythm, anchor_day, day_types
> 4. If the plan has no scheduled_workouts yet, write a default template: `Tu/Fr/Sun quality, anchor Tuesday, 5-day running week`
>
> Include a dry-run mode via a parameter so the team can review the inferences before applying. Log any plans that couldn't be inferred.

---

## Phase B — Pace adjustment logic (Week 2)

### DP-B.1 — Moving-average pace adjuster with 2-week warm-up

**Dependencies:** existing `athlete_pace_profiles` + `workout_reconciliations` (from adaptive-plan-loop work).
**Files:** `supabase/functions/_shared/pace_adjuster.ts`, called from `adapt-plan`.

> Create `supabase/functions/_shared/pace_adjuster.ts` with function `proposePaceAdjustment(user_id): Promise<PaceAdjustmentProposal | null>`.
>
> Logic:
> 1. Warm-up gate: return `null` until BOTH (a) the plan has been active for >= 14 days AND (b) the user has completed >= 4 quality-session reconciliations. This avoids firing prematurely on high-frequency plans and also avoids waiting forever on low-frequency (3-day/week, 1 quality/wk) plans — whichever of volume-or-time satisfies last wins.
> 2. Otherwise, compute the rolling mean of `adjusted_pace_delta_seconds` (from `workout_reconciliations`) across the last 4 quality sessions.
> 3. If the mean is within ±3 seconds of target, no adjustment — return `null`.
> 4. If the mean shows consistent overperformance (≥3s faster than adjusted target), propose bumping the relevant pace zone faster by 2-3s/mi.
> 5. If the mean shows consistent underperformance (≥3s slower), propose softening by 3-5s/mi.
> 6. Return a `PaceAdjustmentProposal` with: target zone (`marathon`, `half`, etc.), current value, proposed value, evidence (the 4 reconciliation IDs), `reasoning` (human-readable one-sentence explanation).
>
> `adapt-plan` consumes this and, if non-null, creates a `plan_adjustments` row with `auto_applied = false` and `proposed_until = now() + 7 days`. The athlete sees it in the Plan Updates feed and accepts or rejects. Never silently write pace changes.
>
> **Tests:**
> - Unit test with 8 synthetic `workout_reconciliations` rows:
>   - Flat scenario (all within ±2s) → proposal is `null`.
>   - Overperforming (4 sessions averaging -6s) → proposal bumps MP 2-3s faster.
>   - Underperforming (4 sessions averaging +8s) → proposal softens MP 3-5s slower.
> - Warm-up gate: 3 reconciliations within 7 days → `null`. 5 reconciliations over 16 days → proposal can fire.

---

### DP-B.2 — Triggered adjustment detector

**Dependencies:** DP-B.1.
**File:** `supabase/functions/_shared/pace_adjuster.ts` (extend).

> Add `detectTriggeredAdjustment(user_id): Promise<TriggerProposal | null>` to the same file.
>
> Logic:
> 1. Look at the last 4 quality-session reconciliations.
> 2. Count "misses": `adjusted_pace_delta_seconds > 10` (missed by more than 10s/mi).
> 3. Also count "qualitative misses": the associated `training_logs.mood` is `tired`, `struggling`, or `injured`.
> 4. If 2 of the last 3 were misses, OR 3 of the last 4 including at least 1 qualitative miss → trigger fires.
> 5. When triggered, propose ONE of:
>    - **Specific pace cut** — larger bump (5-10s/mi slower) if the misses are pace-based
>    - **Recovery week** — if misses include multiple qualitative signals or missed sessions entirely
>    Coach decides which based on evidence; return a `TriggerProposal` with `kind: 'pace_cut' | 'recovery_week'` + reasoning.
> 6. If this is the second trigger within 4 weeks for the same user, prefer recovery_week even if specific pace cut would be valid. Log "repeat trigger — firmer response."
>
> Write to `plan_adjustments` with `trigger_type: 'missed_sessions'` or `'pace_under_target'`, `auto_applied: false` for both pace_cut AND recovery_week — the athlete must explicitly accept. This matches the "always soft-asked" principle from the design conversation. Recovery-week cards should be visually prominent and use urgent copy ("You've been struggling — let's take a week") but do not mutate `scheduled_workouts` until accepted. If the athlete rejects, log it; subsequent triggers within 2 weeks escalate to a coach-chat message rather than another card.
>
> **Tests:** four fixture sequences covering each path:
> - 4 green sessions → no trigger.
> - 2 of last 3 miss by >10s → `kind: 'pace_cut'`.
> - 3 of last 4 include a qualitative miss (mood = tired/struggling) → `kind: 'pace_cut'`.
> - Second trigger within 4 weeks → `kind: 'recovery_week'` regardless of which form of miss.

---

### DP-B.3 — Recovery-week generation

**Dependencies:** DP-B.2.
**File:** `supabase/functions/_shared/recovery_week.ts`.

> When `detectTriggeredAdjustment` proposes a recovery week, we need to actually rewrite next week's `scheduled_workouts`.
>
> Create `generateRecoveryWeek(plan_id, week_start_date, template, severity): Promise<ScheduledWorkout[]>`:
> 1. Honor the weekly template's day-types — long run stays on the long-run day, easy days stay easy days, quality days become... *moderate effort instead of hard* (not removed — replaced with easy runs of equivalent duration, to preserve volume feel).
> 2. Reduce total weekly volume. Default 30%. `severity: 'mild' | 'standard' | 'firm'` maps to 25% / 30% / 35%. Standard is the default from DP-B.2.
> 3. No intervals/tempo — just easy + moderate + one shorter long run.
> 4. Write a note on each workout: "Recovery week — coach reduced intensity after [reason]."
>
> Replace existing `scheduled_workouts` rows for that week. Record the pre-change state in `plan_adjustments.action_payload.before` for revert.
>
> **Tests:** given a 50 mpw build week with Tue tempo + Fri intervals + Sun 18mi long run:
> - `severity: 'standard'` produces a 35 mpw week with Tue+Fri converted to easy/moderate and Sun shortened to ~13mi.
> - Template is respected: Mon=easy, Tue/Fri still have a run (not rest), Sat=easy.
> - `action_payload.before` holds the original 3 scheduled_workouts ids + their prior workout_data for one-click revert.

---

## Phase C — iOS picker UI (Week 3)

### DP-C.1 — Picker screen: rhythm selection

**Dependencies:** DP-A.2.
**File:** new `RunningLog/RunningLog/Training/WeeklyRhythmPickerView.swift`.

> Build a SwiftUI view that presents 4-6 preset rhythm cards. Each card shows:
> - Title: "Tu/Fr/Sun" or "M/W/F" or similar
> - Subtitle: "3 quality per week, weekend long run"
> - Visual: a tiny 7-day strip showing Q/E/E/Q/E/E/LR pattern
>
> Presets (initial set — tune based on archetype data):
> 1. **5-day classic** — 3 quality, Tue/Fri/Sun, easy Mon/Wed/Thu/Sat
> 2. **6-day runner** — 3 quality, Tue/Thu/Sat, easy rest
> 3. **4-day busy** — 2 quality + long, Tue/Thu/Sat
> 4. **3-day minimum** — 1 quality + 1 long, Wed/Sat
> 5. **Custom** — opens anchor + day-type editor
>
> Use existing drip design tokens for fonts/colors. Tap a card → animate selection, reveal anchor-day picker below. Each preset maps to a concrete `WeeklyTemplate` struct.

---

### DP-C.2 — Anchor day picker

**Dependencies:** DP-C.1.
**File:** extend `WeeklyRhythmPickerView.swift`.

> Below the rhythm cards, once a preset is selected, show:
> - 7 weekday chips in a row (Mon Tue Wed Thu Fri Sat Sun)
> - Tapping a chip sets the `anchor_day` and re-renders the 7-day strip preview to show what the week will look like
> - Preview: a stacked list of 7 rows, each with day name + workout type label (Quality / Easy / Long Run / Rest / Cross-Train)
>
> If user selected "Custom" in DP-C.1, show the full day-type editor instead — tap each day to cycle through day-type values. When the athlete picks back-to-back `quality` days, **soft-warn but allow**: show a small banner under the editor ("Back-to-back hard days — that's outside how we'd normally coach it. Proceed?") with [Keep it] / [Rearrange]. Never hard-block; athletes with specific needs (e.g., a fixed work schedule) should be able to override.
>
> Add a `[Continue]` button at the bottom that carries the `WeeklyTemplate` to the next screen.

---

### DP-C.3 — Wire picker into `JoinCoachPlanSheet`

**Dependencies:** DP-C.2, screenshot of existing sheet needed.
**File:** `RunningLog/RunningLog/Training/JoinCoachPlanSheet.swift`.

> Insert `WeeklyRhythmPickerView` into the existing plan-creation flow. It should land after goal-setting and before plan generation. On continue, the `WeeklyTemplate` gets passed to the `custom-plan-builder` call (DP-A.3).
>
> Match the existing sheet's visual style (drip tokens, button treatments, back-button behavior).

---

### DP-C.4 — "Change rhythm" mid-plan

**Dependencies:** DP-C.1-3.
**Files:** `RunningLog/RunningLog/Training/TrainingDashboardView.swift` + a new `ChangeRhythmSheet.swift`.

> Add a "Change weekly rhythm" menu item on the Training Dashboard (in an overflow menu, not a primary button). Tap opens a sheet that:
> 1. Shows the current rhythm
> 2. Re-opens `WeeklyRhythmPickerView` with the current template pre-selected
> 3. On save, calls a new edge function `regenerate-plan-from-this-week` that takes the new template and rewrites all `scheduled_workouts` rows from this week's start date forward (past weeks untouched)
> 4. Surfaces a confirmation: "Your training plan will update starting this week. Past weeks unchanged."

---

## Phase D — Drag-and-drop + adapt-plan template awareness (Week 4)

### DP-D.1 — Drag-and-drop on weekly view

**Dependencies:** existing `WeekCalendarView`.
**File:** `RunningLog/RunningLog/Training/WeekCalendarView.swift`.

> Add SwiftUI drag-and-drop support to the weekly view. Each workout card is draggable; each day cell is a drop target. On a successful drop:
> 1. Capture the original day and the target day
> 2. Trigger the soft-ask sheet (DP-D.2) before writing anything
> 3. If the user confirms, write the new date to `scheduled_workouts`
>
> Visual feedback: lift shadow when dragged, haptic on pickup, green highlight on valid drop targets.

---

### DP-D.2 — Soft-ask sheet: "Shift other days?"

**Dependencies:** DP-D.1, DP-A.2's `rotateAnchor` function.
**File:** new `ShiftWeekSheet.swift`.

> When the user drops a workout on a new day, present a bottom sheet:
>
> > **Want to shift your other days too?**
> > Moving Tuesday's tempo to Wednesday. Keep your pattern intact by also moving:
> > - Friday's intervals → Saturday
> > - Sunday's long run → Monday
> >
> > **[Just this week]** (recommended) — rotate this week only; next week starts back on Tue/Fri/Sun
> > **[Shift my whole plan]** — rotate every remaining week until the end of the plan
> > **[Just today]** — only Tuesday moves; everything else stays put
> > **[Cancel]**
>
> **Just this week:** rotate the current week's remaining days by calling `rotateAnchor` scoped to the current week's date range only. Next week reverts to the stored template.
>
> **Shift my whole plan:** call `rotateAnchor(template, newAnchorDay)`, persist the new anchor to `training_plans.weekly_template`, and regenerate all future `scheduled_workouts` dates from this point forward. Mark the plan-level change in `plan_adjustments` so adapt-plan knows the rhythm moved.
>
> **Just today:** write only the dragged workout's new date. If the one-off move creates back-to-back quality days, show a second soft-warn before accepting: *"This puts two hard days back-to-back. That's outside how we'd normally coach it. Do it anyway?"* [Yes, I'm sure / Go back].
>
> Default selection: **Just this week** — covers the common case (one-off conflict) without silently migrating the athlete's entire plan.
>
> **Tests (UI + data):**
> - Drag Tue tempo → Wed, pick "Just this week" → Wed holds tempo, Thu holds what was Wed (easy), Tue becomes what Wed held. Next week unchanged.
> - Drag Tue tempo → Wed, pick "Shift my whole plan" → every remaining week now shows quality on Wed/Sat/Mon (rotation +1). `training_plans.weekly_template.anchor_day` updates to Wednesday.
> - Drag Tue tempo → Wed, pick "Just today" → Wed holds tempo, Thu unchanged. Soft-warn fires because Wed tempo + Fri intervals is back-to-back with Thu in between (NO back-to-back here). Use a tighter test: drag Fri intervals → Mon (next week's Tue tempo now back-to-back with Mon). Soft-warn fires.

---

### DP-D.3 — `adapt-plan` template awareness

**Dependencies:** DP-A.2, existing `adapt-plan`.
**File:** `supabase/functions/adapt-plan/index.ts`.

> When `adapt-plan` needs to move a workout (missed session, injury flag, weather), it should:
> 1. Read `training_plans.weekly_template`
> 2. Prefer a move target that matches the template's day-types (move a quality session to another quality-marked day, not to an easy-marked day)
> 3. If no template-conforming move is possible, break the template but write a `plan_adjustments` row with `trigger_type: 'template_break'` explaining why
> 4. Never silently violate the pattern — always surface
>
> Add this as a ranked move-selection step: (1) same-rhythm move, (2) adjacent-day move within same day-type, (3) template-break with explanation. First valid wins.

---

## Cross-cutting requirements (apply across phases)

### CC-1 — Feature flag

Gate the whole feature behind a per-athlete flag `day_picking_enabled` (default false). Stored on `athlete_profiles` or a dedicated `feature_flags` table. Consumers:

- `custom-plan-builder` — ignores `weekly_template` on the plan row if the flag is off.
- `subscribe-to-plan` — falls back to sequential placement if off.
- iOS — hides the picker entry point if off.

Lets you dark-ship Phase A-B, beta-test Phase C with a cohort, then roll Phase D to everyone. Flip via dashboard; no deploy needed.

### CC-2 — Analytics

Track at minimum:

- `picker_rhythm_selected` — which preset (or "custom") + final day_types shape.
- `picker_back_to_back_warned` — fired every time the soft-warn shows.
- `picker_back_to_back_accepted` / `_canceled` — which branch the athlete took.
- `rhythm_changed_midplan` — old anchor → new anchor + which week it fired.
- `drag_drop_used` — which of the 3 shift options was picked.
- `pace_adjustment_proposed` — zone, direction, magnitude.
- `pace_adjustment_accepted` / `_rejected` / `_ignored`.
- `recovery_week_proposed` / `_accepted` / `_rejected`.

Ship with each phase's events so post-launch product iteration has data from day one. Wire via Sentry breadcrumbs + a `user_analytics` table if one doesn't already exist.

### CC-3 — Empty-state behavior

Every consumer must handle `training_plans.weekly_template IS NULL` cleanly. Rule: behave exactly as pre-feature.

- `custom-plan-builder` — emit its default week shape as always.
- `subscribe-to-plan` — sequential placement from start_date.
- `adapt-plan` — skip the template-conforming ranked-move logic (DP-D.3 step 1); go straight to the old behavior.
- iOS weekly view — hide the "Change rhythm" entry; drag-and-drop still works but "Shift my whole plan" is unavailable (no template to rotate). Only "Just today" is offered.

Add a test that every Phase A+B+D handler runs green against a plan with `weekly_template = NULL`.

### CC-4 — Rollback plan

If DP-A.5's backfill misreads a plan:

- Store every inferred template in a `backfill_log` table alongside `plan_id` + `inferred_at` + the raw input it was inferred from.
- Provide a reverse script `clear_backfilled_templates.sql` that nulls `weekly_template` for every plan in the log, scoped to a date range.
- Feature flag (CC-1) also acts as an emergency kill switch — flip off and the templates in the DB are ignored by consumers.

If a migration in Phase A or B needs to revert, each migration must ship with a `DROP COLUMN` / `DROP FUNCTION` rollback SQL file committed alongside. Label `<timestamp>_NNN_rollback.sql`.

---

## Verification checklist (end of build)

- [ ] A new plan created via `custom-plan-builder` with `rhythm: Tu/Fr/Sun` places every quality workout on Tuesday/Friday and every long run on Sunday for every week of the plan
- [ ] Athlete can drag Tuesday's tempo to Wednesday; soft-ask appears; choosing "shift all" rotates the entire rhythm; choosing "just today" leaves Friday/Sunday untouched
- [ ] Dragging creates back-to-back quality → second soft-warn appears
- [ ] Pace adjustment fires no earlier than 6 quality sessions after plan start (2-week warm-up)
- [ ] Adjustment surfaces as a `plan_adjustments` row with `auto_applied=false` — athlete must accept
- [ ] Triggered adjustment fires when 2-of-3 quality sessions miss by >10s OR 3-of-4 include a qualitative signal
- [ ] Recovery week replaces quality with moderate+easy and reduces volume 25-35%
- [ ] "Change rhythm" mid-plan only rewrites current week forward, not past weeks
- [ ] `adapt-plan` prefers template-conforming moves; when it must break template, surfaces a plan_adjustments row

---

## Sequencing for a single engineer

**Week 1** — DP-A.1 → A.2 → A.3 → A.4 → A.5 (data model + plan generation end-to-end)
**Week 2** — DP-B.1 → B.2 → B.3 (pace adjustment logic)
**Week 3** — DP-C.1 → C.2 → C.3 → C.4 (iOS picker)
**Week 4** — DP-D.1 → D.2 → D.3 (drag + adapt-plan awareness)

Each prompt is sized for one Claude Code session / one PR. Ship in order; don't let later phases start until earlier phases are verified.

---

## Still outstanding (once you send them)

- **Three archetypal athletes** for concrete preset validation (DP-C.1 has placeholder presets)
- **Screenshot of `JoinCoachPlanSheet.swift`** for DP-C.3 visual alignment

These don't block starting — the placeholder presets are fine to build against — but tuning the final preset library benefits from real archetype data.

---

*End of prompts. Companion: `docs/handover-adaptive-plan-day-picking.md` for problem framing, `adaptive-plan-loop-prompts.md` for the adjacent pace-profile work these build on.*
