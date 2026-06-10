# Plate 18 — Today tab implementation

Status: **Sprint 1 shipped (code-complete, awaiting Xcode build)**.

## What's in the codebase now

Three new/modified files implement the Plate 18 redesign of the Today
tab — diary spine on top (yesterday + today + tomorrow narrative),
cockpit on the bottom (12-week fitness trend, zone shifts, race
predictions across 5 distances).

### Files touched

| File | Change | Purpose |
|---|---|---|
| `RunningLog/RunningLog/App/CoachIntent.swift` | **new** | Static workout-type → "coach intent" italic-serif quote (Tempo → "Hold the rhythm. Consistent splits, not negative — let it settle."). Used for the prescription line under tomorrow's workout. |
| `RunningLog/RunningLog/App/TodayPlate18.swift` | **new** | Data fetchers + view components: `TodayTomorrowWorkout`, `TodayFitnessTrend`, `TodayZoneShifts`, `TodayRacePredictions`, `TodayJournalEntry`, `TodayTomorrowSection`, `TodayMoodPrompt`, `TodayFitnessTrendChart`, `TodayZoneShiftsRow`, `TodayRacePredictionsStrip`. |
| `RunningLog/RunningLog/App/TodayHomeView.swift` | **rewrote body + extended `TodayLogRow`/`TodayLastLog`** | Removed old VOLUME / PACES / MOOD sections (those moved into Trends/Training tabs already). New body lays out the eight Plate 18 sections. Loader fans out six concurrent fetches. |

### Section order (top → bottom)

1. **Header** — `EEEE · MMM d, yyyy` (monospaced, secondary tone) + race-countdown line ("2:20 marathon · 12 weeks out · Aug 3, 2026").
2. **`TodayMoodPrompt`** — five circles (ENERGIZED, POSITIVE, NEUTRAL, TIRED, STRUGGLING). Tap stores via `@AppStorage("todayMoodCheckIn")` keyed by today's date.
3. **Editorial rule** (line · dot · line).
4. **`TodayJournalEntry`** — yesterday's run with mood-color rule on the left, headline, meta line ("8.4 mi · 7:42/mi · 64 min · TIRED"), italic-serif body quote (cleaned notes preferred, raw notes fallback), optional coach insight.
5. **`TodayTomorrowSection`** — TOMORROW eyebrow + headline + monospaced structure line + italic-serif coach intent quote.
6. **Editorial rule**.
7. **`TodayFitnessTrendChart`** — 12-week predicted-marathon line chart with the latest value + delta arrow (down arrow = fitness improving).
8. **`TodayZoneShiftsRow`** — four zones (EASY / MODERATE / THRESHOLD / HARD), this-week % + delta vs 4-week avg (delta colored: green for up on volume zones, coral for down).
9. **`TodayRacePredictionsStrip`** — 5 distance columns (MILE, 5K, 10K, HALF, FULL) with predicted time and 4-week-ago delta + confidence badge.

## Data sources

See `design/PLATE_18_DATA.md` for the full contract. Quick map:

| Section | Table(s) | Status |
|---|---|---|
| Header date | client-side | ✅ |
| Header race countdown | `training_plans` (`fetchActive`) | ✅ |
| `TodayMoodPrompt` | **`@AppStorage` (degraded substitute)** | ⚠️ — see §1 below |
| `TodayJournalEntry` | `training_logs` (notes / cleaned_notes / mood / coach_insight / workout_duration_minutes) | ✅ — fields newly added to `TodayLogRow` and `TodayLastLog` |
| `TodayTomorrowSection` | `scheduled_workouts` (date, workout_type, workout_data.summary, notes) + `CoachIntent` lookup | ⚠️ — see §2 below |
| `TodayFitnessTrendChart` | `fitness_snapshots.predicted_marathon_seconds`, weekly buckets via ISO Monday | ✅ |
| `TodayZoneShiftsRow` | `workout_features.{easy,moderate,threshold,hard}_seconds`, this-week vs prior 4 weeks averaged | ✅ |
| `TodayRacePredictionsStrip` | `fitness_snapshots.predicted_*_seconds`, latest vs row closest to T-28 days | ✅ |

## Holes (degraded substitutes)

### §1 — `daily_check_ins` table missing

`TodayMoodPrompt` saves locally via `@AppStorage` keyed by today's
date string. Survives app restarts on the device but doesn't sync,
doesn't feed the Coach view, doesn't cross devices.

**To close:** add `daily_check_ins (athlete_id, date, mood, energy, sleep_hours, notes)` table with RLS + unique index on `(athlete_id, date)`. Wire `select(...)` to upsert. Add reads to `process-training-memo` so the coach prompt has it. ~3 hr backend + 1 hr iOS.

### §2 — `coach_intent` text source

The italic-serif quote under tomorrow's workout currently comes from
`CoachIntent.forType()` — a hardcoded mapping in `CoachIntent.swift`.
The `TodayTomorrowWorkout.coachIntent` property prefers the workout's
`notes` if present, otherwise falls back to the static lookup.

**To close:** add `coach_intent TEXT` column to `scheduled_workouts` (nullable, populated at plan-generation time by an LLM call that knows the athlete's recent training context). The Swift code already prefers a richer source — just flip the priority in `coachIntent` to read from a new field on `Row`. ~1 hr.

## Verification

### Static checks already run

- Brace and paren balance verified across all three files (61/61, 173/173, 7/7 braces; 169/169, 490/490, 7/7 parens).
- All component references in `TodayHomeView.body` resolve to types defined in either file.
- `TodayJournalEntry`'s field reads (`cleanedNotes`, `rawNotes`, `durationMinutes`, etc.) all resolve to fields newly added on `TodayLastLog`.
- Schema spot-check confirmed `fitness_snapshots.predicted_*_seconds`, `workout_features.{easy,moderate,threshold,hard}_seconds`, and `scheduled_workouts.workout_data` all exist in current migrations.

### Xcode build (next step)

1. `cd RunningLog && open RunningLog.xcodeproj`
2. Ensure the three files are added to the `RunningLog` target (CoachIntent.swift, TodayPlate18.swift — Xcode auto-detects new files in the App folder, but double-check).
3. Build (⌘B). Expected warnings: `recentLogs` may show as set-but-unused on the home view (it's loaded for future reuse). Safe to ignore.
4. Run on simulator with an account that has scheduled workouts in the future and at least 2 weeks of fitness_snapshots history — without that, the screen renders mostly empty-state copy.

### Visual QA (after build)

- [ ] Header date renders monospaced, all caps.
- [ ] Goal line shows under date if a plan is active.
- [ ] Five mood circles tappable — selected circle fills with its accent color, "CHECKED IN" badge appears top-right.
- [ ] Yesterday's entry shows mood-colored vertical rule on the left.
- [ ] Tomorrow section: eyebrow says TOMORROW left, FROM YOUR COACH right; intent quote is italic serif.
- [ ] Fitness chart: line renders left-to-right, last point has a coral dot.
- [ ] Zone shifts: four columns, deltas colored.
- [ ] Race predictions: five columns separated by 1px dividers, confidence badge top-right.

## What got dropped (vs Plate 16 cockpit)

Per the user's explicit feedback ("the training and strain needs to be discussed more" → "I don't even know where that comes from"):

- **TSS / CTL / ATL / TSB strip** — dropped. None of those metrics are computed anywhere in the backend. Adding them is ~1-2 days of work to back-fill rTSS per training_log + nightly rollup.
- **Strain / Performance hero number** — dropped for the same reason.
- **Form (TSB) sparkline** — dropped.

If/when TSS lands server-side, it slots in cleanly above the fitness
chart as a fourth cockpit row without needing layout changes.

## Files for reference

- `design/plate_18_today_diary.png` — the source mockup.
- `design/PLATE_18_DATA.md` — data contract (which fields come from which table).
- `design/build_mockups.py` — `page_18()` function generates the mockup.
