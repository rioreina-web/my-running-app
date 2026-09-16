# Long runs are key sessions — apply notes

**Date:** 2026-08-19 · **Surface:** Trends §03 "Key sessions" · **Scope:** one file, plus copy

---

## Context

The Key Sessions ledger on Trends is meant to answer "what were the sessions that
mattered in this block?" Today it answers a narrower question: *what were the rep
workouts?* Every row in the screenshot is LT or 5K work. The Saturday long run —
the single biggest aerobic stimulus of the week, averaging **14.0 mi** across 21
sessions in the last 180 days — appears nowhere on the tab.

The interesting part: **the backend already got this right.**
`supabase/functions/trends-timeline/keySessions.ts` admits long runs explicitly,
tags them `kind: "long_run"`, scores their load over all bouts, and its header
comment records exactly this bug being fixed once already ("14 of 15 long runs
carry not one MP-or-faster lap, so the Saturday row of the session grid was
empty while the athlete was running 13.8 miles on it"). The iOS `KeySession`
model mirrors it, right down to `isLongRun`.

The ledger on screen doesn't use that payload. When the dot grid came out on
2026-08-17, `WorkoutsAndRepsSection` was promoted from a card inside
`KeySessionsDetailView` to being the section itself — and it carries **its own
fetch**, with its own hard-coded list of what counts:

```swift
// WorkoutsAndRepsSection.swift:73
private static let qualityTypes =
    ["intervals", "interval", "threshold", "tempo", "fartlek", "progression", "race"]
```

No `long_run`. No `long_wo` either — so "Long run workout", a type the taxonomy
in CLAUDE.md defines and `SessionRollup.qualityKeys` already treats as quality,
is invisible on this surface too.

**Outcome wanted:** the ledger reads like the training week actually happened —
Tuesday threshold, Saturday long — with long runs marked apart so their numbers
are never mistaken for rep numbers.

---

## Decisions taken

| Question | Decision |
|---|---|
| Placement | **Mixed into the one chronological list**, marked apart |
| Right-hand number | **Whole-run average pace, labelled `avg`** so it can't read as rep pace |
| What qualifies | **Classifier label only** — `long_run` (+ `long_wo`), no distance rule |

Label-only keeps one definition of "long run" in the app. The cost, stated
plainly: two `steady` runs at 11.5 mi and a few 13 mi `tempo` runs in the data
won't be treated as long runs. That's a classifier problem, and it should be
fixed in the classifier, not papered over with a second rule here (see
Follow-ups).

---

## The changes

All in **`RunningLog/RunningLog/Training/Analytics/WorkoutsAndRepsSection.swift`**
unless noted.

### 1 · Admit them (line ~73)

Rename `qualityTypes` → `keySessionTypes` (the list is no longer "quality"; it's
"what counts as a key session") and add both long types:

```swift
private static let keySessionTypes = [
    "intervals", "interval", "threshold", "tempo", "fartlek",
    "progression", "race", "long_run", "long_wo",
]
```

`long_wo` is a *workout* that happens to be long — it has reps, so it takes the
normal quality treatment below. Only `long_run` gets the long-run dress.

Add one predicate next to it, routed through `WorkoutLabel.normalize(_:)` (the
existing helper — `App/WorkoutLabel.swift:156` — so `"longrun"` and `"long"`
resolve too, and no call site open-codes a raw string comparison):

```swift
private func isLongRun(_ w: QualityWorkout) -> Bool {
    WorkoutLabel.normalize(w.workout_type) == "long_run"
}
```

### 2 · Fetch the duration (`fetchPage`, line ~430)

Add `workout_duration_minutes` to the `.select(...)` and to the private
`QualityWorkout` struct. It's the fallback for average pace when a long run has
no laps — verified present on **23 of 24** long runs in the last year.

### 3 · Title: "Long run · 17.1 mi"

Long runs *do* carry a `workout_structure`, but it reads `"17.1 mi long"` — so
today's `title()` would render **"17.1 mi long · 17.1 mi"**, the distance twice.
In `title(_:_:)`, when `isLongRun`, ignore the stored structure and return
`"Long run"`, letting the existing `distSuffix(_:)` append the miles.

### 4 · Chip: `LONG`

`structureParts` finds no `(zone)` suffix on a long run, so the chip comes back
nil. In both `receipt` and `editorialReceipt`, fall back to a `LONG` chip when
`isLongRun` and no zone chip was parsed. Same capsule, same tracking — set in
`Color.drip.textTertiary` rather than `textSecondary` so a column of long runs
reads as quieter punctuation than a 5K chip.

### 5 · The right-hand number — the honest bit

`repPace(_:)` computes a distance-weighted **work-bout** pace. Run it on a long
run and it happily returns the whole-run mean (long runs have no rest laps to
exclude) and prints it in the same column, same weight, as a 5:19 rep pace.
Those two numbers are not comparable — which is exactly why `KeySessionOut.kind`
exists on the backend and why the client "never draws them on one scale".

Add a flag to the existing struct rather than a parallel path:

```swift
private struct RepPace { let label: String; var isAvg: Bool = false }
```

- **Quality row** — unchanged: `repPace(_:)` off the laps, `○` prefix when
  heat-adjusted, unit `"/mi"`.
- **Long-run row** — new `avgPace(_:)`: prefer laps (sum distance ÷ sum moving
  time, all laps, nothing excluded); when there are no laps, fall back to
  `workout_duration_minutes / workout_distance_miles`. Returns
  `RepPace(label:, isAvg: true)`. No heat adjustment — the backend emits
  `work_pace_adj_sec: null` for long runs and this should match.
- **Rendering** — when `isAvg`, the unit reads `"/mi avg"` and the number is set
  in `Color.drip.textSecondary` rather than `textPrimary`. One glance
  distinguishes the record of a workout from the summary of a run.

### 6 · Density strip — keep it, unchanged

`RepDensityStrip` renders nothing below 2 blocks, so the 1-lap long runs (several
in the data) degrade to no strip on their own. The ones with real mile splits —
14, 22, 25, 26, 29 laps — will draw a flat easy-coloured band, and a progression
long run will visibly ramp. That's a true reading of the session, on the same
`PaceSpectrum` ramp as everything else. No change needed.

### 7 · Copy

- Empty state (line ~144): *"No key sessions logged yet. The first interval day,
  MP miles, LT session or long run lands here."*
- `.card` label (line ~173) `"WORKOUTS & REPS"` → `"KEY SESSIONS"`. Five call
  sites use `.card` (`TrainingTabView`, `TrainingTabTwoView`, `ModelOfYouView`,
  two in `TrendsDetailViews`), and once long runs are in the list, the old label
  is a lie. One definition, one name, everywhere.
- The section header on Trends (`TrendsLegacyTabView.swift:373`) already says
  "Key sessions · One line per session" — correct as-is, and now true.
- File header comment: update the "Data" paragraph (currently "quality types")
  to state the new definition and why long runs carry an average, not a rep pace.

---

## Verification

1. **Build:** `./build.command` (or ⌘B in Xcode).
2. **Read the tab:** Trends → §03. Expect ~8 rows opening, and the recent long
   runs interleaved — Aug 16 (17.1 mi), Aug 8 (18.1 mi), Aug 1 (17.0 mi) should
   land above and between the Aug 18 / Aug 11 threshold rows.
3. **Check each shape against real data** — these rows exercise every branch:
   - `2026-08-16` · 17.1 mi · **1 lap** → title "Long run · 17.1 mi", LONG chip,
     avg pace from the single lap, **no** density strip.
   - `2026-08-01` · 17.0 mi · **25 laps** → strip present, flat easy band.
   - `2026-05-11` · **no distance, no laps** → title "Long run", no pace, chevron.
     Nothing invented.
   - `2026-08-18` · `3×2mi` → unchanged: LT chip, `5:19 /mi`, rep strip.
4. **Tap through:** each long run opens `WorkoutRepDetailSheet`, which already
   handles a lap-less run (see its "voice-logged run has no laps" path).
5. **Regression on Train:** the `.card` instances should show the same rows under
   the new "KEY SESSIONS" label, four at a time.
6. **Query to re-derive the expectations above:**
   ```sql
   select l.workout_date::date, l.workout_distance_miles, l.workout_duration_minutes,
          (select count(*) from running_workout_laps p where p.workout_id = l.id) laps
   from training_logs l
   where l.workout_type in ('long_run','long_wo')
   order by l.workout_date desc limit 10;
   ```

---

## Follow-ups (not this change)

1. **Two definitions of "key session" still exist.** The backend
   (`keySessions.ts` → `KeySession.kind`) and this ledger's own
   `training_logs` fetch answer the same question separately. They now agree,
   but nothing keeps them agreeing. The durable fix is for the ledger to render
   `TrendsService.keySessions` — already fetched for this tab, already carrying
   `kind`, `qualityLoad` and the classified zone — and keep the direct fetch only
   for the Train card. Worth doing before a third surface asks the question.
2. **Classifier mislabels.** A 14.0 mi run on 2026-02-28 is typed `long_run`
   but carries the structure `"1400m-300m-300m-1mi @ 5:36 (threshold)"` — that's
   a `long_wo`. Two `steady` runs at 11.5 mi are long runs by any reading.
   Worth an audit pass on `workout_type` assignment.
3. **A duplicate row.** `2026-07-18` appears twice, 13.49 mi both times — same
   run ingested twice. It will now show as two long runs in the ledger. Dedupe
   belongs in ingestion, not in this view.
