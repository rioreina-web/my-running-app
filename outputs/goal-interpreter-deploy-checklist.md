# Deploy checklist — the goal interpreter ("make the app know the goal")

**Date:** 2026-06-21
**For:** whoever runs deploys (you, a developer, or an AI coding tool).
**Plain-English goal:** turn on the code we built so that saving a goal like
"Run 2:20 at CIM this year" is actually understood — correct time, the race,
and a live web lookup of the course — instead of the old "140 seconds / skip
CIM" behavior.

Everything below is already written and committed to the repo. This is just
switching it on, in the right order.

---

## What was built (so you know what you're deploying)

- `supabase/functions/_shared/prompts/parse-goal.v1.ts` — the "brain": the
  instructions that tell the AI how to read a goal.
- `supabase/functions/interpret-goal/index.ts` — the worker: runs the brain
  when a goal is saved, and triggers the race lookup for a recognized race.
- `supabase/migrations/20260620210000_extend_user_goals_for_race_goals.sql` —
  adds the columns where the understood goal is stored.
- `supabase/functions/_evals/cassettes/parse-goal.v1/*` — two safety tests.
- `RunningLog/.../GoalsView.swift` — the app now calls the interpreter on save
  (the old keyword gate that skipped "CIM" is gone).

Prerequisite: the Supabase CLI is installed and linked to the project
(`aqdijapxmjqaetursrde`), and `GEMINI_API_KEY` is already set as a function
secret (it is — every other AI function uses it). Run all commands from the
repo root.

---

## Step 1 — Add the storage columns (push the migration)

**What it does:** gives the goal a place to hold the understood version
(distance, correct time, the full interpretation). Additive and safe — it
only adds columns, changes no existing data.

```bash
supabase db push
```

**Verify it worked:**
```sql
-- should list: target_race_distance, target_time_seconds, interpretation, ...
select column_name from information_schema.columns
where table_name = 'user_goals'
  and column_name in ('interpretation','target_race_distance','target_time_seconds');
```

Do this **first** — the next steps store data into these columns.

---

## Step 2 — Turn on the interpreter (deploy the function)

**What it does:** deploys the worker that reads the goal and fires the race
lookup.

```bash
supabase functions deploy interpret-goal
```

**Verify it worked:** the command reports success, and `interpret-goal`
appears in your Supabase dashboard's Edge Functions list as ACTIVE.

---

## Step 3 — Update the app (rebuild in Xcode)

**What it does:** makes the app actually call the interpreter when you save a
goal (instead of the old keyword-gated lookup).

- Open the project in Xcode.
- Build and run onto your phone/simulator (the usual ▶︎).

No special steps — the code change is already in `GoalsView.swift`.

---

## Step 4 — Test the whole thing end to end

1. In the app, create a new goal: **"Run 2:20 at CIM this year"**.
2. Wait ~10–20 seconds (the interpreter + web lookup run in the background).
3. Check the goal was understood correctly:

```sql
select goal_title, target_race_distance, target_time_seconds,
       interpretation->'named_race'->>'canonical_name' as race
from user_goals
where user_id = '03857bf3-6276-4634-b3cc-15cc6d0bc653'
order by created_at desc limit 1;
-- EXPECT: target_race_distance = 'marathon', target_time_seconds = 8400,
--         race = 'California International Marathon'  (NOT 140, NOT null)
```

4. Check it looked CIM up on the web and linked it to the goal:

```sql
select race_name, location, goal_id is not null as linked_to_goal, confidence
from race_intel
where user_id = '03857bf3-6276-4634-b3cc-15cc6d0bc653'
  and race_name ilike '%california international%'
order by created_at desc limit 1;
-- EXPECT: a fresh CIM row, linked_to_goal = true
```

If both come back as expected, the app now knows the goal.

---

## Step 5 (later) — the last wire (Phase 3)

Even after the above, one spot still needs updating: the **coach's own
summary** (`active_goals` inside athlete state) still re-reads the goal title
itself, so it can still show the old "140s" there until we point it at the
new stored interpretation instead. That's a focused change in
`_shared/athlete-state.ts` — do it **after** Step 1 has been pushed (it reads
the new columns), then redeploy the functions that rebuild athlete state.

Ask me to build Phase 3 when you're ready; it's the final piece that makes the
coach speak from the correct numbers everywhere.

---

## If something goes wrong (rollback)

- The migration is additive — nothing to roll back; unused columns are
  harmless.
- To disable the interpreter, revert the `GoalsView.swift` change (the app
  stops calling it) or delete the `interpret-goal` function in the dashboard.
  Existing goals and race intel are unaffected.
