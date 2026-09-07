# PAGED HOME — the day you turn to

**Applied:** 2026-08-21 · directly to the working tree
**Scope:** two new files under `RunningLog/RunningLog/App/`, one existing file
rewritten from the `body` down.
**NOT COMPILED HERE** — the cloud container has no Xcode and no Swift
toolchain. Nothing in this change has been type-checked. Build before trusting
it. Verify steps in §7.
**Prototype:** `home-newspaper-pages-prototype.html` (drag, or ← →)

---

## 0 · Two things found while reading, before any code

**The mechanic already exists in this app.** `Workouts/HistoryDetailPager.swift`
turns the journal like a book: `ScrollView(.horizontal)` + `LazyHStack` +
`.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`, a `PageTurnRail`
along the bottom edge, a soft haptic on the turn, accessibility actions named
*"Older entry" / "Newer entry"* — named for time rather than screen direction,
which is the right instinct — and a `pageTurnLocked` environment binding so an
inner control can take the drag.

None of that was reinvented. This change follows it. Two pagers behaving
differently would be worse than either one.

**But they run in opposite directions, and that is now a real inconsistency.**
`HistoryDetailPager` is book order — oldest page first, today's run last,
`128/128` means the end of the journal. This pager is newspaper order — today
is the front page and turning goes backwards in time, which is what the
prototype established and what Rio approved. **An athlete who turns pages in
both surfaces will find "back in time" is a different direction in each.** It
is flagged in the header of `HomeDayPager.swift` and it is open question §8.1.
Flipping this pager is a reversal of `HomePageBuilder.pages` plus the rail's
numbering — nothing else.

**Second finding: Today is not a tab.** The bar is Log · Train · Trends · Ask ·
Sheet · Week (`RunningLogApp.swift:109`). `TodayHomeView` is presented as a
**sheet** from `VoiceLogView` behind `showToday`, wrapped in a `NavigationStack`
with a Done button (`VoiceLogView.swift:207`). So the earlier plan's worry about
the left-edge interactive-pop gesture does not apply — there is nothing to pop.
The sheet's own dismiss gesture is vertical, and the pages now mostly do not
scroll vertically, so **a downward drag on a page that fits will dismiss
Today.** That is probably what you want; it is listed in §7 because it is a
behaviour change nobody asked for.

---

## 1 · What changed

Today used to be one `ScrollView` holding every section at once. It is now a
horizontal run of pages.

| | Before | After |
|---|---|---|
| Shape | one vertical scroll | one page per local day, turned by a swipe |
| Yesterday | a block on today's screen | its own page, one turn right |
| The window | 90 days fetched, one row kept | 90 days fetched, rolled into sessions, 60 days of pages |
| Cockpit | bottom half of the same scroll | page 2, standing on no date |
| Rest days | invisible | a page that says "Rest." · runs of them collapse to a gap page |
| Doubles | one "last log" | every session on the day's page, in clock order |

Page order left → right:

```
[ TODAY ] [ NUMBERS ] [ AUG 17 ] [ AUG 16 ] [ 4 DAYS ] [ AUG 11 ] …
```

---

## 2 · Files

```
App/HomePage.swift        NEW  38 lines of model, ~110 of builder. No views.
App/HomeDayPager.swift    NEW  past-day page, gap page, session entry, folio rail
App/TodayHomeView.swift   REWRITTEN from `body` down; loadAll() gained 4 lines
```

`App/` is a `PBXFileSystemSynchronizedRootGroup` (objectVersion 77), so the two
new files are picked up by Xcode without touching `project.pbxproj`. Nothing
was added to the project file.

Untouched and still used elsewhere: `TodayPlate18.swift` (every component
reused as-is), `SessionRollup.swift`, `TrainingLogStore.swift`,
`DesignSystem.swift`.

Deleted: `TodayHomeView.yesterdaySection` — dead once yesterday has its own
page. `TodayJournalEntry` still exists and is still used; `lastLog` is still
loaded, and is what a "jump to the last run" affordance would use if the rail
ever gets one.

---

## 3 · The page model

`HomePage` is an enum, deliberately, so the pager cannot be handed a page
shape nobody wrote a view for:

```swift
enum HomePage: Identifiable, Hashable {
    case day(Date)                                   // local start-of-day
    case cockpit                                     // stands on no date
    case gap(from: Date, through: Date, days: Int)   // ≥2 dayless days
}
```

`HomePageBuilder.pages(from:today:)` walks backwards from today, one calendar
day at a time, to `min(oldest logged day, today − 60)`. A single dayless day
becomes its own `.day` page (a rest day is part of the training). Two or more
consecutive dayless days collapse into one `.gap`. A trailing empty run — the
space before the athlete's first logged day, or before the 60-day bound — is
dropped, because that is the edge of the paper, not a rest week.

`maxDays = 60` is a rail limit, not a data limit. `TrainingLogStore` holds 400
days; a rail of 400 ticks is a scrollbar. Travelling further back is the Log
tab's job.

The builder takes an injectable `today`, so the page run is testable without a
device. **No test was written** — there is no test target coverage for this
kind of thing in the repo yet and adding one was out of scope.

---

## 4 · Data — nothing new is fetched

`loadAll()` is unchanged except for three derived values:

```swift
let rolled  = SessionRollup.sessions(from: logs)
let pages   = HomePageBuilder.pages(from: rolled)
let grouped = Dictionary(grouping: rolled, by: { $0.day })
```

computed off the main actor, once per load. `TrainingLogStore.shared.refresh(days: 90)`
was already being called and its rows were already being thrown away. **Turning
a page fetches nothing.**

A refresh that rebuilds the page run does not yank the reader back to the front
page: `currentPageID` is only reset when it is nil or when the page it names has
disappeared from the run.

Today-only, and deliberately absent from past pages:

| | Why |
|---|---|
| `TodayMoodPrompt` | Back-filling a check-in invents the athlete's own words. |
| `SleepCheckInPrompt` | Same — it writes `daily_checkins` for *today*. |
| `CoachMemo.fetchLatestUnread()` | "Unread" is a today concept. A dated coach-note fetch does not exist. |
| `TodayTomorrowWorkout` | Tomorrow is relative to today, not to the page. |

Past pages are therefore shorter than today's. That is a known hole, not a bug,
and the design should look deliberate about it rather than padding them.

---

## 5 · A day is not a run

The rule from `WEEK-TAB-APPLY.md` §0, applied here from the start rather than
after a rebuild. Grouping goes through `SessionRollup`, so:

- Aug 4's five Strava uploads are **two sessions**, not one 15.7 mi day and not
  five runs.
- A day with two or three sessions renders each one, in clock order, with its
  start time as the eyebrow (`6:05 PM · 2 OF 3`) instead of "THE SESSION".
- Pace is `TrainingSession.paceSeconds` — derived from miles and minutes.
  `workout_pace_per_mile` is populated on 12% of rows and is never displayed.
- A session's words come from `session.note`, which is nil for Strava's junk
  titles ("Morning Run"). A day whose only note is junk shows no quote rather
  than quoting a machine.
- `foldedCount > 0` surfaces as *"1 duplicate row folded in"*, same wording as
  The Sheet.

The HTML prototype does **not** do this — it shows one headline run per day.
The Swift does. Where they disagree, the Swift is right.

---

## 6 · Fitting a page

Budget on a 390 × 844 device: 844 − 44 masthead − 46 folio − safe areas ≈ 700pt.

Every page sits in `HomePageFrame`, a vertical `ScrollView` with
`.scrollBounceBehavior(.basedOnSize)`. A page that fits does not bounce — it
reads as a sheet of paper. A page that overflows scrolls rather than clipping.

Journal quotes are clamped with `.lineLimit(6)`. **This is the weakest part of
the change.** A 400-word entry is clamped with no affordance to read the rest,
because opening the session sheet from a day page needs a `TrainingLog`, and
what is in hand is a `TrainingSession` built from `TodayLogRow`s. Wiring that
up is the obvious next piece of work and it was left undone rather than faked.

Dynamic Type at XXL will blow the budget on today's page. Untested (§7.6).

---

## 7 · Verify — none of this has run

Build first. Then, on device:

1. **It compiles.** Nothing here is type-checked. Expect the first failures in
   the `DistanceFormat` / `CoachIntent` call sites if any of those signatures
   drifted.
2. **Doubles.** Turn to Mon 17 Aug (6.0 + 4.0) and Tue 18 (2.1 + 6.2 + 2.0).
   Two and three sessions render, each with its own clock time.
3. **A rest day** shows "Rest." and the empty-state sentence, and no invented
   content.
4. **A ≥2-day break** shows one gap page with the right count in words.
5. **Turn 20 pages back.** No stall — the rows are already in memory.
6. **Dynamic Type.** Default: nothing scrolls. XXL: pages scroll rather than
   clip. Today's page is the one to watch.
7. **Sheet dismissal.** A downward drag on a page that fits dismisses Today
   (§0). Decide whether that is right before shipping.
8. **VoiceOver.** Each page announces its date. Rail ticks are reachable and
   labelled. "Older day" / "Newer day" actions work.
9. **Check-ins still write.** Mood and sleep from today's page still upsert
   `daily_checkins`. This is the highest-value regression to catch — those two
   feed the recovery ledger.
10. **Cold launch, airplane mode.** Store falls back to disk; pages still
    build; the error state still appears if the logs fetch throws.
11. **A refresh mid-read** (pull the sheet open, wait for a reload) leaves you
    on the page you were reading.

---

## 8 · Open questions

1. **Direction** (§0). Newspaper here, book in `HistoryDetailPager`. Pick one.
2. **The cockpit.** It duplicates Trends. If it leaves Today, the model becomes
   purely days and `cockpitPage` deletes cleanly.
3. **Opening a session from a day page** (§6) — needs a `TrainingLog`, not a
   `TrainingSession`.
4. **60-day bound** (§3). Is the Log tab how you travel further, or does the
   rail need a jump-to-date?
5. **Does paging suit Train and Trends too**, or only the diary?

---

*— restraint as foundation, intensity as accent*
