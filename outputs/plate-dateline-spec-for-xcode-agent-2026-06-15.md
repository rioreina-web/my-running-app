# Plate dateline — replace fake "FIG. NN" with a goal countdown (Xcode spec)

## Why

The plate strip's trailing slot printed a hardcoded magazine figure number
("FIG. 09", "FIG. 23" …). It's figure-9-of-nothing — decoration pretending to
be information, and it reads as generated filler. Replace it with a real
*training dateline*: a countdown to the runner's goal race when one exists,
otherwise **nothing**. (Decision: goal-or-nothing. No block-week fallback, no
placeholder.)

## Already done (data/logic side — committed)

- `RunningLog/App/TrainingDateline.swift` — pure formatter. `TrainingDateline
  .string(for: UserGoal?) -> String?` returns e.g. `"BERLIN −86D"`,
  `"MARATHON −17W"`, `"HALF · TODAY"`, or `nil` (no goal / past goal). Label
  derivation validated against freeform titles (Berlin Marathon→BERLIN, "Run a
  10K"→10K, "my big race"→GOAL, etc.).
- `RunningLog/App/DesignSystem.swift` — `PlateStrip.fig` is now `String?`
  (default nil → trailing slot renders nothing). Back-compatible.
- `DripPlateStrip.trailingTop` was already `String?`.

## What's left (SwiftUI — your part)

### 1. A shared active-goal source

Add a tiny store so every plate can read the same soonest upcoming goal without
each screen re-fetching. Mirror the existing fetch in `Shared/GoalsView.swift`
(`from("user_goals").select().order("target_date")`).

```swift
@MainActor @Observable final class ActiveGoalStore {
    private(set) var soonest: UserGoal?
    func refresh() async {
        // soonest active goal with target_date >= today; nil if none
    }
}
```

Create once at app root, inject via `.environment(...)`, call `refresh()` on
launch and after the goal is edited (the EditGoal/AddGoal flows in GoalsView).
A screen reads it with `@Environment(ActiveGoalStore.self) private var goals`.

### 2. Swap the literal at each call site

Pass `TrainingDateline.string(for: goals.soonest)` into the trailing slot.
Because both primitives accept nil, no-goal automatically renders nothing.

| File | Line | Change |
|---|---|---|
| `Training/Analytics/TrainingTabView.swift` | ~64 | `fig: "FIG. 1"` → `fig: TrainingDateline.string(for: goals.soonest)` |
| `Analysis/TrainingAnalysisView.swift` | ~66 | `fig: "FIG. 7"` → dateline |
| `App/TodayHomeView.swift` | ~55 | `fig: "FIG. 18"` → dateline |
| `Analysis/InjuryView.swift` | ~16 | `fig: "FIG. 28"` → dateline |
| `Workouts/VitalWorkoutDetailView.swift` | ~60 | `fig: "FIG. 23"` → dateline |
| `Analysis/FitnessPredictorView_Rebrand.swift` | ~188 | `fig: "FIG. 29"` → dateline |
| `Workouts/VoiceLogView.swift` | ~51 | `trailingTop: "FIG. 09"` → `trailingTop: TrainingDateline.string(for: goals.soonest)` |
| `Analysis/FitnessPredictorView.swift` | ~50 | `trailingTop: "FIG. 29"` → dateline |
| `Workouts/WorkoutAnalystView.swift` | ~82 | DripPlateStrip `trailingTop:` → dateline |
| `Workouts/HistoryDetailSheet+Editorial.swift` | ~55 | DripPlateStrip `trailingTop:` → dateline |
| `Coaching/Read/CoachReadView.swift` | ~194 | `Text("FIG. 14")` → render `TrainingDateline.string(for:)` if non-nil, else drop the Text |

### 3. Verify

Build + run. Two states to eyeball:
- **Goal set** (Maya has a BQ goal): every plate shows the same `… −NND` line.
- **No goal**: the trailing slot is empty on every plate (no leftover "FIG.").

## Out of scope (optional follow-up)

The left-hand `surface` suffixes are the same affectation on the other side —
`· SHARPENED`, `v1 DIARY + CHARTS`, `v1 VOICE LOG`, `LIVING LOG`. Worth trimming
to plain surface labels in a later pass, but not part of "goal or nothing."
