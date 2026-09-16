# Brief for Fable — fold the analytical cards into Training Analysis

**Date:** 2026-06-13
**Decision:** Drop the standalone "model of you / The Read" Coach screen. The
new analytical content (workouts & reps, load & balance, fitness range,
weather-adjusted splits, niggles) belongs **inside the existing Training
Analysis feature** — that surface is the right home and the team likes it. The
daily Read stays as-is.

---

## 1. Reframe

We prototyped a new Coach surface ("What I know about you / The model of you").
It read as a creepy surveillance page and duplicates a surface we don't want.
**Reframe:** these are *analysis* features, not a new coach persona. Surface
them as cards/sections in **Training Analysis** (`Analysis/TrainingAnalysisView.swift`,
the Training tab), alongside what's already there.

Keep:
- The daily Read (`Coaching/Read/CoachReadView.swift`) unchanged on the Coach tab.
- Training Analysis as the home for the analytical cards.

## 2. Revert the Coach-tab experiment

`App/RunningLogApp.swift` (~line 122) was changed to render `ModelOfYouView()`
on tab 2. **Revert it to `CoachReadView()`:**

```swift
// Tab 2 — Coach
NavigationStack { CoachReadView() }
```

Do **not** delete the new files — we're harvesting them (next section).

## 3. What to fold into Training Analysis

The components already exist; relocate/adapt them as sections in
`TrainingAnalysisView` rather than rebuilding:

| Source (already written) | Becomes (in Training Analysis) |
|---|---|
| `Coaching/ModelOfYou/ModelOfYouState.swift` | **Reuse as-is** — the `athlete_state` model + `fetch()`. It's the data layer for all the cards. (Already debugged: `recovery_read` is a struct, ranges is `[String: RaceRange]`, etc.) |
| `MOYCard` + `workoutsCard` in `ModelOfYouView.swift` | **Workouts & reps** section — recent classified sessions (`9×1K @ 5:08 (5K)`, threshold, tempo) from `execution[]`. The headline analytical win. |
| `loadCard` | **Load & balance** — volume×intensity trend, hard/easy split, recovery read. The ACWR replacement. |
| `fitnessCard` | **Fitness** — race-anchored range + confidence. |
| `watchingCard` | **Niggles / wear & tear** — detection-not-diagnosis. |
| `cantSeeCard` | Optional "what I can't see" honesty footer. |

Then **delete** `ModelOfYouView.swift`'s screen scaffold (header, empty state,
`#Preview`) once the cards are moved; keep the card structs.

## 4. THE HEADLINE FEATURE — per-workout rep visualization (wire this everywhere)

**The product priority: every workout features its own detail visualization.**
This is the thing that proves we now *see* interval sessions. It is fully
connectable today — no new endpoint, no TrainingLog→RunningWorkout bridge.

### It connects directly — here's why

`running_workout_laps` is rep-level, keyed by `workout_id` **= the
`training_logs.id`**, and has a user-scoped RLS SELECT policy
(`rls_workout_laps_select: user_id = auth.uid()`). So from any workout row the
app already has the id for, it can fetch that workout's reps directly:

```swift
struct WorkoutLap: Decodable {
    var lap_index: Int?
    var distance_meters: Double?
    var moving_time_seconds: Int?
    var avg_pace_sec_per_mile: Double?
    var avg_heart_rate: Int?
    var is_rest: Bool?
    var temp_f: Double?
    var dew_point_f: Double?
    var heat_adjustment_pct: Double?            // FRACTION (0.019 = 1.9%) — ×100 to display
    var heat_adjusted_pace_sec_per_mile: Double?
}

static func fetch(workoutId: UUID) async -> [WorkoutLap] {
    (try? await supabase
        .from("running_workout_laps")
        .select("lap_index,distance_meters,moving_time_seconds,avg_pace_sec_per_mile,avg_heart_rate,is_rest,temp_f,dew_point_f,heat_adjustment_pct,heat_adjusted_pace_sec_per_mile")
        .eq("workout_id", value: workoutId.uuidString)
        .order("lap_index", ascending: true)
        .execute().value) ?? []
}
```

That's the whole data layer. (The old note that "the rich pace chart is gated
on the TrainingLog→RunningWorkout bridge" — in `CoachReadView`'s lightweight
sheet — is **moot**: laps key off the training-log id directly.)

### What to build — `WorkoutRepChart` (one reusable view)

Design source: `outputs/workout-detail-viz.html` (rep-by-rep) +
`outputs/weather-adjustment-viz.html` (heat toggle). Render, in Post Run Drip:

- **Rep bars** — one bar per work lap (skip `is_rest` laps), height = how fast
  (faster = taller). Label each with its pace. Group/title from
  `workout_features.workout_structure` ("9×1K @ 5:08 (5K)").
- **Pace-zone reference lines** — dashed lines at the athlete's 5K / 10K /
  threshold paces (from `athlete_state.pace_zones`) so reps read against zones.
- **HR overlay** — a line + dots across the reps (`avg_heart_rate`), showing
  drift.
- **Rest markers** — thin connectors between reps showing recovery (~Ns).
- **Stat row** — avg work pace, work volume, avg/max HR, rep spread.
- **Heat chip = toggle, default OFF** — quiet one-line warning ("Hot & humid —
  67°F, 67° dew"); tap reveals each rep's cool-air-equivalent (dashed markers,
  ~6 s/mi quicker) using `heat_adjusted_pace_sec_per_mile` (or
  `heat_adjustment_pct × 100`). Never overwrites recorded pace.
- **Non-rep runs** (easy/long, no reps) — degrade gracefully to a simple
  splits/HR summary, not an empty rep chart.

### Where to wire it (everywhere a workout is shown)

Make `WorkoutRepChart` the body of the canonical workout detail and route every
workout tap to it:

- `Workouts/WorkoutDetailView.swift` / `Workouts/WorkoutDetailPlate23.swift` —
  the canonical detail screen. Embed the chart here.
- The **Log** journal rows → tap → this detail.
- **Training Analysis** "Workouts & reps" section (§3) → tap a session → this detail.
- Replace `CoachReadView`'s lightweight `workoutDetailSheet` with this real view.

One reusable chart, one fetch, presented from every entry point.

## 4b. BLOCKER — lap ingestion has no ongoing writer (fix before shipping)

The per-workout viz (§4) and all split evaluation read `running_workout_laps`.
That table is populated **only by a one-shot backfill** inside its create
migration (`20260528222123_create_running_workout_laps.sql`, lines 94–139) —
a single `INSERT…SELECT` from `training_logs.external_streams.laps`. **There is
no trigger and no sync step that writes new lap rows.** So every workout after
the backfill's cutoff (~May 21) had zero laps and was invisible to detection —
this is why "every Tuesday" workout stopped registering.

The raw data is fine: Strava sync stores each activity's laps in
`external_streams.laps` (verified — June workouts all have them). Nothing parses
them onward.

**Required fixes:**
1. **Ongoing writer** — a `BEFORE/AFTER INSERT OR UPDATE` trigger on
   `training_logs` (or a step in `compute-workout-features`) that flattens
   `external_streams.laps` into `running_workout_laps`. Reuse the migration's
   parse, but **cast ints through numeric** (`(lap->>'moving_time')::numeric::int`)
   — Strava sends decimals where the original migration assumed integers
   (`invalid input syntax for type integer: "125.6"`), which would crash a naive
   trigger.
2. **One-time global re-backfill** for the May 22 → present gap (same parse).
   (Already done manually for the golden athlete `03857bf3` so the feature can
   be demoed today; other users still need it.)

Until #1 ships, the headline feature silently rots for every new run.

## 5. Data contract (all live as of today)

- Read `athlete_state` **directly** — it has a `Users read own athlete state`
  RLS SELECT policy, so the auth'd client is user-scoped. Pattern:
  `supabase.from("athlete_state").select(...).limit(1).execute().value`
  (see `ModelOfYouState.fetch()` and `Analysis/TrendsAthleteState.swift`).
- Property names are **snake_case to match the JSON** (the decoder is not
  convertFromSnakeCase). Gotcha already hit: `load_distribution.recovery_read`
  is an object `{down_week, hard_sessions_28d, avg_days_between_hard}`, not a
  string. `fitness_prediction.ranges` is `[String: {low, high, point}]`.
- Backend is **done and live**: WS1 lap-first workout classifier
  (`_shared/workoutSegmentation.ts`), WS2 heat unit fix, WS3 load story, WS4
  fitness ranges, WS7 dedup. So the data these cards read is correct.

## 6. Guardrails (unchanged)

- **Post Run Drip** — `Color.drip.*`, `.dripDisplay/.dripStat/.dripBody/.dripCaption`,
  `DripBackground()`. Warm paper, ink, one coral accent. No em-dash empty states.
- **Range + confidence**, never a single predicted time.
- **Niggles surfaced verbatim, never diagnosed.**
- **No surveillance framing** — these are "training analysis," not "what I know
  about you." Section headers should read like analytics, not a dossier.

## 7. Acceptance

- Training Analysis shows the new sections on real data: the user's interval
  sessions appear as quality work (not "easy"), load reads as a trend, fitness
  shows a range, niggles surface.
- Tapping a workout opens the rep-by-rep view with the heat toggle.
- Coach tab is back to the unchanged daily Read.
- Nothing reads as creepy; framing is analytical.

## 9. Trends layer — days AND trends (equal weight)

A specific workout day is the entry point; the **trend over time is the
through-line**. A coach reads ~8–12 weeks of recent detail, 6–12 months of
pattern, and 2–3 years of profile — not 14 days. Build the trends below; each
one **taps through to the specific day** behind it (trend point → workout rep
view from §4). Deterministic code computes the series; the model only narrates.

Windows: recent detail **8–12 wk** · pattern detection **6–12 mo** · baselines/
profile **2–3 yr**.

| Trend | What it answers | Source (mostly already computed) | Chart |
|---|---|---|---|
| **Workout progression by type** | "Are my Tuesday 1K reps getting faster at the same HR?" | `workout_features` + `running_workout_laps` grouped by `workout_type` over time | rep-pace line per recurring session; overlay HR |
| **Time-at-quality-pace / week** | "Am I actually doing enough quality?" | `workout_features.threshold_seconds + hard_seconds` weekly | weekly bars, 8–12 wk |
| **Intensity-weighted load** (ACWR replacement) | "Building, holding, spiking, backing off?" | weekly `volume_x_intensity` vs 8-wk chronic (`load_distribution`, WS3) | line + chronic band |
| **Hard/easy distribution drift** | "Is my polarization holding (~80% easy)?" | weekly `zone_pct` | stacked area, easy share line |
| **Aerobic efficiency / decoupling** | "Is my easy pace at a given HR improving?" | `workout_features.hr_pace_efficiency`, easy-run HR-at-pace | line over months |
| **Pace drift by zone** | "Is easy pace creeping (overreach tell)?" | weekly avg easy pace | line w/ band |
| **Fitness trajectory** | "Where's my fitness vs last cycle / goal?" | `fitness_snapshots` history (29 on file) + `confirmed_races` anchors | race-anchored fitness curve, race markers — range+confidence, never a point |
| **Niggle recurrence (12 mo)** | "Is this knee a pattern?" | `body_mentions` / `athlete_state.niggle_recurrence` | per-body-part timeline of dots |
| **Block-over-block (28-day rollups)** | "How does this block compare to my last 6?" | `athlete_state.recent_blocks` (already computed: miles, quality count, mood, easy pace) | small-multiples / delta row |

Notes:
- Most series are cheap: `athlete_state` already holds `recent_blocks`,
  `niggle_recurrence`, `load_distribution`, `fitness_prediction`;
  `workout_features` carries per-workout + rolling aggregates;
  `fitness_snapshots` holds the fitness history. The trends layer is mostly
  **surfacing + a few weekly GROUP BYs**, not new computation.
- **Link days ⇄ trends:** every trend point opens the underlying workout (§4),
  and the workout view shows "vs. your last N of this type." One graph, one tap,
  the specific session.
- Guardrails unchanged: observation vs. judgment kept separate (trend line =
  computed; the read on it = model), range+confidence on fitness, niggles
  surfaced not diagnosed.

## 8. Files

- Reuse: `Coaching/ModelOfYou/ModelOfYouState.swift`
- Harvest cards from: `Coaching/ModelOfYou/ModelOfYouView.swift` (then remove the screen)
- Revert: `App/RunningLogApp.swift` tab 2 → `CoachReadView()`
- Extend: `Analysis/TrainingAnalysisView.swift`
- Design intent: `outputs/workout-detail-viz.html`, `outputs/weather-adjustment-viz.html`, `outputs/model-of-you-mock.html` (cards only — ignore the page framing)
