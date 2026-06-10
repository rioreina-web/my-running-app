# Athlete-Side Adaptive Plan — execution prompts

Copy-paste these into Claude to ship each phase. Each prompt is
self-contained (points at the right files, specifies scope, defines done).

Source of truth: `docs/athlete-plan-ux.md`.
Visual reference: `docs/athlete-plan-ux-mockup.html`.
Already shipped: migration `20260424100000_athlete_plan_ux.sql`,
`web/src/app/(app)/plan/page.tsx` Phase 1 shape.

---

## Dependency graph

```
AP-1 (shift-day fn) ──► AP-2 (Move day UI) ──► AP-3 (coach adjustments block)

AP-4 (rationale fn) ──► AP-5 (backfill) ──► AP-6 (Why drawer UI)

AP-7 (reshape-week fn) ──► AP-8 (Reshape dialog UI) ──► AP-9 (coach yellow dashboard)

AP-10 (subscribe-to-plan uses paces.ts)      ← independent, pace-system thread

AP-11 → AP-12 → AP-13 (iOS)                  ← waits on at least AP-2
```

## Recommended sequence

1. **AP-1, AP-2** — ship athlete agency first. Smallest change that makes the plan feel alive.
2. **AP-4, AP-5** — rationales. Gives every day a "why." Makes the UI feel like coaching, not a scheduler.
3. **AP-6** — the Why drawer. Pulls through AP-4's data.
4. **AP-3** — coach's adjustments view. So you can actually see what athletes are doing to their plans.
5. **AP-7, AP-8, AP-9** — the power move. Reshape.
6. **AP-10** — backend pace-system cleanup. Can slip in any time.
7. **AP-11, AP-12, AP-13** — iOS parity.

---

## AP-1 — Backend: `shift-day` edge function

**Purpose.** Athlete moves a single workout to a different day within the same week. Swaps `scheduled_date` values; writes a `plan_adjustments` row with `action_type='shift_day'`, `tier='green'`.

**Prerequisites.** Migration `20260424100000_athlete_plan_ux.sql` deployed.

**Prompt:**

```
Ship a new Supabase edge function `shift-day` at
`supabase/functions/shift-day/index.ts`.

Contract:
  POST /shift-day
  body: { scheduled_workout_id: uuid, new_date: "YYYY-MM-DD" }
  auth: user JWT

Logic:
  1. Verify the workout belongs to the calling user (RLS)
  2. Load the workout's plan_id, current date, week bounds
  3. Validate: new_date must be in the same Mon-Sun week as the original
  4. Find any workout already on new_date for this user; swap dates
     if one exists (atomic in a single transaction)
  5. Write a plan_adjustments row:
       action_type='shift_day', tier='green',
       action_payload={ before: {...}, after: {...}, diff: [...] },
       reason_code='shift_day', auto_applied=true, applied_at=now()
  6. Return { ok: true, swapped_with: uuid | null, new_date }

Rules:
  - Never let an athlete move a workout OUTSIDE the current week (403)
  - Never let an athlete move a past-dated workout (403)
  - If the destination has a rest day, the rest day takes the source slot

Write the test file too: `supabase/functions/shift-day/index.test.ts`.
Cover: happy path, same-week validation, past-date rejection, swap-with-
rest-day case.

Reference: docs/athlete-plan-ux.md §5.
```

**Done when.** Function deploys, tests pass, `plan_adjustments` rows appear correctly.

---

## AP-2 — Frontend: wire the "Move day" action

**Purpose.** The disabled `Move day` and `⋯` buttons on `/plan/page.tsx` become real.

**Prerequisites.** AP-1 deployed.

**Prompt:**

```
In `web/src/app/(app)/plan/page.tsx`, wire the Move affordance.

Create a client component `web/src/components/plan/move-day-sheet.tsx`:
  - Opens as a bottom sheet on mobile, right drawer on desktop
  - Shows the 7 days of the current week as pickable chips
  - Disables the source day and any past days
  - Shows the current workout at the top for context
  - On pick: POSTs to /api/shift-day, shows success, triggers a
    page revalidation

Create `web/src/app/api/shift-day/route.ts` — a thin Next proxy that
forwards to the supabase edge fn with the user's session token.

Update `DayRow` and `TodayBand` in plan/page.tsx:
  - Remove `disabled` from `Move day` and `⋯` buttons
  - The `⋯` button on non-quality days opens the same sheet
  - Quality day `Move day` opens the same sheet with a warning:
    "Moving a quality day — the rest of the week may shift too"

Don't change the visual shape — just make the buttons live.

Reference: docs/athlete-plan-ux.md §2A, §3.
```

**Done when.** Athlete can move any day within the current week; swap happens visibly; reload shows persisted state.

---

## AP-3 — Coach view: adjustments history block

**Purpose.** The coach sees what their athletes are doing to their plans — prefer yellow, then green, past 4 weeks.

**Prerequisites.** AP-2 shipping green-tier rows.

**Prompt:**

```
Add an "Adjustments" block to the coach's athlete detail view
at `web/src/app/(app)/coach-portal/athletes/[id]/page.tsx`
(create if missing; reuse existing conventions).

Query:
  select id, applied_at, action_type, tier, reason_code, reason_text, action_payload
    from plan_adjustments
    where user_id = <athlete> and applied_at > now() - interval '28 days'
    order by applied_at desc
    limit 50

Render a compact table:
  | Date | Week | What | Reason | Tier |
  --------------------------------------
  Yellow rows visually highlighted (coral border-left).
  Clicking a row expands action_payload's before/after as a diff.

If there are 0 yellow-tier rows in the last 28 days, show a one-line
"Plan compliance looking good — no escalations" empty state.

Do not include action buttons (accept/revert) yet — those are a
separate skill.

Reference: docs/athlete-plan-ux.md §2D, §3.
```

**Done when.** Coach loads an athlete's page and sees a clean, sortable table of recent adjustments with visual severity.

---

## AP-4 — Backend: `generate-day-rationale` edge function

**Purpose.** Every day of a new plan-week gets `rationale_short` (subtitle line) and `rationale_full` (structured drawer content) written.

**Prerequisites.** Migration deployed. `_shared/paces.ts` shipped.

**Prompt:**

```
Ship a new Supabase edge function `generate-day-rationale` at
`supabase/functions/generate-day-rationale/index.ts`.

Contract:
  POST /generate-day-rationale
  body: { plan_id: uuid, week_number: number }
  auth: user JWT OR service role

Logic:
  1. Load the 7 scheduled_workouts for (plan_id, week_number)
  2. Load the athlete's pace profile + goal race
  3. Load the plan_template for plan notes + phase context
  4. For each day, build a context object:
       { date, workout_type, target_distance_miles, target_pace,
         prev_day, next_day, days_since_last_quality, days_until_next_quality,
         week_phase, goal_race }
  5. Single LLM call (use the coaching-agent prompt shape) that returns
     JSON for all 7 days at once:
       [{ date, rationale_short, rationale_full: { why_today[], why_this_workout, why_this_pace }}]
  6. UPDATE scheduled_workouts SET rationale_short=..., rationale_full=...
     for each row

Call this from `subscribe-to-plan` AFTER workouts are inserted (fire
and forget with error logging — non-blocking for the subscribe flow).

Also expose it as a callable for reshape-week and any manual re-generation.

Reference: docs/athlete-plan-ux.md §5. Use the existing multi-model
router conventions for the LLM call.
```

**Done when.** New plan subscriptions populate rationale columns. One week of rationales costs ≈1 LLM call, not 7.

---

## AP-5 — Backfill rationales for existing plans

**Purpose.** Plans that pre-date AP-4 also need rationales.

**Prerequisites.** AP-4 deployed.

**Prompt:**

```
Write a one-shot backfill script at
`supabase/functions/backfill-rationales/index.ts` (callable only via
service role).

Logic:
  1. Find all active training_plans (status='active')
  2. For each plan, find distinct week_numbers with scheduled_workouts
     where rationale_short IS NULL
  3. For each (plan, week), call generate-day-rationale
  4. Rate-limit: max 10 concurrent; sleep 500ms between calls
  5. Log progress: how many weeks done, how many failed

Idempotent — re-running skips already-populated rows.

Add a README.md in the function folder with the manual invocation:
  `curl -X POST https://<proj>.supabase.co/functions/v1/backfill-rationales \
     -H "Authorization: Bearer $SERVICE_ROLE_KEY"`

Reference: docs/athlete-plan-ux.md §6 Phase 1 backfill step.
```

**Done when.** Manual run completes; every active plan's future weeks have rationales populated.

---

## AP-6 — Frontend: the "Why?" drawer

**Purpose.** The `Why this?` button on quality days opens the rationale drawer.

**Prerequisites.** AP-4 deployed (or AP-5 run) so rationale_full is populated.

**Prompt:**

```
Create `web/src/components/plan/rationale-drawer.tsx` matching the
mockup in `docs/athlete-plan-ux-mockup.html` (second card).

Props: { workout: ScheduledWorkout, planName: string, open, onClose }

Renders:
  - Title line: "{day}'s {workout_type} · why this, why now"
  - Subtitle: the short workout detail (target_pace, distance, structure)
  - Three sections: Why today (bulleted), Why this workout, Why this pace
    — all from rationale_full
  - Footer actions: Move this workout (opens MoveDaySheet),
    Skip and explain (yellow-tier, opens confirm dialog), Done

Fall-through: if rationale_full is null, render a one-line fallback:
  "This day's why is being written. Check back soon."

Wire into plan/page.tsx:
  - Remove `disabled` from `Why this?` on TodayBand
  - Add `Why?` button to DayRow for quality days
  - Tapping opens the drawer with that day's workout

Reference: docs/athlete-plan-ux.md §2B.
```

**Done when.** Tapping `Why this?` on a quality day opens a drawer showing the coach's reasoning in three sections.

---

## AP-7 — Backend: `reshape-week` edge function

**Purpose.** The power verb. Athlete re-plans a whole week against the coach's constraints.

**Prerequisites.** `_shared/paces.ts` deployed.

**Prompt:**

```
Ship a new edge function `reshape-week` at
`supabase/functions/reshape-week/index.ts`.

Contract:
  POST /reshape-week
  body: {
    plan_id: uuid, week_number: number,
    changes: {
      reason_code: "travel"|"flat_week"|"extra_rest_day"|"extra_day"|"other",
      reason_text?: string,
      blocked_dows?: number[],    // 0=Mon..6=Sun
      volume_target?: number,     // miles, overrides coach default
      keep_qualities: boolean,    // false = drop a quality
      drop_quality_type?: string  // if keep_qualities=false
    }
  }

Logic:
  1. Load the plan_template (for coach constraints: mileage range,
     quality count, preferred days)
  2. Load athlete's pace profile via paces.ts paceTableFromProfile()
  3. Determine tier:
       - volume cut >20% → yellow
       - drop a quality → yellow
       - anything else → green
  4. Re-materialize the week's scheduled_workouts rows using the
     subscribe-to-plan materializer BUT scoped to one week and
     respecting blocked_dows + volume_target + keep_qualities
  5. Compute diff against existing week
  6. Return mode "preview" if tier=yellow OR if body has
     `?preview=1` — don't commit, just return the diff
  7. Otherwise commit: DELETE existing week + INSERT new,
     call generate-day-rationale for the new week,
     write plan_adjustments (action_type='reshape_week', tier, diff)

Completed days MUST NOT be touched — freeze them, work around them.

Write tests covering: green reshape, yellow reshape preview,
blocked-day handling, volume cap, keep_qualities=false path.

Reference: docs/athlete-plan-ux.md §5, §7.
```

**Done when.** Given realistic inputs, the function returns a sane diff; green commits write `plan_adjustments`; yellow returns preview without committing.

---

## AP-8 — Frontend: Reshape dialog + diff preview

**Purpose.** The dialog from the mockup's third card, plus a diff-preview modal when tier=yellow.

**Prerequisites.** AP-7 deployed.

**Prompt:**

```
Create `web/src/components/plan/reshape-week-dialog.tsx` matching the
mockup in `docs/athlete-plan-ux-mockup.html` (third card).

Fields: reason-code chips, blocked-days toggle row, volume-target
radio group, keep-qualities radio group, warning strip (show if
volume cut >15%).

Flow:
  1. User fills it in, clicks "Reshape my week →"
  2. POST to /api/reshape-week?preview=1
  3. If tier=green: show inline confirmation "This is in your green zone,
     reshaping now..." then auto-commit (second POST without preview)
  4. If tier=yellow: show a DiffPreview modal with before/after week
     side-by-side, a "Heads up — this will flag to your coach" banner,
     and [Cancel] [Confirm] buttons
  5. On commit: refresh the plan page, show toast "Week reshaped"

Create `web/src/components/plan/week-diff-preview.tsx` — a two-column
grid (Old week | New week) with changed days highlighted.

Wire the "Reshape this week" button on plan/page.tsx:
  - Remove disabled
  - Opens the dialog

Reference: docs/athlete-plan-ux.md §2C.
```

**Done when.** End-to-end: athlete clicks Reshape → fills form → sees preview (for yellow) or immediate commit (for green) → page reflects new week.

---

## AP-9 — Coach dashboard: yellow-tier queue

**Purpose.** The coach has one place to see all recent yellow-tier adjustments across their athletes.

**Prerequisites.** AP-2, AP-7 producing yellow rows.

**Prompt:**

```
Add a "Adjustments needing eyes" section to the coach dashboard
at `web/src/app/(app)/coach-portal/page.tsx`.

Query (uses the partial index idx_plan_adjustments_tier_applied):
  select pa.*, u.full_name, u.avatar_url
    from plan_adjustments pa
    join coach_athletes ca on ca.athlete_id = pa.user_id
    join users u on u.id = pa.user_id
    where ca.coach_id = <me>
      and pa.tier = 'yellow'
      and pa.applied_at > now() - interval '14 days'
      and pa.acknowledged_by_user_at is null
    order by pa.applied_at desc
    limit 20

Render each as a compact row:
  [Avatar] Sarah M · shifted tempo from Tue to Thu · 2h ago
                                      [View] [Acknowledge]

Empty state: "No adjustments needing eyes. Nice."

View opens the same drawer as AP-3's expansion.
Acknowledge: PATCH plan_adjustments.acknowledged_by_user_at = now().

Reference: docs/athlete-plan-ux.md §2D, §3.
```

**Done when.** Coach sees a single-screen queue of yellow-tier events with visible names, can acknowledge in one click.

---

## AP-10 — Backend: `subscribe-to-plan` uses `_shared/paces.ts`

**Purpose.** Close the pace-system-rework.md Phase C open item — edge fn and web editor agree on pace math.

**Prerequisites.** `_shared/paces.ts` shipped (done — 2026-04-24).

**Prompt:**

```
In `supabase/functions/subscribe-to-plan/index.ts`, replace line 197's
`const athletePaces = athleteState?.pace_zones ?? {};` and the downstream
logic that depends on the old shape.

New approach:
  1. Import from `../_shared/paces.ts`: paceTableFromProfile
  2. Import from `../_shared/resolve-pace.ts`: getOrBuildPaceProfile
  3. Load the athlete's pace profile:
       const profile = await getOrBuildPaceProfile(supabase, userId);
  4. Build the 12-zone table:
       const athletePaces = paceTableFromProfile(profile);
  5. If null (no fitness data), fall back to the coach's plan
     paceAnchor goal:
       const anchor = template.phase_config?.paceAnchor;
       athletePaces = anchor ? derivePaceTableFromGoal(anchor.goalSecPerMile, anchor.raceDistance) : null;

The `personalizeWorkoutData()` function expects an object keyed by zone
name with sec/mi values — our 12-zone `Record<PaceZone, number>` is
compatible. Verify by diffing one realistic case before and after.

Update the test file: `supabase/functions/subscribe-to-plan/index.test.ts`.

Reference: pace-system-rework.md §3 Phase C, docs/athlete-plan-ux.md §5.
```

**Done when.** A subscribe-to-plan run for a known athlete produces the same pace strings the `/pace-chart` page shows them — no drift.

---

## AP-11 — iOS: port This Week view

**Purpose.** iOS gets the same shape as web's new `/plan/page.tsx`.

**Prerequisites.** AP-1 through AP-6 on web.

**Prompt:**

```
In `RunningLog/RunningLog/Training/`, create `ThisWeekView.swift` as the
primary training screen (replaces or renames the current TrainingPlanView
top surface).

Shape matches docs/athlete-plan-ux-mockup.html — header, today band,
week rows, stats footer, reshape button.

Use existing models:
  - ScheduledWorkout (add rationale_short, rationale_full to the struct)
  - TrainingPlan
  - AthletePaceProfile

Data layer updates:
  - Update the scheduled_workouts select in TrainingPlanService to
    include rationale_short, rationale_full
  - Add rationale fields to the Swift model

Render using SwiftUI Cards with the existing design system (check
DesignTokens.swift for colors / spacing).

Routing:
  - Update RunningLogApp's root navigation to land on ThisWeekView
    instead of TrainingDashboardView for athletes with an active plan
  - Keep TrainingDashboardView reachable as a secondary tab

Reference: docs/athlete-plan-ux.md §2A, §2B.
```

**Done when.** iOS athletes see the same today-pinned, rationale-carrying week shape as the web.

---

## AP-12 — iOS: Move day via long-press

**Prerequisites.** AP-1 deployed, AP-11 shipped.

**Prompt:**

```
In iOS `ThisWeekView.swift`, add long-press interaction on any day row
to open a MoveDaySheet.

MoveDaySheet shape:
  - Renders the 7 days of the current week as a day picker
  - Disables source day and past days
  - "Move to {day}" confirms
  - Shows the warning "This moves a quality day" if source is a quality

Network: POST to the shift-day edge fn via the existing AuthenticatedClient
pattern in RunningLog's services folder.

After success: invalidate the TrainingPlanService cache and refetch the
week.

Reference: docs/athlete-plan-ux.md §2A.
```

**Done when.** iOS athlete long-presses a day, picks a target, sees the swap.

---

## AP-13 — iOS: Reshape dialog

**Prerequisites.** AP-7 deployed, AP-11 shipped.

**Prompt:**

```
In iOS, create `ReshapeWeekSheet.swift` matching the mockup's third card.

Use native SwiftUI form primitives (TextField, Toggle, Picker, Button).
Don't re-style.

Flow:
  1. Collect reason_code, blocked_dows, volume_target, keep_qualities
  2. Call reshape-week?preview=1 via AuthenticatedClient
  3. If green: auto-commit (confirm screen is just "Reshaping...")
  4. If yellow: show WeekDiffPreview screen (new view) with before/after
     — use two VStacks side by side, changed days highlighted in coral
  5. On confirm: POST again without preview flag, invalidate cache

Reference: docs/athlete-plan-ux.md §2C.
```

**Done when.** iOS athlete completes a full reshape flow that produces the same outcome as web.

---

## One-off: smoke test after each phase

Not a prompt — a discipline. After each AP-X above lands:

- Subscribe to a plan as a test account
- Make the new change (shift, reshape, read rationale)
- Verify `plan_adjustments` row appears with the expected tier / reason
- Verify the coach's dashboard reflects it (for AP-3 / AP-9)
- Verify iOS shows the same state (for AP-11+)

Keep the test account data clean. Consider seeding a dedicated
`rio+test@postrundrip.com` account so runs don't pollute personal data.
