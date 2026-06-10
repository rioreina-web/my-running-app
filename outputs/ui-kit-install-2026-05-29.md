# UI kit install — 2026-05-29

Installed the expanded **Post Run Drip iOS UI kit** from `Downloads/ui_kits/ios_app`
into the repo at `design-system/ui_kits/ios_app/`. The previous kit is preserved
beside it as `design-system/ui_kits/ios_app.backup-20260529194421/`.

This was a **kit install only** — making the new designs the canonical in-repo
reference. No production Swift was changed. The kit is a static prototype
(buttons fire, sheets open, data is hard-coded) whose job is to fix the visual
language so downstream Swift work has something faithful to build against.

## What changed in the kit

The install is **purely additive on unchanged foundations**. `tokens.css`,
`Primitives.jsx`, and `ios-frame.jsx` are byte-identical to the old kit, so there
is no token or primitive migration — every new screen is built from the same
12 primitives and the same color/type/spacing variables.

What grew:

- **Trends, Coach, and Runs were promoted from inline placeholders to full
  screens.** In the old kit these lived as `TrendsPlaceholder` / `CoachPlaceholder`
  / `RunsPlaceholder` functions inside `App.jsx`. They are now
  `TrendsScreen.jsx`, `CoachScreen.jsx`, `RunsScreen.jsx`.
- **An onboarding flow was added.** `App.jsx` now has three stages —
  `signin → onboarding → app` — driving a new `OnboardingScreen.jsx`. Sign-in
  gained a "create account" path into it.
- **A global hamburger sidebar was added** (`AppSidebar`, used from `App.jsx`).
  This is a new navigation surface available on every screen, separate from the
  tab bar. See the IA flag below.
- **A large set of sheets landed**: day detail, workout picker, manual workout,
  history detail, add-injury, injury detail, training plan, settings, pace chart,
  fitness predictor, content library, athlete profile, goals, backup, export,
  race plan, weekly review. These live across `Sheets.jsx`, `SettingsSheets.jsx`,
  `InjurySheets.jsx`, `TrainingPlanSheet.jsx`, `RacePlanScreen.jsx`,
  `WeeklyReviewScreen.jsx`.
- **Training-screen variations** were added: `TrainA.jsx`, `TrainB.jsx`,
  `TrainC.jsx`, `TrainingScreen.v1.jsx`, plus `Training - Variations.html` and a
  reworked `TrainingScreen.jsx`. These are alternative directions for the Train
  tab — not yet narrowed to one.
- **Chart modules** were split out: `charts-analytics.jsx`, `charts-data.jsx`,
  `design-canvas.jsx`.
- **`TodayScreen.jsx` was removed** — Today is folded into `LogScreen.jsx`,
  consistent with the CLAUDE.md note that Today was removed and folded into Log.

Screens that changed but already existed in the kit: `App.jsx` (nav rewrite),
`SignInScreen.jsx` (create-account path), `InjuriesScreen.jsx`,
`TrainingScreen.jsx`, `WorkoutDetailScreen.jsx`, `index.html`.

## ⚠️ Flag — unresolved IA decision, now larger (not decided here)

You asked me to flag this rather than decide it. The kit embodies a **5-tab nav
(Log · Train · Trends · Coach · Runs)** plus a **global hamburger sidebar**. The
shipping iOS app uses a **4-tab `DripTabBar` (Log · Training · Coach · Plan)**
with no Trends or Runs tab and no sidebar.

So the install does not resolve the 5-tab-vs-4-tab question from CLAUDE.md
("Known IA mismatch") — it sharpens it. There are now **two** open IA questions:

1. Do Trends and Runs become real tabs (5-tab), or stay out (4-tab)?
2. Does the global hamburger sidebar become part of the iOS IA at all? The app
   has no equivalent today; adopting it is a navigation-model change, not a reskin.

Recommend resolving both before any Swift work touches navigation, per the
unblock plan in `outputs/why-ios-design-parity-is-hard.md`.

## Kit hygiene issue to fix

The kit's own `README.md` is **stale** — it still documents `TodayScreen.jsx`
(now deleted) and still describes Trends/Coach/Runs as inline placeholders in
`App.jsx` (now full screens). It also still claims a 5-tab `TabBar` without
mentioning the new sidebar. Worth a pass so the kit's README matches its
contents before anyone treats it as the spec.

## What SwiftUI implementation would take

Good news: this is **mostly a parity reskin, not greenfield.** Nearly every new
kit screen already has a Swift surface in `RunningLog/RunningLog/`. The work is
bringing those surfaces to the kit's visual language (and resolving the drift
already catalogued in `outputs/design-parity-audit-2026-05-20.md`), not building
screens from nothing.

| Kit screen / sheet | Existing Swift surface | Implementation note |
|---|---|---|
| `OnboardingScreen.jsx` | `App/OnboardingView.swift` | Reskin + wire the new signin→onboarding→app staging. |
| `LogScreen.jsx` | `App/LogView.swift`, `TodayHomeView.swift`, `TodayPlate18.swift` | Today is already folded into Log on iOS; align layout. |
| `TrainingScreen.jsx` + `TrainA/B/C` | `Training/TrainingTabView.swift` (+ many `Training/*`) | **Pick one variation first.** Training tab is the known-drifted surface. |
| `TrendsScreen.jsx` | `Trends/TrendsTabView.swift` | Surface exists but is thin; blocked on IA decision #1. |
| `CoachScreen.jsx` | `Coaching/CoachTabView.swift`, `CoachView.swift` | Coach client is itself unresolved (3 surfaces, none canonical). |
| `RunsScreen.jsx` | `Workouts/HistoryView.swift` | Blocked on IA decision #1 (is Runs a tab?). |
| `WorkoutDetailScreen.jsx` | `Workouts/WorkoutDetailPlate23.swift` | Reskin. |
| `InjuriesScreen.jsx` | `Analysis/InjuryPlate28.swift`, `InjuryView.swift` | "Niggles" surface — respect detection-not-diagnosis rules. |
| `InjurySheets.jsx` | `Analysis/AddInjurySheet.swift`, `InjuryDetailSheet.swift` | Reskin. |
| `WeeklyReviewScreen.jsx` | `Coaching/WeeklyCoachingReportSheet.swift` | Reskin. |
| `TrainingPlanSheet.jsx` | `Training/TrainingPlanView.swift` | Reskin. |
| `Sheets.jsx` (day detail) | `Training/DayDetailPlate22.swift`, `DayDetailSheet.swift` | Reskin. |
| `Sheets.jsx` (picker / manual / history detail) | `Workouts/WorkoutPickerSheet.swift`, `ManualWorkoutView.swift`, `HistoryDetailSheet.swift` | Reskin. |
| `SettingsSheets.jsx` (settings/pace/predictor/library/profile/goals/backup/export) | `Shared/SettingsView.swift`, `Workouts/PaceChartView.swift`, `Analysis/FitnessPredictorView.swift`, `ContentLibrary/`, `Shared/AthleteProfileView.swift`, `GoalsView.swift`, `BackupView.swift`, `ExportView.swift` | Reskin each. |
| `SignInScreen.jsx` | `Auth/SignInView.swift` | Add create-account path. |
| `AppSidebar` (hamburger) | **none** | Genuinely new nav element — blocked on IA decision #2. |
| `RacePlanScreen.jsx` | **none** (only `Models/RaceDistance.swift`) | Likely new build; confirm intent before scoping. |

So if/when you greenlight Swift work: two screens are genuinely new
(`AppSidebar`, `RacePlanScreen`) and gated on the IA calls; everything else is a
reskin of an existing view, sequenced behind (a) resolving the two IA questions,
(b) picking one Train variation, and (c) the coach-client decision.

## Verification

- `tokens.css` and `Primitives.jsx` confirmed byte-identical pre/post install.
- Installed directory confirmed an exact match to the source kit (31 files).
- Old kit backed up at `design-system/ui_kits/ios_app.backup-20260529194421/`.
