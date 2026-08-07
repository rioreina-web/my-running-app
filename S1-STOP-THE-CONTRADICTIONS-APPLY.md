# S1 — stop the two ends contradicting each other

**Applied:** 2026-08-07 · branch `fix/audit-2026-08-06`
**Scope:** S1 from `SEAM-MAP-LOG-AND-WORKOUT-2026-08-07.md`. Closes the writes
that provably disagree, before anything structural. Follows S0.
**Not compiled here** — build in Xcode before testing.

---

## 1. `workout_type` had three pickers and two spellings

**Found in prod:**

| stored value | rows |
|---|---|
| `easy` | 155 |
| `recovery` | 39 |
| `long_run` | 22 |
| **`interval`** | **14** |
| `tempo` | 13 |
| `threshold` | 10 |
| **`intervals`** | **9** |
| `race` | 7 |
| `other` | 7 |

`interval` and `intervals` are one concept stored as two values, because two
pickers each had their own hardcoded list:

- `ManualWorkoutView.newRunTypes` — 14 keys, the canonical taxonomy, correct
- `EditableWorkoutTypeSection` (journal) — 6 keys, wrote `"interval"`
- `WorkoutRepReceiptView.typeOptions` — 9 keys, wrote `"intervals"`

`tempo` and `threshold` are stored too, though `WorkoutLabel.swift`'s own header
retired both as ambiguous ("the pace zone IS the label; Threshold maps to LT").

Every consumer that *groups* by `workout_type` — the quality-session filter in
`WorkoutsAndRepsSection`, Trends key-session classification, the Ask analyzers —
splits those rows across two buckets. `WorkoutLabel.display` made them *look*
identical everywhere, which is exactly what hid it.

### Changes

**`App/WorkoutLabel.swift`** — the file that already declares itself the single
source of truth gains the two things it was missing:

- `offered` — the canonical key/label list, lifted verbatim from
  `ManualWorkoutView`, which had the only correct copy.
- `options(including:)` — the offer list plus the row's current value when
  that's a legacy key, so re-typing an old run never silently rewrites it.
  Generalized from `ManualWorkoutView.runTypeOptions`.
- `normalize(_:)` — fold to canonical spelling **on write**: `interval` →
  `intervals`, `long`/`longrun` → `long_run`, `threshold` → `lt`,
  `cross_training` variants → `cross_train`. Anything unrecognised passes
  through untouched; it never invents a type the athlete didn't choose.

**Three pickers → one list.** `ManualWorkoutView`, `EditableWorkoutTypeSection`,
and `WorkoutRepReceiptView` all call `WorkoutLabel.options(including:)` and
their private lists are deleted. Tuples stay unlabeled `[(String, String)]` to
match the existing `ForEach(_, id: \.0)` call sites.

**Both writes normalize.** `WorkoutRepReceiptView.updateType` and
`HistoryDetailViewModel.saveEdits`.

**`EditableWorkoutTypeSection` gains `arrivedAs`** — the type the entry opened
with, captured once in `.onAppear`. Seeding the legacy chip from `selectedType`
instead would make it vanish the moment you tap a canonical one, with no way
back.

**`TrainingLog.workoutTypeLabel` now delegates to `WorkoutLabel.display`.** It
was a fourth switch, and it was missing the entire race-pace half of the
taxonomy — a run typed `mp`, `hmp`, `lt`, `10k`, `5k`, `3k` or `mile` returned
`nil` and showed **no title at all** in the journal. `nil` for a nil/blank type
is preserved deliberately, since `resolvedTitle` falls back to the weekday and
`display(nil)` returns "Run".

*Two small label changes fall out of this:* `long_run` renders "Long run" rather
than "Long Run", and `other` renders "Other" rather than "Workout" — both now
matching what the picker chip says.

### Not done: normalizing the 24 existing rows

`interval` → `intervals` and `threshold` → `lt` on stored data is a migration,
and hard rule #9 says migrations reach prod only via `supabase db push` from a
committed SHA. Not authored here. When you want it:

```sql
update training_logs set workout_type = 'intervals' where workout_type = 'interval';
update training_logs set workout_type = 'lt'        where workout_type = 'threshold';
```

`tempo` (13 rows) is deliberately left alone — it has no unambiguous target.

---

## 2. `workout_type` also wrote to the wrong row

The journal's picker writes `entryId`; the receipt's writes `workoutId` (the
stream row). No mirror existed, so on a split pair the two pickers edited
different rows and neither knew.

`mirrorWorkoutNotes` generalized to **`mirrorToStreamRow(_ fields:)`**, driven
by a named set:

```swift
private static let streamRowMirroredFields: Set<String> = [
    "workout_notes", "workout_type",
]
```

`mood` and `cleaned_notes` are deliberately **not** in it — on a split pair
those belong to the note, not the run, and overwriting the run's copy would be
making the merge decision `merge_voice_orphan_into_run` already makes
differently. That's S3's call, not a mirror's.

Still one-directional (journal → stream). The receipt can't mirror back because
it doesn't hold the journal id — that's what S3 fixes properly.

---

## 3. Two editors for `workout_notes`, in one scroll

The journal's `＋ ADD A NOTE` composer and the receipt's `THE WORKOUT` section
edit the same column under two different labels. While `linkedStreamLogId` was
permanently nil the receipt never rendered inside the journal, so this was
invisible. After S0 both appear in the same scroll.

The composer now stands down when the receipt is present
(`vm.linkedStreamLogId == nil`). The receipt's editor is the better home — it
sits beside the reps the description describes, and `EditWorkoutNotesSheet`
re-fires the structure parser on save. The composer remains the only way to add
a description to a **stream-less** entry, where the receipt never appears.

The type picker needed no such gate: it only exists inside `isEditing`, and the
receipt is hidden in edit mode, so the two can never be on screen together.

---

## 4. `coach-workout-read` returned 404 on every call

`index.ts:161` selected `scheduled_workout_id` and `start_time`. Neither column
exists on `training_logs`. PostgREST rejects the whole select (400), `log` comes
back null, and the next line returns `404 "Workout not found"`.
`coach_workout_reads` has **0 rows**, which is the fingerprint.

`process-training-memo:464` and `generate-workout-insight:355` both hit this and
both carry an explanatory comment; this one was missed. Same fix, same comment:
drop both columns from the select. The scheduled-workout enrichment below is
guarded on the field being truthy, so it no-ops until a real linkage column
exists. `start_time` was never read at all.

**Needs redeploy** — `supabase functions deploy coach-workout-read`.

---

## 5. Niggles — data, not code (not applied)

`body_mentions` is written against the memo row
(`process-training-memo:1155`, `record.id`) and read against the stream row
(`ReceiptNiggleService.fetch`, `WorkoutReceiptSignals.swift:810`), so a voiced
niggle can't reach the receipt.

Going forward this is already correct: since the 2026-08-05 picker fix a memo
attaches to the run's row, so `record.id` *is* the run. Only historical rows are
stranded — and there are four in total:

| points at | rows |
|---|---|
| a `voice_log` row | 2 |
| a `strava` row | 1 (correct) |
| nothing at all (dangling) | 1 |

Two rows to repoint and one to delete. Not worth code; not run here because it
writes to prod. `body_mentions` also has **no foreign key** to `training_logs`,
which is how the dangling row exists — worth adding when S3 touches this table.

---

## Verify

1. **Journal edit mode** → the WORKOUT TYPE chips now show the full pace-zone
   taxonomy (Easy · Moderate · Steady · MP · HMP · LT · 10K · 5K · 3K · Mile ·
   Long run · Recovery · Race · Other), not the old six.
2. Open a run stored as **`tempo`** and enter edit mode → a "Tempo" chip appears
   at the end of the list, selected. Tap "Easy", then tap "Tempo" again — it's
   still there. (That's `arrivedAs` working.)
3. Change the type from the **receipt's** eyebrow chevron → same list.
4. On a **split pair**, change the type in journal edit mode, save, then open
   the receipt → it shows the new type. (The mirror.)
5. A run typed `lt` or `5k` now shows a **title** in the journal instead of
   falling back to the weekday.
6. A journal entry **with** an inline receipt → no `＋ ADD A NOTE` composer;
   description is edited via `THE WORKOUT`. A voice-only entry with **no** run
   → composer still there.
7. `curl` the coach-workout-read function for a real `logId` → a body, not
   `{"error":"Workout not found"}`.

---

## Deliberately deferred

- **`TrainingLogID` wrapper type** (S1 item 5 in the seam map). It would make
  `DayDetailSheet:514` passing a HealthKit device UUID into a `training_logs`
  row-id parameter uncompilable. It also touches every call site of every
  detail surface, and there is no Swift toolchain in this environment to check
  the result. Worth doing — worth doing where it can be compiled.
- **Deleting the receipt's duplicate hand-rolled sheet chrome** (three copies)
  and the eleven unmounted views — S2.
