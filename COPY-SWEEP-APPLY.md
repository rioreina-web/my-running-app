# Copy sweep: no terminal periods, Title Case on titles

Applied 7 Sep 2026 directly in the working tree, on `design/ds-sync`, on top of the
uncommitted changes already there. This is the code half of the standard rewritten in
`design-system/POST-RUN-DRIP-SYSTEM.md` §3 and `design-system/CLAUDE.md` the same day.

**56 string literals changed across 31 files.** Every change is a string literal —
no control flow, no view structure, no types. Not compiled: there is no xcodebuild in
the sandbox this ran in, so build before shipping.

Verify:

```
double-click build.command, then read build.log
```

---

## The rule being applied

1. **Nothing that names something takes a period** — workout and session titles,
   screen headlines, section titles. A title is a label, not a sentence.
2. **Screen and section titles are Title Case. Workout titles are not** — they name
   what the athlete did, in the units they did it in.
3. **Running prose keeps its punctuation** — the read, captions, body copy, error and
   empty-state text that runs to a second sentence, and the athlete's own words.

---

## A · Screen and section titles — Title Case, period off (23)

| File | Was | Now |
|---|---|---|
| `Workouts/LogWildView.swift` | `Text("Log your run.")` | `Text("Log Your Run")` |
| `Workouts/LogWildView.swift` | `Text("Write a note.")` | `Text("Write a Note")` |
| `Workouts/LogWildView.swift` | `Text("Note.")` | `Text("Note")` |
| `Workouts/WildWorkoutPickerSheet.swift` | `Text("Link a run.")` | `Text("Link a Run")` |
| `Workouts/WorkoutComparisonSheet.swift` | `Text("The whole run.")` | `Text("The Whole Run")` |
| `Workouts/WorkoutComparisonSheet.swift` | `lane(title: "Pace."` | `lane(title: "Pace"` |
| `Workouts/WorkoutComparisonSheet.swift` | `lane(title: "Heart rate."` | `lane(title: "Heart Rate"` |
| `Workouts/WorkoutComparisonSheet.swift` | `lane(title: "Elevation."` | `lane(title: "Elevation"` |
| `Week/WeekTabView.swift` | `Text("What's missing.")` | `Text("What's Missing")` |
| `Week/WeekTabView.swift` | `title: "Faster.",` | `title: "Faster",` |
| `Week/WeekTabView.swift` | `title: "Load and recovery.",` | `title: "Load and Recovery",` |
| `Week/WeekTabView.swift` | `title: "The marathon.",` | `title: "The Marathon",` |
| `Training/Analytics/TrainingTabView.swift` | `Text("Your training.")` | `Text("Your Training")` |
| `Training/Analytics/TrainingTabTwoView.swift` | `Text("Your training.")` | `Text("Your Training")` |
| `Analysis/FitnessPredictorView.swift` | `Text("Predicted times.")` | `Text("Predicted Times")` |
| `Analysis/FitnessPredictorView_Rebrand.swift` | `Text("Predicted times.")` | `Text("Predicted Times")` |
| `Trends/CompareDashboardCharts.swift` | `Text("Two sessions.")` | `Text("Two Sessions")` |
| `Coaching/CoachView.swift` | `Text("Ask anything.")` | `Text("Ask Anything")` |
| `ContentLibrary/ContentLibrarySidebar.swift` | `Text("Menu.")` | `Text("Menu")` |
| `App/OnboardingView.swift` | `title: "Voice memos.",` | `title: "Voice Memos",` |
| `App/OnboardingView.swift` | `title: "Pace, narrated.",` | `title: "Pace, Narrated",` |
| `App/OnboardingView.swift` | `title: "The Read tab.",` | `title: "The Read Tab",` |
| `Analysis/Tips/AskTipsView.swift` | `return "Four things."` | `return "Four Things"` |

## B · Display-set phrases and single-line empty states — period off, case kept (22)

These are set on a display font but are not names, so they lose the period and keep
their case. If any of them should be Title Case instead, they are the ones to argue about.

| File | Was | Now |
|---|---|---|
| `Analysis/FitnessPredictorView.swift` | `Text("No prediction yet.")` | `Text("No prediction yet")` |
| `Analysis/Tips/AskTipsView.swift` | `Text("Nothing worth flagging.")` | `Text("Nothing worth flagging")` |
| `Analysis/AskView.swift` | `Text("Why, and compared to what.")` | `Text("Why, and compared to what")` |
| `Analysis/SignalLabView.swift` | `Text("Five signals, one athlete.")` | `Text("Five signals, one athlete")` |
| `Analysis/InjuryView.swift` | `Text("No aches tracked.")` | `Text("No aches tracked")` |
| `Analysis/NiggleTimelineScreen.swift` | `Text("Nothing mentioned yet.")` | `Text("Nothing mentioned yet")` |
| `Analysis/TrainingAnalysisView.swift` | `Text("Where you actually run.")` | `Text("Where you actually run")` |
| `Analysis/Conditions/ConditionsView.swift` | `Text("Every session, with the weather in it.")` | `Text("Every session, with the weather in it")` |
| `Analysis/Conditions/ConditionsView.swift` | `title: "The sheet didn't load.",` | `title: "The sheet didn't load",` |
| `Analysis/Conditions/ConditionsView.swift` | `title: "Nothing here yet.",` | `title: "Nothing here yet",` |
| `App/TodayPlate18.swift` | `Text("Rest day.")` | `Text("Rest day")` |
| `App/InsightsView.swift` | `Text("Where you're trending.")` | `Text("Where you're trending")` |
| `App/DripEditorialPrimitives.swift` | `Text("The 5-second view.")` | `Text("The 5-second view")` |
| `App/HomeDayPager.swift` | `Text("Rest.")` | `Text("Rest")` |
| `App/SheetTabView.swift` | `Text("Every session.")` | `Text("Every session")` |
| `App/SheetTabView.swift` | `title: "Nothing matches \(subtitleFilterPhrase).",` | `title: "Nothing matches \(subtitleFilterPhrase)",` |
| `Trends/TrendsPaceBandsView.swift` | `Text("One band at a time.")` | `Text("One band at a time")` |
| `Trends/PaceSignalView.swift` | `Text("No runs logged.")` | `Text("No runs logged")` |
| `Trends/RacePredictionViews.swift` | `Text("Where the fitness points.")` | `Text("Where the fitness points")` |
| `Trends/TrendsDetailViews.swift` | `Text("First marks on the page.")` | `Text("First marks on the page")` |
| `Trends/TrendsBlockView.swift` | `Text("No weeks in this window.")` | `Text("No weeks in this window")` |
| `Trends/TrendsBlockView.swift` | `Text("Couldn't load your timeline.")` | `Text("Couldn't load your timeline")` |

## C · Generated title builders — the period comes out of the interpolation (11)

These matter most: they are the `headlineLine` / `titleLine` functions that build the
session name shown on Today, the day pager, the Week plate and the goal line. Changing
the view copy alone would not have fixed them.

| File | Was | Now |
|---|---|---|
| `Analysis/Tips/AskTipsView.swift` | `return goal.title.isEmpty ? "\(goal.timeLabel) \(goal.raceLabel)." : "\(goal.title)."` | `return goal.title.isEmpty ? "\(goal.timeLabel) \(goal.raceLabel)" : "\(goal.title)"` |
| `App/TodayPlate18.swift` | `return "\(typeName), \(DistanceFormat.string(miles: m, unit: unit))."` | `return "\(typeName), \(DistanceFormat.string(miles: m, unit: unit))"` |
| `App/TodayPlate18.swift` | `return "\(typeName)."` | `return "\(typeName)"` |
| `App/TodayPlate18.swift` | `return "\(name), \(str) mi."` | `return "\(name), \(str) mi"` |
| `App/TodayPlate18.swift` | `return "\(name)."` | `return "\(name)"` |
| `App/HomeDayPager.swift` | `guard session.miles > 0.05 else { return "\(name)." }` | `guard session.miles > 0.05 else { return "\(name)" }` |
| `App/HomeDayPager.swift` | `return "\(name), \(DistanceFormat.string(miles: session.miles, unit: unit))."` | `return "\(name), \(DistanceFormat.string(miles: session.miles, unit: unit))"` |
| `App/HomeDayPager.swift` | `return "\(monthFormatter.string(from: date)) \(ordinal)."` | `return "\(monthFormatter.string(from: date)) \(ordinal)"` |
| `App/TodayHomeView.swift` | `return "\(month) \(ordinal)."` | `return "\(month) \(ordinal)"` |
| `App/TodayHomeView.swift` | `return "Race day this week — \(f.string(from: raceDate))."` | `return "Race day this week — \(f.string(from: raceDate))"` |
| `Week/WeekService.swift` | `title: "Week of \(monthDay(weekStart)).",` | `title: "Week of \(monthDay(weekStart))",` |

---

## Deliberately left alone

| File | String | Why |
|---|---|---|
| `Shared/SettingsView.swift:1029` | `This can't be undone.` | A warning sentence, not a title. |
| `Coaching/Read/ReadProse.swift:287` | `The base is taking.` | Sample generated read prose, in a `#Preview`. |
| `Coaching/Read/ReadSectionsView.swift:241` | `A strong week — keep that achilles honest.` | Same. |
| `Analysis/Tips/TipEngine.swift` (5 headlines) | `Your easy days aren't easy.` etc. | Generated insight prose. Prose keeps its punctuation. |
| Multi-sentence empty and error states | `Today didn't load. Check your connection and try again.` | Sentences, and they run to two. |
| `web/src/.../journal-view.tsx:796` | `Delete this entry? This cannot be undone.` | Sentence. |
| `web/src/.../pace-chart-client.tsx:656` | `Conf.` | An abbreviation, not a title. |

## Still open

- **The edge functions were not touched.** `coaching-daily-read` and
  `generate-workout-insight` produce prose, which keeps its punctuation — but if either
  prompt ever asks the model for a *title*, that prompt needs the rule too.
- **`Week/WeekPreviewData.swift:37`** subtitle `No runs logged yet this week.` left as a
  subtitle sentence; change it if subtitles should follow the title rule.
