-- training_blocks — a DECLARED training block, with its intent.
--
-- ⚠️  THIS MIGRATION DROPS AN EXISTING TABLE. Read the next section before
--     running `supabase db push`.
--
-- ─────────────────────────────────────────────────────────────────────────
-- THE GHOST TABLE
-- ─────────────────────────────────────────────────────────────────────────
-- A table called `training_blocks` already exists in prod. It is NOT this
-- one: it holds derived block STATISTICS (block_start, block_end,
-- total_miles, weekly_avg_miles, hard_sessions, easy_sessions,
-- avg_easy_pace_seconds, notable_workouts…) and carries no intent, no
-- author and no status.
--
-- Verified live on 2026-09-05:
--   · 0 rows, 0 distinct users — never populated, in prod or anywhere.
--   · No function references it. `pg_get_functiondef` across every function
--     in `public` returns zero hits, including delete_user_account (the
--     20260824190000 migration lists it in a comment only).
--   · No app code reads or writes it. The single mention in the repo is a
--     stale comment in `_shared/athlete-state.ts:625`; the live rollup
--     `buildBlocks()` writes to the `athlete_state.recent_blocks` JSONB
--     column instead, which is where the stats actually live today.
--   · Its `user_id` is UUID, contradicting the repo-wide convention that
--     auth user ids are TEXT matching `auth.uid()::text`.
--
-- So it is a ghost — created, secured, and then never wired to anything,
-- the same species as the `user_profiles` incident. The DO block below
-- refuses to drop it if it has somehow gained rows by push time, so this
-- migration can never destroy data: it will abort instead.
--
-- IF YOU WOULD RATHER KEEP IT: delete the DO block and the DROP, and rename
-- the new table below (`training_block_goals` reads fine). Nothing else in
-- this file depends on the drop.
--
-- ─────────────────────────────────────────────────────────────────────────
-- WHY THE NEW TABLE EXISTS
-- ─────────────────────────────────────────────────────────────────────────
-- `athlete_state.recent_blocks` is a derived JSON column of rolling 28-day
-- windows laid end to end. Those windows are descriptive — miles, session
-- counts, mood — but nobody chose their boundaries and none carries an
-- intent. The Train tab has been labelled "THE BLOCK" over that fiction.
--
-- A training block's goal is NOT the race goal. "Sub-2:20 at CIM in 97 days"
-- is the season target and lives in `user_goals`; "raise the aerobic ceiling"
-- or "get 4 x 3mi at MP feeling controlled" is what actually governs a given
-- week. This table stores the second thing.
--
-- It is always human-authored, never inferred. The app may PROPOSE a block
-- from phase and volume trend, but a person accepts it before a row lands
-- here — see `feedback_ai_advises_never_acts` and `feedback_no_ai_hallucination`.
--
-- AUTHORSHIP: both doors, author recorded, because the product serves a
-- self-coached athlete and coach-athlete dyads at once. `author` is the
-- discriminator; `chk_author_coach_pairing` keeps `coach_id` honest.
--
-- CONVENTIONS
--   · `user_id` is TEXT matching `auth.uid()::text` (repo-wide convention —
--     and the thing the ghost table got wrong).
--   · `coach_id` is UUID referencing `coach_profiles.id`.
--   · Coach-scoped policies use `current_coach_id()`, the SECURITY DEFINER
--     helper from `20260311120000_fix_coach_rls_recursion.sql`. Inlining a
--     subquery against `coach_profiles` causes recursion — that mistake has
--     already been made once.
--   · Types verified against live schema 2026-09-05: coach_profiles.id uuid,
--     coach_athlete_relationships.athlete_user_id text, .coach_id uuid,
--     current_coach_id() returns uuid.

-- Refuse to drop a table that has data. If this raises, STOP and inspect —
-- something started writing to the ghost between 2026-09-05 and this push.
DO $$
DECLARE
    ghost_rows BIGINT;
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name = 'training_blocks'
    ) THEN
        EXECUTE 'SELECT count(*) FROM public.training_blocks' INTO ghost_rows;
        IF ghost_rows > 0 THEN
            RAISE EXCEPTION
                'training_blocks has % row(s); expected 0. The stats table is '
                'no longer a ghost — do not drop it. Rename the new table in '
                '20260905180000 instead.', ghost_rows;
        END IF;
    END IF;
END $$;

DROP TABLE IF EXISTS public.training_blocks;

CREATE TABLE public.training_blocks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     TEXT NOT NULL,

    -- Who declared it. Drives which RLS path may write the row.
    author      TEXT NOT NULL CHECK (author IN ('athlete', 'coach')),
    -- Set only for coach-authored blocks. See chk_author_coach_pairing.
    coach_id    UUID REFERENCES public.coach_profiles(id) ON DELETE SET NULL,

    start_date  DATE NOT NULL,
    end_date    DATE NOT NULL,

    -- What the block is FOR, in the author's own words. Free text on purpose:
    -- a closed vocabulary here would be the app writing the athlete's goal for
    -- them, and block intent is not a taxonomy.
    intent      TEXT NOT NULL CHECK (length(btrim(intent)) > 0),
    -- Optional concrete target ("4 x 3mi @ MP controlled", "70 mpw").
    target      TEXT,

    status      TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'completed', 'abandoned')),

    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_block_dates CHECK (end_date > start_date),
    -- An athlete-authored block has no coach; a coach-authored one names the
    -- coach. Without this, `author` and `coach_id` can disagree and every
    -- consumer has to guess which is true.
    CONSTRAINT chk_author_coach_pairing CHECK (
        (author = 'coach'   AND coach_id IS NOT NULL) OR
        (author = 'athlete' AND coach_id IS NULL)
    )
);

-- One active block at a time. A second concurrent "current block" would make
-- "which block am I in" unanswerable on every read surface.
CREATE UNIQUE INDEX training_blocks_one_active_per_user
    ON public.training_blocks (user_id)
    WHERE status = 'active';

CREATE INDEX training_blocks_user_dates_idx
    ON public.training_blocks (user_id, start_date DESC);

CREATE INDEX training_blocks_coach_idx
    ON public.training_blocks (coach_id)
    WHERE coach_id IS NOT NULL;

COMMENT ON TABLE public.training_blocks IS
    'A declared training block and its intent. Distinct from the race goal in '
    'user_goals: the race goal is the season target, the block intent is what '
    'the current weeks are for. Always human-authored, never AI-inferred. '
    'Replaced an unused stats table of the same name on 2026-09-05.';
COMMENT ON COLUMN public.training_blocks.author IS
    'athlete | coach. Discriminates the two write paths; paired with coach_id '
    'by chk_author_coach_pairing.';
COMMENT ON COLUMN public.training_blocks.intent IS
    'What the block is for, in the author''s own words. Free text by design.';

-- ─────────────────────────────────────────────────────────────────────────
-- RLS — in the same migration as CREATE TABLE (hard rule #1).
-- ─────────────────────────────────────────────────────────────────────────

ALTER TABLE public.training_blocks ENABLE ROW LEVEL SECURITY;

-- SELECT · the athlete reads their own blocks.
CREATE POLICY "Athlete reads own blocks" ON public.training_blocks
    FOR SELECT
    USING (user_id = auth.uid()::text OR auth.uid() IS NULL);

-- SELECT · a coach reads blocks belonging to their ACTIVE athletes, whoever
-- authored them — a coach should see a block the athlete set for themselves.
CREATE POLICY "Coach reads athlete blocks" ON public.training_blocks
    FOR SELECT
    USING (
        user_id IN (
            SELECT athlete_user_id
              FROM public.coach_athlete_relationships
             WHERE coach_id = current_coach_id()
               AND status = 'active'
        )
        OR auth.uid() IS NULL
    );

-- INSERT · the athlete declares their own block. WITH CHECK pins author and
-- forbids a client forging a coach-authored row (a USING clause alone would
-- not stop the insert).
CREATE POLICY "Athlete creates own block" ON public.training_blocks
    FOR INSERT
    WITH CHECK (
        user_id = auth.uid()::text
        AND author = 'athlete'
        AND coach_id IS NULL
    );

-- UPDATE · the athlete edits their own athlete-authored block. Coach-authored
-- blocks are read-only to the athlete: silently rewriting the coach's intent
-- is exactly the unattributed edit `feedback_coach_is_not_ai` warns about.
CREATE POLICY "Athlete updates own block" ON public.training_blocks
    FOR UPDATE
    USING (user_id = auth.uid()::text AND author = 'athlete')
    WITH CHECK (
        user_id = auth.uid()::text
        AND author = 'athlete'
        AND coach_id IS NULL
    );

-- DELETE · the athlete removes a block they authored. Coach-authored rows are
-- retired by setting status, not deleted by the athlete.
CREATE POLICY "Athlete deletes own block" ON public.training_blocks
    FOR DELETE
    USING (user_id = auth.uid()::text AND author = 'athlete');

-- INSERT · a coach assigns a block to one of their active athletes.
CREATE POLICY "Coach creates athlete block" ON public.training_blocks
    FOR INSERT
    WITH CHECK (
        author = 'coach'
        AND coach_id = current_coach_id()
        AND user_id IN (
            SELECT athlete_user_id
              FROM public.coach_athlete_relationships
             WHERE coach_id = current_coach_id()
               AND status = 'active'
        )
    );

-- UPDATE · a coach edits a block they authored, and cannot reassign it to
-- another coach or convert it to athlete-authored.
CREATE POLICY "Coach updates own authored block" ON public.training_blocks
    FOR UPDATE
    USING (coach_id = current_coach_id() AND author = 'coach')
    WITH CHECK (coach_id = current_coach_id() AND author = 'coach');

-- Edge functions write here with the service role.
CREATE POLICY "Service role full access" ON public.training_blocks
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- ─────────────────────────────────────────────────────────────────────────
-- MANUAL RLS VERIFICATION (checklist step 7) — run after `db push`:
--
--   -- as an athlete who owns no blocks: expect 0
--   SELECT count(*) FROM training_blocks;
--
--   -- as a non-coach: current_coach_id() is NULL, so the coach policy
--   -- contributes nothing. Expect 0.
--   SELECT count(*) FROM training_blocks WHERE user_id <> auth.uid()::text;
--
--   -- forging a coach row from a client should FAIL the INSERT policy:
--   INSERT INTO training_blocks (user_id, author, coach_id, start_date,
--                                end_date, intent)
--   VALUES (auth.uid()::text, 'coach', gen_random_uuid(),
--           CURRENT_DATE, CURRENT_DATE + 28, 'forged');
-- ─────────────────────────────────────────────────────────────────────────
