# Trends v2 — the block surface

**Built** 2026-08-18 from `trends-simplified-prototype.html`.
**Status** in the target, opt-in, defaults off. v1 is still the tab.

---

## What shipped

| File | Lines | What it is |
|---|---|---|
| `Trends/TrendsBlockModels.swift` | ~650 | Every derivation. Pure value types, no SwiftUI, no fetch. |
| `Trends/TrendsBlockView.swift` | ~890 | The surface — plate, five sections, three Canvas charts. |
| `Trends/TrendsTabView.swift` | edited | Hosts both surfaces, persists the choice in `@AppStorage("trendsSurface")`. |
| `Trends/TrendsLegacyTabView.swift` | edited | Gains an optional `onOpenBlock` and a `v2 ›` door chip. Nothing else. |

The Xcode project uses synchronized folder groups, so both new files are picked
up without touching `project.pbxproj`.

`TrendsV2View` — the old five-signal surface — is **untouched and still
unlinked**. It stays DEBUG-only behind `-trendsV2Preview`. The new enum case is
called `.block`, not `.v2`, so the two never get confused in code.

---

## How to reach it

Open Trends → tap `v2 ›` in the header. Tap `v1 ›` to go back. The choice is
persisted, so you can live on one for a week without re-picking it every
morning. Default is v1 until the block surface earns the slot.

---

## The five sections

**plate** — weeks in the window, total miles, key sessions, and the race
countdown when a plan with an `end_date` is active.

**01 · The shape of it** — twelve weeks of miles on one axis. The three stat
cards from v1 are read off the chart instead: current week in coral with its
projection ghosted above it, four-week average as a dashed rule, peak labelled
where it happened. Key-session counts as dots under each column — the one place
this surface lets load and quality touch. Acute:chronic is a word (`Balanced`)
with the ratio as a footnote.

**02 · What's actually changed** — the fitness proof. Two lanes on the *same*
axis as section 01: band pace on top (faster is higher), minutes in band
beneath. Two lanes rather than two scales in one plot — overlaid, the line
reads as part of the bars and neither series is legible. Section hides itself
when there are fewer than two work sessions.

**03 · Where the miles go** — the ten-zone histogram folded to one bar:
easy / steady / quality. Token mapping mirrors `TrendsMoodLanes.zoneStack`.
Miles without lap data are stated in the footnote, never folded into a band.

**04 · Best of the block** — biggest completed week, longest run, and the
biggest threshold session (or the fastest key session when there's no band
data). Each is the maximum of one column over the window, so the same block
always produces the same rows.

**05 · One thing** — a focus, chosen by a rule set, first match wins:
grey zone ≥ 30% → easy < 65% → ACWR spiking → key sessions thin → threshold
holding. No match, no section.

---

## Rules this keeps

**One time control.** The segmenter owns the window. Section 02 passes
`range.days` into the threshold builder rather than carrying a range of its own.

**One fetch owner.** Same tab-index gate v1 carries (`selectedTab == 4`), so
swapping surfaces never fires a request for a tab you didn't open. Two small
extra awaits, both cached for the visit and both allowed to fail:
`TrendsAthleteState.fetch()` for the canonical intensity-weighted ACWR (so the
chip can't disagree with v1's number) and `TodayGoal.fetchActive()` for the
countdown.

**One definition.** Partial-week handling — days into week, the on-pace
projection, four-week average over *completed* weeks only, and the mid-week
projected acute load — is copied deliberately from `VolumeDetailView` in
`TrendsDetailViews.swift`, which is canonical. **If that file's rules change,
change them here in the same commit.**

---

## The prose question — read this one

`TrendsLegacyTabView` carries a standing rule from 2026-08-03: *no generated
prose on this tab.* Five paragraph generators were culled for restating the
charts while claiming more than the data held.

This surface writes sentences, so here is the line it draws:

- Every sentence is a **fixed template** with computed numbers slotted in. No
  model, no LLM, no adjective chosen by data.
- Every clause is **arithmetic you could do off the chart beneath it** — a
  difference, a count, a ratio, a rank. Nothing infers cause, trajectory or
  state of body.
- Where a claim needs three points to be honest, the guard is the same one
  `ThresholdRead.trendSecPerMonth` uses, and the sentence is **omitted rather
  than hedged** when the guard fails.

If that still reads as the thing the rule was written against: delete the
`read` properties in `TrendsBlockModels.swift`. Every caption is optional at
the view layer and all five sections stand without them.

---

## Not done yet

- **No scrub.** v1 lets you drag the load chart to read a week. Worth adding
  here if the surface survives.
- **Nothing is tappable.** No drill-down from a moment to the run, no week
  sheet. Deliberate for a first pass — the question was whether the screen is
  worth opening, not whether it's navigable.
- **No unit tests.** `TrendsBlockBuilder` is pure and takes plain arrays, so
  it's ready for them: feed it `TrendsSampleData.weeks` and assert the numbers.
- **Moments are fixed.** Can't pin your own yet.

---

## Verify

Double-click `build.command`, then read `build.log`.

---

## Revision 2 — 2026-08-18, after the first device run

Two things were wrong on the phone at 6 MO.

**Key sessions were invisible.** They were a row of dots under the axis. At
twelve columns that reads; at twenty-six it is a grey smear, because every week
has one or two and twenty-six columns of "one or two" is a texture, not a
signal. Dots are gone. **Quality miles now stack on top of each bar** — the
sharp end up, the same convention `TrendsMoodLanes.zoneStack` uses. The mark
scales with the column, says how *much* rather than how many, and can't smear.
The session *count* still appears, in the scrub readout, because the count is
what you check and the miles are what you see.

**Bars were hairlines.** The gutter was a fixed 9pt — a third of the column at
twelve weeks and most of it at twenty-six. It's now a third of the column width
(`gap(forColumn:)`), so the bar stays the dominant mark at every range: **7.3pt
at 26 weeks, up from 1.7pt.** Bars are also capped at 44pt and centred, so 4 WK
stops drawing four slabs.

**Weeks are now selectable.** Drag or tap the load chart to scrub; a readout
under the chart gives that week's miles, quality miles and key-session count.
Tapping the readout opens the week in `TrendsWeekSheet` — the same sheet the
rest of the tab uses, via `TrendsWeekDrill.make(...)`, rather than a second
definition of "a week, opened". Selection clears on a window change, because an
index into a 12-week array points at a different week in a 26-week one.
`.sensoryFeedback(.selection)` on the scrub. The chart also publishes one
VoiceOver child per column, so it's walkable along the time axis.

**Two label collisions fixed.** `4-WK AVG` moved to below-left: the right end
is where the current week and its projection ghost live, and above the line
belongs to the peak marker, so neither end of the top edge was free. Month
ticks now skip any label that would land within `~34pt` of the previous one —
at 6 MO the naive version printed FEB over MAR.

Geometry was verified by rendering the identical math at 26, 12 and 4 columns
before the Swift went in.
