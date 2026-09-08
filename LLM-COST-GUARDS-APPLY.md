# LLM cost guards — apply notes

**Status:** migrations written and tested in simulation, **not yet applied to prod.**
**Holding action already taken:** cron job 25 (`dispatch-workout-parse`) is
`active = false` in production as of 2026-08-13. The loop cannot restart when
Gemini credits are topped up.

---

## What happened

On 2026-08-11, `parse-workout-structure` made **1,269 Gemini calls** (normal is
single digits) and stopped only because the Gemini prepaid balance hit zero. Cost
was roughly $5–6 of the ~$6 day.

Every parse job in the queue still carries the evidence:

```
[GoogleGenerativeAI Error]: [429 Too Many Requests]
Your prepayment credits are depleted.
```

Reproduced in a rolled-back transaction against prod: stamping
`structure_parsed_at` on a `training_logs` row creates a **new**
`workout_parse_jobs` row for that same log. `jobs_before=0 jobs_after=1`.

### The cycle

1. `parse-workout-structure` writes `parsed_structure` + `structure_parsed_at`
2. `trg_mirror_training_log_to_notes` is registered on **every** `training_logs`
   update, so that stamp wakes it
3. the mirror re-writes `workout_notes` with `cleaned_text` / `raw_transcript` in
   the SET list — unchanged, `COALESCE`d deliberately so a partial write cannot
   blank the athlete's words, but **assigned**
4. `trg_enqueue_workout_parse_from_note` is `AFTER UPDATE OF cleaned_text,
   raw_transcript, run_id`. Postgres fires that on **assignment, not on change**.
   It queues a parse and resets `attempts` to 0
5. `dispatch_workout_parse` retires a job only when
   `structure_parsed_at >= job.created_at` — and the new `created_at` is always
   microseconds *later* than the stamp that caused it, so the job is permanently
   un-retireable
6. one minute later, back to step 1

The `attempts < 3` cap never engaged because step 4 zeroed it every cycle. The
only brake that worked was the 10-minute per-job backoff, which is why this cost
~$5/day rather than ~$300/day.

### Why nothing caught it

`daily-llm-spend-alert` reads `yesterday_llm_spend` → `usage_tracking`. That
table has 160 rows, but **every one of them is `feature = 'coaching'`, written
only by `coaching-agent`.** No parse, insight, or daily-read call has ever been
recorded. See `COST-AUDIT-2026-08-13.md` §1d for the mechanism: the `feature`
CHECK constraint allowed only three labels, supabase-js returns constraint
violations in the result object rather than throwing, and no call site checked —
so unlisted labels were dropped **silently**.

The alert was not reading an empty table. It was reading a table that could only
ever see the cheapest surface.

---

## The four layers

Four independent failures had to line up. Any one of them working would have
contained this. Migrations 1–3 supply three of them; layer 4 is the follow-up.

| | Failure | Fix | Where |
|---|---|---|---|
| 1 | Trigger fired on a no-op write | `IS DISTINCT FROM` guards | `20260813180000` |
| 2 | Retry cap reset itself to zero | per-subject ceiling, 6 / 24h | `20260813180100` |
| 3 | Dispatcher had no ceiling | global ceiling, 250 / day, hard stop | `20260813180100` + `…200` |
| 4 | Spend alarm could not see the expensive surfaces | widened CHECK + pricing rows + real token writes | `20260813120000`, already written — see `COST-AUDIT-2026-08-13.md` |

Layers 1 and 2 fix bugs we can see. **Layer 3 is the one that means "never
again"** — it is bug-agnostic, so a future runaway of a shape nobody predicted
hits the same wall.

### Relationship to the 2026-08-13 cost audit

These migrations are **complementary to, not a replacement for**,
`COST-AUDIT-2026-08-13.md`. That audit covers 2026-08-**12** — the Daily Read
running a frontier model, regenerated on every iOS foreground because the
short-circuit only returns cached rows at `status = 'completed'` and that day's
row was `failed`. It has already shipped model downgrades, an abort-on-API-error
retry rule, and a SELECT-only client.

This file covers 2026-08-**11** — a different day and a different mechanism: a
database trigger cycle in the parse queue, 1,269 calls, not identified in that
audit (which sees only its 23 downstream failures). Neither set of fixes catches
the other's bug.

**Apply `20260813120000` first** — it is older and these do not depend on it, but
keeping migration order aligned with timestamps avoids a confusing history.

### `llm_call_ledger` vs `usage_tracking` — not a second dedup-rules situation

Two tables that both look like "a record of LLM calls" is exactly the drift that
produced six competing dedup rules (`INGESTION-AUDIT-2026-08-12.md`). The
boundary is deliberate and should stay crisp:

| | `llm_call_ledger` | `usage_tracking` |
|---|---|---|
| Written | **before** the call, by the dispatcher | **after** the call, by the edge function |
| Answers | "may I spend?" | "what did it cost?" |
| Needs | to be cheap and always present | to be accurate |
| If it is wrong | we over- or under-throttle | we misreport spend |

Enforcement cannot read `usage_tracking`, because a call that never returns never
writes a row — and a runaway whose calls all fail is precisely the case the
ceiling must catch. If these are ever merged, the ledger's pre-call write is the
half that must survive.

---

## The migrations

### `20260813180000_stop_no_op_writes_from_enqueueing_parses.sql`

Adds `IS DISTINCT FROM` guards to `enqueue_workout_parse_from_note()` and
`enqueue_workout_parse()`, so a write that changes nothing queues nothing. Also
narrows `trg_mirror_training_log_to_notes` to the columns the mirror actually
reads.

**The guard is the load-bearing change**; the column list is belt-and-braces.
Note: if a future column needs mirroring it must be **added to that trigger's
column list**, or it will silently stop mirroring on update.

Also fixes the same class of bug on the `training_logs` side, where
`stream_arrived` fired on any assignment to `external_streams`, changed or not.

### `20260813180100_llm_call_ledger_and_budget_guard.sql`

- `public.llm_call_ledger` — one row per dispatched call. Written at **dispatch**
  time, not completion: a runaway that fails 100% of the time is still a runaway.
- `public.llm_budget` — single-row config. Ceilings are a table, not a constant,
  so raising it for a known backfill is an `UPDATE` and a revert, no deploy.
- `llm_budget_allows(surface, subject, user)` — the single answer to "may I spend
  money". Records the call and returns true, or returns false having dispatched
  nothing.
- `llm_budget_headroom()` — read-only; asking does not spend.
- `llm_budget_note_trip(surface)` — Slack alert, once per calendar day.
- `llm_spend_today` — reporting view.

### `20260813180200_wire_budget_guard_into_dispatchers.sql`

Puts `dispatch_workout_parse` and `dispatch_rpe_extraction` behind the guard.
Bodies are otherwise unchanged.

The pre-check happens **before** the claim statement, because claiming increments
`attempts` — checking after it would burn a retry on every job every minute and
exhaust jobs that never ran. The per-job check happens **after** the claim, on
purpose: a job that keeps tripping the loop detector *should* burn its attempts
and fall out of rotation, with `last_error` recording why.

---

## Not covered yet

`coaching-daily-read`, `drain-coach-insight-jobs`, `drain-coachable-moment-jobs`,
`ask` and the rest call Gemini from **inside the edge function**, not through a
SQL dispatcher, so they are not behind the ceiling. Each needs an RPC call to
`llm_budget_allows()` at the top of its handler — roughly three lines per
function. Until then the ceiling covers the two paths that have actually run away
through SQL.

The *cost* of those surfaces is already addressed by the 2026-08-13 work (model
downgrades, SELECT-only client). What is still missing is the *containment*: if
one of them develops a new loop, nothing stops it. That is the highest-value
remaining task in this workstream.

A ranking to do them in, by observed volume during the incident:
`coaching-daily-read`, then `process-training-memo` (33 invocations in one hour
per the cost audit), then the two drains, then `ask`.

---

## Verify before applying

```bash
scripts/llm-runaway-sim/run.sh
```

Throwaway Postgres, no network, no Supabase. Prints `jobs_after_writeback` = 1
before the migrations and 0 after, then 16 regression and ceiling checks.

## Apply

```bash
supabase db push
```

## Then, in order

1. Confirm against prod that the loop is dead — the rolled-back reproduction
   should now report `jobs_after=0`:

   ```sql
   DO $$
   DECLARE _log_id uuid; _before int; _after int;
   BEGIN
     SELECT t.id INTO _log_id FROM training_logs t
       JOIN workout_notes n ON n.run_id = t.id
      WHERE (t.source IN ('voice_log','check_in') OR t.audio_url IS NOT NULL) LIMIT 1;
     SELECT count(*) INTO _before FROM workout_parse_jobs WHERE training_log_id = _log_id;
     UPDATE training_logs SET structure_parsed_at = now() WHERE id = _log_id;
     SELECT count(*) INTO _after FROM workout_parse_jobs WHERE training_log_id = _log_id;
     RAISE EXCEPTION 'ROLLBACK-RESULT: before=% after=%', _before, _after;
   END $$;
   ```

2. Clear the six jobs stuck at `attempts = 3` with the depleted-credits error:
   `UPDATE workout_parse_jobs SET attempts = 0, last_error = NULL;`

3. Re-enable the cron: `SELECT cron.alter_job(25, active := true);`

4. Watch for an hour: `SELECT * FROM llm_spend_today;` — expect single digits.

5. Only then top up Gemini credits — and do step 5 of the `COST-AUDIT-2026-08-13`
   deploy checklist first (the Cloud Console budget with the 110% disable-billing
   action, per `docs/deploy/llm-cost-controls.md`).

   **That provider-side cap is the only layer that can stop a bill this database
   cannot see.** The ceiling here governs work *we* dispatch; it cannot govern a
   loop in the iOS client hitting an edge function directly, which is exactly
   what happened on 2026-08-12. The two layers cover different halves and
   neither is sufficient alone.

## Rollback

Migration 1: re-run `20260810165403` and `20260810170000`.
Migration 3: re-run `20260810170000` and `20260807130000`.
Migration 2: `DROP` the two tables, four functions and the view.
Or disable the ceiling without a rollback:
`UPDATE llm_budget SET daily_call_ceiling = 100000;`

## Operating it

Raise the ceiling for a known backfill, then put it back:

```sql
UPDATE public.llm_budget SET daily_call_ceiling = 2000;
-- ... run the backfill ...
UPDATE public.llm_budget SET daily_call_ceiling = 250;
```

When the Slack alert fires, find the culprit:

```sql
SELECT surface, subject_id, count(*)
  FROM llm_call_ledger
 WHERE occurred_at >= date_trunc('day', now())
 GROUP BY 1,2 ORDER BY 3 DESC LIMIT 10;
```

A single `subject_id` with a large count is a loop. A single `surface` spread over
many subjects is a backfill or a genuine traffic increase.
