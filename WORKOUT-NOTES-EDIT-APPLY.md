# Phase 0 — "THE WORKOUT" editable on the receipt

**Applied:** 2026-08-06 · branch `fix/audit-2026-08-06`
**Scope:** unblock the silent-no-op edit. Not the architectural fix.
**Full evaluation:** `WORKOUT-EDITABILITY-EVAL.md`

---

## The bug

A Strava-linked run is **two `training_logs` rows**:

- the voice/manual journal entry — `entryId`
- the Strava import carrying the stream + laps — `linkedStreamLogId`

`WorkoutRepReceiptView` renders from `linkedStreamLogId ?? entryId` and reads
`workout_notes` off that row (`WorkoutLapsService.fetchPrescription`).

`HistoryDetailViewModel.saveEdits` / `.saveWorkoutNotes` both write
`.eq("id", entryId)`.

On a linked run those are different rows. The edit returned 200 and changed
nothing on screen. No error surfaced anywhere.

---

## Changes

### 1. `Workouts/EditWorkoutNotesSheet.swift` — NEW

Focused single-field editor for `workout_notes`. Takes a row id and writes to
**that** row, so it is correct by construction wherever it's presented.

- `TextEditor`, autofocus after 0.35s, Cancel / Save, Save disabled until dirty.
- Empty input writes `.null`, not `""` — a blank string would read as
  "described, with nothing in it" downstream and suppress the ADD affordance.
- On save, fires `parse-workout-structure` so the rep chart re-derives from what
  the athlete typed. Safe: that function treats
  `parsed_structure.edited_by_user === true` as sacrosanct, so a manual
  "Fix reps" correction is not clobbered.
- Picked up automatically by the Xcode target — the project uses
  `PBXFileSystemSynchronizedRootGroup`, no `project.pbxproj` edit needed.

### 2. `Workouts/WorkoutRepReceiptView.swift`

- `@State showNotesEditor` + `.sheet` presenting the above.
- `workoutRecipeSection`: whole section tappable, `EDIT` marker beside the
  header, seeded from `prescription?.notes` **only** — never from `pattern`
  (pre-filling the parser's guess would launder it into the athlete's own words
  on Save).
- New empty state: `+ ADD THE WORKOUT` when no description exists. Previously
  the section rendered nothing at all, so an imported run had no way to acquire
  a description.

### 3. `Workouts/HistoryDetailViewModel.swift`

- New `mirrorWorkoutNotes(_:)`. After `saveEdits` (only when `workout_notes` is
  in the payload) and after `saveWorkoutNotes`, copies the value onto
  `linkedStreamLogId` when it differs from `entryId`.
- Best-effort: a mirror failure logs and never fails the save the athlete asked
  for. The journal row is already written and remains the record of truth.

---

## Verify

1. Open a **Strava-linked** run with an existing description → tap THE WORKOUT →
   change it → Save. Text updates immediately; the rep chart re-derives shortly
   after.
2. Open a Strava-linked run with **no** description → `+ ADD THE WORKOUT` →
   type → Save.
3. Edit `workout_notes` from the **journal** sheet's Edit mode → back out →
   reopen the receipt. It now reflects the edit (this was the broken path).
4. Clear the field entirely → Save → the ADD affordance returns.
5. A run with a manual **Fix reps** correction: edit the description, confirm the
   corrected rep structure survives.

Not compiled here — build in Xcode before testing.

---

## Known limits (by design)

- Two rows still exist and are still paired by a fuzzy time+distance heuristic
  at read time. Mirroring hides the symptom; it does not fix the identity split.
- Only `workout_notes` is mirrored. `title`, `mood`, `workout_type`, `distance`,
  `duration`, `cleaned_notes` still write to the journal row only — correct for
  those today, but the same class of bug is one feature away.
- `mirrorWorkoutNotes` is marked for deletion once `session_id` lands.

**Next:** Phase 1 — `session_id` on `training_logs` + offline backfill.
