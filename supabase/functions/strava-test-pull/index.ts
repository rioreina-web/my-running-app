/**
 * Strava Test Pull — one-off backfill of rich workout data for testing.
 *
 * Pulls recent running activities from Strava using a hardcoded personal access
 * token, fetches detailed splits + HR for each, and writes to training_logs.
 *
 * FOR DEVELOPMENT / TESTING ONLY. Multi-user Strava requires full OAuth.
 *
 * Call:  POST /functions/v1/strava-test-pull  { "limit": 30 }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";

// Client ID/Secret come from Supabase secrets. Per-user OAuth tokens
// live in `strava_credentials`. Strava rotates the refresh token on
// every refresh — persisted back on every rotation in persistCredentials.
const STRAVA_CLIENT_ID = Deno.env.get("STRAVA_CLIENT_ID") ?? "";
const STRAVA_CLIENT_SECRET = Deno.env.get("STRAVA_CLIENT_SECRET") ?? "";

interface StravaCreds {
  accessToken: string;
  refreshToken: string;
  expiresAt: Date | null;
  athleteId: number | null;
  scope: string | null;
}

interface StravaActivity {
  id: number;
  name: string;
  sport_type: string;
  type: string;
  distance: number;          // meters
  moving_time: number;       // seconds
  start_date: string;        // ISO
  start_date_local: string;
  average_heartrate?: number;
  max_heartrate?: number;
  average_speed?: number;    // m/s
  total_elevation_gain?: number;
  has_heartrate?: boolean;
}

interface StravaSplit {
  distance: number;          // meters
  elapsed_time: number;      // seconds
  moving_time: number;       // seconds
  average_speed: number;     // m/s
  average_heartrate?: number;
  split: number;             // 1-indexed
}

interface StravaDetailed extends StravaActivity {
  splits_standard?: StravaSplit[]; // imperial miles
  splits_metric?: StravaSplit[];
}

// deno-lint-ignore no-explicit-any
async function loadCredentials(supabase: any, userId: string): Promise<StravaCreds> {
  const { data } = await supabase
    .from("strava_credentials")
    .select("access_token, refresh_token, expires_at, strava_athlete_id, scope")
    .eq("user_id", userId)
    .maybeSingle();
  if (!data) {
    throw new Error(
      `No strava_credentials row for user ${userId}. Run the OAuth exchange first: POST { "action": "exchange", "code": "<auth_code>" }.`
    );
  }
  return {
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresAt: data.expires_at ? new Date(data.expires_at) : null,
    athleteId: data.strava_athlete_id ?? null,
    scope: data.scope ?? null,
  };
}

// deno-lint-ignore no-explicit-any
async function persistCredentials(supabase: any, userId: string, creds: StravaCreds): Promise<void> {
  const { error } = await supabase
    .from("strava_credentials")
    .upsert({
      user_id: userId,
      access_token: creds.accessToken,
      refresh_token: creds.refreshToken,
      expires_at: creds.expiresAt?.toISOString() ?? null,
      strava_athlete_id: creds.athleteId,
      scope: creds.scope,
      last_refreshed_at: new Date().toISOString(),
    }, { onConflict: "user_id" });
  if (error) {
    console.error("[strava-test-pull] persistCredentials failed:", error.message);
  }
}

// deno-lint-ignore no-explicit-any
async function refreshTokens(creds: StravaCreds, supabase: any, userId: string): Promise<void> {
  const refreshRes = await fetch("https://www.strava.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: STRAVA_CLIENT_ID,
      client_secret: STRAVA_CLIENT_SECRET,
      grant_type: "refresh_token",
      refresh_token: creds.refreshToken,
    }),
  });
  if (!refreshRes.ok) {
    const text = await refreshRes.text();
    throw new Error(`Strava refresh failed ${refreshRes.status}: ${text}`);
  }
  const refreshed = await refreshRes.json();
  // Strava rotates refresh_token on every successful refresh — must
  // persist the new one or the next cold start breaks.
  creds.accessToken = refreshed.access_token;
  creds.refreshToken = refreshed.refresh_token ?? creds.refreshToken;
  creds.expiresAt = refreshed.expires_at ? new Date(refreshed.expires_at * 1000) : null;
  creds.athleteId = refreshed.athlete?.id ?? creds.athleteId;
  creds.scope = refreshed.scope ?? creds.scope;
  await persistCredentials(supabase, userId, creds);
}

// deno-lint-ignore no-explicit-any
async function stravaFetch(
  path: string,
  creds: StravaCreds,
  supabase: any,
  userId: string,
  retried = false,
): Promise<Response> {
  // Pre-emptive refresh when expires_at is within 5 minutes — saves a
  // round-trip on the inevitable 401.
  if (!retried && creds.expiresAt && creds.expiresAt.getTime() - Date.now() < 5 * 60 * 1000) {
    try {
      await refreshTokens(creds, supabase, userId);
    } catch (err) {
      console.warn("[strava-test-pull] pre-emptive refresh failed, falling through:", err);
    }
  }
  const res = await fetch(`https://www.strava.com/api/v3${path}`, {
    headers: { Authorization: `Bearer ${creds.accessToken}` },
  });
  if (res.status === 401 && !retried) {
    await refreshTokens(creds, supabase, userId);
    return stravaFetch(path, creds, supabase, userId, true);
  }
  return res;
}

function paceStringFromSpeedMps(speedMps: number): string {
  if (!speedMps || speedMps <= 0) return "";
  const secPerMile = 1609.34 / speedMps;
  const m = Math.floor(secPerMile / 60);
  const s = Math.round(secPerMile % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

function classifyEffort(paceSec: number, avgPaceSec: number): string {
  // Very rough classifier — good enough for testing context.
  if (!avgPaceSec) return "steady";
  const ratio = paceSec / avgPaceSec;
  if (ratio < 0.92) return "fast";
  if (ratio > 1.08) return "easy";
  return "steady";
}

function splitsToPaceSegments(splits: StravaSplit[], avgSpeedMps: number) {
  const avgPaceSec = avgSpeedMps > 0 ? 1609.34 / avgSpeedMps : 0;
  return splits.map((s) => {
    const paceSec = s.average_speed > 0 ? 1609.34 / s.average_speed : 0;
    return {
      effort: classifyEffort(paceSec, avgPaceSec),
      distance_miles: Number((s.distance / 1609.34).toFixed(2)),
      duration_seconds: Number(s.moving_time),
      pace_per_mile: paceStringFromSpeedMps(s.average_speed),
      avg_heart_rate: s.average_heartrate ? Math.round(s.average_heartrate) : null,
    };
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Require a valid authenticated user. No hardcoded/DEBUG fallback —
    // credentials and imported activities are scoped to this userId, so an
    // unauthenticated caller must never resolve to a real account.
    const userId = await getAuthenticatedUser(req);
    if (!userId) return unauthorizedResponse(corsHeaders);

    const body = await req.json().catch(() => ({}));
    const limit = Math.min(Math.max(Number(body.limit) || 30, 1), 100);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    if (body.action === "exchange") {
      if (!STRAVA_CLIENT_ID || !STRAVA_CLIENT_SECRET) {
        throw new Error("STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET secrets are not set");
      }
      if (!body.code) {
        throw new Error("missing 'code' in body");
      }
      const exchangeRes = await fetch("https://www.strava.com/oauth/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: STRAVA_CLIENT_ID,
          client_secret: STRAVA_CLIENT_SECRET,
          grant_type: "authorization_code",
          code: String(body.code),
        }),
      });
      if (!exchangeRes.ok) {
        const text = await exchangeRes.text();
        throw new Error(`Strava exchange failed ${exchangeRes.status}: ${text}`);
      }
      const tokens = await exchangeRes.json();
      const newCreds: StravaCreds = {
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token,
        expiresAt: tokens.expires_at ? new Date(tokens.expires_at * 1000) : null,
        athleteId: tokens.athlete?.id ?? null,
        scope: tokens.scope ?? null,
      };
      await persistCredentials(supabase, userId, newCreds);
      return new Response(
        JSON.stringify({
          ok: true,
          action: "exchange",
          athleteId: newCreds.athleteId,
          scope: newCreds.scope,
          expiresAt: newCreds.expiresAt?.toISOString() ?? null,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Load tokens from strava_credentials. Refresh paths inside stravaFetch
    // mutate the creds object AND persist back to the table on every
    // rotation, so the next cold start picks up where we left off.
    const creds = await loadCredentials(supabase, userId);

    // 1) List recent activities
    const listRes = await stravaFetch(`/athlete/activities?per_page=${limit}`, creds, supabase, userId);
    if (!listRes.ok) {
      const text = await listRes.text();
      throw new Error(`Strava list failed ${listRes.status}: ${text}`);
    }
    const activities = (await listRes.json()) as StravaActivity[];

    const byType: Record<string, number> = {};
    for (const a of activities) {
      const key = a.sport_type ?? a.type ?? "unknown";
      byType[key] = (byType[key] ?? 0) + 1;
    }
    console.log("[strava-test-pull] activities returned:", activities.length, "byType:", JSON.stringify(byType));
    console.log("[strava-test-pull] recent activities:", JSON.stringify(
      activities.slice(0, 10).map((a) => ({ id: a.id, name: a.name, sport_type: a.sport_type, type: a.type, start: a.start_date_local }))
    ));

    // Accept all running shapes. HealthKit-imported treadmill workouts land as
    // VirtualRun; some watches push Workout for runs that aren't auto-detected.
    const RUN_SPORT_TYPES = new Set(["Run", "TrailRun", "VirtualRun"]);
    const runs = activities.filter(
      (a) => RUN_SPORT_TYPES.has(a.sport_type) || a.type === "Run"
    );
    const filteredOut = activities.length - runs.length;

    let imported = 0;
    let skipped = 0;
    const errors: Array<{ id: number; error: string }> = [];

    for (const a of runs) {
      try {
        const stravaKey = `strava_${a.id}`;

        // Dedup — reuse vital_workout_id column as generic external ID.
        // If a row exists but is missing rich streams, we fall through and UPDATE it
        // rather than inserting a duplicate.
        const { data: existing } = await supabase
          .from("training_logs")
          .select("id, external_streams")
          .eq("vital_workout_id", stravaKey)
          .maybeSingle();
        const needsStreamsBackfill = existing && existing.external_streams == null;
        if (existing && !needsStreamsBackfill) {
          skipped++;
          continue;
        }

        // 2) Fetch detailed activity for splits + laps + metadata
        const detailRes = await stravaFetch(`/activities/${a.id}`, creds, supabase, userId);
        if (!detailRes.ok) {
          errors.push({ id: a.id, error: `detail ${detailRes.status}` });
          continue;
        }
        const detail = (await detailRes.json()) as StravaDetailed & {
          laps?: unknown;
          description?: string;
          device_name?: string;
          workout_type?: number;
          suffer_score?: number;
          perceived_exertion?: number;
          calories?: number;
          average_cadence?: number;
          average_watts?: number;
          max_watts?: number;
          average_temp?: number;
        };
        const splits = detail.splits_standard ?? [];

        const paceSegments = splits.length > 0
          ? splitsToPaceSegments(splits, detail.average_speed ?? 0)
          : null;

        // 3) Fetch per-second streams (HR, pace, GPS, altitude, cadence, power, grade, temp)
        const streamKeys = [
          "time",
          "heartrate",
          "velocity_smooth",
          "latlng",
          "altitude",
          "cadence",
          "watts",
          "grade_smooth",
          "temp",
          "distance",
        ].join(",");
        const streamsRes = await stravaFetch(
          `/activities/${a.id}/streams?keys=${streamKeys}&key_by_type=true`,
          creds,
          supabase,
          userId,
        );
        let streams: Record<string, unknown> | null = null;
        if (streamsRes.ok) {
          const raw = await streamsRes.json() as Record<string, { data?: unknown }>;
          streams = {};
          for (const [k, v] of Object.entries(raw)) {
            if (v && typeof v === "object" && "data" in v) {
              streams[k] = (v as { data: unknown }).data;
            }
          }
        } else {
          console.warn(`[strava-test-pull] streams fetch failed for ${a.id}: ${streamsRes.status}`);
        }

        const externalStreams = {
          source: "strava",
          activity_id: a.id,
          streams,
          laps: detail.laps ?? null,
          meta: {
            name: a.name,
            description: detail.description ?? null,
            device_name: detail.device_name ?? null,
            workout_type: detail.workout_type ?? null,
            suffer_score: detail.suffer_score ?? null,
            perceived_exertion: detail.perceived_exertion ?? null,
            calories: detail.calories ?? null,
            average_cadence: detail.average_cadence ?? null,
            average_watts: detail.average_watts ?? null,
            max_watts: detail.max_watts ?? null,
            average_temp: detail.average_temp ?? null,
            average_heartrate: a.average_heartrate ?? null,
            max_heartrate: a.max_heartrate ?? null,
            total_elevation_gain: a.total_elevation_gain ?? null,
          },
        };

        const distanceMiles = Number((a.distance / 1609.34).toFixed(2));
        const durationMinutes = Number((a.moving_time / 60).toFixed(2));
        const avgPace = paceStringFromSpeedMps(a.average_speed ?? 0);

        const noteLines = [
          a.name,
          `Distance: ${distanceMiles} mi`,
          `Duration: ${Math.floor(durationMinutes)}:${String(
            Math.round((durationMinutes % 1) * 60)
          ).padStart(2, "0")}`,
          avgPace ? `Avg pace: ${avgPace}/mi` : null,
          a.average_heartrate ? `Avg HR: ${Math.round(a.average_heartrate)} bpm` : null,
          a.total_elevation_gain ? `Elev gain: ${Math.round(a.total_elevation_gain)} m` : null,
        ].filter(Boolean);

        if (needsStreamsBackfill && existing) {
          const { error: updateErr } = await supabase
            .from("training_logs")
            .update({
              pace_segments: paceSegments,
              external_streams: externalStreams,
              processing_status: "completed",
            })
            .eq("id", existing.id);
          if (updateErr) {
            errors.push({ id: a.id, error: `update: ${updateErr.message}` });
          } else {
            imported++;
          }
        } else {
          const { error: insertErr } = await supabase.from("training_logs").insert({
            user_id: userId,
            source: "strava",
            vital_workout_id: stravaKey,
            workout_date: a.start_date_local,
            workout_distance_miles: distanceMiles,
            workout_duration_minutes: durationMinutes,
            notes: noteLines.join("\n"),
            cleaned_notes: a.name,
            pace_segments: paceSegments,
            external_streams: externalStreams,
            processing_status: "completed",
          });
          if (insertErr) {
            errors.push({ id: a.id, error: insertErr.message });
          } else {
            imported++;
          }
        }
      } catch (err) {
        errors.push({
          id: a.id,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        totalActivities: activities.length,
        runs: runs.length,
        filteredOut,
        byType,
        imported,
        skipped,
        errors,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("[strava-test-pull]", msg);
    return new Response(
      JSON.stringify({ error: msg }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
