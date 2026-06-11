/**
 * Fetch Workout Weather
 *
 * Centralized Open-Meteo fetcher. Takes {lat, lon, timestamp, kind} and returns
 * the weather shape used by scheduled_workouts.weather_forecast and
 * training_logs.weather_actual.
 *
 * Caches per (location × hour) in weather_cache table.
 * Used by:
 *   - scheduled_workouts trigger (forecast for next 7 days on plan creation)
 *   - training_logs trigger (actual conditions at workout time)
 *   - (weekly-plan-review consumed this too — CUT 2026-06-10)
 *   - iOS drag-and-drop preview (forecast for target day)
 *
 * Also supports batch mode: {plan_id, kind: "forecast_week"} to populate
 * forecasts for all scheduled workouts in the next 7 days.
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { buildWeatherJson } from "../_shared/pace-heat-adjustment.ts";
import { corsHeaders } from "../_shared/cors.ts";

// Untyped clients (no generated Database type) resolve their schema generic to
// `never` under the current supabase-js typings, which makes every query row
// `never` and breaks `ReturnType<typeof createClient>` param matching. Use a
// loosened client alias so query results are typed by explicit row interfaces
// at the call site instead.
// deno-lint-ignore no-explicit-any
type SupabaseClientLike = SupabaseClient<any, any, any>;

// Row shape returned by the weather_cache read in getCached().
interface WeatherCacheRow {
  temperature_f: number | null;
  dew_point_f: number | null;
  humidity: number | null;
  wind_speed_mph: number | null;
  weather_code: number | null;
  fetched_at: string;
}

// WMO weather code → condition string (matches WeatherCondition in Swift)
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

// ── Open-Meteo API Calls ───────────────────────────────────────

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
  kind: "forecast" | "actual"
): Promise<Record<string, unknown> | null> {
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
      console.warn(`Open-Meteo ${resp.status}: ${await resp.text()}`);
      return null;
    }
    const data = await resp.json();
    return data?.hourly ? data : null;
  } catch (err) {
    console.warn("Open-Meteo fetch error:", err);
    return null;
  }
}

function extractHourData(
  hourly: OpenMeteoHourly,
  targetHour: number
): { tempF: number; dewF: number; humidity: number; windMph: number; weatherCode: number; condition: string } | null {
  if (!hourly.time || hourly.time.length === 0) return null;
  const idx = Math.min(targetHour, hourly.time.length - 1);
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

// ── Cache Layer ────────────────────────────────────────────────

// Cache schema (per 20260417400000_weather_cache.sql, deployed to prod):
//   PRIMARY KEY (lat_key, lon_key, hour_key)
//   raw observations: temperature_f, dew_point_f, humidity, wind_speed_mph, weather_code
// We reconstruct the rich weather JSON via buildWeatherJson on read since
// composite_score / heat_category / adjustment_pct are deterministic.
// Forecast vs actual share a slot; actuals overwrite stale forecasts after the run.

async function getCached(
  supabase: SupabaseClientLike,
  latKey: number,
  lonKey: number,
  hourKey: number,
): Promise<Record<string, unknown> | null> {
  const { data: raw } = await supabase
    .from("weather_cache")
    .select("temperature_f, dew_point_f, humidity, wind_speed_mph, weather_code, fetched_at")
    .eq("lat_key", latKey)
    .eq("lon_key", lonKey)
    .eq("hour_key", hourKey)
    .maybeSingle();
  const data = raw as WeatherCacheRow | null;
  if (!data || data.temperature_f == null || data.dew_point_f == null) return null;
  return buildWeatherJson(
    data.temperature_f,
    data.dew_point_f,
    data.humidity,
    data.wind_speed_mph,
    wmoToCondition(data.weather_code ?? 0),
    data.fetched_at,
    data.weather_code,
  );
}

async function setCache(
  supabase: SupabaseClientLike,
  latKey: number,
  lonKey: number,
  hourKey: number,
  hourData: { tempF: number; dewF: number; humidity: number | null; windMph: number | null; weatherCode: number },
): Promise<void> {
  await supabase.from("weather_cache").upsert(
    {
      lat_key: latKey,
      lon_key: lonKey,
      hour_key: hourKey,
      temperature_f: hourData.tempF,
      dew_point_f: hourData.dewF,
      humidity: hourData.humidity != null ? Math.round(hourData.humidity) : null,
      wind_speed_mph: hourData.windMph,
      weather_code: hourData.weatherCode,
      fetched_at: new Date().toISOString(),
    },
    { onConflict: "lat_key,lon_key,hour_key" }
  );
}

// ── Preferred hour from run-time preference ────────────────────

function preferredHour(pref: string | null): number {
  switch (pref) {
    case "morning": return 6;
    case "afternoon": return 17;
    case "evening": return 19;
    default: return 7; // default to morning
  }
}

// ── Main Handler ───────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── Mode 1: Single point fetch ─────────────────────────────
    if (body.lat != null && body.lon != null && body.timestamp) {
      const { lat, lon, timestamp, kind = "forecast" } = body;
      const ts = new Date(timestamp);
      const dateStr = ts.toISOString().split("T")[0];
      const hour = ts.getUTCHours();

      const latKey = Math.round(lat * 100);
      const lonKey = Math.round(lon * 100);
      const hourBucket = Math.floor(ts.getTime() / 3600000);

      // Check cache
      const cached = await getCached(supabase, latKey, lonKey, hourBucket);
      if (cached) {
        return new Response(
          JSON.stringify({ weather: cached, cached: true }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Fetch from Open-Meteo
      const data = await fetchFromOpenMeteo(lat, lon, dateStr, kind);
      if (!data) {
        return new Response(
          JSON.stringify({ weather: null, error: "Open-Meteo unavailable" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const hourData = extractHourData(data.hourly as OpenMeteoHourly, hour);
      if (!hourData) {
        return new Response(
          JSON.stringify({ weather: null, error: "No hourly data" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const weather = buildWeatherJson(
        hourData.tempF, hourData.dewF, hourData.humidity,
        hourData.windMph, hourData.condition, new Date().toISOString(), hourData.weatherCode
      );

      // Cache it
      await setCache(supabase, latKey, lonKey, hourBucket, hourData);

      return new Response(
        JSON.stringify({ weather, cached: false }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Mode 2: Batch forecast for a plan's next 7 days ────────
    if (body.plan_id && body.kind === "forecast_week") {
      const { plan_id, user_id } = body;
      const uid = user_id || (await getAuthenticatedUser(req));
      if (!uid) return unauthorizedResponse(corsHeaders);

      // Get user's home location
      const { data: profile } = await supabase
        .from("user_profiles")
        .select("home_lat, home_lon, preferred_run_time")
        .eq("user_id", uid)
        .maybeSingle();

      const lat = profile?.home_lat ?? body.lat;
      const lon = profile?.home_lon ?? body.lon;

      if (lat == null || lon == null) {
        return new Response(
          JSON.stringify({ error: "No location available. Set home_lat/home_lon in profile or pass lat/lon." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const profileHour = preferredHour(profile?.preferred_run_time);
      const today = new Date();
      const weekEnd = new Date(today);
      weekEnd.setDate(weekEnd.getDate() + 7);

      // Fetch scheduled workouts for next 7 days. We now select
      // `scheduled_hour` so each workout can pin its own hour — Saturday
      // LR at 6am vs. Tuesday tempo at 5pm get different forecasts even
      // though they share the same profile preference.
      const { data: workouts } = await supabase
        .from("scheduled_workouts")
        .select("id, date, workout_type, scheduled_hour")
        .eq("plan_id", plan_id)
        .gte("date", today.toISOString().split("T")[0])
        .lte("date", weekEnd.toISOString().split("T")[0])
        .neq("workout_type", "rest");

      if (!workouts || workouts.length === 0) {
        return new Response(
          JSON.stringify({ updated: 0 }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Resolve the local hour for one workout. Per-workout scheduled_hour
      // (0-23) wins; otherwise fall back to the athlete's profile
      // preference; otherwise the 7am default. We read the integer
      // directly — no UTC↔local conversion needed because Open-Meteo's
      // hourly array (with timezone=auto) is already local-time-indexed.
      const resolveHour = (w: { scheduled_hour?: number | null }): number => {
        if (typeof w.scheduled_hour === "number") return w.scheduled_hour;
        return profileHour;
      };

      // Fetch weather per (date, hour) so workouts on the same date with
      // different scheduled_hour values get distinct forecasts.
      const weatherByKey: Record<string, Record<string, unknown>> = {};
      const keyFor = (dateStr: string, hour: number) => `${dateStr}@${hour}`;

      const uniqueRequests = new Map<string, { dateStr: string; hour: number }>();
      for (const w of workouts as Array<{ id: string; date: string; scheduled_hour?: number | null }>) {
        const hour = resolveHour(w);
        uniqueRequests.set(keyFor(w.date, hour), { dateStr: w.date, hour });
      }

      for (const { dateStr, hour } of uniqueRequests.values()) {
        const ts = new Date(`${dateStr}T${String(hour).padStart(2, "0")}:00:00Z`);
        const latKey = Math.round(lat * 100);
        const lonKey = Math.round(lon * 100);
        const hourBucket = Math.floor(ts.getTime() / 3600000);

        let weather = await getCached(supabase, latKey, lonKey, hourBucket);
        if (!weather) {
          const data = await fetchFromOpenMeteo(lat, lon, dateStr, "forecast");
          if (data) {
            const hourData = extractHourData(data.hourly as OpenMeteoHourly, hour);
            if (hourData) {
              weather = buildWeatherJson(
                hourData.tempF, hourData.dewF, hourData.humidity,
                hourData.windMph, hourData.condition, new Date().toISOString(), hourData.weatherCode
              );
              await setCache(supabase, latKey, lonKey, hourBucket, hourData);
            }
          }
        }
        if (weather) weatherByKey[keyFor(dateStr, hour)] = weather;
      }

      // Update scheduled_workouts with forecast — match each workout to
      // the (date, resolved-hour) bucket we just fetched.
      let updated = 0;
      for (const w of workouts as Array<{ id: string; date: string; scheduled_hour?: number | null }>) {
        const hour = resolveHour(w);
        const weather = weatherByKey[keyFor(w.date, hour)];
        if (weather) {
          await supabase
            .from("scheduled_workouts")
            .update({ weather_forecast: weather })
            .eq("id", w.id);
          updated++;
        }
      }

      return new Response(
        JSON.stringify({ updated, buckets: uniqueRequests.size }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Mode 4: Refresh a single scheduled_workout ─────────────
    // Called by iOS after the athlete changes a workout's scheduled_hour.
    // Pulls the forecast for the new hour and writes it back.
    if (body.workout_id && body.kind === "refresh_one") {
      const { workout_id } = body;
      const uid = body.user_id || (await getAuthenticatedUser(req));
      if (!uid) return unauthorizedResponse(corsHeaders);

      // Resolve location. iOS sends a CoreLocation fix in body.lat/lon
      // when permission is granted; we only fall back to user_profiles
      // when body lacks coordinates. The user_profiles table doesn't
      // ship in every env yet, so guard the lookup behind a try/catch
      // and treat any failure as "no profile row" rather than 500ing.
      let lat: number | null | undefined = body.lat;
      let lon: number | null | undefined = body.lon;
      let profile: { home_lat?: number | null; home_lon?: number | null; preferred_run_time?: string | null } | null = null;
      if (lat == null || lon == null) {
        try {
          const { data } = await supabase
            .from("user_profiles")
            .select("home_lat, home_lon, preferred_run_time")
            .eq("user_id", uid)
            .maybeSingle();
          profile = data ?? null;
        } catch (_e) {
          profile = null;
        }
        lat = lat ?? profile?.home_lat;
        lon = lon ?? profile?.home_lon;
      }
      if (lat == null || lon == null) {
        return new Response(
          JSON.stringify({ error: "No location available" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data: w } = await supabase
        .from("scheduled_workouts")
        .select("id, date, scheduled_hour")
        .eq("id", workout_id)
        .maybeSingle();
      if (!w) {
        return new Response(
          JSON.stringify({ error: "Workout not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const hour = typeof w.scheduled_hour === "number"
        ? w.scheduled_hour
        : preferredHour(profile?.preferred_run_time ?? null);

      const ts = new Date(`${w.date}T${String(hour).padStart(2, "0")}:00:00Z`);
      const latKey = Math.round(lat * 100);
      const lonKey = Math.round(lon * 100);
      const hourBucket = Math.floor(ts.getTime() / 3600000);

      let weather = await getCached(supabase, latKey, lonKey, hourBucket);
      if (!weather) {
        const data = await fetchFromOpenMeteo(lat, lon, w.date, "forecast");
        if (data) {
          const hourData = extractHourData(data.hourly as OpenMeteoHourly, hour);
          if (hourData) {
            weather = buildWeatherJson(
              hourData.tempF, hourData.dewF, hourData.humidity,
              hourData.windMph, hourData.condition, new Date().toISOString()
            );
            await setCache(supabase, latKey, lonKey, hourBucket, hourData);
          }
        }
      }

      if (!weather) {
        return new Response(
          JSON.stringify({ weather: null, error: "Forecast unavailable" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      await supabase
        .from("scheduled_workouts")
        .update({ weather_forecast: weather })
        .eq("id", workout_id);

      return new Response(
        JSON.stringify({ weather }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Mode 3: Backfill actuals for a user's last N days ──────
    if (body.kind === "backfill_actuals") {
      const uid = body.user_id || (await getAuthenticatedUser(req));
      if (!uid) return unauthorizedResponse(corsHeaders);

      const days = body.days || 90;
      const { data: profile } = await supabase
        .from("user_profiles")
        .select("home_lat, home_lon, preferred_run_time")
        .eq("user_id", uid)
        .maybeSingle();

      const lat = profile?.home_lat ?? body.lat;
      const lon = profile?.home_lon ?? body.lon;
      if (lat == null || lon == null) {
        return new Response(
          JSON.stringify({ error: "No location available" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const runHour = preferredHour(profile?.preferred_run_time);
      const cutoff = new Date();
      cutoff.setDate(cutoff.getDate() - days);

      const { data: logs } = await supabase
        .from("training_logs")
        .select("id, workout_date")
        .eq("user_id", uid)
        .gte("workout_date", cutoff.toISOString())
        .is("weather_actual", null)
        .not("workout_date", "is", null)
        .gt("workout_distance_miles", 0)
        .order("workout_date", { ascending: false })
        .limit(200);

      if (!logs || logs.length === 0) {
        return new Response(
          JSON.stringify({ updated: 0 }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      let updated = 0;
      for (const log of logs) {
        const dateStr = log.workout_date.split("T")[0];
        const ts = new Date(`${dateStr}T${String(runHour).padStart(2, "0")}:00:00Z`);
        const latKey = Math.round(lat * 100);
        const lonKey = Math.round(lon * 100);
        const hourBucket = Math.floor(ts.getTime() / 3600000);

        let weather = await getCached(supabase, latKey, lonKey, hourBucket);
        if (!weather) {
          const data = await fetchFromOpenMeteo(lat, lon, dateStr, "actual");
          if (data) {
            const hourData = extractHourData(data.hourly as OpenMeteoHourly, runHour);
            if (hourData) {
              weather = buildWeatherJson(
                hourData.tempF, hourData.dewF, hourData.humidity,
                hourData.windMph, hourData.condition, new Date().toISOString(), hourData.weatherCode
              );
              await setCache(supabase, latKey, lonKey, hourBucket, hourData);
            }
          }
        }

        if (weather) {
          await supabase
            .from("training_logs")
            .update({ weather_actual: weather })
            .eq("id", log.id);
          updated++;
        }

        // Rate limit: Open-Meteo free tier is generous but be nice
        if (updated % 10 === 0) {
          await new Promise((r) => setTimeout(r, 500));
        }
      }

      return new Response(
        JSON.stringify({ updated, total: logs.length }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ error: "Invalid request. Provide {lat, lon, timestamp, kind} or {plan_id, kind: 'forecast_week'} or {kind: 'backfill_actuals'}" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("[fetch-workout-weather] Error:", error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
