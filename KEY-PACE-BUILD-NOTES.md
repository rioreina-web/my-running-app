# Key pace — built · 2026-08-09
*Revised same day after the first device run — see §Revision 1 at the end.*

Card 02 of the Charts tab now reads `TrendsService.keySessions` instead of
`TrendsWeek.keyPaceSec`. Spec and rationale: `KEY-PACE-APPLY.md`. Prototype:
`Post Run Drip Design System/key-pace-expand-prototype.html`.

**Not compiled here.** These files were written against the repo's real APIs
and cross-checked symbol by symbol, but this sandbox has no Swift toolchain —
the first real build is yours. Expect the usual first-compile friction (a
missing `import`, an argument-order nit); the logic and the shapes are the part
that was verified.

---

## What landed

| File | Status | Lines |
|---|---|---|
| `RunningLog/Trends/KeyPaceModels.swift` | new | ~660 |
| `RunningLog/Trends/KeyPaceChart.swift` | new | ~730 |
| `RunningLog/Trends/KeyPaceCard.swift` | new | ~200 |
| `RunningLog/Trends/KeyPaceDetailView.swift` | new | ~490 |
| `RunningLogTests/KeyPaceTests.swift` | new | ~420, 20 tests |
| `RunningLog/Trends/InstrumentsCardsTraining.swift` | edited | old card removed, tombstone added |
| `RunningLog/Trends/InstrumentsCardKit.swift` | edited | `InstrumentsData.keyPaces` deprecated |

**No Xcode project changes needed.** `RunningLog.xcodeproj` uses
`PBXFileSystemSynchronizedRootGroup` (objectVersion 77) for both `RunningLog`
and `RunningLogTests`, so files dropped into those folders are picked up
automatically. Nothing to drag in, no `project.pbxproj` to merge.

**No backend, no migration, no deploy.** Every figure comes off the
`trends-timeline` payload `TrendsService` already loads.

---

## How to build it

1. Open `RunningLog.xcodeproj` in Xcode.
2. **⌘B**. If the new files don't appear in the navigator, close and reopen the
   project — the synchronized group scans on open.
3. **⌘U** to run tests. `KeyPaceTests` is 20 tests and should pass on its own;
   it touches no network and no `UserDefaults`.
4. Run on a simulator, go to the **Charts** tab, open **KEY PACE**.

What you should see: the card opens on your most-represented zone rather than
ALL, the headline names that zone, dots are coloured by zone, and dragging
across the chart moves a crosshair with a readout underneath. Tapping the
readout — or a dot — opens the workout. `⤢ EXPAND` opens the full-screen view.

---

## Decisions made while building that the spec didn't pin down

Each of these is a judgement call. If you disagree with one, it's a small edit,
and I've named the file and the reason.

**1 · The card moved to its own file rather than being edited in place.**
`KeyPaceCard.swift`. The old `InstrumentKeyPaceCard` in
`InstrumentsCardsTraining.swift` is replaced by a tombstone comment explaining
what it did and why it went — so a future grep for the name lands on the
explanation instead of on nothing. Card 02 keeps its slot in the running order
in `InstrumentsTabView`; that file is untouched.

**2 · The card owns the time window.**
The Instruments tab has no time control at all, so the card holds
`@State window: TrendsWindow = .sixMonths` and hands a binding to its detail.
This is card-local, not a second global control — the Trends tab is untouched
and cannot disagree with it. When the Instruments tab grows a host-level
picker, hoist those four `@State`s into the host and pass bindings down. The
header comment says so.

**3 · Six zone chips, not seven.**
As flagged: the backend classifier folds LT into `hmp`, and `KeyZone.order` is
already exactly `mile · 3k · 5k · 10k · hmp · mp`. The chart renders every
token in that list, including ones with zero sessions — a zone with no data
gets a dimmed chip reading `0`, never a missing chip. A missing chip would
claim the zone doesn't exist.

**4 · Grade is widened from in-band minutes to the session's work bouts.**
`KeyPaceBuilder.grade` reuses `ThresholdGrade`'s rule — HR over the floor is
work, under it is cruise, absent is not guessed — but applies it to
`KeySession.workHrAvg` rather than to in-band HR, so an out-of-band session
still carries an honest grade. The two agree for in-band sessions. **This is
the one place I extended an existing concept rather than reusing it as-is.**
If you'd rather grade only in-band dots, it's one function; but then the
slow-edge leak stops being visible on this chart, which was the point of
drawing the band here.

**5 · A persistent readout row instead of a floating tooltip.**
`KeyPaceReadout` in `KeyPaceChart.swift`. The prototype's tooltip vanishes on
touch-up, which is useless on a phone and invisible to VoiceOver. The readout
sits under the chart, always shows what the crosshair is on, and is itself the
44pt tap target that opens the workout. Dots stay tappable too.

**6 · A tap and a scrub are told apart by travel.**
In `hitLayer`: a drag with less than 6pt of movement opens the workout; more
than that just moves the crosshair. Otherwise every scrub would end in a
navigation.

**7 · `InstrumentsData.keyPaces` is deprecated, not deleted.**
Nothing calls it now. It carries an `@available(*, deprecated)` and a comment
explaining what replaced it. Delete it whenever you like —
`TrendsWeek.keyPaceSec` itself stays, because Trends v2 still reads the field
directly.

---

## The four rules, and where they live

These are the reason the surface is trustworthy. Each has a test.

1. **No trend across zones.** `KeyPaceRead.trendSecPerMonth` returns `nil` for
   `zone == nil`, and the stat row reports the *zone count* instead of a slope.
   A fit through 5K reps and MP long runs measures the training schedule.
   → `trendIsNilForAllZones`
2. **No trend under three graded points.** Same `count >= 3` guard as
   `ThresholdRead.trendSecPerMonth`. → `trendNeedsThreePoints`
3. **Graded work only.** Cruise and unclassed dots are drawn and counted, never
   fitted. → `trendIgnoresCruiseAndUnclassed`
4. **Long runs excluded by default, reported, never deleted.** The builder keeps
   them; the filter hides them; the NOT COUNTED panel says how many and why.
   → `longRunsAreHiddenNotDropped`

Plus: a point is judged against the ladder of **its own week**, not the
window's last (`pointUsesItsOwnWeeksLadder`) — otherwise old sessions get
flattered by today's fitness.

---

## Degradation

Nothing here throws when the data is thin; it says less.

| Missing | Behaviour |
|---|---|
| No `bandLaps` / no ladder | Dots still plot on absolute pace. No band, no targets, no in-band stat, no vs-target values. Nothing is guessed. → `noLadderDegradesWithoutGuessing` |
| No HR on a session | Dotted-ring dot, graded `unclassed`, excluded from the fit. Never silently counted as cruise. |
| Fewer than 3 graded points | Dots, no line, and the note says why in words. |
| No sessions in the selected zone | Dashed chart frame with a sentence inside it, and `EmptyStateView` in the list. No em-dash anywhere (hard rule #8). |
| `confidenceTier == "low"` | Band edges dash harder. |

---

## Things I'd check first if something looks off

- **The card opens on the wrong zone.** `seedZone` picks the most-represented
  zone once, ties broken by most recent. If your data is long-run heavy, note
  that long runs are excluded from that count by default.
- **The band sits off the bottom of the chart.** Expected when the selected
  zone is much faster than the band anchor — e.g. mile reps against an HMP
  band. That's honest, not a bug; switch the anchor in the band accordion.
- **Trend line missing in vs-target mode.** Deliberate: `drawTrend` only runs
  in `.absolute`. A fit over deltas is a different claim and I didn't want to
  make it silently.
- **`InstrumentStat` shows nothing when collapsed.** Happens only when
  `dominantZone` is nil, i.e. no sessions at all. The card body is the empty
  state in that case.

---

## Not done

- The classifier still folds LT into HMP. Splitting it is a backend change to
  `keySessions.ts` and out of scope here.
- Zone selection and the two toggles are view state, not preferences — they
  reset with the tab. Only `BandSettingsStore.shared` persists, and it already
  existed.
- `TrendsReadView` still carries its own private `zoneColor` switch. There is
  now a canonical `KeyZone.color(_:)`; migrating that private copy to it is a
  two-line cleanup I left alone to keep this diff to one surface.
- Nothing is committed to git. The working tree was already dirty on
  `fix/audit-2026-08-06`; these files are added alongside, uncommitted.


---

# Revision 1 · after seeing it on device

Three things were wrong on the phone that were invisible in the HTML prototype,
plus one change of direction on heat.

## 1 · The legend was a wall of vertical letters

`InstrumentLegendRow` was a plain `HStack`. That is fine for three items and
catastrophic for six: SwiftUI compresses every child to fit the row, and
tracked 8.5pt uppercase text under compression wraps **one character per
line**. The HTML prototype never showed this because CSS `flex-wrap` was doing
the work all along — the bug was in the translation, not the design.

Fixed in `InstrumentsCardKit.swift`, for every Instruments card, not just this
one:

- **`DripFlowLayout`** — a `Layout` implementation that lets items keep their
  natural width and spill onto the next line.
- **`.fixedSize(horizontal: true, vertical: false)`** on `InstrumentLegendItem`,
  which is the actual root cause: without it an item reports whatever width it
  is offered.

Labels also got shorter: `WORK · HR OVER FLOOR` → `WORK`, and so on. The full
explanation lives in the note under the chart, where there is room for a
sentence.

## 2 · The weekly target read as scattered blue bars

The staircase was drawn as one disconnected segment per week, at 1.6pt and 85%
opacity in the *same blue as the dots*. It was the first thing anyone pointed at
when asked what was confusing, and correctly so — it looked like data.

`drawAnchorSteps` now emits **one connected path**: each tread runs to the next
one's start and a riser joins them. It is also deliberately subordinate — 1.1pt
at 45% opacity — so it sits behind the dots rather than competing with them.

## 3 · The card was drawing six layers in 140pt

Band wash, band edges, staircase, heat ticks, trend and 28 dots. Any one of them
is fine; all six in a card-height chart is noise.

New `KeyPaceDensity`:

| | `.glance` (card) | `.full` (detail) |
|---|---|---|
| Band wash | yes, 7% | yes, 10% |
| Band edges | no | yes, dashed |
| Weekly staircase | **no** | yes |
| Ghost ticks | **no** | yes |
| Dots · trend · crosshair | yes | yes |

Card height went 140 → 168 and dots 3.4 → 3.8 with the freed space. The detail
is unchanged in what it shows; it is where the full instrument lives.

Heat ticks also lost their end caps — capped, they read as error bars, which is
a much stronger claim than "the weather moved this by four seconds". Now a plain
hairline with a small open marker.

## 4 · Raw pace leads; the adjustment is offered, not applied

Per your note. The chart was plotting the heat-neutral pace and relegating the
watch pace to a tick — which meant the first number you read was one you never
saw on your wrist.

New `KeyPaceBasis` — `.watch` (default) and `.heatNeutral`. It drives the dots,
the headline, the collapsed stat, the readout, the session list, the stat row
and the note. The other basis becomes the ghost tick, so the correction stays
visible either way. The detail has a two-state control: **WHAT YOU RAN /
HEAT-ADJUSTED**.

**The judgement call worth knowing about:** the trend is fitted on *whichever
basis is showing*, so the line always passes through the dots. A trend on watch
pace across a summer contains the weather, so on `.watch` the note says exactly
that — "the trend still has that weather in it, switch to heat-adjusted to take
it out" — rather than quietly reporting a number that means something different
from what it looks like. `bandMembershipFollowsTheBasis` covers the same issue
for the in-band count: a session can be out of band on watch pace and in band
once the heat comes out, and the surface must not report one while showing the
other.

If you'd rather the trend always fit heat-neutral regardless of what is drawn,
it's one argument at three call sites — but then the dotted line stops matching
the dots, which is its own kind of lie.

## Tests

20 → **26**. The six new ones: `watchPaceLeads`, `noCorrectionNoGhost`,
`trendFollowsTheBasis`, `watchNoteNamesTheWeather`,
`bandMembershipFollowsTheBasis`, and the updated `noLadderDegradesWithoutGuessing`.

`trendFollowsTheBasis` is the interesting one — it builds a window where heat
climbs faster than fitness, so watch pace trends *slower* while corrected pace
trends *faster*. Both fits are correct; the test pins that the one on screen is
the one the dots came from.

## Still open

- The `HMP TARGET` caption sits at the left edge of the staircase and can touch
  the first tread. Cosmetic, easy to move if it bothers you.
- The prototype (`key-pace-expand-prototype.html`) has been updated to match all
  four changes, so it stays usable as the reference.

---

# Revision 2 · volume, heart rate, heat

## Dot size = volume at that pace

`KeyPacePoint.bandMinutes` — the minutes a session actually spent inside the
band around **its own zone's** anchor, measured from `BandLaps` laps joined on
`training_log_id`. Not the whole session, not the whole run: the time at that
pace.

Size is **area-proportional** (`sqrt` on the radius). The eye reads a mark's
area, so mapping minutes straight onto radius would make a 50-minute session
look four times bigger than a 25-minute one instead of twice.

Three sources, and the readout names which one it used, because a measured 24
minutes and an inferred effort score are different claims:

| `volumeSource` | Where it comes from | Reads as |
|---|---|---|
| `.measured` | Laps inside the session's own zone band | `24 MIN` |
| `.load` | `KeySession.qualityLoad`, the app's existing weighted work minutes | `31 LOAD` |
| `.none` | Neither | base-size dot, no claim |

A point with no volume draws at the **base** radius, not the minimum — absent
volume is not the same fact as a short session.

**Volume responds to the band width.** Widen the slow edge and more of each
session counts, and the dots visibly grow. That is the honest behaviour rather
than a bug, and `volumeRespondsToTheBandWidth` pins it.

## Heart rate gets its own lane

The dot already carries four facts: zone (hue), grade (fill), volume (area),
long-run (shape). A fifth would make all five unreadable, and this file's own
rule is that no channel encodes two things.

So HR is a 34pt lane on the same x-axis under the plot, with the **floor drawn
as a dashed line** — because the grade rule above is defined by it. A dot is
solid exactly when its tick sits above that line, which makes the rule visible
instead of something you have to be told.

Detail only, behind a `Heart rate` toggle. The card is the glance and 34pt is
real estate it does not have. HR also appears as bpm in the readout and in
every list row.

## Heat, said out loud

Already plotted as the ghost tick; now also stated. The readout and list rows
read `+4s HEAT → 5:26` rather than the bare adjusted pace, so the correction
is named and quantified rather than implied by a hairline.

## The stat row

When measured volume exists, the third stat becomes **`MIN AT PACE`** — total
minutes at that pace across the visible set — displacing the in-band count. The
dots are already answering "how much work at this pace"; the number underneath
should be the same question, not a different one.

## Tests

26 → **33**. New: `volumeIsMeasuredFromLaps`, `volumeRespondsToTheBandWidth`,
`volumeFallsBackToQualityLoad`, `volumeAbsentIsNotZero`,
`volumeDomainNeedsSpread`, `hrDomainIncludesTheFloor`, `hrDomainNilWithoutHr`.

`hrDomainIncludesTheFloor` is the one worth knowing: even when every session
sits well above 160, the lane's range is padded down to reach the floor, so the
line that defines the grade rule can never be off-screen.

## Still open

- With `ALL` zones and long runs on, the largest dots overlap. Single-zone
  views are clean. If it bothers you the fix is a smaller `rMax` — one constant
  in `KeyPaceChart.radius(for:)`.
- The HR lane at 39 sessions is dense. It reads fine per-zone.

---

# Revision 3 · the lane reads efficiency

Raw bpm is not comparable between sessions. 176 at 5K pace and 158 at marathon
pace say nothing side by side, so a lane of raw heart rate is a lane of noise
unless you already know what every session was — which is exactly the knowledge
the chart is supposed to supply.

**Metres per heartbeat divides that out.** It is pace and heart rate in one
number, it rises as fitness rises, and a 5K rep and an MP block can honestly sit
on the same scale.

`KeyPaceLane` — `.efficiency` (default) · `.heartRate` · `.off`, picked in the
detail. `KeyPacePoint.metresPerBeat(_:)` delegates to
**`InstrumentsData.metresPerBeat`**, the same function card 03 already uses, so
the Efficiency card and this lane cannot report different numbers for the same
session.

## The reference line differs by reading, deliberately

- **Heart rate** draws the grade **floor**, because the fill of every dot above
  is defined by it. A session under that line is exactly a hollow dot — which
  turns the grading rule from something documented into something visible. This
  is the reason heart rate stays available at all.
- **Efficiency** has no floor to draw, so it draws the window's **median**.
  Above the line is a better-than-usual day *for this athlete*. There is no
  external standard for metres per beat and the chart must not imply one.

The median is a median rather than a mean on purpose: one session where the
strap read 90 bpm all the way round would drag a mean badly, and
`efficiencyReferenceIsAMedian` pins that it doesn't.

## Efficiency follows the pace basis

Computed on whichever pace is showing, so the lane agrees with the dots above
it. On `AS RECORDED` in the heat it reads low for the same reason the pace does
— that coupling is honest: you are looking at what happened, not at what it
would have been in October. Switch to `HEAT-ADJUSTED` and both move together.

## Where it shows

Detail only — the lane costs 34pt and the card is the glance. Efficiency also
appears in the readout and every list row as `1.24 M/BEAT`, alongside bpm.

## Tests

35 → **40**. `efficiencyMatchesTheSharedImplementation` is the one that matters
long-term: it asserts this surface's number equals `InstrumentsData`'s, so if
anyone ever forks the formula the test fails rather than the two cards quietly
disagreeing.

---

# Revision 4 · the tagline, and a wordiness pass

## The standing tagline is gone

"— restraint as foundation, intensity as accent" was hardcoded inside
`PlateFooter`, so it printed on **five** unrelated surfaces (Charts, Signal Lab,
Injuries, Training Analysis, Today) plus a sixth hand-written copy in the Pace
Bands footer. It said nothing about the data on any of them.

`PlateFooter` now prints the caller's caption or nothing at all. The four
surfaces that pass a real caption are unchanged; the Charts tab passed none, so
its footer is removed entirely. The Pace Bands caption keeps its real half
("Membership on heat-adjusted pace · weekly median anchor") and loses the
clause.

## "0s PER 30 D" now reads FLAT

A slope under half a second per 30 days rounds to `0s`, which reads as a value
the app failed to compute rather than as the finding it is. It now prints
**FLAT · TREND** with the basis underneath. Same rule as the note, which
already said "flat to within a second a mile per month".

Worth saying plainly: **the zero was correct.** On unadjusted pace through a
block carrying +9s a mile of conditions, flat is what an improving athlete
looks like. That is precisely the comparison the AS RECORDED / HEAT-ADJUSTED
control exists to make.

## The card was carrying five paragraphs of chrome

Under one 168pt chart sat a readout, a six-item legend, three stats with detail
lines, and a four-line note. Trimmed:

| | Before | After |
|---|---|---|
| Note | full paragraph incl. heat lecture | one sentence: the finding |
| Legend | WORK · CRUISE · NO HR (+3 more) | `FILLED · OVER HR FLOOR` (+2) |
| Readout | `JUN 9 · MP · 80 LOAD · 165 BPM · WORK` | `JUN 9 · MP · 80 LOAD · 165 BPM` |
| `MIN AT PACE` detail | `8 SESSIONS` | `HMP BAND` |

Nothing was hidden, only de-duplicated:

- The compact note drops the session count (the stat row's first figure) and
  the "these are watch paces" clause (the stat's own detail line, and the
  segment directly above the chart).
- The glance legend collapses three grade swatches into one statement. Filled
  means the heart rate cleared the floor; everything else is visibly not
  filled. The detail still spells all three out, because it has the HR lane and
  the floor line beside it to spell them against.
- The readout stops naming the grade when it is plain `work` — the swatch to
  its left already shows it. Cruise and no-HR are still named, because those
  are the cases worth reading.
- `MIN AT PACE` stopped repeating the session count that sits two columns to
  its left.

Detail view is unchanged: it has the room, and it is where someone goes to read
carefully.

---

# Revision 5 · chip order, and naming the graded subset

## Chips list slowest first

`MP · HMP · 10K · 5K · 3K · MILE`, via a new `KeyZone.chipOrder`.

**Not** a change to `KeyZone.order`. That constant is the input to
`KeyZone.rank`, and four call sites treat the rank as a meaningful ordinal —
"tie goes to the faster zone" in `TrendsDetailViews.defaultZone`, a reversed
stacking order at `:905`. Flipping it would silently invert decisions that have
nothing to do with how a chip row reads. Taxonomy order and presentation order
are two concepts; `chipOrder` names the second instead of overloading the first.

The other chip rows in the app (Trends detail, Fast segments) still read fast →
slow. Say the word and they move too.

## The count stat names its own subset

The row read `12 SESSIONS / LT ONLY` beside a slope computed from nine of them.
It now reads `12 SESSIONS / 9 OVER HR FLOOR` whenever the two differ.

This replaces the phrase `GRADED WORK ONLY`, which was carrying the same fact
under the slope in words nothing on screen defined. "Over HR floor" matches the
legend the reader has just looked at.

---

# Revision 6 · the volume bug, and per-zone HR floors

## The 5-mile session that measured 5 minutes

`3mi-1mi-1mi @ 5:15`, labelled HMP, drawn as one of the smallest dots on the
chart. The volume filter was:

```swift
laps.filter { !$0.skip && $0.adjSec >= edges.fast && $0.adjSec <= edges.slow }
```

HMP anchor 335s, fast edge `335 × 0.95 = 318s` = **5:18**. The session's reps
were run at **5:15**. Every one of them was a second faster than its own band's
fast edge, so every one was discarded, and the only lap that counted was a
single slower chunk — five minutes.

Root cause is the classifier folding LT into HMP: the session is *labelled* HMP
and was *run* at LT effort. Label and pace genuinely disagree, and the volume
measure was silently taking the label's side.

**Fix: the fast edge is not applied.** Inside a single session there is no
faster zone to keep out, so it has no job. The slow edge does — it is what
separates the reps from the recovery jogs, the warmup and the cooldown. Running
quicker than target is still work. That session now measures **5.0 mi / 26 min**.

Volume is also now stated and sized in **miles**, not minutes. You described the
session as "five miles of work"; a number you can check against your own memory
of the run beats a marginally better load proxy you can't.

## Per-zone HR floors — option 1

`KeyPaceFloors`. For each zone: **that zone's own median work HR, minus 8 bpm.**

The single 160 was honest about its provenance and wrong outside it. It guarded
one band, HMP, calibrated on nineteen of your sessions. On six zones it demoted
real marathon-pace work for the crime of being marathon pace. The question
"was this hard in absolute terms" has no single answer across six zones; "was
this easy *for this kind of session*" does, and it is what the grade was always
reaching for.

Rules:

| Condition | Behaviour |
|---|---|
| ≥ 3 HR sessions in the zone | floor = median − 8 |
| < 3 | **no floor** — an HR-bearing session grades work |
| `BandSettings.hrFloor == 0` | grading off entirely, as before |
| No HR on the session | `unclassed`, as before — never guessed |

Two deliberate choices. **Floors are derived from the whole history, not the
visible window** — a zone's typical heart rate is a property of the athlete, and
narrowing the range should not move what counts as hard. And **an underived
floor does not demote**: guessing one would recreate the exact failure this
replaces.

The HR lane now draws the *selected zone's* floor. Across ALL zones it draws
none and the legend says `FLOOR IS PER ZONE`, because there isn't one — which
was the whole problem with the single number.

`BandSettings.hrFloor` is untouched as a stored setting: it still drives the
threshold surface, and here it acts as the on/off switch.

## Tests

43 → **50**.
