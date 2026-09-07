# Coach · The Athlete — v3 apply

Making the coach athlete page real: fix the read, port the three sections that
only exist as a mockup, and shape the page for an athlete with no plan.

Written 2026-08-28 so this can be executed without re-deriving anything. Every
claim below was checked against the live DB (project `aqdijapxmjqaetursrde`) or
the working tree on `design/ds-sync`, not inferred.

---

## 0. Where things actually stand

Three artefacts exist and none of them is the finished thing.

| Artefact | Reads live data | Has the v3 design |
|---|---|---|
| `design-system/Coach Portal Athlete.html` (also `web/public/design/coach-athlete.html`) | **No** — every figure is a literal, typed in from SQL | **Yes** |
| `web/src/components/coach/dashboard/*` (React) | **No** — the query fails, see §1 | **No** — it is the earlier v2 order |
| `/design/coach-dashboard` preview | No — Maya fixtures | No |

The React page renders: `Latest · Key sessions · Against the plan · Body & mind
· Load · Analytics`. The mockup renders: `The workout · Train · Niggles & mood ·
Load`. The gap between those two lists is the work.

The mockup is the spec. Read it before writing JSX — it carries its reasoning in
comments, and the numbers in it are real rows for
`03857bf3-6276-4634-b3cc-15cc6d0bc653` (rioreina@gmail.com) as of 2026-08-28.

---

## 1. P0 — the read is broken, and it blocks everything

`web/src/lib/coach-dashboard/from-supabase.ts:343` selects two columns that do
not exist on `training_logs`:

```
… workout_duration_minutes, scheduled_workout_id, weather_actual, start_time, stress_load
                            ^^^^^^^^^^^^^^^^^^^^                  ^^^^^^^^^^
```

Verified absent in `information_schema.columns`. PostgREST 400s, `safe()`
(line 247) returns `null` on any error, `.then(d => d ?? [])` turns that into
`[]`, and the whole dashboard renders its empty state for every real athlete.
**Nothing downstream can work until this is fixed**, and the failure is silent —
there is no error in the UI and none in the server log.

### 1.1 Fix the select

Remove `scheduled_workout_id` and `start_time`. Keep everything else.

### 1.2 Replace what those columns were doing

**`start_time`** — used at line 718 for `buildConditions(..., fmtStart(...))`.
`training_logs.workout_date` is `TIMESTAMPTZ` and carries the clock time
(`2026-08-25 11:32:37+00`), so derive the start from it. Convert to the
athlete's zone via `athlete_settings.timezone` when present; that table is
already read at line 392, so widen the select rather than adding a query. With
no timezone row, label the time as UTC or omit it — do not silently render UTC
as if it were local.

**`scheduled_workout_id`** — used at line 415 to batch-fetch prescriptions and
at line 694 to attach one to a day. There is no link column on `training_logs`.
The only path from a log to its prescription is
`workout_reconciliations(training_log_id → scheduled_workout_id)`.

Rewrite as: logs → `workout_reconciliations` keyed by `training_log_id` (that
fetch already exists, added at line ~430) → collect non-null
`scheduled_workout_id` → batch `scheduled_workouts` as today. Drop `ScheduledRow`
lookups keyed off the log and key them off the reconciliation instead.

### 1.3 Know what this will and will not recover

Measured on the real athlete, 243 reconciliations:

| Column | Populated |
|---|---|
| `actual_pace_seconds_per_mile` | 243 |
| `adjusted_pace_delta_seconds` | **4** |
| `hit_target` | **4** |
| `scheduled_workout_id` | **0** |

So the prescription join is correct to build but will return **nothing** for
this athlete, and `days[].delta` will be `null` on 239 of 243 sessions. That is
not a bug to fix — it is what a self-coached athlete with no plan looks like.
The UI must not read it as "0 s/mi" or as a miss. See §4.

---

## 2. Port the three sections

Source of truth for layout, copy and spacing is the mockup. Type comes from the
`.drip-*` roles in `web/src/app/globals.css`; the coach portal is already
wrapped in `data-skin="wild"` (`(app)/coach-portal/layout.tsx:18`), so those
resolve. Do not introduce new colour literals — every token exists.

### 2.1 §01 The workout — replace `latest-band.tsx`

Today it is a summary strip. It becomes the **workout sheet**:

1. Eyebrow (`Tue · Aug 25 · 6:32 AM`) and a keyed/mood marker on the right.
2. Factual headline naming the session (`6 × 1K / 600m`). Never editorialised.
3. **The big three** — Dist / Time / Pace, hairline-divided, ~34px tabular.
4. **The session as written**, in roman mono behind a blue left rule, from
   `workout_notes`. Roman because it is a machine reading; italic mono is the
   athlete. Follow with effort load / density / stress.
5. **Splits** — pace above, average HR below, per mile, from
   `pace_segments[]` (`pace_per_mile`, `avg_heart_rate`, `distance_miles`).
   Numbers, not bars: a pace bar has to be inverted to read correctly and
   inverted bars lie.
6. **Conditions** — Temp / Dew point / Heat cost / Humidity / Avg HR from
   `weather_actual`. Dew point ≥ 68 °F renders red (`WorkoutConditions.dewHot`).
7. **The log notes** — `cleaned_notes` verbatim in `.drip-voice`, behind a
   neutral rule. Neutral, not coral: a coloured left rule means mood.

Data note: `pace_segments` needs `duration_seconds` on every segment or the
journal empties — that contract already exists, honour it.

### 2.2 §02 Train — new, replaces "Against the plan"

The iOS TRAIN tab's own shape, not a plan-adherence table. Reference
`design-system/Training Screen v3.html` and
`RunningLog/Training/Analytics/TrainingTabView.swift:64` (`TrainMode: current /
calendar / history`).

- Segmenter: Current · Calendar · History (Current is the only one built).
- **Week flipper** — this is the part with real logic. Port
  `render()` / `weekRows()` / `weekTotals()` from the mockup's inline script
  into a hook; the math is plain JS and moves almost unchanged.
  - `‹` / `›` buttons, disabled at the ends.
  - `←` / `→` keys, ignored while focus is in an input.
  - A clickable week strip (bar height = miles) doubling as the selector.
  - A **This week** button, hidden when already there.
  - `?week=YYYY-MM-DD` deep link, kept in sync via `history.replaceState`.
- Stat row: Miles / Longest / Quality / Load, recomputed per week.
- Seven day rows + a Total row.

### 2.3 §03 Niggles & mood — rework `niggles-panel.tsx`

Group `body_mentions` by `body_area`, newest first, and render **every verbatim
quote** plus a date chip row. The count alone is not trustworthy — see §4.3.

Mood lane stays close to what `mood-strip.tsx` does; add an explicit
**Not logged** step in `--rule` so an unlogged day is visibly different from a
neutral one.

---

## 3. Shape it for an athlete with no plan

`activePlan == nil` is a first-class state (CLAUDE.md), and the canonical
athlete has **0 active plans**. Everything plan-shaped must disappear rather
than render empty:

- Drop `BlockStrip` (week N of M, adherence) when `block` is undefined.
- Drop §02's old "Against the plan" framing entirely — replaced by Train.
- `keySessions` as built measures *delta vs target*, which needs prescriptions.
  With none, the strip has nothing to say. **Either** hide it, **or** re-base it
  on what does exist — the session's own paces against the athlete's pace zones
  from `athlete_pace_profiles` / `derivePaceTableFromGoal`. Decide before
  building; do not ship a strip of "Not scored".
- Sections with no data drop out of the contents rail as well as the page.

---

## 4. Traps

These are the places where a reasonable-looking simplification is wrong. Each
one was actually hit during this work.

### 4.1 `onTarget === false` does not mean "bad"

The delta vocabulary includes `1s under`, `2s under`, `neg split`, `steady`,
`peak long` — all fine, all carrying `onTarget: false`. Colouring on `!onTarget`
paints a faster-than-target session red. This was written wrong once and fixed.

Use `isMiss()` in `components/coach/dashboard/editorial.tsx`: a miss is a delta
that reads slow (`+11 s/mi`) or short (`cut 1 rep`). One red, pointing at the
thing that needs a decision.

### 4.2 A missing value is not a zero

Three distinct states, three distinct renderings:

| State | Renders |
|---|---|
| Day before today with no run | **Rest** |
| Day after today | **To come** |
| Metric never computed | **Not scored** |

Collapsing any of these to `0` makes rest look like failure and makes an
unscored session look like a failed one. `deltaLabel()` in `from-supabase.ts`
returns `null` for "no verdict" and `"on pace"` for zero — keep them apart.

### 4.3 The niggle extractor writes junk

Confirmed on the real rows. Of seven left-knee mentions, the Aug 21 one reads
*"my knee, which had been a concern, felt good today"* — a clearing statement,
filed as `severity_hint: sore`. `side` is `NULL` on several quotes that plainly
say "left".

Therefore: surface the verbatim quote, never a bare count; derive side from the
quote when `side` is null; do not present the tally as a severity signal. This
matches the standing rule — surface, never interpret.

### 4.4 Two different adherence questions

`ranOf` (sessions run ÷ prescribed) and `hitOf` (keyed sessions on target) are
not the same measure. A block can score 86% on the first while missing every
target on the second — which is exactly the block that needs a coach. If only
one is shown, the reassuring one wins. Show both or neither.

### 4.5 Direction I has no boxes

`bg-bg-card` and `bg-bg-base` are both `#FFFFFF` under `data-skin="wild"`, so a
"card" is only a border ring plus padding. Replace with `border-b border-divider
py-5`. No radius above 4px, no shadow, no gradient, no tinted chip — the wild
skin zeroes radius and shadow but will happily render a tint.

---

## 5. Verification

Do not trust a green build here — the failure mode in §1 is silent.

1. `npx tsc --noEmit -p web/tsconfig.json` and `npm run lint` (13 pre-existing
   warnings, 0 errors is the baseline).
2. `npm run build`, `npm test` (179 tests: 44 contract + 135 smoke).
3. **Prove the read works.** Temporarily log `logs.length` in
   `buildDashboardFromSupabase`, load `/coach-portal/athletes/<id>` for
   `03857bf3-6276-4634-b3cc-15cc6d0bc653`, and confirm it is **306**, not 0.
   This is the only check that catches §1 regressing.
4. Spot-check against known real values for that athlete:
   - Week of Aug 3 — 77.4 mi, 16 sessions, 3 keyed, load 711
   - Week of Aug 24 — 47.9 mi through Fri, 8 sessions, load 500
   - Tue Aug 25 — 4 sessions, 14.68 mi; the keyed one is 6.38 mi @ 6:01
   - Rest days: Jul 26, Aug 19, Aug 23 must read **Rest**, not 0 mi
5. Both skins: the coach portal is `wild`, but `/design/coach-dashboard` needs
   `data-skin="wild"` on its wrapper or it previews a page that does not exist.

---

## 6. Not in scope

- The static mockup at `web/public/design/coach-athlete.html` stays as the
  design reference. It does not read data and is not meant to.
- The middleware CSP carve-out for `/design/*.html` (`web/src/middleware.ts`)
  exists so that mockup renders. It skips only the CSP header, never the auth
  gate. If the mockup is retired, remove the carve-out with it.
- `MoodBadge` is still a tinted pill and is shared with trends, injuries and two
  workout pages. De-chipping it repaints four surfaces — a separate call.
- Nothing here is committed. The branch carries unrelated uncommitted work.
