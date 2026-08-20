# BUILD — The Read, the weekly training report

**Authored:** 2026-08-20
**For:** an agent working in `my-running-app`, executing top to bottom
**Companions:** `WEEKLY-READ-APPLY.md` (content design + prompt), `ANALYZER-PROMOTION-APPLY.md` (analyzer specs), `ACCURACY-RISK.md` (why Phase A exists), `the-weekly-read-prototype.html` (the surface)

---

## 0 · Read this before writing any code

### 0.1 · What this actually is

The brief was "make The Read a weekly training report." The investigation that
followed found the report itself is the **smallest** part of the work. Three
things sit under it that are wrong today, and each one silently corrupts the
numbers a weekly report would print:

1. **A cron job deletes genuine second runs of the day.** This athlete doubles
   most days. It is destroying data right now, on a 30-minute schedule.
2. **No server-side session concept.** A morning session of 2mi warm-up + 6mi
   tempo + 2mi cooldown is three uploads. Server-side code counts it as three
   runs, or rolls it to the day and reports one 10-mile tempo that never
   happened. iOS solved this in `SessionRollup.swift`. The server never learned.
3. **The zone buckets the analytics read are two lossy steps from the pace
   chart**, and marathon pace is filed as "moderate."

**Building the report on top of these produces a confident, well-designed,
weekly-delivered wrapper around wrong numbers.** That is worse than not building
it, because provenance sheets and Monday-morning ritual make wrong numbers more
convincing, not less.

So this document builds bottom-up. **Phases A and B contain no new features.**

### 0.2 · The two rules that bind every phase

From `WEEK-TAB-APPLY.md §0`, written after a fixture shipped that looked finished
and was a string someone typed:

1. **If a value cannot be derived from the athlete's own rows, do not produce it.**
   No constants standing in for data. No "typical" values. No placeholder series.
   A section that cannot speak says why, in a sentence.
2. **Never attach provenance to a number you invented.** A false number with
   sources attached is worse than a false number.

### 0.3 · Hard gates

**Do not proceed past a gate that has not passed.** If a gate cannot pass, stop
and report why rather than working around it.

| Gate | Between | Condition |
|---|---|---|
| **G1** | A → B | The dedupe rewrite is deployed and `dedupe_audit` shows zero deletions of rows more than 5 minutes apart |
| **G2** | B → C | Golden fixtures pass for `sessionRollup` **and** for the three existing analyzers under test |
| **G3** | C → D | Every new analyzer has a passing fixture asserting a **known correct number**, not just an empty state |
| **G4** | D → E | A generated report renders end to end with `guard_tripped = false` and a coverage line on every section |

### 0.4 · House rules this repo already enforces

- **Migrations are append-only** (hard rule #5). Never edit a shipped migration;
  add a new one. `CREATE OR REPLACE FUNCTION` is fine.
- **Never an em-dash placeholder** (hard rule #8). Every analyzer returns a real
  `EmptyState` with a plain-prose nudge.
- **No analyzer may diagnose, recommend rest, or assess severity** (hard rule #2).
  `FactTone` has no "bad" value; `watch` is the ceiling.
- **AI advises, never acts.** Nothing in `_shared/analyzers/` writes.
- **No "we."** The app does not talk about itself (`design-system/README.md`).
- Files under `RunningLog/RunningLog/` are picked up automatically
  (`PBXFileSystemSynchronizedRootGroup`). **No `.pbxproj` edit is ever needed.**
- **This container has no Xcode.** Swift is written here and compiled by Rio.
  Never report Swift as verified.

---

## PHASE A · Stop corrupting the data

*No new features. Three fixes. Everything downstream depends on all three.*

### A1 · Rewrite the destructive dedupe cron

**File:** new migration `supabase/migrations/20260820100000_dedupe_by_time_window.sql`
**Replaces the behaviour of:** `public.dedupe_recent_training_logs(integer)` from
`20260613240000_dedupe_training_logs_recurring.sql`
**Runs:** every 30 minutes via `pg_cron`

#### What is wrong with the current function

It partitions on `(user_id, UTC date, round(miles*2)/2)`.

| Bug | Consequence |
|---|---|
| `round(miles*2)/2` is a **bucket, not a window** | 5.24 and 5.26 mi → buckets 5.0 and 5.5, real duplicate never merged. 5.25 and 5.74 mi → both bucket 5.5, **a genuine second run is deleted** |
| Groups by **UTC date** | For a UTC-5 athlete, Tuesday evening and Wednesday morning share a UTC date. `SessionRollup.swift:125-135` records this misplacing "8 rows / 39.2 mi of this athlete's history onto the wrong date" |
| **No time proximity test at all** | A 6am 5.2mi and a 5pm 5.2mi are treated as the same run |
| Deletes whenever `laps = 0` | HealthKit rows structurally cannot have laps, so **every lapless double is deletable** |

`LogDedup.swift:83-88` on the client deliberately preserves the exact case the
server deletes. The client and server are in direct opposition and the server
wins, because it deletes.

#### The fix, in one sentence

**Cluster by time proximity and a distance window, never by calendar bucket; log
every deletion before making it; and let the cron handle only high-confidence
device twins.**

Voice-memo-versus-GPS pairing is explicitly **out of scope for this function**.
Those can be hours apart (`Jul 18 2026`: Strava 01:38, voice memo 06:38) and a
time window will never catch them. That pairing already happens at read time in
`LogDedup.dedupedByPhysicalWorkout()`, where it **folds for display instead of
deleting**. That is the correct treatment for anything ambiguous.

#### The migration

```sql
-- ============================================================================
-- Dedupe by time window, not calendar bucket.
--
-- Supersedes the behaviour of dedupe_recent_training_logs() from
-- 20260613240000. That function partitioned on (user_id, UTC date,
-- round(miles*2)/2) and deleted losers. Three failures, all live:
--
--   1. A DISTANCE BUCKET IS NOT A WINDOW. 5.25mi and 5.74mi land in the same
--      0.5 bucket and one is deleted, though they are 0.49mi apart and are two
--      different runs. 5.24 and 5.26 land in different buckets and are never
--      merged, though they are the same run from two devices.
--   2. UTC DATE. For a UTC-5 athlete a Tuesday evening run and a Wednesday
--      morning run share a UTC date.
--   3. NO TIME TEST. A 6am and a 5pm run of similar distance are "duplicates".
--
-- For an athlete who doubles on most days this deletes real training. It is
-- the reason the weekly aggregates cannot currently be trusted.
--
-- WHAT THIS DOES INSTEAD
--   * Clusters rows that start within DEDUPE_WINDOW_SECONDS of each other AND
--     whose distances differ by no more than max(0.30mi, 5%).
--   * Records every candidate deletion in `dedupe_audit` BEFORE deleting, so
--     the sweep is reviewable and reversible.
--   * Keeps the conservative delete guard: lapless losers, or lapped losers
--     that share an external key with the keeper.
--
-- WHAT THIS DELIBERATELY DOES NOT DO
--   Voice-memo/GPS pairing. Those can be five hours apart. That pairing belongs
--   at read time in LogDedup.dedupedByPhysicalWorkout(), which FOLDS rather
--   than deletes. Ambiguous cases must never be resolved destructively.
--
-- Hard rule #5: append-only. The old function is replaced in place via
-- CREATE OR REPLACE; nothing is dropped.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.dedupe_audit (
    id            BIGSERIAL PRIMARY KEY,
    swept_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_id       TEXT        NOT NULL,
    deleted_id    UUID        NOT NULL,
    keeper_id     UUID        NOT NULL,
    deleted_date  TIMESTAMPTZ,
    keeper_date   TIMESTAMPTZ,
    gap_seconds   DOUBLE PRECISION,
    deleted_miles DOUBLE PRECISION,
    keeper_miles  DOUBLE PRECISION,
    reason        TEXT
);

CREATE INDEX IF NOT EXISTS dedupe_audit_user_swept_idx
    ON public.dedupe_audit (user_id, swept_at DESC);

ALTER TABLE public.dedupe_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dedupe_audit_owner_read ON public.dedupe_audit;
CREATE POLICY dedupe_audit_owner_read
    ON public.dedupe_audit FOR SELECT
    USING (user_id = auth.uid()::text);

COMMENT ON TABLE public.dedupe_audit IS
  'Every row the dedupe sweep deleted, written before the delete. Exists '
  'because the previous sweep destroyed genuine doubles for months with no '
  'record. Query this before trusting any weekly aggregate.';


CREATE OR REPLACE FUNCTION public.dedupe_recent_training_logs(p_days integer DEFAULT 3)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted integer := 0;
  -- Two device copies of one run start within SECONDS. 5 minutes is already
  -- generous, and it matches the repo's two existing client rules
  -- (WorkoutSyncService.swift:77-86 and VoiceLogView.swift:1409 both use
  -- ±300s). A wider window starts eating track reps: three 2mi pieces logged
  -- 18 minutes apart are a warm-up, a rep and a cooldown, not three copies of
  -- one run. Verified — at 1200s a t / t+18min / t+36min fixture collapsed
  -- three real pieces into one. Do NOT widen this to catch voice memos; see
  -- the header.
  c_window_seconds constant double precision := 300;
BEGIN
  CREATE TEMP TABLE _dup_rank ON COMMIT DROP AS
  WITH base AS (
    SELECT
      tl.id, tl.user_id, tl.vital_workout_id, tl.workout_date,
      tl.workout_distance_miles AS mi,
      tl.created_at,
      (tl.pace_segments IS NOT NULL) AS has_seg,
      (tl.cleaned_notes IS NOT NULL) AS has_notes,
      (SELECT count(*) FROM public.running_workout_laps l
        WHERE l.workout_id = tl.id) AS laps
    FROM public.training_logs tl
    WHERE tl.workout_distance_miles IS NOT NULL
      AND tl.workout_date >= (now() - make_interval(days => p_days))
  ),
  -- Gaps-and-islands. A row starts a NEW cluster when it is too far in time
  -- from its predecessor, or too far in distance. Everything else continues
  -- the current cluster.
  flagged AS (
    SELECT b.*,
      CASE
        WHEN lag(b.workout_date) OVER w IS NULL THEN 1
        WHEN extract(epoch FROM (b.workout_date - lag(b.workout_date) OVER w))
             > c_window_seconds THEN 1
        WHEN abs(b.mi - lag(b.mi) OVER w) > greatest(0.30, 0.05 * b.mi) THEN 1
        ELSE 0
      END AS is_new_cluster
    FROM base b
    WINDOW w AS (PARTITION BY b.user_id ORDER BY b.workout_date, b.id)
  ),
  clustered AS (
    SELECT f.*,
      sum(f.is_new_cluster) OVER (
        PARTITION BY f.user_id ORDER BY f.workout_date, f.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS cluster_seq
    FROM flagged f
  )
  SELECT c.*,
    count(*)          OVER w AS grp_size,
    row_number()      OVER w AS rn,
    first_value(c.id) OVER w AS keeper_id,
    first_value(c.vital_workout_id) OVER w AS keeper_vid,
    first_value(c.workout_date)     OVER w AS keeper_date,
    first_value(c.mi)               OVER w AS keeper_mi
  FROM clustered c
  WINDOW w AS (
    PARTITION BY c.user_id, c.cluster_seq
    ORDER BY c.laps DESC, c.has_seg DESC, c.has_notes DESC, c.created_at ASC
  );

  -- 1. Merge qualitative fields from losers onto the keeper. Unchanged in
  --    spirit from the original: words are never lost, even when a row is.
  WITH donors AS (
    SELECT r.user_id, r.cluster_seq,
      (array_remove(array_agg(tl.cleaned_notes)
        FILTER (WHERE tl.cleaned_notes IS NOT NULL), NULL))[1] AS cleaned_notes,
      (array_remove(array_agg(tl.mood)
        FILTER (WHERE tl.mood IS NOT NULL), NULL))[1]          AS mood,
      (array_remove(array_agg(tl.notes)
        FILTER (WHERE tl.notes IS NOT NULL), NULL))[1]         AS notes,
      (array_remove(array_agg(tl.workout_notes)
        FILTER (WHERE tl.workout_notes IS NOT NULL), NULL))[1] AS workout_notes
    FROM _dup_rank r
    JOIN public.training_logs tl ON tl.id = r.id
    WHERE r.grp_size > 1 AND r.rn > 1
    GROUP BY r.user_id, r.cluster_seq
  )
  UPDATE public.training_logs k
  SET cleaned_notes = COALESCE(k.cleaned_notes, d.cleaned_notes),
      mood          = COALESCE(k.mood,          d.mood),
      notes         = COALESCE(k.notes,         d.notes),
      workout_notes = COALESCE(k.workout_notes, d.workout_notes)
  FROM _dup_rank r
  JOIN donors d ON d.user_id = r.user_id AND d.cluster_seq = r.cluster_seq
  WHERE r.rn = 1 AND r.grp_size > 1 AND k.id = r.id;

  -- 2. Record what is about to be deleted. BEFORE the delete, always.
  --
  --    NOTE THE KEEPER-PROXIMITY GUARD in both statements below. Cluster
  --    membership alone is not sufficient: gaps-and-islands chains, so A~B and
  --    B~C put A, B and C in one cluster even when A and C are two windows
  --    apart. Requiring each loser to sit within the window OF THE KEEPER
  --    bounds that. Belt and braces with the 300s window above.
  INSERT INTO public.dedupe_audit (
    user_id, deleted_id, keeper_id, deleted_date, keeper_date,
    gap_seconds, deleted_miles, keeper_miles, reason
  )
  SELECT r.user_id, r.id, r.keeper_id, r.workout_date, r.keeper_date,
         extract(epoch FROM (r.workout_date - r.keeper_date)),
         r.mi, r.keeper_mi,
         CASE WHEN r.laps = 0 THEN 'lapless-loser-in-time-window'
              ELSE 'same-external-key' END
  FROM _dup_rank r
  WHERE r.grp_size > 1 AND r.rn > 1
    AND abs(extract(epoch FROM (r.workout_date - r.keeper_date))) <= c_window_seconds
    AND (r.laps = 0
         OR (r.vital_workout_id IS NOT NULL
             AND r.vital_workout_id = r.keeper_vid));

  -- 3. Delete.
  WITH del AS (
    DELETE FROM public.training_logs tl
    USING _dup_rank r
    WHERE tl.id = r.id
      AND r.grp_size > 1
      AND r.rn > 1
      AND abs(extract(epoch FROM (r.workout_date - r.keeper_date))) <= c_window_seconds
      AND (r.laps = 0
           OR (r.vital_workout_id IS NOT NULL
               AND r.vital_workout_id = r.keeper_vid))
    RETURNING 1
  )
  SELECT count(*) INTO v_deleted FROM del;

  RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION public.dedupe_recent_training_logs(integer) IS
  'Clusters by start-time proximity (5 min) and a distance WINDOW '
  '(max 0.30mi / 5%), never by UTC date or a 0.5mi bucket. Audits every '
  'deletion to dedupe_audit first. Does not attempt voice/GPS pairing — that '
  'is folded, not deleted, in LogDedup.dedupedByPhysicalWorkout().';
```

#### Known limitation — found by running it, then bounded

Gaps-and-islands **chains**: A~B and B~C put A, B and C in one cluster even when
A and C are two windows apart.

This is not hypothetical. The first draft of this function used a 1200s window,
and a fixture of three ~5mi pieces at `t`, `t+18min`, `t+36min` — a warm-up, a
rep and a cooldown — **collapsed into one row, deleting two real pieces.** Two
changes bound it:

1. **The window is 300s**, matching `WorkoutSyncService.swift:77-86` and
   `VoiceLogView.swift:1409`. Device twins start within seconds.
2. **Deletion additionally requires the loser to be within the window of the
   keeper**, not merely in the same cluster.

Both are in the SQL above. A1-T3 asserts the fixture that caught it. If a
`dedupe_audit` row ever shows `gap_seconds` above the window, the guard has
failed — investigate before trusting any aggregate.

**This function was executed against PostgreSQL 16 with the fixtures in the table
below and the results recorded there. It is not untested pseudocode.**

#### A1 tests — `supabase/migrations/tests/dedupe.test.sql` (or the repo's SQL test harness)

| # | Fixture | Assert |
|---|---|---|
| A1-T1 | 6:05am 5.2mi + 5:40pm 5.2mi, both lapless | **Both survive.** This is the regression that matters most |
| A1-T2 | Two rows 40s apart, 5.24 and 5.26mi, one with laps | One deleted, the lapped one kept, `dedupe_audit` has one row with `gap_seconds ≈ 40` |
| A1-T2b | 5.25mi at noon + 5.74mi at 8pm (the pair the OLD code deleted) | **Both survive** |
| A1-T3 | Three rows at t, t+18min, t+36min, all ~5mi — a warm-up, a rep, a cooldown | **All three survive.** At the original 1200s window this collapsed to one, deleting two real pieces. This test is the reason the window is 300s |
| A1-T4 | UTC-5 athlete, 8:30pm Tue + 6:00am Wed, similar distance | Both survive |
| A1-T5 | Strava 01:38 + voice memo 06:38, same distance | **Both survive.** The cron must not touch this pair |

#### A1 — actually executed, results recorded

Run against **PostgreSQL 16.13**, fixtures loaded, `dedupe_recent_training_logs(30)`
called once. Not a dry read of the SQL:

| Fixture | Rows in | Rows surviving | Correct? |
|---|---|---|---|
| A1-T1 genuine double, 6:05am + 5:40pm, both 5.2mi, lapless | 2 | **2** | ✅ the regression that matters |
| A1-T2 device twins 40s apart, 5.24 / 5.26mi, one lapped | 2 | **1** (lapped kept) | ✅ audited, `gap_seconds = 40` |
| A1-T2b 5.25mi noon + 5.74mi 8pm — the pair the OLD code deleted | 2 | **2** | ✅ old bug fixed |
| A1-T3 three ~5mi pieces at t / t+18min / t+36min | 3 | **3** | ✅ *was 1 before the window fix* |
| A1-T4 UTC-5 athlete, 8:30pm Tue + 6:00am Wed | 2 | **2** | ✅ |
| A1-T5 Strava 01:38 + voice memo 06:38, same distance | 2 | **2** | ✅ cron leaves this pair alone |

Total deletions: **1**, and it is the only true duplicate in the set. One
`dedupe_audit` row, `gap_seconds = 40`, well inside the 300s window.

Port these into the repo's SQL test harness before deploying — they were run in a
scratch database with stub tables, which proves the logic and the syntax but not
the interaction with real constraints, triggers or RLS.

#### A1 deploy and verify

```bash
supabase db push                       # from a committed SHA (hard rule #9)
```

```sql
-- Let two sweeps run (60 min), then:
SELECT count(*) FILTER (WHERE abs(gap_seconds) > 300) AS suspicious,
       count(*) AS total
FROM   dedupe_audit
WHERE  swept_at > now() - interval '2 hours';
```

**GATE G1: `suspicious` must be 0.** If it is not, stop.

> **Data already destroyed is not recovered by this.** The sweep has been running
> since 2026-06-13. Rows deleted before today have no audit trail. Tell Rio
> plainly: historical weekly mileage may be under-reported and there is no way to
> reconstruct it from this database. If Strava still holds the originals, a
> re-import after this fix would repair history — that is the file-import gap the
> ingestion audit scores 0/10, and it is a separate build.

---

### A2 · A server-side session rollup

**New file:** `supabase/functions/_shared/sessionRollup.ts`
**Mirrors:** `RunningLog/RunningLog/App/SessionRollup.swift`

#### Why

`SessionRollup.swift` opens with exactly the case raised in review:

> *"A session is not a day and it is not an upload. Aug 4 2026 is five Strava
> activities, which are two sessions: a 6:08am track workout (warm-up +
> threshold + cooldown) and a 5:52pm double. Rolling to the day reports one
> 15.7 mi threshold day that never happened; rolling to the upload reports five
> runs that never happened either."*

That logic is **iOS-only and used only by The Sheet.** A repo-wide search for a
clock-gap rollup under `supabase/functions/` returns nothing. So every
server-side analyzer, and therefore the entire weekly report, currently counts a
warm-up, a tempo and a cooldown as three separate runs.

Concretely, for `2mi wu + 6mi tempo + 2mi cd` in the morning and `5mi easy` in
the evening:

| Layer | Sees | Correct? |
|---|---|---|
| Uploads | 4 runs, 15mi | No — "4 runs" is wrong |
| Day rollup | 1 run, 15mi | No — invents a 15mi tempo |
| **Session rollup** | **2 sessions: 10mi quality + 5mi easy** | **Yes** |

Run-count, easy-share, long-run identification and "was the second run of the
day easy" are all wrong without this.

#### The constants, and they must match Swift

```
SESSION_GAP_MINUTES = 90
```

`SessionRollup.swift:85-88` explains the 90: *"90 rather than 60 because
Jul 21 2026's warm-up-to-cooldown gap is 65 minutes."* Do not change it here
without changing it there. A2-T5 below asserts they agree.

#### Implementation

```ts
/**
 * sessionRollup — uploads → SESSIONS, server side.
 *
 * The port of `RunningLog/RunningLog/App/SessionRollup.swift`. Read that file
 * before changing this one; the constants are shared and a parity test asserts
 * they agree.
 *
 * A session is not a day and it is not an upload. A morning of
 * "2mi warm-up / 6mi tempo / 2mi cooldown" is three uploads and ONE session.
 * An evening 5mi easy is a second session. Rolling to the upload reports four
 * runs that never happened; rolling to the day reports one 15-mile tempo that
 * never happened either.
 *
 * Every server-side weekly aggregate — run count, easy share, long-run
 * detection, "was the day's second run easy" — is wrong without this layer.
 *
 * ORDER MATTERS. Local day first, THEN clock gap. Grouping by gap alone pairs
 * a Tuesday 11pm run with a Wednesday 12:15am run.
 *
 * Timezone comes from `athlete_settings.timezone` (TEXT, defaults 'UTC').
 * Never use the UTC date: for a UTC-5 athlete an evening run belongs to the
 * previous local day, and getting this wrong is what
 * `SessionRollup.swift:125-135` records as misplacing 8 rows / 39.2 mi.
 */

/** Keep in lockstep with `SessionRollup.sessionGapMinutes`. */
export const SESSION_GAP_MINUTES = 90;

export interface RollupRow {
  id: string;
  /** ISO timestamptz — the START of the piece. */
  workout_date: string;
  miles: number | null;
  minutes: number | null;
  workout_type: string | null;
}

export interface TrainingSession {
  /** Local calendar day, YYYY-MM-DD. */
  day: string;
  /** ISO start of the session's first piece. */
  start: string;
  pieces: RollupRow[];
  miles: number;
  minutes: number;
  /** Normalized type of the hardest piece — what the session is NAMED for. */
  typeKey: string | null;
  /** True when this is a day's second or later session. */
  isSecond: boolean;
  /** Derived. `workout_pace_per_mile` is populated on 12% of rows and must
   *  never be a display source — see SessionRollup.swift. */
  paceSeconds: number | null;
}

/** YYYY-MM-DD in the athlete's own timezone. en-CA yields ISO order. */
export function localDay(iso: string, tz: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date(iso));
}

/** Hardness order, hardest first. Used to name a session after its hardest
 *  piece — a warm-up + tempo + cooldown session is a TEMPO session. */
const TYPE_HARDNESS = [
  "race", "intervals", "tempo", "threshold", "fartlek",
  "progression", "long", "steady", "easy", "recovery",
];

function hardestType(pieces: RollupRow[]): string | null {
  let best: string | null = null;
  let bestRank = Number.MAX_SAFE_INTEGER;
  for (const p of pieces) {
    const t = p.workout_type?.toLowerCase().trim();
    if (!t) continue;
    const rank = TYPE_HARDNESS.indexOf(t);
    const effective = rank === -1 ? TYPE_HARDNESS.length : rank;
    if (effective < bestRank) { bestRank = effective; best = t; }
  }
  return best;
}

/**
 * Group uploads into sessions.
 *
 * `rows` need not be sorted. Rows with no usable date are dropped and MUST be
 * reported by the caller in `Coverage.missing` — never silently discarded.
 */
export function rollupSessions(rows: RollupRow[], tz: string): TrainingSession[] {
  const usable = rows.filter((r) => r.workout_date && !isNaN(Date.parse(r.workout_date)));

  // Step 1 — group by LOCAL calendar day.
  const byDay = new Map<string, RollupRow[]>();
  for (const r of usable) {
    const day = localDay(r.workout_date, tz);
    const list = byDay.get(day);
    if (list) list.push(r); else byDay.set(day, [r]);
  }

  const out: TrainingSession[] = [];

  for (const [day, dayRows] of [...byDay.entries()].sort((a, b) => a[0] < b[0] ? -1 : 1)) {
    dayRows.sort((a, b) => Date.parse(a.workout_date) - Date.parse(b.workout_date));

    // Step 2 — split into sessions by clock gap, measured from the END of the
    // previous piece to the START of the next. A 2mi warm-up that ENDS at 6:20
    // and a tempo that STARTS at 6:35 is a 15-minute gap, not 30.
    const groups: RollupRow[][] = [];
    let current: RollupRow[] = [];
    let prevEndMs = 0;

    for (const r of dayRows) {
      const startMs = Date.parse(r.workout_date);
      if (current.length === 0) {
        current = [r];
      } else {
        const gapMin = (startMs - prevEndMs) / 60000;
        if (gapMin <= SESSION_GAP_MINUTES) current.push(r);
        else { groups.push(current); current = [r]; }
      }
      prevEndMs = startMs + (r.minutes ?? 0) * 60000;
    }
    if (current.length > 0) groups.push(current);

    groups.forEach((pieces, idx) => {
      const miles   = pieces.reduce((s, p) => s + (p.miles ?? 0), 0);
      const minutes = pieces.reduce((s, p) => s + (p.minutes ?? 0), 0);
      out.push({
        day,
        start: pieces[0].workout_date,
        pieces,
        miles,
        minutes,
        typeKey: hardestType(pieces),
        isSecond: idx > 0,
        paceSeconds: miles > 0.05 && minutes > 0 ? (minutes * 60) / miles : null,
      });
    });
  }

  return out;
}
```

#### A2 tests — `supabase/functions/_shared/sessionRollup.test.ts`

| # | Fixture | Assert |
|---|---|---|
| A2-T1 | 6:00 2mi wu (16min) · 6:20 6mi tempo (36min) · 7:00 2mi cd (17min) · 17:00 5mi easy | **2 sessions**, 10.0mi and 5.0mi. First `typeKey === "tempo"`, second `isSecond === true` |
| A2-T2 | The `Aug 4 2026` five-activity case from the Swift header | 2 sessions, not 1 and not 5 |
| A2-T3 | UTC-5 athlete, run at `2026-08-04T01:30:00Z` | `day === "2026-08-03"`, not `"2026-08-04"` |
| A2-T4 | Two runs 95 minutes apart | 2 sessions — just past the 90-minute boundary |
| A2-T5 | **Parity** — grep `sessionGapMinutes` out of `SessionRollup.swift` | Equals `SESSION_GAP_MINUTES`. Fails loudly if either drifts |
| A2-T6 | A row with `minutes: null` | Included; treated as zero duration; does not throw |

A2-T5 is the one that stops this file and the Swift file silently diverging in
six months. Write it even though it feels odd.

---

### A3 · Fix the stale zone comment

**File:** new migration `supabase/migrations/20260820100100_fix_zone_column_comments.sql`

`20260318120000_create_workout_features.sql:20-23` documents the columns as
`easy < 75% MP velocity`, `moderate 75-85%`, `threshold 85-95%`, `hard > 95%`.
That matches **neither** `pace-engine.ts` (which uses 70/80/90/100% of MP speed
for its range zones) **nor** the rollup actually running in
`workoutSegmentation.ts:539-543`. It documents an implementation that no longer
exists, in the first place anyone looks.

```sql
COMMENT ON COLUMN public.workout_features.easy_seconds IS
  'Seconds in zones easy + recovery, per workoutSegmentation.ts:539-543. '
  'NOT a % of MP velocity — zone membership comes from paceToZone(), which '
  'uses midpoint cutoffs between the athlete''s own anchors. Easy and '
  'recovery are MERGED here and cannot be separated from this column.';

COMMENT ON COLUMN public.workout_features.moderate_seconds IS
  'Seconds in zones mp + steady + moderate. NOTE: MARATHON PACE IS IN HERE. '
  'A marathon-pace block is indistinguishable from a steady run in this '
  'column. Any analytic that needs MP volume must go to the laps and '
  'classify with paceToZone(), not read this.';

COMMENT ON COLUMN public.workout_features.threshold_seconds IS
  'Seconds in zone hmp only. The backend classifier folds LT into HMP.';

COMMENT ON COLUMN public.workout_features.hard_seconds IS
  'Seconds in zones 10k + 5k + 3k + mile.';
```

**Do this even if nothing else in this document ships.**

---

## PHASE B · A verification harness

*Gate G1 must have passed.*

### B1 · Why this phase exists

`analyzers.test.ts` has 26 tests. Twenty test the plumbing — the narration guard,
param coercion, formatters, registry hygiene. **Three** test analyzer behaviour,
and all three are empty-state tests: `zone_trend` with no anchor, `zone_trend`
with nothing logged, `load_balance` with too little history.

**Not one test asserts that an analyzer computes a correct number from known
input.** Every analyzer test checks that it *declines* correctly, never that it
*computes* correctly. The narration guard is excellent and it is guarding the
wrong layer: it stops the model inventing a number, and has no opinion on
whether Layer 1's number is right. A wrong number in `facts` passes the guard
perfectly and gets narrated with total confidence.

This has already happened twice in production, both recorded in the code's own
comments, neither caught by a test:

- `currentFitness` read `ranges["10k"]` against a stored `"10K"` and "silently
  rendered no capacity at all — a lowercase miss that compiled fine."
- 2026-08-08: `heat_effect` narrated *"your long runs over 12 miles"* having read
  all 127 runs in 90 days, because 12 appeared in the facts as "12 s/mi."

### B2 · The golden-fixture pattern

**New file:** `supabase/functions/_shared/analyzers/fixtures/goldens.ts`

Three fixtures per analyzer. Every one asserts a number that is **known by
construction**, not one produced by running the code and pasting the output.

> Writing the expected value by running the analyzer and copying the result is
> not a test. It is a snapshot of current behaviour, including its bugs.
> Compute the expected number by hand, in the test's comment, from the fixture.

```ts
/**
 * Golden fixtures — the test class this repo does not have.
 *
 * Each fixture is a hand-built week whose correct answer is known BY
 * CONSTRUCTION. The expected value is derived in the comment above the
 * assertion, from the fixture's own numbers. Never paste analyzer output.
 */

/** Fixture 1 — a clean week. Catches the arithmetic. */
export const CLEAN_WEEK = { /* 6 sessions, zone seconds hand-set */ };

/** Fixture 2 — a week containing a genuine double AND a wu/tempo/cd session.
 *  Catches the dedup and session classes AT THE ANALYZER, so a regression
 *  upstream fails a test instead of a card. Write this one first. */
export const DOUBLES_WEEK = { /* … */ };

/** Fixture 3 — a partial week: some sessions missing zone data.
 *  Asserts they are EXCLUDED and NAMED in coverage.missing, never silently
 *  averaged over. */
export const PARTIAL_WEEK = { /* … */ };
```

Shape of a golden test:

```ts
Deno.test("golden: easy_discipline on a clean week", async () => {
  // By construction: 4,200 easy seconds of 6,000 total = 70%.
  const r = await easyDiscipline.run({}, ctxFor(CLEAN_WEEK));
  assertEquals(r.facts.find((f) => f.key === "easy_share_current")?.value, "70");
  assertEquals(r.coverage.sessionsUsed, 6);
  assert(factLinesToStrings(r).some((l) => l.includes("70")));
});
```

### B3 · Retrofit before extending

Write all three fixtures for the analyzers the weekly Read will actually call —
at minimum `load_balance`, `zone_trend`, `mood_trend`, `niggle_timeline`,
`race_projection`. **Do not add new analyzers until these pass.** If a
retrofitted fixture fails, that is a bug found, not a blocked phase — fix it and
record it.

### B4 · Reconciliation assertions

Two cheap invariants, added inside the analyzers, that catch corrupt input at
the point of use:

**Zone seconds must roughly equal duration.** `workout_features` stores both. If
`easy+moderate+threshold+hard` differs from `total_duration_seconds` by more than
5%, that run's classification is incomplete — **exclude it and name it in
`coverage.missing`.** Silent inclusion is how a wrong easy-share gets produced
from visibly broken data.

**Weekly totals must match the day rows.** `trends-timeline` already returns
per-day miles with doubles summed. If an analyzer's own sum disagrees with the
timeline's total for the same week, that is the dedup bug surfacing in the only
place it can be caught automatically. **Surface the disagreement; do not pick a
winner.** A card that says "two sources disagree about this week, so this is not
shown" is worth far more than one that quietly picks the smaller number.

**GATE G2: B3 fixtures pass and A2 tests pass.**

---

## PHASE C · The analyzers

*Gate G2 must have passed. Full specs in `ANALYZER-PROMOTION-APPLY.md`.*

Build in this order. Each ships with three golden fixtures before the next
starts.

| # | Analyzer | Kind | Note |
|---|---|---|---|
| C1 | `long_run_share` | JOIN | Miles, not zones — untouched by the pace-chart problem. Both operands persisted. Ship first |
| C2 | `easy_discipline` | **BUILD** | Goes to the laps. See below |
| C3 | `effort_mismatch` | promote | Existing `athlete_state` pattern |
| C4 | `down_week_response` | promote | Existing pattern |
| C5 | `niggle_load` | promote | Existing pattern |

### C2 · `easy_discipline`, and why it is a BUILD

It cannot read `workout_features.easy_seconds`. That column merges easy with
recovery, and it is two lossy transformations from the pace chart (A3, and
`ANALYZER-PROMOTION-APPLY.md §2.0`). Instead, like the two analyzers that already
need per-session truth:

> *"The exceptions are `zone_trend` and `compare_session`, which need
> per-session detail that state doesn't carry, so they go to the laps."*
> — `analyzers/athleteState.ts`

`easy_discipline` is the third exception. Requirements:

1. Fetch laps via the existing `fetchLapsByWorkout` / `LAP_COLUMNS` in `data.ts`.
2. Classify against the **chart's own `easy` range** — `paceFast` / `paceSlow`
   from `pace-engine.ts` — not a midpoint cutoff. "Was this inside the easy
   range" is a range question, which is what the range zones are for.
3. **Keep `easy` and `recovery` distinct** and report both.
4. **Use `heat_adjusted_pace_sec_per_mile` where present** (already in
   `LAP_COLUMNS`). Judging easy discipline on raw pace in 26°C penalises the
   athlete for the weather, and the Week tab already decides band membership on
   adjusted pace — this must match or two surfaces will disagree about one run.
5. Roll up through `sessionRollup` (A2), so a warm-up is not counted as an easy
   run in its own right.
6. `FactTone` ceiling is `watch`. Never "bad."

**GATE G3: every new analyzer has a fixture asserting a known correct number.**

---

## PHASE D · The report

*Gate G3 must have passed. Content model, section design, prompt rails and copy
examples are in `WEEKLY-READ-APPLY.md` — this section covers only the build.*

### D1 · The cadence already exists — do not build a second one

`20260806160000_weekly_coaching_read_cadence.sql` already:

- moved the Read from daily 06:00 local to **Sunday 18:00 local**;
- filtered eligibility to athletes with a `training_log` in the trailing 7 days,
  so dormant accounts cost nothing;
- kept `daily_coaching_reads` keyed on `(user_id, read_date)` — **a weekly read
  is simply one row on the Sunday date. No schema rework, no iOS change.**

**Two things follow.**

**First, a decision for Rio.** Sunday 18:00 local is already scheduled; Monday
morning was the answer given in review. Sunday evening arguably suits a training
report better — it lands before the week is planned rather than after it starts.
Pick one and change the cron expression only; do not add a second job.

**Second, a warning the migration itself records.** The previous daily cadence
**never once worked**: 104 dispatches between 2026-06-16 and 2026-08-06 produced
**zero** rows with `triggered_by = 'cron'` — all 47 reads on file are `'manual'` —
because the function returned 429 from `enforceFeatureRateLimit` before ever
reaching the model. It looked built and produced nothing for seven weeks.

`coaching-daily-read/index.ts:169` now passes `{ isServiceRole }`, which should
exempt the cron. **Verify empirically, do not assume:**

```sql
SELECT triggered_by, count(*), max(created_at)
FROM   daily_coaching_reads
WHERE  created_at > now() - interval '14 days'
GROUP  BY 1;
```

**If no `cron` rows appear after the first scheduled fire, stop and fix the
dispatch before building anything on top of it.** Check `daily_read_dispatch_log`
for what the dispatcher thought it did.

Note also that `llmBudgetAllows` at `:223` deliberately does **not** exempt
service-role callers. A budget exhaustion will silently no-op the weekly run in
exactly the same way. Assert on the log, not on the schedule.

### D2 · Architecture — a scheduled Ask, not a bigger prompt

Full rationale in `WEEKLY-READ-APPLY.md §2`. The shape:

```
for each section:
    run its analyzers  →  FactLine[] + Coverage + SeriesSpec
    if coverage insufficient  →  render EmptyState, DO NOT narrate
    else  →  narrate under narration-guard, scoped to that section's facts
compose  →  one daily_coaching_reads row on the Sunday date
```

Do **not** extend `weekly-coaching-report.v1.ts`. It hands ~15 pre-formatted
blocks to one large prompt and asks for 4–6 paragraphs; the model does the
analysis *and* the writing, and it has no structural defence against a number
that is not there.

Per-section narration is not stylistic. It is what lets one section go dark while
six others stand. In one fat prompt, thin data degrades the *whole* report into
hedged prose.

### D3 · Prompt

New `supabase/functions/_shared/prompts/weekly-read.v6.ts`. Inherit from
`daily-read.v5.ts`: the voice rules, the banned-word list, `PLAN_MODE` /
`SELF_COACHED_MODE` / `COACHED_MODE`, and hard rule #2 on niggles — *surface,
never diagnose or direct.* Section-by-section copy design and the worked
rewrites of the brief's two example lines are in `WEEKLY-READ-APPLY.md §0`.

Every narration call goes through `validateNarration()`. Log
`analysis_queries.guard_tripped` on every rejection — that row is the
early-warning system for prompt drift, and it is the only way anyone will notice
the report degrading.

**GATE G4: a generated report renders end to end, `guard_tripped = false`, and
every section carries a coverage line.**

---

## PHASE E · The surface

*Gate G4 must have passed.*

Per the review decision, the weekly Read is the **narrative lede at the top of
the Week tab** — prose on top, the evidence charts already built below it. No
seventh tab.

Files, all under `RunningLog/RunningLog/Week/` so the synchronized root group
picks them up (**no `.pbxproj` edit**):

| File | Change |
|---|---|
| `WeekModels.swift` | Add `WeekRead.report: WeeklyReport?` |
| `WeekService.swift` | Fetch the `daily_coaching_reads` row for the current week |
| `WeekComponents.swift` | The report sections + the §07 capture control |
| `WeekTabView.swift` | Mount above the existing sections |

Reuse `CoachRead`-shaped rendering from `Coaching/Read/` where it fits —
`ReadProse`, `EvidenceChip`, `SourcesPanel`, `ConfidenceBar` are built and
tested on device.

**Also fix `WeekService.swift:461`**, whose fallback string still says
`daily_biometrics` "exists but nothing writes to it yet." Two producers write to
it (`WEEKLY-READ-APPLY.md §3.1`). One-line change.

**Nothing in Phase E can be compiled in the cloud container. Never report Swift
as verified.**

---

## Verify

Run in order. Every item is checkable by someone who does not read code.

| # | Check | Pass |
|---|---|---|
| 1 | `SELECT count(*) FROM dedupe_audit WHERE abs(gap_seconds) > 300` | `0` |
| 2 | A day with a real double still shows both runs in the app | Both present |
| 3 | `deno test supabase/functions/_shared/sessionRollup.test.ts` | All pass, including the Swift parity test |
| 4 | A wu/tempo/cd morning counts as **one** session in a weekly run count | Yes |
| 5 | `deno test supabase/functions/_shared/analyzers/` | All pass, goldens included |
| 6 | Weekly mileage in the report equals the sum of the day rows in Week | Equal, or the disagreement is stated |
| 7 | `SELECT triggered_by, count(*) FROM daily_coaching_reads GROUP BY 1` after the first scheduled fire | `cron` rows exist |
| 8 | `SELECT count(*) FROM analysis_queries WHERE guard_tripped` | `0` for the report's own calls |
| 9 | A week with no quality session | Section 02 goes dark in prose; the rest render |
| 10 | A brand-new account | Empty states everywhere; no invented numbers |
| 11 | Tap any number in the report | Names the sessions it came from |
| 12 | Build in Xcode | Compiles. **Not verifiable here** |

---

## What this deliberately does not build

- **Sleep stages, sleep efficiency, sleep score.** Tier-0 in
  `docs/specs/recovery-trend-v2-2026-07-27.md §7.4` — *"capturing them invites
  someone to use them."* `HealthBiometricsSync` reads stages only to decide
  whether a sample counts as asleep. Keep it that way.
- **Fuelling.** Carbohydrate intake is captured nowhere — no column, no field, no
  classifier. `WeekModels.LongRun.fuel` is a fixture and flagged as one. It is a
  **capture** problem before it is a display problem.
- **The proposal engine.** No `proposed_actions` exists anywhere in the repo. The
  glass-box Apply/Adjust/Keep flow is not built. Section 06 makes at most one
  bounded training call in prose; that is not a proposal engine and must not
  grow into one without the decision in `WEEK-TAB-APPLY.md §7.4`.
- **History import.** GPX/TCX/FIT/CSV import does not exist and is scored 0/10.
  It is the only thing that could repair mileage already deleted. Separate build,
  and arguably a larger one than this.
- **The two security holes** in `INGESTION-AUDIT-2026-08-12.md`
  (`post-run-reconciliation` cross-tenant read+write; the `sk_us_…` Vital server
  key shipped inside the iOS binary). **Unrelated to this feature and more urgent
  than it.** Do them first or in parallel; do not let this document bury them.

---

## Honest scope

| Phase | What | Rough size |
|---|---|---|
| A | Dedup fix · session rollup · comments | 1–2 days |
| B | Golden fixtures · reconciliation assertions | 2–3 days |
| C | Five analyzers | 2–3 days |
| D | Report: prompt · function · cadence verify | 3–4 days |
| E | iOS surface | 2–3 days |

**Phases A and B are two-fifths of the work and ship no visible feature.** That
is the correct allocation given what the investigation found, and skipping them
does not save the time — it moves the cost to a Monday-morning report that is
confidently wrong and much harder to debug once athletes are reading it.

If only one thing gets built: **A1.** It is deleting real training right now.
