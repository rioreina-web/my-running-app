# The Conditions — install into the iOS app

Four new files, three small edits to files that already exist, and a row in
Settings. Nothing else in the app changes.

**I could not compile this.** There is no Xcode in the environment I built it
in, so treat the first build as the real review. The three places most likely to
need a nudge are called out at the bottom under *If it doesn't build*.

---

## The good news, before you start

Everything this feature needs is **already in your database**. I checked before
writing a line:

| What | Where it already lives | Coverage, last 8 weeks |
|---|---|---|
| Temperature + dew point | `training_logs.weather_actual` | 90 of 91 rows |
| **Heat pace penalty, already computed** | `weather_actual.adjustment_pct` | 90 of 91 rows |
| Splits with heart rate | `training_logs.pace_segments` | 82 of 91 rows |
| The workout you described | `training_logs.workout_notes` | 14 of 91 rows |
| Felt RPE | `training_logs.felt_rpe` | 19 of 91 rows |

So there is **no new backend work, no migration, and no third-party service**.
`fetch-workout-weather` is already writing the temperature, the dew point *and*
the pace penalty on every synced run. The app simply never read them.

That also settles a design question: the client does **not** recompute the heat
adjustment. Two heat models that disagree by a tenth of a percent is a bug
report waiting to happen, so the screen displays `adjustment_pct` as the server
wrote it.

---

## Step 1 · Add the four new files

Create a folder `RunningLog/RunningLog/Analysis/Conditions/` and put these in it:

- `ConditionsSession.swift` — the session rollup and the heat model
- `ConditionsView.swift` — the screen
- `ConditionsExport.swift` — builds the five-tab workbook
- `ConditionsWorkbook.swift` — the `.xlsx` writer

In Xcode: right-click the `Analysis` group → **Add Files to "RunningLog"** →
select the folder → make sure **Copy items if needed** is ticked and the
**RunningLog** target is checked.

---

## Step 2 · Let the app fetch the three columns it already has

**File:** `RunningLog/RunningLog/Models/TrainingLog.swift`

Find `static let columns` (around line 139). It currently ends `parsed_structure, title`.
Add three column names. This is the whole edit:

```swift
    static let columns = """
        id, created_at, audio_url, notes, cleaned_notes, mood, workout_date, \
        workout_distance_miles, workout_duration_minutes, processing_status, \
        processing_error, processing_attempts, transcript_url, coach_insight, \
        workout_notes, workout_pace_per_mile, workout_type, source, \
        vital_workout_id, pace_segments, parsed_structure, title, \
        weather_actual, felt_rpe
        """
```

Note the `\` continuation at the end of the `title,` line — it has to be there
or the string breaks. And keep using this constant: a bare `.select()` drags the
`external_streams` blob (~2 MB per run) over the wire, which is PERF-AUDIT
finding #1.

---

## Step 3 · Decode them onto the row

**File:** `RunningLog/RunningLog/App/TodayHomeView.swift`

Find `struct TodayLogRow: Codable` (around line 429).

**3a.** Just after the `let parsed: ParsedLite?` line, add:

```swift
    /// Temperature, dew point and the server-computed heat penalty, written by
    /// `fetch-workout-weather` at sync time. Present on ~99% of GPS rows and
    /// absent on treadmill and hand-entered ones, which is exactly the
    /// distinction the Conditions screen needs.
    let weather: RunWeather?
    /// Athlete-reported effort, extracted from the voice memo.
    let feltRPE: Int?
    /// The workout as the athlete described it into the memo. The only record
    /// of intent in the system: `scheduled_workouts` has no rows.
    let workoutNotes: String?
```

**3b.** In the `private enum CodingKeys` block just below, add three cases
before the closing brace:

```swift
        case weather = "weather_actual"
        case feltRPE = "felt_rpe"
        case workoutNotes = "workout_notes"
```

That is all. `TodayLogRow` has no custom `init(from:)`, so the synthesised one
picks these up, and every field is Optional so old cached rows still decode.

> **One thing to watch:** `TrainingLogStore` snapshots these rows to disk. After
> this change the cached JSON is a version behind, and because the new fields
> are Optional it will decode fine but come back with `weather: nil` until the
> next refresh. The screen calls `refresh` on appear, so it self-heals on first
> open. No cache-busting needed.

---

## Step 4 · Add the row to Settings

**File:** `RunningLog/RunningLog/Shared/SettingsView.swift`

**4a.** Near the other `@State private var showX = false` declarations at the
top of the struct, add:

```swift
    @State private var showConditions = false
```

**4b.** In the same section that holds **Backup All Data** (around line 615),
add this `Button` — it copies that row's shape exactly, so it will look native:

```swift
Divider().padding(.leading, 16)

Button {
    showConditions = true
} label: {
    HStack {
        Image(systemName: "tablecells")
            .font(.system(size: 16))
            .foregroundStyle(Color.drip.coral)
        VStack(alignment: .leading, spacing: 2) {
            Text("The Conditions")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Every session with its splits, heart rate and weather")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
        }
        Spacer()
        Image(systemName: "chevron.right")
            .font(.system(size: 12))
            .foregroundStyle(Color.drip.textTertiary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
}
```

**4c.** Alongside the other `.sheet` modifiers on the `NavigationStack` (around
line 107), add:

```swift
.sheet(isPresented: $showConditions) {
    NavigationStack { ConditionsView() }
}
```

The `NavigationStack` wrapper is what gives the screen its title bar and the
share button in the top right.

---

## Step 5 · Build and check

Open Settings, tap **The Conditions**. You should see:

1. Every session in the last 8 weeks, easy runs included, newest first.
2. A row reading something like `HR 149   10× fast   HR 164   78° · dew 75° · · ·   cool 6:46`.
3. Tapping a workout row opens **As you called it** (your voice memo's plan),
   then the reps with per-rep heart rate, then the splits, then the heat panel.
4. Tapping an easy run opens its splits with heart rate.
5. A treadmill row reads `indoor · no weather` and shows no adjusted pace.
6. The share button in the top right produces
   `post-run-drip-training-<date>.xlsx` with five tabs, opening straight into
   Numbers or Files.

---

## If it doesn't build

Three spots use APIs I could read but not compile against. Each is a one-line
fix and the compiler will point straight at it.

**1. `PaceZonesEngine`.** `ConditionsView` currently hardcodes the fast cut at
`375` seconds (6:15/mi) with a `TODO`. That is right for your current fitness
and wrong as a shipped default, because a fixed number makes one colour mean
different fitness for different athletes. When you wire it up, replace the
constant with `ConditionsRollup.fastCutSeconds(zones:)` and pass your zone
engine. If `paceSeconds(for:)` isn't the accessor's real name, the compiler will
say so — fix it in `ConditionsSession.swift` only, it is used in one place.

**2. `ShareSheet`.** It lives in `Shared/ExportView.swift` and is already used
by `BackupView`, so it should resolve. If it is `private`, delete the `private`
keyword on that struct — it is meant to be shared and already has two callers.

**3. `DripStatStrip` / `DripStat`.** I matched the signature
`DripStatStrip(stats: [DripStat(_ label, _ value, unit:)])` from the source. If
the initialiser has moved, the two lines to fix are in `ConditionsView.header`.

Anything else that fails will almost certainly be a font or colour name; every
one of those comes from `DesignSystem.swift` and I took them from the file.

---

## What I deliberately did not build

- **A second heat model.** The backend already computes `adjustment_pct`. The
  client displays it.
- **Parsing your voice memo into structured targets.** `workout_notes` is free
  text an LLM wrote from speech: `"1600m @ 5:08 + 2×800m @ 2:33"`, `"6 minutes
  steady, 2 minutes easy"`. A parser that is right 80% of the time and silently
  invents a target the other 20% is worse than none, because a wrong "you missed
  your target" is a claim about your training. The plan renders verbatim
  directly above the reps and you do the comparison.
- **Audio playback.** `audio_url` is populated but a dense scannable table is
  not an audio player. Tapping through to the journal entry is the right
  affordance.
- **Feeding adjusted pace into training load.** ACWR, TLS and fitness stay on
  recorded values. Changing that is a separate decision with its own doc.
- **A feature flag.** It is a read-only screen behind a Settings row that writes
  nothing. If it is wrong, it is wrong in a place nobody has to visit.
