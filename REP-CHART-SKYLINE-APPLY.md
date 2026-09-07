# Rep chart — Skyline · apply notes

*Placed 2026-08-11. Single-file change plus one field on `RRRep` and one line in
`WorkoutRepReceiptView`. No new files, no new dependencies.*

Rebuilds the pace-bar axis and bar rendering in `RRRepBars`
(`RunningLog/RunningLog/Workouts/WorkoutReceiptCharts.swift`) so a normal
interval session reads as a skyline of tall bars instead of ten stubs in the
bottom quarter of the plot. Prototype: `rep-chart-skyline-prototype.html`
(variants explored in `rep-chart-variants-prototype.html` and
`rep-chart-zone-ladder-prototype.html`).

## The bug being fixed

On a 10 × 1K session — reps 5:10 → 5:22, avg 5:18 — the shipping chart draws a
3:00–6:00 axis and every bar fills 23% of the plot.

Three causes, compounding:

1. **A pace ratio decides what's a work rep.** `RRRepBars` is fed `allSplits`
   (every lap: warmup, reps, recovery jogs, cooldown) and brackets the axis with
   `allPaces.filter { $0 <= fastest * 1.6 }`. A 0.01 mi auto-lap reading 3:28/mi
   becomes `fastest`, drags `axisMin` to 3:00 **and** widens the 1.6× gate enough
   to let a slow lap set `axisMax`. That lap renders 2 px wide, so it is
   invisible while owning the entire scale.
2. **Bar height is measured up from `axisMax`.** With a 180-second axis, a
   5:18 rep is 23% tall and the 11-second spread between reps is ~2 px.
3. **Recovery laps draw as 3 px nubs** between the reps, chopping the rhythm.

Strava's chart is the same encoding; the only difference is that their axis span
is about 5× the rep spread rather than 15×, and their baseline is off-frame.

## Behaviour after

| | axis | span | slowest bar fills |
|---|---|---|---|
| before | 3:00 – 6:00 | 180 s | 23% |
| after | 5:00 – 5:45 | 45 s | 51% (fastest 78%) |

Work reps only in the strip; recovery becomes the gap. Bars run past the bottom
edge under a clip, with no baseline stroke drawn, so the eye reads the skyline
of tops against the gridlines.

---

## 1 · `RRRep` gains a role flag

`WorkoutReceiptCharts.swift`, the struct at line 32. Default `true` so every
existing caller (notably `continuousSplits`, where each mile split *is* the
work) keeps today's behaviour with no edit:

```swift
    var restPaceSec: Double? = nil  // recovery jog pace, sec/mi
    var restHR: Int? = nil          // avg HR during the recovery
    /// False for warmup, recovery jogs, cooldown and stray auto-laps. Only
    /// work reps set the pace axis and draw a bar — role, never a pace ratio.
    /// A GPS-glitched 4-second lap is excluded because of what it *is*, not
    /// because of how fast it looks.
    var isWork: Bool = true
```

## 2 · Populate it where `allSplits` is built

`WorkoutRepReceiptView.swift` ≈ line 1408. The view already computes the
authoritative work set in `reps` (line 155) and matches it by `lap_index` in
`slots` (line 184) — reuse exactly that:

```swift
        do {
            var cum = 0.0
            let workIdx = Set(reps.compactMap { $0.lap_index })   // ← add
            allSplits = orderedLaps.enumerated().map { i, lap in
                ...
                return RRRep(
                    id: i + 1,
                    ...
                    elevFt: elevNetFt(start: start, end: end),
                    isWork: lap.is_rest != true                    // ← add
                        && workIdx.contains(lap.lap_index ?? -1)
                )
            }
        }
```

Warmup and cooldown are not `is_rest` and are not in `reps`, so they correctly
fall out too.

## 3 · The axis rule

Replace `WorkoutReceiptCharts.swift` lines **246–264** (the block from the
`// Pace axis (faster sits higher)` comment through the `ticks` binding) with a
call to a new static function on `RRRepBars`:

```swift
                let workPaces = reps.filter(\.isWork).map(pace)
                let ax = Self.skylineAxis(workPaces.count >= 2 ? workPaces : reps.map(pace))
                let axisMin = ax.min, axisMax = ax.max
                let axisSpan = max(axisMax - axisMin, 1)
                let ticks = ax.ticks
```

And add the function to the type:

```swift
    /// Skyline axis for the rep bars.
    ///
    /// Two guarantees: the slowest work rep fills at least 45% of the plot and
    /// no more than 80%, so a set always carries mass without being squashed
    /// against the ceiling. Everything else follows from the rep spread —
    /// target span is 5× it, which is roughly what Strava's rep charts land on.
    ///
    /// The rule this replaces keyed off `fastest * 1.6` over EVERY lap, so one
    /// 0.01 mi auto-lap reading 3:28/mi pulled the floor to 3:00 and left ten
    /// 5:1x reps as 23% stubs under three quarters of dead plot.
    static func skylineAxis(_ paces: [Double])
        -> (min: Double, max: Double, step: Double, ticks: [Double])
    {
        let fast = paces.min() ?? 300
        let slow = paces.max() ?? 360
        let spread = max(slow - fast, 4)              // a dead-even set still gets air
        let want   = min(max(spread * 5, 30), 240)
        var step   = niceStep(want / 4)
        var lo = (fast / step).rounded(.down) * step
        if fast - lo < step * 0.2 { lo -= step }      // never crowd the ceiling
        var hi = (slow / step).rounded(.up) * step
        var guardCount = 0
        while (hi - slow) / max(hi - lo, 1) < 0.45, guardCount < 12 {
            hi += step; guardCount += 1
        }
        while (hi - slow) / max(hi - lo, 1) > 0.80, hi - lo > step * 2 { lo -= step }
        // Grew a lot? Coarsen the ladder once so it never turns into 9 labels.
        if (hi - lo) / step > 6 {
            step = niceStep((hi - lo) / 4)
            lo = (lo / step).rounded(.down) * step
            hi = (hi / step).rounded(.up) * step
        }
        return (lo, hi, step, stride(from: lo, through: hi + 0.5, by: step).map { $0 })
    }

    private static func niceStep(_ raw: Double) -> Double {
        [5.0, 10, 15, 20, 30, 45, 60, 90, 120].first { $0 >= raw } ?? 120
    }
```

Worked cases (add these as tests — see §7):

| session | spread | axis | ticks | slowest fill |
|---|---|---|---|---|
| 10 × 1K, 5:10–5:22 | 12 s | 5:00 – 5:45 | 4 | 51% |
| dead-even, all 5:18 | 0 s | 5:10 – 5:30 | 3 | 60% |
| ragged, 5:00–7:00 | 120 s | 4:00 – 10:00 | 7 | 50% |

## 4 · Work-only bars, rest as the gap

`barLayout(plotW:)` (line 310) currently emits one bar per lap. Change it to
skip non-work laps and fold their duration into the gap that precedes the next
work bar, so gap width stays proportional to real rest:

- iterate `reps`; when `!r.isWork`, add its duration to a pending rest
  accumulator and emit **no** layout entry
- when `r.isWork`, emit the bar, then the gap = `baseGap` + pending rest scaled
  the same way `restRatio` is today
- raise `baseGap` from `2` to `4` — with the nubs gone, the reps need air

**Layout entries must carry their source index.** Return
`[(x: CGFloat, w: CGFloat, idx: Int)]` instead of `[(x:, w:)]`. This is the one
place the change can silently break something: `repIndex(at:layout:)` (line 377),
the tap gesture (line 280), `plotCanvas`'s
`for (i, r) in reps.enumerated() where i < layout.count` (line 408), the
elevation `cx(i)` helper (line 355) and `readout(_:index:)` / `decoupling(_:)`
all currently assume `layout[i]` ↔ `reps[i]`. Every one of them must go through
`idx`, or tap-to-select silently selects the wrong rep.

## 5 · Skyline rendering

In `plotCanvas` (line 349):

- **Bars bleed past the floor.** Extend the rect by 10 pt
  (`height: max(baseY - top, 3) + 10`) and wrap the bar loop in
  `ctx.drawLayer { l in l.clip(to: Path(CGRect(x: 0, y: 0, width: width, height: plotH))); … }`.
  Keep `Path(roundedRect:cornerRadius: 4)` — the bottom rounding is clipped away,
  so there's no need to hand-build a top-only rounded path.
- **Delete the baseline stroke** (lines ~397–399, the `var base = Path()` block).
  A drawn baseline invites area comparison against a floor that is arbitrary;
  hiding it makes the tops the thing you read.
- **Delete the per-gap separators** (lines 401–406). With real gaps they're
  clutter.
- **Fill opacity** `0.72` → `0.90` (selected stays `1.0`). Ink mass is the point.
- Gridline opacity can drop to `0.5` — with taller bars they only need to be
  legible where they cross empty paper.

Everything else in the canvas — elevation ghost, AVG dashed line, selection
stroke, rep numbers — stays as is.

## 6 · What deliberately does not change

- `RRRepBars`'s public signature, so `WorkoutRepReceiptView` line 809 and the
  continuous-splits call at line 814 are untouched apart from the new field.
- The HEAT-ADJ path: `pace(r)` still resolves adjusted vs raw, and the axis is
  computed from those same values, so the toggle still moves the bars and
  `avgLineSec` still tracks them.
- `LapSplitsList` below the chart still shows **every** lap including `rec`
  rows. Recoveries leave the chart, not the screen.
- Zone-anchored floors (`rep-chart-zone-ladder-prototype.html`) are **not** in
  this pass. They need `PaceZonesEngine` anchors plumbed into `RRRepBars`, which
  is a bigger change; the 5×-spread rule gets the same visual result today.

## 7 · Tests

New `RunningLogTests/RepChartSkylineAxisTests.swift`, Testing framework, over
`RRRepBars.skylineAxis`:

1. the three worked cases in §3, asserting min/max/step and fill ratio
2. **the regression that started this**: work paces `[310…322]` plus a 208 s/mi
   glitch lap → asserting the glitch is excluded by role, and that passing it in
   anyway never pulls `min` below `fast - 2 * step`
3. slowest-rep fill is always within 0.45…0.80 across a sweep of spreads
   (0…240 s) — the invariant the whole rule exists to hold
4. tick count never exceeds 7

## 8 · Check by eye after

Open a 10 × 1K session. Bars should reach roughly half to four-fifths of the
plot, four gridlines, no visible floor line, recoveries gone from the strip and
still present in the table below. Toggle HEAT-ADJ — the axis should re-scale and
the bars should stay tall. Tap rep 7 and confirm the readout says rep 7.
