# HEAD-TO-HEAD POOL — APPLY

Widen the head-to-head pool from *"any run containing MP-or-faster laps"* to
**every key session, plus every long run, long-run workout, progression and
fartlek** — and make the metric grid choose its rows from what the two chosen
sessions can actually measure, instead of printing a column of dashes.

Two changes, in this order:

- **Phase 1 · backend.** `trends-timeline` emits a `compare_pool` alongside
  `fast_segments.sessions`. Additive field, additive columns, no migration.
- **Phase 2 · client.** `HeadToHeadCard` reads the pool, resolves the star
  through `KeySessionStore`, and picks its rows by session *shape*.

**Do not start Phase 2 before Phase 1 is deployed.** The card falls back to
`fast_segments.sessions` when `compare_pool` is absent (§2.6), so an
out-of-order deploy degrades to today's behaviour rather than an empty grid —
but you will be debugging a surface that has nothing new to show.

---

## 0 · Why

Head-to-head is the only comparison surface that survived the 2026-07-27
Trends cull, and it can only see a third of the sessions worth comparing.

`TrendsLegacyTabView.swift:578` builds the pool from
`service.fastSegments.sessions`. That array comes from `analyzeKeySession`
(`_shared/fast-segment-trends.ts:333`), which opens with:

```ts
const firstFast = fastFlags.indexOf(true);
if (firstFast === -1) return null;
```

No MP-or-faster lap, no session. Which means:

| Session | In the pool today | Should be |
|---|---|---|
| 6 × 1K @ 5K | ✅ | ✅ |
| 4 mi threshold block | ✅ | ✅ |
| 17 mi long run | ❌ *(zero MP+ laps)* | ✅ |
| Long run with an MP finish (`long_wo`) | ⚠️ *only its MP block* | ✅ *whole run* |
| Progression, easy → HMP last 2 mi | ⚠️ *only the last 2 mi* | ✅ *whole run* |
| Fartlek, 10 × 1 min float | ⚠️ *if the surges cleared MP* | ✅ |
| A stray fast 400 m inside an easy run | ✅ **wrong** | ❌ |

That last row is the same bug the key-session commit fixed everywhere else.
`59289d6` ("Key sessions: one definition, and the four rules are deleted")
replaced four disagreeing heuristics with persisted `quality_load` resolved
through `KeySessionMark`. Head-to-head was not in that sweep — it is still
running a fifth rule, *"contains a fast lap"*, and it is the loosest of them all.

**This change makes head-to-head the sixth consumer of the one definition, not
the keeper of a sixth rule.**

The second half of the problem is arithmetic. A long run has no reps, so four
of the eleven rows in `CompareMetrics.all` (`rep`, `dens`, `rest`, `rec`) have
nothing to measure, and `pace` means a different quantity for it than it does
for a rep session — *work* pace vs *run* pace. Printing them as `—` would put
a long run against a 5K day on a grid that is half empty and, in the one row
that isn't, comparing two different numbers under one label. The grid has to
pick its rows.

---

## Phase 1 · Backend

### 1.1 · What already exists

Everything the pool needs is already fetched. Nothing new is queried.

| Input | Where | Line |
|---|---|---|
| `training_logs.workout_type` (the athlete's label) | `LOG_COLS_BASE` | `trends-timeline/index.ts:51` |
| `workout_features.workout_type` (the classifier's) | features select | `trends-timeline/index.ts:113` |
| `workout_features.quality_load` / `quality_kind` | **not selected yet** — one column added to the same select | `trends-timeline/index.ts:113` |
| Laps per workout | `lapsByWorkout` | `trends-timeline/index.ts` §4 |
| Weather per log | `weatherByLog` | `trends-timeline/index.ts` §4 |
| Pace zones | `zoneTable` | `trends-timeline/index.ts:298` |
| Daily mileage (doubles summed) | `milesByDate` | `trends-timeline/index.ts:319` |

### 1.2 · New: whole-run metrics

**File: `supabase/functions/_shared/fast-segment-trends.ts`**

`analyzeKeySession` measures the *fast work*. A long run needs the *whole run*
measured with the same adjustments, so the two can share a grid.

Add an exported `analyzeWholeRun(input: KeySessionInput, zones: ZoneTable):
WholeRunMetrics | null`. It runs over **all** laps, not the fast window:

```ts
export interface WholeRunMetrics {
  runMiles: number;              // Σ lap distance
  runSeconds: number;
  runPaceSecPerMile: number;     // the clock — always raw
  runNeutralPaceSecPerMile: number | null;    // heat removed
  runFlatPaceSecPerMile: number | null;       // grade removed
  runConditionsPaceSecPerMile: number | null; // both removed
  runAvgHeartRate: number | null;             // time-weighted
  runAvgGradePct: number | null;
  /** Aerobic decoupling across the WHOLE run, first half → second half. */
  runDecouplingPct: number | null;
  /** Second-half pace − first-half pace, s/mi. Negative = negative split.
   *  This is the progression read: the number the session was FOR. */
  secondHalfDeltaSec: number | null;
  /** Fraction of run time spent at MP-or-faster. 0 for a pure long run. */
  fastTimeShare: number;
}
```

Three notes that are load-bearing:

1. **Reuse the existing halves helper.** The decoupling maths at
   `fast-segment-trends.ts:523-548` already splits a bout's laps at the
   time-midpoint and compares speed-per-heartbeat. Extract that inner `eff()`
   and the split loop into a module-private `halfSplit(laps)` returning
   `{ firstHalf, secondHalf }`, and call it from both places. Do **not**
   write a second copy — a second copy of a halving rule is how the two halves
   end up defined differently in two months.

2. **`secondHalfDeltaSec` is pace, not efficiency.** Decoupling needs HR and
   goes null without it. The split delta needs only distance and time, so a
   progression logged from a watch with no HR strap still gets its headline
   number. Both are emitted; they answer different questions.

3. **Warmup/cooldown are NOT trimmed.** For a rep session the fast window is
   the session; for a long run the whole thing is the session. `analyzeWholeRun`
   deliberately measures door to door, and `fastTimeShare` is how the client
   knows which reading it's holding.

Return `null` when the laps carry no distance or no time. A lapless long run
gets nothing here — see §1.5.

### 1.3 · New: the eligibility rule

**File: `supabase/functions/trends-timeline/fastSegments.ts`**

```ts
/**
 * Types the athlete can always put head to head, whether or not they scored
 * as key sessions. A long run is the anchor of its week even in a down week;
 * a progression is worth comparing to the last progression even when it was
 * deliberately small. These four are session INTENTS — the athlete chose the
 * shape — so they earn a place in the pool on the label alone.
 *
 * Mirrors WorkoutLabel.offered (RunningLog/App/WorkoutLabel.swift:115-121).
 * `threshold`, `intervals` and `race` are DELIBERATELY ABSENT: those score as
 * key sessions on their own quality_load, so listing them here would only
 * matter for a threshold session too small to clear the floor of 25 — which
 * is exactly the stray-fast-400m case this change exists to exclude.
 */
export const ALWAYS_COMPARABLE_TYPES = new Set([
  "long_run", "long_wo", "progression", "fartlek",
]);

/** Legacy spellings that must fold before the set is consulted. */
const TYPE_FOLD: Record<string, string> = {
  longrun: "long_run", long: "long_run", longwo: "long_wo",
};
```

A log is a **compare candidate** when either holds:

- `ALWAYS_COMPARABLE_TYPES.has(type)`, where `type` is
  `training_logs.workout_type` folded, falling back to
  `workout_features.workout_type` — the athlete's own label outranks the
  classifier's, same precedence as `KeySessionMark`; **or**
- `quality_load != null` — i.e. `quality_kind` is `quality` or `long_run`, so
  the session is a *derived key-session candidate*.

Note the second arm emits the candidate with its `quality_load`; it does
**not** apply the floor. The floor is `QualityLoad.floor` and lives client-side
on purpose (`TrendsQualityLoad.swift:79-83`, and the migration comment at
`20260810190100_workout_features_quality_load.sql:44-52`). The backend ships
the number; the client decides. Keep it that way — it is why the floor can be
tuned without an edge-function deploy.

⚠️ **Do not widen the second arm to "any run with laps."** `quality_load` is
`NULL` for an ordinary run precisely so an easy hour cannot enter this pool.
The guard in `qualityLoadForSession` (`_shared/qualityLoad.ts:119-139`) is
already documented as load-bearing; this is the same trap one layer up, and
the failure mode is the same — every day in the SWAP menu.

### 1.4 · New: the `compare_pool` payload

**File: `supabase/functions/trends-timeline/fastSegments.ts`**

`buildFastSegments` gains one parameter and returns one more array:

```ts
export function buildFastSegments(
  logs: FSLog[],                                    // + workout_type, workout_duration_minutes
  lapsByWorkout: Map<string, FSLapRow[]>,
  featuresById: Map<string, {
    workout_structure?: string | null;
    workout_type?: string | null;                   // + already selected
    quality_load?: number | null;                   // + new
    quality_kind?: string | null;                   // + new
  }>,
  weatherByLog: Map<string, FSWeather>,
  zones: ZoneTable,
  streamsByWorkout?: Map<string, FSStream>,
  dailyMilesByDate?: Map<string, number>,
) // → { systems, sessions, compare_pool }
```

`systems` and `sessions` are **unchanged**. Their shape, their filtering, their
consumers — untouched. `compare_pool` is a new sibling, so nothing that reads
the fast-segment trends can be moved by this change.

One `compare_pool` entry per candidate log:

```jsonc
{
  "id": "…", "date": "2026-08-09", "date_label": "Aug 9",
  "name": "16 mi long run",          // workout_structure, else null
  "workout_type": "long_run",        // folded; the athlete's label wins
  "quality_load": 96.4,              // null when never scored
  "quality_kind": "long_run",        // quality | long_run | null
  "shape": "aerobic",                // reps | continuous | aerobic   ← §1.6
  "run_miles": 16.1,
  "run_pace_sec": 471,
  "run_neutral_pace_sec": 462, "run_flat_pace_sec": null,
  "run_conditions_pace_sec": 462,
  "run_avg_hr": 148, "run_avg_grade_pct": 0.4,
  "run_decoupling_pct": 3.2,
  "second_half_delta_sec": -14,
  "fast_time_share": 0.0,
  "feels_f": 81,
  "fast": { /* the existing session object, or null when no MP+ work */ }
}
```

`fast` is the *exact* object already emitted into `sessions` (same builder, same
keys — reuse the mapping function, don't re-inline it). A session that has both
fast work and a whole run — a `long_wo`, a fartlek — carries both, and the grid
gets to use both. That is the point of nesting rather than flattening.

### 1.5 · Lapless sessions

Four of this athlete's fourteen Saturday long runs have no lap data at all
(noted in `_shared/qualityLoad.ts:84-89`). Those still enter the pool, built
from the log row alone:

- `run_miles` ← `workout_distance_miles`
- `run_pace_sec` ← `workout_pace_per_mile`, else `duration / distance`
- everything requiring laps (`run_decoupling_pct`, `second_half_delta_sec`,
  `run_avg_hr`, all adjusted paces) ← `null`
- `shape` ← `"aerobic"`

Degrade honestly, never fake. The grid will fall back to `run_pace` + distance
for a pair like this — three rows, all real — which beats hiding the athlete's
biggest run of the month from the one surface built to compare it.

### 1.6 · `shape` — measured, not labelled

```
reps        ≥ 2 fast bouts            → rep length, density, rest, recovery all mean something
continuous  exactly 1 fast bout       → one sustained effort; rest/recovery do not apply
aerobic     0 fast bouts              → no MP+ work; only whole-run reads apply
```

Derived from `repCount`, **not** from `workout_type`. A "fartlek" whose surges
never reached MP is honestly `aerobic`; a "long run" with 4 × 1 mi @ MP is
honestly `reps`. The label says what the athlete meant; the shape says what the
laps show, and the grid must key off what can be measured.

This supersedes `FastSession.isContinuous`
(`FastSegmentModels.swift:169`, `repCount <= 1`), which conflates *one bout*
with *no bouts* — a distinction that did not exist before this change and now
does.

### 1.7 · Wiring

**File: `supabase/functions/trends-timeline/index.ts`**

1. Line 113 — add two columns:
   ```ts
   .select("training_log_id, intensity_score, total_duration_seconds, workout_structure, workout_type, quality_load, quality_kind")
   ```
   Keep the existing `if (!featRes.error)` degrade path. Both columns land in
   `20260810190100`; if that migration hasn't reached the target project the
   select errors, features degrade to empty, and `compare_pool` falls back to
   the type arm alone. Acceptable, and silent — which is why the deploy-order
   note is at the top of this document.

2. Line 331 — widen the `logs.map` passed to `buildFastSegments` to carry
   `workout_type` and `workout_duration_minutes` (both already in
   `LOG_COLS_BASE`).

3. Widen `keyFeaturesById` (`KeySessionFeature`, `keySessions.ts:54-62`) to
   carry `quality_load` / `quality_kind`, or pass a second map. Prefer widening
   — one map of features, not two.

4. **Remove the `lapsByWorkout.size > 0` guard** around the fast-segments
   block (`index.ts:297`). A lapless long run must still reach the pool
   (§1.5). Keep the `try/catch`: a failure here still degrades to
   `fastSegments = null`, and the Trends tab still renders.

### 1.8 · Tests

**`supabase/functions/trends-timeline/fastSegments.test.ts`** — extend:

| Test | Asserts |
|---|---|
| `longRunEntersThePool` | 16 mi long run, no MP+ laps → in `compare_pool`, `shape: "aerobic"`, `fast: null` |
| `easyRunStaysOut` | 60 min easy, `quality_load: null`, type `easy` → **absent**. The named regression, matching *"easy run scores NOTHING — the trap that would star every day"* (`qualityLoad.test.ts:137`) |
| `strayFast400StaysOut` | one 400 m @ 5K inside an easy run, sub-floor `quality_load` → present *with its load*, and §2.3 filters it client-side |
| `progressionCarriesBoth` | easy → HMP finish → `fast` non-null **and** `second_half_delta_sec < 0` |
| `athleteTypeBeatsClassifier` | log `long_run`, feature `easy` → in the pool |
| `laplessLongRunDegrades` | no laps → in the pool, `run_pace_sec` from the log, adjusted paces `null` |
| `systemsUnchanged` | `systems` and `sessions` byte-identical to pre-change for the same fixture |

**`supabase/functions/_shared/fast-segment-trends.test.ts`** — add:

| Test | Asserts |
|---|---|
| `wholeRunPaceIsDoorToDoor` | warmup + work + cooldown → `runPaceSec` covers all three |
| `negativeSplitIsNegative` | second half faster → `secondHalfDeltaSec < 0` |
| `splitDeltaSurvivesNoHR` | HR stripped → `runDecouplingPct: null`, `secondHalfDeltaSec` still a number |
| `halfSplitSharedWithDecoupling` | the extracted `halfSplit` gives decoupling the same halves it computed before the refactor |

---

## Phase 2 · Client

### 2.1 · Decode

**File: `RunningLog/Trends/FastSegmentsDTO.swift`**

Add `ComparableSessionDTO` + `comparePool: [ComparableSessionDTO]` to
`FastSegmentsDTO`, decoded with the same tolerant `try?` pattern already used
for `systems` / `sessions` (lines 44-47). An older payload yields `[]`, and
§2.6 handles that.

**File: `RunningLog/Trends/FastSegmentModels.swift`**

```swift
enum SessionShape: String { case reps, continuous, aerobic }

struct ComparableSession: Identifiable {
    let id: String
    let date: String
    let dateLabel: String
    let name: String
    let workoutType: String?      // folded key; render via WorkoutLabel.display
    let qualityLoad: Double?
    let shape: SessionShape

    // Whole-run reads — present for every session in the pool.
    let runMiles: Double?
    let runPaceSec: Int?
    let runNeutralPaceSec: Int?
    let runFlatPaceSec: Int?
    let runConditionsPaceSec: Int?
    let runAvgHr: Int?
    let runDecouplingPct: Double?
    let secondHalfDeltaSec: Int?
    let fastTimeShare: Double
    let feelsF: Int?

    /// The fast-work reads, when this session had any. nil for a pure long run.
    let fast: FastSession?
}
```

`FastSession` is **not** modified. It stays what it is — a measurement of fast
work — and `ComparableSession` composes it. Widening `FastSession` with
optional whole-run fields would leave every existing consumer holding a type
whose invariants no longer hold.

### 2.2 · One definition of the star

**File: `RunningLog/Trends/TrendsLegacyTabView.swift`**

Replace the pool at line 578:

```swift
// BEFORE
let ordered = service.fastSegments.sessions.sorted { $0.date < $1.date }

// AFTER
let ordered = comparePool().sorted { $0.date < $1.date }
```

```swift
/// The head-to-head pool: every key session, plus the four session types the
/// athlete can always compare.
///
/// The star is resolved through KeySessionStore — the SAME store the calendar,
/// the journal and the day sheet read — so a day the athlete marked key is
/// comparable, and a day they marked NOT key is not, on every surface at once.
/// This is what makes head-to-head the sixth consumer of the one definition
/// (KeySessionMark.swift) rather than the keeper of a sixth rule.
private func comparePool() -> [ComparableSession] {
    let store = KeySessionStore.shared
    return service.fastSegments.comparePool.filter { s in
        if WorkoutLabel.alwaysComparable.contains(s.workoutType ?? "") { return true }
        // s.date is already a "yyyy-MM-dd" LOCAL day key — see the trap below.
        return store.isKey(dayKey: s.date, derived: QualityLoad.qualifies(s.qualityLoad))
    }
}
```

⚠️ **Do not route this through `Date`.** The obvious spelling —
`TrendsWeekday.date(from: s.date)` then `store.isKey(on: day, derived:)` — is
**wrong, and silently so**:

- `TrendsWeekday.date(from:)` (`TrendsQualityLoad.swift:138`) parses in **UTC**,
  so `"2026-08-09"` → `2026-08-09T00:00:00Z`.
- `KeySessionStore.dayKey(_:)` (`KeySessionStore.swift:87-92`) formats with **no
  `timeZone` set**, i.e. the device's local zone — deliberately, because
  `day_overrides.date` is a local date, matching `daily_checkins`. That contract
  is in the file's header, and it is right.

Round-tripping through the two therefore lands a day early for every athlete
west of UTC — Rio at `America/Chicago` (UTC-5) would look up `2026-08-08` for a
run logged on the 9th, every star would miss, and the pool would quietly
collapse to the four types. It would look exactly like the
`hydrateLoadsIfNeeded` mistake and would not be visible in a UTC simulator.

So add a string overload to `KeySessionStore` and use it here:

```swift
/// Same question, keyed by a day string that is ALREADY a local "yyyy-MM-dd".
///
/// The Date-taking overloads format through `dayKey(_:)` in the device's zone,
/// which is correct for a Date and wrong for a key that has already been
/// resolved — `trends-timeline` emits `workout_date` sliced to 10 chars, the
/// same local date `day_overrides.date` stores. Converting it to a Date and
/// back moves it a day in any zone behind UTC.
func isKey(dayKey: String, derived: Bool?) -> Bool {
    KeySessionMark.isKey(override: overrideByDay[dayKey],
                         planIntent: planIntentByDay[dayKey],
                         derived: derived,
                         isFuture: dayKey > Self.dayKey(Date()))
}
```

`dayKey > Self.dayKey(Date())` is a lexicographic compare on `yyyy-MM-dd`, which
is the same ordering as the dates — the pattern `TrendsWeekday.weekStart` and
`analyzeFastSegmentTrends` already rely on (`a.date.localeCompare(b.date)`).

The Swift half of the type list lives next to `offered` in
**`RunningLog/App/WorkoutLabel.swift`**, not in the Trends folder — that file is
already the single source of truth for workout-type keys, and its header exists
because seven screens once each kept their own copy:

```swift
/// The session INTENTS the athlete can always put head to head, whatever they
/// scored. Mirrors ALWAYS_COMPARABLE_TYPES in
/// `supabase/functions/trends-timeline/fastSegments.ts` — keep the two in sync.
/// Compare against `normalize(_:)`d keys, so `longrun` folds to `long_run`.
static let alwaysComparable: Set<String> = [
    "long_run", "long_wo", "progression", "fartlek",
]
```

Three things this buys, none of which are available to the current rule:

- an explicit `false` override **removes** a session from the pool — "I'm
  telling you that wasn't a key session" is a real, persisted answer
  (`KeySessionStore.swift` header, "THREE STATES");
- an athlete star **adds** a session the derived rule missed;
- the sub-floor stray fast 400 m drops out, because `QualityLoad.qualifies`
  applies the floor of 25 that the backend deliberately did not.

**`await KeySessionStore.shared.hydrateLoadsIfNeeded()` in the Trends tab's
`.task`** (it is `async` — `KeySessionStore.swift:279`). Without it
`loadByDay` is empty on a cold open into Trends and every
derived star reads false — the pool collapses to the four types only. This is
the single most likely way to ship this looking broken.

### 2.3 · The type-aware grid

**File: `RunningLog/Trends/CompareMetrics.swift`**

Give every metric the shapes it can measure, and source its value from
`ComparableSession`:

```swift
struct CompareMetric: Identifiable {
    …
    /// The session shapes this row can honestly measure. A row is drawn only
    /// when BOTH sessions in the pair are in this set — a row that is real on
    /// one side and "—" on the other is not a comparison, it is a blank.
    let shapes: Set<SessionShape>
}

extension CompareMetrics {
    /// The rows this pair can carry. Never empty: the five whole-run rows
    /// accept every shape.
    static func rows(for a: ComparableSession, _ b: ComparableSession) -> [CompareMetric] {
        all.filter { $0.shapes.contains(a.shape) && $0.shapes.contains(b.shape) }
    }
}
```

The row set, after the change:

| id | Label | Group | Shapes | Note |
|---|---|---|---|---|
| `runPace` | **Run pace** | OUTPUT | all | **new** — whole run, door to door. Raw clock; heat/flat as sub-lines |
| `miles` | **Distance** | OUTPUT | all | **new** — whole run |
| `pace` | Work pace | OUTPUT | reps, continuous | **relabelled** from "Pace" — it was always the fast-work pace |
| `vol` | Fast volume | OUTPUT | reps, continuous | unchanged |
| `rep` | Rep length | OUTPUT | reps | was `.neutral`, stays `.neutral` |
| `dens` | Density | OUTPUT | reps, continuous | fast ÷ total |
| `rest` | Avg rest | OUTPUT | reps | drop `isContinuous` guard — `shapes` now does that job |
| `split` | **Second half** | OUTPUT | continuous, aerobic | **new** — s/mi vs first half, `lowerBetter`. The progression row |
| `hr` | Avg HR | COST | reps, continuous | on the work |
| `runHr` | **Avg HR** | COST | aerobic | **new** — on the run. Separate id because it is a different denominator; never both in one grid |
| `drift` | HR drift | COST | reps | unchanged |
| `rec` | Rep recovery | COST | reps | unchanged |
| `dec` | Decoupling | COST | continuous, aerobic | source flips: `fast.decouplingPct` when `continuous`, `runDecouplingPct` when `aerobic` |
| `heat` | Heat cost | CONDITIONS | all | from whole-run paces when `fast` is nil |
| `hill` | Hill cost | CONDITIONS | all | same |

**Two rep sessions** see 13 rows (everything but `split` and `runHr`) — a
superset of today's grid, so nothing regresses.
**Two long runs** see 7: run pace, distance, second half, avg HR, decoupling,
heat, hill.
**Long run vs 5K day** see 5: run pace, distance, heat, hill, and nothing
pretending to be more.

The `editorialRule(group)` loop (`CompareDashboardCharts.swift:77-83`) iterates
`["OUTPUT", "COST", "CONDITIONS"]` unconditionally. **Skip a group whose
filtered row list is empty**, or a mismatched pair draws a `COST` rule with
nothing under it.

### 2.4 · The card

**File: `RunningLog/Trends/CompareDashboardCharts.swift`**

- `HeadToHeadCard.sessions` becomes `[ComparableSession]`; `a` / `b` follow.
- `structureLine` (line 158) — a long run has no `workout_structure`, so the
  fallback `"SESSION · 6.0 MI"` is what it gets. Make the fallback carry the
  type: `WorkoutLabel.display(s.workoutType).uppercased() + " · \(mi) MI"` →
  `LONG RUN · 16.1 MI`. Route it through `WorkoutLabel.display`, never a local
  switch — that file's header is explicit about why.
- `metaLine` (line 104) — `fastMiles` is 0 for two long runs, so
  `"0.0 MI OF WORK EACH"` is a lie. Branch on shape: aerobic pairs read
  `"16.1 VS 15.2 MI"`, otherwise the existing work-miles line.
- The SWAP `Menu` (line 140) now spans types. Add the label so the list is
  readable at length:
  `"\(ss.dateLabel) · \(WorkoutLabel.display(ss.workoutType)) · \(mi) mi"`.
  Consider a `Section` per type once the pool passes ~20 entries.
- `coachRead` (line 293) — its clauses are all rep-shaped ("shorter reps",
  "half the rest"). Add an aerobic branch keyed on `a.shape == .aerobic &&
  b.shape == .aerobic`: lead with the split delta and decoupling
  (*"Aug 9 held its shape — 14 s/mi faster over the second half for the same
  heart rate"*). It already counts wins over `CompareMetrics.all`; point it at
  `CompareMetrics.rows(for:_:)` instead, or a mismatched pair is judged on rows
  the grid never drew.
- The footnote ("Pace is the clock…") still holds. Extend it by one clause when
  the pair is aerobic: pace there is the whole run, not the work.

### 2.5 · Empty state

`headToHead` (`TrendsLegacyTabView.swift:578-585`) currently reads *"Two key
sessions with lap data and this puts them side by side."* With long runs in
scope that undersells it:

> **Two sessions to compare.** Key sessions, long runs, progressions and
> fartleks all count — mark a day as key from its day sheet to add it.

The second sentence is the important one: the athlete now has a *control*, and
the empty state is where they find out.

### 2.6 · Fallback

When `comparePool` decodes empty but `sessions` is not — an old payload against
a new build — fall back to today's pool by mapping each `FastSession` into a
`ComparableSession` with `shape` from `repCount` and whole-run fields nil.
The grid then draws work-pace rows only, which is exactly today's behaviour.
No version check, no feature flag: the shape of the payload is the signal.

### 2.7 · Tests

**`RunningLog/RunningLogTests/HeadToHeadPoolTests.swift`** — new, alongside the
existing `KeySessionTests.swift` and `TrendsQualityLoadTests.swift`:

| Test | Asserts |
|---|---|
| `longRunInPool` | `quality_kind: "long_run"`, load 96 > floor 25 → in the pool |
| `easyRunNotInPool` | `qualityLoad: nil`, type `easy` → out |
| `subFloorFastWorkNotInPool` | load 11.7 (a real stride set from the calibration set) → out |
| `athleteOverrideAdds` | `overrideByDay[date] = true`, load nil → **in** |
| `athleteOverrideRemoves` | `overrideByDay[date] = false`, load 88 → **out** |
| `typeAlwaysWins` | `progression`, load nil → in |
| `rowsForTwoRepSessions` | 13 rows, none `split` / `runHr` |
| `rowsForTwoLongRuns` | 7 rows, includes `split`, excludes `pace` / `rest` |
| `rowsForMismatchedPair` | 5 rows, no empty group rule drawn |
| `rowsNeverEmpty` | every shape pair yields ≥ 5 rows |
| `dayKeyDoesNotShiftInNegativeOffsets` | with `TimeZone(identifier: "America/Chicago")` as the test zone, a session dated `2026-08-09` resolves against `overrideByDay["2026-08-09"]` — **not** `"2026-08-08"`. The named regression for the trap in §2.2 |

---

## 3 · What this change must not do

- **Must not move `fast_segments.systems` or `.sessions`.** They feed the
  per-system trends. `systemsUnchanged` (§1.8) pins it.
- **Must not apply the key-session floor server-side.** It stays in
  `QualityLoad.floor` so it is tunable without a deploy, and so sub-floor work
  can still be drawn as an open ring elsewhere.
- **Must not add a sixth key-session rule.** Every membership question routes
  through `KeySessionStore` → `KeySessionMark`. If a new rule feels necessary,
  it belongs in `KeySessionMark` where all six surfaces get it.
- **Must not relax `qualityLoadForSession`'s `long_run` guard**
  (`_shared/qualityLoad.ts:120-139`). `aerobicLoadForBouts` counts every bout;
  widen it to "any run without work bouts" and a routine easy hour scores ~60,
  clears the floor, and every day in the athlete's calendar gets a star.
- **Must not print `—` on both sides of a row.** If neither session can carry
  it, the row does not belong in that grid.

---

## 4 · Order

| Step | Where | Blocks |
|---|---|---|
| 1 | `fast-segment-trends.ts` — `halfSplit` extraction + `analyzeWholeRun` + tests | 2 |
| 2 | `fastSegments.ts` — eligibility, `compare_pool`, tests | 3 |
| 3 | `trends-timeline/index.ts` — columns, wiring, drop the laps guard | deploy |
| 4 | **Deploy `trends-timeline`.** Confirm `compare_pool` is non-empty in the response for a week containing a long run | 5 |
| 5 | `FastSegmentsDTO.swift` + `FastSegmentModels.swift` — decode | 6 |
| 6 | `CompareMetrics.swift` — shapes, new rows | 7 |
| 7 | `CompareDashboardCharts.swift` — card, empty groups, coach read | 8 |
| 8 | `TrendsLegacyTabView.swift` — pool, `hydrateLoadsIfNeeded`, empty state | — |
| 9 | `HeadToHeadPoolTests.swift` | — |

Steps 1–3 are independently shippable: `compare_pool` can sit unread in the
payload for a release without changing anything on screen.

---

## 5 · The one gap — phase 2, not now

A day the athlete stars that scored *nothing* — an easy run they declare key —
will not be in `compare_pool`, because neither eligibility arm fires. The star
appears in the calendar and the journal; the session is missing from SWAP.

Closing it is one query: fetch `day_overrides` where `field = 'is_key_session'`
and `value = true` for the window (`trends-timeline/index.ts`, alongside the
niggles fetch at line 144), and add those dates as a third eligibility arm.
Everything downstream already works — an easy run has `shape: .aerobic` and
whole-run metrics like any long run.

Left out of this pass only to keep the backend change to columns already
selected. Worth doing next; the athlete who marks a day key and then can't
compare it has been told the mark means something and then shown that it
doesn't.
