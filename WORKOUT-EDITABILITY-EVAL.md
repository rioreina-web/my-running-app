# Workout Detail — Editability Evaluation & Proposal

**Screen:** `WorkoutRepDetailSheet` → `WorkoutRepReceiptView` (title "WORKOUT")
**Date:** 2026-08-06

---

## TL;DR

You can't edit "THE WORKOUT" or the notes from this screen for three separate
reasons, stacked. Only one of them is a UI problem.

1. **Data:** a Strava-linked run is *two* `training_logs` rows. The journal
   sheet edits row A. This receipt reads row B. Your edit saves successfully
   and then never appears.
2. **Architecture:** editing is a single global *mode* (`isEditing`) that lives
   on a different sheet (`HistoryDetailSheet`). This receipt has no edit state
   at all.
3. **Coverage:** even inside that mode, only 7 of ~20 visible fields are
   editable.

Fixing #3 alone gets you nothing. Fixing #1 is the unlock.

---

## 1. Root cause — one run, two rows

`HistoryDetailViewModel.matchVitalWorkout()` finds the Strava import as a
**separate `training_logs` row** and stores its id:

```swift
linkedStreamLogId = stravaRows.min(by: closer)?.id   // HistoryDetailViewModel.swift:368
```

The receipt is then opened against *that* row:

```swift
var workoutDetailId: UUID { vm.linkedStreamLogId ?? entry.id }  // HistoryDetailSheet.swift:67
```

And "THE WORKOUT" text is read off that row:

```swift
// WorkoutRepChart.swift:511 — fetchPrescription(workoutId:)
.from("training_logs").select("workout_notes").eq("id", value: workoutId.uuidString)
```

But every write goes to the **journal** row:

```swift
// HistoryDetailViewModel.swift:193 (saveEdits) and :244 (saveWorkoutNotes)
.from("training_logs").update(updateData).eq("id", value: entryId.uuidString)
```

`entryId` ≠ `workoutDetailId` whenever the entry is Strava-linked — which is
exactly the case in your screenshot (`4.15 mi · 30:33 · Strava`).

**Consequence:** you type the workout description, tap Save, the network call
returns 200, and the receipt is unchanged. There is no error to see. This will
read as "the app is broken" to every beta tester who tries it.

The two rows are also joined by a *fuzzy heuristic* at read time (start time
within 2 min, then closest distance). Nothing in the schema records the match.
On a double-run day the pairing can flip between sessions.

---

## 2. Editing is a mode, and it lives on the other screen

`HistoryDetailSheet` carries the entire edit surface:

```swift
@State var isEditing = false
@State var editTitle, editMood, editWorkoutType, editDistanceText,
         editDurationText, editNotesText: String
```

Flipping `isEditing` swaps out six sections of the layout — the stat strip
disappears, the summary becomes a `TextField`, the whole WORKOUT receipt is
hidden (`if !isEditing, vm.linkedStreamLogId != nil`). So the moment you enter
edit mode, **the thing you were trying to fix leaves the screen.**

`WorkoutRepDetailSheet` — the screen in your screenshot — has no `Edit` button,
no `Done` button, and no edit state. Its only toolbar item is a `Text("WORKOUT")`
label. The single editor reachable from here is a coral **"Fix reps"** capsule
at the bottom of the reps chart, which opens `EditWorkoutStructureSheet`.

That sheet is genuinely good — it has plain-language AI reconciliation, a
`edited_by_user` flag so the auto-parser can't clobber your correction, and a
"restore auto" path. **It is the right model.** It's just applied to exactly one
field group and buried where nobody will find it.

---

## 3. Field coverage

| Field on screen | Editable? | Where | Writes to |
|---|---|---|---|
| Title / date header | ✅ | journal Edit mode | journal row |
| Mood | ✅ | journal Edit mode | journal row |
| Workout type | ✅ | journal Edit mode | journal row |
| Distance / duration | ✅ | journal Edit mode | journal row |
| Summary (`cleaned_notes`) | ✅ | journal Edit mode | journal row |
| **THE WORKOUT** (`workout_notes`) | ⚠️ | journal Edit mode | **wrong row** |
| Rep structure | ✅ | "Fix reps" (buried) | Strava row ✓ |
| Avg pace / HR | ❌ | — | — |
| Temp / dewpoint / heat cost / climb | ❌ | — | — |
| SIGNALS chips + their thresholds | ❌ | — | — |
| The prose read ("5 reps at 5:20/mi…") | ❌ | — | — |
| Voice memo transcript | ❌ | — | — |
| Memo mood classification (POSITIVE) | ❌ | — | — |
| Niggles | ❌ | — | — |
| Individual rep pace / distance | ⚠️ | "Fix reps" only | Strava row ✓ |

Roughly a third editable, and the one field you named is in the broken column.

---

## Design read — what's working

Keep this. The information architecture on this screen is the strongest thing
in the app:

- Four-stat strip → conditions strip → SIGNALS → one-sentence prose read is a
  genuinely good funnel. A reader gets the session in ~3 seconds.
- Amber/green signal chips carry judgment without a score. Right call.
- The prose sentence restating the chips in English ("5 reps at 5:20/mi, inside
  a 6-second spread") is the single most valuable line on the page.
- Mono numerals + editorial serif headline is a real visual identity.

### Small bugs visible in the screenshot

1. **The "August 6" headline is clipped** by the sheet chrome.
   `WorkoutRepDetailSheet` never sets `.toolbarBackground(.visible, for: .navigationBar)`
   — `HistoryDetailSheet` does. Content scrolls under an unbacked nav bar.
2. **No close button.** Drag-to-dismiss only. `HistoryDetailSheet` has "Done";
   this sheet has nothing.
3. **The voice-memo card's `›` chevron reads as navigation, not edit.** It
   expands text in place. Ambiguous affordance on the one card people will most
   want to correct.

---

## Proposal

Three changes. The order matters — 1 and 2 are foundations, 3 is the surface
everyone will actually see.

### Change 1 — One session identity (schema)

Add `session_id uuid` to `training_logs`. Two rows describing the same run
share a `session_id`. Backfill using the existing time+distance heuristic *once*,
offline, where you can review the pairs — instead of re-guessing on every screen
load.

Then `workoutDetailId` and `entryId` both collapse to "the session", and reads
and writes can no longer disagree.

*Why this first:* every other fix is unsafe until a write is guaranteed to land
where the read looks.

### Change 2 — An overrides layer, never in-place mutation

Add `user_overrides jsonb` (or a `session_field_overrides` table).

- Import / AI writes the **base** value.
- An athlete edit writes an **override**, keyed by field path.
- Every read is `override ?? derived`.

You already invented this pattern for one field group —
`parsed_structure.edited_by_user`, so the auto-parser never overwrites a manual
correction. Generalize it and you get, for free:

- A re-import or re-parse can never destroy something the athlete typed.
- "Restore auto" works on every field, not just reps.
- Making a *new* field editable is zero schema change.
- You have an audit trail of what the AI got wrong — which is the training
  signal for making it get it right.

This is the single highest-leverage decision for "beta that grows into a real
product." Without it, every new editable field is a new column and a new
clobber-risk.

### Change 3 — The field is the editor

Delete the global `isEditing` mode. Replace with: **tap any value, edit that one
value.**

- Tap "THE WORKOUT" → focused sheet for that text (with the AI reconcile box
  that `EditWorkoutStructureSheet` already has).
- Tap the memo card → correct the transcript or the mood.
- Tap a stat → correct that stat.
- One `SessionEditor.set(.workoutNotes, text, for: sessionId)` call site per
  field. Optimistic update, write, refresh.

Add a **provenance marker** on fields that came from a machine — a small `AUTO`
tag next to derived values, dropping to `YOURS` once corrected. This solves
discoverability without hanging an Edit button on a screen whose whole point is
that it reads like a printed receipt.

---

## Sequencing for the beta

**Phase 0 — this week, no schema change.** Point `saveWorkoutNotes` at
`workoutDetailId` instead of `entryId`, and put a tap target on "THE WORKOUT"
that opens a text editor writing to that same id. This unblocks the specific
thing you hit, today, with about 40 lines. It is a patch, not the fix — but it
stops testers from hitting a silent no-op.

**Phase 1 — `session_id` + backfill.** The identity fix.

**Phase 2 — `user_overrides`.** The durability fix.

**Phase 3 — tap-to-edit + provenance markers.** The surface, rolled out field by
field. Start with the four people correct most: workout description, memo
transcript, mood, distance.

---

## What not to do

- **Don't add a second `isEditing` mode to the receipt.** Two modal edit modes
  over two rows is how you get edits that overwrite each other.
- **Don't let the AI re-derive from athlete-edited text.** Once a field is
  overridden it's ground truth; re-running the parser over it and writing back
  is the clobber bug in a new costume.
- **Don't make every field editable at once.** Ship the four above, watch what
  testers actually correct, and let that set the queue.
