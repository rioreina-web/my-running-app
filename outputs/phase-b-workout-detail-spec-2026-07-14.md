# Phase B — Workout Detail Overhaul · Implementation Spec

**Handoff doc, written 2026-07-14.** Self-contained execution spec for the
workout-detail redesign ("one view, three acts"). Written to be handed to
a fresh Claude/Opus session with no other conversation context. Read
`CLAUDE.md` at the repo root first; it is binding. Companion docs:
`outputs/beta-design-overhaul-plan-2026-07-13.md` (§4 is this phase),
`outputs/beta-mockups-2026-07-13.html` (frame 04 is the target),
`outputs/post-run-drip-design-system-copy-2026-07-13.md` (tokens + voice).

**Goal in one sentence:** turn the workout detail from a ~12-section flat
stack into three acts with hierarchy — conditions up top, Workouts & Reps
as the hero, traces collapsed — in ONE canonical view.

---

## 1. Current state (verified 2026-07-14)

### The canonical view
`RunningLog/RunningLog/Workouts/WorkoutRepReceiptView.swift` (~1,120 LOC)
is the real workout detail. It loads via
`WorkoutLapsService.fetchLaps(workoutId:)` + `fetchParsedReps` +
`fetchZones` + `fetchInsight` + `fetchType` (see `load()` around line
886). `workoutId` == the `training_logs` row id; `running_workout_laps`
is keyed by that id in its `workout_id` column.

Current rendered order (flat, all equal weight): date header → stat strip
→ THE READ (weather woven in as a prose sentence, `weatherSentence`
around line 606) → time-in-HR-zone → HR-over-session → pace trace →
cadence → elevation/grade → mile splits → comparison vs recent → route.

### Entry points (all four must keep working)
- `Workouts/WorkoutRepDetailSheet.swift:32`
- `Workouts/HistoryDetailSheet+Editorial.swift:163`
- `Coaching/Read/CoachReadView.swift:538` (workout chips in the Read)
- `Training/Analytics/WorkoutsAndRepsSection.swift:80` (Train · HISTORY)

### The fork to kill
`Workouts/WorkoutDetailPlate23.swift` (~302 LOC) is editorial *chrome*
(`WD23Header`, `WD23TwoStatStrip`, `WD23SecondaryStats`,
`WD23SectionEyebrow`, `WD23WeeklyContext`). Verified: these components
are referenced **nowhere outside their own file** — orphaned design
intent. Known lie: `WD23TwoStatStrip` renders FOUR stats. A
`VitalWorkoutDetailView` exists only in stale `.claude/worktrees/*` —
**do not source anything from worktrees** (CLAUDE.md known-issues).

### Data available per workout
- **Laps** (`running_workout_laps` via `WorkoutLapsService.fetchLaps`):
  `lap_index, distance_meters, moving_time_seconds,
  avg_pace_sec_per_mile, avg_heart_rate, is_rest, temp_f, dew_point_f,
  heat_adjusted_pace_sec_per_mile`. Weather rides the laps. Note the
  existing carry-forward fix (~line 939): parsed/merged geometry loses
  weather, so max temp/dew are copied back onto reps — keep that logic.
- **Rep structure**: `WorkoutLapsService.mergeWorkBouts(_:)` builds
  deterministic reps from raw laps (consecutive work laps merge; rests
  pass through). Preferred over the LLM `parsed_structure` — keep.
- **Elevation**: NOT on laps. Lives in `training_logs.external_streams`
  meta (`total_elevation_gain`) + altitude stream, loaded by
  `Workouts/ExternalStreamAdapter.swift` (see `buildMeta`, ~line 262).
  Strava-sourced rows only; HealthKit rows may have none.
- **Targets**: planned target pace exists where a plan prescribed the
  session (the receipt already heat-adjusts targets — `adjustedTarget`,
  ~line 724). Keep heat-adjusted target logic.
- **Voice/qualitative**: the receipt already has an honest no-data state
  for voice-logged runs. Mood vocabulary (TEXT labels):
  `energized | positive | neutral | tired | struggling | injured`.
  Render via the existing `MoodBadge` (App/DesignSystem.swift:209) —
  never SF-symbol faces, never emoji.
- **GAP (grade-adjusted pace)**: the JSX intent has a GAP column but
  the lap rows carry NO grade data today. **Do not fabricate.** Ship
  the table without GAP; leave a `// TODO(GAP)` referencing the
  altitude stream as the future source. (Same for the JSX "LOAD"
  column — data model doesn't have it; omit.)

### Design intent (the JSX wins on disagreement)
`design-system/ui_kits/ios_app/WorkoutDetailScreen.jsx` ("Plate 23 —
Pace, narrated") + `WorkoutMark.jsx` (14 stroked workout-type glyphs).
Known drift: hardcoded tracking values with comments admitting drift.

---

## 2. Target design — three acts

Mirror `outputs/beta-mockups-2026-07-13.html` frame 04.

### Act 1 · The run at a glance (fits without scrolling)
1. Eyebrow: `TUESDAY · QUALITY` (mono, tracked, uppercase).
2. Display date: `July 9.` — Crimson Pro bold ~34pt, coral period.
3. Italic source line: `7.42 mi · 51:08 · HealthKit` (PT Serif italic,
   middle-dot separators — NEVER `|` or `/`).
4. Four-stat strip: DISTANCE · DURATION · AVG PACE · AVG HR (mono
   values, tracked mono 8–9pt labels, hairline top rule in ink).
5. **Conditions plate** (NEW, promoted from the buried prose sentence):
   a `paper-deep` (#E8E4DF) rounded well with four cells — TEMP ·
   DEWPOINT · HEAT ADJ · CLIMB. Heat adj = raw minus heat-adjusted
   pace, mean over work laps, shown only when ≥ 3 s/mi (matches
   `WorkoutForecast` threshold). Climb only when elevation data exists.
   Cells with no data DROP OUT — never render an em-dash (hard rule 8).
   Ink text only — conditions are facts, not alerts (no coral).

### Act 2 · The story
6. `THE READ` eyebrow (this is the one coral eyebrow on the screen) +
   the existing insight paragraph. Weather no longer needs its own
   sentence — trim `weatherSentence` if it duplicates the plate; keep
   the heat context inside the read prose where it already exists.
7. Qualitative inline: `MoodBadge` + verbatim voice-memo quote in PT
   Serif italic with curly quotes. Honest empty state when absent
   (existing pattern — keep).
8. **WORKOUTS & REPS — the hero.** Eyebrow like
   `WORKOUTS & REPS · 6 × 800 @ 5K`. Table: REP · PACE · TARGET · HR.
   Rep index cell = small rounded chip filled with the rep's pace-zone
   color from `PaceSpectrum` / `PaceZoneScale` (pale Easy stop takes
   ink text; deep stops take paper text). Target column present only
   when a prescription exists. Footer caption:
   `REP AVG 6:41 · TARGET 6:40 · RECOVERIES 2:00 JOG`. This section
   gets the visual investment — generous spacing, ink header rule,
   tabular-nums alignment. Reuse `mergeWorkBouts` output; do not
   re-derive reps.

### Act 3 · The traces, collapsed
9. `TRACES` eyebrow, then one row per chart: HR ZONES · PACE TRACE ·
   CADENCE · ELEVATION · VS. RECENT · ROUTE. Row anatomy: eyebrow-style
   title (ink) + one-line mono summary stat (`31 MIN Z4 · 12 MIN Z2`,
   `174 AVG`, `+310 FT · MAX 5.2% GRADE`…) + chevron. Tap expands the
   existing chart in place (reuse the current chart implementations —
   this phase moves them, it does not rewrite them).
10. **Default-expand exactly one** row by workout type: quality/interval
    → HR ZONES; long run → PACE TRACE; hilly run (climb ≥ ~150 ft or
    max grade ≥ 4%) → ELEVATION; else all collapsed. Rows with no data
    for that workout are omitted entirely (not shown disabled).

---

## 3. Implementation tasks, in order

- **T1 — Restructure.** Reorganize `WorkoutRepReceiptView.body` into
  `actOne` / `actTwo` / `actThree` sub-views. No chart rewrites; move
  existing sections into the new order. Keep `load()` and all fetch /
  merge logic intact.
- **T2 — Conditions plate.** New `ConditionsPlate` view in the same
  file (or `Workouts/`), fed from already-loaded laps (max temp, max
  dew, mean heat delta ≥ 3 s/mi) + elevation gain from
  `ExternalStreamAdapter` meta if already loaded — if streams aren't
  loaded by this view today, fetch ONLY the meta lazily and degrade
  silently (climb cell drops out).
- **T3 — Hero reps table.** Columns REP · PACE · TARGET · HR; zone-color
  rep chips; heat-adjusted target logic preserved; footer caption. No
  GAP/LOAD (see data note; leave TODO).
- **T4 — Collapsible traces** + the default-expand rule (§2.10).
  Collapse state is per-presentation `@State`; no persistence needed.
- **T5 — Kill the fork.** Delete `WorkoutDetailPlate23.swift` OR reduce
  it to components actually composed by the receipt — no orphaned
  chrome. If any WD23 component is adopted, rename truthfully
  (`WD23TwoStatStrip` → `StatStrip4`). Never import from
  `.claude/worktrees/*`.
- **T6 — Tokens.** Replace hardcoded tracking/spacing in the touched
  code with the drip helpers (`.dripEyebrow(11).tracking(1.3)`,
  `.dripDisplay(n)`, `.dripStat(n)`, `.dripBody(n)`; 8pt spacing grid:
  4/8/12/16/20/24/32/40). Align to `WorkoutDetailScreen.jsx` where the
  two disagree — the JSX wins.
- **T7 — Verify entry points.** Build and open the detail from all four
  call sites listed in §1. They pass `workoutId:` — signature must not
  change (the laps/zones injection initializer used by previews stays).
- **T8 — QA script** (run in simulator):
  1. Interval workout with weather → conditions plate shows all four
     cells; HR ZONES default-expanded; reps table has TARGET column if
     planned, colored chips either way.
  2. Easy HealthKit run, no streams → climb cell absent, no em-dashes
     anywhere, traces list shorter (route/elevation omitted).
  3. Voice-logged run (no GPS) → honest empty states; screen still
     composes; mood + quote render in Act 2.
  4. Hot run (dew ≥ 65°) → HEAT ADJ cell present and read references
     conditions without duplicating the plate verbatim.
  5. Open from the Coach read chip and from Train · HISTORY — back
     navigation intact.

## 4. Binding constraints

1. **AI never diagnoses / prescribes rest** — the Read text is
   observation only; don't add advisory copy anywhere (CLAUDE.md hard
   rule 2). Niggles: verbatim quotes, surface never interpret.
2. **Three-palette rule:** blue (PaceSpectrum ramp) = pace ONLY; warm
   palette = mood ONLY; coral = alert/punctuation, **max one coral
   element per visual cluster** (the coral date-period and the THE READ
   eyebrow are in different clusters — fine; don't add more).
3. **No em-dash empty states** (hard rule 8) — cells/rows drop out or
   use the empty-state pattern (state the absence, say what fills it).
4. **Voice:** middle-dot separators; lowercase units (`7:42 / mi`);
   numerals always; no exclamation points; no emoji; no SF-symbol
   mood faces; sentence-case body, ALL-CAPS tracked mono labels only.
5. **Predictions/derived numbers:** never invent values that aren't in
   the data (no fabricated GAP, no fabricated weather); rounding to
   whole seconds/degrees is fine.
6. **Migrations/backend:** none required for this phase. Do not touch
   `supabase/` (and never apply migrations outside `supabase db push`).
7. Don't rename or break `WorkoutLapsService` public API — other
   surfaces (`WorkoutsAndRepsSection`, `RepDensityStrip`) consume it.

## 5. Acceptance criteria

- One canonical detail view; `WorkoutDetailPlate23.swift` gone or truly
  composed; no orphaned WD23 chrome remains.
- Act 1 fits a 6.1" screen without scrolling; conditions plate present
  whenever lap weather exists.
- Workouts & Reps is unmistakably the visual center of the screen.
- Trace charts all still reachable; exactly one default-expanded per
  the workout-type rule; all four entry points verified.
- No new hardcoded tracking values in touched code; builds clean with
  no new warnings.

## 6. Out of scope (do not do here)

Climb column on Train's week rows, niggle chips on day rows, PATTERNS
correlation work (Phase D), Coach read prompt changes (golden family —
cassette-gated), any web or backend changes.
