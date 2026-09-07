-- ============================================================================
-- Coach-defined custom workout labels ("add your own")
--
-- The workout builder ships a fixed set of workout-type chips (easy, steady,
-- tempo, intervals, fartlek, long run, long run workout, progression,
-- recovery, strides, race). Coaches asked to define their OWN labels — a
-- reusable, per-coach library (name + color) that persists and syncs.
--
-- Model:
--   - Each custom label is a row here, owned by one coach.
--   - `slug` is the machine key; the value stored on a workout's
--     `workout_type` is `custom:<slug>` (e.g. 'custom:hill-repeats').
--   - `label` is what the coach sees on the chip; `color` is an on-brand
--     hex from the Post Run Drip pace ramp (validated to #RRGGBB).
--
-- Why a `custom:` prefix rather than dropping the CHECK entirely:
--   keeps the built-in vocabulary validated (typo protection, analytics
--   stay clean) while giving custom labels a clearly-namespaced escape
--   hatch. See the CHECK widening at the bottom of this migration.
--
-- RLS mirrors coach_notes (20260522130619): coaches manage their own rows
-- via current_coach_id(); athletes may READ the labels belonging to a coach
-- they have an active relationship with, so the athlete app can render a
-- coach-issued custom label with its real name + color.
--
-- Append-only (hard rule #5). Apply via `supabase db push` from a committed
-- SHA (hard rule #9) — NOT the dashboard SQL editor or MCP apply_migration.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS coach_workout_labels (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id   UUID NOT NULL REFERENCES coach_profiles(id) ON DELETE CASCADE,
    -- Machine key used in workout_type as `custom:<slug>`. Lowercase,
    -- alnum with single -/_ separators. Generated app-side from `label`.
    slug       TEXT NOT NULL CHECK (slug ~ '^[a-z0-9]+(?:[-_][a-z0-9]+)*$'),
    -- Human-facing chip text. Non-empty.
    label      TEXT NOT NULL CHECK (length(trim(label)) > 0),
    -- On-brand hex (#RRGGBB). App offers pace-ramp swatches; the CHECK just
    -- guards the shape so nothing malformed lands in an inline style.
    color      TEXT NOT NULL CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- One slug per coach; lets the app upsert/dedupe cleanly.
    UNIQUE (coach_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_coach_workout_labels_coach
    ON coach_workout_labels (coach_id, created_at DESC);

ALTER TABLE coach_workout_labels ENABLE ROW LEVEL SECURITY;

-- Coaches: full read/write on labels they own.
CREATE POLICY "Coaches manage own workout labels"
    ON coach_workout_labels FOR ALL
    USING (coach_id = current_coach_id())
    WITH CHECK (coach_id = current_coach_id());

-- Athletes: read the labels of any coach they have an active relationship
-- with, so a `custom:<slug>` on a scheduled workout can be rendered with its
-- real name + color on the athlete side. Read-only; no write path.
CREATE POLICY "Athletes read their coach's workout labels"
    ON coach_workout_labels FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM coach_athlete_relationships car
            WHERE car.coach_id = coach_workout_labels.coach_id
              AND car.athlete_user_id = auth.uid()::text
              AND car.status = 'active'
        )
    );

-- ── Widen the workout_type CHECK to accept `custom:<slug>` ───────────────
-- Additive, like 20260702210000: the full built-in vocabulary is retained
-- verbatim; we only OR in the namespaced custom pattern. No existing row is
-- invalidated. (training_logs.workout_type stays free TEXT — see
-- 20260702210000 — so no change is needed there.)

ALTER TABLE scheduled_workouts
  DROP CONSTRAINT IF EXISTS scheduled_workouts_workout_type_check;

ALTER TABLE scheduled_workouts
  ADD CONSTRAINT scheduled_workouts_workout_type_check
  CHECK (
    workout_type IN (
      'long_run', 'tempo', 'intervals', 'progression', 'fartlek', 'hills',
      'easy', 'recovery', 'rest', 'race',
      'moderate', 'steady',
      'mp', 'hmp', 'lt', '10k', '5k', '3k', 'mile',
      'long_wo', 'cross_train', 'strength'
    )
    OR workout_type LIKE 'custom:%'
  );

ALTER TABLE workout_templates
  DROP CONSTRAINT IF EXISTS workout_templates_workout_type_check;

ALTER TABLE workout_templates
  ADD CONSTRAINT workout_templates_workout_type_check
  CHECK (
    workout_type IN (
      'long_run', 'tempo', 'intervals', 'progression', 'fartlek', 'hills',
      'easy', 'recovery', 'rest', 'race',
      'moderate', 'steady',
      'mp', 'hmp', 'lt', '10k', '5k', '3k', 'mile',
      'long_wo', 'cross_train', 'strength'
    )
    OR workout_type LIKE 'custom:%'
  );

COMMIT;

-- ── Verification (run manually after deploy) ─────────────────────────────
--   SELECT DISTINCT workout_type FROM workout_templates
--     WHERE workout_type LIKE 'custom:%';
--   -- Should list only namespaced custom labels; every other value must
--   -- still be inside the built-in set above.
--   -- RLS smoke: as a coach, INSERT a label; as an unrelated athlete,
--   -- SELECT should return zero rows.
