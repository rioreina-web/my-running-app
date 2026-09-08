# Sharp End — "Are you getting fitter?" fitness read · apply notes

*Placed 2026-07-26. Follows the repo's additive-new-files + one-tracked-edit convention (see `TRENDS-WEEKLY-MONTHLY-APPLY.md`).*

Adds a plain-language fitness verdict + a Progress-over-time chart **above** the
existing Compare dashboard, in **Trends → GO DEEPER → Fitness → "Compare
sessions"**. The existing head-to-head, scatter and trend tiles are untouched
and still render below. Nothing on the Trends 2 tab changes.

## What it answers

Are you running faster for the same effort than you were at the start of the
block? Stated in one sentence, backed by a chart that shows the trend.

## The method (why it's not just "average pace over time")

Comparing raw pace across a block is confounded twice: a rep session is faster
*and* higher-HR than a marathon-pace run, and summer heat slows pace *and* lifts
HR. So the read fits pace-against-effort **separately** on the early third and
the recent third of the block, then measures the horizontal gap between those
two lines at your **median working effort**. That gap is the number in the
verdict and the arrow on the chart. Verified on a 42-session synthetic block:
+13.5 s/mi with heat-adjusted effort; the sign flips to −14 if effort isn't
heat-adjusted — which is exactly the trap the estimate below avoids.

## Files added (new, additive — safe)

Drop into `RunningLog/RunningLog/Trends/`:

- `SharpEndFitnessRead.swift` — the `FitnessRead` maths, the `FastSession.effortHr`
  extension, and `FitnessReadSection` (the card: headline, verdict, segmented
  map, readout). Self-contained; its own heat/hills state.
- `SharpEndFitnessCharts.swift` — the three Canvas charts: Progress (default),
  Two lines, Every session.

Drop into `RunningLog/RunningLogTests/`:

- `SharpEndFitnessReadTests.swift` — 9 Testing-framework cases over the maths.

If the project uses file-system–synchronized groups (the small `project.pbxproj`
suggests it does), these are picked up automatically on next open. Otherwise add
them to the app / test targets in Xcode once.

## The one tracked-file edit — `CompareDashboardView.swift`

In `body`, insert the section right after `header` (≈ line 39):

```swift
            VStack(alignment: .leading, spacing: 22) {
                header
                FitnessReadSection(sessions: ordered)   // ← add this line
                if ordered.count < 2 {
                    emptyState
```

`ordered` already exists in that view (chronological sessions). That's the whole
integration — one line.

## Behaviour

- **Under ~8 sessions with HR:** shows a "building your baseline" state instead
  of a verdict; the chart still plots what's there. The gain is withheld until
  there's enough to separate a trend from a good day.
- **Sessions with no HR** are dropped from the read (can't be placed on the
  effort axis), matching the existing ScatterPlot.
- **Heat / Hill toggles** are local to this card and mirror the fallback chain in
  `FastSession.pace(heat:hills:)`.

## Follow-up: heat-adjusted heart rate (the one estimate)

`FastSession.effortHr(heat:)` currently estimates the heat penalty on HR from
feels-like temperature (~0.3 bpm/°F above 68°F, capped at 12) because there is no
server-side heat-adjusted HR yet. This is honest but rough. The proper fix is a
`neutral_hr` field from the same backend model that already produces
`neutral_pace_sec`; once it exists, have `effortHr` prefer it and delete the
estimate. Search `TODO(server)` in `SharpEndFitnessRead.swift`.

## Reverting

Delete the three files and remove the one added line. Because it's additive and
the old Compare screen is untouched, revert is clean.
