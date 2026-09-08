# Seam map — where the log and the workout detail come apart

**Date:** 2026-08-07
**Question asked:** "the log and workout details tend to start living in separate
places a lot — where can we make them seamless?"
**Reads with:** `docs/specs/runs-and-notes-split.md` (approved 2026-08-05) —
that spec owns the *data* fix. This doc owns the *surface* fix and the sequence
that joins them.
**Supersedes the proposal half of:** `WORKOUT-EDITABILITY-EVAL.md` (2026-08-06).
Its diagnosis stands; its "add `session_id`" recommendation is superseded by the
`external_id` / `workout_notes.run_id` model already approved.

---

## TL;DR

Four seams, stacked. They are not the same problem and they don't get fixed in
the same place.

| # | Seam | Layer | Status |
|---|---|---|---|
| **0** | **The join is switched off in production.** The receipt has never once rendered inside a journal entry on a live device. | one-line bug | **fix today** |
| **1** | One run is two rows, paired by nine disagreeing guesses | data | spec approved, Phase 2 next |
| **2** | Eleven entry points, four of them dead, and the same run opens different screens depending on where you tapped it | navigation | undesigned |
| **3** | The two surfaces state the same fact from different rows, in different words, with different editors | content | undesigned |
| **4** | They don't look like the same product — serif vs mono headers, five date formats, four pace formatters | visual | undesigned |

**The one number that frames all of it:** 143 of 179 measured runs — **80%** —
carry no mood, no description, and no memo. The workout detail screen has
nothing from the log to show on four runs out of five. Not because the athlete
didn't write anything: 89 journal entries exist, and 35 of them sit on the same
calendar day as a run they are never joined to.

The log and the workout detail aren't drifting apart. **They have never been
connected on a live device.** Seam 0 is why.

---

## Seam 0 — the connective tissue is switched off

`HistoryDetailSheet+Editorial.swift:175` embeds the entire workout receipt
inside the journal entry. This is exactly the seamless thing you're asking for,
and it already exists in the code:

```swift
if !isEditing, vm.linkedStreamLogId != nil {
    editorialSection(eyebrow: "WORKOUT") {
        WorkoutRepReceiptView(workoutId: workoutDetailId)
    }
}
```

`linkedStreamLogId` is set by `matchVitalWorkout()`, whose candidate query is
`HistoryDetailViewModel.swift:441`:

```swift
.in("source", values: ["garmin", "vital"])
```

Live row counts in `training_logs`:

| source | rows |
|---|---|
| `strava` | 176 |
| `voice_log` | 88 |
| `auto_sync` | 11 |
| `strava_backfill` | 3 |
| `check_in` | 1 |
| **`garmin`** | **0** |
| **`vital`** | **0** |

`vital_credentials` has zero rows. Vital was never connected.

So the query returns `[]` every time. `linkedStreamLogId` is always `nil`.
Consequences, all of them currently live:

- The inline WORKOUT receipt **never renders** (`Editorial.swift:175`).
- The `VS. YOUR LAST SIMILAR SESSION` / COMPARE row never renders
  (`Editorial.swift:186`, same gate).
- `workoutDetailId` collapses to `entry.id` always (`HistoryDetailSheet.swift:67`),
  so `VIEW DETAIL ↗` opens the receipt against the **journal** row — a row with
  no streams and, for 34 of 89 notes, no distance either.
- `mirrorWorkoutNotes` — the Phase-0 patch shipped yesterday — returns at its
  first guard and has never executed (`HistoryDetailViewModel.swift:262`).

The sibling query 950 lines away has the right list, and a comment explaining
this exact failure mode (`VoiceLogView.swift:1394`):

```swift
// MUST include "strava". This list is the ONLY way a synced run
// reaches the link picker […] Omitting a source here silently
// downgrades every memo for that source into a NEW duplicate row.
.in("source", values: ["garmin", "vital", "strava", "auto_sync", "strava_backfill"])
```

**Fix:** make `HistoryDetailViewModel.swift:441` match. One line. Do it behind a
same-day sanity check, because turning the matcher on also turns on nine
matchers' worth of guessing (Seam 1) — see the sequence below for the guard.

*Why this matters more than it looks:* every observation in
`WORKOUT-EDITABILITY-EVAL.md` about the receipt-inside-the-journal, the double
render, the mirror, the id split — describes a code path that has never run on
your phone. The screen you were looking at when you wrote that doc was the
receipt opened against a *journal* row.

---

## Seam 1 — one run, two rows, nine guesses

`docs/specs/runs-and-notes-split.md` owns this and its diagnosis is correct.
Three things to add to it.

**The matcher count is nine, not six.** The spec's table lists six. Also live:

| Where | Rule |
|---|---|
| `strava-sync/index.ts:67` `findDeviceTwin` | ±15 min & ±0.3 mi, sources `{auto_sync, vital, garmin}` |
| `process-training-memo/index.ts:502` | same UTC day, ±0.3 mi, `limit(10)`, **first** match wins — not closest |
| `TrainingDayExpanded.swift:490` `primaryLog` | first row with a GPS source, else max miles |

They disagree on the bucket itself: `dedupe_recent_training_logs()` groups on
**UTC** date; every client matcher groups on the **local** calendar day. The one
live split pair in the database (2026-07-18, 13.49 mi) has its two rows exactly
five hours apart — the old `start_date_local` bug — which is precisely the gap
that flips a UTC bucket.

**`matchVitalWorkout` has no rejection threshold.** The `120` in the comparator
is not a match window; it's a tie-break switch between ranking-by-time and
ranking-by-distance. `min(by:)` always returns a winner. A candidate 23 hours
away on the same local day wins if it's the only one
(`HistoryDetailViewModel.swift:398-412`).

**A durable identity already shipped and nothing reads it.** Migration
`20260806015008` added `external_id` `NOT NULL` with `UNIQUE (user_id, external_id)`,
backfilled 276/276 with no collisions. Grepping the whole repo for `external_id`
returns exactly one write (`strava-sync/index.ts:614`) and **zero reads**. The
uniqueness constraint is doing its job silently; nothing else uses it.

**Cross-row damage this causes today, beyond the two known ones:**

| Fact | Written to | Read from | Mirrored? |
|---|---|---|---|
| `workout_notes` | journal (`saveEdits:191`) **and** import (`EditWorkoutNotesSheet:176`) | import (`WorkoutRepChart:518`) | one-way, and dead (Seam 0) |
| `workout_type` | journal (`saveEdits:191`) **and** import (`WorkoutLapsService.setType:549`) | import (`WorkoutRepChart:538`) | **no** |
| `mood` | journal | import (`WorkoutRepChart:452`) | **no** |
| `coach_insight` | both, independently | both, independently | **no** — two AI reads per run are possible |
| `stats_excluded` | whichever row Trends listed | `trends-timeline`, `trends-insights` | **no** — excluding one row leaves the other counted |
| `body_mentions` (niggles) | journal row (`process-training-memo:1155`, `record.id`) | import row (`ReceiptNiggleService.fetch`, `WorkoutReceiptSignals.swift:810`) | **no** |

That last one is worth naming on its own: **niggles are written against the memo
and read against the run.** A niggle the athlete voiced can never appear on the
receipt for the run it happened on. `body_mentions` also has no foreign key —
one row in the table is already dangling.

**Two bugs found while tracing that aren't seams, but should not sit:**

- `coach-workout-read/index.ts:161` selects `scheduled_workout_id` and
  `start_time`. Neither column exists. PostgREST 400s the select, `log` is
  `null`, and the function returns `404 "Workout not found"` on **every** call.
  `coach_workout_reads` has 0 rows. Two sibling functions carry comments about
  having removed `scheduled_workout_id` for this reason; this one was missed.
- `WorkoutsView.swift:971` writes `pace_segments` with **no `id` and no
  `user_id`** — `.gte/.lte("workout_date", ±300s)`. A broadcast write across a
  ten-minute window that stamps both rows of a pair and any other run in range.
  (`WorkoutsView` is currently unreachable, so this is latent, not live.)

---

## Seam 2 — eleven doors, four of them bricked

The same run opens a different screen depending on where you tapped it.

| Tap it from | Lands on | id passed |
|---|---|---|
| Log tab feed | **Journal** (`HistoryDetailPager`) | `entry` |
| Trends → signal lane day | **Journal** (pager) | `entry` |
| Trends → week sheet day | **Journal** (pager) — third modal deep | `entry` |
| Trends → head-to-head / pace bands | **Journal**, *no pager* | `entry` |
| Signal Lab chart scrub | **Journal**, *no pager* | `entry` |
| Train → HISTORY, WORKOUTS & REPS | **Receipt** | `training_logs` id |
| Train → day → DayAnalysisSheet → FULL ANALYSIS ↗ | **Receipt** | `training_logs` id, **Strava-only** |
| Plan day sheet → View details | **Receipt** | ⚠️ a **HealthKit device id**, not a row id |
| The Read → workout chip | **Receipt** | `training_logs` id |
| Journal → VIEW DETAIL ↗ | **Receipt** | `workoutDetailId` |
| Ask → any answer about a session | **nothing** | — |

Findings:

**Two id types flow into one parameter.** `WorkoutRepDetailSheet`'s own header
says `workoutId` is "the `training_logs` row id"
(`WorkoutRepDetailSheet.swift:19`). `DayDetailSheet.swift:514` and
`WorkoutsView.swift:96` pass `RunningWorkout.id`, which for a HealthKit match is
a device sample UUID (`HealthKitManager.swift:942`). `HistoryDetailViewModel`
already knows this trap and documents it at `:26-28`. Nothing enforces it. A
`UUID` typealias or a `TrainingLogID` wrapper type would make this
uncompilable rather than merely wrong.

**`WorkoutRepDetailSheet` is bypassed by three of the seven receipt call
sites.** `WorkoutsAndRepsSection.swift:77`, `CoachReadView.swift:548`, and the
inline embed each hand-roll their own `NavigationStack` + `ScrollView` +
`Text("WORKOUT").font(.dripStat(10)).tracking(1.0)` toolbar — copied verbatim
from `WorkoutRepDetailSheet.swift:36`. Four copies of the chrome, so any fix to
it (the missing Done button, the missing `toolbarBackground`) has to be made
four times.

**Deepest live path is four modals and five nav stacks for one run:** Log tab →
`HistoryDetailPager` → `HistoryDetailSheet` → `WorkoutRepDetailSheet` →
`EditWorkoutNotesSheet`. Trends → week sheet → day → journal → receipt is also
four.

**Nothing propagates back.** `WorkoutRepDetailSheet` takes `let workoutId: UUID`
and nothing else — no `onSaved`, no binding, no callback
(`WorkoutRepDetailSheet.swift:27`). Every editor inside the receipt refreshes
only the receipt (`WorkoutRepReceiptView.swift:338, 353, 361` — all
`onSaved: { Task { await load() } }`). The journal underneath holds a value
snapshot taken in `init` (`HistoryDetailSheet.swift:55`). And four of the seven
journal call sites pass `onUpdate: {}`, so a delete made from any Trends
drill-down leaves the chart behind it showing a row that no longer exists.
There is no `NotificationCenter` channel for `training_logs` — the only
app-level one is `.trainingPlanDidChange`.

**`VIEW DETAIL ↗` can render as a dead tap.** Shown when `hasLinkedWorkout`
(`workoutDate != nil && workoutDistanceMiles != nil`, `TrainingLog.swift:262`);
acts only when `matchedVitalWorkout != nil` (`Editorial.swift:567`), which is
filled asynchronously and — per Seam 0 — often never. The row reads
"LINKED · HEALTHKIT" with a coral affordance that does nothing.

**Ask has no drill-through at all.** `AskView.swift:96` presents only
`CoachAskSheet`; that file contains no `.sheet` or `fullScreenCover`. An Ask
answer about a specific session cannot be opened as that session. For a surface
whose whole job is "interrogate the block," that's a missing floor.

**Four of the eleven doors are in unreachable code:** `HistoryView` and
`WorkoutsView` exist only in `#Preview`; `TrainingPlanView`'s day-log-picker
branch is never triggered (`showDayLogPicker` is never set true); `LogView.swift`
is never constructed anywhere. Plus eleven other unmounted detail-adjacent views
and four in-tree `.bak` files. **The code's apparent entry-point count is
roughly double the shipped one**, which is most of why this area feels
unmappable when you go looking.

---

## Seam 3 — the same fact, twice, differently

With Seam 0 fixed, both surfaces render in one scroll view. Then these stop
being theoretical.

| Fact | Journal says | Receipt says | Why they differ |
|---|---|---|---|
| **Title** | `title ?? workoutTypeLabel ?? weekday` — "Intervals" | `"MMMM d"` of `workout_date` — "July 9." | Two title concepts, ~12 points apart in the same scroll |
| **Distance** | `%.0f`/`%.1f`/`%.2f` off the journal row (`TrainingLog.swift:270`) | always `%.2f`, km-aware, off row → stream → summed laps (`Receipt:896`) | "6" above "6.00" |
| **Duration** | h:mm:ss (`TrainingLog.swift:280`) | `clock()` reimplemented (`Receipt:917`) | diverge above one hour: `1:03:12` vs `63:12` |
| **Workout type** | 6-value vocabulary, writes `"interval"` | 9-value vocabulary, writes `"intervals"` | **two editors, two rows, two closed vocabularies** |
| **Mood** | `MoodBadge` off journal row | `MoodBadge` inside `VoiceMemoRow`, off receipt row | editing one never updates the other |
| **The words** | `cleaned_notes` only — section vanishes for a `notes`-only row | `cleaned_notes ?? notes` | the receipt quotes text the journal hides |
| **Source** | `"Garmin"`, hardcoded (`HistoryDetailViewModel.swift:459`) | the `source` column — "Strava" | "LINKED · GARMIN" above "· Strava" |
| **The read** | `coach_insight`, an LLM paragraph | `computedRead`, a deterministic sentence | two different "reads" on one screen |

Plus a silent data mutation: the journal's summary editor seeds
`cleanedNotes ?? notes` (`HistoryDetailSheet.swift:247`) and saves to
`cleaned_notes`. Tapping Edit then Save on a `notes`-only row **promotes the raw
transcript into `cleaned_notes`** without the athlete asking.

**And `workout_notes` renders twice in one scroll, under two labels:**
`WORKOUT NOTES` (journal composer, `Editorial:616`) and `THE WORKOUT` (receipt,
`Receipt:691`). Same column. Two editors. Neither knows about the other.

### What only one side has

| Journal only | Receipt only |
|---|---|
| Playable memo audio (`MemoPlayerRow`) | SIGNALS chips + thresholds |
| Verbatim transcript | Conditions — temp, dewpoint, heat cost, climb |
| The AI read (`coach_insight`) | Avg HR (journal has no HR accessor at all) |
| Athlete-authored `title` | Rep/lap tables, the hero bar chart |
| LINK A RUN / COMPARE / DELETE | Act 3 traces: HR zones, telemetry, recovery, route |
| Page-turn to sibling entries | Niggle chips (journal has **no** niggles surface) |
| Toolbar Done/Edit/Save | Fix reps, unit + heat toggles |

Neither list is wrong. They're the two halves of one session, and the product
thesis — "fuses quantitative training data with qualitative voice-log signal" —
is the sentence that says they belong on one page.

**Editability, after the Phase-0 patch:** 8 of ~28 visible fields. Both
`workout_notes` editors exist; the mirror runs in one direction only and, per
Seam 0, has never run at all. Niggle chips render a `↗` glyph and are
`.disabled(true)` (`WorkoutReceiptSignals.swift:769`).

---

## Seam 4 — they don't look like the same product

Once both render in one scroll, the visual mismatch is the first thing the eye
catches.

**Section headers are two different typefaces.** `Font.dripCaption` is PT Serif;
`Font.dripEyebrow` is SF Mono (`DesignSystem.swift:205-215`). The journal's
`DripEyebrow` primitive uses `.dripCaption(10)` tracking `1.4`. The receipt
inlines `.dripEyebrow(11)` tracking `1.3`. So `SUMMARY` and `WORKOUT NOTES` are
**serif**, and `SIGNALS`, `THE WORKOUT`, `TRACES` are **mono** — twenty points
apart. The receipt never uses `DripEyebrow`; the journal never uses
`.dripEyebrow` for a section label.

**Stat strips.** Same three numbers. Journal: PT Serif 18, labels `DIST`/`TIME`/
`PACE`, hairline top and bottom. Receipt: SF Mono 20, labels `Distance`/
`Duration`/`Avg Pace`, 1pt ink rule on top only.

**Four pace formatters** (`TrainingLog:292`, `rr_pace` at
`WorkoutReceiptCharts:1396`, `EditWorkoutStructureSheet:585`,
`WorkoutComparisonSheet:193` — the last two byte-identical to the second) and
**five clock formatters**. **Five date formats for one run**: `MAY 22`,
`WEDNESDAY · MAY 22`, `May 21, 9:06 AM`, `May 21, 2026 at 9:06 AM`, `TUESDAY` +
`July 9`.

**Opposite empty-cell conventions on the same screen.** `LapSplitsList` renders
`—` for a missing value (`WorkoutReceiptCharts:660`); `RepsTable` renders `""`
for the same one (`Receipt:1765`), with a source comment saying "never an
em-dash." Two tables, one surface.

**Coral budget.** The receipt is disciplined and says so in-source: "the one
coral mark in this cluster: the period" (`Receipt:409`). The journal spends
coral on Edit, Save, VIEW DETAIL ↗, COMPARE ↗, the ✦ rule, EDIT, SAVE, ＋, and
header text. Nested, the combined screen carries about a dozen coral marks
against a spec of one per cluster.

**Chrome.** `WorkoutRepDetailSheet` has no Done button and never sets
`.toolbarBackground(.visible, for: .navigationBar)` — which both
`HistoryDetailSheet:138` and `EditWorkoutNotesSheet:145` do. That's the clipped
headline in your screenshot from yesterday.

---

## What seamless should mean here

Not "merge two screens." One idea, stated three ways:

> **One session. One scroll. One editor per fact.**

- **One session.** `external_id` is the run's identity; `workout_notes.run_id`
  is the note's pointer at it. Both surfaces resolve to a session, never to a
  row. `workoutDetailId` and `entryId` stop existing as separate concepts.
- **One scroll.** Journal and receipt are *acts of one page*, not two sheets.
  The qualitative reads first (words, mood, niggles), the quantitative after
  (stats, signals, reps, traces) — which is the order `Editorial.swift:170`
  already argues for. `VIEW DETAIL ↗` disappears because there's nothing left
  behind it. Every entry point in the table above lands on the same page,
  scrolled to the relevant act.
- **One editor per fact.** Kill the global `isEditing` mode. Tap a value, edit
  that value, write it once. `AUTO` / `YOURS` provenance markers instead of an
  Edit button. This is the `EditWorkoutNotesSheet` + `EditWorkoutStructureSheet`
  pattern, generalized — you already built it twice.

The test: **an athlete who taps a run from Trends, from Train, and from the Log
feed sees the same page all three times, and can correct anything they can
read.**

---

## Sequence

Each step ships alone and leaves the app working. Steps S0–S2 are days; S3–S5
are the real work.

### S0 — turn the join on *(today, ~1 line + a guard)*

Add `strava`, `auto_sync`, `strava_backfill` to
`HistoryDetailViewModel.swift:441`, matching `VoiceLogView.swift:1394`.

Add the rejection threshold `matchVitalWorkout` never had, reusing the numbers
`voiceOrphanMatch.ts:26` already uses (±4 h, `max(0.5 mi, 8%)`). Without it, a
morning run and an evening run on the same day pair arbitrarily — 34 of 89
journal entries have no distance at all, so distance can't break the tie.

**What you'll see immediately:** the WORKOUT receipt and the COMPARE row appear
inside journal entries for the first time. 35 historical entries have a same-day
run to find. And Seams 3 and 4 become visible in one scroll, which is the point
— you can't design the join while it's dark.

### S1 — stop the two ends contradicting each other *(1–2 days)*

Before anything structural, close the writes that provably disagree:

1. Mirror `workout_type` both ways, or better — remove the receipt's picker and
   keep one editor. Two vocabularies (`"interval"` vs `"intervals"`) for one
   column is a data-quality bug, not just a UX one.
2. Point `ReceiptNiggleService.fetch` at both row ids so voiced niggles reach
   the receipt.
3. Delete one of the two `workout_notes` editors. `THE WORKOUT` on the receipt
   is the better home; the journal's `WORKOUT NOTES` composer duplicates it
   under a different name.
4. Fix `coach-workout-read`'s select list — it 404s on every call today.
5. Add a `TrainingLogID` wrapper type so a HealthKit device UUID can't be passed
   where a row id is expected (`DayDetailSheet:514`).

### S2 — one door *(2–3 days)*

Make every entry point land on the same surface. Concretely: delete the three
hand-rolled copies of `WorkoutRepDetailSheet`'s chrome; route
`WorkoutsAndRepsSection`, `CoachReadView`, `DayAnalysisSheet` and the plan day
sheet through the journal page rather than the bare receipt; give Ask a
drill-through. Add an `onUpdate` callback to the receipt and pass a real one
from all seven journal call sites — or a `NotificationCenter` channel for
`training_logs`, which is less plumbing.

Delete the four unreachable doors and the unmounted views while you're in there.
The map is unreadable at twice its true size.

### S3 — `workout_notes` table, dual-write *(the approved Phase 2)*

Per `docs/specs/runs-and-notes-split.md`. Nothing reads it yet; fully reversible.
Unchanged from the approved spec — no reason to re-litigate it here.

### S4 — one page, three acts *(the design work)*

With one session identity underneath, collapse journal + receipt into a single
scroll. Suggested acts, following the order the code already argues for:

1. **What it was** — date, title, stat strip, conditions
2. **What you said** — memo player, transcript, mood, niggles, the read
3. **What it was made of** — THE WORKOUT, signals, reps, splits, traces

One header treatment (pick mono or serif and delete the other),
one date formatter, one pace formatter, one clock, one empty-cell convention,
one coral mark per cluster. This is where Seam 4 gets paid off — it's mostly
deletion, not new code.

### S5 — tap-to-edit + provenance *(rolled out field by field)*

Delete `isEditing`. `SessionEditor.set(.field, value, for: sessionId)`, one call
site per field, optimistic update. `AUTO` markers on machine-derived values,
flipping to `YOURS` on correction. Start with the four fields testers actually
correct — description, transcript, mood, distance — and let the correction log
set the queue.

Ship S4 before S5. A merged page with 8 editable fields is a coherent product;
a split page with 28 editable fields is a bigger version of today.

---

## What not to do

- **Don't design the merged page before S0.** You'd be designing against a
  layout that has never rendered.
- **Don't add a tenth matcher.** Every screen that needs the pair should ask one
  function. The spec says this; nine implementations later, it's worth repeating.
- **Don't add a second `isEditing` mode to the receipt.** Two modal edit modes
  over two rows is how edits overwrite each other.
- **Don't make everything editable at once.** Four fields, watch what gets
  corrected, let that set the order.
- **Don't let the AI re-derive from athlete-edited text.** Once a field is
  overridden it's ground truth. `parse-workout-structure:97` respects
  `edited_by_user`; `strava-sync:625` sets `parsed_structure: null` on twin
  promote and then re-parses, which walks around that guard. Fix that when you
  touch S3.

---

## Open questions

1. **Does a note without a run get the same page?** 34 of 89 journal entries
   have no distance. The spec says a note with no run is "a valid, complete,
   displayable journal entry" — so act 1 and act 3 are empty. Is that the same
   page with two acts collapsed, or a genuinely different, shorter page?
2. **Who owns the title?** The journal has an athlete-authored `title`; the
   receipt titles by date. One has to win. (Weak preference: athlete title when
   present, date when not — the receipt's "July 9." reads better as an eyebrow
   than a headline.)
3. **One read or two?** `coach_insight` (LLM paragraph) and `computedRead`
   (deterministic sentence) are both on the page after S4. The computed sentence
   is the more trustworthy of the two and never fails. Does the AI paragraph
   stay?
4. **Mono or serif for section headers?** Deleting one of the two is the single
   largest visual-coherence win available, and it's a taste call, not a
   technical one.
