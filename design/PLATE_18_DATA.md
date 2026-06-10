# Plate 18 (Today · Diary + Charts) — Data Inputs Contract

A full inventory of every data point Plate 18 needs, where it comes from,
whether it exists today, and what to do about each gap.

Sections, top-to-bottom:
1. Date heading + race countdown
2. Today's mood prompt
3. Yesterday's journal entry
4. Tomorrow's prescription
5. Fitness · 12-week trend chart
6. Zone shifts · week vs 4-week avg
7. Race predictions · 5 distances with deltas

Status legend: ✅ ready · ⚠️ partial / degraded v1 acceptable · ❌ true hole

---

## 1. Date heading + race countdown

| Field | Source | Status | Notes |
|---|---|---|---|
| Today's day name (`TUESDAY`) | `Date()` | ✅ | client-side `DateFormatter` |
| Today's date (`May 5th.`) | `Date()` | ✅ | client-side |
| Race countdown (`eleven weeks to the marathon`) | `viewModel.activePlan.endDate` minus today | ✅ | already used elsewhere |
| Race distance label (`marathon`) | `activePlan.targetRaceDistance` | ✅ | string column |

**Effort to ship:** zero — pure client-side computation.

---

## 2. Today's mood prompt

The runner picks one of: `ENERGIZED · POSITIVE · NEUTRAL · TIRED · STRUGGLING`.
Each tap saves a daily check-in entry.

| Field | Source | Status | Notes |
|---|---|---|---|
| List of available mood values | Hardcoded enum (matches `training_logs.mood`) | ✅ | already standardized |
| Current selection (if user already checked in today) | `daily_check_ins` table | ❌ | **HOLE.** No table exists. |
| Today's check-in timestamp | Same | ❌ | Same hole. |

**The hole:** there's no `daily_check_ins` table. The mood field on `training_logs`
attaches to a workout, not to a calendar day. A "did you check in today?" lookup
has nowhere to read from.

**v1 substitute:** Use `training_logs.mood` filtered to today's date as a proxy.
If the user logged a workout today (with mood), treat that as today's check-in.
**Limitation:** can't check in on rest days, since rest days don't usually generate
a `training_logs` row.

**Proper fix (1-2 hr work):** Add a `daily_check_ins` table:
```sql
create table daily_check_ins (
  user_id uuid not null,
  check_in_date date not null,
  mood text not null,
  note text,
  created_at timestamptz default now(),
  primary key (user_id, check_in_date)
);
```
Plus an iOS write path when the user taps a mood circle. Trivial.

---

## 3. Yesterday's journal entry

The most important section — this is the *signature* of the diary feel.
Each field has to be there for the prose to land.

| Field | Source | Status | Notes |
|---|---|---|---|
| Most-recent log's date | `training_logs.workout_date` (latest non-null) | ✅ | `lastLog` already computed in TodayHomeView |
| Day-of-week label (`SUNDAY`) | Derived from date | ✅ | client-side |
| Workout type label (`Tempo`) | `training_logs.workout_type` | ✅ | string column |
| Distance (`6.5 mi`) | `training_logs.workout_distance_miles` | ✅ | already populated |
| Pace (`7:25 / mi`) | `training_logs.workout_pace_per_mile` (string) OR computed from duration / distance | ✅ | already populated |
| Duration (`48 min`) | `training_logs.workout_duration_minutes` | ✅ | already populated |
| Mood label (`POSITIVE`) | `training_logs.mood` | ✅ | already populated |
| Mood color rule | Mapped from mood enum | ✅ | mapping exists in JournalEntryRow |
| **Cleaned voice memo prose** (the italic-serif quote) | `training_logs.cleaned_notes` (preferred) or `training_logs.notes` (fallback) | ✅ | already populated for voice-memo logs |
| Coach's marginal note (`solid tempo. Hold it for week 11 too.`) | `training_logs.coach_insight` | ⚠️ | Column exists. **Population is uneven** — only filled by the post-run-analysis edge function, which doesn't always run. |
| Audio playback (when applicable) | `training_logs.audio_url` | ✅ | already populated |

**The watch-out:** if the most recent log is a *manually typed* entry (no voice
memo), `cleaned_notes` may be empty and only `notes` is set. The prose looks the
same either way; the data layer should fall back gracefully (prefer `cleaned_notes`,
then `notes`, then a placeholder line).

**The watch-out 2:** if there's no recent log at all (new user, just signed up),
this whole section needs an empty state. Suggest: *"Log your first run and it will
live here as a journal entry."*

**Effort to ship:** zero — all data already populated.

---

## 4. Tomorrow's prescription

The coach's voice — what the athlete is doing next.

| Field | Source | Status | Notes |
|---|---|---|---|
| Tomorrow's date | `Date()` + 1 day | ✅ | client-side |
| Workout type (`Tempo`) | `scheduled_workouts.workout_type` (where `date` = tomorrow) | ✅ | column exists |
| Workout distance (`8 miles`) | `scheduled_workouts.workout.totalDistanceMiles` (nested PlannedWorkout) | ✅ | populated for AI-generated and imported plans |
| Workout structure (`2 mi WU · 5 mi at 7:00/mi · 1 mi CD`) | `scheduled_workouts.workout.steps` (the structured breakdown) | ⚠️ | Schema exists; **population varies**: AI-generated plans have full structure, imported plans often only have summary text. |
| **Coach's intent quote** (`"Consistent splits, not negative. Let the rhythm settle."`) | `scheduled_workouts.notes` OR `scheduled_workouts.workout.description` OR a new column | ⚠️ | `notes` is athlete-editable freeform; `description` (if it exists) is plan-author-set. **No reliable "coach intent" string today.** |

**The hole:** the *intent* — the coach explaining *why* this workout matters today —
is the most evocative part of the diary feel, and we don't have a reliable source.

**v1 substitute:** generate the intent string client-side from a small lookup table
keyed on `workout_type`:

```
.tempo: "Hold the rhythm. Don't chase the last mile."
.longRun: "Steady, conversational. Fuel and hydrate."
.intervals: "Sharp efforts. Full recovery between."
.easy: "Conversational. Recovery focus."
.progression: "Easy → moderate → MP. Build through."
.recovery: "Easy shakeout between hard days."
```

This gives every workout type a stock intent without pretending it's coach-authored.

**Proper fix (medium effort):** Add a `coach_intent` text column to either
`scheduled_workouts` or the underlying `plan_templates.workout_definitions` JSON.
Populate from plan-author input (for coach plans), or from a one-off Claude Haiku
call when the workout is generated (for AI plans). 2-3 days of work depending on
how thorough you want to be.

**The watch-out:** if there is no scheduled workout for tomorrow (rest day, no plan,
end of plan), this whole section needs an empty state. Suggest: *"Rest day tomorrow.
Recover, hydrate, sleep."*

---

## 5. Fitness · 12-week trend chart

A single line showing the runner's predicted marathon time over the last 12 weeks.
Lower line = better fitness.

| Field | Source | Status | Notes |
|---|---|---|---|
| 12 weekly samples of predicted marathon time | `fitness_snapshots.predicted_marathon_seconds` | ✅ | snapshots are *daily* — pick one per week (e.g., the most recent snapshot in each ISO week) |
| Latest data point | Same | ✅ | most recent row |
| Headline number above the chart (`3:15 → fitness up`) | Computed from latest vs 12 weeks ago | ✅ | client-side computation |
| Trend direction arrow (↑ / ↓ / →) | Sign of (latest minus 12-week-ago) | ✅ | client-side |
| Confidence per snapshot | `fitness_snapshots.confidence` | ✅ | `high` / `medium` / `low` |

**Watch-out:** new users have <12 weeks of data. The chart needs a minimum
threshold — show "Building baseline (X/12 weeks of data)" until there are at
least, say, 4 data points. Then degrade the chart to whatever weeks are available.

**Watch-out 2:** snapshots may have multi-week gaps for inactive periods.
The line should connect across them but visually mark the gap (faint line vs.
solid line, or a small "no data" hash).

**Effort to ship:** zero — fitness_snapshots already populated daily by the
fitness-predictor edge function. Just needs a client-side weekly downsampler.

---

## 6. Zone shifts · this week vs 4-week avg

4-zone strip showing percent-of-volume distribution + delta vs. the trailing
4-week average.

| Field | Source | Status | Notes |
|---|---|---|---|
| This week's seconds-in-zone (4 zones: easy, moderate, threshold, hard) | `workout_features.easy_seconds`, `moderate_seconds`, `threshold_seconds`, `hard_seconds` summed across this week's workouts | ✅ | per-workout rows already populated by `compute-workout-features` |
| 4-week-avg seconds-in-zone | Same fields, summed across the previous 4 weeks (excluding this week), divided by 4 | ✅ | client-side aggregation |
| % distribution per zone | (zone seconds) / (total seconds) × 100 | ✅ | computed |
| Delta percentage points | (this week %) − (4-week avg %) | ✅ | computed |
| Color per zone | Static mapping (Easy → green, Moderate → slate, Threshold → amber, Hard → ink) | ✅ | already in design system |

**Watch-out:** if the runner has done zero runs this week, all four cells will
read `0% +0`. The empty state should either suppress the section or show the
4-week average as a single column (no delta).

**Watch-out 2:** the mockup originally showed 5 zones (Easy/Steady/Threshold/VO2/Race).
**`workout_features` only has 4** (no separation between VO2 and race). Plate 18
correctly uses 4 zones. If you want 5 later, that's a `workout_features` schema
change — a per-step pace classification breakdown.

**Effort to ship:** zero — data exists.

---

## 7. Race predictions · 5 distances with deltas

| Field | Source | Status | Notes |
|---|---|---|---|
| Predicted mile time | `fitness_snapshots.predicted_mile_seconds` | ✅ | populated by fitness-predictor |
| Predicted 5K | `fitness_snapshots.predicted_5k_seconds` | ✅ | populated |
| Predicted 10K | `fitness_snapshots.predicted_10k_seconds` | ✅ | populated |
| Predicted half | `fitness_snapshots.predicted_half_seconds` | ✅ | populated |
| Predicted marathon | `fitness_snapshots.predicted_marathon_seconds` | ✅ | populated |
| 4-week-ago value (per distance) | Snapshot from ~28 days back | ✅ | snapshots are daily — find the closest to (today − 28d) |
| Delta string (`−47s` / `−1:24`) | Computed difference, formatted as M:SS or "Xs" | ✅ | client-side |
| Confidence label | `fitness_snapshots.confidence` (latest) | ✅ | shown in the right-side eyebrow |

**Watch-out:** the predictions assume a calibrated VDOT-style model. **If the
runner's goal is mismatched with their actual fitness** (the 2:20 vs 3:15 gap we
identified earlier), the predictions will look "off" relative to their goal.
That's a real signal, not a bug — but the prediction strip should not falsely
imply they're approaching the goal.

**Effort to ship:** zero — data exists.

---

## Summary table

| Section | Holes | Effort to ship as-shown |
|---|---|---|
| 1. Date heading | None | zero |
| 2. Mood prompt | `daily_check_ins` table doesn't exist | 1-2 hr backend; v1 substitute via `training_logs.mood` works for run days |
| 3. Yesterday entry | `coach_insight` population is uneven | ship as-is, hide the line when missing |
| 4. Tomorrow prescription | No reliable `coach_intent` text source | 1-2 hr to add a static lookup of intent strings per workout_type |
| 5. Fitness trend | None — fully populated | zero |
| 6. Zone shifts | Limited to 4 zones | ship with 4 zones; 5-zone is a later schema change |
| 7. Race predictions | None | zero |

**Total effort to ship a properly-grounded Plate 18:**
- **3-5 hours** of backend / data work for the two real holes (`daily_check_ins`
  table, `coach_intent` lookup table or static map)
- **1-2 days** of iOS work to wire everything up, build the fitness curve view,
  build the zone-shifts row, build the journal entry component (already partially
  built), and add the empty states.

**Total effort to ship a fully degraded but honest Plate 18 (no backend changes):**
- **1 day** of iOS work using existing data and v1 substitutes for the holes.

---

## What's intentionally NOT on Plate 18

So the contract is clear about what we're *not* building:

- ❌ Strain / TSS — requires `tss_score` column + daily rollup. Out of scope.
- ❌ TSB / Form — same dependency. Out of scope.
- ❌ CTL / ATL chart — same dependency. Out of scope.
- ❌ HR-based zones — requires reliable HR sync. Out of scope.
- ❌ HRV / readiness — Terra integration not yet shipped per CLAUDE.md.
- ❌ Sleep data — same.
- ❌ Detailed per-workout splits — that's a workout detail screen, not Today.

Each of these is a real gap that could be filled later. None of them block
Plate 18 from shipping a useful version today.

---

## Recommended ship sequence

**Sprint 1 — ship Plate 18 as-shown, with degraded substitutes for two fields.**
- Fitness trend, zone shifts, race predictions all populated from existing
  fitness_snapshots and workout_features.
- Yesterday entry uses existing training_logs fields (cleaned_notes, mood, etc.).
- Tomorrow prescription uses a static `coach_intent` lookup keyed on
  workout_type — no backend change.
- Mood prompt persists to `training_logs` for runs and uses the most recent
  workout's mood as "today's mood" — degraded but functional.

**Sprint 2 — close the two real holes.**
- Add `daily_check_ins` table + iOS write path. ~2 hr.
- Add `coach_intent` text column to `scheduled_workouts` or a per-workout-type
  lookup populated by the AI plan generator. ~3 hr.

**Sprint 3 — extend the cockpit charts.**
- Compute per-workout `tss_score` (Daniels rTSS formula).
- Add `daily_training_load` rollup table.
- Surface a real CTL / ATL / TSB chart in place of the single-line fitness trend.
- This is when the full Plate 16 cockpit becomes available, on top of Plate 18's
  diary spine.

This sequence ships honest functionality at every step — never lying to the user
with computed-from-thin-air numbers, never blocking the diary experience on a
backend that doesn't exist yet.
