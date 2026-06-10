-- Stale-invalidation trigger for athlete_state
--
-- Problem: training_logs can be written by multiple paths (Strava pull,
-- HealthKit sync, reconcile-log, direct iOS inserts) that don't know to
-- update athlete_state. Result: getOrBuildAthleteState's 60-min cache
-- returns stale state after a sync.
--
-- Fix: any write to training_logs invalidates the athlete_state row by
-- pushing last_updated_at into the past. The next getOrBuildAthleteState
-- call sees the staleness and rebuilds. Writers no longer need to know
-- about state.
--
-- Cost: one indexed UPDATE per training_logs row change. The PK lookup
-- by user_id is O(1). No-ops when the user has no state row yet.

CREATE OR REPLACE FUNCTION invalidate_athlete_state_on_training_log()
RETURNS trigger AS $$
DECLARE
    affected_user_id text;
BEGIN
    -- On DELETE the new row is null; on INSERT/UPDATE use NEW.
    affected_user_id := COALESCE(NEW.user_id, OLD.user_id);

    IF affected_user_id IS NOT NULL THEN
        UPDATE athlete_state
        SET last_updated_at = '1970-01-01'::timestamptz,
            last_updated_by = 'invalidated:training_log_' || TG_OP
        WHERE user_id = affected_user_id;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invalidate_athlete_state ON training_logs;

CREATE TRIGGER trg_invalidate_athlete_state
    AFTER INSERT OR UPDATE OR DELETE ON training_logs
    FOR EACH ROW
    EXECUTE FUNCTION invalidate_athlete_state_on_training_log();
