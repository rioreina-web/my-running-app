# Athlete Onboarding to a Coach's Plan

Working doc. The flow today (`JoinCoachPlanSheet`) is "enter a 6-char
code → instantly get materialized into the plan." That's two clicks too
few — the athlete subscribes blind, and the resulting plan is calibrated
on default assumptions (rest day Friday, easy fills based on coach's
mileage range, paces from coach's anchor or empty fallback).

What's missing: the **5 minutes of personalization** that turns a
generic coach plan into "this fits MY week." This doc names what to
collect, in what order, and how it threads through the existing
materializer (`subscribe-to-plan`).

Sister docs:
[`adaptive-plan-builder-rework.md`](adaptive-plan-builder-rework.md),
[`pace-system-rework.md`](pace-system-rework.md),
[`docs/athlete-plan-ux.md`](docs/athlete-plan-ux.md).

---

## 1. Current state — what `JoinCoachPlanSheet` collects today

Read the file: `RunningLog/Training/JoinCoachPlanSheet.swift` (~250 LOC).

Today the sheet collects:
- 6-char join code
- Start date
- Goal time (optional)
- Race distance (defaults to plan's `target_race_distance`)

That's it. After "Join Plan," the athlete hits the
`subscribe-to-plan` edge function, which:
- Snaps start to Monday
- Reads coach's `rest_day_of_week` (or null)
- Materializes weeks based on the coach's `targetMilesMin/Max`
- Pace resolution: coach's `phase_config.paceAnchor` → athlete's pace
  profile → empty (after the Phase A pace fixes shipped 2026-04-24)

**Net:** the athlete has zero say in:
- Their rest day(s) — coach's choice or none
- Which day(s) they want quality on
- How much volume in their easy fill
- Whether they want strides on pre-quality days
- Whether the day after long run is recovery
- Their goal time — it's optional and easy to skip

The result is a plan calibrated for a generic athlete, not the one
subscribing.

---

## 2. What to actually collect

Six questions. Each one matters. None of them are corporate-friendly
"would you like to..." — they're "here's what your week looks like;
adjust it."

| # | Question | Default | Why it matters |
|---|---|---|---|
| 1 | **Goal time** | Coach's plan anchor (recommended), or "set my own" | Drives every pace shown in workouts. Coach anchor wins when present; athlete goal fills the gap when no anchor is set. |
| 2 | **Rest days** | Empty (no forced rest) | Athlete picks zero, one, or many. No nudge. Multi-day support — some athletes rest Mon+Thu. |
| 3 | **Quality days** | Coach's pattern (typically 2 days, e.g. Tue+Sat) | Coach says "2 quality days per week" — but is that Tue+Sat, Wed+Sun, or M+F? Athlete's life dictates this. |
| 4 | **Current weekly mileage** | Pre-fill from last 4 weeks of logs if available; else ask | Drives the volume ramp. Coach prescribes 50-60. If athlete averaged 32, we start at 35 and ramp. New athletes (no log history) answer the question directly. |
| 5 | **Shape preferences** | `auto_strides`: on, `recovery_after_long_run`: on | These are real coaching decisions. Athletes who lift on long-run days don't want strides Friday too. |
| 6 | **Start date** | Next Monday | Athletes should pick when they're ready, not be force-snapped. (We still snap to Monday inside subscribe-to-plan; this is just choosing which Monday.) |

That's the full picture. Six screens or one long form — depends on
density preference (see §3 for the proposal).

---

## 3. Proposed flow

### Macro shape — one sheet, scrolling sections

Don't make it a 6-step modal carousel. That's a 2010 onboarding pattern
and it makes athletes click "Next" 5 times. Make it **one scrolling
sheet with 6 sections** — they can fill out top-to-bottom or skim and
adjust.

```
┌─ SUBSCRIBE TO COACH'S PLAN ─────────────────────────┐
│ Aerobic Base · Marathon · 16 weeks                  │
│ from Coach Sarah                            [×]     │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. YOUR GOAL                                       │
│  ─────────────                                      │
│  This plan is built for a 2:25 marathon.            │
│  ( ) Train at the coach's paces (2:25)              │
│  (•) My goal is...  [2 ▾] : [30 ▾] : [00 ▾]        │
│                            Marathon ▾               │
│                                                     │
│  2. REST DAYS                                       │
│  ────────────                                       │
│  Pick zero, one, or many. Your call.                │
│  ☐ Mon  ☐ Tue  ☐ Wed  ☐ Thu  ☑ Fri  ☐ Sat  ☐ Sun  │
│  (no rest is fine — adaptive plans don't require)   │
│                                                     │
│  3. YOUR QUALITY DAYS                               │
│  ──────────────────                                 │
│  Coach calls for 2 quality days per week.           │
│  Pick when you can do them.                         │
│  ☐ Mon  ☑ Tue  ☐ Wed  ☑ Thu  ☐ Fri  ☐ Sat  ☐ Sun  │
│                                                     │
│  Long run lands on:  [ Saturday ▾ ]                 │
│                                                     │
│  4. STARTING VOLUME                                 │
│  ─────────────────                                  │
│  Coach prescribes 50-60 mi/week.                    │
│                                                     │
│  What's your current weekly mileage?                │
│  [ 32 ] mi/week                                     │
│   (we pre-fill from your last 4 weeks of logs       │
│    when available; otherwise tell us)               │
│                                                     │
│  Ramp from   [ 35 ] mi  to coach's 50-60            │
│              over the first 4 weeks                 │
│  [×] Use coach's full range from Week 1             │
│                                                     │
│  5. WORKOUT SHAPE                                   │
│  ────────────────                                   │
│  ☑ Strides on the day before quality                │
│  ☑ Easy recovery after long run                     │
│  ☐ Add a second easy run on non-quality days        │
│                                                     │
│  6. START DATE                                      │
│  ─────────────                                      │
│  [ Mon, Apr 28 ] (next Monday — recommended)        │
│                                                     │
├─────────────────────────────────────────────────────┤
│  PREVIEW WEEK 1                                     │
│  ──────────────                                     │
│  Mon · Rest                                         │
│  Tue · Tempo · 4 mi @ 5:32/mi                      │
│  Wed · Easy 5 mi @ 7:30                             │
│  Thu · Intervals · 6×800m @ 4:55/mi                │
│  Fri · Easy 5 mi + strides                          │
│  Sat · Long run · 14 mi @ 7:45                      │
│  Sun · Easy 5 mi                                    │
│  ≈ 35 mi this week                                  │
│                                                     │
│              [ Subscribe to Plan → ]                │
└─────────────────────────────────────────────────────┘
```

Six sections, one button at the bottom. Athlete sees a real preview
before committing. Coach's defaults pre-fill everything; athlete
adjusts only what doesn't fit.

### Why a preview at the bottom

Today, athlete enters code → tap → sub. If the plan doesn't fit, the
ONLY way to find out is by looking at the calendar after subscribing.
By then it's a bad first impression.

A preview of week 1, rendered live as the athlete adjusts their inputs,
makes the form feel like "configure my plan" not "fill out a form."
Same data, dramatically different perceived effort.

### What each section writes to

| Section | Writes to |
|---|---|
| Goal time | `athlete_pace_profiles.goal_race_distance` + `<distance>_pace_seconds` |
| Rest day | `athlete_plan_subscriptions.rest_day_of_week` (NEW field) |
| Quality days | `athlete_plan_subscriptions.preferred_quality_dows[]` (NEW field) |
| Long run day | `athlete_plan_subscriptions.long_run_dow` (NEW field) |
| Starting volume + ramp | `athlete_plan_subscriptions.volume_ramp` jsonb (NEW field) |
| Shape preferences | `athlete_plan_subscriptions.shape_prefs` jsonb (NEW field) |
| Start date | `athlete_plan_subscriptions.start_date` (existing) |

The new pattern: **`athlete_plan_subscriptions` becomes the
per-subscription customization layer.** The plan template holds the
coach's defaults; the subscription holds the athlete's overrides; the
materializer reads both.

---

## 4. Data model additions

### `athlete_plan_subscriptions` — extend with athlete preferences

```sql
ALTER TABLE athlete_plan_subscriptions
  ADD COLUMN IF NOT EXISTS rest_dows INTEGER[] DEFAULT '{}',
    -- Multi-day. Empty array = no forced rest. Athlete decides; no nudge.
  ADD COLUMN IF NOT EXISTS preferred_quality_dows INTEGER[],
  ADD COLUMN IF NOT EXISTS long_run_dow INTEGER
    CHECK (long_run_dow IS NULL OR (long_run_dow BETWEEN 0 AND 6)),
  ADD COLUMN IF NOT EXISTS volume_ramp JSONB,
  ADD COLUMN IF NOT EXISTS shape_prefs JSONB,
  ADD COLUMN IF NOT EXISTS current_weekly_mileage NUMERIC(5,1);
    -- Athlete-reported baseline at subscribe time. Drives the ramp start.
    -- Re-fetched from logs on reopen if available.

-- Element-level check on rest_dows array
ALTER TABLE athlete_plan_subscriptions
  ADD CONSTRAINT rest_dows_valid
    CHECK (rest_dows <@ ARRAY[0,1,2,3,4,5,6]);
```

`volume_ramp` shape:
```ts
{
  start_mileage: number,           // first week's target (from athlete-reported or log avg)
  ramp_to_coach_target: boolean,   // true = ramp; false = use coach's range as-is
  ramp_weeks: number               // typically 4
}
```

`shape_prefs` shape:
```ts
{
  strides_pre_quality: boolean,    // default true
  recovery_after_long: boolean,    // default true
  doubles_on_easy_days: boolean    // default false
}
```

**Why multi-day rest** — Q3 resolved: athlete picks zero, one, or many. `rest_dows: []` means no forced rest. `rest_dows: [4]` is Friday rest. `rest_dows: [0,3]` is Mon + Thu rest. The materializer iterates the set, marking each day as `rest`.

### Goal goes to `athlete_pace_profiles`, not the subscription

Goal time is athlete-level, not subscription-level. The card I shipped
(`GoalAndPacesCard.swift`) reads from `athlete_pace_profiles`. The
onboarding's "Your Goal" section writes to that table.

---

## 5. `subscribe-to-plan` edge function changes

Today, the function reads the plan template and applies coach's
defaults. Update it to **layer** athlete subscription preferences on
top:

```ts
// Pseudocode — actual change goes in supabase/functions/subscribe-to-plan/index.ts
const subPrefs = body.subscription_preferences ?? {};

const restDay = subPrefs.rest_day_of_week ?? template.rest_day_of_week ?? null;
const qualityDows = subPrefs.preferred_quality_dows ?? coachQualityDows(template);
const longRunDow = subPrefs.long_run_dow ?? coachLongRunDow(template);
const targetMilesByWeek = subPrefs.volume_ramp
  ? rampMileage(subPrefs.volume_ramp, template)
  : template.weeks.map(w => avg(w.targetMilesMin, w.targetMilesMax));
const shapePrefs = {
  ...DEFAULT_SHAPE_PREFS,
  ...(template.shape_prefs ?? {}),
  ...(subPrefs.shape_prefs ?? {})  // athlete's wins
};
```

Order of precedence: **athlete's subscription > template's defaults >
hardcoded fallback**.

---

## 6. iOS `JoinCoachPlanSheet` — the rebuild

Today the file is ~250 LOC, single sheet with code + start date +
optional goal. Rebuild as `JoinCoachPlanFlow.swift` (or rename in
place) — one ScrollView with 6 sections.

Section components (one each):
- `GoalSection` — radio: coach's pace vs my goal time, plus distance picker
- `RestDaySection` — 7 day buttons; one selectable (or none)
- `QualityDaysSection` — 7-day checkbox row + long-run day picker
- `VolumeSection` — current vs prescribed mileage + ramp toggle
- `ShapeSection` — 3 toggles
- `StartDateSection` — date picker, defaults to next Monday

Plus:
- `LivePreview` at the bottom — re-renders as state changes. Shows week 1's materialized days using on-device pace math + the same easy-fill logic the edge function uses (or a simplified preview).

### Live preview implementation

Don't call the edge function for the preview — that's a network round
trip per state change. Instead, **port a simplified version of the
materializer to iOS** as `PlanPreviewMaterializer.swift`. It produces
a one-week preview from the athlete's selections + the coach's
template. The actual subscribe still goes through the edge function;
the preview is just a visual confirmation.

---

## 7. Migration phasing — 4 PRs, each shippable

### Phase 1 — DB migration (1 PR, deploy independently)
- [ ] Add 5 new columns to `athlete_plan_subscriptions` (rest_day, quality_dows, long_run_dow, volume_ramp, shape_prefs)
- [ ] Index on `(athlete_user_id, status)` for the subscription lookup

Independently shippable. Edge function ignores new fields until Phase 3.

### Phase 2 — `JoinCoachPlanSheet` rebuild (iOS only, ~1 day)
- [ ] Refactor existing sheet into 6 sections + live preview
- [ ] Sections write to local state only — submit collects everything
- [ ] Submit calls existing `subscribe-to-plan` with the new
  `subscription_preferences` body field

iOS ships before edge function reads the new field. The new field is
silently ignored by the old edge fn — no breakage.

### Phase 3 — `subscribe-to-plan` reads preferences (1 PR, ~half day)
- [ ] Read `subscription_preferences` from request body
- [ ] Persist to `athlete_plan_subscriptions` (the columns from Phase 1)
- [ ] Apply preferences to materialization: rest day, quality dows, long run dow, volume ramp, shape prefs

Only ships after Phase 1 + 2 are out. After this lands, the new
onboarding flow's preferences actually shape the materialized plan.

### Phase 4 — preview live-renders (iOS, ~half day)
- [ ] Port simplified materializer to `PlanPreviewMaterializer.swift`
- [ ] Wire to onboarding's local state — re-renders week 1 as athlete adjusts inputs
- [ ] Confirm sub button is disabled until at least Goal + Start Date are answered

Polish, but the most rewarding part of the UX.

### Phase 5 — "Edit subscription" entry point (iOS, ~half day)

Resolved Q4: subscriptions are always editable. The same sheet used for
onboarding becomes reopenable mid-plan.

- [ ] Add an "Edit preferences" entry point on the Plan tab. Likely lives in `TrainingPlanView`'s toolbar `⋯` menu next to "Edit Goal," OR as a tap target on the existing plan-header banner.
- [ ] Reuse `JoinCoachPlanFlow.swift` in "edit mode": same sections, same fields, defaults pre-filled from existing `athlete_plan_subscriptions` row.
- [ ] Submit calls `subscribe-to-plan` with `mode: "rematerialize"` (new field) — which:
  - Updates the subscription row's preference columns
  - Re-runs materialization for FUTURE weeks only (current week onward)
  - Frozen past weeks stay as-is
- [ ] Show a clear "this rebuilds your plan from this week forward; past workouts stay" warning before the rematerialize fires.

**Why future-only:** rebuilding past weeks would erase completed workouts and break analytics. The athlete decided what they did; the system shouldn't second-guess.

---

## 8. Resolved questions (2026-04-25)

1. ✅ **Goal precedence — coach plan anchor vs athlete goal time.** **Coach anchor wins when present.** Athlete goal fills the gap when no coach anchor is set. The onboarding's Goal section makes this visible: "This plan is built for a 2:25 marathon. Train at coach's paces (recommended) OR set my own."
2. ✅ **Mileage history baseline.** **Ask the athlete what their current weekly mileage is** during onboarding. If they have a log history, pre-fill from logs (last 4-week rolling average). If they have none / answer "I'm new," default to the coach's lower bound. The volume ramp uses this answer as the start.
3. ✅ **Rest days — athlete decided.** Allow **zero, one, or multiple** rest days. No nudge, no recommendation. The athlete picks. Multi-select picker. Materializer respects whatever set is chosen.
4. ✅ **Modifiable mid-plan.** **Always editable.** The onboarding sheet is reopenable from the Plan tab as "Edit subscription preferences" — same sections, same fields, same materializer rerun on save. Subsequent changes apply to FUTURE weeks only; past weeks stay frozen.
5. **What about athletes who can ONLY do quality on certain days (e.g., Tue and Sat because of a track group)?** The Quality Days picker handles this — they tap exactly the days they can do quality. The materializer respects the selection.
6. **Start date snapping.** Currently the edge function snaps to Monday regardless. Should the onboarding warn the athlete? Recommend: show "starts Monday Apr 28 (we snap to Monday-anchored weeks)" inline in the date picker.
7. **Two coaches, two plans?** Athlete subscribed to two plans currently isn't supported (RLS / unique constraint TBD). If we ever support it, the onboarding handles one plan at a time anyway.

---

## 9. Brand-voice copy guide

The current sheet has placeholder copy; the rebuild should match brand
voice (`brand-voice.md` if not yet written; pattern is direct, measured,
no hype). Sample copy:

| Section | Bad copy | Brand-voice copy |
|---|---|---|
| Goal | "What's your goal? 🎯" | "Your goal anchors every pace in the plan." |
| Rest Day | "Pick a rest day! 💆" | "Pick a day off. Or skip — adaptive plans don't require one." |
| Quality | "When do you want hard workouts? 💪" | "Coach calls for 2 quality days per week. Pick when you can do them." |
| Volume | "How fit are you? 📈" | "Coach prescribes 50–60 mpw. You've averaged 32 mpw recently. We'll ramp." |
| Shape | "Customize your plan! ✨" | "Optional shape preferences. Defaults are coach's." |
| Submit | "Let's go! 🚀" | "Subscribe to plan →" |

No emoji. No exclamation points. No "we'll do this for you" — declarative
about what happens.

---

## 10. Immediate next step — pick one

**(a) Phase 1 — DB migration.** Smallest, ships independently. ~30 min. Unblocks Phase 3. **Recommended first.**

**(b) Phase 2 — iOS `JoinCoachPlanSheet` rebuild without preview.** Visible UX shift. ~1 day. Athlete sees the new flow even before Phase 3 edge fn lands; the prefs just don't yet shape the materialization.

**(c) Mockup-only HTML/SwiftUI preview.** Build a non-functional version of the screen first. ~2 hrs. Lets you eyeball density, copy, ordering before committing engineers. Recommended if any decision in §8 above is unsettled.

**(d) Skip the rebuild for now and tackle a different thread.** The current `JoinCoachPlanSheet` works (it's just minimal). If onboarding isn't the bottleneck right now, defer.

My call: **(a) → (c) → (b) → Phase 3 → Phase 4** in 5 sprints over 2 weeks. (a) is one migration, (c) is one mockup file, (b) is the visible iOS work, Phase 3 is the edge fn update, Phase 4 is preview wiring.

---

*Last updated 2026-04-25. Companion docs:
[`adaptive-plan-builder-rework.md`](adaptive-plan-builder-rework.md),
[`pace-system-rework.md`](pace-system-rework.md),
[`docs/athlete-plan-ux.md`](docs/athlete-plan-ux.md),
[`docs/build-adaptive-plan-suspension.md`](docs/build-adaptive-plan-suspension.md).*
