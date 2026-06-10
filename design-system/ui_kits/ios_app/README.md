# Post Run Drip · iOS UI kit

A pixel-faithful recreation of the Post Run Drip iOS app — the "Plate 18" diary+cockpit direction documented in `my-running-app/design-system/`.

**This is a UI kit, not a production app.** Buttons fire, tabs switch, sheets open and close, but data is static. The job is to faithfully reproduce the visual language so designs that bolt onto it look correct.

## Run it

Open [`index.html`](./index.html) — a single-file static prototype that mounts the whole app inside an iOS device frame. `App.jsx` drives three stages: `signin → onboarding → app`. A dev switcher (top-right, outside the frame) jumps between them without code edits.

## Navigation

Two navigation surfaces:

- **A 5-tab footer** — `Log · Train · Trends · Coach · Runs` (defined in `Primitives.jsx` · `TabBar`, coral dot on active).
- **A global hamburger sidebar** (`AppSidebar`, top-left of every screen) — opens the secondary surfaces that aren't tabs: Goals, Pace Chart, Fitness Predictor, Training Analysis (jumps to the Trends tab), Injuries, Content Library, Settings, and Sign out.

> **Note — unresolved IA.** This kit's 5-tab + sidebar model does not match the shipping iOS app, which uses a 4-tab `DripTabBar` (`Log · Training · Coach · Plan`) with no Trends/Runs tab and no sidebar. The 5-vs-4 tab question and whether the sidebar belongs in the iOS IA are both open. See `outputs/ui-kit-install-2026-05-29.md` and `outputs/why-ios-design-parity-is-hard.md` before building nav.

## Tab screens (in nav order)

| Tab | Surface label | Component | Notes |
|---|---|---|---|
| **Log** | `LOG · v1 VOICE LOG` | [`LogScreen.jsx`](./LogScreen.jsx) | Today folded into Log — diary spine + cockpit. (Replaces the old `TodayScreen.jsx`.) |
| **Train** | `TRAINING · MARATHON BLOCK` | [`TrainingScreen.jsx`](./TrainingScreen.jsx) | Block summary, week strip (today in coral), pace × volume, recent log. See variations below. |
| **Trends** | `TRENDS · v1 ANALYTICS SURFACE` | [`TrendsScreen.jsx`](./TrendsScreen.jsx) | "The 5-second view." Stat tiles, 12-week fitness line, volume × ACWR bars; links into Workout detail and Injuries. |
| **Coach** | `COACH · CONVERSATION` | [`CoachScreen.jsx`](./CoachScreen.jsx) | "The base is taking." Coach conversation; the canonical coral-bar blockquote treatment. |
| **Runs** | `HISTORY · ALL RUNS` | [`RunsScreen.jsx`](./RunsScreen.jsx) | "Every run, indexed." All-runs index; tapping a run opens Workout detail. |

### Train tab variations (not yet narrowed to one)

[`TrainA.jsx`](./TrainA.jsx), [`TrainB.jsx`](./TrainB.jsx), [`TrainC.jsx`](./TrainC.jsx), and [`TrainingScreen.v1.jsx`](./TrainingScreen.v1.jsx) are alternative directions for the Train tab. [`Training - Variations.html`](./Training%20-%20Variations.html) previews them side by side. `TrainingScreen.jsx` is the current pick.

## Sheets & secondary screens

| Surface label | Component | Reached from |
|---|---|---|
| `PLAN · MARATHON BLOCK` | [`PlanScreen.jsx`](./PlanScreen.jsx) / `TrainingPlanSheet.jsx` | Train |
| `PLAN · DAY DETAIL · FIG. 22` | `DayDetailSheet` (`Sheets.jsx`) | Train / plan |
| `WORKOUT DETAIL · SHARPENED` | [`WorkoutDetailScreen.jsx`](./WorkoutDetailScreen.jsx) | Trends / Runs |
| `WORKOUT PICKER · LINK RUN` | `WorkoutPickerSheet` (`Sheets.jsx`) | Log |
| `MANUAL WORKOUT · ENTRY` | `ManualWorkoutSheet` (`Sheets.jsx`) | Runs |
| `JOURNAL · ENTRY DETAIL` | `HistoryDetailSheet` (`Sheets.jsx`) | Runs / Log |
| `INJURY · LIVING LOG` | [`InjuriesScreen.jsx`](./InjuriesScreen.jsx) | Sidebar |
| `INJURIES · ADD` | `AddInjurySheet` (`InjurySheets.jsx`) | Injuries |
| injury detail | `InjuryDetailSheet` (`InjurySheets.jsx`) | Injuries |
| `RACE PLAN · TARGET` | [`RacePlanScreen.jsx`](./RacePlanScreen.jsx) | Train |
| `WEEKLY REVIEW · FROM COACH` | [`WeeklyReviewScreen.jsx`](./WeeklyReviewScreen.jsx) | Coach |
| `SETTINGS` | `SettingsScreen` (`SettingsSheets.jsx`) | Sidebar |
| `GOALS · ACTIVE` | `GoalsScreen` (`SettingsSheets.jsx`) | Sidebar |
| `TARGETS · PACE CHART` | `PaceChartScreen` (`SettingsSheets.jsx`) | Sidebar |
| `TARGETS · FITNESS PREDICTOR` | `FitnessPredictorScreen` (`SettingsSheets.jsx`) | Sidebar |
| `LIBRARY · CONTENT` | `ContentLibraryScreen` (`SettingsSheets.jsx`) | Sidebar |
| `PROFILE · ATHLETE` | `AthleteProfileScreen` (`SettingsSheets.jsx`) | Sidebar |
| `DATA · BACKUP` | `BackupScreen` (`SettingsSheets.jsx`) | Settings |
| `DATA · EXPORT LOGS` | `ExportScreen` (`SettingsSheets.jsx`) | Settings |
| onboarding | [`OnboardingScreen.jsx`](./OnboardingScreen.jsx) | Sign-in → create account (goal: Half / Marathon / Ultra / General fitness) |
| sign-in | [`SignInScreen.jsx`](./SignInScreen.jsx) | App start (email + Apple, plus create-account path) |

Chart primitives for these surfaces live in [`charts-analytics.jsx`](./charts-analytics.jsx) and [`charts-data.jsx`](./charts-data.jsx) (`CombinedChart`, `SplitsChart`, `StackCharts`, `WorkoutTelemetry`, `workoutColor`). [`design-canvas.jsx`](./design-canvas.jsx) is the scratch canvas.

## Components

The shared primitives are factored out into [`Primitives.jsx`](./Primitives.jsx). Each is exposed on `window` for cross-file use:

- `PlateStrip` — top mono header (`RUNNING LOG · …` / `FIG. N · NEGATIVE SPLITS · 04.2026`)
- `Eyebrow`, `eyebrow--coral` — tracked uppercase section labels
- `EditorialRule` — `line · dot · line` divider
- `Hairline` — 1px rule
- `MoodPill`, `MoodRadio` — tracked capsules, with the 7-mood palette
- `StatTile` — white card numeral tile (the cockpit fundamental)
- `Section` — eyebrow + optional right-aligned eyebrow + children
- `TabBar` — 5-tab footer, coral dot on active
- `CoachQuote` — italic blockquote with the 2px coral left-bar (the *one* place coloured left-borders appear in the system)
- `LineChart`, `ZoneBar` — tiny inline SVG primitives for the cockpit charts
- `Toggle` — coral pill toggle

`tokens.css`, `Primitives.jsx`, and `ios-frame.jsx` are the unchanged foundations — every screen above is built from these and from the same color/type/spacing variables.

## Voice notes

- All headlines end in a period: `Marathon block.`, `The base is taking.`, `Every run, indexed.`
- All separators are middle-dot `·`. Never `|` or `/` between fields.
- All UPPERCASE labels are monospaced and tracked at +0.10em to +0.14em.
- Coach copy is in 2nd person, in italics, inside the coral-bar blockquote.
- Empty states state the absence then say what fills it.

## Caveats

- Icons substituted from Lucide (the iOS app uses Apple SF Symbols natively).
- The kit's nav model (5-tab + sidebar) is ahead of the shipping 4-tab iOS app — see the IA note under Navigation.
- The Train tab has multiple unresolved variations (A/B/C/v1).
- `RacePlanScreen` and the `AppSidebar` have no Swift equivalent yet; everything else maps to an existing surface (see `outputs/ui-kit-install-2026-05-29.md`).
- The status bar / device chrome comes from the shared `ios-frame.jsx` starter; it's iOS 26-style.
