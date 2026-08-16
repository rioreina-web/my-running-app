# llm-runaway-sim

Reproduces the 2026-08-11 Gemini cost runaway against a throwaway Postgres, then
proves the migrations stop it.

```bash
./run.sh
```

Touches nothing real — no Supabase, no network, no Gemini. Spins up its own
Postgres in a temp dir, loads a stub schema with the **pre-fix** trigger
definitions, and tears everything down on exit. ~20 seconds.

Needs the postgresql-16 client and server binaries (`brew install postgresql@16`
on macOS; set `PGBIN` if they are not on your `PATH`).

## What it checks

**The loop itself.** Stamping `structure_parsed_at` on a training log — what
`parse-workout-structure` does on success — used to create a *new*
`workout_parse_jobs` row for that same log. Completion manufactured its own next
assignment. The run prints `jobs_after_writeback` before the migrations (`1`) and
after (`0`).

**That the feature still works** (A1–A5). The loop is easy to stop by breaking
re-parsing entirely, which would be worse than the bug — an athlete's words would
silently stop reshaping their run. These assert that real edits still queue work
and only no-op writes are ignored.

**The ceilings** (B–E). Per-subject 6/24h catches a single row stuck in a cycle.
Global 250/day catches everything else. D is the important one: when the budget is
spent the dispatcher must claim *nothing*, because claiming burns a retry and
would exhaust jobs that never actually ran.

## When to run it

Before applying anything to production, and any time you touch a trigger on
`training_logs` or `workout_notes` — that pair is where the cycle lived, and the
failure mode is silent and expensive.

## Adding a case

Add to `02-guards.sql` in the existing shape. Anything matching `^[A-E][0-9]` with
a boolean second column is picked up automatically:

```sql
SELECT 'B4 my new case' AS check, <expression that should be true> AS pass;
```

## The trap this encodes

Postgres fires `AFTER UPDATE OF <cols>` when a column is **assigned**, not when
its value **changes**. Writing `'felt good'` over `'felt good'` counts. Every
enqueue trigger therefore needs an explicit `IS DISTINCT FROM` guard — the column
list is not one.
