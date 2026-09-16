# Key Sessions chart redesign — honest pace progression

**Date:** 2026-07-02
**Status:** Proposal for review

> **Update 2026-07-03 — low-data state + receipts implemented.** The
> degraded branch of `KeySessionsDetailView` is now editorial (header
> citing real numbers, zone tally, invitation chart with a dashed
> next-session slot; true-empty keeps the empty-state component).
> `WorkoutsAndRepsSection` became session receipts: structure titles from
> `workout_features.workout_structure` (Intervals/Tempo/Threshold labels
> gone), zone chip, work-bout REP PACE (○ when heat-adjusted), and a
> `RepDensityStrip` per row — width = rep distance, color = the
> PaceSpectrum ramp **anchored to the athlete's zone table** (new
> `PaceSpectrum.anchoredColor(paceSec:zones:)`, resolving the "later
> pass" note in that file). Mockups:
> `key-sessions-low-data-editorial-mockup-2026-07-02.html`,
> `pace-volume-studies-2026-07-02.html`.
> **Blocker for the full chart:** deployed `trends-timeline` is v3
> (June 15) and does not emit `quality_sessions` — redeploy from a
> committed SHA to light up Sections A–C.
**Replaces:** the "Pace progression" chart on Trends (`KeySessionsDetailView` /
`PaceProgressionChart` in `RunningLog/Trends/TrendsDetailViews.swift`, fed by
`supabase/functions/trends-timeline/timeline.ts`)
**Mockup:** `outputs/key-sessions-chart-redesign-mockup.html`

---

## 1. The problem

The current chart plots one number per week: the **whole-workout average
pace** of the week's highest-intensity session (`timeline.ts:363-374`,
`logPaceSec` = pace string or `duration / distance`).

Four failures, in order of severity:

1. **Rest breaks poison the number.** An interval session is 6:00 reps
   separated by recovery jogs and standing rest. Its whole-workout average
   (~8:06) describes neither the work nor the recovery. The athlete looks at
   the chart and sees a number that matches nothing she experienced.
2. **It compares unlike sessions as if they were alike.** A 5K rep day, an LT
   session, and an MP run land on the same line. The subtitle — *"quality
   pace at the same effort"* — is false. Week-to-week movement on this chart
   mostly reflects *which workout type* happened, not fitness.
3. **No conditions normalization.** A 7:10 LT session at 78°F dew point 68 is
   a *fitter* performance than 7:02 in March chill. The chart penalizes
   summer training exactly when honest encouragement matters most.
4. **The headline is unearned.** "The engine is growing." is asserted
   whenever `last < first` on this broken series — an editorial claim built
   on a number we know is wrong. This violates the product's own honesty
   principle (cf. `marathon-prediction-honesty.md`: the math artifact is not
   the signal).

Also: the Workouts & Reps list beneath it labels sessions "Intervals",
"Tempo", "Threshold" — all three were **dropped from the taxonomy on
2026-05-28** (workout labels are pace-zone labels).

## 2. What we already have (data audit, 2026-07-02)

Everything the honest chart needs already exists in the backend. Nothing new
must be collected; the chart just has to stop ignoring it.

| Asset | Where | What it gives us |
|---|---|---|
| Per-lap reps | `running_workout_laps` | distance, moving time, `avg_pace_sec_per_mile`, `is_rest`, per-lap **avg/max heart rate**, cadence, elevation |
| Heat adjustment | same table (`20260528222217`) | `heat_adjusted_pace_sec_per_mile`, `heat_category` (ideal→dangerous), temp/dew-point snapshot. Raw and adjusted stored side by side, by design. |
| Work-bout detection | `_shared/shared/workBouts.ts` | reps bounded by recoveries from raw streams — "GPS splits lie; recoveries are ground truth" |
| Zone classification | `_shared/workoutSegmentation.ts` | each bout classified to the athlete's own 10-zone table (`paceToZone`, midpoint cutoffs, athlete-relative) |
| Session type + structure | `workout_features.workout_type` / `workout_structure` | detection label + human string, e.g. **"9×1K @ 5:07 (5K)"** |
| Time-in-band buckets | `workout_features.easy/moderate/threshold/hard_seconds` | seconds per intensity band per workout (hard = 10K-and-faster zones, threshold = HMP band) — coarse volume-at-pace, precomputed. Per-zone (all 10) requires aggregating from laps. |
| Intensity score | `workout_features.intensity_score` | existing quality gate |
| HR efficiency | `workout_features.hr_pace_efficiency` | already-computed pace-vs-HR signal — Section C may reuse it instead of recomputing |
| Per-second streams | `training_logs.external_streams` | HR/velocity streams for drill-down |

**Coverage caveat (drives every gating decision below):** laps and streams
come from Strava-sourced workouts; HealthKit-only and manual logs may lack
them. HR coverage is a strict subset of that. The design must degrade
honestly at every level: rep data → session data → nothing.

## 3. Design principle

One sentence: **compare like with like, then show the trend.**

A pace only means something relative to (a) the same *kind* of work, and
(b) the conditions it was run in. So: rep-only pace (rest excluded), grouped
by the athlete's own pace zone, heat-adjusted when conditions weren't ideal.
Only then is a line between two dots an honest statement.

The redesigned surface answers three questions, in three stacked sections,
matching the reader's natural order: *am I faster? did I do the work? is it
costing me less?*

### Section A — Same effort, faster? (the headline chart)

Replaces the current line chart.

- **Unit of the dot: a quality session's work-bout pace.** Mean pace across
  the session's work bouts only (`is_rest = false`, zone ∈ work zones).
  Warmup, recovery jogs, standing rest excluded.
- **Grouped by zone.** A zone-chip row (e.g. `5K · LT · HMP · MP`) filters
  the chart, showing only zones with ≥ 2 sessions in range. Default
  selection: the zone with the most sessions in the window. Dots are only
  connected *within* a zone — never across zones.
- **Heat-adjusted by default, honestly labeled.** When `heat_category !=
  'ideal'`, plot the adjusted pace and mark the dot hollow. Chart footer:
  `"○ = heat-adjusted · raw pace on tap"`. Tapping a dot shows both numbers
  and conditions ("7:34 raw · 7:21 adj · 81°F / dew 66"). Never silently
  replace the raw number — adjustment is a model, not a measurement (this is
  already the stored-data policy; the UI follows it).
- **Earned headline.** "The engine is growing." only renders when the
  selected zone has ≥ 4 sessions in range **and** the heat-adjusted trend
  improves by a meaningful margin (proposed: median of last 2 vs. first 2
  sessions ≥ 5 sec/mi faster). Otherwise the header is descriptive:
  "Key sessions · 5K pace". Cite the number in the narrative, per the
  data_depth rule: *"5K reps at 6:52 adjusted vs. 7:04 eight weeks ago —
  at the same effort."*
- **Y-axis inverted mentally, as today** (down = faster); label endpoints.

### Section B — The work behind it (volume at fast paces)

New. Weekly stacked bars of **time at quality intensity**. Cheap v1: the
precomputed `hard_seconds` / `threshold_seconds` / `moderate_seconds` bands
from `workout_features`. Per-zone stacks (5K vs. LT vs. MP separately, as
mocked) require aggregating lap time by zone — slightly more backend work,
noted in §6. Answers "am I actually accumulating work at
these paces, or was that one hero session?" Easy/recovery volume is shown as
a muted total-line only — this section is about the sharp end. Bars use ink
tones; the currently selected zone from Section A is highlighted coral
(coral as punctuation: one accent per cluster).

### Section C — Same pace, cheaper (effort vs. output)

New, and **gated on HR coverage**. For the selected zone: each session's
work-bout pace plotted against its work-bout average HR. The honest fitness
signal is the drift — same pace arriving at lower heart rate. Render only
when ≥ 3 sessions in the selected zone have lap-level HR; otherwise show the
empty-state component: eyebrow `EFFORT VS. OUTPUT`, nudge *"Not enough
heart-rate data on these sessions yet. Runs synced with HR will start
filling this in."* (no CTA needed; no em-dash).

Presentation: dots positioned by date on x, pace on y (same scale as
Section A), each dot annotated with its avg work HR; narrative sentence
states the drift when it exists: *"LT work at 7:20 now costs ~158 bpm —
it was ~166 in April."* No cardiac-drift jargon; never a medical claim.

### Workouts & Reps list (below the chart)

- Labels come from `workout_features.workout_structure` when present —
  `5K 5×1km · 6.0 mi` — falling back to `<ZONE> <distance>` (`LT 7.4 mi`),
  falling back to the plain distance. "Intervals/Tempo/Threshold" are gone.
- Each row gains a right-aligned **work-bout pace** (not whole-workout), and
  a heat marker when adjusted (`○ 7:21`).

## 4. What this is not

- **Not a coaching verdict.** The chart surfaces observation; interpretation
  belongs to the athlete (or her Coach Read, which can reference these same
  numbers). No "you should…" anywhere on this surface.
- **Not a lab.** No VO₂ estimates, no training-stress pseudo-science, no
  single-number "fitness score" here. Range-and-confidence honesty carries
  over from the prediction rule.
- **Not dependent on new data collection.** Everything renders from data
  already flowing. Missing data degrades the surface; it never fakes it.

## 5. Data-depth and degradation ladder

| Athlete's data | What renders |
|---|---|
| Lap-level reps + weather | Full Section A (adjusted), B, C if HR |
| Laps, no weather | Section A with raw pace, no hollow dots, footer omitted |
| No laps (manual/HealthKit-only sessions) | Session excluded from A/C; still counted in B if zone buckets exist, else in weekly total only |
| < 2 sessions in every zone | Chart area shows empty-state: eyebrow `KEY SESSIONS`, nudge *"A few more quality sessions and the same-effort trend starts here. Two in the same zone is all it takes."* |
| data_depth < 2 | No editorial headline ever; plain descriptive header |

## 6. Backend changes (sketch — sized for review, not committed scope)

`trends-timeline` currently returns one `key_pace_sec` per week. Proposal:
extend the payload (append-only, keep `key_pace_sec` until iOS migrates)
with a `quality_sessions` array: per session `{ date, log_id, zone,
work_pace_sec, work_pace_adj_sec, heat_category, work_hr_avg, structure,
distance_mi }`, computed by joining `running_workout_laps` +
`workout_features`. Zone-time buckets ride along per week for Section B.
Pure-function derivation in a shared module with tests, mirroring the
`timeline.ts` convention. No schema changes; no new tables; RLS untouched
(service-role read path unchanged).

## 7. Phasing

1. **Phase 0 — stop lying (small, shippable now).** Work-bout pace instead
   of whole-workout average for the weekly dot (fall back to current number
   when no laps, marked visually); subtitle changed to "Rep pace, rest
   excluded"; headline gated; list labels from `workout_structure`.
2. **Phase 1 — zone grouping + heat adjustment.** Zone chips, per-zone
   trends, hollow adjusted dots, tap-through detail. The mockup's Section A.
3. **Phase 2 — volume-at-pace (Section B).**
4. **Phase 3 — effort vs. output (Section C),** after checking real HR
   coverage across the user base.

## 8. Open questions for Rio

1. Default window: current chart is ~4 months. Keep, or align to the
   training-block boundary (since same-zone comparison across a base block
   and a sharpening block is still apples-to-oranges-ish)?
2. Section C framing: pace-vs-HR as described, or fold HR into Section A's
   tap-through detail only (simpler, less prominent)?
3. Should long-run quality segments (the `Long wo` label) feed Section A's
   MP/HMP zones, or stay out because embedded quality "doesn't carry the
   precision of a pace-zone workout" (per the taxonomy decision)?
4. Threshold for "the engine is growing": is median-of-2 vs. 2 at ≥ 5 sec/mi
   the right bar, or stricter?

## 9. Hard-rule compliance check

- Rule 2 (no diagnosis/medical): HR presented as observation only. ✓
- Rule 7 (range + confidence, no false precision): paces shown as M:SS; no
  seconds-precision projections; headline gated on sample size. ✓
- Rule 8 (no em-dash empty states): both empty states specced with the
  eyebrow + nudge component. ✓
- Coral as punctuation: one coral element per section (selected zone). ✓
- data_depth gating respected (Section 5). ✓
- Taxonomy: all labels are pace-zone labels. ✓
