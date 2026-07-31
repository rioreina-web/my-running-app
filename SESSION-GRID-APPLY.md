# Key Sessions grid — apply notes

*Placed 2026-07-27. Follows the repo's additive-new-files + minimal-tracked-edits
convention (see `TRENDS-WEEKLY-MONTHLY-APPLY.md`, `SHARP-END-APPLY.md`).*

Adds the **session grid** as the Trends hero: `y = Mon→Sun`, `x = week`, one dot
per quality session on the day it happened, **size = effort**, **colour = pace
zone**. Sessions below an effort floor draw as an open ring instead of a filled
dot. The existing `UnifiedTrainingChart` and every drill-down are untouched and
still render below.

Design rationale and the prototype are in `trends-multitrack-prototype.html`
(flip the dataset toggle to see it on real prod data).

---

## What it answers

*What quality work did I actually do, when, and how big was it?* The weekly
rhythm — a Tuesday threshold habit, a Wednesday second session, Friday strides —
is invisible in any weekly-total chart, and so are the weeks it breaks.

## The effort score

**Quality load = Σ over work bouts of `seconds × ZONE_WEIGHTS[zone]` ÷ 60.**

No new maths. `segmentFromLaps` already computes that weighted sum — it just
divides it by total time and throws the numerator away, producing the
whole-workout `intensity_score` that `_shared/quality-volume.ts` documents as
broken. Integrating instead of averaging, restricted to `isWork` bouts, is the
entire change.

**Floor = 25 weighted minutes**, calibrated against 23 real lap-scored sessions
in prod on 2026-07-27:

| | load |
|---|---|
| stride sets (4) | 5.4, 6.4, 11.7, 13.1 |
| *— nothing in between —* | |
| smallest real session | 42.1 |
| largest real session | 103.5 (`6×1mi @ 5:12`) |

Any floor from 15 to 40 keeps the same 19 and cuts the same 4. The exact value
is not load-bearing; the gap is real.

⚠️ **Known limitation, worth reading before tuning the weights.** Across those
sessions quality load correlates **0.965** with plain work-duration — the
mp→mile weight spread is only 2× while duration spans 30×. For the *gate* alone,
`work_seconds >= 300` gives the identical split with no weight table. The
weights earn their keep on dot size (1.9× spread in load-per-minute), not on the
gate.

---

## Files placed automatically (new, additive — safe)

- `RunningLog/RunningLog/Trends/TrendsQualityLoad.swift`
  — the score, the floor, the gate, and Mon-first weekday/week-start maths.
    Pure, no view code.
- `RunningLog/RunningLog/Trends/TrendsSessionGrid.swift`
  — the Canvas grid + `sessionSummary(for:sessions:)` for the readout.
- `RunningLog/RunningLogTests/TrendsQualityLoadTests.swift`
  — 17 `Testing` cases: weights mirror the backend, sum-not-average, the four
    real stride loads gated out, the five real session loads kept, nil-load
    never promotes, Mon-first indexing, week-start across month/year boundaries.
- `supabase/functions/trends-timeline/qualityLoad.ts`
  — `qualityLoadForBouts()`. Scores only; deliberately does not gate.
- `supabase/functions/trends-timeline/qualityLoad.test.ts`
  — 9 Deno cases including the calibration boundary.

If the Xcode project uses file-system–synchronized groups (the small
`project.pbxproj` suggests it does), the two Swift files and the test are picked
up on next open. Otherwise add them to the app / test targets once.

---

## Tracked-file edits — APPLIED 2026-07-27

All four are already in your working tree. Recorded here so you can review the
diff, and so revert is a known quantity.

### 1. `supabase/functions/trends-timeline/keySessions.ts`
- imports `qualityLoadForBouts` from `./qualityLoad.ts`
- `KeySessionOut` gains `quality_load: number`
- `deriveKeySession` returns `quality_load: qualityLoadForBouts(workBouts)`
  (`workBouts` was already in scope — rest is excluded by `isWork` upstream)

`keySessions.test.ts` asserts field-by-field, not on whole objects, so the new
field breaks nothing. **Needs a `trends-timeline` redeploy to take effect.**

### 2. `RunningLog/RunningLog/Trends/TrendsModels.swift`
- `TrendsWeek` gains `var weekStart: String = ""`
- `KeySession` gains `var qualityLoad: Double? = nil`

Both default and sit last, so `TrendsSampleData` and
`TrendsAggregation.monthly` — which use labelled initialisers and omit them —
compile untouched.

### 3. `RunningLog/RunningLog/Trends/TrendsService.swift`
- `KeySessionDTO` gains `qualityLoad: Double?` + `case qualityLoad = "quality_load"`
- `KeySessionDTO.toModel()` passes `qualityLoad`
- `TrendsWeekDTO.toModel()` passes `weekStart` — the DTO already decoded
  `week_start` and discarded it

### 4. `RunningLog/RunningLog/Trends/TrendsTabView.swift`
`TrendsSessionGrid` inserted in `loadedContent` between `readout` and
`UnifiedTrainingChart`, guarded by `granularity == .weekly`, sharing
`scrubIndex` so grid and chart scrub together.

## Verify — what's left for you

1. **Build in Xcode.** I can't compile Swift in the cloud sandbox, so this is
   the first real check. If the two new Swift files aren't picked up
   automatically, add them to the app / test targets once.
2. `⌘U` → `TrendsQualityLoadTests`, 17 green.
3. `deno test supabase/functions/trends-timeline/qualityLoad.test.ts`, 9 green.
4. **Deploy `trends-timeline`.** Until you do, `quality_load` is absent from
   the payload, every load decodes as nil, nothing clears the floor, and the
   grid shows its empty state. That is the designed failure mode — it degrades
   to "no key sessions yet" rather than promoting strides. Then open Trends. Expect on your own account:
   a Tuesday band (10 of your 19 sessions), a Wednesday band, Friday strides as
   **open rings**, and Monday/Thursday empty.

## Two things you will notice immediately, and they are data, not bugs

- **Your quality sessions start 23 March.** There is no lap data before it, so
  nothing earlier can be classified and the left third of a 6-month grid is
  blank. Either the lap sync has a gap or a backfill is owed.
- **No HRV / sleep / rest exists anywhere in the schema**, so the Recovery track
  has nothing to draw. It renders its empty state rather than implying numbers.

## Recommended follow-up (not in this change)

**Default the range to 12 wk and drop the grid at 6 MO.** On real data the grid
is ~10% full over 26 weeks — legible at 12 weeks, mostly whitespace at 26. The
grid is right; the range is wrong. A weekly-total view serves that zoom better.

## Reverting

`git checkout` the four tracked files and delete the five new ones. Everything is additive and
the existing chart is untouched, so revert is clean. Leaving `quality_load` on
the payload is harmless if you only revert the client.
