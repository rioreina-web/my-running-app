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
import type { ZoneTable } from "../_shared/quality-volume.ts";

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
        .select("training_log_id, intensity_score, total_duration_seconds, workout_structure")
        .in("training_log_id", logIds);
      // Features are an optimization — a failure here degrades to the
      // workout_type fallback rather than failing the whole request.
      if (!featRes.error) {
        const rows = (featRes.data ?? []) as Array<
          TimelineFeature & { workout_structure?: string | null }
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
    const lapsByWorkout = await fetchLapsByWorkout(userId, logIds);

    const timeline = buildTrendsTimeline(
      { logs, features, mentions, mpSecPerMile: zones.mp ?? null, lapsByWorkout },
      weeks,
    );
    const flagged = flaggedRuns(logs);
    const trimmed = trimmedRuns(logs);

    // 4) Quality sessions (Section A of the redesigned Key Sessions chart).
    //    Per-session work-bout pace, zone-grouped, heat-adjusted. Requires
    //    rep-level laps + the athlete's pace zones; degrades to an empty array
    //    when either is missing (manual/HealthKit-only athletes see the
    //    empty-state, never a faked dot). Append-only: `key_pace_sec` on each
    //    week is retained until iOS fully migrates off it.
    let qualitySessions: ReturnType<typeof buildKeySessions> = [];
    let qualityVolume: ReturnType<typeof buildQualityVolume> = [];
    try {
      if (lapsByWorkout.size > 0) {
        const keyLogs = logs.map((l) => ({
          id: l.id,
          workout_date: l.workout_date,
          workout_distance_miles: l.workout_distance_miles,
        }));
        qualitySessions = buildKeySessions(keyLogs, lapsByWorkout, keyFeaturesById, zones);
        // Section B: weekly work-time per zone, over the same window.
        qualityVolume = buildQualityVolume(keyLogs, lapsByWorkout, zones, weeks);
      }
    } catch (e) {
      // Sections A/B are additive — never fail the whole timeline on them.
      console.error("[trends-timeline] quality surfaces skipped:", e);
    }

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
        const weatherByLog = await fetchWeatherByLog(userId, logIds);
        // Altitude streams for the key workouts → split (segmented) grade.
        const streamsByWorkout = await fetchStreamsByWorkout(userId, [...lapsByWorkout.keys()]);
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
        );
      }
    } catch (e) {
      console.error("[trends-timeline] fast segments skipped:", e);
    }

    return new Response(
      JSON.stringify({
        weeks: timeline,
        flagged,
        trimmed,
        quality_sessions: qualitySessions,
        quality_volume: qualityVolume,
        fast_segments: fastSegments,
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
 * Rep-level laps for a set of workout ids, grouped by `workout_id`. Selects
 * the segmentation columns plus the heat snapshot (adjusted pace + category)
 * that Section A carries alongside the raw pace. Chunked to keep the IN list
 * sane, matching `compute-workout-features.fetchLapsByWorkout`.
 */
async function fetchLapsByWorkout(
  userId: string,
  workoutIds: string[],
): Promise<Map<string, KeySessionLap[]>> {
  const byId = new Map<string, KeySessionLap[]>();
  if (workoutIds.length === 0) return byId;
  for (let i = 0; i < workoutIds.length; i += 200) {
    const chunk = workoutIds.slice(i, i + 200);
    const { data, error } = await supabase
      .from("running_workout_laps")
      .select(
        "workout_id, lap_index, is_rest, distance_meters, avg_pace_sec_per_mile, moving_time_seconds, elapsed_time_seconds, avg_heart_rate, max_heart_rate, total_elevation_gain, stream_start_index, stream_end_index, heat_adjusted_pace_sec_per_mile, heat_category",
      )
      .eq("user_id", userId)
      .in("workout_id", chunk)
      .order("lap_index", { ascending: true });
    if (error) continue; // additive surface — skip the chunk, don't fail
    for (const lap of (data ?? []) as Array<Record<string, unknown>>) {
      const wid = String(lap.workout_id);
      const arr = byId.get(wid) ?? [];
      arr.push(lap as unknown as KeySessionLap);
      byId.set(wid, arr);
    }
  }
  return byId;
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
