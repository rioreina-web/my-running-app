# Pace color system — decision + to-dos (2026-07-03)

## The decision

**Pace is now a single-hue blue depth ramp: pale sky `#93B9D6` (Easy) →
navy `#0E1D4E` (Mile).** One hue, ten depths — pace reads as intensity,
not a rainbow. This resolves the mood-collision problem found in the
Trends prototype review:

- **Blue = pace** (all charts, zone chips, route traces)
- **Warm traffic-light = mood** (energized green → injured rose, unchanged)
- **Coral = alert** (niggles, out-of-zone workload, brand punctuation)

Three systems, zero shared hues. Source of truth:
`RunningLog/RunningLog/Workouts/PaceSpectrum.swift`.

The 10 stops (Easy → Mile):
`93B9D6 · 74A8CC · 578FC0 · 3F7CB5 · 2F66A8 · 27549B · 20448B · 1A3679 · 142964 · 0E1D4E`
plus `easyText #5E93BE` — legibility-darkened Easy for small text only.

## Shipped today

- `PaceSpectrum.swift`, `IntensityRamp` (TrainingAnalyticsViewModel),
  `PaceZoneScale` (WorkoutReceiptCharts) — all on the blue ramp
- Zone chips (`PaceModels`), race-distance colors (`RaceDistance`),
  route map (`RouteMapView`), Today zone-shift labels (`TodayPlate18`),
  pace markers, `Color.drip.speed` token + `--mood-speed` CSS token
- Volume × Pace ramp strip: zone labels positioned at true warped axis spots
- Mocks synced: `outputs/trends-signal-chart.html`,
  `outputs/trends-pace-signal-prototype-v2.html`, `pace-spectrum-mockup.html`

## To-dos

1. **Build & run in Xcode.** No compile check was possible in this
   session. Eyeball: Volume × Pace (Trends), rep receipt (workout detail),
   splits, route map, Today zone-shift strip, race-distance chips.
2. **Judge the pale Easy end on device.** Base miles now recede by
   design; if the pale bars feel too faint on the warm paper, darken the
   Easy stop one step in `PaceSpectrum.swift` (single-file change —
   `IntensityRamp` and `PaceZoneScale` carry duplicated RGB stops, keep
   all three in sync).
3. **Fix the histogram marker-label collision.** MP and LT header labels
   overlap when the paces are close (seen in the 30-days screenshot:
   "5:45" / "5:30" colliding). Needs a stagger or min-spacing rule in
   the marker layout (`TrainingTabView` / `PaceVolumeSpectrumChart`
   label rows).
4. **Sweep the design-system kit for stale plum/spectrum colors.**
   Still carrying the old palette: `design-system/fitness-predictor.jsx`
   (`PLUM`), `design-system/training-analysis.jsx` (`PLUM`),
   `design-system/ui_kits/ios_app/SettingsSheets.jsx` (interval dot
   `#6B4A8A`), `design-system/preview/colors-coral.html` (speed swatch),
   `design-system/Fitness Predictor.html` + `Training Analysis.html`.
5. **Check the web app for pace-zone coloring.** iOS is fully swept;
   `web/` (coach portal workout builder, pace chart page) was not.
   Any zone colors there should mirror the 10 blue stops.
6. **Neutralize any green "safe zone" bands in-app.** The prototypes'
   ACWR safe band went from green to neutral gray so green stays
   mood-only. Check the iOS workload/ACWR surfaces for the same pattern.
7. **Document the rule.** Add a line to `design-system/README.md` (and
   CLAUDE.md's design section): *blue = pace, warm = mood, coral =
   alert; the three palettes never share hues.* Update
   `colors_and_type.css` if the mood block deserves a matching comment.
8. **Decide: keep `--mood-speed` naming?** The token now holds a pace
   color but lives in the mood block — consider renaming to
   `--pace-fast` (breaking change; touch `DesignSystem.swift` mapping).

## Deferred / parked

- Cool-slate or ink-coral mood scales: rejected — moods stay warm.
- Heat / richer-warm pace ramps: superseded by blue.
- Route-map recovery grey (`PaceZoneScale.recoveryGrey`): still warm
  gray; fine against blue, revisit only if it muddies the map trace.
