# Workout Detail — "Rep Receipt" (Direction A) port

Drop-in for the full-screen workout detail. Design source:
`Workout Detail Redesign.html` → artboard **A · Rep Receipt**.

## Files

| File | Role |
|---|---|
| `WorkoutRepReceiptView.swift` | The screen. `init(workoutId:)` + preview `init(laps:zones:)`. Owns data loading, sections, the diverging-bar splits, weather copy. |
| `WorkoutReceiptCharts.swift` | Hand-drawn chart kit (`RR*` views) + shared models/helpers (`rr_*`). No chart dependency. |

Both compile against what already exists — no new dependencies:
- `WorkoutLapsService`, `WorkoutLapRow`, `RepChartZones`, `WorkoutPrescription` (from `WorkoutRepChart.swift`)
- `ExternalStreamAdapter`, `VitalWorkoutStream`, `StreamMeta` (streams + route)
- `Color.drip` / `Font.drip*` tokens, `supabase`, `Log`

## The swap (one line)

`WorkoutRepDetailSheet.swift`:

```swift
ScrollView {
-   WorkoutRepChart(workoutId: workoutId)
+   WorkoutRepReceiptView(workoutId: workoutId)
        .padding(20)
}
```

I left `WorkoutRepChart` **untouched** on purpose — it's still embedded in the
compact contexts (Trends, Coach Read) where the full dense screen would be too
much. Only the canonical detail sheet gets the receipt. If you'd rather it
*replace* RepChart everywhere, rename the struct to `WorkoutRepChart` and delete
the old one — the init signatures match.

## What's new vs. the current screen

Kept verbatim: type pill + picker, prescribed-workout headline, ANALYSIS with
on-demand **Generate AI insight**, heat-adjust.

Added (all from `external_streams`, loaded in parallel):
- **Hero rep chart** — bars width ∝ distance (2K wider than 1K), height ∝ speed, avg-HR line over the tops, target-pace dashed refs, rest gaps to scale.
- **Stat strip** — AVG WORK / WORK / AVG HR / SPREAD.
- **THE READ** — weather woven into the sentence (temp + dew point + cool-air equivalent).
- **Time in HR zone** stacked bar.
- **HR over full session** with zone bands + rep windows.
- **Pace trace**, **cadence**, **elevation + grade** (grade computed from altitude/distance deltas — `VitalWorkoutStream` has no grade field).
- **Per-rep HR recovery** small-multiples (drop in each rest).
- **SPLITS vs target** — diverging bars anchored to your session target pace, Δ column, rest jogs as interstitials, totals footer.
- **Route** — line colored by work/easy (or HR zone), rep-start pins.

Three inline chips toggle **heat-adjust**, **zone color**, **mi/km** (the HTML
Tweaks panel, native).

## Graceful degradation

Every stream section is gated on `hasStream`. A manual entry or a run with no
`external_streams` still renders: headline, rep chart, stat strip, the read,
time-in-zone (from rep HR), and the splits table. The preview at the bottom of
`WorkoutRepReceiptView.swift` is lap-only and shows exactly that path.

## Status / wiring

1. **Comparison vs recent same-type sessions** — ✅ BUILT (2026-06-19).
   `WorkoutLapsService.fetchRecentSimilar(type:excluding:limit:)` returns
   `[RecentSimilarWorkout]` (date label, avg work pace, avg HR). Rather than a
   per-workout pace column (none stores work-rep-only pace), it derives avg
   work pace the same way the receipt's "AVG WORK" stat does: the mean of
   non-recovery `parsed_structure.blocks` paces — so the strip is
   apples-to-apples. Sessions with no parsed structure are skipped. The
   `VS RECENT <TYPE>` section (`comparisonSection` + `RRComparison` chart)
   renders after SPLITS whenever ≥2 comparable prior sessions exist, with the
   current session as the highlighted coral point and a dashed recent-average
   reference. Shows nothing (no empty state) when there's no history yet.
   *If `parsed_structure` coverage is thin in prod, the strip will often be
   hidden — a future fallback could read `training_logs.workout_pace_per_mile`
   for overall pace, but that mixes in warmup/cooldown so it's intentionally
   not used here.*

2. **Heat-adjust** depends on `running_workout_laps.heat_adjusted_pace_sec_per_mile`
   being populated (same field the current chart's heat toggle reads). Where
   it's null the bar/split just shows the raw pace. The chip auto-disables when
   no rep carries temp/dew.

## Notes

- Strava run cadence arrives per-leg; the view doubles it to SPM when the
  average looks halved (`< 120`). Adjust in `sCad` if your ingestion already
  doubles.
- Rep windows in the stream are derived by accumulating lap
  `moving_time_seconds` in order — exact when laps are contiguous (they are for
  Strava). If a source has gaps, windows drift; not fatal (only shading).
