# Athlete onboarding rebuild — execution prompts

Copy-paste these into Claude to ship each phase of
`athlete-onboarding-redesign.md`. Each prompt is self-contained — paste
into a fresh Claude session, no prior context needed.

**Source of truth:** `athlete-onboarding-redesign.md` at the repo root.
**Mockup reference:** `RunningLog/Training/JoinCoachPlanFlowMockup.swift`.

Already shipped (need to deploy):
- Migration `20260425200000_athlete_subscription_preferences.sql` — Phase 1
- Static SwiftUI mockup of the new sheet — Phase 2 reference

---

## AO-1 — Phase 2: rebuild `JoinCoachPlanSheet` from the mockup

**Prerequisites:** Migration `20260425200000_athlete_subscription_preferences.sql` deployed (`supabase db push`). Mockup eyeballed and approved.

**Prompt:**

```
Rebuild RunningLog/RunningLog/Training/JoinCoachPlanSheet.swift to
match the static mockup in JoinCoachPlanFlowMockup.swift. The mockup
has the visual + interaction shape; this PR adds state wiring +
the subscribe-to-plan call.

Read first:
  1. athlete-onboarding-redesign.md (full spec)
  2. RunningLog/RunningLog/Training/JoinCoachPlanFlowMockup.swift (visual reference)
  3. RunningLog/RunningLog/Training/JoinCoachPlanSheet.swift (current implementation, ~250 LOC)
  4. supabase/migrations/20260425200000_athlete_subscription_preferences.sql (the new columns)

Implementation:
  - Replace JoinCoachPlanSheet's body with the 6-section structure
    from the mockup. Keep the same struct name + presentation
    semantics so callers don't change.
  - Add @State for: goalUseCoach, goalHours/Min/Sec, goalDistance,
    selectedRestDows, selectedQualityDows, longRunDow,
    currentWeeklyMileage, rampStartMileage, useFullRangeFromWeek1,
    stridesPreQuality, recoveryAfterLong, doublesOnEasy, startDate.
  - Pre-fill currentWeeklyMileage from the last 4 weeks of training
    logs when available (TrainingPlanService.recentMileageAvg or
    similar). Fall back to coach's lower bound when no logs.
  - Pre-fill selectedQualityDows from coach's plan template's
    pattern (look at how the existing sheet reads template data).
  - Pre-fill goalUseCoach = true when the plan has a paceAnchor.
  - Live preview at the bottom: simple inline materializer
    rendering the 7 days of week 1. Just enough to show what
    rest/quality/long-run looks like; no actual paces yet.
    Real preview comes in AO-3.
  - Submit button (existing pattern):
      - Validate: at least one quality day picked OR coachUseCoach
        path doesn't require it (coach-set qualities).
      - POST to subscribe-to-plan with body extended:
          {
            ...existing fields,
            subscription_preferences: {
              rest_dows: [...],
              preferred_quality_dows: [...],
              long_run_dow: ...,
              volume_ramp: { start_mileage, ramp_to_coach_target, ramp_weeks: 4 },
              shape_prefs: { strides_pre_quality, recovery_after_long, doubles_on_easy_days },
              current_weekly_mileage
            }
          }
      - Goal time still goes via existing path; if goalUseCoach
        is false, ALSO upsert athlete_pace_profiles with the
        athlete's chosen goal (this is the unbundling from
        athlete-plan-ux.md).

Don't touch:
  - subscribe-to-plan edge function (next prompt: AO-2)
  - update-plan-goal edge function (handled separately in AO-4)

Out of scope (separate prompts):
  - Edge function reads + applies the new preferences (AO-2)
  - Live preview using a real materializer (AO-3)
  - Edit-from-Plan-tab path (AO-5)

When done:
  - Type-check passes
  - Old sheet behavior preserved when subscription_preferences
    is omitted (backward compat with the edge function pre-AO-2)
  - Manual smoke test on simulator: enter join code, fill all 6
    sections, hit Subscribe — verify the new fields appear in
    the request payload (use Xcode's network log).

Reference: athlete-onboarding-redesign.md §3 (proposed flow), §6 (iOS rebuild).
```

**Done when:** new sheet renders all 6 sections, fills with sensible defaults, submits to existing edge function, doesn't break for users who haven't deployed the edge function update yet.

---

## AO-2 — Phase 3: `subscribe-to-plan` reads athlete preferences

**Prerequisites:** AO-1 deployed (or in flight — edge function ignores unknown body fields, so iOS can ship first).

**Prompt:**

```
Update supabase/functions/subscribe-to-plan/index.ts to read the
new `subscription_preferences` body field and apply it to the
materialization.

Read first:
  1. athlete-onboarding-redesign.md (full spec, esp §5 + §7)
  2. supabase/migrations/20260425200000_athlete_subscription_preferences.sql
  3. supabase/functions/subscribe-to-plan/index.ts (current impl, ~640 LOC)

Implementation:
  1. Parse body.subscription_preferences (optional). Shape:
       {
         rest_dows: number[],
         preferred_quality_dows: number[],
         long_run_dow: number | null,
         volume_ramp: { start_mileage, ramp_to_coach_target, ramp_weeks } | null,
         shape_prefs: { strides_pre_quality, recovery_after_long, doubles_on_easy_days } | null,
         current_weekly_mileage: number | null
       }

  2. Persist to athlete_plan_subscriptions on insert (line ~455).
     Map the JSON fields directly to the new columns.

  3. Apply preferences during materialization (the for-loop over
     weeks, ~line 211). Order of precedence:
       athlete subscription > template defaults > hardcoded fallback

     Specifically:
       - rest_dows: replace template.rest_day_of_week logic. Empty
         array = no forced rest; non-empty = each dow gets type "rest".
       - preferred_quality_dows: shift the materializer's
         qualityDaysByDow keys to match the athlete's pick. The coach
         specified N quality days in templateWorkouts; map them onto
         the athlete's dow choices in order.
       - long_run_dow: when set, ensure the longest quality lands on
         this dow (swap if needed).
       - volume_ramp: when set, override targetMileage per week:
            startWeek = volume_ramp.start_mileage
            endWeek   = avg(week.targetMilesMin, week.targetMilesMax)
            interpolate over volume_ramp.ramp_weeks; full coach target
            after that.
         When `ramp_to_coach_target` is false, just use start_mileage
         every week.
       - shape_prefs: replace easyDayPrefs.{autoStrides,recoveryAfterLong}
         with the athlete's choices. doubles_on_easy_days is a future
         hook (no-op for now; log when true).

  4. Backward compat: when subscription_preferences is missing,
     behavior must be identical to today.

  5. Tests in subscribe-to-plan/index.test.ts — add 3 cases:
     - subscription with only rest_dows + quality_dows (verify materialized days)
     - subscription with volume_ramp (verify weekly mileage matches expected ramp)
     - no subscription_preferences (verify nothing changed from today)

Do NOT touch:
  - The flatten-removal logic (already done)
  - The coach pace anchor resolver (already done)

Reference: athlete-onboarding-redesign.md §5.
Companion files: pace-system-rework.md, docs/build-adaptive-plan-suspension.md.
```

**Done when:** Tests pass, deploy succeeds, a manual subscribe with preferences produces a week 1 with the picked rest days, picked quality days, and ramped mileage.

---

## AO-3 — Phase 4: live week-1 preview using real materializer

**Prerequisites:** AO-1 + AO-2 deployed.

**Prompt:**

```
The onboarding sheet (AO-1) has a placeholder week-1 preview using
inline mock logic. Replace it with a real materializer that
mirrors the edge function's output.

Read first:
  1. RunningLog/RunningLog/Training/JoinCoachPlanSheet.swift
     (the AO-1 implementation)
  2. supabase/functions/subscribe-to-plan/index.ts (the materializer
     this preview should mirror)

Implementation:
  - Create RunningLog/RunningLog/Training/PlanPreviewMaterializer.swift
    — a Swift port of the materializer's logic, scoped to JUST week 1.
  - Inputs: coach's week-1 template, athlete's preferences (the same
    shape as the edge function's subscription_preferences), athlete's
    pace ladder.
  - Output: array of 7 PreviewDay structs:
      { dow, type ("quality" | "easy" | "rest" | "longRun"),
        miles, paceLabel? }
  - Wire the preview into JoinCoachPlanSheet — re-run the materializer
    on every state change. Pace ladder comes from PaceCalculator using
    the athlete's goal time.
  - Performance: materializer should run in <5ms on a phone. No I/O,
    pure function.

Edge cases:
  - Empty rest_dows + 7-day quality plan: athlete sees 7 days of work.
    Show, but render a footer: "no rest day — your call."
  - Goal not set: pace labels show as "—" not 0:00 or fake numbers.
  - Volume ramp resulting in week-1 mileage of 0: show but warn.

Reference: athlete-onboarding-redesign.md §6 ("Live preview implementation").
```

**Done when:** week-1 preview re-renders in <100ms as the athlete adjusts inputs, shows real days with correct rest/quality/long-run placement, paces match the athlete's goal-derived ladder.

---

## AO-4 — Decoupled goal save (athlete profile path)

**Prerequisites:** None — independent of the onboarding rebuild.

**Prompt:**

```
The current update-plan-goal edge function only writes to
training_plans (per-plan goal). The new `GoalAndPacesCard` and the
onboarding sheet need a path that writes to athlete_pace_profiles
(athlete-level goal) so paces flow even without a plan.

Read first:
  1. supabase/functions/update-plan-goal/index.ts (current impl)
  2. supabase/functions/_shared/paces.ts (paceTableFromProfile)
  3. RunningLog/RunningLog/Training/EditGoalSheet.swift
  4. docs/athlete-plan-ux.md §2A goal-card

Two-part change:

  Part 1 — Edge function:
    Update update-plan-goal to handle plan_id: null. When null:
      - Skip training_plans write
      - Compute pace from goal_time_seconds + race_distance
      - Upsert athlete_pace_profiles { user_id, goal_race_distance,
        <distance>_pace_seconds }
    When plan_id is set (existing path):
      - Update training_plans.target_time_seconds + target_race_distance
      - ALSO upsert athlete_pace_profiles (so goal stays in sync)

  Part 2 — iOS:
    Update EditGoalSheet to accept plan: TrainingPlan? (optional).
    When plan == nil:
      - Hide race-date picker (no plan = no race date)
      - Submit calls update-plan-goal with plan_id: null
    When plan != nil: existing behavior.

Test cases:
  - Save goal without active plan → athlete_pace_profiles row exists
  - Save goal with active plan → both tables update
  - Subscribe to a plan after setting athlete goal → coach anchor
    wins, athlete goal becomes the fallback (already correct in
    resolveAthletePaces; just verify)

Reference: athlete-onboarding-redesign.md §6 (resolved Q4).
```

**Done when:** Athlete with no active plan can set 2:30 marathon goal from the Training tab card; pace ladder renders; subsequent subscribe-to-plan respects the saved goal as fallback.

---

## AO-5 — Phase 5: edit subscription preferences mid-plan

**Prerequisites:** AO-1, AO-2 deployed.

**Prompt:**

```
Athletes need to be able to change their subscription preferences
after subscribing — rest day shifted, mileage ramp adjusted, etc.
Resolved Q4: subscriptions are always editable.

Read first:
  1. RunningLog/RunningLog/Training/TrainingPlanView.swift (toolbar menu)
  2. RunningLog/RunningLog/Training/JoinCoachPlanSheet.swift (post AO-1)
  3. supabase/functions/subscribe-to-plan/index.ts (rematerialize logic
     to add)

Implementation:

  1. Add an entry point in TrainingPlanView's toolbar ⋯ menu when an
     active subscription exists: "Edit plan preferences."

  2. Reopen the same JoinCoachPlanFlow sheet in "edit mode":
     - Pre-fill from existing athlete_plan_subscriptions row
     - Submit button text: "Update preferences →"
     - Show a warning before submit: "This will rebuild your plan
       from this week forward. Past workouts stay as-is."

  3. Edge function (subscribe-to-plan or new endpoint):
     - Accept mode: "create" | "rematerialize" in body.
     - "create" = today's behavior.
     - "rematerialize":
        a. Update athlete_plan_subscriptions with new preferences.
        b. Find the current calendar week (today's Monday-anchored week).
        c. Delete scheduled_workouts for that week and all future weeks
           where status = 'scheduled' (preserve completed/skipped).
        d. Re-run materialization for those weeks using the new
           preferences.
        e. Return the new schedule.

  4. iOS handles the response: refresh the calendar.

Edge cases:
  - Athlete has completed workouts THIS week — don't rebuild this week,
    rebuild from next Monday onward.
  - Athlete changes goal time during edit → also writes to
    athlete_pace_profiles (AO-4 must be deployed first).
  - Race-date change is NOT allowed mid-plan via this path; that goes
    through Edit Goal sheet which has different consequences.

Reference: athlete-onboarding-redesign.md §7 Phase 5.
```

**Done when:** athlete reopens the sheet from Plan tab, changes rest day from Friday to Sunday, future weeks rebuild with the new rest day, past weeks unchanged.

---

## AO-6 — Smoke-test path (after each phase)

Not a prompt — a discipline. After each AO-N above lands:

1. Subscribe a fresh test athlete to a coach's plan via the new flow.
2. Verify the row in `athlete_plan_subscriptions` has the expected columns populated.
3. Open the plan in the iOS Plan tab — calendar should reflect picked rest/quality/long-run days.
4. Pick one workout in week 1, verify pace label matches the goal-derived ladder.
5. (After AO-5) edit preferences mid-plan, verify only future weeks rebuild.

Use a dedicated test account so the data stays clean.

---

## Cadence suggestion

- **Day 1:** Deploy migration → AO-1 (build + ship the new iOS sheet)
- **Day 2:** AO-2 (edge function) + smoke test end-to-end
- **Day 3:** AO-4 (decoupled goal save) — small, ships independently
- **Day 4:** AO-3 (live preview) — polish, biggest UX delta
- **Day 5:** AO-5 (edit-mid-plan) — completion of the loop

Total ~3 days of focused work spread over a week. Each phase is
shippable independently; no need to land them all before the next.

---

*Last updated 2026-04-25. See also:
[athlete-plan-prompts.md](athlete-plan-prompts.md) for the broader
athlete-side UX work,
[athlete-onboarding-redesign.md](../athlete-onboarding-redesign.md)
for the spec.*
