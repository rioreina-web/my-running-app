# Test plan — athlete_state v2 + Read v3 + keep-warm

**Date:** 2026-06-12
**Scope:** everything built in the 2026-06-12 session — `athlete_state` v2
(Phases A–E), `daily-read.v3`, the `coaching-daily-read` context fix, the
1–5 intensity-weight change, and the iOS Read-tab changes.
**Why this doc:** none of it has been compiled or deployed yet. This is the
ladder from "review-ready" to "verified," cheapest checks first.

---

## Layer 0 — Static checks (local, no deploy, minutes)

**Deno typecheck the edge functions** (catches TS errors I couldn't catch
without a compiler):

```
cd supabase/functions
deno check coaching-daily-read/index.ts
deno check rebuild-athlete-state/index.ts
deno check _shared/athlete-state.ts
deno check _shared/prompts/daily-read.v3.ts
deno check compute-workout-features/index.ts
```

Fix anything that surfaces — the athlete-state.ts changes are the most
likely to have a type slip (it's a 2,000-line file edited heavily).

**Eval harness** — DONE: `record.ts daily-read.v3` → 4/4 pass.

**iOS build** — open the project in Xcode, ⌘B. The Swift changes
(`WorkoutPresentation`, `CoachReadView`, `DripTabBar`, `EvidenceChip`) have
never been compiled. Also run the SwiftUI previews for `CoachReadView` and
`EvidenceChip` to eyeball the rendering.

**Existing unit tests** — `deno test --allow-read` over `_shared` (e.g.
`pace-engine.test.ts`, `pace_adjuster.test.ts`) to confirm the weight change
didn't break pace math.

---

## Layer 1 — Migrations (on a BRANCH, never prod first)

Three new migrations: `20260612120000_athlete_state_v2_satellites.sql`,
`20260612130000_body_mentions.sql`, `20260612140000_nightly_athlete_state_rebuild.sql`.

Per hard rule #9, push from a committed SHA to a **Supabase preview branch**,
not prod:

```
supabase db push   # against the branch
```

Then verify in the branch DB:

```sql
-- satellite columns exist
select column_name from information_schema.columns
where table_name='athlete_state'
  and column_name in ('load_distribution','fitness_prediction','memories','execution','environment','patterns','field_provenance');

-- body_mentions table + RLS
select relrowsecurity from pg_class where relname='body_mentions';      -- expect t
select policyname, cmd from pg_policies where tablename='body_mentions'; -- service-role ALL + owner SELECT

-- cron scheduled
select jobname, schedule from cron.job where jobname='nightly-athlete-state-rebuild';
```

---

## Layer 2 — Edge-function smoke tests (after deploy to the branch)

Deploy the functions to the branch, then curl them with the service key.

**rebuild-athlete-state (the keep-warm worker):**

```
curl -s -X POST "$URL/functions/v1/rebuild-athlete-state" \
  -H "Authorization: Bearer $SERVICE_KEY" -H "Content-Type: application/json" \
  -d '{"user_id":"<a real test user_id>"}'
# expect {"rebuilt":1,...}
```

Then confirm the satellites actually populated:

```sql
select
  load_distribution->'volume_x_intensity_7d' as vxi_7d,
  jsonb_array_length(execution)   as execution_n,
  jsonb_array_length(environment) as environment_n,
  jsonb_array_length(patterns)    as patterns_n,
  jsonb_array_length(niggle_recurrence) as niggles_n
from athlete_state where user_id = '<test user_id>';
```

`load_distribution` should be non-null with sane zone %s; the array
counts depend on whether that athlete has laps/niggles, so 0 is valid for
a sparse athlete (verify against one who has lap data).

**Batch mode (proves the nightly fan-out target logic):**

```
curl ... -d '{"batch":25}'   # expect {"active":N,"targeted":M,"rebuilt":M,...}
```

Row count check — the whole point of Phase E:

```sql
select count(*) from athlete_state;  -- should jump from 2 toward the active-athlete count
```

**coaching-daily-read (the Read, now on v3):**

```
curl ... "$URL/functions/v1/coaching-daily-read" -d '{"user_id":"<test>","triggered_by":"manual"}'
```

Then read the row and eyeball the prose against the v3 contract:

```sql
select headline, paragraph, confidence from daily_coaching_reads
where user_id='<test>' order by generated_at desc limit 1;
```

Check by eye: zone vocab (no "tempo"/"threshold" labels), no "coach"
self-reference, predictions as ranges, niggle surfaced-not-diagnosed,
heat context used if the athlete had a hot run.

---

## Layer 3 — Data-correctness SQL (the stuff that was actually wrong)

**Intensity-weight change** — after re-running `compute-workout-features`
over existing rows (backfill), `intensity_score` should drop (mile 10→5,
5K 6→4):

```sql
select min(intensity_score), max(intensity_score), avg(intensity_score)
from workout_features;   -- max should now be ≤ ~5, not ~10
```

**Citation-key fix** — confirm the Read no longer echoes raw `workout_type`
+ avg pace as the workout label (the original "tempo @ 7:30/mi" bug). Read a
generated paragraph and check the labels match the parsed zones, not the raw
column.

**body_mentions populated** — after a rebuild for an athlete with niggle
notes: `select * from body_mentions where user_id='<test>';`

---

## Layer 4 — End-to-end (the real test, on a test athlete)

The honest "does it work" test, ideally with a Maya-shaped fixture:

1. Log a workout via the app with a voice memo that mentions **a niggle**
   ("left knee's tight again") and a **hot run** ("so humid today").
2. Force a rebuild (`rebuild-athlete-state` with that `user_id`).
3. Generate the Read (`coaching-daily-read`).
4. Verify the Read: correct zone label on the workout, the niggle surfaced
   *without* a diagnosis or "monitor," the slow pace attributed to heat, and
   any recurrence noted as a pattern.

**iOS Read tab manual pass** (the user-facing surface):
- Tab reads **"The Read"**; masthead **"THE READ · TRAINING INSIGHT"**;
  byline **"YOUR TRAINING INSIGHT"** with the coral diamond (no "C", no
  "coach").
- Source cards show real zone labels + paces (no "Tempo"/"Interval", no
  km splits).
- Tap a workout → detail sheet shows distance/pace/splits/mood/verbatim
  memo (no blank body).
- Tap **"VOLUME × INTENSITY · VIEW CHART ↗"** → lands on the Training tab.
- The Ask bar → "Ask AI about my training…" (note: returns answers only
  once the `coaching-agent` editorial shape ships — expected to error
  until then).

---

## Layer 5 — Cron / keep-warm verification

After the cron migration lands on the branch, don't wait for 4am — fire it
once manually and watch the row count:

```sql
-- find the job id, then run it now
select jobid from cron.job where jobname='nightly-athlete-state-rebuild';
select cron.run(<jobid>);
-- a minute later:
select count(*) from athlete_state;            -- climbing
select last_updated_at from athlete_state order by last_updated_at desc limit 5;
```

---

## What this plan can't cover (yet)

- **Production-faithful schema shape** — the eval recorder calls the model
  without the `responseSchema`, so the cassettes prove *content* not shape;
  the live function's `responseSchema` enforces shape. The end-to-end Read
  (Layer 4) is what actually exercises the schema path.
- **Token budget** — `stateToPromptContext` now renders a lot for a rich
  athlete; watch the `coaching-daily-read` logs for truncation markers
  (`prompt_response_truncated`) on a data-rich test athlete (Rec #7).
