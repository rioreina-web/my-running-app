# Calendar · slice 4 — pattern cards

*iOS. Depends on slices 1 and 3. The most dangerous slice in the plan — read the Ethics section
before writing any code.*

---

## What this gives you

Four cards under the week view that say something about the week rather than just reporting it:
polarisation, load vs recovery, session spacing, niggle timing. Each opens to the evidence it used.

---

## Read this first

These cards make claims about an athlete's body. That puts them in a different category from
everything else in the calendar, and three rules follow.

**1. Descriptive, never prescriptive.** *"HRV averaged 67 against a 28-day baseline of 71.6"* is a
fact. *"You should take a rest day"* is medical advice from an app that cannot see the athlete. Ship
only the first kind. `InjuryModels.swift` already sets this standard — "surfaces, never interprets."

**2. Every card shows its working.** A card that cannot open to the runs, weeks or sessions it
counted should not make the claim. This is not a nice-to-have; it is what keeps a wrong card
recoverable — the athlete can see the reasoning and disagree with it.

**3. The thresholds are guesses and must not become notifications.** 78 % easy, ACWR 1.08, HRV −4.
They are tuned against one athlete's twelve weeks. In-view they are fine. As a push notification
saying you might be getting injured, a false positive is genuinely harmful — it can push someone into
unnecessary rest, or teach them to ignore the one that matters. **Do not wire these to
`PushNotification`, the coach, or any nudge surface in this slice.** That is a separate decision with
a calibration study behind it.

**Niggle language.** `InjuryModels.swift` is explicit: niggle severity is a **verbatim word**
(`severity_hint`), and the 1–10 score exists for sorting only, never display. The HTML prototype
shows `2/10` in one place. That is a bug in the prototype. Show the word.

---

## Paste this to Claude Code

> Read `CALENDAR-4-PATTERNS-APPLY.md` in the repo root in full, including the Ethics section, then
> open `calendar-month-prototype.html`, switch to WEEK, and read the four pattern cards and their
> evidence sheets.
>
> Build the four detectors as **pure functions in a separate file with no SwiftUI import**, taking
> slice 1's `CalendarDay` / `CalendarWeek` models and returning a `CalendarPattern` value. Then build
> the card and sheet views on top. Every threshold goes in one `CalendarPatternThresholds` struct
> with a comment saying it is uncalibrated.
>
> Write unit tests for every detector covering the boundary cases listed in this document. These are
> the only part of the calendar that is properly testable — do not skip them.
>
> Do not wire any of this to notifications, the coach, or any nudge. Do not display a numeric
> severity for a niggle; use the verbatim word.

---

## The shape

```swift
struct CalendarPattern: Identifiable {
    let id: String                  // "polarisation" | "load-recovery" | "spacing" | "niggle-timing"
    let label: String
    let value: String               // compact readout, e.g. "88 / 12"
    let tone: Tone                  // good | watch | flag — colour only, never a verdict on the athlete
    let verdict: String             // one sentence, descriptive
    let body: String                // the numbers behind it
    let evidence: Evidence          // what the sheet lists
    enum Tone { case good, watch, flag }
}
```

Detectors live in `CalendarPatterns.swift` with **no `import SwiftUI`**. That constraint is the whole
reason this slice is testable.

---

## The four

### 1 · Polarisation — *are easy days actually easy?*

Easy + steady miles vs MP-and-faster, from slice 1's `zone_miles`. Plus a count of non-key runs whose
whole-run pace landed MP or faster.

- `good` when easy share ≥78 % **and** quality > 0
- `watch` when easy share <78 %
- `flag` when quality == 0 — a week with no quality at all is worth naming

> Note the third case. A 116 km week with zero quality (see week of 11 May) is not a good week just
> because it was 100 % easy. A naive "more easy is better" rule calls that perfect.

**Evidence:** every run in the week with the zone it landed in, tappable to the day.

### 2 · Load vs recovery

ACWR from `athlete_state`, against HRV mean vs its 28-day trailing baseline.

- `flag` only when **both** move wrong — ACWR >1.08 **and** HRV baseline delta < −4
- `watch` when HRV is down but load is not
- `good` otherwise

> The conjunction matters. HRV alone is noisy — sleep, alcohol, illness, a bad sensor night. ACWR
> alone is a volume statistic. Firing on either one separately generates constant false positives,
> which is exactly how a feature like this becomes wallpaper.

**Degrades without slice 5.** With no HRV, show ACWR alone and say so — *"HRV not connected"* — and
never show `flag`. A one-legged version of a two-signal test must not claim the two-signal verdict.

**Evidence:** all weeks in the block with their ACWR and HRV delta, so the athlete can see whether
this week is actually unusual. One week in isolation means nothing.

### 3 · Session spacing

Gaps between `key_dates`, back-to-back detection, and whether the long run followed a hard or
low-mood day.

- `flag` on any 1-day gap between key sessions
- `watch` when the long run followed a day with ≥4 km quality or a mood of tired/struggling
- `good` otherwise

**Evidence:** every key session in the block with its gap from the previous one.

### 4 · Niggle timing

Co-occurrence of `body_mentions` with: the day after a key session, a double day, a night below sleep
baseline, a rest day.

**This card must state its own limits in the UI**, not just in code: categories overlap, one mention
can sit in several, and none of it is causal. The prototype's wording — *"This is co-occurrence, not
cause"* on the card and *"Detection, not diagnosis"* in the sheet — is the required standard, not a
suggestion.

Tone is `good` when the week has no mentions, `watch` otherwise. **Never `flag`.** An app should not
raise an alarm about someone's body from a correlation over twelve weeks of one person's data.

**Evidence:** the co-occurrence bars, plus the niggle threads with their verbatim words.

---

## Files

**New, additive:**

```
Training/Analytics/CalendarPatterns.swift          detectors — NO import SwiftUI
Training/Analytics/CalendarPatternCard.swift       card + evidence sheet views
RunningLogTests/CalendarPatternsTests.swift
```

**Tracked files edited — one:** `Training/Analytics/CalendarWeekView.swift` from slice 3 — fill the
patterns placeholder. If slice 3 left the container in place this is a one-line change.

---

## Thresholds

One struct, one place:

```swift
/// UNCALIBRATED. Tuned against a single athlete's 12-week block, 2026-05 → 2026-07.
/// These decide what the athlete is told about their own body — do not widen their
/// reach (notifications, coach prompts, plan changes) without a calibration study
/// across multiple athletes. Changing a number here changes a health claim.
struct CalendarPatternThresholds {
    static let easySharePct       = 78.0
    static let acwrElevated       = 1.08
    static let hrvBaselineDrop    = -4.0
    static let qualityKmHardDay   = 4.0
    static let sleepBelowBaseline = -0.6
}
```

---

## Tests

`CalendarPatternsTests.swift`. Pure functions, no view. Every boundary stated as inclusive or
exclusive and asserted:

**Polarisation**
- [ ] 78.0 % exactly → `good` (boundary is inclusive)
- [ ] Quality == 0 with 100 % easy → `flag`, not `good`
- [ ] A drifting non-key run at exactly the MP boundary counts
- [ ] Zero-volume week does not divide by zero

**Load vs recovery**
- [ ] ACWR 1.08 exactly with HRV −5 → not `flag` (exclusive)
- [ ] ACWR 1.09 with HRV −4.0 exactly → not `flag` (exclusive)
- [ ] ACWR 1.09 with HRV −4.1 → `flag`
- [ ] HRV nil → never `flag`, and body text says HRV is not connected
- [ ] ACWR nil → card still renders

**Spacing**
- [ ] Two key sessions on consecutive days → `flag`
- [ ] One key session → no gaps, no crash
- [ ] Zero key sessions → renders, does not claim spacing is good
- [ ] Long run identified by the biggest **single run**, not the biggest day total — a session day
      of 4 runs totalling 23 km must not be called the long run

**Niggle timing**
- [ ] Zero mentions in block → no division by zero, `good`
- [ ] A mention on a rest day that is also a low-sleep day counts in both categories
- [ ] Never returns `flag` under any input
- [ ] Verbatim word is surfaced; no numeric severity appears in any output string

---

## Done when

- All four cards render for every week in the block with no crash — walk all 13
- Week of 18 May shows three of four in `watch`; week of 20 July shows mostly `good`
- Week of 11 May shows polarisation as `flag`, not `good`, despite being 100 % easy
- With HRV nil, load-vs-recovery degrades to ACWR-only and never shows `flag`
- No niggle output anywhere contains a `/10`
- `CalendarPatterns.swift` has no `import SwiftUI`
- Nothing in this slice is wired to a notification, the coach, or a plan change
