-- Watches — a thing to look for in training, written by the athlete or the coach.
--
-- The three watches that exist today are hand-written TypeScript. That proved
-- the shape and is the wrong way to ship: a coach can't write a `.ts` file, and
-- a new thing to look for shouldn't need a deploy. A watch becomes a row.
--
-- Shape mirrors `_shared/watch/authored.ts`:
--   metric + comparison + threshold + window + how-many-times + cooldown
--
-- What is deliberately NOT here: free-form logic. `metric` is a closed
-- vocabulary matching `_shared/watch/metrics.ts`, the same discipline as
-- reschedule-plan's closed workout library. A language model may help someone
-- phrase a watch, and it words the message when one fires — but it never
-- invents something to measure, and it is nowhere in the check itself, which
-- is arithmetic.
--
-- Hard rules: #1 RLS ships in this migration, #5 append-only, #6
-- current_coach_id() for coach scoping, #9 prod only via `supabase db push`
-- from a committed SHA.

BEGIN;

CREATE TABLE IF NOT EXISTS watches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ── Ownership ────────────────────────────────────────────────────────
    -- Exactly one of these is set. An athlete's own watch has author_user_id;
    -- a coach's has author_coach_id. Enforced by the CHECK below.
    author_user_id  TEXT,
    author_coach_id UUID REFERENCES coach_profiles(id) ON DELETE CASCADE,

    -- Who it watches. Always an athlete, whoever wrote it.
    athlete_user_id TEXT NOT NULL,

    -- ── What it looks for ────────────────────────────────────────────────
    label TEXT NOT NULL CHECK (length(trim(label)) > 0),

    -- Closed vocabulary — keep in step with metrics.ts METRIC_IDS.
    metric TEXT NOT NULL CHECK (metric IN (
        'easy_run_hr',
        'easy_run_pace',
        'easy_share',
        'mood_level',
        'niggle_mentions',
        'days_without_rest',
        'weekly_mileage_jump'
    )),

    comparison TEXT NOT NULL CHECK (comparison IN ('above', 'below')),
    threshold DOUBLE PRECISION NOT NULL,

    window_days INTEGER NOT NULL CHECK (window_days BETWEEN 1 AND 365),

    -- "so one hill doesn't count" — readings that must breach before it speaks.
    min_observations INTEGER NOT NULL DEFAULT 1 CHECK (min_observations >= 1),

    -- The noise control. A standing truth should be said once, not daily.
    cooldown_days INTEGER NOT NULL DEFAULT 7 CHECK (cooldown_days BETWEEN 0 AND 365),

    severity TEXT NOT NULL DEFAULT 'low'
        CHECK (severity IN ('info', 'low', 'med', 'high')),

    -- The move to propose. NULL = an observation, not an ask. Mirrors
    -- plan_adjustments.action_type; nothing here applies anything.
    suggested_action TEXT
        CHECK (suggested_action IS NULL OR suggested_action IN (
            'reprice_future_paces', 'reduce_volume', 'cap_volume', 'propose_swap',
            'update_fitness', 'pause_quality', 'shift_day', 'insert_rest'
        )),

    -- What the person actually typed, kept beside the parsed row as the
    -- record of intent — "so you can see later what you meant".
    source_sentence TEXT,

    -- ── State ────────────────────────────────────────────────────────────
    enabled BOOLEAN NOT NULL DEFAULT TRUE,

    -- An athlete may mute a coach's watch; the coach can see that they did.
    muted_until TIMESTAMPTZ,
    muted_by_user_id TEXT,

    -- The honesty counter. A watch that has fired nine times this month is a
    -- watch set wrong, and the list should say so before anyone works it out.
    fired_count INTEGER NOT NULL DEFAULT 0,
    last_fired_at TIMESTAMPTZ,

    -- "Not useful" presses. This is the data that tells us which templates
    -- are badly tuned, so it is counted, not just acted on.
    dismissed_count INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT watches_single_author CHECK (
        (author_user_id IS NOT NULL AND author_coach_id IS NULL) OR
        (author_user_id IS NULL AND author_coach_id IS NOT NULL)
    )
);

COMMENT ON TABLE watches IS
    'Athlete- or coach-authored things to look for in training. Evaluated by '
    '_shared/watch/authored.ts against a closed metric registry. The check is '
    'arithmetic; no model is in the trigger path.';
COMMENT ON COLUMN watches.min_observations IS
    'How many readings in the window must breach before the watch speaks. The '
    'difference between firing on one warm Tuesday and firing on a habit.';
COMMENT ON COLUMN watches.source_sentence IS
    'The sentence the person typed, kept beside the parsed row. Never re-parsed '
    'at evaluation time — the row is the contract, the sentence is the record.';

CREATE INDEX IF NOT EXISTS idx_watches_athlete_enabled
    ON watches(athlete_user_id) WHERE enabled;
CREATE INDEX IF NOT EXISTS idx_watches_author_coach
    ON watches(author_coach_id) WHERE author_coach_id IS NOT NULL;

-- ── RLS (hard rule #1) ───────────────────────────────────────────────────

ALTER TABLE watches ENABLE ROW LEVEL SECURITY;

-- An athlete sees every watch aimed at them, including their coach's — the
-- prototype is explicit that coach watches are marked but not walled off.
CREATE POLICY "Athletes read watches aimed at them"
    ON watches FOR SELECT
    USING (auth.uid()::text = athlete_user_id);

-- An athlete writes only their own.
CREATE POLICY "Athletes write their own watches"
    ON watches FOR INSERT
    WITH CHECK (auth.uid()::text = athlete_user_id
                AND auth.uid()::text = author_user_id
                AND author_coach_id IS NULL);

-- An athlete may edit their own outright, and may mute a coach's. The column
-- guard below is what stops muting from becoming silent editing.
CREATE POLICY "Athletes update watches aimed at them"
    ON watches FOR UPDATE
    USING (auth.uid()::text = athlete_user_id)
    WITH CHECK (auth.uid()::text = athlete_user_id);

CREATE POLICY "Athletes delete their own watches"
    ON watches FOR DELETE
    USING (auth.uid()::text = athlete_user_id
           AND auth.uid()::text = author_user_id);

-- Coaches manage watches they authored, scoped by the SECURITY DEFINER helper
-- (hard rule #6 — a direct coach_profiles subquery recurses).
CREATE POLICY "Coaches manage their own watches"
    ON watches FOR ALL
    USING (author_coach_id = current_coach_id())
    WITH CHECK (author_coach_id = current_coach_id());

CREATE POLICY "Service role full access to watches"
    ON watches FOR ALL
    USING (auth.role() = 'service_role');

-- An athlete may mute a coach's watch, not quietly rewrite it. Without this,
-- the athlete UPDATE policy above would let them move a coach's threshold and
-- leave the coach believing their watch was still set where they left it.
CREATE OR REPLACE FUNCTION enforce_watch_athlete_columns()
RETURNS TRIGGER AS $$
BEGIN
    IF auth.role() = 'service_role' THEN
        RETURN NEW;
    END IF;

    -- Editing your own watch is unrestricted.
    IF OLD.author_user_id IS NOT NULL
       AND OLD.author_user_id = auth.uid()::text THEN
        RETURN NEW;
    END IF;

    -- Otherwise it's a coach's watch: mute fields only.
    IF NEW.label            IS DISTINCT FROM OLD.label
       OR NEW.metric           IS DISTINCT FROM OLD.metric
       OR NEW.comparison       IS DISTINCT FROM OLD.comparison
       OR NEW.threshold        IS DISTINCT FROM OLD.threshold
       OR NEW.window_days      IS DISTINCT FROM OLD.window_days
       OR NEW.min_observations IS DISTINCT FROM OLD.min_observations
       OR NEW.cooldown_days    IS DISTINCT FROM OLD.cooldown_days
       OR NEW.severity         IS DISTINCT FROM OLD.severity
       OR NEW.suggested_action IS DISTINCT FROM OLD.suggested_action
       OR NEW.athlete_user_id  IS DISTINCT FROM OLD.athlete_user_id
       OR NEW.author_user_id   IS DISTINCT FROM OLD.author_user_id
       OR NEW.author_coach_id  IS DISTINCT FROM OLD.author_coach_id THEN
        RAISE EXCEPTION
            'You can mute a coach''s watch, but not change what it looks for.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE TRIGGER trg_watches_athlete_column_guard
    BEFORE UPDATE ON watches
    FOR EACH ROW
    EXECUTE FUNCTION enforce_watch_athlete_columns();

COMMIT;
