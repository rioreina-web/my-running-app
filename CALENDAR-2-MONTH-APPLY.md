# Calendar · slice 2 — month grid

*iOS. Depends on slice 1. Read `CALENDAR-BUILD-PLAN.md` first.*

---

## What this gives you

The month grid from `calendar-month-prototype.html` — every cell a bar whose height is that day's
volume, so each week row reads as a seven-bar chart and the month reads as a stack of five. Mood on
the bottom edge, niggles on the left edge, weekly totals as an eighth column.

**This is an upgrade, not a new build.** `TrainingCalendarSection.swift` already renders a per-day
calendar with mileage, a pace chip, a session label and a mood dot, and already taps into
`DayAnalysisSheet`. You are changing how a cell draws and adding a week column.

---

## Paste this to Claude Code

> Read `CALENDAR-2-MONTH-APPLY.md` in the repo root, then `calendar-month-prototype.html` (the month
> view — ignore the Week segment, that is slice 3), then
> `RunningLog/RunningLog/Training/Analytics/TrainingCalendarSection.swift` and
> `TrainingAnalyticsViewModel.swift`.
>
> Build the new cell rendering as described. Follow the repo's additive-new-files convention: put the
> new cell and week-rail views in new files, and make the smallest possible edit to
> `TrainingCalendarSection.swift` to use them. Do not restructure the view model.
>
> Use design tokens from `Color.drip` and the `Drip*` primitives in `App/DripEditorialPrimitives.swift`
> — no hardcoded hex values, `.github/scripts/check_design_tokens.py` runs in CI and will fail you.
>
> Build for iPhone SE width (375 pt) as well as 390. Show me a simulator screenshot of July and of
> May before you call it done.

---

## The encoding

Four channels in one cell, from the prototype. The rule that makes them coexist: **each channel owns
a different part of the cell**, so none of them compete for the same pixels.

| Channel | Where | How |
|---|---|---|
| **Volume** | Bar height, bottom-anchored | Fixed 0–30 km (0–18 mi) scale so months compare. Doubles split into stacked segments with a 1.5 pt gap. |
| **Session type** | Bar fill | Coral = key session, dark warm grey = long run, light warm grey = easy. One coral — intensity is the only thing that gets the accent. |
| **Mood** | 3.5 pt strip, bottom edge, full width | Rest days carry it too. Mood is not a property of a run. |
| **Niggle** | 2.5 pt bar, left edge | Opacity by severity. Left edge, **not** a top-right corner notch — a corner notch sits next to the *next* day's numeral and reads as belonging to it. |

Plus: date numeral top-left, a small coral dot top-right when the day contains a key session, coral
inset ring on today.

**Do not colour the bars by pace zone.** This was tested and rejected — see the "Day bar fill" toggle
in the prototype. Pace is a property of a segment, not of a day, and at bar width the ten-step ramp
collapses into one wash that also destroys the long-run channel. Pace zones belong in the week view
(slice 3) and the day sheet.

---

## The week rail

An eighth grid column, inside the grid so a heavy week and the days that made it sit on one line.
Per week: total, a bar scaled against the block's biggest week, and a mood-average tick underneath.
Bar colour keys off ACWR — coral above 1.12, light grey below 0.85, ink between. Taps open the week
sheet (or switches to the week view once slice 3 exists).

---

## Files

**New, additive:**

```
Training/Analytics/CalendarMonthCell.swift      the cell: bars, mood strip, niggle edge, key dot
Training/Analytics/CalendarWeekRail.swift       the eighth column
Training/Analytics/CalendarMonthScale.swift     fixed volume scale + the type→colour mapping,
                                                as pure functions so they are testable
RunningLogTests/CalendarMonthScaleTests.swift
```

**Tracked files edited — one:**

`Training/Analytics/TrainingCalendarSection.swift` — swap the existing per-day cell body for
`CalendarMonthCell(...)` and add the rail column to the row. Keep `onTapDay` exactly as it is; the
host still owns presentation. Do not change the file's public signature — `TrainingTabTwoView`
depends on it and the header comment says so explicitly.

If you need a second tracked edit, stop and write down why. The convention exists so this reverts in
one line.

---

## Data

Everything comes from slice 1's `calendar-days`. Add a decode + service alongside the existing
Trends pattern:

```
Training/Analytics/CalendarService.swift        fetch + decode, mirrors Trends/TrendsService.swift
Training/Analytics/CalendarModels.swift         CalendarDay, CalendarRun, CalendarWeek, BodyMention
```

`TrendsService.swift` only decodes DTOs into models and does no aggregation. Match that. The
temptation here is to compute the month rollup on-device because `TrainingAnalyticsViewModel`
already half does it — resist it. Two rollups will disagree.

---

## Layout

At 390 pt with 20 pt page padding: 350 usable, minus a 42 pt rail and 2 pt gutters, leaves ~41.7 pt
per day column. At 375 pt (iPhone SE, iPhone 13 mini) that drops to ~39.6 pt.

**This is under the 44 pt minimum touch target and you have to decide what to do about it.** Two
options, both acceptable:

- **Extend the tap target into the gutter** and grow the row to 68 pt. Visual cell stays small, the
  hit region does not. This is what the prototype notes lean toward.
- **Grow the row and let the grid scroll.** Honest, but a month you cannot see at once stops being a
  month view.

Whichever you pick, set it in `CalendarMonthCell` with a comment saying which and why, and verify
with the Accessibility Inspector rather than by eye.

---

## Accessibility

The grid is the whole feature, so this is not optional polish.

- Every cell needs an `accessibilityLabel` that reads the day as a sentence: *"Tuesday 21 July,
  23.2 kilometres, four runs including a key session, mood energized, left foot achy."* Colour
  carries four channels here and none of them survive VoiceOver otherwise.
- Mood is encoded **only** in colour. Green and amber at 3.5 pt are indistinguishable to a
  deuteranope. The accessibility label is the fix; consider also a Settings toggle for a mood glyph.
- Respect Dynamic Type in the numerals or clamp them and say so.
- `.accessibilityElement(children: .ignore)` on the cell so VoiceOver reads one label, not six.

---

## Tests

`CalendarMonthScaleTests.swift`, pure functions only:

- [ ] A 30 km day maps to full bar height; 0 km maps to no bar and a rest dash
- [ ] A day over the fixed scale clamps rather than overflowing the cell
- [ ] Multi-run days split proportionally and the segments sum to the total height
- [ ] Type mapping: key → coral, ≥18 km without a key → long, otherwise easy
- [ ] Week rail ACWR banding at the 0.85 and 1.12 boundaries, inclusive/exclusive stated

Views themselves are not unit-tested — iOS is not in CI (`.github/workflows/ci.yml` covers edge
functions, web and ML only). That is exactly why the scale and colour logic lives in a separate pure
file rather than inside the view body.

---

## Done when

- July renders as the prototype does: five week rows, a rail, coral only on key days
- May 11–17 visibly reads as the heaviest week without reading a number
- June 22–28 shows three rest cells, a 28.6 km bar, and four consecutive niggle edges
- VoiceOver reads one sentence per cell
- Tap targets measure ≥44 pt in Accessibility Inspector at 375 pt width
- `check_design_tokens.py` passes
- `TrainingTabTwoView` still compiles and renders — you did not change the section's signature
