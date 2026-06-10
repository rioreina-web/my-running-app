-- Serialize athlete_state rebuilds (HOTFIX-H.2).
--
-- Problem: rebuildAthleteState in _shared/athlete-state.ts is a 900+ LOC
-- function that runs 10 parallel queries and takes ~1-2s. When N callers hit
-- getOrBuildAthleteState on a cold or stale user, all N run the rebuild and
-- race on the final upsert.
--
-- Naive pg_advisory_xact_lock inside a one-shot RPC doesn't help — the lock
-- releases the instant the RPC transaction ends, well before the JS-side
-- rebuild is done. We'd get full lock serialization only if the entire
-- rebuild ran inside plpgsql, which isn't feasible.
--
-- Design: "claim" pattern backed by the athlete_state row.
--   1. claim_athlete_state_rebuild(user_id) acquires an xact-scoped advisory
--      lock scoped to that user so the claim check is atomic.
--   2. Returns false if the state is fresh (<30s) — caller uses the cache.
--   3. Returns false if another claim is in-flight (<120s) — caller waits
--      briefly and reads the result.
--   4. Otherwise stamps rebuild_started_at = now() and returns true; the
--      caller proceeds with the full rebuild, whose final upsert will
--      overwrite last_updated_at (making the row fresh again).
--
-- The xact lock prevents two callers from both passing the freshness +
-- in-flight checks simultaneously. The marker prevents a third caller from
-- starting a parallel rebuild while the first is still running.

ALTER TABLE athlete_state
    ADD COLUMN IF NOT EXISTS rebuild_started_at timestamptz;

CREATE OR REPLACE FUNCTION claim_athlete_state_rebuild(
    p_user_id text,
    p_fresh_seconds int DEFAULT 30,
    p_in_flight_seconds int DEFAULT 120
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_updated timestamptz;
    v_in_flight timestamptz;
BEGIN
    -- Serialize the claim check for this user. Auto-released at xact end.
    PERFORM pg_advisory_xact_lock(hashtext('athlete_state:claim:' || p_user_id));

    SELECT last_updated_at, rebuild_started_at
      INTO v_last_updated, v_in_flight
      FROM athlete_state
      WHERE user_id = p_user_id;

    -- State is fresh — caller uses cached row, no rebuild needed.
    IF v_last_updated IS NOT NULL
       AND v_last_updated > now() - make_interval(secs => p_fresh_seconds) THEN
        RETURN false;
    END IF;

    -- Another rebuild is in flight and hasn't stalled — caller should wait
    -- rather than start a second one.
    IF v_in_flight IS NOT NULL
       AND v_in_flight > now() - make_interval(secs => p_in_flight_seconds) THEN
        RETURN false;
    END IF;

    -- Stake the claim. Upsert handles first-ever-build case.
    INSERT INTO athlete_state (user_id, rebuild_started_at, last_updated_by)
    VALUES (p_user_id, now(), 'claiming')
    ON CONFLICT (user_id) DO UPDATE
        SET rebuild_started_at = now();

    RETURN true;
END;
$$;
