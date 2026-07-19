# Coach-Assigned Doubles — Phase 2 Execution (built)

**Date:** 2026-07-16
**Spec:** `outputs/doubles-and-activity-types-spec-2026-07-16.md` (Part B)
**Status:** Code written + logic-tested (20/20). Pending `deno check`/`deno test`
in CI, `supabase db push`, and edge-function redeploy.

This is the doubles half of the combined spec. Activity types (Cross-Train /
Strength / Mobility + GPS/HR) — Part A — is untouched and remains queued.

## What shipped

| File | Change |
|---|---|
| `supabase/migrations/20260716120000_plan_templates_doubles_config.sql` | **New.** Adds nullable `plan_templates.doubles_config JSONB`. Append-only; RLS unchanged (table already coach-scoped). |
| `supabase/functions/_shared/doubles.ts` | **New.** Pure logic: `parseDoublesConfig`, `adaptiveDoublesCount`, `resolveDoublesConfig`, `planDoubles`. |
| `supabase/functions/_shared/doubles.test.ts` | **New.** 15 Deno tests over the four functions. |
| `supabase/functions/subscribe-to-plan/index.ts` | **Edited.** Reads coach + athlete config into the materialize context; the deferred `doubles_on_easy_days` no-op is replaced by the real generation pass. |

No new tables, no RLS changes, no changes to `scheduled_workouts` (the
`session` 1/2 column already existed).

## The safety property

`doubles_config` defaults to `NULL`, and `resolveDoublesConfig` returns `off`
for null/absent config. **Every existing athlete's plan generates byte-for-byte
as before until a coach explicitly sets a config** (or a self-coached athlete
sets `shape_prefs.doubles`). This is what makes the live-file edit safe to land
without a migration backfill or a feature flag.

## How it decides (coach-assigned first)

`resolveDoublesConfig(coach, athlete, weeklyTargetMileage)`:

1. Coach `mode:"off"` → **off** (an athlete toggle can never re-enable what a
   coach turned off).
2. Coach `assigned` / `adaptive` → coach is the base. The athlete may dial the
   count **down** or switch it off, never up.
3. No coach opinion + athlete `assigned`/`adaptive` (or legacy
   `doubles_on_easy_days:true`) → athlete config is the fallback (self-coached
   Maya).
4. Otherwise → **off**.

`adaptive` derives the count from weekly mileage: `<55 → 0`, `55–70 → 2`,
`70–85 → 3`, `85+ → 4` (coarse and tunable — spec Part G #4).

## How it places (guardrails in `planDoubles`)

Candidate easy days are filtered, then the highest-mileage ones are chosen up to
the count. A day is **excluded** if it is:

- the day before a quality session or the long run (don't blunt tomorrow),
- the post-long recovery run,
- a rest day,
- not in `eligible_dows` (when the coach pinned days),
- too small to split (`split` needs AM ≥ 2× the easy floor; `add` needs AM ≥ the
  floor),
- already doubled by a coach-authored PM run (coach-authored always wins).

PM mileage = midpoint of the range, clamped so `split` leaves at least the easy
floor (2 mi) on the AM run. `split` preserves weekly volume; `add` raises it.

## Worked example — Maya, 65 mpw, Tue quality + Sat long

Coach sets `{ mode:"assigned", per_week:2, range_miles:{min:3,max:5} }`. The
easy-fill week (Mon 6 / Wed 9 / Thu 9 / Fri 6 / Sun 5-recovery) becomes:

| Day | Before | After |
|---|---|---|
| Mon | Easy 6 | Easy 6 *(pre-quality → skipped)* |
| Tue | Quality ~11.5 | unchanged |
| Wed | Easy 9 | **Easy 5 AM + 4 PM** |
| Thu | Easy 9 | **Easy 5 AM + 4 PM** |
| Fri | Easy 6 | Easy 6 *(pre-long → skipped)* |
| Sat | Long 18 | unchanged |
| Sun | Recovery 5 | Recovery 5 *(recovery → skipped)* |

Weekly total stays ~65; the week now has 9 sessions instead of 7, doubles landing
only on the two "safe" aerobic days.

## Coach payload shape

```json
{
  "mode": "assigned",
  "per_week": 2,
  "range_miles": { "min": 3, "max": 5 },
  "distribution": "split",
  "eligible_dows": [2, 3],
  "placement": "easy_only"
}
```

Adaptive fallback (self-coached): athlete `shape_prefs.doubles = { "mode": "adaptive" }`.

## Deploy steps

1. **Push the migration** from a committed SHA: `supabase db push` (hard rule #9
   — no dashboard/MCP apply). `select("*")` on `plan_templates` means the new
   column flows into the materializer automatically.
2. **Redeploy** the `subscribe-to-plan` edge function.
3. **CI gate:** `deno test supabase/functions/_shared/doubles.test.ts` and
   `deno check supabase/functions/subscribe-to-plan/index.ts`. Logic was verified
   here via a `tsx` harness (20/20), but Deno's typecheck of the edited edge
   function is the authoritative gate and hasn't run in this environment.

## Required follow-ups before it's user-visible

- **`athlete-state.ts` per-day aggregation (spec B4).** Confirm running volume /
  ACWR / monotony sum the two sessions **by calendar day**, so a doubled day
  reads as one elevated day, not two stimuli. This is the one correctness check
  outside the materializer — verify before enabling in the coach UI.
- **Coach portal UI.** The config row (mode toggle · count · range · split/add ·
  day chips) in Plan setup, beside the existing shape flags. Until then a coach
  can only set `doubles_config` via the DB.
- **iOS.** Render AM/PM as two sessions with a `2×` marker; the journal sums the
  day.
- **Adaptive nudge for Maya.** Surface the suggestion in Coach Read / a
  coachable-moment rather than silently inserting (AI advises, never acts).

## Deliberately deferred

- **Per-week override** (`weeks[i].doublesOverride`) — plan-level config only for
  now; add later without a migration (JSON on the existing weeks blob).
- **`add`-mode vs. weekly range ceiling** (spec Part G #5) — `add` can exceed
  `targetMilesMax`; today the range readout would show AM-only. Resolve in the
  coach UI work.
