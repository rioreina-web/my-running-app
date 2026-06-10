-- ============================================================================
-- Weather Cache
--
-- Per-location, per-hour weather observations from Open-Meteo, keyed so we
-- can check for hits before calling the API. RLS disabled — service-role
-- only (edge functions), never addressed directly by user clients.
--
-- Keys are quantized to keep the cache small:
--   lat_key  = round(lat * 100)   → ~1.1 km buckets
--   lon_key  = round(lon * 100)
--   hour_key = floor(unix_ts / 3600)
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS weather_cache (
    lat_key INTEGER NOT NULL,
    lon_key INTEGER NOT NULL,
    hour_key BIGINT NOT NULL,

    temperature_f NUMERIC,
    dew_point_f NUMERIC,
    humidity INTEGER,
    wind_speed_mph NUMERIC,
    weather_code INTEGER,

    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (lat_key, lon_key, hour_key)
);

-- No user-facing access — edge functions bypass RLS via service role.
ALTER TABLE weather_cache ENABLE ROW LEVEL SECURITY;
-- (Deliberately no SELECT/INSERT/UPDATE policies: only service_role reads/writes.)

COMMIT;
