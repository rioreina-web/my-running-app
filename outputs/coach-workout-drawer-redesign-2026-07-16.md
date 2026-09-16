# Coach workout drawer — redesign spec (2026-07-16)

**Status:** proposed · **Surface:** web coach portal — `WorkoutDrawer`
(`web/src/components/coach/dashboard/workout-drawer.tsx`), reusable on the full-page detail
(`coach-portal/athletes/[id]/workouts/[logId]/page.tsx`)
**Design mock:** `Post Run Drip Design System/coach-workout-detail-mock.html` (FIG. 24 — numbered
annotations map every section to its data source)
**Related:** `coach-athlete-dashboard-spec-2026-07-16.md` §2.5 (log band), `body-mentions-design.md`,
`heat-pace-adjustment-validation-2026-06-23.md`, `grade-adjusted-pace-plan-2026-06-21.md`,
`docs/coaching/principles.md`

---

## 1. Problem

The drawer's subline promises *"prescribed vs. actual"*. On live data it delivers three KPI cells —
Distance, Type, Mood — plus the note. The live builder (`from-supabase.ts`) populates
`WorkoutDetail.kpis` with only those three fields and uses splits as a "sessions this day" list;
the rich fixture shape (targets, per-rep splits) never materializes from real rows.

Real example (Jul 11): athlete cuts a hot, hilly long run at 15 mi, logs *struggling*, voice note
explains heat + the cut. The drawer showed `15.0 mi · Long run · struggling` — the coach got no
prescription, no conditions, no splits, no load context, even though every one of those exists in
the schema.

## 2. Design intent

The drawer answers the coach's five questions, in reading order:

1. **What was asked vs. what happened** — verdict-as-title, prescription line, cut/delta chip.
2. **How hard was it really** — planned-vs-ran on every headline stat; heat-adjusted pace as the
   honest number; pace × elevation shape chart; conditions strip.
3. **What did the athlete say** — verbatim voice note with the mood pill beside it, plus a
   28-day mood-pattern caption.
4. **Is the body flagging** — niggle for this run, or explicit "quiet" context (absence is
   information, not an empty cell).
5. **Where it sits** — week volume vs. plan, ACWR after this run, next key session; then the AI
   read (last, synthesizing), and one coach action.

Register: Plate 23 ("Pace, narrated") grammar — 4-stat strip, secondary strip, narrated captions —
applied to the coach's job. Every caption cites a number.

## 3. Sections → data

| # | Section | Content | Source | Status |
|---|---|---|---|---|
| 1 | Verdict header | Title ("Long run, cut at 15."), prescribed line, cut/delta chip | `training_logs` ↔ `scheduled_workouts` via `scheduled_workout_id`; cut = actual < prescribed distance/steps | exists — join not surfaced in drawer yet |
| 2 | Headline strip | Distance / Time / Pace each with planned sub; 4th cell heat-adj pace | log fields + `scheduled_workouts.workout_data`; adj = distance-weighted `running_workout_laps.heat_adjusted_pace_sec_per_mile` | exists |
| 3 | Telemetry chart | **Plate 23's Combined chart, ported** — readout chips, pace + HR lines over elevation terrain, HR-zone ribbon, drag-to-scrub crosshair — plus two coach layers: prescribed target band, cut marker + unrun ghost | port `design-system/ui_kits/ios_app/charts-analytics.jsx` `CombinedChart` to a shared web component; data from `running_workout_laps` (pace, HR, elevation per lap); band from athlete pace table (`derivePaceTableFromGoal`) | chart pattern exists in the design system; web port is net-new |
| 4 | Conditions strip | Temp · dew pt · climb · HR avg · drift | `training_logs.weather_actual`, lap `temp_f`/`dew_point_f`/`heat_category`, lap `avg_heart_rate`; dew > 68°F = hot band (`adaptation-rules.ts`) renders coral | exists; **drift (Pa:HR) not stored — derive from lap pace+HR halves, or omit cell until derived** |
| 5 | Splits | Thirds for long runs, reps for quality (keep fixture pattern); raw + heat-adj columns; unrun rows "not run" ghost | `running_workout_laps` bucketed; `WorkoutSplit` gains `adj?: string` | exists |
| 6 | Voice + mood | Verbatim `cleaned_notes`; mood pill inline; pattern caption ("2nd struggling in 8 days — both key sessions") | `training_logs.mood/cleaned_notes`; caption from the 28-day mood strip already computed for the dashboard | exists |
| 7 | Body | Niggle w/ verbatim quote, or "No niggles mentioned · <area> quiet for N days" | `body_mentions` by `training_log_id`; recency per `body_area` | exists |
| 8 | Week & load | Run n of m · miles vs. plan · ACWR after run on banded bar (grays; coral only ≥ spike) · next key session | `athlete_state.acwr`, `weekly_mileage_targets`, next `scheduled_workouts` key day | exists |
| 9 | The read | AI observation: feeling first, numbers cited, soft question, no directives | new prompt via `_shared/prompt-library.ts` | net-new LLM call — see §5 |
| 10 | Actions | "Adjust this week" → plan builder week; "Open full log" → full-page detail | routing only | exists |

## 4. Type & builder changes

- `WorkoutDetail` grows optional blocks: `prescribed?: { label; distance; window; timeEst }`,
  `conditions?: { tempF; dewPointF; climbFt; hrAvg; drift? }`, `chart?: { laps: Array<{ mi; paceSec;
  adjPaceSec?; elevFt }> ; bandLow; bandHigh; cutAtMi? }`, `weekContext?`, `bodyContext?`,
  `read?: { body; question }`. All optional — the drawer renders what it gets, so fixtures and
  thin live rows both stay valid.
- `WorkoutSplit` gains `adj?: string`.
- `from-supabase.ts` already fetches laps (zone bucketing) and `body_mentions`; the enrichment is
  reshaping data already in memory plus one `scheduled_workouts` join and `weather_actual` read —
  no new tables, no schema change (hard rule #1 untouched).

## 5. The AI read (§3 row 9)

- New prompt family (e.g. `coach-workout-read`) in `_shared/prompt-library.ts`. **Not a golden
  family** → CI warns only; gate is manual review against `docs/coaching/principles.md`. Cassettes
  encouraged via promote-to-cassette as usage accrues.
- Voice: observational, second-person about the athlete to the coach; cites at least two numbers;
  ends with one soft question; **never** a directive, diagnosis, or stop-training recommendation
  (hard rule #2). The athlete's own stated plan ("already penciled recovery Sunday") is quoted as
  context, not endorsed as advice.
- On-demand or cached per log row; do not auto-generate for every drawer open (cost note:
  `ai-cost-optimization-plan.md`).

## 6. Design-system compliance

- **Three palettes:** pace = blue ramp only (line, split dots, zone dot, heat-adj value); mood =
  warm pill only; coral = alerts only (cut chip, dew-point-past-68, spike band) + the single
  action button. ACWR in-range bands are grays — never green.
- **Coral as punctuation:** max one per cluster — header: cut chip · chart: cut marker ·
  conditions: dew value · footer: button. No two corals compete inside a cluster.
- **Empty states:** "not run" ghost rows and "No niggles mentioned" prose — no em-dash
  placeholders anywhere (hard rule #8).
- **Casing/voice:** eyebrows mono ALL-CAPS tracked; titles sentence case with period; middle-dot
  separators; numerals always; no cheerleading.
- No predictions on this surface → hard rule #7 not in play.

## 7. Phasing

- **P1 — pure-read enrichment (no schema, no LLM):** header verdict + prescription join, headline
  strip with targets, conditions strip (omit drift if not derived), splits w/ heat-adj, voice+mood
  merge, body context, week & load. Ships the "prescribed vs. actual" promise.
- **P2 — telemetry chart:** port `CombinedChart` (charts-analytics.jsx) to web as a shared
  component; layer target band + cut marker + unrun ghost on top. **Re-ink on port:** the JSX
  predates the 2026-07-03 three-palette rule — pace line coral → blue ramp, pace axis labels →
  `--pace-easy-text`. Reuse on full-page detail (wider) and, later, athlete web surfaces.
- **P3 — the read + actions:** `coach-workout-read` prompt behind manual review; deep link to plan
  builder week.

## 8. Open questions

1. **Drift:** store Pa:HR decoupling on `workout_features` vs. derive in the builder each read?
2. **GAP:** when `grade-adjusted-pace-plan` lands, GAP replaces heat-adj as the 4th headline cell
   or joins it? (Mock uses heat-adj because it ships today.)
3. **Time-based prescriptions:** when `workout_data` prescribes by duration ("~2:15"), the
   headline Distance sub should invert (planned time, est. distance) — confirm the
   `workout_data.steps[]` shape distinguishes these.
4. Does the drawer redesign fully replace the full-page detail body, or does the page keep a
   wider chart + per-mile table? (Lean: same sections, wider chart.)
5. **HR-zone ribbon colors:** `charts-data.jsx` HR_ZONES reuse mood hues (Z1/Z2 are the mood
   greens, Z4/Z5 the terracotta/rose) — this predates the three-palette rule. Decide whether HR
   zones get their own ramp before the web port, or accept HR as a sanctioned fourth palette.
   The mock keeps the app's current zone colors for fidelity.
