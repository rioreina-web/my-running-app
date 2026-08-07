# S2 (partial) — one door

**Applied:** 2026-08-07 · branch `fix/audit-2026-08-06`
**Scope:** the three items from S2 that change behaviour. The rest deferred —
see bottom. **Not compiled here** — build in Xcode.

---

## 1. The plan day sheet opened a blank receipt *(live bug)*

`DayDetailSheet` lists `completedVitalWorkouts`, which comes from
`VitalManager.fetchRunningWorkouts` — so each element's `id` is a **HealthKit /
Vital device UUID**. It handed that straight to:

```swift
WorkoutRepDetailSheet(workoutId: vitalWorkout.id)
```

whose own header documents `workoutId` as "the `training_logs` row id", and
which queries `training_logs` with it. No row has a device UUID for an id. The
receipt opened blank, every time, with no error — both types are `UUID`, so
nothing could catch it. `HistoryDetailViewModel` already knew this trap and
documents it at `:26-28`; the trap was live two files away.

**Fix:** resolve the device workout to its row first —
`HistoryDetailViewModel.streamLogId(matching:)`, new. It reuses the same day
query and the same plausibility test S0 added, so this adds **no new matcher**
(`fetchStreamCarryingLogsForDate` and `isPlausibleMatch` drop `private`).

If the run hasn't synced yet there's no row, so the sheet doesn't present at
all rather than opening empty. That's a real state, not a failure.

*This is the case the `TrainingLogID` wrapper type would have made
uncompilable. Still worth doing — where there's a compiler to check it.*

---

## 2. Four copies of the sheet chrome → one

`WorkoutRepDetailSheet` is ~20 lines of chrome around `WorkoutRepReceiptView`.
Three other surfaces re-implemented it instead of presenting it:

- `WorkoutsAndRepsSection.swift:77` (Train › HISTORY)
- `CoachReadView.swift:548` (The Read) — already drifted: `tracking(0.8)` where
  the canonical sheet uses `1.0`
- the inline embed in `HistoryDetailSheet+Editorial` — *legitimately* different,
  it's embedded rather than presented, so it stays

Both modal copies now present `WorkoutRepDetailSheet`. The only two remaining
uses of `WorkoutRepReceiptView(workoutId:)` are the canonical sheet and the
inline embed, which is the correct shape.

---

## 3. The chrome itself was missing two things

Fixed once, now inherited everywhere:

- **`.toolbarBackground(.visible, for: .navigationBar)`** — without an opaque
  nav bar the 34pt headline scrolls under it and clips. That's the artefact in
  your 2026-08-06 screenshot. `HistoryDetailSheet` and `EditWorkoutNotesSheet`
  both set this; this sheet didn't.
- **A Done button.** Drag-to-dismiss was the only way out. Every other sheet in
  the app offers an explicit exit.

---

## Verify

1. Train › CALENDAR → a day with a completed run → tap the run. The receipt
   opens **with data** (it was blank before). If the run isn't synced yet,
   nothing opens — expected.
2. Open the receipt from anywhere: the "August 6" headline is no longer clipped,
   and there's a coral **Done** at top right.
3. Train › HISTORY → WORKOUTS & REPS → tap a session. Same chrome as everywhere
   else, Done button present.

---

## Deferred from S2 (deliberately)

- **Routing every entry point through one page.** Six doors land on the journal
  and four on the receipt. Collapsing them is S4's job — that's what "one page,
  three acts" *is*. Doing half of it now means building a merge, then rebuilding
  it. The chrome consolidation above is the part that pays off immediately.
- **Refresh propagation** (`NotificationCenter` channel for `training_logs`).
  Real: edit in the receipt and the journal underneath keeps a stale snapshot;
  four of seven journal call sites pass `onUpdate: {}`, so a delete from a
  Trends drill-down leaves the chart showing a row that's gone. Wants its own
  pass, and is cheaper once S3 gives one session identity to key off.
- **Ask drill-through.** `AskView` presents only `CoachAskSheet`, which contains
  no sheet of its own — an Ask answer about a session can't open that session.
  Needs a design call about what it opens *into*, so it's an S4 conversation.
- **Deleting the eleven unmounted views, four dead entry points and four
  in-tree `.bak` files.** Safe but wide, and it inflates the diff you're about
  to build and test. Worth its own commit once this one is green.
