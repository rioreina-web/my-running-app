# Calendar — build plan

*Written 2026-07-28. Design reference: `calendar-month-prototype.html` (Month | Week toggle at the
top of the phone). Follows the repo's additive-new-files + minimal-tracked-edits convention — see
`APPLY-NOTES.md` and `SHARP-END-APPLY.md`.*

---

## The short version

**Most of this already exists.** The month calendar is an upgrade to a shipped component, not a new
build. The genuinely new work is the week view, the day-level pace breakdown, and the pattern cards.
Sleep and HRV are blocked on work you have already written but not applied.

Rough shape of the effort, in slices you can ship one at a time:

| Slice | What it is | New code | Blocked by |
|---|---|---|---|
| **0** | Decide the pace-zone contract | none — a decision | nothing |
| **1** | Day-level pace zones, server side | 1 edge function + tests | slice 0 |
| **2** | Month grid upgrade | 2 Swift files, 1 tracked edit | slice 1 |
| **3** | Week rows view | 3 Swift files, 1 tracked edit | slice 1 |
| **4** | Pattern cards | 2 Swift files + tests | slice 3 |
| **5** | Sleep + HRV | small | `VITAL-GARMIN-APPLY-NOTES.md` |

Slices 2 and 3 are independent of each other. Either can ship alone.

---

## What already exists — do not rebuild any of this

### iOS

| Thing | Where | What it gives you |
|---|---|---|
| Per-day rollup | `Training/Analytics/TrainingAnalyticsViewModel.swift` | `DayCell`, `GridWeek`, `DayVolume`, `DaySummary`, `ZoneSplit`, and the API `dayVolumes()`, `gridWeeks()`, `sessions(on:)`, `daySummary(_:)`, `mood(on:)` |
| A working calendar | `Training/Analytics/TrainingCalendarSection.swift` | Per-day mileage, intensity-coloured pace chip, session label, ambient mood dot, tap → day sheet. Already shared by two tabs so they can't drift. |
| Day detail sheet | `Training/Analytics/DayAnalysisSheet.swift` | Already has a **BY PACE ZONE** strip (3 buckets — see slice 0) |
| Calendar scope | `Training/Analytics/TrainingTabView.swift` | `enum TrainMode { current, calendar, history }` and a `WEEK · MONTH · BLOCK` `scopeToggle` — the Month/Week segment already has a home |
| Day + mood + niggle + ACWR fused | `Trends/SignalService.swift` | `SignalDay { date, comp, mood, niggles, niggleLabel, paceBuckets, miles }` over 400 days, plus a client ACWR array |
| Week strip primitive | `App/DripEditorialPrimitives.swift:402` | `DripWeekStrip` / `DripWeekDay` / `DripDayState`, already ported from the design system CSS |
| Zone weights | `Trends/TrendsQualityLoad.swift` | `TrendsZoneWeight.table` (10 zones), `QualityLoad.floor = 25`, pinned by `TrendsQualityLoadTests` |

### Backend

| Thing | Where | What it gives you |
|---|---|---|
| Canonical zone model | `supabase/functions/_shared/workoutSegmentation.ts` | `paceToZone(paceSecPerMile, anchors)`, `buildZoneAnchors`, `segmentFromLaps`, `coalesceReps` |
| Canonical "quality" | `supabase/functions/_shared/quality-volume.ts` | `isQualityPace`, `ZoneTable`, `MP_TOLERANCE`. Read its docblock before touching anything here. |
| Per-lap data | `running_workout_laps` | `avg_pace_sec_per_mile`, `heat_adjusted_pace_sec_per_mile`, `is_rest`, `avg_heart_rate`, indexed on `(user_id, avg_pace_sec_per_mile) WHERE is_rest = false` |
| Weekly rollups | `supabase/functions/trends-timeline/` | `week_start, miles, quality_miles, key_pace_sec, mood, niggles[], voice_quote` + `dominantMood` + `distinctNiggleLabels` |
| ACWR | `athlete_state` + `_shared/builders/buildLoadMetrics.ts` | `acwr`, `rolling_7d_miles`, `rolling_28d_miles` |
| Niggles | `body_mentions` | `body_area, side, verbatim_quote, severity_hint, mentioned_at` |
| Mood vocabulary | `process-training-memo/index.ts:66` | `["energized","positive","neutral","tired","struggling","injured"]` |

### Web

`web/src/components/train/train-calendar.tsx` — a month grid with `CalendarEntry { date, loggedMiles,
zone, plannedType, plannedMiles, plannedCompleted }`, wired at `train/page.tsx:331`. There is no week
detail view. **Web is out of scope for slices 1–4** and should follow iOS once the shapes settle.

---

## Slice 0 — settle the pace-zone contract *(do this first, it is a decision not a build)*

You currently have **two pace-zone models that disagree**, and the calendar needs one.

**Model A — server, 10 zones.** `_shared/workoutSegmentation.ts` → `paceToZone` against
`athlete_state.pace_zones`, anchored on race pace. Weights in `TrendsZoneWeight.table`
(recovery, easy, moderate, steady, mp, hmp, 10k, 5k, 3k, mile). This is what Trends, quality volume,
key-session detection and the coach all use.

**Model B — client, 3 buckets.** `TrainingAnalyticsViewModel.split(for:)` at line 686 builds
`ZoneSplit { easy, aerobic, threshold }` on-device from `training_logs.pace_segments`, falling back
to the run's average pace. This is what the Train tab and `DayAnalysisSheet`'s BY PACE ZONE strip
show today.

Three problems with leaving it:

1. `PaceZonesEngine.swift` states outright that *"there is no on-device pace math."* Model B is
   on-device pace math. The comment and the code disagree.
2. `quality-volume.ts` warns that `pace_segments`' `effort` label is untrustworthy because it is
   relative to each run's own mean. Model B reads that table (it does use measured pace rather than
   the label, which is better, but it is still a second source).
3. Three buckets cannot render the prototype. The design needs at least the six bands your zone data
   actually supports.

**Recommendation: retire model B.** Have the server return day-level zone volume and let
`ZoneSplit` become a view of it. That is what slice 1 does.

**Also settle: six bands or ten?** `athlete_state.pace_zones` produces five boundaries, so six
reachable bands. The published spectrum in `pace-spectrum-mockup.html` has ten stops — four of them
can never be reached by a logged run. Either the zone engine gets finer or the spectrum drops to six.
The prototype assumes **six**, named for a race pace that actually falls inside each band.

> **Nothing else in this plan can be built correctly until this is decided.** It is a ten-minute
> conversation, not a task.

---

## Slice 1 — day-level pace zones *(server)*

New edge function `calendar-days`. Reads `training_logs` + `running_workout_laps` + `body_mentions`,
returns one row per calendar day with zone volume at the model-A resolution. See
`CALENDAR-1-DAY-ZONES-APPLY.md`.

**Why server, not client:** the laps table is where sub-workout resolution lives, the zone anchors
live in `athlete_state`, and `paceToZone` is already written and tested. Doing it on-device would
mean a third zone model.

---

## Slice 2 — month grid

Upgrade `TrainingCalendarSection` to the prototype's encoding: bar height = volume, bar fill =
session type, bottom edge = mood, left edge = niggle, plus a week-total rail column. See
`CALENDAR-2-MONTH-APPLY.md`.

---

## Slice 3 — week rows

New view. Seven rows, each carrying session name, volume, pace-zone bar, pace, time, climb, sleep,
HRV and a niggle word. Plus the Month | Week segment. See `CALENDAR-3-WEEK-APPLY.md`.

---

## Slice 4 — pattern cards

Four computed cards — polarisation, load vs recovery, session spacing, niggle timing — each opening
to its evidence. Pure functions over the slice-1 payload, so they are unit-testable without a view.
See `CALENDAR-4-PATTERNS-APPLY.md`.

---

## Slice 5 — sleep and HRV *(blocked)*

`VITAL-GARMIN-APPLY-NOTES.md` is written but not applied, and `VitalManager.vitalRequest` is still a
stub returning `nil`. Until that lands there is no sleep or HRV anywhere in the app.

When it does land, the shapes to store are Vital/Junction's: `duration_s`, `efficiency`,
`hrv_rmssd`, `resting_hr`. The prototype computes baselines as **28-day trailing means** so a
delta is measured against the athlete rather than a population — keep that.

**Until then:** slices 3 and 4 must degrade gracefully. The week rows drop the sleep/HRV chips, the
recovery chart shows an empty state, and the load-vs-recovery card falls back to ACWR alone. Build it
that way from the start rather than retrofitting.

---

## Risks and open decisions

**Touch targets.** Month cells are 42 × 62 px in the prototype — under the 44 px minimum on width.
Either the row grows and the grid scrolls, or the tap target extends into the 2 px gutter. Decide in
slice 2; the prototype notes lean toward the latter.

**Pattern thresholds are guesses.** 78 % easy, ACWR 1.08, HRV −4. They are tuned against one
athlete's twelve weeks. Ship the cards as descriptive ("HRV averaged 67 against a baseline of 71.6")
and do not turn any of them into a nudge or a notification until they are calibrated against more
people. A wrong nudge about injury risk is worse than no nudge.

**Niggle language.** `InjuryModels.swift` is explicit that niggle severity is a **verbatim word**
(`severity_hint`) and that the 1–10 score exists for sorting only, never display. The prototype
shows `2/10` in one place. That is wrong and should show the word. Detection, not diagnosis.

**iOS is not in CI.** `.github/workflows/ci.yml` covers edge functions (57 Deno test files), web, and
the ML service. `RunningLogTests/` has 11 test files against 246 sources. That is why slices 1 and 4
put their logic in testable places — Deno for slice 1, pure functions for slice 4 — rather than
inside views.

**Web will drift.** `web/src/lib/run-metrics.ts` already duplicates Deno `_shared` logic, guarded by
`_shared/cross-language-pace-contract.test.ts`. If the calendar ships on iOS only, add the day-zone
shape to that contract test before building the web version.

---

## Suggested order

1. **Slice 0** — decide. Ten minutes.
2. **Slice 1** — server. Ships invisibly, nothing in the UI changes, fully covered by Deno tests.
3. **Slice 2 or 3** — whichever you want to look at sooner. They do not depend on each other.
4. **Slice 4** — patterns, once the week view exists to host them.
5. **Slice 5** — when Vital lands.

Each slice is a separate session. Do not run them together; the whole point of the convention is
that each one reverts cleanly on its own.
