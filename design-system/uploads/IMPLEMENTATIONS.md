# Implementations

Map of design system files → app implementations. Keep this current as
designs ship to web/iOS or drift apart from what's actually shipping.

If the answer to "where does this design live in the app?" can't be
read from this file, this file is out of date.

## Screens

| Design file | Web | iOS | Status |
|---|---|---|---|
| `home.v4.jsx` | `web/src/app/(public)/page.tsx` | — | live on web · marketing only (no iOS marketing surface) |
| `home.jsx` (alt v5 · data-forward) | — | — | designed only |
| `training-summary.jsx` | `web/src/app/design/training-summary/page.tsx` (preview) | `Training/TrainingDashboardView.swift` (closest match) | preview only on web · iOS predates this design |
| `plan.jsx` | — | spread across `Training/TrainingDashboardView`, `PlanTemplateListView`, `MonthCalendarView`, `WeekCalendarView`, `AdaptivePlanBuilderSheet` | not consolidated on iOS |
| `training-analysis.jsx` | — | `Analysis/AnalysisView.swift` | iOS implementation exists; parity not verified |
| `training-log.jsx` | — | `Workouts/HistoryView.swift` | iOS implementation exists; parity not verified |
| `workout-cards.jsx` (A/B/C/D) | — | `Workouts/WorkoutDetailPlate23.swift` (= direction A) | A on iOS as Plate 23; B/C/D not picked |
| `fitness-predictor.jsx` | — | **none** | **no iOS view exists yet** (only `FitnessPredictorService` backend) |
| `explorations/web/plan-builder/` (A/B/C) | — | n/a (web only) | direction not picked |

## ui_kits/ios_app/ → iOS Swift files

`ui_kits/ios_app/` is the pixel-faithful iOS reference set. Each file
maps to a Swift implementation:

| ui_kit file | iOS implementation | Parity verified? |
|---|---|---|
| `TodayScreen.jsx` | `App/TodayHomeView.swift` + `App/TodayPlate18.swift` | — |
| `TrainingScreen.jsx` | `Training/TrainingDashboardView.swift` | — |
| `WorkoutDetailScreen.jsx` | `Workouts/WorkoutDetailPlate23.swift` | — |
| `InjuriesScreen.jsx` | `Analysis/InjuryPlate28.swift` | — |
| `SignInScreen.jsx` | `Auth/SignInView.swift` | — |

## iOS-only (no design system .jsx)

These editorial plates ship on iOS but don't have a standalone .jsx in
this folder:

- `Training/DayDetailPlate22.swift` (Plate 22 · day detail sheet)

## Open

- **Fitness predictor** — designed (`fitness-predictor.jsx`), but no iOS view exists
- **Workout card directions** — A ships on iOS as Plate 23; B/C/D explored but not picked. Either confirm A is canonical or revisit
- **Plan builder directions** — 3 web-shaped directions in `explorations/web/plan-builder/`, no decision yet. Production route exists at `/coach-portal/plans/[id]/builder`
- **Parity checks** — none of the ui_kit ↔ iOS pairs above have been visually verified against the design. First pass would be the sign-in screen (often drifts) and the Training Dashboard (its iOS file predates the editorial plate naming)

## Keeping this current

- A design ships → fill in the Web or iOS column with the file path
- Visual parity checked → mark the "Parity verified?" column yes/no
- Drift spotted → add a brief note in the Status column
- Work starting → prefix the status with "→ in progress"
