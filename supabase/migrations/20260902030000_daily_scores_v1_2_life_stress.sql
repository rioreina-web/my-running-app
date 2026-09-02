-- ============================================================================
-- Daily scores v1.2 — outside-life stress (step 5 of the drip-scores handoff)
--
-- extract-rpe now returns a `life_stress` 0–4 (null when the memo never
-- mentions life outside training), stored on training_logs.felt_stress —
-- the number only, never the reason. This migration:
--
--   1. Adds training_logs.felt_stress smallint (0–4).
--   2. compute_daily_scores v1.2: the '-- outside stress' stub becomes a
--      real recovery component, deducting when today's mentioned stress sits
--      above the athlete's own 28-day median (default baseline 1 when there
--      isn't enough history) — same shape as the soreness/sleep components.
--   3. Recreates the auto_enqueue_daily_score_on_update trigger (from
--      20260902010000) with felt_stress in its WHEN list, so a memo that
--      mentions life stress recomputes today's score within a minute.
--
-- The handoff said "bump v_version to '1.1'" but was written before the
-- resting-HR change took that version; this is 1.2. Old 1.0/1.1 rows are
-- never recomputed in place (table comment rule); consumers already pick
-- max(score_version), and '1.2' sorts above '1.1' lexically.
--
-- Step 6 note: the scorer has mapped severity_hint 'none' -> soreness 0
-- since v1.0, so the "nothing hurts" memo rows (written by the niggle
-- extractor) need no scorer change.
-- ============================================================================

BEGIN;

ALTER TABLE training_logs
    ADD COLUMN IF NOT EXISTS felt_stress SMALLINT
    CHECK (felt_stress BETWEEN 0 AND 4);

COMMENT ON COLUMN training_logs.felt_stress IS
    'Outside-life stress 0-4 extracted from the memo by extract-rpe '
    '(life_stress). NULL = not mentioned. The number only — the reason is '
    'never stored. Read by compute_daily_scores >= v1.2.';

create or replace function compute_daily_scores(p_user_id text, p_from date default null, p_to date default null)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version    constant text := '1.2';
  tau_fit      constant double precision := 42;
  tau_fat      constant double precision := 7;
  kf           double precision := exp(-1/tau_fit);
  kfa          double precision := exp(-1/tau_fat);
  form_max     constant int := 30;
  spike_pts    constant int := 20;
  form_min_hist constant int := 28;
  mech_min_hist constant int := 14;
  mech_min_sess constant int := 6;
  base_days    constant int := 28;
  base_min_obs constant int := 5;
  d_first date; d_last date; d date;
  fitness double precision; fatigue double precision;
  seed double precision;
  hist int;
  srpe double precision;
  sess record;
  session_notes jsonb;
  spike_until date := null; spike_reason text := null;
  dmg_windows jsonb := '[]';
  w jsonb;
  form_pts int; form_detail text; gap double precision;
  dmg_pts int; dmg_detail text; remaining int; pts int;
  longest double precision; n_prior int;
  prior_q_median double precision; n_prior_q int;
  wk_thr double precision; prior_mean_thr double precision; avail_weeks int;
  tier text; reason text; n_mid int; mid_reason text;
  comps jsonb; rcomps jsonb; present int;
  soreness double precision; sleep_v double precision; stress_v double precision;
  base_v double precision; base_src text; n_obs int;
  recovery int; conf text;
  m7 double precision; mb double precision; cv7 double precision; cvb double precision; lower double precision;
  n7 int; nb int;
  rhr7 double precision; rhrb double precision; rhr_cvb double precision; rhr_upper double precision;
  rhr_n7 int; rhr_nb int;
  bits text;
  rows_written int := 0;
begin
  select min(workout_date::date), max(workout_date::date) into d_first, d_last
  from training_logs
  where user_id = p_user_id and stats_excluded is not true and superseded_at is null and duplicate_of is null
    and coalesce(workout_duration_minutes,0) > 0;
  if d_first is null then return 0; end if;
  d_last := greatest(d_last, coalesce(p_to, current_date));
  create temp table if not exists _ss (
    dt date, duration_min double precision, distance_km double precision,
    threshold_min double precision, descent_m double precision, is_race boolean,
    rpe double precision, rpe_src text, log_id uuid
  ) on commit drop;
  truncate _ss;
  insert into _ss
  select tl.workout_date::date,
         tl.workout_duration_minutes,
         coalesce(tl.workout_distance_miles,0) * 1.609344,
         coalesce(wf.threshold_seconds,0)/60.0 + coalesce(wf.hard_seconds,0)/60.0,
         0,
         (tl.workout_type = 'race' or tl.race_result is not null),
         tl.felt_rpe,
         case when tl.felt_rpe is null then 'estimated' else coalesce(tl.rpe_source,'memo') end,
         tl.id
  from training_logs tl
  left join workout_features wf on wf.training_log_id = tl.id
  where tl.user_id = p_user_id and tl.stats_excluded is not true and tl.superseded_at is null
    and tl.duplicate_of is null and coalesce(tl.workout_duration_minutes,0) > 0;
  update _ss set rpe = least(9, greatest(2, round((3 + 4*(threshold_min/duration_min) + case when duration_min > 90 then 1 else 0 end)::numeric, 1)))
  where rpe is null;
  select coalesce(sum(rpe*duration_min),0) / form_min_hist into seed
  from _ss where dt < d_first + form_min_hist;
  fitness := seed; fatigue := seed;
  d := d_first;
  while d <= d_last loop
    hist := d - d_first;
    srpe := 0; session_notes := '[]';
    for sess in select * from _ss where dt = d loop
      srpe := srpe + sess.rpe * sess.duration_min;
      session_notes := session_notes || jsonb_build_object('log_id', sess.log_id, 'km', round(sess.distance_km::numeric,1),
                                                           'rpe', sess.rpe, 'rpe_source', sess.rpe_src);
      select coalesce(max(distance_km),0), count(*) into longest, n_prior
      from _ss where dt between d - 30 and d - 1;
      if hist < mech_min_hist then n_prior := 0; end if;
      if n_prior >= mech_min_sess and sess.distance_km > 1.10 * longest then
        spike_until := d + 6;
        spike_reason := format('%s km is >110%% of your longest run in the prior 30 days (%s km)', round(sess.distance_km::numeric,1), round(longest::numeric,1));
      end if;
      avail_weeks := least(4, hist / 7);
      if avail_weeks >= 2 then
        select coalesce(sum(threshold_min),0) / avail_weeks into prior_mean_thr
        from _ss where dt between d - 7*avail_weeks and d - 1;
        select coalesce(sum(threshold_min),0) into wk_thr from _ss where dt between d - 6 and d;
        if prior_mean_thr >= 10 and wk_thr > 1.5 * prior_mean_thr and wk_thr >= prior_mean_thr + 20 then
          spike_until := d + 6;
          spike_reason := format('quality minutes this week (%s) well above your 4-week average (%s)', round(wk_thr), round(prior_mean_thr));
        end if;
      end if;
      tier := null; reason := null; n_mid := 0; mid_reason := null;
      if sess.distance_km >= 40 then
        tier := 'high'; reason := format('%s km session', round(sess.distance_km::numeric,1));
      else
        if sess.is_race and sess.distance_km >= 15 then n_mid := n_mid + 1; mid_reason := coalesce(mid_reason, format('race, %s km', round(sess.distance_km::numeric,1))); end if;
        if n_prior >= mech_min_sess and sess.distance_km > 1.15 * longest then n_mid := n_mid + 1; mid_reason := coalesce(mid_reason, format('%s km is >115%% of your longest run in the prior 30 days (%s km)', round(sess.distance_km::numeric,1), round(longest::numeric,1))); end if;
        if sess.distance_km >= 10 and sess.descent_m / sess.distance_km > 15 then n_mid := n_mid + 1; mid_reason := coalesce(mid_reason, 'heavy descent'); end if;
        if n_mid >= 2 then tier := 'high'; reason := mid_reason || ' (two triggers)';
        elsif n_mid = 1 then tier := 'mid'; reason := mid_reason;
        else
          if sess.is_race then tier := 'low'; reason := format('race, %s km', round(sess.distance_km::numeric,1));
          else
            select percentile_cont(0.5) within group (order by threshold_min), count(*) into prior_q_median, n_prior_q
            from _ss where dt between d - 28 and d - 1 and threshold_min > 0;
            if sess.threshold_min >= 20 and n_prior_q >= 4 and sess.threshold_min > 1.5 * prior_q_median then
              tier := 'low'; reason := format('%s min at threshold is >150%% of your usual quality session', round(sess.threshold_min));
            end if;
          end if;
        end if;
      end if;
      if tier is not null then
        dmg_windows := dmg_windows || jsonb_build_object(
          'end', (d + case tier when 'high' then 14 when 'mid' then 7 else 3 end)::text,
          'tier', tier, 'reason', reason,
          'total', case tier when 'high' then 14 when 'mid' then 7 else 3 end,
          'points', case tier when 'high' then 30 when 'mid' then 20 else 10 end);
      end if;
    end loop;
    fitness := fitness * kf + srpe * (1 - kf);
    fatigue := fatigue * kfa + srpe * (1 - kfa);
    form_pts := 0; gap := fatigue - fitness;
    if hist < form_min_hist then
      form_detail := format('building baseline (%s more days of history needed)', form_min_hist - hist);
    elsif fitness > 0 and gap > 0 then
      form_pts := least(form_max, round(form_max * gap / fitness))::int;
      form_detail := format('fatigue %s vs fitness %s (fatigue %s%% above fitness)', round(fatigue), round(fitness), round(100*gap/fitness));
    else
      form_detail := format('fatigue %s vs fitness %s (at or below fitness)', round(fatigue), round(fitness));
    end if;
    if spike_until is not null and spike_until < d then spike_until := null; spike_reason := null; end if;
    dmg_pts := 0; dmg_detail := 'no muscle-damage window open';
    for w in select * from jsonb_array_elements(dmg_windows) loop
      if (w->>'end')::date >= d then
        remaining := (w->>'end')::date - d;
        pts := round((w->>'points')::int * remaining::double precision / (w->>'total')::int)::int;
        if pts > dmg_pts then
          dmg_pts := pts;
          dmg_detail := format('%s tier, %s of %s days left: %s', w->>'tier', remaining, w->>'total', w->>'reason');
        end if;
      end if;
    end loop;
    select coalesce(jsonb_agg(x), '[]') into dmg_windows from jsonb_array_elements(dmg_windows) x where (x->>'end')::date >= d;
    comps := jsonb_build_array(
      jsonb_build_object('name','form','points',form_pts,'detail',form_detail),
      jsonb_build_object('name','spike','points', case when spike_until is not null then spike_pts else 0 end,
                         'detail', coalesce(spike_reason, 'no load spike in the last 7 days')),
      jsonb_build_object('name','damage','points',dmg_pts,'detail',dmg_detail));

    rcomps := '[]'; present := 0;
    -- soreness
    select max(case severity_hint when 'tight' then 1 when 'sore' then 2 when 'pain' then 3 when 'painful' then 3
                                  when 'stopped' then 4 when 'limping' then 4 when 'none' then 0 else 2 end)
    into soreness from body_mentions where user_id = p_user_id and mentioned_at = d;
    if soreness is null then
      rcomps := rcomps || jsonb_build_object('name','soreness','points',0,'detail','not mentioned');
    else
      present := present + 1;
      select percentile_cont(0.5) within group (order by v), count(*) into base_v, n_obs
      from (select max(case severity_hint when 'tight' then 1 when 'sore' then 2 when 'pain' then 3 when 'painful' then 3
                                          when 'stopped' then 4 when 'limping' then 4 when 'none' then 0 else 2 end) v
            from body_mentions where user_id = p_user_id and mentioned_at between d - base_days and d - 1 group by mentioned_at) s;
      if n_obs >= base_min_obs then base_src := 'your 28-day median'; else base_v := 1; base_src := 'default, not enough history'; end if;
      pts := case when soreness > base_v then -round(10 * (soreness - base_v))::int else 0 end;
      rcomps := rcomps || jsonb_build_object('name','soreness','points',pts,'detail', format('%s vs %s usual (%s)', soreness, base_v, base_src));
    end if;
    -- sleep
    select case sleep_quality when 'rough' then 1 when 'bad' then 1 when 'ok' then 3 when 'good' then 4 when 'great' then 4 end
    into sleep_v from daily_checkins where user_id = p_user_id and date = d;
    if sleep_v is null then
      rcomps := rcomps || jsonb_build_object('name','sleep','points',0,'detail','not mentioned');
    else
      present := present + 1;
      select percentile_cont(0.5) within group (order by v), count(*) into base_v, n_obs
      from (select case sleep_quality when 'rough' then 1 when 'bad' then 1 when 'ok' then 3 when 'good' then 4 when 'great' then 4 end v
            from daily_checkins where user_id = p_user_id and date between d - base_days and d - 1) s where v is not null;
      if n_obs >= base_min_obs then base_src := 'your 28-day median'; else base_v := 3; base_src := 'default, not enough history'; end if;
      pts := case when sleep_v < base_v then -round(10 * (base_v - sleep_v))::int else 0 end;
      rcomps := rcomps || jsonb_build_object('name','sleep','points',pts,'detail', format('%s vs %s usual (%s)', sleep_v, base_v, base_src));
    end if;
    -- outside stress (extract-rpe life_stress -> training_logs.felt_stress, v1.2)
    select max(felt_stress) into stress_v
      from training_logs
     where user_id = p_user_id and workout_date::date = d and felt_stress is not null;
    if stress_v is null then
      rcomps := rcomps || jsonb_build_object('name','stress','points',0,'detail','not mentioned');
    else
      present := present + 1;
      select percentile_cont(0.5) within group (order by v), count(*) into base_v, n_obs
      from (select max(felt_stress) v
              from training_logs
             where user_id = p_user_id and workout_date::date between d - base_days and d - 1
               and felt_stress is not null
             group by workout_date::date) s;
      if n_obs >= base_min_obs then base_src := 'your 28-day median'; else base_v := 1; base_src := 'default, not enough history'; end if;
      pts := case when stress_v > base_v then -round(10 * (stress_v - base_v))::int else 0 end;
      rcomps := rcomps || jsonb_build_object('name','stress','points',pts,'detail', format('%s vs %s usual (%s)', stress_v, base_v, base_src));
    end if;
    -- resting HR: elevated 7-day mean vs 28-day baseline band (higher = worse)
    select avg(resting_hr), count(*) into rhr7, rhr_n7 from daily_biometrics
      where user_id = p_user_id and date between d - 6 and d and resting_hr > 0;
    select avg(resting_hr), count(*), stddev_pop(resting_hr) into rhrb, rhr_nb, rhr_cvb from daily_biometrics
      where user_id = p_user_id and date between d - base_days - 6 and d - 7 and resting_hr > 0;
    if rhr_n7 >= 4 and rhr_nb >= 14 then
      present := present + 1;
      rhr_upper := rhrb + 0.5 * rhr_cvb;   -- 0.5 SD above baseline mean
      if rhr7 > rhr_upper then
        pts := -15;
        rcomps := rcomps || jsonb_build_object('name','resting_hr','points',pts,
                    'detail', format('7-day resting HR %s bpm, above your usual (%s)', round(rhr7), round(rhr_upper)));
      else
        rcomps := rcomps || jsonb_build_object('name','resting_hr','points',0,
                    'detail', format('7-day resting HR %s bpm, normal for you', round(rhr7)));
      end if;
    else
      rcomps := rcomps || jsonb_build_object('name','resting_hr','points',0,
                  'detail', case when rhr_n7 > 0 then 'building baseline' else 'no data' end);
    end if;
    -- hrv
    select avg(ln(hrv_rmssd)), count(*) into m7, n7 from daily_biometrics
      where user_id = p_user_id and date between d - 6 and d and hrv_rmssd > 0;
    select avg(ln(hrv_rmssd)), count(*), stddev_pop(ln(hrv_rmssd)) into mb, nb, cvb from daily_biometrics
      where user_id = p_user_id and date between d - base_days - 6 and d - 7 and hrv_rmssd > 0;
    if n7 >= 4 and nb >= 14 then
      present := present + 1;
      select stddev_pop(ln(hrv_rmssd)) into cv7 from daily_biometrics where user_id = p_user_id and date between d - 6 and d and hrv_rmssd > 0;
      cvb := cvb / nullif(mb,0); cv7 := cv7 / nullif(m7,0);
      lower := mb - 0.5 * cvb * mb;
      pts := 0; bits := null;
      if m7 < lower then pts := pts - 20; bits := format('7-day mean %s below your band (%s)', round(m7::numeric,2), round(lower::numeric,2)); end if;
      if cvb > 0 and cv7 < 0.5 * cvb then pts := pts - 10; bits := coalesce(bits || '; ', '') || 'day-to-day variation has collapsed'; end if;
      rcomps := rcomps || jsonb_build_object('name','hrv','points',pts,'detail', coalesce(bits, format('7-day mean %s, within your band', round(m7::numeric,2))));
    else
      rcomps := rcomps || jsonb_build_object('name','hrv','points',0,'detail', case when n7 > 0 then 'building baseline' else 'no data' end);
    end if;

    if present > 0 then
      select greatest(0, 100 + sum((c->>'points')::int)) into recovery from jsonb_array_elements(rcomps) c;
      conf := case when present >= 2 then 'ok' else 'low' end;
    else
      recovery := null; conf := 'none';
    end if;
    if p_from is null or d >= p_from then
      insert into daily_scores (user_id, score_date, score_version, srpe, fitness, fatigue, stress, stress_components,
                                recovery, recovery_confidence, recovery_components, sessions, computed_at)
      values (p_user_id, d, v_version, round(srpe), round(fitness::numeric,1), round(fatigue::numeric,1),
              least(100, form_pts + case when spike_until is not null then spike_pts else 0 end + dmg_pts),
              comps, recovery, conf, rcomps, session_notes, now())
      on conflict (user_id, score_date, score_version) do update
        set srpe = excluded.srpe, fitness = excluded.fitness, fatigue = excluded.fatigue, stress = excluded.stress,
            stress_components = excluded.stress_components, recovery = excluded.recovery,
            recovery_confidence = excluded.recovery_confidence, recovery_components = excluded.recovery_components,
            sessions = excluded.sessions, computed_at = now();
      rows_written := rows_written + 1;
    end if;
    d := d + 1;
  end loop;
  return rows_written;
end $$;

revoke all on function compute_daily_scores(text, date, date) from public, anon, authenticated;

-- Recreate the recompute-enqueue UPDATE trigger (20260902010000) with
-- felt_stress in the transition list.
DROP TRIGGER IF EXISTS auto_enqueue_daily_score_on_update ON training_logs;
CREATE TRIGGER auto_enqueue_daily_score_on_update
    AFTER UPDATE ON training_logs
    FOR EACH ROW
    WHEN (
        NEW.user_id IS NOT NULL
        AND (
            (OLD.rpe_extracted_at IS NULL AND NEW.rpe_extracted_at IS NOT NULL)
            OR OLD.felt_rpe IS DISTINCT FROM NEW.felt_rpe
            OR OLD.felt_stress IS DISTINCT FROM NEW.felt_stress
            OR OLD.workout_date IS DISTINCT FROM NEW.workout_date
            OR OLD.workout_type IS DISTINCT FROM NEW.workout_type
            OR OLD.workout_distance_miles IS DISTINCT FROM NEW.workout_distance_miles
            OR OLD.workout_duration_minutes IS DISTINCT FROM NEW.workout_duration_minutes
            OR OLD.stats_excluded IS DISTINCT FROM NEW.stats_excluded
            OR OLD.superseded_at IS DISTINCT FROM NEW.superseded_at
            OR OLD.duplicate_of IS DISTINCT FROM NEW.duplicate_of
            OR OLD.race_result IS DISTINCT FROM NEW.race_result
        )
    )
    EXECUTE FUNCTION fn_enqueue_daily_score_recompute();

COMMIT;

-- ============================================================================
-- Verification (run after applying):
--
-- 1. SELECT count(*) FROM information_schema.columns
--     WHERE table_name='training_logs' AND column_name='felt_stress';  -- 1
-- 2. SELECT compute_daily_scores('<athlete>', current_date - 3, null);
--    then check daily_scores has score_version='1.2' rows for those days
--    with a 'stress' element in recovery_components.
-- 3. UPDATE a training_logs row's felt_stress; the recompute queue gets a
--    row within the same transaction.
-- ============================================================================
