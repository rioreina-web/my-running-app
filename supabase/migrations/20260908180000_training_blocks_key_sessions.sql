-- training_blocks — drop the free-text fields. A block is dates; what fills
-- it is the key sessions already in the data.
--
-- WHY
-- The table landed in prod on 2026-09-08 carrying `intent` (NOT NULL free
-- text, "raise the aerobic ceiling") and an optional `target`. Those were the
-- fiddly part: they asked the athlete to write and maintain prose describing
-- a block, on top of the goal they already keep in `user_goals`. Rio's call —
-- "I don't want this to be difficult to use, simplify it", then "we do want
-- to have training blocks be around key targets".
--
-- So the block keeps its boundaries and loses its prose. What characterises a
-- block is which KEY SESSIONS fall inside it, and those already exist: the
-- athlete stars a day (`day_overrides.is_key_session`), the plan can intend
-- one (`scheduled_workouts`), and quality_load derives one
-- (`workout_features`). `KeySessionStore` already resolves all three into one
-- answer for four surfaces. A block needs to add nothing to that — it just
-- bounds it.
--
-- Net effect: declaring a block is picking a start and an end. There is no
-- text field, so there is nothing to keep current.
--
-- Safe as written: the table is empty (created in prod earlier today, 0 rows,
-- no readers or writers in app code), so dropping a NOT NULL column loses
-- nothing. `author`, `coach_id` and `status` stay — who drew the boundaries
-- still matters, and one-active-block still matters.

ALTER TABLE public.training_blocks
    DROP COLUMN IF EXISTS intent,
    DROP COLUMN IF EXISTS target;

COMMENT ON TABLE public.training_blocks IS
    'A training block: a start and an end someone declared. Carries no prose — '
    'what characterises a block is the key sessions inside it '
    '(day_overrides.is_key_session / scheduled_workouts / workout_features, '
    'resolved by KeySessionStore). The season target lives in user_goals; a '
    'block does not restate it.';
