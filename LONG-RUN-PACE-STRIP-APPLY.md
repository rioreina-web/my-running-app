# Long runs get a pace chart — apply notes

**Date:** 2026-08-20 · **Surface:** Trends §03 "Key sessions" + Train card
**Scope:** one new file, two three-line branches, one header comment

---

## Context

Long runs landed in the Key Sessions ledger yesterday
(`KEY-SESSIONS-LONG-RUNS-APPLY.md`). That change said of the chart under each
row: *"Density strip — keep it, unchanged … the ones with real mile splits —
14, 22, 25, 26, 29 laps — will draw a flat easy-coloured band, and a
progression long run will visibly ramp."*

Half of that was wrong, and it's worth writing down why, because the mistake
was reasoning about a component instead of running it on the data.

`RepDensityStrip` calls `WorkoutLapsService.mergeWorkBouts` **first**. That
joins every consecutive non-rest lap into one bout — the correct reading of a
rep workout, where a 2 mi rep the watch auto-lapped at each mile is ONE rep.
Applied to a long run, it deletes exactly the thing a long run has to show.
And it renders nothing at all below 2 blocks.

Run it against the six long runs in the last 90 days that carry splits:

| Run | Recorded splits | What ships today |
|---|---|---|
| 2026-08-01 · 17.0 mi | 25 | **3 slabs** (one per water stop) |
| 2026-07-25 · 13.1 mi | 14 | **nothing** — one bout |
| 2026-07-11 · 15.0 mi | 26 | **2 slabs** |
| 2026-06-27 · 17.8 mi | 29 | **nothing** — one bout |
| 2026-06-20 · 13.0 mi | 22 | **nothing** — one bout |
| 2026-05-24 · 14.0 mi | 23 | **nothing** — one bout |

Four of six draw no chart; the other two draw a picture of where the athlete
stopped for water, not of how the run was paced. The Jun 27 run went out at
7:26, came down to 6:18 through the middle third, and faded to 7:27 over the
last three km. None of that reached the screen.

**Outcome wanted:** a long run's row shows the run's own splits, so a fade, a
progression, or a genuinely even run are each visible at a glance and
distinguishable from each other.

---

## Decisions taken

| Question | Decision |
|---|---|
| Mark | **One continuous bar**, split at the recorded splits, no gaps |
| Width | **∝ split distance** — same rule as the rep strip |
| Colour | **The app-wide zone-anchored PaceSpectrum ramp** |
| No splits recorded | **Draw nothing** |
| Pause laps | **Dropped, not drawn** — the bar closes over them |

**Why no gaps.** In `RepDensityStrip` the gaps carry meaning: they are the
rest. A long run has no rest, so gaps there would be a statement about the
session that isn't true. One unbroken bar with internal structure says
"continuous effort, varying pace", which is what a long run is.

**Why the app-wide ramp, not a per-run stretch.** Stretching each run's own
slowest split to palest and fastest to darkest gives far more contrast — and
makes a 6:50 mile navy on one row and pale on the next. The whole point of
`PaceSpectrum.anchoredColor` is that the same pace is the same colour on every
surface. The honest cost, stated plainly: these six runs span 5:54–8:35, which
sits in the pale third of the ramp between Easy (7:33) and Steady (5:57). The
variation is real and readable, but it is not dramatic, because a long run is
not dramatic. See `long-run-pace-strip-prototype.html` for both side by side
on real data.

**Why nothing when there are no splits.** 2026-08-16 (17.1 mi), 2026-08-08
(18.1 mi) and 2026-07-18 (13.5 mi) each carry a single summary lap — no
splits were ever recorded, and no stream table exists to recover them. A flat
bar at the average would be a picture of even pacing the app never measured.
This matches `deriveKeySession`, which emits no dot for a lap-less session
rather than a faked one.

---

## The changes

### 1 · New file · `RunningLog/RunningLog/Workouts/LongRunPaceStrip.swift`

Sibling to `RepDensityStrip`, ~90 lines of view. Takes the same
`[WorkoutLapRow]`, same `height` parameter, same colour helper shape.

- Sorts by `lap_index`, keeps laps that were actually run
  (`is_rest != true`, ≥150 m, ≥20 s, pace > 0) — the same predicate
  `RepDensityStrip` and `isContinuousAutoLap` already use, so the three never
  disagree about which laps are real. **No `mergeWorkBouts`.**
- Renders nothing below **4** splits (`minSplits`). Four is the floor at which
  a fade is legible; a one-lap long run falls far below it.
- One `Canvas`: clip to a 1.5 pt rounded rect, then fill each split
  edge-to-edge. Each split overruns 0.5 pt into the next so antialiasing can't
  leave a pale hairline and invent a boundary; the last runs to the edge,
  absorbing rounding drift.
- Colour: `PaceSpectrum.anchoredColor(paceSec:zones:)` → the run's own
  slow/fast bounds when there's no zone table → flat ink when the run has no
  spread. Identical fallback ladder to the rep strip.

The Xcode project uses `PBXFileSystemSynchronizedRootGroup`, so the new file
needs no `project.pbxproj` edit — it's picked up on open.

### 2 · `WorkoutsAndRepsSection.swift` — two branches

Both `receipt(_:)` and `editorialReceipt(_:)` already compute `let long =
isLongRun(w)`. The strip call site becomes:

```swift
if long {
    LongRunPaceStrip(laps: laps).padding(.top, 9)
} else {
    RepDensityStrip(laps: laps).padding(.top, 9)
}
```

(and the same with `height: 10` in the editorial row). `long_wo` still takes
the rep strip — a long run *workout* has reps.

### 3 · `WorkoutsAndRepsSection.swift` — header comment

The "A long run is NOT dressed like a workout" list gains a fourth bullet
recording the chart choice and why a lap-less long run draws nothing.

---

## Verification

1. **Build:** `./build.command` (or ⌘B).
2. **Xcode preview:** open `LongRunPaceStrip.swift` → the canvas shows the real
   Jun 27 lap sequence at both heights, then a lap-less run rendering nothing.
3. **Read the tab:** Trends → §03. Expect
   - `2026-08-16`, `2026-08-08` — LONG chip, `6:42 /mi avg`, **no bar**.
   - `2026-08-01` — a bar of ~23 splits, alternating (this watch lapped both
     miles and part-miles), visibly darker where the miles were 5:56–6:20.
   - `2026-06-27` — pale at both ends, deepest through the middle. The fade.
   - `2026-08-18` `3×2mi` — unchanged: three blocks, two gaps.
4. **Train tab regression:** the KEY SESSIONS card shows the same two marks at
   the taller 12 pt height.
5. **Re-derive the table above:**
   ```sql
   select l.workout_date::date, l.workout_distance_miles,
          count(p.*) filter (where not p.is_rest) splits
   from training_logs l left join running_workout_laps p on p.workout_id = l.id
   where l.workout_type in ('long_run','long_wo')
   group by 1,2 order by 1 desc limit 12;
   ```

---

## Follow-ups (not this change)

1. **The lap-less long runs are an ingestion gap, not a display gap.** Three of
   the last six long runs arrived with one summary lap. Worth finding out which
   source path drops laps — the same runs' rep-workout siblings from the same
   week have full lap tables.
2. **A tap-through has no split chart either.** `WorkoutRepDetailSheet` renders
   rep geometry; a long run opens it and sees a single bout. The full-size
   version of this strip, with a pace axis and mile labels, belongs there.
3. **`2026-07-18` still appears twice** — same run ingested twice. Dedupe
   belongs in ingestion (carried over from the previous apply notes).
