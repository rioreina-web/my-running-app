# Phase B — Live Plan Editing: Build Plan

**Date:** 2026-07-03
**Status:** Plan for review (no code written yet)
**Source spec:** `adaptive-coach-plan-builder-spec-2026-07-03.md` §5 (R5)
**Scope:** Phase B only — manual live-plan editing. Assisted AI rewrite is
Phase E and is explicitly **out of scope** here.

This plan is grounded in a read of the actual codebase (coach portal, edge
functions, and the `plan_adjustments` / `scheduled_workouts` / `training_plans`
data model). Where the spec and the code disagree, the code wins and the note
is called out.

---

## 0. TL;DR — what Phase B delivers

A coach, on a specific athlete's page in the web portal, can:

1. **See the athlete's live plan** as a calendar (planned workouts, week by week).
2. **Pick a future week range** (e.g. W7–W10) and open an editor.
3. **Manually edit** those weeks — swap key sessions, change mileage ranges,
   insert a recovery/rest week — using the same week-grid UX as the builder.
4. **Review a week-by-week diff** and confirm.
5. On confirm, a new **`rewrite-block` edge function** writes the changes to the
   athlete's `scheduled_workouts` and records the change in the `plan_adjustments`
   ledger (one row per changed week), reversibly.
6. The coach sees an **adjustments feed** on the athlete page (newest first,
   tier-colored) — this also surfaces the Phase A athlete day-moves.
7. The athlete gets a **"Coach updated W7–W10 — sickness recovery"** banner
   (iOS touch — smaller, can trail the web work).

**R5 (assisted rewrite) and the athlete-facing feedback loop (R7) are not in
this phase.** No LLM is involved in Phase B — it's deterministic manual editing.

---

## 1. Key finding (CORRECTED): repo is ahead of prod — a deploy gap blocks the core path

> **Update 2026-07-03, after querying the live database (`RunningAppMVP2`,
> project `aqdijapxmjqaetursrde`).** The original version of this section said
> "Phase B needs zero migrations." That was true against the *repo* migration
> files and **false against production**. The real state:

**The repo's migration files exist but are NOT applied to prod.** The latest
applied migration in prod is `20260702210000`. Everything dated `20260703*`
(including `20260703120000_plan_adjustment_vocab_for_coach_plans.sql`, the
"Phase A" vocab migration) is authored but **pending `supabase db push`**.
Verified consequences in the live schema:

- `plan_adjustments` CHECK constraints still list only the **original 7
  trigger_types / 6 action_types** — they REJECT `coach_rewrite`,
  `user_action`, `rewrite_block`, `shift_day`.
- `plan_adjustments` has **no `tier`, `reason_code`, `reason_text`, or
  `week_number` columns** in prod (those come from `20260424100000` +
  `20260703120000`, both unpushed).
- The `scheduled_workouts` date column is literally named **`date`**, not
  `scheduled_date`. There is no `scheduled_date` column and no rename migration.
- `scheduled_workouts` has **no `rationale_short` / `rationale_full`** columns
  in prod (despite `types.ts` and CLAUDE.md claiming they exist) — relevant to
  Phase C, but more evidence the ledger has diverged.

**Two distinct problems, don't conflate them:**

1. **Deploy gap (needs a `db push`, not new code).** The intended schema exists
   in repo migrations; the team just hasn't pushed. `rewrite-block` targets the
   intended (post-push) schema and will error at its ledger insert until
   `20260424100000` + `20260703120000` land in prod.
2. **A real repo bug (`scheduled_date`).** `shift-day/index.ts`,
   `web/src/lib/types.ts`, `web/.../plan/page.tsx`, and `move-day-sheet.tsx` all
   reference `scheduled_date`, which does not and never did exist. The column is
   `date`. This is wrong even after the pending migrations land — it's an actual
   bug to fix, separate from the deploy gap.

**Therefore `shift-day` (Phase A's athlete "move a day") is currently broken
against prod on three counts:** it SELECTs a missing column (`scheduled_date`),
INSERTs four missing columns (`tier`/`reason_code`/`reason_text`/`week_number`),
and INSERTs a CHECK-violating value (`trigger_type='user_action'`). The audit
ledger it's supposed to write is empty because every insert fails (logged,
non-fatal). The adjustments feed (B2) would render nothing until this is fixed.

**Revised migration/deploy prerequisites for Phase B** (resolved 2026-07-03):
- `20260424100000` is a **ghost/re-stamped ledger entry** — marked applied but
  its SQL never ran (columns absent in prod). A plain `db push` would skip it and
  then `20260703120000` would fail on `COMMENT ON … reason_code`. Fixed with a
  new idempotent forward-fix migration
  `20260703115000_reconcile_plan_adjustments_ux_ledger_drift.sql` that runs
  first. Full validated deploy sequence: **`outputs/phase-b-deploy-runbook-2026-07-03.md`**.
- Fixed the `scheduled_date` → `date` bug in `shift-day` + its test (done). The
  three web athlete surfaces still carry it — tracked as a follow-up in the
  runbook §8.

The new `rewrite-block` edge function in this build uses the correct `date`
column throughout and targets the intended ledger schema.

(The `coach_instruction` / `athlete_feedback` columns from spec §4.2 belong to
**Phase C/D**, not here.)

### The three tables and which one Phase B edits

| Table | Role | Phase B touches it? |
|---|---|---|
| `plan_templates` | Coach's reusable blueprint (what the *builder* edits) | **No** — Phase B edits live plans, not templates |
| `training_plans` | One row per athlete subscription — the athlete's live plan | Read (to scope weeks); not mutated structurally |
| `scheduled_workouts` | One row per athlete per day — the materialized plan | **Yes — this is what a coach rewrite updates** |
| `plan_adjustments` | Append-only mutation ledger (tiers, reasons, before/after) | **Yes — one row written per changed week** |

The critical mental model: **the builder edits templates; Phase B edits a
specific athlete's materialized `scheduled_workouts`.** They share a week-grid
UX but write to different places.

---

## 2. Backend: the `rewrite-block` edge function

New file: `supabase/functions/rewrite-block/index.ts`
Follows the service-role pattern of `subscribe-to-plan` and `shift-day`.

### 2.1 Contract

**Input (POST body):**
```
{
  planId: string,            // training_plans.id (the athlete's live plan)
  coachId: string,           // for ownership verification
  weekRange: { fromWeek: number, toWeek: number },
  // The new/edited workouts for the block, one entry per changed day:
  changes: Array<{
    scheduledWorkoutId?: string,   // present = edit existing; absent = new day
    scheduledDate: string,          // YYYY-MM-DD
    weekNumber: number,
    dayOfWeek: number,              // 1=Mon..7=Sun
    workoutType: string,            // 10-zone vocab (long_run|tempo|intervals|...|rest)
    workoutData: object | null,     // PlannedWorkout JSON (paces, distance, steps)
    notes: string | null
  }>,
  weeklyMileageTargets?: Array<{ weekNumber, targetMilesMin, targetMilesMax }>,
  reasonCode: 'sickness'|'injury_niggle'|'race_change'|'life_event'|'performance'|'other',
  reasonText?: string     // optional coach explanation, <= 280 chars
}
```

**Behavior:**
1. **Auth:** `requireServiceRole` (called only from the trusted API route). The
   API route has already authenticated the coach's session.
2. **Ownership check (in-function):** confirm `coachId` owns `planId` — join
   `training_plans.coach_id` (and/or `athlete_plan_subscriptions`) → 403 if not.
   Mirror the gating the athlete-detail page already does server-side.
3. **Guardrails (hard fails → 4xx):**
   - Every `scheduledDate` in `changes` must be **strictly in the future**
     (past weeks are immutable history — spec §5).
   - `weekRange` must be future-only and match the weeks present in `changes`.
   - **Race-week edits require an explicit `confirmRaceWeek: true` flag** (spec
     §5 guardrails) — otherwise reject with a specific error the UI can catch.
   - `workoutType` must be in the canonical 10-value vocab.
4. **Compute `before`:** fetch current `scheduled_workouts` for the range; snapshot.
5. **Apply:** upsert the `scheduled_workouts` rows (UPDATE existing by id, INSERT
   new days). Set `source = 'coach_locked'` on rewritten key sessions so the
   materializer/athlete-move logic treats them as coach-owned.
6. **Compute `after`** and the per-day `diff`.
7. **Ledger — one row per changed week** (spec §5, "one `plan_adjustments` row
   per changed week"):
   ```
   {
     user_id, plan_id: planId,
     trigger_type: 'coach_rewrite',
     trigger_evidence: { source: 'rewrite_block', coach_id: coachId },
     action_type: 'rewrite_block',
     action_payload: { before, after, diff },   // reversible per ledger contract
     auto_applied: true,        // coach action is authoritative, applied immediately
     applied_at: now(),
     tier: 'yellow',            // coach-initiated change, visible to athlete (not routine-green)
     reason_code, reason_text,
     week_number: <that week>
   }
   ```
   > **Open decision to confirm with Rio:** tier for coach rewrites. The Phase A
   > athlete moves use `green` (routine) / `yellow` (cross-week). A coach rewrite
   > is authoritative and not something the athlete "did," so `yellow` (visible,
   > allowed, flagged) is the natural fit. Flagging this rather than silently
   > choosing. See §7 Open Questions.
8. **Fire rationale regen (R6 hook):** spec §5 says rewrite "re-triggers
   rationale generation (R6) for the rewritten weeks." `generate-day-rationale`
   is a **Phase C** function that doesn't exist yet. Phase B should **emit the
   hook but no-op gracefully** if the function isn't deployed (feature-flag /
   try-catch), so Phase C can light it up without touching `rewrite-block` again.
9. **Response:** `{ ok, changedWeeks, updatedCount, adjustmentIds }`.

### 2.2 Reversibility

The `action_payload.before/after` snapshot is the existing ledger contract used
by `shift-day`. Storing full before/after per week means a future "undo" path
(not built in B) can restore. No new mechanism needed — just honor the shape.

### 2.3 What Phase B deliberately does NOT do in this function

- No LLM call, no `WORKOUT_CODES_BY_DAY`, no prompt-library entry, no eval
  cassette. That's Phase E (`rewrite-block` gains an *assisted* mode later).
  Because Phase B ships no prompt, **hard rule #3 (eval gate) does not trigger.**
- No re-materialization of easy-fill days. Coach edits the specific days they
  touch. (Optional stretch: recompute easy-fill to honor a changed mileage
  range — flagged as a scope toggle in §7.)

---

## 3. Backend: the API route (web → edge function)

New file: `web/src/app/api/rewrite-block/route.ts`
Mirrors the existing `web/src/app/api/assign-plan/route.ts` pattern exactly.

- `POST` handler.
- Authenticate the coach via the **server** Supabase client (session cookie).
- Validate the body with Zod (week range, changes array, reason enum,
  `confirmRaceWeek` flag).
- Re-derive `coachId` from the authenticated coach profile (never trust the
  client for identity).
- Call the edge function with `SUPABASE_SERVICE_ROLE_KEY`:
  ```
  fetch(`${SUPABASE_URL}/functions/v1/rewrite-block`, { headers: { Authorization: Bearer <service_role>, apikey: <service_role> }, body: ... })
  ```
- Return the edge function's JSON (or mapped error, e.g. race-week-needs-confirm
  → 409 with a code the client shows as a confirm dialog).

This keeps the service-role key server-side only — the established security
boundary.

---

## 4. Frontend: coach portal UI

All under `web/src/app/(app)/coach-portal/athletes/[id]/` and
`web/src/components/coach/`. Reuse existing design-system primitives
(`Card`, `EmptyState`, `EditorialDivider`, `DripButton`, inline eyebrow style).
No `Eyebrow` component exists yet — use the established inline
`font-mono text-[10px] uppercase tracking-[0.18em]` pattern (matches the rest
of the portal).

### 4.1 Athlete live-plan calendar (spec §6.3)

New component: `web/src/components/coach/athlete-plan-calendar.tsx`
Rendered on the athlete detail page (`athletes/[id]/page.tsx`), which already
fetches `scheduled_workouts` for the athlete.

- Week-by-week list (or month grid) of the athlete's `scheduled_workouts`.
- Each day cell: workout type + name + mileage/range, tier-consistent color
  stripe (coral only as punctuation — one accent per cluster, hard rule).
- Past weeks visually muted and marked immutable; future weeks actionable.
- Empty/`activePlan == nil` state → `EmptyState` component, **never an em-dash**
  (hard rule #8).

### 4.2 Adjustments feed (spec §4.109, §6.3)

New component: `web/src/components/coach/plan-adjustments-feed.tsx`
On the athlete detail page. Reads `plan_adjustments` for `user_id = athlete`,
newest first.

- Each row: human string like `"Tue quality → Wed (work)"` for Phase A moves,
  and `"Rewrote W7–W10 (sickness)"` for coach rewrites.
- Tier-colored dot (green / yellow / red).
- Read-only list. This surfaces **both** the existing Phase A athlete moves
  (which currently render nowhere) **and** the new coach rewrites.
- Because the athlete-detail page is a server component, add a small
  server-side fetch for `plan_adjustments` next to the existing
  `scheduled_workouts` / `coachable_moments` fetches.

### 4.3 "Edit live plan" flow (spec §6.4)

New route + client: `athletes/[id]/edit-plan/page.tsx` (server) wrapping
`web/src/components/coach/live-plan-editor-client.tsx` (client).

Flow: **scope selector → manual grid → diff review → confirm.**

1. **Scope selector:** pick `fromWeek`–`toWeek`, future-only. Preload those
   weeks' `scheduled_workouts`.
2. **Manual grid:** reuse the builder's day-grid + `WorkoutStepEditor` +
   `PaceReferenceEditor` components, but bound to the athlete's materialized
   workouts instead of a template's `weeks` blob. This is the biggest reuse win
   — the editing UX already exists in `plan-builder-client.tsx`; the work is
   pointing it at `scheduled_workouts` and a different save path.
   - **Refactor note:** `plan-builder-client.tsx` is ~1,193 lines and reads/
     writes `plan_templates` directly. Rather than fork it, extract the
     day-grid + step-editor into a shared presentational component both the
     builder and the live editor use. This is a real refactor cost — call it
     out in the estimate. (Alternative: copy the grid for B, unify later —
     faster to ship, more drift. Recommend extract.)
3. **Diff review:** week-by-week before/after summary the coach confirms. Add a
   reason-code picker (the 6-value coach vocab) + optional note here.
4. **Confirm:** POST to `/api/rewrite-block`. Handle the race-week 409 with an
   explicit confirm dialog.

### 4.4 Schedule-prefs viewer (spec §6.3, from R2)

Spec lists a schedule-prefs editor on the athlete page. That's an **R2 finish**
item, adjacent to but not part of R5. **Recommend deferring to a small follow-up**
unless you want it bundled — flag in §7.

---

## 5. iOS touches (smaller, can trail web)

Spec §7. Phase B's only iOS item is the **"Coach updated your plan" banner**:

- Reads unacknowledged `plan_adjustments` rows where
  `trigger_type = 'coach_rewrite'` for the athlete.
- Banner text: `"Coach updated W7–W10 — sickness recovery"` (derive week range +
  reason from the ledger rows); tap → shows `reason_text` (and/or a linked
  `coach_note`).
- Marks acknowledged via the existing athlete-writable
  `acknowledged_by_user_at` column (already RLS-permitted for athletes).
- Files: banner surface in `RunningLog/App/` (Log/Today home) + a read of
  `plan_adjustments`. No new columns.

This can ship a beat after the web coach flow, since the coach can rewrite
before the athlete-side banner exists (the change still lands correctly).

---

## 6. Build order (suggested, each independently shippable)

| Step | Work | Why first |
|---|---|---|
| B1 | `rewrite-block` edge function + `/api/rewrite-block` route, tested with a hand-built payload — **✅ code written 2026-07-03** (`supabase/functions/rewrite-block/index.ts`, `web/src/app/api/rewrite-block/route.ts`). Not deployable until the pending ledger migrations are pushed (§1). | Backend is the foundation; verifiable with a script before any UI |
| B2 | Adjustments feed on athlete page (read-only) — **✅ code written 2026-07-03** (`web/src/components/coach/plan-adjustments-feed.tsx` + wired into `athletes/[id]/page.tsx` with a `select("*")` fetch). Section renders only when rows exist; empty until the ledger migrations are pushed. Web project type-checks clean. | Immediately surfaces Phase A moves too; low risk; no write path |
| B3 | Athlete live-plan calendar (read-only) | Coach visibility; prerequisite view for editing |
| B4 | Extract shared day-grid component from `plan-builder-client.tsx` | **Deferred.** B5 shipped with a purpose-built editor instead of refactoring the 1,193-line builder — lower risk, ships now. Reusing the builder's `WorkoutStepEditor` for richer per-step editing is a follow-up. |
| B5 | "Edit live plan" flow (scope → grid → diff → confirm) wired to B1 — **✅ code written 2026-07-03**: `web/src/components/coach/live-plan-editor-client.tsx` + `athletes/[id]/edit-plan/page.tsx` (server, ownership-gated) + "Edit live plan →" entry point on the athlete page. Edits existing future days (type/name/miles/notes/rest), diff review, reason picker, race-week confirm, posts to `/api/rewrite-block`. Web project type-checks clean. Inserting brand-new days + assisted rewrite (Phase E) remain out of scope. | The centerpiece feature |
| B6 | iOS "coach updated" banner | Trails web; independent |

Steps B1–B3 deliver coach *visibility* and a working apply path even before the
full editing UI (B5) lands — matching the spec's "each phase ships
independently" philosophy at a finer grain.

---

## 7. Open questions / decisions to confirm before coding

1. **Ledger tier for coach rewrites** — recommend `yellow` (authoritative,
   visible, flagged). Confirm vs. a new treatment.
2. **Easy-fill on mileage change** — when a coach changes a week's mileage
   range, does `rewrite-block` recompute easy-fill days (invoking the
   materializer's distribution logic), or only touch days the coach explicitly
   edited? Recommend: **Phase B edits only touched days**; mileage-range-driven
   re-fill is a fast-follow. Cheaper and more predictable.
3. **Bundle the R2 schedule-prefs editor?** It's listed under §6.3 but is an R2
   finish, not R5. Recommend deferring to keep Phase B tight.
4. **Refactor vs. fork the builder grid** (B4). Recommend extract-and-share;
   costs ~a day but avoids permanent drift between builder and live editor.
5. **Athlete banner data source** — drive purely from `plan_adjustments`, or
   also auto-write a `coach_note` on rewrite so the athlete gets a readable
   message? Recommend: write a `coach_note` too (reuses the existing
   coach→athlete pipeline; the banner links to it).
6. **Cross-week athlete moves** (spec §10 Q2) — unrelated to R5 apply path;
   leave as-is (yellow) for Phase B.

---

## 8. What this plan intentionally leaves for later phases

- **Assisted AI rewrite** (constrained-library, diff review, eval cassettes) —
  Phase E. `rewrite-block` is designed so an `assisted` input mode can be added
  without reshaping the apply path.
- **`generate-day-rationale` + `coach_instruction` field** — Phase C (R6).
  `rewrite-block` emits a no-op-safe hook for it now.
- **Per-workout athlete feedback, week strips, threaded notes** — Phase D (R7).

---

## 9. Risk notes

- **CONFIRMED: the pending migrations are NOT in prod** (queried 2026-07-03).
  `rewrite-block` cannot write its ledger rows until `20260424100000` +
  `20260703120000` are pushed. This is the top prerequisite — see §1.
- **CONFIRMED: `shift-day` is broken against prod**, not just historically —
  `scheduled_date` (missing column) + four missing ledger columns + a
  CHECK-violating `user_action`. The adjustments feed (B2) will be empty until
  both the deploy gap and the `scheduled_date` bug are fixed. See §1.
- **Service-role writes bypass RLS** — the coach ownership check lives entirely
  in the edge function. Get that check right; it's the only thing standing
  between coaches and other coaches' athletes (hard rule #4 pattern).
- **Builder refactor blast radius** (B4) — extracting the grid touches the
  working builder. Guard with a careful diff and manual test of the builder
  after extraction.
