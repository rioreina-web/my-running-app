# Key pace — session level, expandable, tappable · apply notes

*Written 2026-08-09. **Not applied** — this is the spec.*
*Prototype: `Post Run Drip Design System/key-pace-expand-prototype.html` (open it
before reading this — the three phone panes are the spec).*
*Follows the repo's `APPLY-NOTES.md` additive-new-files convention.*

Card 02 of the Charts tab ("The Instruments") stops being a weekly average and
becomes a session-level chart with a target behind it and a workout on the other
side of a tap.

**No backend work. No deploy. No migration. No new fetch.** Every number already
arrives on the `trends-timeline` payload `TrendsService` loads today — the card
is currently reading the wrong field off it.

---

## 1 · The diagnosis

`InstrumentKeyPaceCard` (`InstrumentsCardsTraining.swift:134`) plots
`InstrumentsData.keyPaces(service.weeks)`, which is
`TrendsWeek.keyPaceSec` — *"pace of the week's key quality session"*, one Int per
week. Four things follow from that single choice, and they are the four
complaints:

| # | Symptom | Cause |
|---|---|---|
| 1 | Fastest week 4:32, slowest 8:02, on one line | A week's number can be a 400m rep session or a marathon-pace long run. The card averages across quantities the model itself says are not comparable (`KeySession.kind`, `TrendsModels.swift`: *"Their paces are NOT comparable … never plots them on one scale"*). |
| 2 | "Not enough data to support a chart" | 26 weeks of history collapse to ~24 plottable points, and weeks with no quality work drop out entirely (`keyPaces` `compactMap`s them away) without saying so. The underlying `keySessions` array has 39 rows over the same window. |
| 3 | Can't scrub, can't tell which session a point is | The card draws a `Path` and some `Circle`s. There is no hit layer, no crosshair, no readout, no identity — `TrendsWeek` carries no `training_log_id`, so a point *cannot* know which run it was. |
| 4 | No pace ranges, no threshold window | The card knows nothing about `PaceSpectrum`, `BandSettings`, or the weekly race-pace ladder, though all three already ship and Trends section 04 already draws them. |

**The fix for all four is the same fix:** read `service.keySessions`
(`[KeySession]`) instead of `service.weeks`, because that array already carries
`id` (the `training_log_id`), `zone`, `workPaceSec`, `workPaceAdjSec`,
`workHrAvg`, `structure`, `kind` and `heatCategory` per session.

---

## 2 · The invariants this must not break

Load-bearing in `CLAUDE.md` and in the existing file headers. Everything below is
shaped around them.

| Invariant | How it survives |
|---|---|
| **No mock data in the Instruments surface** (`InstrumentsCardKit.swift` header) | Every figure still derives from `TrendsService`. New derivations go in `InstrumentsData` next to the existing ones. Empty series still route to `InstrumentEmpty`. |
| **No em-dashes as empty-state placeholders** (hard rule #8) | A zone with no sessions renders `EmptyStateView`; a trend with fewer than three graded points renders the words "NOT YET", never a dash. The stat row omits an item rather than filling it. |
| **One band** (`TrendsBandSettings.swift:180`) | The band drawn behind the dots comes from `BandSettingsStore.shared`. The detail's controls are `TrendsThresholdControls`, unchanged, writing to that same store. Nothing new persists. Move the slow edge here and Trends section 04 moves too. |
| **One renderer** (`TrendsV2View.swift:36`) | Card and detail render the same `KeyPaceChart` view at two heights (140pt / 250pt). If a change below needs a second implementation, it's the wrong change. |
| **Trends ships ONE time control** (`TrendsSignalModels.swift:12`) | The detail's `TrendsWindowPicker` binds to the *same* `@State window` the host owns, not a copy. |
| **Blue is pace and only pace** (three-palette rule) | Zone colour comes from `PaceSpectrum` stops. Grade is encoded by *fill*, not hue: filled / hollow / dotted-ring. Heat ticks are `textTertiary` hairlines. Coral appears exactly once per surface, on the latest session. |
| **Observation, never prescription** | Nothing grades a number or suggests what to run next. The note states what happened. |

---

## 3 · The four encodings

### 3a · One dot per session, coloured by zone

x = the session's real date (not sample index — sessions are not evenly spaced,
and `ThresholdRead.dayNumber` already establishes this convention).
y = `workPaceAdjSec` (heat-neutral), faster plotted higher.
fill = `PaceSpectrum` colour for `KeySession.zone`.

`zone` is the shared classifier's token: `mile | 3k | 5k | 10k | hmp | mp`.
**Note the existing wart:** the backend classifier folds LT/threshold into `hmp`
(documented at `TrendsModels.swift`, `KeySession.zone`). The chip row must
therefore show six zones, not seven, until that classifier changes — the
prototype shows seven because it models the post-fix taxonomy. *Ship six and
label them honestly; do not invent an LT bucket in the client.*

### 3b · Long runs are a different quantity

`KeySession.kind == "long_run"` renders as an **open diamond**, never a dot, and
is **off by default** behind a `LONG RUNS` toggle. When hidden, the count is
reported in the NOT COUNTED panel — a filter that silently deletes running is a
filter that lies (`TrendsThresholdModels.swift` header).

### 3c · Grade by fill

Reuse `ThresholdGrade`'s rule, applied to the session's own work-bout HR:

```
filled dot   → workHrAvg != nil && workHrAvg >= settings.hrFloor   (work)
hollow dot   → workHrAvg != nil && workHrAvg <  settings.hrFloor   (cruise)
dotted ring  → workHrAvg == nil                                    (unclassed)
```

**Deliberate widening, call it out in review.** `ThresholdGrade` currently grades
*in-band minutes*; here it grades the *session's work bouts*, so out-of-band
sessions can carry a grade too. The two agree for in-band sessions. If that
widening is unwanted, the alternative is to grade only in-band dots and leave the
rest plain — but then the slow-edge leak stops being visible on this chart, which
was the point of drawing it.

### 3d · The band and the stepped anchor

- **Shaded window** = `settings.edges(anchorSec:)` at the *end* of the window,
  filled at 11% of the anchor's zone colour, edges dashed. Dash more heavily when
  `ThresholdRead.lowConfidence`.
- **Stepped anchor line** = one horizontal segment per week at that week's
  `BandLadder` value for the anchor. Steps, not a smooth line: the ladder is
  weekly and drawing it as a curve would claim resolution the data has not got.
  `ThresholdPoint.anchorSec` already establishes that each point knows the anchor
  it was judged against.
- **Heat tick** = a hairline from `workPaceAdjSec` (the dot) to `workPaceSec`
  (the watch), capped with a 5pt serif. Drawn only when the two differ. Behind a
  `HEAT CORRECTION` toggle, on by default.
- **Field test** = a small filled triangle above the dot, matching the existing
  `InstrumentTriangle` convention.

---

## 4 · The honest-trend rules

These are the reason the surface is trustworthy, and they are the part most
likely to get dropped in implementation. Each maps to a guard already in the
codebase.

1. **No trend across zones.** With `ALL` selected, no line is fitted and the
   middle stat reports the *zone count*, not a slope. A least-squares fit through
   5K reps and MP long runs measures the training schedule, not fitness.
2. **No trend under three graded points.** Mirrors
   `ThresholdRead.trendSecPerMonth`'s `count >= 3` guard, verbatim, with the same
   reason surfaced in prose: *two points are a line through anything.*
3. **Trend over graded work only.** Cruise and unclassed dots are drawn but
   excluded from the fit — same rule and same rationale as
   `trendSecPerMonth`.
4. **Slope in sec/mi per 30 days**, over real elapsed days, negative = faster.
5. **The headline names its zone.** `"LT work: 5:38 to 5:21."` — never a
   cross-zone range. Pick the most-represented zone in the window; the collapsed
   stat caption says which zone it is.

---

## 5 · New files

Additive. Nothing in `InstrumentsCardsTraining.swift` moves except the body of
`InstrumentKeyPaceCard`.

```
RunningLog/Trends/
  KeyPaceModels.swift        // KeyPacePoint, KeyPaceRead, KeyPaceBuilder  (pure)
  KeyPaceChart.swift         // the one renderer, height-parameterised
  KeyPaceDetailView.swift    // full-screen: window picker, chart, controls, list
RunningLogTests/
  KeyPaceTests.swift         // the §4 rules, testable without a renderer
```

### `KeyPaceModels.swift`

```swift
struct KeyPacePoint: Identifiable, Equatable {
    let id: String            // training_log_id — a tap opens this
    let date: String          // "2026-08-05"
    let dateLabel: String     // "Aug 5"
    let zone: String          // mile | 3k | 5k | 10k | hmp | mp
    let adjSec: Int           // KeySession.workPaceAdjSec ?? workPaceSec
    let rawSec: Int           // KeySession.workPaceSec
    let correctionSec: Int    // rawSec - adjSec, 0 when no weather
    let hrAvg: Int?           // KeySession.workHrAvg
    let structure: String?    // "5K 5×1km · 6.0 mi"
    let isLongRun: Bool       // kind == "long_run"
    let zoneAnchorSec: Int    // that week's ladder value for THIS point's zone
    let grade: ThresholdGrade
}

struct KeyPaceRead {
    let points: [KeyPacePoint]
    let settings: BandSettings
    let anchorSec: Int, fastSec: Int, slowSec: Int
    let lowConfidence: Bool
    let hiddenLongRuns: Int          // reported, never silently dropped
    let zonesPresent: [String]

    func filtered(zone: String?) -> [KeyPacePoint]
    func trendSecPerMonth(zone: String) -> Double?   // nil for ALL, nil under 3
}
```

`KeyPaceBuilder.read(sessions:ladder:settings:window:)` is pure — no SwiftUI, no
network — so §4 is unit-testable. Same shape as `ThresholdBuilder`.

### `KeyPaceChart.swift`

One `View`, `height: CGFloat` parameter, `onSelect: (KeyPacePoint) -> Void`.
Card passes 140, detail passes 250. Draw order: band → stepped anchor →
gridlines → trend → heat ticks → dots → field-test triangles → crosshair → hit
layer.

**Interaction.** A `DragGesture(minimumDistance: 0)` over the plot updates
`selected` to the nearest point by x; the persistent **readout row** below the
chart shows it and is itself the tap target (`onSelect`). Tapping a dot selects
and opens in one gesture. The readout row, not a floating tooltip, is the primary
affordance — a tooltip vanishes on touch-up, which is useless on a phone and
invisible to VoiceOver.

### `KeyPaceDetailView.swift`

`fullScreenCover`, drawn grabber (matching `TrendsThresholdDetailView`), sticky
`TrendsWindowPicker` bound to the host's window, then: mode segment
(`PACE / MI` · `SECONDS VS TARGET`), zone chips with counts, the two toggles,
`KeyPaceChart(height: 250)`, readout, legend, stat row, note, a collapsed
`TrendsThresholdControls` accordion, the session list, and the NOT COUNTED panel.

`SECONDS VS TARGET` plots `adjSec - zoneAnchorSec`, which puts every zone on one
scale and makes "am I on target" the y-axis. The band is hidden in this mode
while `ALL` is selected, with a caption saying so — a band is anchor-relative and
there is no single anchor across zones.

---

## 6 · Navigation

```
InstrumentsTabView
  └─ InstrumentKeyPaceCard            tap card → expand (unchanged)
       ├─ readout row / dot tap       → HistoryDetailPager (sheet)
       └─ ⤢ EXPAND                    → KeyPaceDetailView (fullScreenCover)
            ├─ dot / readout / list   → HistoryDetailPager (sheet)
            └─ Done                   → back, selection preserved
```

`HistoryDetailPager(entries:initial:onUpdate:)` is the existing destination —
`TrendsThresholdDetailView.swift:100` already presents it this way. Copy that
call site. Resolve `entries` from the `training_log_id` exactly as it does;
`HistoryDetailViewModel.swift:586` documents the id rule and the `DayDetailSheet`
divergence — read it before wiring, it is a known trap.

**Nothing new is built in pane 3 of the prototype.** It is a sketch of the screen
that already exists, included so the loop is visible end to end.

---

## 7 · States

| State | Behaviour |
|---|---|
| No key sessions at all | `InstrumentEmpty`: "Log a quality session and it appears here as a dot you can open." Card collapses to headline + empty. |
| Sessions but none in the selected zone | `EmptyStateView` in the list, chart shows the axis and the band with the words NO SESSIONS IN THIS ZONE AND WINDOW. Chip stays visible with count 0, dimmed and unpressable. |
| Fewer than 3 graded points | Dots drawn, no trend line, note explains why, stat reads NOT YET. |
| No HR on any session | All dots dotted-ring. Grade legend still shown; the note says the floor could not be applied. |
| `lowConfidence` ladder | Band edges dash more heavily; the accordion summary says the prediction behind the band is low-confidence. |
| Long runs hidden | Count and reason in NOT COUNTED. |
| Loading / error | Unchanged — the host `InstrumentsTabView` already handles both. |

---

## 8 · Accessibility

- Zone is **never** carried by colour alone: every dot's accessibility label
  names it, the chips carry text, and the readout row spells it out. Same rule
  the mood cards already follow.
- Grade is fill, not hue, so it survives greyscale and colour-blind rendering.
- Each dot is an `.accessibilityElement` with label
  `"Aug 5, LT, 5 minutes 20 per mile, work, 2 by 25 minutes off 3 minutes"` and
  `.accessibilityAddTraits(.isButton)`.
- The chart as a whole supports `.accessibilityChartDescriptor` so VoiceOver can
  play the series.
- Touch targets: chips and the readout row at 44pt minimum. Dots are 8–9pt
  visually but the drag layer spans the full plot, so no dot is a 9pt target.

---

## 9 · Explicitly out of scope

- **No classifier change.** LT stays folded into HMP until the backend splits it.
  Ship six chips.
- **No new persistence.** Zone selection and the two toggles are view state, not
  settings. They reset when the tab does. Only `BandSettingsStore.shared`
  persists, and it already exists.
- **No second time control.** If the detail needs a range the host doesn't have,
  stop.
- **No coach note.** This card carries `InstrumentNote` ("WHAT THE DATA SAYS")
  only — derived prose built from numbers already on screen, never authored copy.
- **`TrendsWeek.keyPaceSec` is not deleted.** Trends v2 still reads it. This card
  stops reading it; the field stays.

---

## 10 · Test list (`KeyPaceTests.swift`)

1. `trend(zone: .all)` returns nil regardless of point count.
2. `trend` returns nil with two graded points, non-nil with three.
3. Cruise and unclassed points are excluded from the fit; adding a cruise point
   far off-trend does not move the slope.
4. `grade` is `.unclassed` when `workHrAvg == nil`, never `.cruise`.
5. `hrFloor == 0` grades every HR-bearing session as work (the no-strap athlete).
6. Long runs excluded by default; `hiddenLongRuns` equals the number excluded.
7. `correctionSec` is never negative; a session with no weather has 0 and draws
   no tick.
8. A zone with zero sessions yields an empty `filtered` array and a live chip
   with count 0 — not a missing chip.
9. `zoneAnchorSec` for a point uses **that point's week**, not the window's last
   week.
10. Band membership matches `BandSettings.contains(paceSec:anchorSec:)` exactly —
    the chart must not reimplement the edge test.

---

## 11 · Sequencing

Three commits, each shippable on its own.

1. **Models + tests.** `KeyPaceModels.swift` + `KeyPaceTests.swift`. Nothing
   renders yet. Green before anything is drawn.
2. **The card.** `KeyPaceChart.swift`; `InstrumentKeyPaceCard` swaps its data
   source and body. Zone chips, band, grade, heat ticks, readout row, tap → sheet.
   The card is better on its own even without step 3.
3. **The detail.** `KeyPaceDetailView.swift` + the `⤢ EXPAND` affordance. Mode
   toggle, controls accordion, session list, NOT COUNTED panel.

Step 2 is the one that answers the original complaint. Step 3 is the one that
makes it worth expanding.
