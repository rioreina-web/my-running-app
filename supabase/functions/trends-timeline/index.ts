/**
 * trends-timeline — read-only endpoint backing the iOS Trends tab.
 *
 * Returns the unified weekly timeline (mileage, intensity, key-session
 * pace, mood, niggles) for the signed-in user. NO LLM, NO writes — so it
 * does not trip the eval-coverage CI gate (that fires only on
 * `_shared/prompts/` changes). Pure week math lives in `timeline.ts`.
 *
 * Auth: user-JWT or service-role (dual-mode). All reads are filtered by
 * the resolved `user_id`, mirroring `post-run-analysis`.
 *
 * Request:  POST { user_id?, weeks? }   weeks ∈ [4, 26], default 26.
 * Response: { weeks: TrendsWeekOut[], generated_at }
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import {
  buildDailyTimeline,
  analyticsRunLogs,
  buildTrendsTimeline,
  flaggedRuns,
  trimmedRuns,
  type TimelineFeature,
  type TimelineLog,
  type TimelineMention,
} from "./timeline.ts";
import {
  buildKeySessions,
  buildQualityVolume,
  type KeySessionFeature,
  type KeySessionLap,
} from "./keySessions.ts";
import type { PaceZones } from "../_shared/workoutSegmentation.ts";
import { buildFastSegments, type FSLapRow, type FSStream, type FSWeather } from "./fastSegments.ts";
import {
  buildPaceBands,
  type FitnessSnapshotRow,
  type PaceBandLap,
} from "./paceBands.ts";
import { buildBandLaps } from "./bandLaps.ts";
import type { ZoneTable } from "../_shared/quality-volume.ts";
import { fetchQualityLaps } from "../_shared/qualityLaps.ts";

const LOG_COLS_BASE =
  "id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, mood, source, pace_segments";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const MAX_WEEKS = 26;
const MIN_WEEKS = 4;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const bodyUserId = body?.user_id as string | undefined;

    const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
    if ("response" in auth) return auth.response;
    const { userId } = auth;

    const weeks = clampWeeks(body?.weeks);

    // Lower bound for the SQL window: a little wider than `weeks` to be
    // safe against partial-week edges. (weeks + 1) Mondays back.
    const sinceMs = Date.now() - (weeks + 1) * 7 * 24 * 60 * 60 * 1000;
    const since = new Date(sinceMs).toISOString().split("T")[0];

    // 1) Running + voice logs in the window. Prefer selecting stats_excluded
    //    (athlete trim/restore decision); fall back gracefully if the column
    //    isn't migrated yet so the endpoint never hard-fails on it.
    const selectLogs = (cols: string) =>
      supabase
        .from("training_logs")
        .select(cols)
        .eq("user_id", userId)
        .gte("workout_date", since)
        .order("workout_date", { ascending: true });

    const primary = await selectLogs(`${LOG_COLS_BASE}, stats_excluded`);
    let logs: TimelineLog[];
    if (primary.error) {
      const fallback = await selectLogs(LOG_COLS_BASE);
      if (fallback.error) throw fallback.error;
      logs = (fallback.data ?? []) as unknown as TimelineLog[];
    } else {
      logs = (primary.data ?? []) as unknown as TimelineLog[];
    }

    // 2) workout_features for those logs (intensity + structure). Skipped when
    //    no logs. `workout_structure` feeds the Section-A quality-session
    //    labels ("5K 5×1km · 6.0 mi"); intensity still drives the weekly
    //    key-pace classification in timeline.ts.
    let features: TimelineFeature[] = [];
    const keyFeaturesById = new Map<string, KeySessionFeature>();
    const logIds = logs.map((l) => l.id);
    if (logIds.length > 0) {
      const featRes = await supabase
        .from("workout_features")
        .select("training_log_id, intensity_score, total_duration_seconds, workout_structure, workout_type")
        .in("training_log_id", logIds);
      // Features are an optimization — a failure here degrades to the
      // workout_type fallback rather than failing the whole request.
      if (!featRes.error) {
        const rows = (featRes.data ?? []) as Array<
          TimelineFeature & {
            workout_structure?: string | null;
            workout_type?: string | null;
          }
        >;
        features = rows.map((r) => ({
          training_log_id: r.training_log_id,
          intensity_score: r.intensity_score,
          total_duration_seconds: r.total_duration_seconds,
        }));
        for (const r of rows) {
          keyFeaturesById.set(r.training_log_id, {
            training_log_id: r.training_log_id,
            workout_structure: r.workout_structure ?? null,
            // Admits long runs as key sessions — they carry no MP-or-faster
            // work, so without this label they never appear at all.
            workout_type: r.workout_type ?? null,
          });
        }
      }
    }

    // 3) Niggles in the window.
    const mentionsRes = await supabase
      .from("body_mentions")
      .select("body_area, side, verbatim_quote, severity_hint, mentioned_at")
      .eq("user_id", userId)
      .gte("mentioned_at", since)
      .order("mentioned_at", { ascending: true });

    if (mentionsRes.error) throw mentionsRes.error;
    const mentions = (mentionsRes.data ?? []) as TimelineMention[];

    // The athlete's own zone table is what makes "quality" meaningful — MP is
    // the boundary, and MP is personal. Fetched once and shared by the weekly
    // quality-volume count and the key-session classifier below.
    const zones = await fetchPaceZones(userId);

    // Laps are fetched BEFORE the timeline because quality volume needs them:
    // per-mile splits blur a rep session (a mile holding a 5:10 rep and a 9:00
    // float averages ~6:30 → slower than MP → booked as zero quality). Laps see
    // the rep. On real data that's the difference between 29 and 58 quality
    // miles over 90 days. Reused by the key-session classifier below.
    // Laps resolved once from the best source — native/derived, then the
    // athlete's fix-reps correction where present (see `fetchQualityLaps`).
    const lapsByWorkout = await fetchQualityLaps(supabase, userId, logIds);

    // Quality sessions FIRST — the weekly key pace needs their work-bout (rep)
    // pace, and Sections A/B render from them too. Additive: a failure here
    // degrades to whole-workout pace + empty quality surfaces, never a 500.
    const keyLogs = logs.map((l) => ({
      id: l.id,
      workout_date: l.workout_date,
      workout_distance_miles: l.workout_distance_miles,
      workout_duration_minutes: l.workout_duration_minutes ?? null,
    }));
    let qualitySessions: ReturnType<typeof buildKeySessions> = [];
    let qualityVolume: ReturnType<typeof buildQualityVolume> = [];
    try {
      qualitySessions = buildKeySessions(keyLogs, lapsByWorkout, keyFeaturesById, zones);
      qualityVolume = buildQualityVolume(keyLogs, lapsByWorkout, zones, weeks);
    } catch (e) {
      console.error("[trends-timeline] quality surfaces skipped:", e);
    }
    // Rep pace per quality log — rest excluded — so the weekly key pace shows
    // the 5:10 reps, not the 6:20 whole-workout blend.
    const keyWorkPaceByLog = new Map<string, number>(
      qualitySessions
        .filter((s) => s.kind === "quality" && s.work_pace_sec > 0)
        .map((s) => [s.log_id, s.work_pace_sec]),
    );

    const timelineInput = {
      logs,
      features,
      mentions,
      mpSecPerMile: zones.mp ?? null,
      lapsByWorkout,
      keyWorkPaceByLog,
    };
    const timeline = buildTrendsTimeline(timelineInput, weeks);
    // Daily substrate for the v2 calendar (Month/Block scales). Same dedup +
    // quality + mood logic as the weekly rollup, so days can't drift from the
    // weeks they sum into.
    const days = buildDailyTimeline(timelineInput, weeks);
    const flagged = flaggedRuns(logs);
    const trimmed = trimmedRuns(logs);

    // Sleep + overnight biometrics onto the daily substrate (additive,
    // 2026-08-05): daily_biometrics (device data, written by vital-webhook)
    // and daily_checkins (the one-tap self-report). Feeds the recovery
    // ledger's Overnight + Sleep factors. Errors leave the days untouched —
    // supabase-js reports errors in-band, so a missing table (migration not
    // yet pushed) degrades to no decoration, never a 500. Only one source
    // ('garmin') exists today; if more arrive, last row per date wins.
    try {
      const [bio, checkins] = await Promise.all([
        supabase
          .from("daily_biometrics")
          .select("date, hrv_rmssd, resting_hr, sleep_total_min")
          .eq("user_id", userId)
          .gte("date", since),
        supabase
          .from("daily_checkins")
          .select("date, sleep_quality")
          .eq("user_id", userId)
          .gte("date", since),
      ]);
      const bioByDate = new Map<string, Record<string, unknown>>();
      for (const r of (bio.data ?? []) as Array<Record<string, unknown>>) {
        bioByDate.set(String(r.date).slice(0, 10), r);
      }
      const qualByDate = new Map<string, string>();
      for (const r of (checkins.data ?? []) as Array<Record<string, unknown>>) {
        if (typeof r.sleep_quality === "string") {
          qualByDate.set(String(r.date).slice(0, 10), r.sleep_quality);
        }
      }
      for (const d of days) {
        const b = bioByDate.get(d.date);
        if (b) {
          if (typeof b.hrv_rmssd === "number") d.hrv_rmssd = b.hrv_rmssd;
          if (typeof b.resting_hr === "number") d.resting_hr = b.resting_hr;
          if (typeof b.sleep_total_min === "number") d.sleep_total_min = b.sleep_total_min;
        }
        const q = qualByDate.get(d.date);
        if (q) d.sleep_quality = q;
      }
    } catch (e) {
      console.error("[trends-timeline] sleep/biometrics decoration skipped:", e);
    }

    // Per-session weather, fetched ONCE and shared by fast segments (which
    // needs temp + dew for its conditions adjustment) and pace bands (which
    // reports dew alongside a session, but never decides membership on it).
    // Both consumers require laps, so skip the round trip without them, and
    // swallow a failure — weather is additive to every surface that reads it.
    const weatherByLog = lapsByWorkout.size > 0
      ? await fetchWeatherByLog(userId, logIds).catch((e) => {
        console.error("[trends-timeline] weather skipped:", e);
        return new Map<string, FSWeather>();
      })
      : new Map<string, FSWeather>();

    // 5) Fast segments — the system-aware fast-work trend (volume vs. each
    //    system's own range, conditions-adjusted pace, mixed-session
    //    breakdown). Reuses the same laps + zones as Sections A/B, plus
    //    per-session weather for the heat/grade adjustment. Additive: a
    //    failure here never fails the timeline.
    let fastSegments: ReturnType<typeof buildFastSegments> | null = null;
    try {
      if (lapsByWorkout.size > 0) {
        const zoneTable: ZoneTable = {
          mp: zones.mp ?? undefined,
          hm: zones.hm ?? undefined,
          tenK: zones.tenK ?? undefined,
          fiveK: zones.fiveK ?? undefined,
          threeK: zones.threeK ?? undefined,
          mile: zones.mile ?? undefined,
          steady: zones.steady ?? undefined,
          moderate: zones.moderate ?? undefined,
          easy: zones.easy ?? undefined,
        };
        // NOTE: split-grade from per-second altitude streams is OFF in the
        // timeline path. Fetching every key workout's `external_streams` blob
        // (tens–hundreds of KB each, serially) stalled the whole Trends
        // response. The net-grade fallback (from lap elevation gain, with the
        // GPS-noise deadband) keeps the hills adjustment working cheaply. If we
        // want split-grade back, move it to a lazy per-session request, not the
        // list load.
        const streamsByWorkout = undefined;
        // Total running miles per day (doubles summed) → a session's whole-day
        // context, not just its own run.
        const milesByDate = new Map<string, number>();
        for (const l of logs) {
          // Honor the athlete's trim flag here too — a trimmed duplicate
          // (e.g. a voice memo double-logging a synced run) must not inflate
          // the "X mi day" context. The weekly chart already filters this.
          if ((l as { stats_excluded?: boolean | null }).stats_excluded === true) continue;
          const d = String(l.workout_date).slice(0, 10);
          const mi = l.workout_distance_miles ?? 0;
          if (mi > 0) milesByDate.set(d, (milesByDate.get(d) ?? 0) + mi);
        }
        fastSegments = buildFastSegments(
          logs.map((l) => ({
            id: l.id,
            workout_date: l.workout_date,
            workout_distance_miles: l.workout_distance_miles,
          })),
          lapsByWorkout as unknown as Map<string, FSLapRow[]>,
          keyFeaturesById as unknown as Map<string, { workout_structure?: string | null }>,
          weatherByLog,
          zoneTable,
          streamsByWorkout,
          milesByDate,
        );
      }
    } catch (e) {
      console.error("[trends-timeline] fast segments skipped:", e);
    }

    // 6) Pace bands — "am I doing the work at the pace I'm supposed to be
    //    doing it at?" One band at a time (HM / MP), membership decided on
    //    heat-adjusted lap pace against a weekly-median anchor that steps
    //    across the window. Reuses the same laps and weather as everything
    //    above; the only extra read is `fitness_snapshots`. Additive: a
    //    failure here never fails the timeline, and a missing anchor returns
    //    null so the surface hides itself rather than guessing a band.
    //
    //    `band_laps` rides alongside on the same reads: the same laps, the
    //    same weekly anchors, but shipped un-bucketed and with the full
    //    race-pace ladder, so the Signal Lab's threshold band can be
    //    re-anchored and re-widened on-device without a round trip. Sibling,
    //    not replacement — see the header note in `bandLaps.ts` for why the
    //    two payloads gate their session lists differently on purpose.
    let paceBands: ReturnType<typeof buildPaceBands> = null;
    let bandLaps: ReturnType<typeof buildBandLaps> = null;
    try {
      if (lapsByWorkout.size > 0) {
        const snapshots = await fetchFitnessSnapshots(userId, since);
        if (snapshots.length > 0) {
          const dewByLog = new Map<string, number>();
          for (const [id, w] of weatherByLog) dewByLog.set(id, w.dewPointF);
          // The SAME pipeline the weekly and daily builders use — running
          // only, the athlete's trim decision, then one row per physical
          // workout. Filtering on `stats_excluded` alone (as this did until
          // 2026-08-05) is not enough: a run that was both synced from Strava
          // and spoken about lands as two rows with identical timestamp,
          // distance and laps, neither trimmed, and every minute inside the
          // band got counted twice.
          const bandLogs = analyticsRunLogs(logs as unknown as TimelineLog[])
            .map((l) => ({
              id: l.id,
              workout_date: l.workout_date,
              workout_distance_miles: l.workout_distance_miles,
            }));
          const bandLapRows = lapsByWorkout as unknown as Map<string, PaceBandLap[]>;
          paceBands = buildPaceBands(bandLogs, bandLapRows, snapshots, dewByLog);
          bandLaps = buildBandLaps(bandLogs, bandLapRows, snapshots, dewByLog);
        }
      }
    } catch (e) {
      console.error("[trends-timeline] pace bands skipped:", e);
    }

    return new Response(
      JSON.stringify({
        weeks: timeline,
        days,
        flagged,
        trimmed,
        quality_sessions: qualitySessions,
        quality_volume: qualityVolume,
        fast_segments: fastSegments,
        pace_bands: paceBands,
        band_laps: bandLaps,
        generated_at: new Date().toISOString(),
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("[trends-timeline] error:", err);
    return new Response(
      JSON.stringify({ error: (err as Error).message ?? "Internal error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});

function clampWeeks(raw: unknown): number {
  const n = typeof raw === "number" ? Math.floor(raw) : MAX_WEEKS;
  if (Number.isNaN(n)) return MAX_WEEKS;
  return Math.min(MAX_WEEKS, Math.max(MIN_WEEKS, n));
}

/**
 * The athlete's pace zones from `athlete_state.pace_zones`. Mirrors
 * `compute-workout-features.fetchPaceZones` so Section A classifies bouts
 * against exactly the same zone table as load scoring. Returns an all-empty
 * object when missing — `segmentFromLaps` then degrades to easy (and
 * `buildKeySessions` emits nothing, since nothing classifies as work).
 */
async function fetchPaceZones(userId: string): Promise<PaceZones> {
  const { data } = await supabase
    .from("athlete_state")
    .select("pace_zones")
    .eq("user_id", userId)
    .maybeSingle();
  const z = (data?.pace_zones ?? {}) as Record<string, unknown>;
  const num = (v: unknown): number | undefined =>
    typeof v === "number" && v > 0 ? v : undefined;
  return {
    mile: num(z.mile),
    fiveK: num(z.fiveK),
    threeK: num(z.threeK),
    tenK: num(z.tenK),
    hm: num(z.hm) ?? num(z.hmp),
    mp: num(z.mp),
    steady: num(z.steady),
    moderate: num(z.moderate),
    easy: num(z.easy),
  };
}

/**
 * Per-session weather (temp + dew point) from `training_logs.weather_actual`,
 * keyed by log id. Drives the conditions (heat) adjustment on fast segments;
 * a missing or partial snapshot simply omits that session's adjustment.
 */
async function fetchWeatherByLog(
  userId: string,
  logIds: string[],
): Promise<Map<string, FSWeather>> {
  const out = new Map<string, FSWeather>();
  if (logIds.length === 0) return out;
  for (let i = 0; i < logIds.length; i += 200) {
    const chunk = logIds.slice(i, i + 200);
    const { data, error } = await supabase
      .from("training_logs")
      .select("id, weather_actual")
      .eq("user_id", userId)
      .in("id", chunk);
    if (error) continue; // additive — skip the chunk, don't fail
    for (const row of (data ?? []) as Array<Record<string, unknown>>) {
      const w = row.weather_actual as Record<string, unknown> | null;
      if (!w) continue;
      const t = w.temp_f, dp = w.dew_point_f;
      if (typeof t === "number" && typeof dp === "number") {
        out.set(String(row.id), { tempF: t, dewPointF: dp });
      }
    }
  }
  return out;
}

/**
 * The athlete's race-prediction snapshots, which anchor the pace bands.
 *
 * Reaches ~8 weeks further back than the session window on purpose: the
 * anchor is a weekly median and the junk filter is relative to the series
 * median, so both are steadier with more history behind them. A read failure
 * returns `[]` — pace bands then emit nothing rather than a guessed band.
 */
async function fetchFitnessSnapshots(
  userId: string,
  since: string,
): Promise<FitnessSnapshotRow[]> {
  const from = new Date(new Date(since + "T00:00:00Z").getTime() - 56 * 86400_000)
    .toISOString();
  const { data, error } = await supabase
    .from("fitness_snapshots")
    .select("created_at, predicted_half_seconds, predicted_marathon_seconds, confidence_tier")
    .eq("user_id", userId)
    .gte("created_at", from)
    .order("created_at", { ascending: true });
  if (error) {
    console.error("[trends-timeline] fitness_snapshots read failed:", error);
    return [];
  }
  return (data ?? []) as unknown as FitnessSnapshotRow[];
}

/**
 * Per-second altitude streams for the key workouts, from
 * `training_logs.external_streams` (`{ time, distance, altitude }`). Drives the
 * split (segmented) grade adjustment. Fetched only for workouts that have laps,
 * in small chunks (the blobs are large); a missing altitude array simply falls
 * back to net grade for that session.
 */
async function fetchStreamsByWorkout(
  userId: string,
  workoutIds: string[],
): Promise<Map<string, FSStream>> {
  const out = new Map<string, FSStream>();
  if (workoutIds.length === 0) return out;
  for (let i = 0; i < workoutIds.length; i += 50) {
    const chunk = workoutIds.slice(i, i + 50);
    const { data, error } = await supabase
      .from("training_logs")
      .select("id, external_streams")
      .eq("user_id", userId)
      .in("id", chunk);
    if (error) continue; // additive — skip, don't fail
    for (const row of (data ?? []) as Array<Record<string, unknown>>) {
      const es = row.external_streams as Record<string, unknown> | null;
      if (!es) continue;
      const time = es.time, distance = es.distance, altitude = es.altitude;
      if (
        Array.isArray(time) && Array.isArray(distance) && Array.isArray(altitude) &&
        altitude.length > 0
      ) {
        out.set(String(row.id), {
          time: time as number[],
          distance: distance as number[],
          altitude: altitude as number[],
        });
      }
    }
  }
  return out;
}
