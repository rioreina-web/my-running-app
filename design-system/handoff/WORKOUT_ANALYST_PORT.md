# Workout Detail — Analyst Port (Direction B)

Swift port of the **B · Analyst** direction from `Workout Detail Rebrand.html`.
**12 distinct charts** in editorial chrome. Two files:

- `swift/DripWorkoutPrimitives.swift` — reusable chart kit. All hand-drawn
  with `Path` so the editorial look (very thin zone separators, dashed
  avg, one coral) survives — `Charts` would impose its own grid
  treatments. Includes:
    - `DripHRZoneChart` — HR over time, faint zone bands, dashed avg
    - `DripPaceOverTimeChart` — pace over time, inverted Y, neg-split shading
    - `DripCadenceChart` — cadence + avg
    - `DripElevationProfile` — thin shaded strip
    - `DripHRPaceScatter` — efficiency plot with regression line
    - `DripHRDriftChart` — 1st vs 2nd half pace+HR bars + drift %
    - `DripHRRecoveryArc` — post-finish HR curve + big −BPM/60s readout
    - `DripMileSparklines` — small-multiples grid, one HR sparkline per mile
    - `DripTimeInZoneRow` — single histogram row
    - `DripSplitRow` — splits table row
    - `DripComparisonRow` — this-vs-4w-avg row
    - `DripHeroStatBlock` — big-number cell
    - `DripHRZone` / `DripPaceZone` — descriptors with defaults
- `swift/WorkoutAnalystView.swift` — composes all 12 into the screen.

Also assumes `DripEditorialPrimitives.swift` (from the Log Details port)
is already in the project — it provides `DripPlateStrip`, `DripHairline`,
`DripEyebrow`.

## Where this drops in

It's a peer to `VitalWorkoutDetailView` / `WorkoutAnalysisView`. Wire it
into the same call sites that present those today — `HistoryDetailSheet`
opens `WorkoutAnalysisView` for HK/Strava workouts and
`VitalWorkoutDetailView` for legacy Vital. Add a third arm for the
rebrand, or swap one of them entirely once you've validated.

## What you'll need to wire in `loadStream()`

The stub `loadStream()` in `WorkoutAnalystView` is the only piece of
real data plumbing left. The existing app already has all of it — copy
the call path from `VitalWorkoutDetailView.fetchStream()`:

```swift
private func loadStream() async {
    let vitalManager = VitalManager.shared
    let stream = await vitalManager.fetchWorkoutStream(workoutId: workout.vitalWorkoutId)
    let mileSplits = vitalManager.calculateSplits(from: stream)
    let hr = stream?.heartRateSeries.map { $0.bpm } ?? []
    let elev = stream?.elevationSeries ?? []

    // Bucket HR into zones once
    var zs: [String: TimeInterval] = [:]
    let zones = self.zones
    let dtPerSample = workout.durationMinutes * 60 / Double(max(hr.count, 1))
    for bpm in hr {
        if let z = zones.first(where: { Int(bpm) >= $0.low && Int(bpm) < $0.high }) {
            zs[z.id, default: 0] += dtPerSample
        }
    }

    await MainActor.run {
        self.hrSamples = hr
        self.elevationSamples = elev
        self.splits = mileSplits
        self.zoneSeconds = zs
    }
}
```

For HK / Strava sources, swap `VitalManager.shared.fetchWorkoutStream`
for the equivalent `HealthKitManager` path used by
`WorkoutAnalysisView`.

## HR zones

`DripHRZone.defaultZones(maxHR: 185)` uses textbook %HRmax thresholds
(67/75/82/89). In production, read the athlete's zones from
`PaceZonesEngine` / `AthletePaceProfile` so the bands match what the
user sees on the Coach screen.

## Splits HR column

The current `MileSplit` struct doesn't carry HR. To populate the `HR`
column on the splits table, either:
- Pre-compute average HR per mile from the HR stream (cheap — index
  by elapsedTime), or
- Extend `MileSplit` with `avgHeartRate: Int?` and have
  `VitalManager.calculateSplits` fill it.

Until that's wired, `hr: nil` renders as "—" and the column degrades
gracefully.

## Route block

Today this is a placeholder hairline well. Drop the existing
`RouteMapCard` / `MKMapView` snapshot in its place — wrap it in the
hairline `Rectangle()` overlay so the Apple Maps chrome (the "Maps"
attribution, the I-35 freeway shield, etc.) sits inside the editorial
frame instead of bleeding to the edges. Consider a desaturation pass
on the snapshot for brand fidelity.

## Why this lift was worth it

The chart kit is reusable. The same `DripHRZoneChart`,
`DripTimeInZoneRow`, and `DripSplitRow` slot into the Fitness Predictor
trend card and the Trends tab without changes. The next data-viz port
should be 50 lines, not 500.
