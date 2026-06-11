/**
 * Strava Sync — automatic, multi-user, incremental.
 *
 * Cron-driven worker (every ~15 min) that, for EVERY row in
 * `strava_credentials`, pulls the activities created since that user's last
 * sync and ingests new runs into `training_logs`. This is the production
 * replacement for the manual, single-user `strava-test-pull` test harness.
 *
 * Auth: SERVICE-ROLE ONLY (same contract as the drain workers). The cron
 *   sends `Authorization: Bearer <service_role_key>` (read from Vault at run
 *   time — see the companion migration); we constant-time compare it to the
 *   function's SUPABASE_SERVICE_ROLE_KEY env. No user JWT path: this never
 *   runs on behalf of an end user, it iterates all connected accounts.
 *
 * Incremental: each user carries `strava_credentials.last_synced_at`. We list
 *   `/athlete/activities?after=<watermark>` so we never re-fetch the whole
 *   history and never miss runs (the old test-pull used a flat top-30 with no
 *   `after`, which could silently drop activities). First sync (null
 *   watermark) looks back DEFAULT_LOOKBACK_DAYS. Dedup on
 *   `vital_workout_id = strava_<id>` makes overlap harmless.
 *
 * Token refresh + rotation-persist is identical to strava-test-pull: Strava
 *   rotates the refresh token on every refresh, so we persist it back on every
 *   rotation or the next cold start breaks.
 *
 * Body (optional): { source?: string, lookbackDays?: number, perUserLimit?: number }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRAVA_CLIENT_ID = Deno.env.get("STRAVA_CLIENT_ID") ?? "";
const STRAVA_CLIENT_SECRET = Deno.env.get("STRAVA_CLIENT_SECRET") ?? "";

// The default SupabaseClient generics resolve untyped queries to `never`;
// strava ingest uses an untyped admin client (mirrors strava-test-pull).
// deno-lint-ignore no-explicit-any
const db = createClient(supabaseUrl, supabaseServiceKey) as any;

const DEFAULT_LOOKBACK_DAYS = 60;   // first sync window when last_synced_at is null
const DEFAULT_PER_USER_LIMIT = 100; // Strava per_page cap

const RUN_SPORT_TYPES = new Set(["Run", "TrailRun", "VirtualRun"]);

interface StravaCreds {
  accessToken: string;
  refreshToken: string;
  expiresAt: Date | null;
  athleteId: number | null;
  scope: string | null;
}

interface CredRow {
  user_id: string;
  access_token: string;
  refresh_token: string;
  expires_at: string | null;
  strava_athlete_id: number | null;
  scope: string | null;
  last_synced_at: string | null;
}

interface StravaActivity {
  id: number;
  name: string;
  sport_type: string;
  type: string;
  distance: number;
  moving_time: number;
  start_date: string;
  start_date_local: string;
  average_heartrate?: number;
  max_heartrate?: number;
  average_speed?: number;
  total_elevation_gain?: number;
  has_heartrate?: boolean;
}

interface StravaSplit {
  distance: number;
  elapsed_time: number;
  moving_time: number;
  average_speed: number;
  average_heartrate?: number;
  split: number;
}

interface StravaDetailed extends StravaActivity {
  splits_standard?: StravaSplit[];
  splits_metric?: StravaSplit[];
}

// ── Credential persistence + refresh (rotation-safe) ───────────────

async function persistCredentials(userId: string, creds: StravaCreds): Promise<void> {
  const { error } = await db
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
    console.error(`[strava-sync] persistCredentials failed for ${userId}:`, error.message);
  }
}

async function refreshTokens(creds: StravaCreds, userId: string): Promise<void> {
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
  // Strava rotates refresh_token on every refresh — persist the new one or
  // the next cold start breaks.
  creds.accessToken = refreshed.access_token;
  creds.refreshToken = refreshed.refresh_token ?? creds.refreshToken;
  creds.expiresAt = refreshed.expires_at ? new Date(refreshed.expires_at * 1000) : null;
  creds.scope = refreshed.scope ?? creds.scope;
  await persistCredentials(userId, creds);
}

async function stravaFetch(
  path: string,
  creds: StravaCreds,
  userId: string,
  retried = false,
): Promise<Response> {
  // Pre-emptive refresh when within 5 minutes of expiry.
  if (!retried && creds.expiresAt && creds.expiresAt.getTime() - Date.now() < 5 * 60 * 1000) {
    try {
      await refreshTokens(creds, userId);
    } catch (err) {
      console.warn(`[strava-sync] pre-emptive refresh failed for ${userId}:`, err);
    }
  }
  const res = await fetch(`https://www.strava.com/api/v3${path}`, {
    headers: { Authorization: `Bearer ${creds.accessToken}` },
  });
  if (res.status === 401 && !retried) {
    await refreshTokens(creds, userId);
    return stravaFetch(path, creds, userId, true);
  }
  return res;
}

// ── Pace-segment helpers (identical to strava-test-pull) ───────────

function paceStringFromSpeedMps(speedMps: number): string {
  if (!speedMps || speedMps <= 0) return "";
  const secPerMile = 1609.34 / speedMps;
  const m = Math.floor(secPerMile / 60);
  const s = Math.round(secPerMile % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

function classifyEffort(paceSec: number, avgPaceSec: number): string {
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

// ── Per-user sync ──────────────────────────────────────────────────

interface UserSyncResult {
  user_id: string;
  totalActivities: number;
  runs: number;
  imported: number;
  skipped: number;
  errors: Array<{ id: number; error: string }>;
}

async function syncUser(row: CredRow, lookbackDays: number, perUserLimit: number): Promise<UserSyncResult> {
  const userId = row.user_id;
  const creds: StravaCreds = {
    accessToken: row.access_token,
    refreshToken: row.refresh_token,
    expiresAt: row.expires_at ? new Date(row.expires_at) : null,
    athleteId: row.strava_athlete_id ?? null,
    scope: row.scope ?? null,
  };

  const afterMs = row.last_synced_at
    ? new Date(row.last_synced_at).getTime()
    : Date.now() - lookbackDays * 86400 * 1000;
  const afterEpoch = Math.floor(afterMs / 1000);

  const result: UserSyncResult = {
    user_id: userId,
    totalActivities: 0,
    runs: 0,
    imported: 0,
    skipped: 0,
    errors: [],
  };

  // 1) List activities since the watermark
  const listRes = await stravaFetch(
    `/athlete/activities?after=${afterEpoch}&per_page=${perUserLimit}`,
    creds,
    userId,
  );
  if (!listRes.ok) {
    const text = await listRes.text();
    throw new Error(`Strava list failed ${listRes.status}: ${text}`);
  }
  const activities = (await listRes.json()) as StravaActivity[];
  result.totalActivities = activities.length;

  const runs = activities.filter(
    (a) => RUN_SPORT_TYPES.has(a.sport_type) || a.type === "Run",
  );
  result.runs = runs.length;

  for (const a of runs) {
    try {
      const stravaKey = `strava_${a.id}`;

      const { data: existing } = await db
        .from("training_logs")
        .select("id, external_streams")
        .eq("vital_workout_id", stravaKey)
        .maybeSingle();
      const existingRow = existing as { id: string; external_streams: unknown } | null;
      const needsStreamsBackfill = existingRow && existingRow.external_streams == null;
      if (existingRow && !needsStreamsBackfill) {
        result.skipped++;
        continue;
      }

      // 2) Detailed activity (splits + laps + metadata)
      const detailRes = await stravaFetch(`/activities/${a.id}`, creds, userId);
      if (!detailRes.ok) {
        result.errors.push({ id: a.id, error: `detail ${detailRes.status}` });
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

      // 3) Per-second streams
      const streamKeys = [
        "time", "heartrate", "velocity_smooth", "latlng", "altitude",
        "cadence", "watts", "grade_smooth", "temp", "distance",
      ].join(",");
      const streamsRes = await stravaFetch(
        `/activities/${a.id}/streams?keys=${streamKeys}&key_by_type=true`,
        creds,
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
        console.warn(`[strava-sync] streams fetch failed for ${a.id}: ${streamsRes.status}`);
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
        `Duration: ${Math.floor(durationMinutes)}:${String(Math.round((durationMinutes % 1) * 60)).padStart(2, "0")}`,
        avgPace ? `Avg pace: ${avgPace}/mi` : null,
        a.average_heartrate ? `Avg HR: ${Math.round(a.average_heartrate)} bpm` : null,
        a.total_elevation_gain ? `Elev gain: ${Math.round(a.total_elevation_gain)} m` : null,
      ].filter(Boolean);

      if (needsStreamsBackfill && existingRow) {
        const { error: updateErr } = await db
          .from("training_logs")
          .update({
            pace_segments: paceSegments,
            external_streams: externalStreams,
            processing_status: "completed",
          })
          .eq("id", existingRow.id);
        if (updateErr) {
          result.errors.push({ id: a.id, error: `update: ${updateErr.message}` });
        } else {
          result.imported++;
        }
      } else {
        const { error: insertErr } = await db.from("training_logs").insert({
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
          result.errors.push({ id: a.id, error: insertErr.message });
        } else {
          result.imported++;
        }
      }
    } catch (err) {
      result.errors.push({ id: a.id, error: err instanceof Error ? err.message : String(err) });
    }
  }

  // Advance the watermark. now() is safe even on partial failure: dedup makes
  // re-runs idempotent, and we'd rather not re-scan the whole window forever.
  const { error: wmErr } = await db
    .from("strava_credentials")
    .update({ last_synced_at: new Date().toISOString() })
    .eq("user_id", userId);
  if (wmErr) console.error(`[strava-sync] watermark update failed for ${userId}:`, wmErr.message);

  return result;
}

// ── Auth ────────────────────────────────────────────────────────────

function constantTimeEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

// ── Handler ─────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Service-role only — same contract as the drain workers.
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Authentication required" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const token = authHeader.slice("Bearer ".length).trim();
  if (!constantTimeEq(token, supabaseServiceKey)) {
    return new Response(JSON.stringify({ error: "Service role required" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const startedAt = Date.now();
  try {
    if (!STRAVA_CLIENT_ID || !STRAVA_CLIENT_SECRET) {
      throw new Error("STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET secrets are not set");
    }

    const body = await req.json().catch(() => ({}));
    const lookbackDays = Math.min(Math.max(Number(body.lookbackDays) || DEFAULT_LOOKBACK_DAYS, 1), 365);
    const perUserLimit = Math.min(Math.max(Number(body.perUserLimit) || DEFAULT_PER_USER_LIMIT, 1), 200);

    const { data: credData, error: credErr } = await db
      .from("strava_credentials")
      .select("user_id, access_token, refresh_token, expires_at, strava_athlete_id, scope, last_synced_at");
    if (credErr) throw new Error(`load credentials failed: ${credErr.message}`);
    const creds = (credData ?? []) as CredRow[];

    const perUser: UserSyncResult[] = [];
    let imported = 0;
    let skipped = 0;
    let failedUsers = 0;

    // Sequential on purpose: keeps us well under Strava's 200-req/15-min rate
    // limit and avoids hammering the API. Fine for the current user count.
    for (const row of creds) {
      try {
        const r = await syncUser(row, lookbackDays, perUserLimit);
        perUser.push(r);
        imported += r.imported;
        skipped += r.skipped;
      } catch (err) {
        failedUsers++;
        console.error(`[strava-sync] user ${row.user_id} failed:`, err);
        perUser.push({
          user_id: row.user_id,
          totalActivities: 0,
          runs: 0,
          imported: 0,
          skipped: 0,
          errors: [{ id: 0, error: err instanceof Error ? err.message : String(err) }],
        });
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        users: creds.length,
        failedUsers,
        imported,
        skipped,
        elapsed_ms: Date.now() - startedAt,
        perUser,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("[strava-sync]", msg);
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
