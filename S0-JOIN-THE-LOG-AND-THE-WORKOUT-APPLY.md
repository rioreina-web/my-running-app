# S0 — turn the log↔workout join on

**Applied:** 2026-08-07 · branch `fix/audit-2026-08-06`
**Scope:** S0 from `SEAM-MAP-LOG-AND-WORKOUT-2026-08-07.md`. Makes the receipt
render inside the journal entry. Not the architectural fix.
**Not compiled here** — build in Xcode before testing.

---

## The bug

`HistoryDetailViewModel.fetchStravaRunningWorkoutsForDate` asked for the day's
runs with:

```swift
.in("source", values: ["garmin", "vital"])
```

There has never been a `garmin` or a `vital` row in the database. Vital was
never connected (`vital_credentials` is empty). Live source counts: 176
`strava`, 88 `voice_log`, 11 `auto_sync`, 3 `strava_backfill`, 1 `check_in`,
**0 garmin, 0 vital**.

So the query returned `[]` on every call and `linkedStreamLogId` was permanently
`nil`. Three things gated on it had therefore **never run on a live device**:

- the inline WORKOUT receipt inside a journal entry (`Editorial.swift:175`)
- the `VS. YOUR LAST SIMILAR SESSION` / COMPARE row (`Editorial.swift:186`)
- `mirrorWorkoutNotes`, shipped 2026-08-06, which returns at its first guard

And `workoutDetailId` collapsed to `entry.id` always, so `VIEW DETAIL ↗` opened
the receipt against the *journal* row — a row with no stream.

The sibling query 950 lines away (`VoiceLogView.swift:1394`) has the corrected
source list *and* a comment describing this exact failure mode. The two drifted.

Git blame: the `["garmin","vital"]` list arrived with `0ac693e` (2026-07-31,
"WIP safety snapshot").

---

## Changes

### 1. `Workouts/HistoryDetailViewModel.swift`

**`fetchStravaRunningWorkoutsForDate` → `fetchStreamCarryingLogsForDate`.**
The filter is now the actual question being asked:

```swift
.not("external_streams", operator: .is, value: "null")
```

Not a longer source allowlist. An allowlist is the wrong shape here — every new
source string breaks it silently while the call site still reads as correct,
which is precisely how this happened. `external_streams` is filtered on but
never selected; the blob is large and nothing here reads it.

**The entry's own row is deliberately not excluded.** Since the 2026-08-05
picker fix, a memo recorded against a synced run attaches to that run's row
rather than creating a second one — so for anything logged since then the stream
is on `entryId` itself and there is no sibling to find. Including it lets that
row win on a zero time delta, which is what makes the receipt render for the
modern single-row shape as well as the historical split pair. When it wins,
`linkedStreamLogId == entryId` and `workoutDetailId` resolves to the same id it
already fell back to. `mirrorWorkoutNotes` already guards `mirrorId != entryId`.

**A rejection threshold, which this matcher never had.** New
`isPlausibleMatch(_:entryTime:entryDist:)`: ±4 h and `max(0.5 mi, 8%)` — the
numbers from `_shared/voiceOrphanMatch.ts`, which is the one matcher
`docs/specs/runs-and-notes-split.md` keeps when the other eight are deleted.
Both `matchedVitalWorkout` and `linkedStreamLogId` are now picked from the
filtered set.

Why this is needed: ranking ran through `min(by:)` over every candidate on the
local calendar day, and `min` always returns a winner — a run 23 hours away won
by being the only one on the day. The `120` in `closer` is a tie-break switch
(rank by time, or by distance when two candidates are simultaneous), never a
match window.

**`sourceApp: "Garmin"` → derived from `source`.** Harmless while the query
returned nothing; would now label every Strava run `LINKED · GARMIN`. New
`sourceAppLabel(_:)`, mirroring `VoiceLogView.swift:1413`. Also added an error
log to the previously silent `catch`.

### 2. `Workouts/HistoryDetailSheet+Editorial.swift`

**`VIEW DETAIL ↗` stands down when there's nowhere to go.** New
`showsViewDetailLink` = `linkedStreamLogId == nil && matchedVitalWorkout != nil`.

- When the receipt renders inline, the link would open a modal copy of what's
  already on screen. That's the opposite of one session, one page.
- When nothing matched, the row previously rendered a coral affordance that did
  nothing — shown on `hasLinkedWorkout` (date + distance), acted on
  `matchedVitalWorkout != nil`.

`linkedSourceRow` splits into content + wrapper so the non-navigating case
renders as plain content rather than a disabled `Button` — `.disabled` on a
`.plain` button dims its whole label and would grey out the `LINKED · STRAVA`
eyebrow.

---

## Verify

1. Open a journal entry for a **run logged since 2026-08-05** (memo attached to
   the Strava row). The WORKOUT receipt should now render **inline**, below the
   memo. `VIEW DETAIL ↗` should be gone; `LINKED · STRAVA` stays.
2. Open one of the **35 historical entries** that sit on the same day as a run.
   Same result, via the sibling row.
3. Open a **voice-only entry with no run that day**. No inline receipt, no
   `VIEW DETAIL ↗`, no dead coral link. `LINKED · NONE` + `LINK A RUN →` if it
   has no date/distance at all.
4. The `VS. YOUR LAST SIMILAR SESSION` row should appear for the first time on
   entries in cases 1 and 2. Tap it — the comparison sheet should open.
5. Edit `THE WORKOUT` on the inline receipt, back out, reopen. The text should
   persist. (This is the path yesterday's Phase 0 patch was written for and
   which has not run until now.)
6. **Watch for a mis-pair.** On a double-run day, confirm the receipt shows the
   run the memo is about. If it doesn't, the ±4 h window is too wide for that
   day's shape — narrow `matchWindowSeconds` rather than adding a tenth matcher.

---

## Expected to become visible (not regressions — Seams 3 and 4)

With both halves in one scroll for the first time, the surfaces will visibly
disagree. All of this is catalogued in the seam map; none of it is new:

- Two section-header typefaces — `SUMMARY` in PT Serif, `SIGNALS` / `THE WORKOUT`
  in SF Mono, twenty points apart.
- Two stat strips for the same three numbers — serif 18 over mono 20, `6` above
  `6.00`.
- `workout_notes` rendered twice, as `WORKOUT NOTES` (journal composer) and
  `THE WORKOUT` (receipt), with two independent editors.
- Two titles: "Intervals" then "July 9."
- Two workout-type pickers with different vocabularies (`interval` vs
  `intervals`), writing to different rows.
- A dozen coral marks against a spec of one per cluster.

Seeing this is the point of S0. S1 closes the contradicting writes; S4 merges
the page.

---

## Known limits (by design)

- Still two rows, still paired by a guess — now a guess with a floor. The fix is
  `workout_notes.run_id` (S3 / the approved Phase 2).
- Niggles are still written against the journal row and read against the stream
  row, so a voiced niggle still can't reach the receipt. S1.
- `workout_type` still has two editors and no mirror. S1.
- `WorkoutRepDetailSheet` still has no Done button and no
  `.toolbarBackground(.visible, for: .navigationBar)`, so its headline still
  clips when opened modally. S2.
