# KEY SESSION — one definition, set by intent

**Written:** 2026-08-07 · **Not applied** — this is the spec.
**Scope:** four disagreeing key-session rules collapse to one. Key session
becomes something you *declare* — on the plan when you schedule it, or on the
session afterwards — with the derived rule demoted to a default for days you
never said anything about.

**Derived rule, in your words:** MP-and-faster work, plus long runs. That is
already what `keySessions.ts` computes. Nothing new gets invented.

---

## The diagnosis

Nothing is deliberately assigning key sessions. **Four** separate heuristics
each guess, using different inputs, and not one of them can be corrected.

### Rule 1 — the calendar star *(the one in your screenshots)*

`Training/Analytics/TrainingCalendarSection.swift:511`

```swift
private func isKey(_ c: DayCell) -> Bool { !c.isFuture && c.split.threshold > 0 }
```

`split.threshold` is any mileage faster than `thresholdRatio × MP`, where
`thresholdRatio = 1.07` (`TrainingAnalyticsViewModel.swift:792`, classifier at
`:797-804`, split built at `:758`). **There is no minimum.** One 400m surge at
the end of an easy run, a downhill mile, a Strava segment sprint — any of them
puts miles in the threshold bucket and stars the whole day.

So the star currently means *"you touched fast pace"*, not *"this was a key
session."* That is the bug, and it's why it reads as the app assigning
thresholds: it is reporting pace-bucket membership under a different name.

### Rule 2 — the journal row star

`Training/JournalLogRow.swift:60-67` — a hardcoded string set including
`long_run`, `race`, `intervals`, `mp`, `hmp`, `lt`, `10k`, `5k`, `3k`, `mile`.

Rule 1 has no long-run concept at all, because a pure long run has zero
threshold miles. **Same run, two answers.** Aug 1's 17.0 stars in the journal
and not in the calendar.

### Rule 3 — the server *(the good one)*

`supabase/functions/trends-timeline/keySessions.ts` → `deriveKeySession()`: has
MP-or-faster work bouts, **or** `workout_type == 'long_run'`; then gated
client-side at `QualityLoad.floor = 25` weighted minutes
(`Trends/TrendsQualityLoad.swift:83`, gate at `:97-102`).

Its `WORK_ZONES` is `{mile, 3k, 5k, 10k, hmp, mp}` — **exactly "MP and
faster."** This rule is already the one you described. It is calibrated against
23 real lap-scored sessions (stride sets 5.4–13.1, smallest real session 42.1,
empty gap between), and it has tests (`keySessions.test.ts`). It just never
reaches the calendar.

### Rule 4 — the coach web portal

`web/src/lib/coach-dashboard/from-supabase.ts:715-718`

```ts
const key =
  runLogs.some((l) => KEY_TYPES.has((l.workout_type ?? "").toLowerCase())) ||
  runLogs.some((l) => numMiles(l.workout_distance_miles) >= 12) ||
  (athletePaces !== undefined && qualityMiles >= 2.5);
```

A third vocabulary (`KEY_TYPES:161-172`), a fourth zone set
(`QUALITY_ZONES:174` — the same MP-and-faster group under different spellings),
and two hand-picked constants that exist nowhere else: **12 miles** and **2.5
quality miles**. Feeds `KeySessionRail` — a whole coach-facing surface built on
it.

Two things worth noting: it is already **day-scoped** (computed per `iso` day),
which is evidence for the decision below. And it is the closest of the four to
what you actually want — it's just wearing arbitrary numbers.

### Summary

| Surface | Rule | Aug 1 (17.0 long run) | Stray fast 400m |
|---|---|---|---|
| Calendar (`TrainingCalendarSection:511`) | `threshold miles > 0` | not key | **key** |
| Journal row (`JournalLogRow:60`) | `workout_type` in a set | key | not key |
| Trends (`keySessions.ts`) | MP+ work or long run, load ≥ 25 | key | not key |
| Coach portal (`from-supabase.ts:715`) | type set, or ≥12 mi, or ≥2.5 quality mi | key | not key |

**Scope is smaller than four suggests.** `TrainingTabTwoView.swift:475` holds a
byte-identical copy of Rule 1, but that view is retired as a tab
(`App/RunningLogApp.swift:194`) — dead code to delete, not a fifth thing to fix.
The live calendar is `TrainingCalendarSection`, mounted at
`Training/Analytics/TrainingTabView.swift:109`.

---

## The decision — three inputs, one resolution order

```
athlete override   (set on the session, after the fact)
      ↓ falls through to
plan intent        (set on scheduled_workouts, when the plan is built)
      ↓ falls through to
derived            (MP-and-faster work, or long run, clearing the load floor)
```

First non-null wins. Two consequences worth stating out loud:

**A key session becomes knowable before you run it.** That falls out of marking
at scheduling time, and it's the better model — a key session is a thing you
*intend*, not a thing a classifier notices afterwards. Your calendar already has
the vocabulary for it: the `PLANNED` legend and the dashed future cells in the
Block screenshot.

So the `!c.isFuture` guard in Rule 1 does **not** survive intact. It becomes:
*derived* never applies to the future (there's no run to score), but *plan
intent* does. A future Tuesday you marked as key shows its star.

**The derived rule is Rule 3, unchanged.** Don't write a fifth. Delete Rules 1,
2 and 4 and call Rule 3. The floor of 25 stays, but its job shrinks: it is no
longer *the definition*, only the line between a real session and a stride set
on days you never said anything about. Leave it at 25 — it sits mid-gap in an
empty interval in real data, and now it's overridable anyway.

### Why the athlete override is keyed by DAY

Even though you'll set it from a session sheet, store it against the day.

1. **The star lives on a day.** It's drawn on a `DayCell`
   (`TrainingCalendarSection.swift:296-301`), and the week row aggregates — Tue
   Jul 28 reads `9.2 mi · 3 runs`. Three rows, one star. A per-row flag has no
   defined answer there.
2. **It sidesteps the two-row bug.** Per `WORKOUT-EDITABILITY-EVAL.md §1`, a
   Strava-linked run is two `training_logs` rows paired by a fuzzy read-time
   heuristic, and `workout_notes` edits already land on the wrong one and
   silently vanish. A day-keyed override cannot fail that way.
3. **It survives data churn.** `LogDedup.dedupedByPhysicalWorkout()` picks the
   representative row *at read time*, and the dedupe sweep (`20260613220000`,
   `20260613240000`) cascade-deletes rows. A row-keyed flag can be deleted from
   under you. A day cannot.
4. **Rule 4 already does this** and it's the only one of the four nobody has
   complained about.

`null` is a real value: **null = nothing said, true = key, false = explicitly
not key.** Without the nullable middle you can only fail to claim a day was key;
you can't say it wasn't.

Plan intent is keyed differently and correctly so — `scheduled_workouts` has a
real per-session identity, `(plan_id, date, session)`. The blanket
`UNIQUE(plan_id, date)` was dropped in `20260227_plan_builder_setup.sql:13`, and
`session` was added by `20260301_add_session_column.sql`, so doubles work.

---

## 1. Migration — persist the load the calendar can't compute

`supabase/migrations/20260808120000_workout_features_quality_load.sql`

`workout_features` is the right home: one row per log
(`UNIQUE(training_log_id)`, `20260318120000:67`), already carrying the derived
classification (`workout_type`, `workout_structure` — `20260613200000`).
Append-only per **hard rule #5**; nullable columns, no RLS change — the same
shape as that migration.

```sql
ALTER TABLE workout_features
  ADD COLUMN IF NOT EXISTS quality_load DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS quality_kind TEXT;

COMMENT ON COLUMN workout_features.quality_load IS
  'Weighted minutes of stimulus. Quality session: sum over WORK bouts '
  '(qualityLoadForBouts). Long run: sum over ALL bouts (aerobicLoadForBouts). '
  'NULL for an ordinary run. The key-session floor is applied client-side '
  '(QualityLoad.floor) so it can be tuned without an edge-function deploy.';
COMMENT ON COLUMN workout_features.quality_kind IS
  'quality | long_run | NULL. Which formula produced quality_load. NULL means '
  'neither applied and this session is not a derived key-session candidate.';
```

### ⚠️ The trap that stars every day in your calendar

The two load formulas are **not interchangeable**.

- `qualityLoadForBouts()` — **work bouts only.** Warmup, floats, rest, cooldown
  fall out.
- `aerobicLoadForBouts()` — **every bout.** A 93-minute easy long run scores ~93.

`aerobicLoadForBouts` is legal **only** when `workout_type == 'long_run'`
(`keySessions.ts` → `deriveKeySession`, the `workBouts.length === 0` branch).
Apply it to any run without work bouts and a routine 60-minute easy run scores
~60, clears the floor of 25, and every single day gets a star. Preserve the
branch exactly:

```
work bouts present        → 'quality',  qualityLoadForBouts(workBouts)
no work bouts + long_run  → 'long_run', aerobicLoadForBouts(allBouts)
                                        (longRunLoadFromMinutes when lapless)
otherwise                 → NULL,       NULL
```

## 2. Migration — plan intent

`supabase/migrations/20260808120100_scheduled_workout_key_session.sql`

```sql
ALTER TABLE scheduled_workouts
  ADD COLUMN IF NOT EXISTS is_key_session BOOLEAN;

COMMENT ON COLUMN scheduled_workouts.is_key_session IS
  'Coach/athlete intent set when scheduling. NULL = nothing said, fall through '
  'to the derived rule. Never written by a pipeline — intent only.';
```

Nullable, three-state, same contract as the athlete override.

⚠️ **`scheduled_workouts` RLS is `FOR ALL USING (true) WITH CHECK (true)`**
(`20260204110000:31-32`) — the exact "Allow all" placeholder **hard rule #1**
forbids. Adding a column inherits that. Not this spec's job to fix, but it
should be a tracked item, because plan intent is now a thing any authenticated
caller could rewrite.

## 3. Migration — the athlete override

`supabase/migrations/20260808120200_day_overrides.sql`

Model it on `daily_checkins` (`20260804090100`), the established
client-writable athlete-owned day table. Generic on purpose: this is the
day-scoped half of the overrides layer `WORKOUT-EDITABILITY-EVAL.md §Change 2`
already argued for. `is_key_session` is its first field; the next needs no
migration.

```sql
CREATE TABLE IF NOT EXISTS day_overrides (
    user_id    TEXT NOT NULL,          -- matches auth.uid()::text (convention)
    date       DATE NOT NULL,          -- LOCAL date, as in daily_checkins
    field      TEXT NOT NULL,          -- 'is_key_session'
    value      JSONB NOT NULL,         -- true | false
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, date, field)
);
```

Plus an index on `(user_id, date)`, `ENABLE ROW LEVEL SECURITY`, and policies
copied from `daily_checkins:46-57` — `user_id = (auth.uid())::text` for SELECT,
INSERT and UPDATE. Real RLS in the same migration, per **hard rule #1**.

**You need a fourth policy `daily_checkins` doesn't have: `FOR DELETE`.** That
table never deletes a check-in so it never needed one. "Back to auto" deletes a
row, and with no DELETE policy RLS drops it silently — the call returns success,
zero rows affected, and the override looks stuck on.

**Clearing an override deletes the row.** Never write `null` into `value`, or
"back to auto" and "explicitly not key" collapse into one state, which is the
ambiguity this whole design exists to avoid.

## 4. `compute-workout-features` writes the load

`supabase/functions/compute-workout-features/index.ts` already does the work —
`segmentFromLaps` at `:145`, persists `workout_type` from `seg.workoutKind` at
`:265`. It has the bouts; it just discards the sum.

- Move `trends-timeline/qualityLoad.ts` → `_shared/qualityLoad.ts`, update both
  importers (`trends-timeline/keySessions.ts` and this function). One copy of
  the formula, same discipline as `_shared/workoutSegmentation.ts`.
- Populate `quality_load` / `quality_kind` per the branch table in §1.
- The upsert at `:572-589` already degrades when a column is missing —
  `:580-581` strips `workout_type`/`workout_structure` and retries. **Extend
  that guard to the two new columns**, so the function survives landing before
  the migration.
- Backfill by re-running over the existing window once after migrating.

## 5. `edit-scheduled-workout` accepts intent

`supabase/functions/edit-scheduled-workout/index.ts` is already the plan-side
write path, with auth, validation, reason codes and a `plan_adjustments` audit
trail. Add `is_key_session?: boolean | null` to the accepted body (`:45`), to
the "nothing to change" check (`:125-134`), and to the update.

`null` in the body means *clear it* — distinct from omitting the field, which
means *leave it*. Worth a line of comment, because the two look identical in
JSON if you're not careful.

## 6. One definition — `Training/KeySession.swift` *(new)*

Everything above exists so this file is the only answer to the question.

```swift
enum KeySession {
    enum Provenance { case auto, planned, athlete }

    /// The one definition. First non-null wins.
    static func isKey(override: Bool?,      // day_overrides
                      planIntent: Bool?,    // scheduled_workouts.is_key_session
                      dayLoad: Double?,     // Σ quality_load, deduped
                      isFuture: Bool) -> Bool

    static func provenance(override: Bool?, planIntent: Bool?) -> Provenance
}
```

Rules:

- Override wins outright, then plan intent, then derived. No blending, and no
  hiding the marker when two of them happen to agree.
- Derived = `QualityLoad.qualifies(dayLoad)`, reusing
  `TrendsQualityLoad.swift:97-102` unchanged. It already treats `nil` as not
  qualifying, which is what we want for a day with nothing scored.
- **Day load = sum of `quality_load` across the day's deduped physical
  workouts.** Sum, not max: a doubles day uploaded as warmup + main is one
  stimulus split over two rows. Dedup first via
  `LogDedup.dedupedByPhysicalWorkout()` — summing raw rows double-counts a
  cross-source duplicate straight over the floor.
- **Derived does not apply to future days; plan intent does.** A future day with
  `planIntent == true` is key. A future day with no intent is not, regardless of
  what the plan's mileage looks like.

### Reading it

Add a second fetch keyed by `training_log_id`, the shape the view model already
uses for conditions at `TrainingAnalyticsViewModel.swift:493-496`:

```swift
.from("workout_features")
.select("training_log_id,quality_load,quality_kind")
.in("training_log_id", values: ids)
```

Do **not** widen `TodayLogRow.fetchRecentThrowing`
(`App/TodayHomeView.swift:510-521`) — it selects from `training_logs` only and
sits on the Today/Log hot path.

### Writing it

Mirror `SleepCheckInPrompt.select(_:)` (`App/SleepCheckInPrompt.swift:106-140`)
beat for beat: optimistic local update → upsert → roll back locally on failure,
logging the error. It is the write-through pattern that already works here.

```swift
try await supabase.from("day_overrides")
    .upsert(row, onConflict: "user_id,date,field")
    .execute()
```

and for *back to auto*, `.delete()` matched on all three key columns.

## 7. Call sites

| File | Now | Change |
|---|---|---|
| `TrainingCalendarSection.swift:511` | `split.threshold > 0` | call `KeySession.isKey` |
| `TrainingCalendarSection.swift:296-301` | star overlay | style by provenance (§9) |
| `TrainingCalendarSection.swift:165` | `keyTag` in the week row | same call |
| `JournalLogRow.swift:60-67` | hardcoded `Set<String>` | **delete the set**, call `KeySession.isKey` |
| `TrainingTabTwoView.swift:475` | identical dead copy | delete (view retired) |
| `web/.../from-supabase.ts:715-718` | type set, ≥12 mi, ≥2.5 quality mi | read the resolved value; **delete `KEY_TYPES`, `QUALITY_ZONES`, both constants** |
| `keySessions.ts` | server derivation | unchanged — it *is* the rule |

The calendar becomes a pure display of resolved state — no editing affordance
there, since you're setting this from the sheet and the plan.

`FiveStar` is `private` at `TrainingCalendarSection.swift:562`. It needs to go
internal (or into the design system) so the journal row and the day sheet draw
the same star. Those surfaces looking different is half of what made this
confusing.

Leave `split.threshold` otherwise alone. It's still right for tile colour
(`dayColor`, `:498-503`) and the intensity bars — "was there fast running today"
is a fine question. It was just the wrong answer to "was this a key session."

## 8. The manual surface

**A. In the session detail sheet.** One row, following the `AUTO`/`YOURS`
provenance shape from `WORKOUT-EDITABILITY-EVAL.md §Change 3`:

```
KEY SESSION                    AUTO  ( )     ← derived; tap to set
KEY SESSION                 PLANNED  (★)     ← from the plan; tap to override
KEY SESSION                   YOURS  (★)     ← you set it; tap to clear
```

Tapping cycles set → clear → back to auto. Because the override is day-keyed, on
a multi-run day the row must say which day it marks — `MARKS TUE JUL 28`
underneath, not just a bare toggle. Otherwise it reads as marking the one run
you happened to open.

**B. On the plan, when scheduling.** The workout builder already has a
`workout_type` chip row; key session is a checkbox beside it, writing
`scheduled_workouts.is_key_session` through `edit-scheduled-workout`. Surfaces:
`web/src/components/coach/plan-builder-client.tsx` and
`live-plan-editor-client.tsx` on the coach side,
`Training/PlanTemplateBuilderView.swift` and `DayDetailSheet.swift` on iOS.

Per **hard rule #8**, none of these states uses an em-dash placeholder — a day
with nothing set reads `AUTO`, which is a real value, not an empty one.

## 9. Provenance

Three states, one glyph of difference each — these are 9pt marks, so restraint
matters:

- **Outline star** — derived. The app's guess.
- **Half/tinted star** — plan intent. Somebody meant this.
- **Filled star** — athlete override. You said so.

A day explicitly un-keyed shows **no star**, but its sheet still reads `YOURS`,
so a deliberate "not key" never looks like the app forgot.

## 10. Tests

- `KeySessionTests` *(new)* — the resolution table. Override true beats intent
  false beats derived true, and every other ordering; nil at each level falls
  through; day load sums across a doubles day; a future day with intent is key;
  a future day without is not.
- **The easy-run regression, named explicitly.** A 60-minute easy run with no
  work bouts must produce `quality_kind = NULL` and must not be key. This is the
  §1 trap and it deserves its own test, not coverage by accident.
- `keySessions.test.ts` — extend for the `_shared/qualityLoad.ts` move. Existing
  cases must pass untouched; if they don't, the move changed behaviour.
- `TrendsQualityLoadTests` already pins the weight table against
  `_shared/workoutSegmentation.ts`. Leave it pinning.
- A coach-portal test that `from-supabase.ts` returns the same `key` set as the
  iOS resolution for one fixture week. That's the regression that catches Rule 4
  growing back.

---

## Verify

1. **Train › CALENDAR › BLOCK**, against the Jul 6 – Aug 9 block. Stars land on
   real sessions. Any day starred only for a stray fast stretch loses it. Tue
   Jul 28 (`9.2 mi · 3 runs`, threshold) keeps it.
2. **Aug 1, the 17.0 long run** — now starred in the calendar. It already was in
   the journal. Both surfaces agree for the first time.
3. **Open Fri Aug 7** (the 7.0 easy) → sheet reads `AUTO`, no star. Tap → `YOURS`,
   **filled** star. It should say `MARKS FRI AUG 7`. Kill and relaunch: still set.
4. **Open Tue Jul 28** → tap to *not a key session*. Star gone from the calendar,
   sheet still reads `YOURS`.
5. **Back to auto on both.** Aug 7 loses its star, Jul 28 gets one back, both
   outline.
6. **Schedule a future Tuesday as a key session** in the builder. It shows a
   half-filled star on a dashed future cell — the case that couldn't exist
   before. Override it from the sheet after running: filled.
7. **Trends › Key Sessions grid** — same day set as the calendar. Disagreement
   means a call site was missed.
8. **Coach portal** — `KeySessionRail` shows the same days the athlete sees.
9. **Airplane mode**, set a day. Star appears, reverts, error in the log — the
   `SleepCheckInPrompt` rollback contract.

All migrations reach prod via `supabase db push` from a committed SHA, per
**hard rule #9**. Not the dashboard editor, not MCP `apply_migration`.

---

## Deferred, deliberately

- **Session-scoped athlete overrides.** Day-keyed covers this completely and
  needs no session identity. The moment you want to override *which run on
  Tuesday* was key, you need `session_id` first — `WORKOUT-EDITABILITY-EVAL.md
  §Change 1`, a bigger job.
- **Fixing `scheduled_workouts` RLS.** Flagged in §2. Real, and a hard-rule-#1
  violation, but folding a security fix into this diff makes both harder to
  review.
- **Tuning `QualityLoad.floor`.** Leave at 25. Retune once real overrides show a
  pattern — which is now something you can actually observe, and is half the
  point of storing them.
- **"Why is this a key session?"** An explainer built from `quality_load` +
  `workout_structure`. Good idea later; not needed to fix the assignment.
- **Auto-suggesting intent when a plan is generated.** Tempting — the plan
  builder knows which sessions are the week's anchors. But a pipeline writing
  `is_key_session` breaks the "intent only" contract in §2. If you want it, it
  writes a *suggestion* the athlete confirms, not the field itself.

## What not to do

- **Don't write `null` into `day_overrides.value`.** Delete the row.
- **Don't key the athlete override on `training_log_id`.** It reintroduces the
  `workout_notes` silent-no-op bug and can be cascade-deleted by the dedupe
  sweep.
- **Don't let any pipeline write `is_key_session` or `day_overrides`.** Same law
  as `parsed_structure.edited_by_user`: once a human says it, nothing
  recomputes over it. `day_overrides` is client-written only.
- **Don't add a fifth derivation.** If `quality_load` isn't available yet, show
  no star rather than falling back to `split.threshold > 0`. A missing star is
  honest; a wrong star is the bug you're fixing.
- **Don't apply `aerobicLoadForBouts` outside `long_run`.** Re-read §1. It is
  the one change that looks harmless and stars every day in the calendar.
- **Don't leave Rule 4 in place "for now."** It's the rule with the arbitrary
  constants, it feeds a coach-facing surface, and it is exactly how five rules
  become six.
