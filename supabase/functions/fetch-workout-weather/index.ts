/**
 * fetch-workout-weather — centralized Open-Meteo fetcher (no API key required).
 *
 * Returns the weather shape used by `scheduled_workouts.weather_forecast` and
 * `training_logs.weather_actual`, caching per (location × hour) in
 * `weather_cache`. Heat math (composite score, category, adjustment %) is
 * reconstructed deterministically via `buildWeatherJson` on read.
 *
 * Modes (POST body):
 *   { training_log_id } ............ actual conditions for ONE completed run,
 *                                    located from the run's OWN GPS (latlng
 *                                    stream) — the path strava-sync fires.
 *   { lat, lon, timestamp, kind } .. single-point fetch (iOS preview).
 *   { plan_id, kind:"forecast_week" } batch forecast for a plan's next 7 days.
 *   { workout_id, kind:"refresh_one" } re-forecast one scheduled workout.
 *   { kind:"backfill_actuals" } .... backfill weather_actual for recent runs.
 *
 * Location source: the run's GPS where available, else `athlete_settings`
 * (home_lat/home_lon). NOTE: repointed off the dead `user_profiles` ghost table
 * (resolved 2026-06-15) onto `athlete_settings`.
 *
 * Auth: user JWT or service role (strava-sync calls with the service role).
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { adjustPace, buildWeatherJson } from "../_shared/pace-heat-adjustment.ts";
import { corsHeaders } from "../_shared/cors.ts";

// deno-lint-ignore no-explicit-any
type SupabaseClientLike = SupabaseClient<any, any, any>;

interface WeatherCacheRow {
  temperature_f: number | null;
  dew_point_f: number | null;
  humidity: number | null;
  wind_speed_mph: number | null;
  weather_code: number | null;
  fetched_at: string;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function wmoToCondition(code: number): string {
  if (code <= 0) return "clear";
  if (code <= 2) return "partly_cloudy";
  if (code === 3) return "cloudy";
  if (code === 45 || code === 48) return "fog";
  if (code >= 51 && code <= 57) return "drizzle";
  if (code >= 61 && code <= 82) return "rain";
  if (code >= 71 && code <= 86) return "snow";
  if (code >= 95) return "thunderstorm";
  return "unknown";
}

// ── Open-Meteo ─────────────────────────────────────────────────

interface OpenMeteoHourly {
  time: string[];
  temperature_2m: number[];
  weather_code: number[];
  relative_humidity_2m: number[];
  wind_speed_10m: number[];
  dew_point_2m: number[];
}

async function fetchFromOpenMeteo(
  lat: number,
  lon: number,
  dateStr: string,
  kind: "forecast" | "actual",
): Promise<Record<string, unknown> | null> {
  // timezone=auto → the hourly arrays are indexed by LOCAL hour at the point.
  const baseUrl = kind === "actual"
    ? "https://archive-api.open-meteo.com/v1/archive"
    : "https://api.open-meteo.com/v1/forecast";
  const url = `${baseUrl}?latitude=${lat}&longitude=${lon}` +
    `&hourly=temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m,dew_point_2m` +
    `&start_date=${dateStr}&end_date=${dateStr}` +
    `&temperature_unit=fahrenheit&windspeed_unit=mph&timezone=auto`;
  try {
    const resp = await fetch(url, { signal: AbortSignal.timeout(10000) });
    if (!resp.ok) {
      console.warn(`[fetch-workout-weather] Open-Meteo ${resp.status}: ${await resp.text()}`);
      return null;
    }
    const data = await resp.json();
    return data?.hourly ? data : null;
  } catch (err) {
    console.warn("[fetch-workout-weather] Open-Meteo error:", err);
    return null;
  }
}

function extractHourData(hourly: OpenMeteoHourly, localHour: number) {
  if (!hourly.time || hourly.time.length === 0) return null;
  const idx = Math.max(0, Math.min(localHour, hourly.time.length - 1));
  const code = hourly.weather_code[idx];
  return {
    tempF: hourly.temperature_2m[idx],
    dewF: hourly.dew_point_2m[idx],
    humidity: hourly.relative_humidity_2m[idx],
    windMph: hourly.wind_speed_10m[idx],
    weatherCode: code,
    condition: wmoToCondition(code),
  };
}

// ── Cache ──────────────────────────────────────────────────────

async function getCached(
  supabase: SupabaseClientLike,
  latKey: number,
  lonKey: number,
  hourKey: number,
): Promise<Record<string, unknown> | null> {
  const { data: raw } = await supabase
    .from("weather_cache")
    .select("temperature_f, dew_point_f, humidity, wind_speed_mph, weather_code, fetched_at")
    .eq("lat_key", latKey).eq("lon_key", lonKey).eq("hour_key", hourKey)
    .maybeSingle();
  const data = raw as WeatherCacheRow | null;
  if (!data || data.temperature_f == null || data.dew_point_f == null) return null;
  return buildWeatherJson(
    data.temperature_f, data.dew_point_f, data.humidity, data.wind_speed_mph,
    wmoToCondition(data.weather_code ?? 0), data.fetched_at, data.weather_code,
  );
}

async function setCache(
  supabase: SupabaseClientLike,
  latKey: number,
  lonKey: number,
  hourKey: number,
  h: { tempF: number; dewF: number; humidity: number | null; windMph: number | null; weatherCode: number },
): Promise<void> {
  await supabase.from("weather_cache").upsert({
    lat_key: latKey, lon_key: lonKey, hour_key: hourKey,
    temperature_f: h.tempF, dew_point_f: h.dewF,
    humidity: h.humidity != null ? Math.round(h.humidity) : null,
    wind_speed_mph: h.windMph, weather_code: h.weatherCode,
    fetched_at: new Date().toISOString(),
  }, { onConflict: "lat_key,lon_key,hour_key" });
}

function preferredHour(pref: string | null | undefined): number {
  switch (pref) {
    case "morning": return 6;
    case "afternoon": return 17;
    case "evening": return 19;
    default: return 7;
  }
}

/** Resolve a weather slot from a local date string + local hour. */
async function weatherForLocal(
  supabase: SupabaseClientLike,
  lat: number,
  lon: number,
  dateStr: string,
  localHour: number,
  kind: "forecast" | "actual",
): Promise<Record<string, unknown> | null> {
  const latKey = Math.round(lat * 100);
  const lonKey = Math.round(lon * 100);
  // Hour bucket keyed on the local wall-clock slot (stable across calls).
  const hourBucket = Math.floor(
    new Date(`${dateStr}T${String(localHour).padStart(2, "0")}:00:00Z`).getTime() / 3600000,
  );
  const cached = await getCached(supabase, latKey, lonKey, hourBucket);
  if (cached) return cached;
  const data = await fetchFromOpenMeteo(lat, lon, dateStr, kind);
  if (!data) return null;
  const h = extractHourData(data.hourly as OpenMeteoHourly, localHour);
  if (!h) return null;
  await setCache(supabase, latKey, lonKey, hourBucket, h);
  return buildWeatherJson(
    h.tempF, h.dewF, h.humidity, h.windMph, h.condition, new Date().toISOString(), h.weatherCode,
  );
}

/** Pull [lat, lon] from a run's stored GPS (first latlng sample). */
function startLatLng(externalStreams: unknown): [number, number] | null {
  const streams = (externalStreams as { streams?: { latlng?: unknown } } | null)?.streams;
  const ll = streams?.latlng;
  if (Array.isArray(ll) && Array.isArray(ll[0]) && (ll[0] as unknown[]).length === 2) {
    const [la, lo] = ll[0] as number[];
    if (Number.isFinite(la) && Number.isFinite(lo)) return [la, lo];
  }
  return null;
}

/**
 * Stamp per-lap heat columns on running_workout_laps for a workout, so the iOS
 * HEAT-ADJ toggle (which reads temp_f / dew_point_f / heat_adjusted_pace_sec_per_mile)
 * lights up. Heat-adjusted pace is rep-length scaled per lap: short interval
 * reps get half the penalty, continuous bouts the full amount.
 */
async function applyHeatToLaps(
  supabase: SupabaseClientLike,
  workoutId: string,
  tempF: number,
  dewF: number,
): Promise<void> {
  const { data: laps } = await supabase
    .from("running_workout_laps")
    .select("id, distance_meters, avg_pace_sec_per_mile, is_rest")
    .eq("workout_id", workoutId);
  if (!laps || laps.length === 0) return;

  const typedLaps = laps as Array<{ id: string | number; distance_meters: number | null; avg_pace_sec_per_mile: number | null; is_rest: boolean | null }>;

  // Rep-length scaling is earned by standing still between bouts, not by a lap
  // happening to be short. The mile splits of a continuous run are ONE bout
  // carved up: scaling each of them lands them mid-ramp at 0.67× and silently
  // cuts the run's adjustment by a third. Decide once, per workout.
  const isIntervalGeometry = typedLaps.some((l) => l.is_rest === true);

  // Threshold pace for intensity scaling of the CREDIT. Absent → the engine
  // falls back to the chart as published, which is the conservative direction.
  const thresholdPace = await thresholdPaceForWorkout(supabase, workoutId);

  for (const lap of typedLaps) {
    const pace = Number(lap.avg_pace_sec_per_mile);
    const distMi = Number(lap.distance_meters) / 1609.34;
    const runnable = lap.is_rest !== true && Number.isFinite(pace) && pace > 0;
    const a = adjustPace(
      runnable ? pace : 600,
      tempF,
      dewF,
      isIntervalGeometry && Number.isFinite(distMi) ? distMi : null,
      thresholdPace,
    );
    const heatAdj = runnable ? Math.round(a.neutralEquivalentPaceSeconds) : null;
    // Write ALL the heat columns, not just the pace. Leaving score/pct/category
    // to the SQL migration path is how the two writers drifted: that path had no
    // rep-length scaling, so short reps got the full penalty while laps this
    // function touched got the correct half. One writer now, one answer.
    // `heat_adjustment_pct` is the CREDIT fraction (after BOTH rep-length and
    // intensity scaling), so it always reconciles with
    // heat_adjusted_pace_sec_per_mile. It is NOT the prescriptive figure — a
    // target to run today uses effectiveAdjustmentPercent, which omits the
    // intensity scaling. See the header of _shared/pace-heat-adjustment.ts.
    await supabase
      .from("running_workout_laps")
      .update({
        temp_f: tempF,
        dew_point_f: dewF,
        heat_adjusted_pace_sec_per_mile: heatAdj,
        heat_composite_score: a.compositeScore,
        heat_category: a.heatCategory,
        heat_adjustment_pct: runnable ? a.creditAdjustmentPercent : null,
        heat_intensity_factor: runnable ? a.intensityFactor : null,
      })
      .eq("id", lap.id);
  }
}

/** The athlete's LT pace for this workout, for intensity scaling of the heat
 *  credit. Prefers the `threshold` zone (written by paces.ts's
 *  oneHourPaceSecPerMile); older blobs predate that key, so fall back to `hm`.
 *  HM is slower than LT for every runner whose half takes under an hour and
 *  much slower for everyone else, which makes the ratio lower and the discount
 *  smaller — the fallback errs toward the chart as published rather than
 *  inventing a discount on an athlete we can't classify confidently. */
async function thresholdPaceForWorkout(
  supabase: SupabaseClientLike,
  workoutId: string,
): Promise<number | null> {
  const { data: log } = await supabase
    .from("training_logs")
    .select("user_id")
    .eq("id", workoutId)
    .maybeSingle();
  const userId = (log as { user_id?: string } | null)?.user_id;
  if (!userId) return null;

  const { data: state } = await supabase
    .from("athlete_state")
    .select("pace_zones")
    .eq("user_id", userId)
    .maybeSingle();
  const zones = (state as { pace_zones?: Record<string, unknown> } | null)?.pace_zones;
  if (!zones) return null;

  for (const key of ["threshold", "hm"]) {
    const v = Number(zones[key]);
    if (Number.isFinite(v) && v > 0) return v;
  }
  return null;
}

/** Local date (YYYY-MM-DD) + local hour from a run's metadata. Strava's
 *  start_date_local is wall-clock time (the trailing Z is a known quirk). */
function localDateHour(
  meta: Record<string, unknown> | null,
  workoutDate: string | null,
): { dateStr: string; hour: number } | null {
  const local = (meta?.start_date_local as string | undefined) ?? null;
  const src = local ?? workoutDate;
  if (!src) return null;
  const dateStr = src.slice(0, 10);
  const hh = src.slice(11, 13);
  const hour = /^\d\d$/.test(hh) ? parseInt(hh, 10) : 7;
  return { dateStr, hour };
}

// ── Handler ────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  const bodyUserId = typeof body.user_id === "string" ? body.user_id : undefined;
  const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
  if ("response" in auth) return auth.response;
  const { userId, isServiceRole } = auth;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    // ── Mode: actual conditions for ONE completed run (GPS-located) ──
    if (typeof body.training_log_id === "string") {
      const { data: row } = await supabase
        .from("training_logs")
        .select("id, user_id, workout_date, external_streams, weather_actual")
        .eq("id", body.training_log_id)
        .maybeSingle();
      if (!row) return json({ error: "Not found" }, 404);
      if (!isServiceRole && (row as { user_id?: string }).user_id !== userId) {
        return json({ error: "Not found" }, 404);
      }
      if (row.weather_actual && body.force !== true) {
        return json({ weather: row.weather_actual, cached: true }, 200);
      }

      const meta = (row.external_streams as { meta?: Record<string, unknown> } | null)?.meta ?? null;
      let loc = startLatLng(row.external_streams);
      if (!loc) {
        const { data: settings } = await supabase
          .from("athlete_settings")
          .select("home_lat, home_lon")
          .eq("user_id", (row as { user_id?: string }).user_id ?? userId)
          .maybeSingle();
        if (settings?.home_lat != null && settings?.home_lon != null) {
          loc = [settings.home_lat, settings.home_lon];
        }
      }
      if (!loc) return json({ weather: null, error: "no location for this run" }, 200);

      const dh = localDateHour(meta, row.workout_date as string | null);
      if (!dh) return json({ weather: null, error: "no workout date" }, 200);

      const weather = await weatherForLocal(supabase, loc[0], loc[1], dh.dateStr, dh.hour, "actual");
      if (!weather) return json({ weather: null, error: "Open-Meteo unavailable" }, 200);

      await supabase.from("training_logs").update({ weather_actual: weather }).eq("id", row.id);
      // Stamp per-lap heat columns so the iOS HEAT-ADJ toggle works.
      await applyHeatToLaps(supabase, String(row.id), Number(weather.temp_f), Number(weather.dew_point_f));
      return json({ weather, cached: false }, 200);
    }

    // ── Mode: single point fetch (iOS preview) ──
    if (body.lat != null && body.lon != null && body.timestamp) {
      const lat = Number(body.lat), lon = Number(body.lon);
      const kind = body.kind === "actual" ? "actual" : "forecast";
      const tsStr = String(body.timestamp);
      const dateStr = tsStr.slice(0, 10);
      const hour = new Date(tsStr).getUTCHours();
      const weather = await weatherForLocal(supabase, lat, lon, dateStr, hour, kind);
      return json({ weather, cached: false }, 200);
    }

    // ── Mode: batch forecast for a plan's next 7 days ──
    if (body.plan_id && body.kind === "forecast_week") {
      const { data: settings } = await supabase
        .from("athlete_settings")
        .select("home_lat, home_lon, preferred_run_time")
        .eq("user_id", userId)
        .maybeSingle();
      const lat = settings?.home_lat ?? (body.lat as number | undefined);
      const lon = settings?.home_lon ?? (body.lon as number | undefined);
      if (lat == null || lon == null) {
        return json({ error: "No location. Set athlete_settings home_lat/home_lon or pass lat/lon." }, 400);
      }
      const profileHour = preferredHour(settings?.preferred_run_time);
      const today = new Date();
      const weekEnd = new Date(today);
      weekEnd.setDate(weekEnd.getDate() + 7);
      const { data: workouts } = await supabase
        .from("scheduled_workouts")
        .select("id, date, workout_type, scheduled_hour")
        .eq("plan_id", body.plan_id)
        .gte("date", today.toISOString().split("T")[0])
        .lte("date", weekEnd.toISOString().split("T")[0])
        .neq("workout_type", "rest");
      if (!workouts || workouts.length === 0) return json({ updated: 0 }, 200);

      const resolveHour = (w: { scheduled_hour?: number | null }) =>
        typeof w.scheduled_hour === "number" ? w.scheduled_hour : profileHour;
      let updated = 0;
      for (const w of workouts as Array<{ id: string; date: string; scheduled_hour?: number | null }>) {
        const weather = await weatherForLocal(supabase, lat, lon, w.date, resolveHour(w), "forecast");
        if (weather) {
          await supabase.from("scheduled_workouts").update({ weather_forecast: weather }).eq("id", w.id);
          updated++;
        }
      }
      return json({ updated }, 200);
    }

    // ── Mode: refresh one scheduled workout ──
    if (body.workout_id && body.kind === "refresh_one") {
      let lat = body.lat as number | null | undefined;
      let lon = body.lon as number | null | undefined;
      let prefRun: string | null | undefined;
      if (lat == null || lon == null) {
        const { data: settings } = await supabase
          .from("athlete_settings").select("home_lat, home_lon, preferred_run_time")
          .eq("user_id", userId).maybeSingle();
        lat = lat ?? settings?.home_lat;
        lon = lon ?? settings?.home_lon;
        prefRun = settings?.preferred_run_time;
      }
      if (lat == null || lon == null) return json({ error: "No location available" }, 400);
      const { data: w } = await supabase
        .from("scheduled_workouts").select("id, date, scheduled_hour")
        .eq("id", body.workout_id).maybeSingle();
      if (!w) return json({ error: "Workout not found" }, 404);
      const hour = typeof w.scheduled_hour === "number" ? w.scheduled_hour : preferredHour(prefRun);
      const weather = await weatherForLocal(supabase, lat, lon, w.date, hour, "forecast");
      if (!weather) return json({ weather: null, error: "Forecast unavailable" }, 200);
      await supabase.from("scheduled_workouts").update({ weather_forecast: weather }).eq("id", body.workout_id);
      return json({ weather }, 200);
    }

    // ── Mode: backfill actuals for recent runs (uses each run's own GPS) ──
    if (body.kind === "backfill_actuals") {
      const uid = bodyUserId ?? userId;
      const days = Number(body.days ?? 90);
      const cutoff = new Date();
      cutoff.setDate(cutoff.getDate() - days);
      const { data: logs } = await supabase
        .from("training_logs")
        .select("id, workout_date, external_streams")
        .eq("user_id", uid)
        .gte("workout_date", cutoff.toISOString())
        .is("weather_actual", null)
        .not("workout_date", "is", null)
        .gt("workout_distance_miles", 0)
        .order("workout_date", { ascending: false })
        .limit(200);
      if (!logs || logs.length === 0) return json({ updated: 0 }, 200);

      const { data: settings } = await supabase
        .from("athlete_settings").select("home_lat, home_lon").eq("user_id", uid).maybeSingle();
      let updated = 0;
      for (const log of logs as Array<{ id: string; workout_date: string; external_streams: unknown }>) {
        const meta = (log.external_streams as { meta?: Record<string, unknown> } | null)?.meta ?? null;
        let loc = startLatLng(log.external_streams);
        if (!loc && settings?.home_lat != null && settings?.home_lon != null) {
          loc = [settings.home_lat, settings.home_lon];
        }
        if (!loc) continue;
        const dh = localDateHour(meta, log.workout_date);
        if (!dh) continue;
        const weather = await weatherForLocal(supabase, loc[0], loc[1], dh.dateStr, dh.hour, "actual");
        if (weather) {
          await supabase.from("training_logs").update({ weather_actual: weather }).eq("id", log.id);
          await applyHeatToLaps(supabase, String(log.id), Number(weather.temp_f), Number(weather.dew_point_f));
          updated++;
        }
        if (updated % 10 === 0) await new Promise((r) => setTimeout(r, 400));
      }
      return json({ updated, total: logs.length }, 200);
    }

    return json({
      error: "Invalid request. Provide { training_log_id } | { lat, lon, timestamp, kind } | { plan_id, kind:'forecast_week' } | { workout_id, kind:'refresh_one' } | { kind:'backfill_actuals' }",
    }, 400);
  } catch (error) {
    console.error("[fetch-workout-weather] error:", error);
    return json({ error: String(error) }, 500);
  }
});
