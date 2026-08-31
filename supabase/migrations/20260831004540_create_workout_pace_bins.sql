-- Per-workout pace histogram, binned from the 1 Hz Garmin/Strava streams rather
-- than from laps. Laps are auto-lap mile splits for most runs, so a lap-derived
-- histogram can only ever resolve one mile at a time and averages away anything
-- that does not line up with a mile marker.
--
-- One row per (workout, 5-second pace bucket). Width 5 so the UI can aggregate
-- to 10s bins exactly, or wider, without recomputing.

CREATE TABLE IF NOT EXISTS public.workout_pace_bins (
    workout_id    uuid        NOT NULL REFERENCES public.training_logs(id) ON DELETE CASCADE,
    user_id       text        NOT NULL,
    workout_date  timestamptz NOT NULL,
    bin_start_sec integer     NOT NULL,
    miles         numeric(9,4)  NOT NULL,
    seconds       numeric(10,2) NOT NULL,
    PRIMARY KEY (workout_id, bin_start_sec),
    CONSTRAINT workout_pace_bins_bin_range   CHECK (bin_start_sec BETWEEN 180 AND 1500),
    CONSTRAINT workout_pace_bins_bin_width   CHECK (bin_start_sec % 5 = 0),
    CONSTRAINT workout_pace_bins_nonnegative CHECK (miles >= 0 AND seconds >= 0)
);

COMMENT ON TABLE public.workout_pace_bins IS
  'Per-workout pace histogram in 5 sec/mile buckets, computed from the distance+time streams by compute_pace_bins(). Every moving meter of a run lands in exactly one bucket, so SUM(miles) per workout reconciles to its moving distance. Read through pace_spectrum() / pace_band_totals(), never directly -- both read this table so the histogram and the threshold card cannot disagree.';
COMMENT ON COLUMN public.workout_pace_bins.bin_start_sec IS
  'Floor of the 5-second pace bucket, in seconds per mile. 320 = the 5:20-5:24 bucket.';

CREATE INDEX IF NOT EXISTS idx_workout_pace_bins_user_date
    ON public.workout_pace_bins (user_id, workout_date DESC);
CREATE INDEX IF NOT EXISTS idx_workout_pace_bins_user_bin
    ON public.workout_pace_bins (user_id, bin_start_sec, workout_date DESC);

ALTER TABLE public.workout_pace_bins ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_workout_pace_bins_select_own
    ON public.workout_pace_bins FOR SELECT
    USING (user_id = (auth.uid())::text);

CREATE POLICY rls_workout_pace_bins_service
    ON public.workout_pace_bins FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Provenance, so the UI can tell an athlete how much of a window was measured
-- at stream resolution versus fallen back to something coarser.
ALTER TABLE public.training_logs
    ADD COLUMN IF NOT EXISTS pace_bins_source      text,
    ADD COLUMN IF NOT EXISTS pace_bins_miles       numeric,
    ADD COLUMN IF NOT EXISTS pace_bins_computed_at timestamptz;

ALTER TABLE public.training_logs
    DROP CONSTRAINT IF EXISTS training_logs_pace_bins_source_check;
ALTER TABLE public.training_logs
    ADD CONSTRAINT training_logs_pace_bins_source_check
    CHECK (pace_bins_source IS NULL
           OR pace_bins_source IN ('stream', 'laps', 'average', 'none'));

COMMENT ON COLUMN public.training_logs.pace_bins_source IS
  'How workout_pace_bins rows for this log were derived: stream (1 Hz distance+time, correct), laps (lap averages, mile-resolution fallback), average (whole run at one pace, last resort), none (not binnable -- no distance or no duration).';
COMMENT ON COLUMN public.training_logs.pace_bins_miles IS
  'Miles actually binned. Percentages must be computed against SUM(pace_bins_miles), not SUM(workout_distance_miles), or unbinnable runs silently deflate every bin.';;
