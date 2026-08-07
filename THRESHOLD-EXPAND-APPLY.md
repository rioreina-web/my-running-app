# Threshold pace — expandable detail + a sticky time control · apply notes

*Placed 2026-08-07. Follows the repo's `APPLY-NOTES.md` additive-new-files convention.*
*Prototype: `threshold-expand-prototype.html` (open it before reading this — the two
phone panes are the spec).*

Two changes to the Trends tab, plus the small refactors that let them share code with
what already ships.

1. **The one time control pins.** `TrendsWindowPicker` already offers 30d / 3mo / 6mo /
   1yr / custom and already drives every section. It just scrolls away above four long
   sections, so by the time you reach section 04 the range is a scroll-to-top away. It
   now pins to the top of the scroll, shrinks slightly once stuck, and carries a meta
   line naming the dates it resolved to. Presets relabel to **1 MO / 3 MO / 6 MO / 1 YR
   / CUSTOM**.
2. **Section 04 expands full-screen.** The inline card is unchanged — it is the glance.
   An `⤢ EXPAND` button on the section head (and the whole `ADJUST ›` line) opens a
   full-screen detail: the same chart at 250pt instead of 168, the four band controls
   tabbed instead of stacked, and every session in the window listed and tappable.

**No backend work. No deploy. No migration. No new fetch.** Every number already comes
off the `trends-timeline` payload `TrendsService` loads today.

---

## 0 · The three invariants this must not break

These are load-bearing in `CLAUDE.md` and in the file headers. Everything below is
shaped around them.

| Invariant | How it survives |
|---|---|
| **Trends ships ONE time control** (`TrendsSignalModels.swift:12`) | The detail's picker is bound to `TrendsV2View`'s *same* `@State window`, not a copy. Change the range in the detail and the page behind it is already changed. There is no second window that can disagree. |
| **One renderer for the threshold chart** (`TrendsV2View.swift:36`) | The detail renders `TrendsThresholdView`, the same view the inline card and the Signal Lab's section 02 render. It is handed a taller frame, not a second implementation. |
| **One band** (`TrendsBandSettings.swift:180`) | The detail's controls are `TrendsThresholdControls` writing to the same `BandSettingsStore.shared`. Nothing new persists. |

If a change below would require duplicating the chart, the settings, or the window —
stop, it's the wrong change.

---

## 1 · New files (additive — safe)

| File | What it is |
|---|---|
| `Trends/TrendsThresholdDetailView.swift` | The full-screen detail. Owns no data: takes the already-built `ThresholdRead` and bindings to the window and the settings. Contains `TrendsThresholdSessionList` (private) — the tappable session rows. |

That's the only new file. Everything else is a small edit to something that exists.

---

## 2 · Changed files

### 2.1 `Trends/TrendsSignalModels.swift` — labels only

`TrendsWindow.thirtyDays` keeps its case name and its `days: 30`. Only the two display
strings change, so no call site moves and no behaviour changes:

```swift
case .thirtyDays: "1 MO"          // was "30 D"
case .thirtyDays: "1-Month View"  // plateTitle, was "30-Day View"
```

Rationale: "30 D" sits in a row with "3 MO / 6 MO / 1 YR" and is the only member using a
different unit, which makes the row read as four options and one oddity. `1 MO` is the
same fact in the row's own unit.

Add one computed property, used by the picker's new meta line:

```swift
/// "JUL 9 – AUG 7" for the window ending on `lastDay`. The picker states the
/// dates it RESOLVED to, so a preset and a custom range are read the same way.
func rangeLabel(endingAt lastDay: Date) -> String
```

### 2.2 `Trends/TrendsSignalSections.swift` — `TrendsWindowPicker` grows two options

Both default to today's behaviour, so `SignalLabView`'s call site compiles untouched.

```swift
struct TrendsWindowPicker: View {
    @Binding var window: TrendsWindow
    @Binding var customFrom: Date
    @Binding var customTo: Date

    /// Compact treatment for when the bar is pinned rather than in flow:
    /// 27pt pills instead of 32, tighter padding, a hairline divider and a
    /// short shadow so content reads as passing UNDER it.
    var isPinned: Bool = false

    /// "JUL 9 – AUG 7" and "24 runs". Nil in the Lab, which has its own lede.
    var meta: (range: String, count: String)? = nil
}
```

Implementation notes:

- Animate `isPinned` with `.animation(.easeInOut(duration: 0.18), value: isPinned)` on the
  pill frame — a hard snap at the scroll threshold reads as a glitch.
- The divider is `Color.drip.divider` at 1pt, opacity driven by `isPinned` so it fades in.
- No new colour. The bar's fill is `Color.drip.background`, matching the page, which is
  what makes the pinning read as the page's own edge rather than a floating widget.

### 2.3 `Trends/TrendsThresholdView.swift` — one constant becomes a parameter

```swift
- private let chartHeight: CGFloat = 168
+ /// 168 inline; the full-screen detail passes 250. Same renderer, more room —
+ /// a second chart is how the two surfaces start disagreeing.
+ var chartHeight: CGFloat = 168
```

`gutter`, `axisHeight` and the whole `Layout` / `draw(_:layout:)` path are untouched —
they already read `chartHeight`. One further tweak inside `draw`: the mark radius
currently maxes at a fixed size; scale its upper bound with `chartHeight / 168` so the
dots grow with the chart instead of scattering as pinpricks across 250pt.

### 2.4 `Trends/TrendsThresholdControls.swift` — a layout mode, no new controls

The four blocks are already separate computed properties (`anchorBlock`, `edgeBlock`,
`minimumBlock`, `floorBlock`). Only the assembly in `body` changes.

```swift
enum Layout {
    /// Today's behaviour, unchanged: summary line + ADJUST, four blocks stacked.
    case inline
    /// The detail's: a four-segment strip, each segment showing its own current
    /// value, and only the selected block below it.
    case tabbed
}
var layout: Layout = .inline
```

**Why tabs.** Stacked, the four blocks are ~700pt of scroll — the athlete is scrolling
past three settings to reach the fourth, and can never see the chart and the control she
is moving at the same time. Tabbed, they are one screen under the chart.

**The tab strip is also the read.** Each segment carries its current value underneath its
name — `ANCHOR / HMP`, `BAND / ±5%`, `MINIMUM / 8/5`, `FLOOR / 160`. That is the whole of
`summaryLine` distributed across four labels, so nothing is hidden by tabbing: the
complete settings read is visible without opening anything, which is the property the
collapsed inline header has and must not lose.

In `.tabbed`, `header` (the summary + ADJUST button) does not render — the strip replaces it.

### 2.5 `Trends/TrendsV2View.swift` — pin the bar, add the door

**Pin.** Move `TrendsWindowPicker` out of the scrolling `VStack` and into a
`.safeAreaInset(edge: .top)` on the `ScrollView`. Track the offset with
`.onScrollGeometryChange(for: Bool.self)`:

```swift
@State private var pickerIsPinned = false

.onScrollGeometryChange(for: Bool.self) { geo in
    geo.contentOffset.y > 8
} action: { _, pinned in
    pickerIsPinned = pinned
}
.safeAreaInset(edge: .top) {
    TrendsWindowPicker(
        window: $window, customFrom: $customFrom, customTo: $customTo,
        isPinned: pickerIsPinned,
        meta: windowMeta
    )
}
```

The `header` (eyebrow + plate title) stays inside the scroll and scrolls away as it does
today. Only the control pins — a pinned title is chrome, a pinned control is a control.

`windowMeta` is derived from the already-built `bucketSet`, not recomputed:
`(range: window.rangeLabel(endingAt: set.days.last?.date ?? .now), count: "\(set.runCount) runs")`.

**Door.** `section(eyebrow:number:sub:anchor:)` gains one optional parameter:

```swift
private func section<Content: View>(
    eyebrow: String, number: String, sub: String, anchor: String,
    onExpand: (() -> Void)? = nil,        // ← new
    @ViewBuilder content: () -> Content
) -> some View
```

When non-nil it renders a chevron-out capsule between the explainer chevron and the
section number. Sections 01–03 pass nothing and are visually identical to today. Only
`thresholdSection` passes `onExpand: { thresholdExpanded = true }`.

The existing `ADJUST` line in `thresholdBody` becomes `Adjust ›` and opens the detail on
the Band tab rather than expanding in place. This is the change most worth reviewing on a
device: it removes the inline expanded controls entirely.

**Present.**

```swift
@State private var thresholdExpanded = false

.fullScreenCover(isPresented: $thresholdExpanded) {
    TrendsThresholdDetailView(
        read: thresholdRead,
        settings: $bandSettings.settings,
        window: $window,                       // ← the SAME window
        customFrom: $customFrom, customTo: $customTo,
        ladder: service.bandLaps?.latestLadder,
        bandIsAdjustable: bandIsAdjustable,
        resolveDay: { iso, focus in await service.resolveDay(dayISO: iso, focusLogId: focus) }
    )
}
```

`fullScreenCover` rather than `sheet`: the controls plus a 250pt chart plus a session list
do not fit a detent, and a half-height sheet over a chart the athlete is trying to read is
the worst of both.

### 2.6 `Analysis/SignalLabView.swift` — optional, same treatment

The Lab's picker has the same problem behind a longer lede. Same `.safeAreaInset` move.
Not required for this change to land; do it in the same pass or not at all, but don't
leave the two surfaces pinning differently.

---

## 3 · `TrendsThresholdDetailView` — the shape

```
┌──────────────────────────────────────┐
│ ⎯⎯  (grabber)                        │  fixed
│ SECTION 04                    DONE   │  fixed
│ Threshold pace                       │  fixed
│ [1 MO][3 MO][6 MO][1 YR][CUSTOM]     │  fixed — the SAME window binding
│ JUL 9 – AUG 7            HMP ±5%     │  fixed
├──────────────────────────────────────┤
│ ┌──────────────────────────────────┐ │  ← scrolls
│ │ IN BAND  SESSIONS  BEST  AVG HR  │ │
│ │ readout line                     │ │
│ │ ▓▓▓ chart, 250pt ▓▓▓             │ │  TrendsThresholdView(chartHeight: 250)
│ │ legend                           │ │
│ └──────────────────────────────────┘ │
│  ANCHOR   BAND   MINIMUM   FLOOR     │  TrendsThresholdControls(layout: .tabbed)
│   HMP     ±5%      8/5      160      │
│  ───────                             │
│  [ the selected block ]              │
│                                      │
│  SESSIONS IN THIS WINDOW  23 · 8 out │
│  JUL 21  5:23  24 min · 163 bpm WORK │  ← tap opens the workout
│  JUL 14  5:41  18 min · 149 bpm CRUISE│
└──────────────────────────────────────┘
```

The range control is **fixed, not scrolling** — the reason the detail exists is to change
the band and the range while watching the chart, and a range control you have to scroll
back to is the problem this change is fixing.

**The session list is new content, and it is the honest half of the chart.** The chart can
only place a session; the list can name why it graded the way it did. Rows carry date,
heat-neutral pace, minutes, longest block, avg HR, and a grade pill (`WORK` / `CRUISE` /
`NO HR`). Sessions the minimums held out are **counted in the header** (`23 counted · 8
held out`) — consistent with `ThresholdRead.excludedSessions`, which exists precisely
because a filter that silently deletes running is a filter that lies.

**Tapping a row** opens `HistoryDetailPager` from a `.sheet(item:)` on the detail view
itself, not by dismissing back to the tab. Hence the `resolveDay` closure rather than
handing the whole `TrendsService` down — the detail gets the one capability it needs and
cannot fetch anything else.

---

## 4 · Empty and degraded states

| State | What renders |
|---|---|
| `read == nil` or `read.isEmpty`, band adjustable | The existing `emptyBandTitle(_:)` copy, in the chart's slot. The controls stay — the way out is directly below. The session list renders its own empty line naming the band that found nothing. |
| `bandIsAdjustable == false` (backend predates `band_laps`) | No `EXPAND` button on the section head at all. There is nothing to adjust and no list worth a full screen; the fallback HM ±5% card is the whole story. |
| Custom range with no data | Existing "Nothing in this range" empty state on the tab. In the detail, the same copy plus the `Back to 1 month` CTA, which writes the shared window binding. |
| Custom range where `to < from` | Already prevented — the `DatePicker` is bounded `in: customFrom...`. |

---

## 5 · Accessibility

- The `EXPAND` button: `.accessibilityLabel("Expand threshold pace")`, hint `"Opens the full
  detail, where the band and the date range can be adjusted"`.
- The control tab strip: one `.accessibilityElement` per segment, `.isSelected` on the
  current one, value = that segment's current setting. The value under each tab label is
  decorative for VoiceOver (it's already in the accessibility value) — mark it
  `.accessibilityHidden(true)` so it isn't read twice.
- The pinned picker keeps its existing per-pill labels. Add
  `.accessibilityAddTraits(.isHeader)` to nothing here — it's a control, not a heading.
- Session rows: one element each, label = `"Jul 21, 5:23 per mile, 24 minutes in band,
  163 bpm, graded work"`, hint `"Opens this workout"`.
- Every new control clears 44×44 except the tab segments, which are 44 tall by design and
  full-width-quarter wide — acceptable, and the same shape as the existing anchor chips.

---

## 6 · Tests

`RunningLogTests/TrendsThresholdTests.swift` needs no changes — `ThresholdBuilder`,
`BandSettings` and `ThresholdRead` are untouched. That is the point of the split: this is
entirely a presentation change.

Add to the same file:

1. `testWindowLabelsAreMonthUnits` — `TrendsWindow.thirtyDays.label == "1 MO"` and
   `.plateTitle == "1-Month View"`. Cheap, but it's the one string change that could be
   silently reverted by a merge.
2. `testRangeLabelResolvesPresetToDates` — a 30-day window ending 2026-08-07 labels
   `"JUL 9 – AUG 7"`, and a custom window with the same bounds labels identically. The
   picker must not describe a preset and a custom range differently when they are the
   same range.
3. `testDetailAndInlineShareOneRead` — build one `ThresholdRead` and assert the detail's
   stat figures equal the inline card's. Guards the invariant that matters most: two
   surfaces, one arithmetic.

Previews to add:

- `TrendsThresholdDetailView` at each of the four presets.
- The detail with `read == nil` and `bandIsAdjustable == true` (the band-set-to-catch-
  nothing state).
- `TrendsThresholdControls(layout: .tabbed)` in the existing `ThresholdControlsHarness`.
- `TrendsWindowPicker(isPinned: true, meta: ...)`.

---

## 7 · Order of work

Each step compiles and ships on its own. Stop after any of them.

1. **Labels.** `TrendsWindow` display strings + `rangeLabel(endingAt:)` + its test.
   Ten minutes, zero risk.
2. **Pin.** `TrendsWindowPicker` gains `isPinned` / `meta`; `TrendsV2View` moves it to
   `.safeAreaInset`. This alone answers "adjust the date range easily" — ship it and live
   with it for a few days before step 4.
3. **Chart height.** `TrendsThresholdView.chartHeight` becomes a parameter. Nothing calls
   it with a new value yet; verify the inline card is pixel-identical.
4. **Tabbed controls.** `TrendsThresholdControls.layout`. Verify `.inline` is
   pixel-identical to today.
5. **The detail.** New file, the `EXPAND` door, the `fullScreenCover`, the session list.
6. **Lab parity.** `SignalLabView`'s picker.

---

## 8 · What this deliberately does not do

- **No per-section ranges.** Section 04 does not get its own window. Two ranges on one
  screen is how a page starts telling two stories about the same block.
- **No expand on sections 01–03.** The `onExpand:` parameter is built generic so they
  *can* have one later, but a door that opens onto the same content at a different size
  is chrome. Section 04 earns it because it has controls and a list that don't fit inline.
- **No new persisted state.** Which control tab was last open is view state, forgotten on
  dismiss — same reasoning as `revealedExplainers` in `TrendsV2View`. The athlete asked
  once, not forever.
- **No change to what counts as threshold work.** Not one line of `ThresholdBuilder`,
  `BandSettings` or `TrendsThresholdModels` is touched. If a number moves after this
  lands, something is wrong.
