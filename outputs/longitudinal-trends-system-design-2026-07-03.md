# System design — multi-horizon trends & analysis

**Date:** 2026-07-03
**Question:** how do we build a system that knows an athlete's trends at
weekly / monthly / 3-mo / 6-mo / 1-yr / multi-year horizons, and turns them
into analysis the coach can use?

**Assumptions (stated, not asked):** existing stack — Supabase Postgres, Deno
edge functions, pg_cron, the `athlete_state` read-model, and the pure-function
"builders" pattern. Scale: beta today (1s–1000s of athletes), design to ~100k.
Per athlete: ~250–1000 runs over 2 years. Cost-sensitive, tiny team. Trends do
NOT need intra-day freshness; the coach read must be fast (reads pre-computed
summaries, never scans raw history live). No new heavy infra (no warehouse/
Kafka/Spark) at this scale.

---

## 1. The core idea: a rollup pyramid, built incrementally

Don't query 2 years of `training_logs` every time the coach speaks — it's slow
and blows the prompt. Instead, pre-aggregate into a **pyramid of time buckets**,
where the **week is the atomic unit** and every coarser grain rolls UP from it:

```
                         ┌───────────────┐
   multi-year / career → │  YEAR buckets │  ← rolled up from quarters
                         └───────┬───────┘
                     ┌───────────┴───────────┐
        1-yr / 6-mo →│   QUARTER buckets     │  ← rolled up from months
                     └───────────┬───────────┘
                 ┌───────────────┴───────────────┐
   3-mo/monthly →│        MONTH buckets          │  ← rolled up from weeks
                 └───────────────┬───────────────┘
             ┌───────────────────┴───────────────────┐
    weekly → │            WEEK buckets (leaf)         │  ← the source of truth
             └───────────────────┬───────────────────┘
                     ┌───────────┴───────────┐
                     │  training_logs (raw)  │  append-only, forever
                     └───────────────────────┘
```

Your `buildBlocks` builder already does a version of the month grain (6×4-week
blocks). This generalizes that into a full, persisted pyramid.

Each of your horizons maps to a grain (or a comparison across grains):

| Horizon | Served by |
|---|---|
| Weekly | the week bucket + week-over-week delta |
| Monthly / 3-mo | month buckets + month-over-month, last-3-months slope |
| 6-mo / 1-yr | quarter buckets + "vs 2 quarters ago", "this time last year" |
| Multi-year | year buckets + career trajectory / PR progression |

---

## 2. High-level design

```
 workout lands / memo processed
        │
        ▼
 [mark affected WEEK dirty]  ──►  dirty_rollups queue
        │                              │ (drain, like your drain-* workers)
        │                              ▼
        │                    [rebuild that WEEK bucket] (pure builder)
        │                              │
        │                    [cascade: recompute its MONTH → QUARTER → YEAR]
        │                              ▼
        │                    athlete_rollups  (the pyramid, one table)
        │                              │
        ▼                              ▼
 nightly reconcile ───────►  [trend + biography builder]
 (bounded sweep)                       │  deltas, slopes, seasonality, PRs, anomalies
                                       ▼
                            athlete_state.longitudinal  (compact summary)
                                       │
                                       ▼
                            coach prompt (budget-bounded, horizon-selected)
```

Components (all reuse existing patterns):

- **`athlete_rollups`** — new table, the pyramid.
- **`buildRollup`** — pure function: given a set of logs for a period, produce
  its metrics. Same style as `buildLoadDistribution` / `buildBlocks`. Fully
  unit-testable.
- **`compute-rollups`** — edge function (service-role) that drains the dirty
  queue and cascades, mirroring `compute-fitness-snapshot` and the `drain-*`
  workers.
- **`buildTrends` / `buildBiography`** — pure functions deriving analysis from
  the pyramid (below).
- **`athlete_state.longitudinal`** — new jsonb block the coach reads.

---

## 3. Data model

One table, keyed by grain — simpler to maintain and extend than a table per
grain:

```sql
create table athlete_rollups (
  user_id       text not null,
  grain         text not null check (grain in ('week','month','quarter','year')),
  period_start  date not null,          -- ISO week Monday / month-1st / etc.
  period_end    date not null,
  -- promoted hot metrics (queryable for slopes/anomalies):
  mileage           double precision,
  moving_time_s     integer,
  runs              integer,
  quality_sessions  integer,
  vol_x_intensity   double precision,   -- your load metric
  longest_run_mi    double precision,
  -- everything else evolves in jsonb (zone splits, mood, niggles, sleep, PRs):
  metrics       jsonb not null default '{}',
  source_count  integer not null,       -- # logs that fed this bucket (for dedupe/debug)
  computed_at   timestamptz not null default now(),
  primary key (user_id, grain, period_start)
);
create index on athlete_rollups (user_id, grain, period_start desc);
```

Design choices:
- **Hybrid columns + jsonb** — promote the handful of metrics you run math on
  (mileage, load) to real columns for fast slope/anomaly queries; keep the long
  tail in `metrics` jsonb so the shape can evolve without migrations.
- **`week` is the only grain computed from raw logs.** month/quarter/year are
  computed from their child grain — never re-scan raw history for them.
- **PK `(user_id, grain, period_start)`** makes every rebuild an idempotent
  upsert.

Rollup counts are tiny: ~104 weeks + 24 months + 8 quarters + 2 years ≈ **140
rows/athlete for 2 years**. 100k athletes ≈ 14M rows — nothing for Postgres.

---

## 4. Incremental maintenance (the key to not recomputing 2 years)

- **On write:** when a workout/memo lands, mark its **week** dirty (a row in
  `dirty_rollups`, or reuse the existing outbox trigger you already have on
  `training_logs`). The drain worker rebuilds that one week, then cascades up:
  recompute the month that contains it, then that quarter, then that year —
  each from its children, so each step is cheap.
- **Backfill / edited history:** same path — mark the affected periods dirty,
  the cascade corrects them. This is why weekly-as-leaf matters: any correction
  flows up deterministically.
- **Nightly reconcile:** a bounded sweep (like your `nightly-fitness-snapshot`
  cron) that re-derives the current week + rolls the current month/quarter/year,
  catching anything the on-write path missed. Belt and suspenders.

Cost per workout is **O(1)** (one week + its ancestors), not O(history).

---

## 5. Trends & analysis layer (pure functions over the pyramid)

`buildTrends(rollups)` derives, cheaply, at each horizon:

- **Deltas** — WoW, MoM, quarter-over-quarter, "vs this time last year"
  (same ISO week/month one year back — your seasonality signal).
- **Trajectory (slope)** — simple linear regression over the last N buckets
  ("volume climbing 4% / month over the last quarter").
- **PR progression** — best race/effort per distance over time, from
  `confirmed_races` + detected efforts; the multi-year through-line.
- **Anomalies** — threshold/z-score bands: volume spike or collapse,
  monotony, "you get a niggle every time you cross ~60 mpw."
- **Seasonality** — recurring patterns keyed on month/quarter across years
  ("you fade every spring", "you PR off winter base").

`buildBiography(trends)` distills that into the compact, evolving profile the
coach reads — updated **incrementally** (only re-derive the parts whose
underlying periods changed, exactly like the memory subsystem):

```
longitudinal: {
  current_trajectory: "volume up 6%/mo this quarter; fitness trending",
  vs_last_year:       "~8 mpw higher and one gear faster than this week in 2025",
  seasonal_pattern:   "spring fade 2 yrs running; strongest in Nov–Feb",
  pr_progression:     "10K 33:04 (Apr'26) ← 34:20 (Nov'25) ← 35:40 (2024)",
  volume_response:    "handles 55 mpw; niggles appear past ~60",
  multi_year_arc:     "3rd year of training; ~+18% annual volume, injury-light"
}
```

---

## 6. Consumption — feeding the coach without blowing the budget

`athlete_state` selects horizons by **relevance + prompt budget**: always the
weekly + monthly deltas and a 1–2 line multi-year arc; expand a specific horizon
on demand (Maya asks "how does this cycle compare to last year?" → pull the
quarter/year detail for that answer). The coach never sees raw buckets — it sees
the distilled `longitudinal` block, same as it sees `life_context` today.

---

## 7. Scale & reliability

- **Storage/compute:** trivial at target scale (14M rollup rows at 100k users;
  O(1) maintenance per workout). No warehouse needed.
- **Idempotent:** every rebuild is a deterministic upsert keyed on
  `(user_id, grain, period_start)`; safe to re-run, safe under retries.
- **Correct under late/edited data:** dirty-mark + cascade from the weekly leaf.
- **Monitoring:** rollup freshness (max `now() - computed_at` per grain) and
  dirty-queue depth — reuse the alerting you already have on the drain crons.
- **Reuses existing reliability primitives** (outbox trigger, drain worker,
  nightly cron) — no new operational surface.

---

## 8. Trade-offs (explicit)

- **Materialize coarse grains vs derive-on-read.** For the beta, you could store
  only weekly and derive month/quarter/year on demand (fewer moving parts, and
  weekly is small). Materializing all grains costs a little write amplification
  but makes reads and "this time last year" O(1). *Recommendation: materialize —
  the cascade is cheap and the read simplicity is worth it.*
- **One table (grain column) vs table-per-grain.** Single table is simpler and
  extensible; per-grain gives tighter types/indexes. *Start single.*
- **jsonb vs wide columns.** jsonb evolves without migrations; columns are
  faster to query. *Hybrid — promote only the metrics you do math on.*
- **On-write incremental vs nightly-only.** On-write keeps the current week
  fresh; nightly alone is simpler but stale intra-day. *Do both: on-write for
  the current week, nightly reconcile for safety.*
- **TS builders vs the Python ml-service.** Deltas/slopes/seasonality-by-lookup
  belong in TS builders (consistent, testable, cheap). *Defer to the ml-service
  only if you later want real seasonal decomposition or forecasting* — that's
  its job, not Postgres's.
- **Postgres vs a warehouse.** Correct to stay in Postgres at this scale.
  Revisit only past ~100k users or heavy ad-hoc analytics.

---

## 9. Phased build (start small, don't boil the ocean)

1. **Weekly rollups only** — `athlete_rollups` (week grain) + `buildRollup` +
   on-write/nightly maintenance. Immediately gives clean weekly/monthly trends
   and replaces ad-hoc window scans. *(Small.)*
2. **Cascade to month/quarter/year** + `buildTrends` (deltas + slope +
   this-time-last-year). Unlocks 3-mo/6-mo/1-yr. *(Small–moderate.)*
3. **`buildBiography`** — the distilled `longitudinal` profile into
   `athlete_state`, incrementally maintained. This is the piece that makes the
   coach "know you over years." *(Moderate.)*
4. **Anomaly + seasonality + PR progression** — the richer analysis, once 1+
   years of buckets exist to learn from. *(Moderate; and it needs real
   multi-year data, so it naturally comes later.)*

## What I'd revisit as it grows

- Materialize/partition rollups per user at very large scale.
- Move seasonal decomposition / forecasting into the ml-service (feature store
  if models start consuming rollups).
- Add a "career milestones" episodic layer that ties into the memory subsystem
  (PRs, comebacks) so quantitative trends and durable memories reinforce.

---

**Bottom line:** the whole thing is a rollup pyramid (weekly leaf → month →
quarter → year), maintained incrementally the same way your memory system
already works, with pure-function trend + biography builders on top and a
budget-bounded summary into `athlete_state`. It reuses every pattern you already
have (builders, outbox/drain, nightly cron, the read-model) — no new infra — and
it's the concrete answer to "does the coach understand the athlete over years."
