/**
 * Weather fetcher — reads from weather_cache, falls back to Open-Meteo.
 *
 * URLs match RunningLog/WeatherService.swift (forecast line 189,
 * archive line 237). No API key required. Responses are cached per
 * (lat_key, lon_key, hour_key) indefinitely.
 */

const FORECAST_URL = "https://api.open-meteo.com/v1/forecast";
const ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive";
const HOURLY_FIELDS =
  "temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m,dew_point_2m";

export interface WeatherObservation {
  temperature_f: number | null;
  dew_point_f: number | null;
  humidity: number | null;
  wind_speed_mph: number | null;
  weather_code: number | null;
  hour_iso: string;
}

export interface FetchWeatherArgs {
  lat: number;
  lon: number;
  timestamp: Date;
  kind: "forecast" | "historical";
}

function latKey(lat: number): number { return Math.round(lat * 100); }
function lonKey(lon: number): number { return Math.round(lon * 100); }
function hourKey(ts: Date): number { return Math.floor(ts.getTime() / 1000 / 3600); }

// deno-lint-ignore no-explicit-any
export async function fetchWeather(supabase: any, args: FetchWeatherArgs): Promise<WeatherObservation | null> {
  const lk = latKey(args.lat);
  const nk = lonKey(args.lon);
  const hk = hourKey(args.timestamp);

  // ── Cache hit? ──────────────────────────────────────────
  const { data: cached } = await supabase
    .from("weather_cache")
    .select("temperature_f, dew_point_f, humidity, wind_speed_mph, weather_code")
    .eq("lat_key", lk)
    .eq("lon_key", nk)
    .eq("hour_key", hk)
    .maybeSingle();
  if (cached) {
    return {
      temperature_f: cached.temperature_f,
      dew_point_f: cached.dew_point_f,
      humidity: cached.humidity,
      wind_speed_mph: cached.wind_speed_mph,
      weather_code: cached.weather_code,
      hour_iso: new Date(hk * 3600 * 1000).toISOString(),
    };
  }

  // ── Upstream fetch ──────────────────────────────────────
  const dateStr = args.timestamp.toISOString().slice(0, 10); // YYYY-MM-DD
  const base = args.kind === "historical" ? ARCHIVE_URL : FORECAST_URL;
  const url = `${base}?latitude=${args.lat}&longitude=${args.lon}` +
    `&start_date=${dateStr}&end_date=${dateStr}` +
    `&hourly=${HOURLY_FIELDS}` +
    `&temperature_unit=fahrenheit&windspeed_unit=mph&timezone=UTC`;

  let payload: Record<string, unknown>;
  try {
    const res = await fetch(url);
    if (!res.ok) {
      console.warn(`[weather] Open-Meteo ${res.status} for ${url}`);
      return null;
    }
    payload = await res.json();
  } catch (err) {
    console.warn("[weather] fetch failed", err);
    return null;
  }

  const hourly = payload.hourly as Record<string, unknown> | undefined;
  const times = hourly?.time as string[] | undefined;
  if (!hourly || !times || times.length === 0) return null;

  // Find the index of the hour closest to the requested timestamp.
  const target = new Date(args.timestamp).getTime();
  let bestIdx = 0;
  let bestDelta = Number.MAX_SAFE_INTEGER;
  for (let i = 0; i < times.length; i++) {
    const delta = Math.abs(new Date(times[i]).getTime() - target);
    if (delta < bestDelta) {
      bestDelta = delta;
      bestIdx = i;
    }
  }

  const pick = (field: string): number | null => {
    const arr = hourly[field] as Array<number | null> | undefined;
    if (!arr) return null;
    const v = arr[bestIdx];
    return typeof v === "number" ? v : null;
  };

  const obs: WeatherObservation = {
    temperature_f: pick("temperature_2m"),
    dew_point_f: pick("dew_point_2m"),
    humidity: pick("relative_humidity_2m"),
    wind_speed_mph: pick("wind_speed_10m"),
    weather_code: pick("weather_code"),
    hour_iso: times[bestIdx],
  };

  // Write-through to cache. Fire-and-forget; cache write failures shouldn't
  // fail the caller.
  supabase
    .from("weather_cache")
    .upsert({
      lat_key: lk,
      lon_key: nk,
      hour_key: hk,
      temperature_f: obs.temperature_f,
      dew_point_f: obs.dew_point_f,
      humidity: obs.humidity != null ? Math.round(obs.humidity) : null,
      wind_speed_mph: obs.wind_speed_mph,
      weather_code: obs.weather_code != null ? Math.round(obs.weather_code) : null,
    })
    .then((r: { error?: unknown }) => {
      if (r.error) console.warn("[weather] cache upsert failed", r.error);
    });

  return obs;
}
