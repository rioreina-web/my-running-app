# `pace_segments` from watch laps, not mile splits · apply notes

*Written 2026-08-20, from a question Rio asked of the Trends pace spectrum:
"is this chart accurate? I feel like I run a lot of volume faster on Tuesdays."*

*The chart was accurate. The data under it was not. Every number below was
measured on real rows, before and after.*

---

## 1 · The diagnosis

The Trends pace spectrum ("Pace · How many miles at each pace") buckets miles
by `training_logs.pace_segments`. Over the 4 weeks to 2026-08-19 it credited
**0.6 mi** in the 5:12–5:22/mi bucket and **9.0 mi** at 5:39/mi or faster.

`pace_segments` was built by `strava-sync` from Strava's `splits_standard` —
plain per-**MILE** autolap splits. On an easy run that is a fair sample. On a
quality day it is wrong, because one mile of an interval session contains the
work **and** the jog between reps, and the split reports their blend.

The 2026-08-18 session is the clean case. Stored mile splits:

| | mile splits (what we stored) | watch laps (what she ran) |
|---|---|---|
| 6×1mi | 5:24 · 5:29 · 6:54 · 5:34 · 6:28 · 5:33 | 5:23 · 5:31 · 5:18 · 5:35 · 5:27 · 5:36 |

The 6:54 and 6:28 "miles" are not paces she ran at all — they are a rep and a
standing recovery averaged together. Every rep lands one to two buckets slow,
and the fast tail of the histogram collapses.

**The contradiction was already on screen.** Directly under the spectrum, the
Threshold Miles card reported 21 mi / 117 min in the 5:07–5:39 band — because
it reads `running_workout_laps` via `trends-timeline` → `paceBands`, not
`pace_segments`. Two surfaces one screen apart, disagreeing, because they read
two different definitions of a segment.

It is also the same root cause as the **MILE-SPLIT GUARD** in
`_shared/coach-context.ts` (2026-08-06), which stopped the LLM narrating a
5×4:00 threshold session as "4×1 mile reps" a minute/mi slow. That guard
treated the symptom at the read side. This treats the cause at the write side.

## 2 · The fix

Strava already hands us `laps` — the watch's own lap structure, which on a
quality day **is** the rep structure. We have stored them verbatim in
`external_streams.laps` all along, and a trigger already fans them into
`running_workout_laps`. `pace_segments` was the last consumer still reading the
coarse splits.

**Laps win; mile splits are the fallback.** Splits are still used when a lap
array is absent (manual entries, some devices), when there is only one lap, or
when the laps do not cover ≥80% of the recorded distance — so nothing that
synced fine before starts failing.

### New files

- **`supabase/functions/_shared/paceSegments.ts`** — the one definition of what
  a segment is. `buildPaceSegments()`, `lapsToPaceSegments()`,
  `splitsToPaceSegments()`, `lapsAreUsable()`, `isRestLap()`. Pure functions,
  no I/O.
- **`supabase/functions/_shared/paceSegments.test.ts`** — 11 tests driven off
  the *real* recorded lap payloads for 2026-08-18 and 2026-08-11, so a change
  in what Strava sends fails the suite rather than the chart.
- **`supabase/migrations/20260820120000_backfill_pace_segments_from_laps.sql`**
  — rebuilds already-ingested rows from `external_streams.laps`. No Strava
  re-fetch, no API budget.

### Changed

- **`strava-sync/index.ts`**, **`strava-test-pull/index.ts`** — both now call
  `buildPaceSegments`; their duplicated local copies of the helpers are gone,
  so the harness and the production sync can never again disagree.
- **`_shared/coach-context.ts`** — new `"rest"` effort kind. Recoveries now
  arrive as their own segments and must never be numbered as reps (a 6×1mi
  session would otherwise narrate as twelve reps, half at 23:00/mi). And
  because explicit recoveries are *positive evidence* of rep structure, they
  stand the mile guard down — a genuine mile-rep session finally reads
  "Rep 3 @ 5:18/mi" instead of "Mile 3".
- **`RunningLog/Trends/SignalService.swift`** — recovery segments count toward
  **volume** (`comp` → daily miles → ACWR: they are miles she covered) but are
  kept out of the **pace histogram**, because standing still is not a pace.
  See §4 — this one is load-bearing, not cosmetic.

### The rest rule is defined once, copied twice, on purpose

`running_workout_laps.is_rest` is a generated column:

```sql
distance_meters < 200 OR avg_speed_mps < 2.0
```

`isRestLap()` in `paceSegments.ts` and the `CASE` in the migration mirror it
exactly. **If it is ever retuned, retune all three in the same migration.**
Two rest definitions is the contradiction this whole change exists to end.

## 3 · Measured result

Same 4-week window, same base rows, read-only against prod:

| | total mi | 5:12–5:22 | ≤5:39 | ≤6:00 | Tue ≤6:00 |
|---|---|---|---|---|---|
| before (mile splits) | 254.3 | 0.6 | 9.0 | 13.2 | 13.2 |
| after (watch laps) | 254.3 | **11.5** | **24.9** | **29.7** | **23.0** |

Three things to note:

1. **Total volume is unchanged — 254.3 both ways.** No miles invented, none
   lost. This is the safety check that matters; the change redistributes where
   miles sit on the pace axis, it does not add any.
2. **≤5:39 goes 9.0 → 24.9 mi, which reconciles with the Threshold Miles
   card's 21 mi.** The two surfaces now agree, because they finally read the
   same thing.
3. **Rio's instinct was right.** 23.0 of the 29.7 sub-6:00 miles are Tuesdays.

## 4 · The one judgement call

Recoveries now arrive as real rows at 17:00–75:00/mi — over the window, 3.3 mi
across 41 laps. Bucketed, all of it clamps into the leftmost bar and reads as
easy running that never happened.

Worse, it is *just under* the 2% tail that `SignalService.fittedBounds` trims
(3.3 / 254 = 1.3%). One extra interval week pushes it over, and the slow end of
the axis stretches to walking pace, squashing every real bar into the left
third of the chart. So this is a stability fix, not a tidiness one.

`SignalService` therefore splits what a segment counts toward: rest miles go
into `comp` (volume, ACWR — she covered them) and stay out of `paceBuckets`
(pace). Matched on the effort tag written by the sync, never by re-deriving a
threshold in Swift.

## 5 · Deploy

Per hard rule #9, the migration reaches prod via `supabase db push` from a
committed SHA — **not** the dashboard SQL editor and not MCP `apply_migration`.
It was validated instead against a scratch Postgres 16 loaded with the real
rows: `UPDATE 2` on the 8-row fixture (both interval days; the six continuous
runs untouched), idempotent on a second run (`UPDATE 0`).

1. `deno test supabase/functions/_shared/paceSegments.test.ts` — 11 pass.
2. `deno test supabase/functions/_shared/coach-context-splits.test.ts` — 14
   pass (11 pre-existing + 3 new).
3. `deno check` on both strava functions — clean.
4. Commit, then `supabase db push`.
5. `supabase functions deploy strava-sync strava-test-pull` — and any function
   importing `coach-context.ts`.
6. **Not yet done: the iOS build.** This session had no Swift toolchain (Linux
   container, no Xcode), so `SignalService.swift` is unverified by the
   compiler. Build before shipping.

### Expected blast radius of the backfill

On the data as of 2026-08-20, continuous runs (easy, long, recovery) arrive
from Strava with a **single** whole-run lap, so the ≥2 guard leaves them
exactly as they are — their mile splits were never the problem. Only lapped
quality sessions are rewritten. **Expect the updated row count to be roughly
the number of interval/threshold days in the history, not the whole table.
That is the migration working, not failing.**

### Reverting

The migration snapshots the old value into
`training_logs.pace_segments_legacy_splits` before writing. Migrations are
append-only (hard rule #5), so the revert is run by hand:

```sql
UPDATE public.training_logs
   SET pace_segments = pace_segments_legacy_splits
 WHERE pace_segments_legacy_splits IS NOT NULL;
```

Drop that column once the laps-based spectrum has been trusted for a cycle.

## 6 · What this opens up, and what it does not

**Does not fix:** runs whose watch never lapped (a continuous tempo inside an
easy run still reads as mile splits — the laps carry no more information than
the splits do there). For those, true time-at-pace needs the `velocity_smooth`
stream, which is already stored in `external_streams.streams`. That is the
next rung, and it would let the spectrum report *time* at pace rather than
mile-averaged distance. Deliberately not done here.

**Opens up:** the 2026-08-06 mile-split guard can eventually be retired for
lapped sessions, since `pace_segments` now carries genuine rep structure —
`splitsFromPaceSegments` already stands the guard down when recoveries are
present. And `paceBands` / `SignalService` now agree by construction, which
removes the class of bug where two Trends surfaces contradict each other on
the same screen.
