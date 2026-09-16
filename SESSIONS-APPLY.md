# Sessions on the server — apply notes

> **Reviewed and applied 2026-08-20.** Steps 1 and 2 are done: the module is in
> place, tests are **18 passing**, and the uploads-vs-sessions comparison was
> run against 100% of this athlete's history rather than sampled for a week —
> **it passed on all three stop-conditions.** The review also turned up two
> things this doc did not account for, both written up under
> **[Known limits](#known-limits--read-before-trusting-it)**: the 90-minute
> constant was calibrated on corrupted timestamps (it holds anyway, for a
> better reason), and **9 days of mixed local-as-UTC rows make 4 of the 41
> reported doubles fictional**. Step 3 onward is unchanged and not started.

**New file:** `supabase/functions/_shared/sessions.ts` (pure, no imports, no I/O)
**Tests:** `supabase/functions/_shared/sessions.test.ts` — **14 passing**
**Ports:** `RunningLog/RunningLog/App/SessionRollup.swift` (shipped on iOS since 2026-08-11)

---

## Why this exists

`SessionRollup.swift` already gets this right, and its header states the problem
better than I can:

> *"A session is not a day and it is not an upload. Aug 4 2026 is five Strava
> activities, which are two sessions: a 6:08am track workout (warm-up +
> threshold + cooldown) and a 5:52pm double. Rolling to the day reports one
> 15.7 mi threshold day that never happened; rolling to the upload reports five
> runs that never happened either."*

**It exists only on iOS, and only The Sheet uses it.** Every edge function,
every analyzer, `trends-timeline`, and the old dedup sweep count *uploads*.
(One partial exception, found 2026-08-20: `_shared/shared/sessions.ts` has a
weaker `groupIntoSessions()` that `buildLoadMetrics.ts` alone uses — see
**Known limits · name collision**.) The
regression test states the cost exactly:

```
rows.length          = 5   ← what every server aggregate counts today
weeklyTotals.sessions = 3   ← what you actually ran
weeklyTotals.miles    = 20.3 (unchanged — only the COUNT was wrong)
```

Miles were never the problem. **"8–16 runs a week"** in `WEEK-TAB-APPLY.md §0` is
an upload count, and the real number of sessions is lower. Every per-run average
computed server-side — pace per run, load per run, easy share by run count — has
been divided by the wrong denominator.

## The two rules

**1 · Local day, never UTC.** `workout_date` is `timestamptz`. Grouping by
`(workout_date AT TIME ZONE 'UTC')::date` misplaces an Aug 5 7:01pm run onto
Aug 6 — `SessionRollup.swift:125` measures the damage at **8 rows / 39.2 mi** of
this athlete's history. Timezone comes from `athlete_settings.timezone`
(`20260615210000`, `NOT NULL DEFAULT 'UTC'`).

**2 · The gap is measured from the previous piece's END, not its start.**
90 minutes. Using start-to-start instead would split a long tempo from its own
cooldown.

> **Corrected 2026-08-20.** This section used to justify 90 with *"Jul 21 2026's
> warm-up-to-cooldown gap is 65 minutes."* That gap is an artifact — the two
> rows it measures are stored local-as-UTC, and the threshold between them is
> not, so what looked like wu→cd is really wu→cd *with the workout missing*.
> See **Known limits · timestamps** below.
>
> The constant survives anyway, for a better reason. Over all 80 same-day
> end-to-start gaps in this athlete's repaired history the distribution is
> sharply bimodal: **the largest gap inside a session is 73 min, the smallest
> gap between sessions is 236 min, and nothing lands in between.** Any constant
> in (73, 236] produces identical grouping. 90 is not load-bearing to the
> minute, which is the property you want in a threshold. Locked by the test
> `90 minutes sits in a genuinely EMPTY band`.

## What the tests lock down

| Test | Guards |
|---|---|
| wu + tempo + cd is ONE session | your original question |
| a genuine double is TWO sessions | the other half of it |
| morning workout + evening double = 2 sessions, 4 pieces | both at once |
| 65-min gap stays one session | the Jul 21 case |
| 2-hour gap splits | the shakeout case |
| 7:01pm run belongs to the day it was run | the UTC bug |
| UTC-boundary double doesn't merge | the same bug the other way |
| named for the hardest piece | a track day isn't "recovery" |
| unknown type never names the session | `firstIndex(of:)` returning nil |
| mood from the named piece | Aug 4's cooldown memo (RPE 3) vs the session's (RPE 7) |
| Strava junk titles aren't words | "Morning Run" as a diary quote |
| zero-distance rows excluded | a strength row making a day look like a double |

## Wire it up, in this order

**Step 1 — drop the files in, run the tests. ✅ DONE 2026-08-20.**
Both files are in `supabase/functions/_shared/`. **18 passing** (the original 14
plus 4 added by the real-data review below). Nothing consumes them yet.

```bash
deno test supabase/functions/_shared/sessions.test.ts
```

**Step 2 — compare before switching. ✅ DONE 2026-08-20, and it passed.**

The plan here was to shadow-log `trends-timeline` for a week. That was run
instead against **100% of this athlete's history** (295 rows / 261 with miles,
all 120+ days), which is strictly stronger than a week of sampling. Result:

```
uploads (rows)          : 295
uploads with miles > 0  : 261
SESSIONS                : 222      <- 15% fewer than the number every
pieces in sessions      : 261         server aggregate reports today
days run                : 181
doubles                 : 41
quality sessions        : 46
miles (sessions)        : 1707.24
miles (raw upload sum)  : 1707.22   <- delta 0.02, pure rounding
```

All three stop-conditions hold: `sessions <= uploads` ✅, every running row
lands in exactly one session (`pieces == uploads>0`) ✅, miles agree to
rounding ✅. The port is sound.

The `WEEK-TAB-APPLY.md §0` claim is confirmed too — by week, uploads vs
sessions:

| week | uploads | sessions | doubles | days run | miles |
|---|---|---|---|---|---|
| 2026-06-29 | 10 | 9 | 2 | 7 | 66.6 |
| 2026-07-06 | 9 | 7 | 1 | 6 | 56.8 |
| 2026-07-13 | 11 | 9 | 2 | 7 | 72.6 |
| 2026-07-20 | 10 | 9 | 3 | 6 | 60.2 |
| 2026-07-27 | 9 | 7 | 0 | 7 | 63.0 |
| 2026-08-03 | 16 | **11** | 4 | 7 | 77.4 |
| 2026-08-10 | 13 | 11 | 4 | 7 | 71.4 |

And the Aug 4 case from the header reproduces exactly: 5 activities → a
3-piece 10.7 mi threshold at 6:08am and a 2-piece 5.0 mi double at 5:52pm.

**What still gates a consumer switch is not the port — it is the data. Read
"Known limits · timestamps" before wiring `trends-timeline`.**

**Step 3 — promote it into the iOS side too.** Right now the same rule exists
twice, in two languages. `SessionRollup.swift`'s own header flags the debt:

> *"Promote it into `LogDedup.swift` once The Sheet has proven out on device —
> at which point the six call sites need a before/after totals check, not a hope."*

Do not skip the totals check. Two implementations drifting apart is worse than
one imperfect one.

**Step 4 — then the analyzers.** `easy_discipline`, `long_run_share` and
everything in `ANALYZER-PROMOTION-APPLY.md` should count sessions, not uploads.
This is the piece that has to exist first, which is why it moved ahead of them.

## Known limits — read before trusting it

- **⛔ TIMESTAMPS — the one that actually blocks a consumer switch.**
  *(Found 2026-08-20; this section did not exist in the original.)*
  Session grouping is only as good as `workout_date`, and `workout_date` is
  known-bad. **108 of this athlete's 261 running rows are stored local-as-UTC** —
  a 6:05am run written as `06:05Z` instead of `11:05Z`. The authoritative
  detector is the one from the backfill note, not a clock heuristic:

  ```sql
  source = 'strava' AND external_streams->'meta'->>'start_date' IS NULL
  ```

  Legacy window **2026-03-25 … 2026-08-13** (the backfill note says it ends
  Jul 21 — it does not; `2026-08-13` is in it). The damage is visible in the
  local start-hour histogram as a phantom 01:00–04:00 cluster that mirrors the
  real 06:00–09:00 one 5 hours early:

  ```
  01:00  ############################ 28     <- phantom
  02:00  #################### 20             <- phantom
  03:00  ############## 14                   <- phantom
  04:00  ######### 9                         <- phantom
  05:00  ### 3
  06:00  ################################################### 51   <- real
  07:00  ######################## 24
  08:00  ######################## 24
  ```

  Note the histogram only *shows* 69 of the 108 — a shifted 5pm run lands at
  noon, still daytime. **The clock is a smoke alarm; the SQL above is the
  census.** Two regimes, and only one is harmless:

  - **71 days are shifted in their entirety.** Grouping survives; only the date
    can be wrong. Tolerable.
  - **9 days MIX shifted and correct rows.** Grouping is *destroyed* — pieces
    interleave in an order that never happened, and the model invents sessions
    out of it. Affected days: `2026-03-31, 04-04, 04-10, 04-14, 05-07, 05-29,
    07-18, 07-21, 08-13`.

  Jul 21 is the worked example, and it is the day this doc originally cited as
  its calibration:

  | | sessions | the threshold session |
  |---|---|---|
  | as stored | **3** | 7.5 mi, 1 piece |
  | timestamps repaired (+5h) | **2** | 10.5 mi, 3 pieces |

  The warm-up and cooldown get torn off the workout and become a phantom
  "1:05am session". Across the whole history:

  | | as stored | repaired (DST-aware) |
  |---|---|---|
  | sessions | 222 | **218** |
  | doubles | 41 | **37** |
  | quality sessions | 46 | 45 |
  | days run | 181 | 181 |
  | miles | 1707.24 | 1707.24 |

  **So 4 of the 41 doubles this endpoint would report are fictional.** Miles are
  untouched — as everywhere else in this doc, only the counts were wrong.

  This is the deferred `workout_date` local-as-UTC backfill, and sessions are
  the consumer that makes deferring it expensive. **Either run the backfill
  before a consumer trusts a session count, or accept that the 19 mixed days
  are wrong and say so wherever the number is printed.** `buildSessions` cannot
  detect this — a corrupted timestamp is a perfectly valid timestamp.

  The cheap guard ships alongside it:

  ```ts
  const { suspect, mixedDays } = assertPlausibleStartHours(rows, tz);
  if (mixedDays.length) {
    console.warn("[sessions] %d rows pre-5am; %d MIXED days — counts unreliable: %s",
      suspect.length, mixedDays.length, mixedDays.join(","));
  }
  ```

  Nobody starts a run between midnight and 5am, so a nonzero count means the
  session numbers built from those rows are not trustworthy. It is deliberately
  a smoke alarm: it needs only `workout_date`, catches ~two-thirds of the
  corruption, and never fires on clean data. When you need the true count, run
  the SQL detector — `buildSessions` never sees `external_streams`. Locked by
  three tests (`REAL DATA: …`, `the guard flags the phantom pre-5am cluster`).

- **⚠️ NAME COLLISION — `sessions.ts` now exists twice, with different rules.**
  *(Found 2026-08-20.)* The claim above that *"nothing server-side had a session
  concept"* is not quite right. `_shared/shared/sessions.ts` has shipped a
  `groupIntoSessions()` since June, extracted verbatim from `athlete-state.ts`,
  and `builders/buildLoadMetrics.ts` consumes it as `sessions7d`. It disagrees
  with this port on both rules — **UTC** calendar day, and **3h start-to-start /
  1.5h end-to-start** instead of 90min end-to-start. The UTC-day rule alone
  misfiles 10 rows / 45.2 mi of this athlete's history onto the wrong date.

  Both files now carry a header pointing at the other. That is a guard, not a
  fix: two modules named `sessions.ts` two directories apart, exporting two
  different definitions of a session, is a bug waiting to happen. **Recommend
  renaming the older one to `loadSessions.ts`** — one consumer, one import line,
  and it removes the ambiguity permanently. Not done here because it touches
  tracked code this doc's Step 1 was explicitly scoped away from.

- **Timezone is current, not historical.** A run logged while travelling is
  bucketed by the athlete's timezone *setting now*, not the zone they were in.
  The Swift has the same limitation (`Calendar.current`). Correct fix is storing
  a per-activity UTC offset at ingest; Strava supplies one. Not done here.
- **`athlete_settings.timezone` defaults to `'UTC'`.** For any athlete who never
  set it, this behaves exactly like the bug it fixes. **Check the column is
  populated before trusting a single number** — and make onboarding set it.
- **It does not fold cross-source duplicates.** That is `dedupe_v2`'s job, and
  it must run first. Sessions assume the rows they are given are real.
- **The Swift folds voice-memo rows in via `dedupedByPhysicalWorkout()`; this
  port does not.** It has no `audioUrl` or folded-row concept, so a voice log
  that is a *separate row* from its GPS run will not attach. `mood` still
  resolves when the memo is on one of the session's own pieces. Worth adding
  once a consumer needs it — flagged rather than silently different.

## Then: the rest of the build

With sessions and dedup in place, `BUILD-THE-READ.md` becomes safe to run:

| Phase | What | Gate before moving on |
|---|---|---|
| A1 | `dedupe_v2` — stop the deletion | pair list is clean |
| A2 | **this** — sessions on the server | ✅ port verified on 100% of history; **now gated on the `workout_date` backfill, not the port** |
| B | golden-fixture tests for the 11 existing analyzers | arithmetic verified, not just empty states |
| C | `long_run_share`, then `easy_discipline` off the laps + pace chart | §2.0 of the analyzer doc |
| D | the weekly Read | every number it prints traces to a tested analyzer |

The order is not negotiable in one respect: **D cannot be trusted before B.**
The narration guard stops the model inventing numbers; nothing stops a wrong
number that Layer 1 computed, and the weekly Read attaches provenance to
everything it prints.
