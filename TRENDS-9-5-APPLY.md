# Trends: the 9.5 pass

Two files changed: `RunningLog/RunningLog/Trends/TrendsLegacyTabView.swift`
(the default Trends surface) and `RunningLog/RunningLog/Training/GoalAndPacesCard.swift`
(one new defaulted parameter, so Train's call site is untouched). Applied directly in the working tree on
2026-09-01, on top of the uncommitted changes already there. A backup of the
files as they were before this pass are at `~/TrendsLegacyTabView.swift.bak`
and `~/GoalAndPacesCard.swift.bak` on the Mac (outside the repo).

Verify:

```
double-click build.command, then read build.log — the Swift half was NOT
compiled when this was written (no xcodebuild in the sandbox). See "Not
verified" below.
```

---

## What changed, in the order it reads

**The readout leads the tab.** "WEEK OF AUG 31 · THIS WEEK / 42 mi · 12
quality · 7:10 /mi / mood · WATCHING: calf" used to open section 03, four
screens down. It now sits directly under the headline — the five-second read
the tab promises, in numbers and the athlete's own words, so the
no-generated-prose rule still holds. Its eyebrow went from coral to secondary
(the header's coral eyebrow is 60pt above it; coral is punctuation) and the
three stats went 16 → 22pt because they are now the read.

**Race prediction moved up under Load.** It was last on the scroll, half
behind the tab bar. "How much am I running" → "what does that buy me" is one
question in two halves. New order:

    readout → YOUR GOAL → segmenter
    01 Load · 02 Race prediction · 03 Pace · 04 Key sessions · 05 Mood ·
    06 Closing on goal pace

**The top of the tab is one masthead, no rules** (second pass, after the
first screenshot: "too many lines" / "make this a much smoother look"). The
header, readout, goal line and segmenter were separated by five hairlines in
about 300pt — a rule under the readout, the goal card's own top AND bottom
hairlines, a rule under the card, and a rule under the segmenter. All of them
are gone except the last, which closes the masthead and is the first line on
the tab. Separation is space now: 18 / 22 / 26pt. `GoalAndPacesCard` gained a
`hairlines: Bool = true` parameter for this — Train keeps its boxed line,
Trends passes `false` — and drops its 14pt vertical padding with them, so the
goal reads as the last line of the readout rather than a card sitting on top
of one.

**Two doubled rules fixed.** Where Recovery was deleted (08-24) two
`EditorialRule`s sat back to back with 44pt between them — it read as a bug.
The same thing happened before the goal-pace grid (a rule after Mood, then
another inside the `if`). One rule each now.

**Threshold miles is behind a fold**, the same `expandableSubHead` head-to-head
uses. Inside Pace it is the second read, not the first.

**Nothing vanishes any more.** Threshold miles and Closing on goal pace used
to render nothing when they had nothing — so a new athlete's tab was shorter
than Rio's and they never learned those sections existed. Each now leaves one
quiet 13pt tertiary line saying what fills it (`quietEmpty(_:)`, a footnote,
deliberately not `EmptyStateView`).

**Mood says why it doesn't obey the segmenter.** Subhead now reads "Mood,
miles and niggles by day · always the last 30 days". It is the one exception
to ONE TIME CONTROL on this tab and was silent about it.

**The `lab ›` / `v2 ›` door chips are `#if DEBUG`.** They are surface-switchers
for Rio, not features; a TestFlight tester was one tap from an unfinished
surface. Xcode builds are Debug, so nothing changes on the Mac.

**The two smallest labels scale.** The WATCHING niggle line (9pt fixed) and
the sub-block eyebrows (10pt fixed) now come from `@ScaledMetric`s off
`DripTypeFloor.eyebrowSmall` (10) and 11 — the house pattern in
`DesignSystem.swift`, so they grow with Dynamic Type instead of staying at
the floor.

## Not verified

- Not compiled. Brace/paren balance checked; `#if DEBUG` inside an `HStack`
  builder is supported (Swift 5.4+). `subHead(_:)` is now unreferenced —
  expect a warning, not an error; it is kept for the next sub-block.
- Not rendered. Check on device: the readout under the headline with the
  goal line under it — if the top feels crowded, the 22pt stat can come
  back to 20, or the goal line can lose its top rule.
- `CLAUDE.md`'s Trends bullet ("Race-anchored fitness range with
  confidence, volume tile, ACWR, niggles tile…") was already stale before
  this pass and still is; the section list in the file header of
  `TrendsLegacyTabView.swift` is current.

## Rollback

```bash
cp ~/TrendsLegacyTabView.swift.bak RunningLog/RunningLog/Trends/TrendsLegacyTabView.swift
cp ~/GoalAndPacesCard.swift.bak   RunningLog/RunningLog/Training/GoalAndPacesCard.swift
```
