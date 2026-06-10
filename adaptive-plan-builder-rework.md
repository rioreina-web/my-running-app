# Adaptive Plan Builder — Coach's Side

Working doc for reviewing / reworking the coach-facing adaptive plan builder.
Edit in place. When you want something executed, point at a section.

---

## 1. Adaptive vs Fixed — what's the difference?

| | Fixed | Adaptive |
|---|---|---|
| **Coach authors** | Every day of every week explicitly (warmup/tempo/long run/etc.) | Just the **quality days** per week + a weekly mileage *range* |
| **Easy / recovery / rest days** | Coach writes them | Edge function fills them per athlete at subscribe time |
| **Paces** | Literal M:SS/mi the coach typed | Resolved from the athlete's pace profile at subscribe time |
| **Athlete can drag workouts?** | No (`is_movable = false`) | Yes for quality days (`is_movable = true`) |
| **Goal of the format** | Full prescription | "Here's the skeleton; make it fit the athlete" |

**Implication for the builder UI:** an adaptive plan needs two things fixed plans don't:
1. A **weekly mileage target range** (so the edge function knows how many easy miles to add)
2. A way to mark **which day is the rest day** (optional — today it's hardcoded default)

---

## 2. UI surface today

Plan-builder file: [plan-builder-client.tsx](web/src/components/coach/plan-builder-client.tsx) (~1050 lines).

### Header controls

| Control | State var | Saved to | Adaptive-specific? |
|---|---|---|---|
| Plan name | `planName` | `plan_templates.name` | no |
| Fixed / Adaptive toggle | `planType` | `plan_templates.plan_type` | — |
| Distance chips (Mara / Half / 10K / 5K / Custom) | `targetDistance` | `plan_templates.target_distance` | no |
| Duration weeks (1–24) | `durationWeeks` | `plan_templates.duration_weeks` | no |
| **Pace ref strip** (goal time + per-zone overrides) | `paceAnchor` | `plan_templates.phase_config.paceAnchor` | **both** |
| **Race effort readout** (5K/10K/Half/Marathon times) | derived | — | **both** |

### Per-week area

| Control | State | Adaptive-specific |
|---|---|---|
| Week selector tabs (W1, W2…) | `selectedWeekIdx` | no |
| **Mileage range** (min/max mpw) | `weeks[i].targetMilesMin/Max` | **adaptive only** |
| Day grid (Mon–Sun, click to assign workout) | `weeks[i].workouts[j]` | shared |
| Quick type chips + workout template picker | inline | shared |
| Workout step editor for the chosen day | `WorkoutStepEditor` | shared |

### What's NOT in the adaptive builder today
- No "mark this day as rest" control (beyond implicitly leaving it blank)
- No **"forced rest day"** picker for the whole plan (the backend default of Fri was invisible — just fixed that to opt-in)
- No **phase** config per week (base / build / specific / taper) — there's an [`AdaptivePlanConfig`](web/src/components/coach/adaptive-plan-config.tsx) component that handles phase + day-role + mileage targets but it's not wired into this builder
- No **preferred workout days** config (`workoutDay1`, `workoutDay2`) visible to the coach

---

## 3. Data model

### `plan_templates` table (what the builder writes)

| Column | Type | Used for adaptive? | Notes |
|---|---|---|---|
| `name` | text | ✓ | |
| `target_distance` | text | ✓ | "marathon" / "half_marathon" / "10k" / "5k" / custom string |
| `duration_weeks` | int | ✓ | |
| `plan_type` | text | ✓ | "fixed" or "adaptive" |
| `weeks` | jsonb | ✓ | Array of `{weekNumber, theme, notes, targetMilesMin, targetMilesMax, workouts[]}` |
| `phase_config` | jsonb | ✓ | Currently holds `{ paceAnchor: {...} }`. Also where phases *could* go. |
| `weekly_mileage_targets` | jsonb | not currently used | Available — intended for `{ weekNumber, targetMiles, phase }` entries |
| `day_structure` | jsonb | not currently used | Available — intended for `{ dayOfWeek, role }` entries (pre-assigns "this plan always has Tue=speed, Thu=medium, Sat=long") |
| `race_date` | date | not used | Available |
| `join_code` | text | — | Generated on publish |
| `is_published` | bool | — | Draft vs published |

### `weeks[i].workouts[j]` shape (inside the JSONB)

```ts
{
  dayOfWeek: number;   // 0=Mon..6=Sun
  workoutTemplateId?: string;   // optional: reference to workout_templates row
  workoutType?: string;         // "tempo" / "intervals" / "long_run" / "easy" / "rest" / etc.
  workoutData?: {               // inline workout
    schema_version: "v3";
    name: string;
    steps: WorkoutStep[];       // see workout-helpers.ts
    total_distance_km?: number;
  };
  notes: string;
}
```

### Fields on `plan_templates` that subscribe-to-plan reads but the UI doesn't set yet

- `rest_day_of_week` (int, 0=Mon..6=Sun) — was defaulting to Fri in the edge fn; now opt-in
- `auto_strides_on_pre_quality` (bool)
- `recovery_after_long_run` (bool)

No UI surface for any of these today.

---

## 4. Materialization — what happens at subscribe time

Source: [`subscribe-to-plan/index.ts`](supabase/functions/subscribe-to-plan/index.ts)

For each week in the template:

1. **Snap start to Monday** — plan always starts on a Monday regardless of the athlete's chosen start date
2. **Read quality days from `weeks[i].workouts`** — anything with a `workoutType` that's *not* `rest` goes into `qualityDaysByDow`. `rest` types are added to `explicitRestDows`. Blank days are left for the fill step.
3. **Personalize paces** — `personalizeWorkoutData()` walks every step in each quality workout, expands `repeats`/`recovery` into flat steps, and attaches a `target_pace` string based on athlete's pace profile (after my recent fix)
4. **Identify long run day** — whichever quality day has the most miles
5. **Pick rest day** — coach-marked first; else `template.rest_day_of_week` if set; else *nothing* forced (after my recent fix)
6. **Distribute easy mileage** — `(targetMilesMin + targetMilesMax) / 2` minus quality miles = easy budget. Split across remaining days with weights:
   - Day after long run = 0.6× (recovery)
   - Day before a quality = 0.7× (taper into the workout)
   - Normal easy = 1.0×
7. **Shape B extras** — day after long run gets `"recovery"` type with recovery-pace target; day before quality gets `"easy + strides"` if `auto_strides_on_pre_quality` is true (default true)
8. **Insert** — one `scheduled_workouts` row per day × week, plus `quality_session_templates` rows for the pool UI

### Rest-day picker detail

```ts
const easyDayPrefs = {
  restDayOfWeek: typeof template.rest_day_of_week === "number"
    ? template.rest_day_of_week
    : null,  // null = don't force one (after recent fix)
};
// ...
if (explicitRestDows.size === 0 && easyDayPrefs.restDayOfWeek !== null) {
  explicitRestDows.add(easyDayPrefs.restDayOfWeek);
}
```

---

## 5. Known issues / gaps

### Fixed very recently
- [x] Friday rest day was forced on every adaptive plan (restDayOfWeek defaulted to 4)
- [x] Compact `repeats`/`recovery` interval steps weren't being expanded into flat steps before iOS read them (collapsed 7×1600m → "Active 1600m")
- [x] Timezone bug — every web display of a workout date shifted one day earlier
- [x] Sunday-Saturday week ordering on the athlete plan page
- [x] Per-plan pace anchor + goal-derived ladder (new)
- [x] Exact-pace step override + Rec pace removed from picker + notes on steps (new)

### Still broken / missing

**UI gaps (coach's seat):**
- No control for `rest_day_of_week` / `auto_strides_on_pre_quality` / `recovery_after_long_run` — all three are coach decisions sitting in the backend with no UI
- No way to mark a day as "rest" inside a week (have to leave it blank, which means "easy fill" instead)
- No phase config per week (base / build / specific / taper) — the `AdaptivePlanConfig` component exists but is orphaned
- No "preferred workout days" concept (Tue/Thu/Sat or whatever the coach wants) — you're placing workouts day by day, no templated weekly skeleton
- Weekly mileage target is a flat range — no easy way to sketch "build up 60 → 80 → 50 taper" across 16 weeks

**Backend gaps:**
- Coach pace anchor goal → athlete subscribes → athlete's paces are used for personalization, NOT the coach's anchor. The anchor is never read by `subscribe-to-plan`. So a coach setting "MP = 5:32 for this 2:25 marathon plan" has no effect on the prescribed paces an athlete sees.
- `weekly_mileage_targets` column exists in DB but isn't written or read
- `day_structure` column exists but isn't written or read
- `race_date` on the template is unused

**Data integrity:**
- `dayOfWeek` is 0-indexed in the web builder (0=Mon..6=Sun), 1-indexed in `scheduled_workouts.day_of_week` column (1=Mon..7=Sun). subscribe-to-plan has heuristic code to detect which indexing the template uses. Fragile.
- `plan_templates.weeks` is a blob — easy to get out of sync with the `duration_weeks` count if you adjust duration after writing workouts

**iOS alignment:**
- The iOS plan viewer doesn't always render `repeats`/`recovery` correctly (separate bug, partially mitigated by the flattening we added on the edge side)
- Phase labels ("Designed for Base Phase") appear on iOS with no corresponding coach-set phase — it's computed from `weeksUntilRace`. If the coach wants "base" to be weeks 1-6 of a 10-week plan, there's no way to express that.

---

## 6. Proposed restructure

Goals: the coach can say **once at the plan level** "this is a marathon plan for a 2:25 goal, 14 weeks, Mon-rest, Tue-speed, Thu-medium, Sat-long, ramp 60→90→70 mpw" — and then only has to fill in the quality workouts.

### A. Plan-level controls (header)
Add a collapsible "Plan setup" section:
- Goal race + goal time (already in pace anchor) — **make this drive the default pace overrides**
- Preferred workout days — Mon-Sun chip picker for Workout 1, Workout 2, Long Run, Rest
- Mileage ramp shape — a tiny sparkline input for each week's target mileage, with fill tools ("ramp linearly X→Y", "cut to 60% for taper")
- Shape flags — checkboxes for `auto_strides`, `recovery_after_long`, `force_rest_day`

Save into `plan_templates.weekly_mileage_targets` + `day_structure` + relevant columns.

### B. Per-week view simplification
Once plan-level defaults exist, each week only shows:
- The 2–3 quality day slots (labeled by role, not day name)
- A mileage readout (auto from ramp)
- Notes field

Clicking a quality slot opens the workout editor. Easy/rest slots are hidden — they're auto-filled.

### C. Backend additions
- `subscribe-to-plan` should **read the plan's pace anchor** and use it as the athlete's pace table if the athlete has no fitness profile yet
- Materialize `weekly_mileage_targets` into the week-by-week target instead of reading from `weeks[i].targetMilesMin/Max`
- Respect `day_structure` when laying out quality vs easy (today it's inferred from `workoutType`)

### D. Phase labeling
Let the coach tag phase per week; remove the weeksUntilRace-derived "Base Phase" string from iOS in favor of the coach-set phase.

---

## 7. Open questions for you

1. **Quality day count** — should the default be 2 or 3 quality days per week? (Today it's implicit.)
2. **Rest day default** — you just said "always one day off" was bad. Do you want *zero* rest days by default, or "ask the coach on plan creation"?
3. **Mileage ramp UX** — sparkline sketch? Preset shapes ("linear build 8 wks, 2 wk down, 2 wk taper")? Just per-week number inputs?
4. **Workout days naming** — "Workout 1 / Workout 2 / Long Run" (role-based) or "Tue / Thu / Sat" (day-based) for the coach to think about?
5. **Phase** — explicit per-week or implicit from weeksUntilRace? Elite coaches prefer explicit.
6. **Adaptive vs Fixed** — should Adaptive be the only mode? (The Fixed path is there mostly for "coach wrote it in Google Doc and pasted it in")
7. **Per-athlete customization at subscribe time** — should the athlete be able to shift the rest day, add a double, etc., or is the coach-prescribed plan sacrosanct?

---

## 8. Immediate executable next step (pick one)

**(a) Wire up rest-day control** — add a "Forced rest day" chip row in the plan header (None / Mon / Tue / … / Sun). Persists to `plan_templates.rest_day_of_week`. Also add "mark this day as rest" to the per-day picker. ~30 min.

**(b) Plan pace anchor → athlete paces** — make `subscribe-to-plan` read `phase_config.paceAnchor` and use it as the fallback when the athlete has no pace profile. Means a coach's 2:25 marathon plan actually produces 2:25-aligned paces. ~45 min, requires edge fn deploy.

**(c) Mileage ramp UI** — add a sparkline/chart in the plan header showing weeks 1..N with editable `targetMilesMin/Max`. Overwrites the per-week inputs. ~1.5 hrs.

**(d) Preferred workout days** — add a 3-chip picker in the plan header (Workout 1 day, Workout 2 day, Long Run day). Prefills the per-week grid so coaches only have to fill in the quality workout itself, not place it day by day. ~1 hr.

My recommendation: **(a)** (closes an open bug immediately), then **(b)** (biggest unlock for pace correctness), then **(d)**.
