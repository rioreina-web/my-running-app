# Dedup fix — apply notes

**Migration:** `20260820120000_dedupe_v2_quarantine.sql`
**Replaces:** the sweep from `20260613240000_dedupe_training_logs_recurring.sql`
**Tested:** 13-case battery on PostgreSQL 16. **v2: 13/13. Original: 8/13.**

---

## The result that matters

Thirteen rows built from real documented training. "Truth" is what a coach
would say; only one row is an actual duplicate.

| Case | Original | v2 | Truth |
|---|---|---|---|
| Tue session — 2.1mi warm-up | kept | kept | must stay |
| Tue session — 6.2mi tempo | kept | kept | must stay |
| Tue session — 2.0mi cooldown | **DELETED** | kept | must stay |
| Mon double — 6.0 am | kept | kept | must stay |
| Mon double — 4.0 pm | kept | kept | must stay |
| Same-distance double — 5.1 am | **DELETED** | kept | must stay |
| Same-distance double — 5.2 pm | **DELETED** | kept | must stay |
| Cross-source dup — Strava 5.24 | kept | kept | must stay |
| Cross-source dup — HealthKit 5.26 | kept | **quarantined** | **should go** |
| Two runs 0.49mi apart — 5.25 | **DELETED** | kept | must stay |
| Two runs 0.49mi apart — 5.74 | kept | kept | must stay |
| UTC-boundary double — Tue 8:30pm | **DELETED** | kept | must stay |
| UTC-boundary double — Wed 6am | kept | kept | must stay |

Totals: **60.09 mi → 38.54 mi** under the original (21.55 mi destroyed, 36%).
**60.09 → 54.83** under v2, and the 5.26 removed is the genuine duplicate.

The original also **missed the one true duplicate entirely** — 5.24 and 5.26
round into different half-mile buckets. It is not merely over-aggressive; it is
wrong in both directions at once.

Worth noting what the battery exposed: on 2026-08-19 the old rule pooled the
5.1am run, the 5.2pm run **and** the 5.24 Strava copy into a single bucket-5.0
group and kept one row. A genuine double and a cross-source copy, merged into
one another.

## What changed

**1 · Time is used.** `workout_date` is `TIMESTAMPTZ` and always was. The old
rule cast it to a UTC date on its first line, so a 6am run and a 5:30pm run were
the same run. Two copies of one activity start within a couple of minutes —
that is the actual signal, and `strava-sync` (±15 min) and `WorkoutSyncService`
(±300s) already use it.

**2 · Distance is a window, not a bucket.** `round(mi*2)/2` fails both ways —
5.24 / 5.26 never merge, 5.25 / 5.74 do. The match is now
`max(0.15 mi, 3%)`.

**3 · Nothing is deleted.** Rows get `superseded_at` + `duplicate_of`. The old
sweep has run every 30 minutes since 2026-06-13 with no record of what it took.

Kept, because it was right: the sweep-not-trigger design (laps arrive after the
log row), notes and mood merged onto the keeper before anything is superseded,
and a lapped loser only touched when it shares the keeper's external key.

## Apply order

### Step 1 — stop the bleeding (do this first, on its own)

```sql
SELECT cron.unschedule('dedupe-training-logs');
```

One statement, instantly reversible, no code change. Data loss stops today.
Duplicates will slowly accumulate until step 3 — that is the correct trade.

### Step 2 — install and observe

```bash
supabase db push          # applies the migration; the function is NOT scheduled
```
```sql
-- what WOULD be marked across 120 days, writing nothing
SELECT public.dedupe_recent_training_logs_v2(120, 10, 0.15, 0.03, true);
```

Then inspect the pairs by hand before trusting it:

```sql
WITH d AS (SELECT * FROM training_logs WHERE workout_date > now() - interval '120 days')
SELECT a.workout_date, a.workout_distance_miles, a.source,
       b.workout_date, b.workout_distance_miles, b.source
FROM d a JOIN d b
  ON a.user_id = b.user_id AND a.id < b.id
 AND abs(extract(epoch FROM a.workout_date - b.workout_date)) <= 600
 AND abs(a.workout_distance_miles - b.workout_distance_miles)
     <= greatest(0.15, 0.03 * greatest(a.workout_distance_miles, b.workout_distance_miles))
ORDER BY a.workout_date DESC;
```

**Every row should be an obvious same-run pair from two sources.** If any pair
is two real runs, tighten `p_time_tol_min` to 5 and re-run. Do not proceed until
this list is clean.

### Step 3 — hide quarantined rows, then schedule

`superseded_at` does nothing on its own: **42 edge-function read paths and 27
Swift read paths** query `training_logs` and would now see the duplicates. Two
options:

**3a · View swap (recommended — tested, zero read-path edits):**

```sql
ALTER TABLE public.training_logs RENAME TO training_logs_all;
CREATE VIEW public.training_logs WITH (security_invoker = true) AS
  SELECT * FROM public.training_logs_all WHERE superseded_at IS NULL;
```

Verified in test: all reads work unchanged, and `INSERT`/`UPDATE` pass through
(a single-table view with a `WHERE` clause is auto-updatable in Postgres).
**`security_invoker = true` is mandatory** — without it the view runs as its
owner and RLS stops applying. Confirm policies still bite before trusting it.

**3b · Add `.eq("superseded_at", null)` to all 69 read paths.** More explicit,
far more places to get wrong.

Then:

```sql
SELECT cron.schedule('dedupe-training-logs-v2', '*/30 * * * *',
  $$ SELECT public.dedupe_recent_training_logs_v2(3); $$);
```

### Step 4 — the rows already gone

Everything the old sweep deleted since 2026-06-13 is **hard deleted and not
recoverable from the database.** The only route back is re-import from source —
Strava for anything it holds, HealthKit for the rest. Worth quantifying the hole
before deciding whether to bother:

```sql
SELECT date_trunc('week', workout_date) AS wk, count(*), sum(workout_distance_miles)
FROM training_logs WHERE workout_date > now() - interval '90 days'
GROUP BY 1 ORDER BY 1;
```

Weeks that read short against what you remember running are where it ate.

## Verify after applying

1. `SELECT count(*) FROM training_logs WHERE superseded_at IS NOT NULL;` — small.
2. Every quarantined row has a `duplicate_of` that resolves to a live row.
3. A day you know you doubled still shows both runs.
4. A tempo session with warm-up and cooldown still shows all three pieces.
5. Weekly mileage for a known week matches what you actually ran.
6. Restore works: `UPDATE training_logs_all SET superseded_at = NULL, duplicate_of = NULL WHERE superseded_at IS NOT NULL;`

## Two things this does not fix

- **It is still a sweep over `training_logs`, not a session model.** Warm-up,
  tempo and cooldown remain three rows. v2 stops them being *destroyed*, but
  "how many runs did I do Tuesday" still answers 3, not 1. That is
  `SessionRollup.swift`'s job, and it exists only on iOS — nothing server-side
  has a session concept.
- **The other five dedup rules still disagree with each other.** This fixes the
  one that was destructive. Collapsing all six into one shared function is item
  14 in the ingestion audit and still stands.

## The parameter that matters most

`p_time_tol_min` defaults to **10**. Lower is safer — it errs toward keeping two
rows. If step 2's pair list looks at all questionable, use 5. The cost of a
missed duplicate is a visible extra row you can delete by hand; the cost of a
false match is a run that vanishes silently. Those are not symmetric.
