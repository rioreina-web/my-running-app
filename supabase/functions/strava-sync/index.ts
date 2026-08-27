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
import {
  ORPHAN_FALLBACK_AFTER_MS,
  ORPHAN_FALLBACK_BEFORE_MS,
  ORPHAN_TIME_WINDOW_MS,
  type OrphanCandidate,
  pickBestOrphan,
} from "../_shared/voiceOrphanMatch.ts";
import {
  buildPaceSegments,
  paceStringFromSpeedMps,
  type StravaLapLike,
} from "../_shared/paceSegments.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRAVA_CLIENT_ID = Deno.env.get("STRAVA_CLIENT_ID") ?? "";
const STRAVA_CLIENT_SECRET = Deno.env.get("STRAVA_CLIENT_SECRET") ?? "";

// Background-task hook (Supabase keeps the worker alive until the promise
// settles). Falls back to a detached promise off-platform.
declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

// ── Device-twin absorption (auto_sync ↔ strava) ─────────────────────
//
// The same physical run reaches training_logs through two independent
// writers that do not know about each other:
//
//   • HealthKit  — client-side, fires on app launch (RunningLogApp.swift),
//                  writes source "auto_sync" keyed `sync-<ISO date>`.
//   • strava-sync — this function, keyed `strava_<activity id>`.
//
// A Garmin/Apple Watch run lands in Apple Health *and* in Strava, so both
// fire. The dedup above only looks for `vital_workout_id = strava_<id>`,
// which an auto_sync row never has — so whichever writer lost the race got
// a second row. That is how 2026-08-06's 5x4min ended up rendered from a
// lapless HealthKit copy ("no rep structure to break out") while the Strava
// copy sat unread with all ten laps.
//
// Strava is authoritative for runs: it is the only source that carries lap
// markers, and lap geometry is what makes rep detection possible at all
// (ExternalStreamsPayload, the HealthKit payload, has no `laps` field —
// a HealthKit row is structurally incapable of ever showing splits).
//
// So: before inserting, look for a device twin and PROMOTE it in place.
// Promoting rather than inserting-then-merging keeps the row id stable, so
// the voice memo, coach reads, workout_features and niggles already hanging
// off that row stay attached instead of being orphaned by a delete.
const TWIN_TIME_WINDOW_MS = 15 * 60 * 1000; // start times drift by device clock
const TWIN_DISTANCE_TOLERANCE_MI = 0.3;     // GPS vs HealthKit rounding
const TWIN_SOURCES = ["auto_sync", "vital", "garmin"];

async function findDeviceTwin(
  db: ReturnType<typeof createClient>,
  userId: string,
  runDate: string,
  runDistanceMiles: number,
): Promise<{ id: string; source: string } | null> {
  try {
    const base = new Date(runDate).getTime();
    const lo = new Date(base - TWIN_TIME_WINDOW_MS).toISOString();
    const hi = new Date(base + TWIN_TIME_WINDOW_MS).toISOString();
    const { data, error } = await db
      .from("training_logs")
      .select("id, source, workout_date, workout_distance_miles")
      .eq("user_id", userId)
      .in("source", TWIN_SOURCES)
      .gte("workout_date", lo)
      .lte("workout_date", hi);
    if (error) {
      console.warn(`[strava-sync] twin lookup failed for ${userId}: ${error.message}`);
      return null;
    }
    const candidates = (data ?? []) as Array<
      { id: string; source: string; workout_date: string; workout_distance_miles: number | null }
    >;
    // Closest start time among those that also agree on distance. Two real
    // runs inside 15 min that also match to 0.3 mi would be a warm-up logged
    // twice, not a double — either way collapsing them is the right call.
    let best: { id: string; source: string } | null = null;
    let bestDelta = Number.POSITIVE_INFINITY;
    for (const c of candidates) {
      const mi = c.workout_distance_miles ?? 0;
      if (Math.abs(mi - runDistanceMiles) > TWIN_DISTANCE_TOLERANCE_MI) continue;
      const delta = Math.abs(new Date(c.workout_date).getTime() - base);
      if (delta < bestDelta) {
        bestDelta = delta;
        best = { id: c.id, source: c.source };
      }
    }
    return best;
  } catch (err) {
    console.warn(`[strava-sync] findDeviceTwin threw: ${err instanceof Error ? err.message : String(err)}`);
    return null;
  }
}

// Fold a matching orphan voice_log row (a memo recorded BEFORE this run synced,
// so it has audio + notes but no telemetry) into the run row we just wrote.
// The run stays canonical (keeps GPS/laps/streams) and inherits the memo's
// subjective content via the merge_voice_orphan_into_run RPC. Best-effort: any
// failure — including the RPC not yet being deployed — is logged and swallowed
// so reconciliation can never break the core sync.
async function reconcileVoiceOrphan(
  db: ReturnType<typeof createClient>,
  userId: string,
  runId: string,
  runDate: string,
  runDistanceMiles: number,
): Promise<void> {
  try {
    const windowMs = ORPHAN_TIME_WINDOW_MS;
    const base = new Date(runDate).getTime();
    const lo = new Date(base - windowMs).toISOString();
    const hi = new Date(base + windowMs).toISOString();
    // NULL-dated memos are windowed on created_at instead, and asymmetrically:
    // a memo is WRITTEN after the run it describes, sometimes many hours after.
    // Mirrors ORPHAN_FALLBACK_* — pickBestOrphan re-checks both bounds.
    const cLo = new Date(base - ORPHAN_FALLBACK_AFTER_MS).toISOString();
    const cHi = new Date(base + ORPHAN_FALLBACK_BEFORE_MS).toISOString();
    const { data, error } = await db
      .from("training_logs")
      .select("id, workout_date, workout_distance_miles, created_at")
      .eq("user_id", userId)
      .is("external_streams", null)      // no telemetry
      .not("audio_url", "is", null)      // is a voice memo
      .is("vital_workout_id", null)      // not already linked to a run
      .neq("id", runId)
      // Window on workout_date when it is set, else on created_at. A range
      // predicate on a NULL column matches NOTHING, so the old workout_date-only
      // filter made NULL-dated memos — every memo recorded without a run picked
      // in the recorder — structurally invisible to reconciliation. pickBestOrphan
      // applies the same fallback and still enforces the ±4h / distance checks.
      .or(
        `and(workout_date.gte.${lo},workout_date.lte.${hi}),` +
          `and(workout_date.is.null,created_at.gte.${cLo},created_at.lte.${cHi})`,
      );
    if (error) {
      console.warn(`[strava-sync] orphan lookup failed for ${userId}: ${error.message}`);
      return;
    }
    const orphan = pickBestOrphan(
      { workout_date: runDate, workout_distance_miles: runDistanceMiles },
      (data ?? []) as OrphanCandidate[],
    );
    if (!orphan) return;
    // The service-role client carries no generated DB types, so rpc() can't
    // see this function's params; cast to satisfy the checker (args pass at
    // runtime unchanged).
    const { error: mergeErr } = await db.rpc(
      "merge_voice_orphan_into_run",
      { p_orphan: orphan.id, p_run: runId } as never,
    );
    if (mergeErr) {
      console.warn(`[strava-sync] voice-orphan merge failed (${orphan.id} → ${runId}): ${mergeErr.message}`);
    } else {
      console.log(`[strava-sync] merged voice orphan ${orphan.id} into run ${runId}`);
    }
  } catch (err) {
    console.warn(`[strava-sync] reconcileVoiceOrphan threw: ${err instanceof Error ? err.message : String(err)}`);
  }
}

/**
 * Fire parse-workout-structure for a freshly-ingested run. The pg_net trigger
 * that was supposed to do this is dead on Supabase (ALTER DATABASE SET
 * app.settings.* is permission-denied), so structure was never parsed for any
 * workout. We invoke the parser directly with the service role instead —
 * fire-and-forget so the sync loop never blocks on Gemini. See Option A.
 */
function fireParseStructure(trainingLogId: string, userId: string): void {
  if (!supabaseUrl || !supabaseServiceKey) return;
  const p = fetch(`${supabaseUrl}/functions/v1/parse-workout-structure`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${supabaseServiceKey}`,
      apikey: supabaseServiceKey,
    },
    body: JSON.stringify({ training_log_id: trainingLogId, user_id: userId }),
  })
    .then((r) => {
      if (!r.ok) console.warn(`[strava-sync] parse-structure ${r.status} for ${trainingLogId}`);
    })
    .catch((e) => console.warn(`[strava-sync] parse-structure fetch failed: ${e}`))
    // Features AFTER parse settles (success or not): compute-workout-features
    // reads the parsed laps when they exist and falls back to pace_segments
    // when they don't, so sequencing beats racing it against the parser.
    // Without this, a Strava-ingested run's `stress_load` (TLS) stayed NULL
    // until something else happened to invoke the batch compute — and one
    // NULL run day drops the recovery model's whole load unit off the
    // stressLoad rung (see the LoadUnit ladder in TrendsRecoveryDemand.swift).
    .then(() => fireComputeFeatures(trainingLogId, userId));
  try {
    if (typeof EdgeRuntime !== "undefined" && EdgeRuntime?.waitUntil) {
      EdgeRuntime.waitUntil(p);
      return;
    }
  } catch { /* fall through */ }
  void p;
}

/**
 * Fire compute-workout-features for one freshly-ingested run — per-log mode,
 * which recomputes even when a features row already exists (the twin-promote
 * path deletes the stale row first anyway). This is what persists
 * `training_logs.stress_load` (TLS, weighted training-minutes), the recovery
 * model's preferred load unit. Fire-and-forget like its siblings.
 */
function fireComputeFeatures(trainingLogId: string, userId: string): void {
  if (!supabaseUrl || !supabaseServiceKey) return;
  const p = fetch(`${supabaseUrl}/functions/v1/compute-workout-features`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${supabaseServiceKey}`,
      apikey: supabaseServiceKey,
    },
    body: JSON.stringify({ training_log_id: trainingLogId, user_id: userId }),
  })
    .then((r) => {
      if (!r.ok) console.warn(`[strava-sync] compute-features ${r.status} for ${trainingLogId}`);
    })
    .catch((e) => console.warn(`[strava-sync] compute-features fetch failed: ${e}`));
  try {
    if (typeof EdgeRuntime !== "undefined" && EdgeRuntime?.waitUntil) {
      EdgeRuntime.waitUntil(p);
      return;
    }
  } catch { /* fall through */ }
  void p;
}

/**
 * Fire fetch-workout-weather for a freshly-ingested run so its actual
 * conditions (temp / dew point / heat) attach to training_logs.weather_actual,
 * located from the run's own GPS. Fire-and-forget — the sync loop never blocks
 * on Open-Meteo, and a miss is harmless (weather_actual just stays null).
 */
function fireWorkoutWeather(trainingLogId: string, userId: string): void {
  if (!supabaseUrl || !supabaseServiceKey) return;
  const p = fetch(`${supabaseUrl}/functions/v1/fetch-workout-weather`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${supabaseServiceKey}`,
      apikey: supabaseServiceKey,
    },
    body: JSON.stringify({ training_log_id: trainingLogId, user_id: userId }),
  })
    .then((r) => {
      if (!r.ok) console.warn(`[strava-sync] fetch-weather ${r.status} for ${trainingLogId}`);
    })
    .catch((e) => console.warn(`[strava-sync] fetch-weather fetch failed: ${e}`));
  try {
    if (typeof EdgeRuntime !== "undefined" && EdgeRuntime?.waitUntil) {
      EdgeRuntime.waitUntil(p);
      return;
    }
  } catch { /* fall through */ }
  void p;
}

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
  start_date: string;        // true UTC instant, e.g. "2026-06-17T11:30:46Z"
  start_date_local: string;  // local wall-time stamped with Z (Strava quirk)
  timezone?: string;         // e.g. "(GMT-06:00) America/Chicago"
  utc_offset?: number;       // seconds, e.g. -18000
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

/** Strava omits `laps` for some activities (manual entries, certain devices).
 *  When that happens, `external_streams.laps` is null, the lap-writer trigger
 *  has nothing to parse, and the app silently re-segments the GPS stream into
 *  miles. Fall back to Strava's per-mile splits, mapped into the lap shape the
 *  `running_workout_laps` trigger expects, so every run still gets distance
 *  splits with real per-split HR. Native `laps` (which reflect the recording's
 *  own auto-lap unit, e.g. 1 km) always win when present. */
function lapsOrSplitFallback(
  detail: { laps?: unknown; splits_standard?: StravaSplit[] },
): unknown[] | null {
  if (Array.isArray(detail.laps) && detail.laps.length > 0) return detail.laps as unknown[];
  const splits = detail.splits_standard;
  if (!splits || splits.length === 0) return null;
  return splits.map((s, i) => ({
    lap_index: s.split ?? (i + 1),
    distance: s.distance,
    moving_time: s.moving_time,
    elapsed_time: s.elapsed_time,
    average_speed: s.average_speed,
    average_heartrate: s.average_heartrate ?? null,
  }));
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

// ── Pace-segment helpers ───────────────────────────────────────────
//
// The segment builders moved to `_shared/paceSegments.ts` on 2026-08-20, when
// `pace_segments` stopped being built from per-mile splits and started being
// built from the watch's own laps. See that file's header for why. They are
// shared rather than copied so this function and `strava-test-pull` can never
// again disagree about what a segment is.

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

  // Strava's `after` filter is on each activity's start_date (when the run
  // happened), but the watermark advances to now() (when the sync ran). An
  // activity uploaded later than it started — always true, and large for long
  // runs uploaded after completion — can have a start_date that already
  // predates last_synced_at, making it invisible to `after=last_synced_at`
  // forever. Re-scan a safety buffer behind the watermark so late uploads are
  // caught; dedup on vital_workout_id (checked before any detail/stream fetch)
  // keeps the re-scan idempotent and cheap.
  const WATERMARK_SAFETY_DAYS = 14;
  const afterMs = row.last_synced_at
    ? new Date(row.last_synced_at).getTime() - WATERMARK_SAFETY_DAYS * 86400 * 1000
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
      // Laps first, mile splits as the fallback. A mile of an interval session
      // is work + recovery averaged together; the laps are the reps.
      const paceSegments = buildPaceSegments({
        laps: Array.isArray(detail.laps) ? detail.laps as StravaLapLike[] : null,
        splits_standard: splits,
        average_speed: detail.average_speed ?? 0,
        distance: a.distance,
      });

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
        laps: lapsOrSplitFallback(detail),
        meta: {
          name: a.name,
          // Timestamps: start_date is the true UTC instant (what workout_date
          // now stores); the local/tz fields let the UI render the run in its
          // own zone even if the device is elsewhere.
          start_date: a.start_date,
          start_date_local: a.start_date_local,
          timezone: a.timezone ?? null,
          utc_offset: a.utc_offset ?? null,
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
            // Also correct the timestamp to true UTC on re-sync, so rows that
            // were imported with the old start_date_local bug get fixed.
            workout_date: a.start_date,
            pace_segments: paceSegments,
            external_streams: externalStreams,
            processing_status: "completed",
          })
          .eq("id", existingRow.id);
        if (updateErr) {
          result.errors.push({ id: a.id, error: `update: ${updateErr.message}` });
        } else {
          result.imported++;
          // Streams just landed — parse the workout structure from the GPS.
          fireParseStructure(existingRow.id, userId);
          fireWorkoutWeather(existingRow.id, userId);
          // Fold in a voice memo that was recorded before this run had streams.
          await reconcileVoiceOrphan(db, userId, existingRow.id, a.start_date, distanceMiles);
        }
      } else {
        // Strava is authoritative for runs. If HealthKit already wrote this
        // same physical run as an `auto_sync` row, promote that row in place
        // rather than inserting a second one — see findDeviceTwin above.
        const twin = await findDeviceTwin(db, userId, a.start_date, distanceMiles);
        if (twin) {
          const { error: promoteErr } = await db
            .from("training_logs")
            .update({
              source: "strava",
              vital_workout_id: stravaKey,
              external_id: stravaKey,
              workout_date: a.start_date,
              workout_distance_miles: distanceMiles,
              workout_duration_minutes: durationMinutes,
              notes: noteLines.join("\n"),
              pace_segments: paceSegments,
              external_streams: externalStreams,
              processing_status: "completed",
              // Anything DERIVED from the lapless HealthKit copy is wrong by
              // construction (one "steady" block, confidence 0.5, geometry
              // "model"). Clear it so the laps that just landed drive a fresh
              // parse + read. Anything the athlete OWNS — audio_url,
              // transcript_url, cleaned_notes, workout_notes, mood, RPE — is
              // deliberately untouched: the memo is the one thing the
              // HealthKit row holds that Strava cannot supply.
              parsed_structure: null,
              coach_insight: null,
              coach_insight_status: "pending",
            })
            .eq("id", twin.id);
          if (promoteErr) {
            result.errors.push({ id: a.id, error: `promote: ${promoteErr.message}` });
          } else {
            result.imported++;
            console.log(
              `[strava-sync] promoted ${twin.source} row ${twin.id} → strava ${a.id} (absorbed device twin)`,
            );
            // workout_type is DERIVED from the lapless copy too, and clearing it
            // belongs with parsed_structure/coach_insight above — but it cannot
            // go in that payload, because an undeclared write is demoted to
            // `unknown` by the authority ladder and would be refused. Declaring
            // `device` clears exactly what the device heuristic wrote and is
            // refused against anything stronger, so a re-sync can never wipe a
            // type the athlete picked or spoke. This is the specific hole that
            // left 2026-08-26's easy run reading "Threshold": the promote
            // cleared every other derived field and carried this one forward.
            // The compute pass fired below refills it from real lap geometry.
            const { error: clearTypeErr } = await db.rpc("set_workout_type", {
              p_log: twin.id,
              p_type: null,
              p_source: "device",
            });
            if (clearTypeErr) {
              console.warn(`[strava-sync] device type clear failed for ${twin.id}: ${clearTypeErr.message}`);
            }
            // Features were computed off the lapless copy — drop them so the
            // next compute pass rebuilds from real lap geometry.
            const { error: featErr } = await db
              .from("workout_features")
              .delete()
              .eq("training_log_id", twin.id);
            if (featErr) {
              console.warn(`[strava-sync] stale feature cleanup failed for ${twin.id}: ${featErr.message}`);
            }
            fireParseStructure(twin.id, userId);
            fireWorkoutWeather(twin.id, userId);
            await reconcileVoiceOrphan(db, userId, twin.id, a.start_date, distanceMiles);
          }
          continue;
        }

        const { data: insertedRow, error: insertErr } = await db
          .from("training_logs")
          .insert({
            user_id: userId,
            source: "strava",
            vital_workout_id: stravaKey,
            // True UTC instant. The app renders it in the run's local zone
            // (device tz, or the captured utc_offset). Storing start_date_local
            // here was the old bug — local wall-time tagged Z got re-converted
            // and showed the run hours off.
            workout_date: a.start_date,
            workout_distance_miles: distanceMiles,
            workout_duration_minutes: durationMinutes,
            notes: noteLines.join("\n"),
            cleaned_notes: a.name,
            pace_segments: paceSegments,
            external_streams: externalStreams,
            processing_status: "completed",
          })
          .select("id")
          .single();
        if (insertErr) {
          result.errors.push({ id: a.id, error: insertErr.message });
        } else {
          result.imported++;
          // New run with GPS streams — parse the workout structure from it.
          if (insertedRow?.id) {
            fireParseStructure(String(insertedRow.id), userId);
            fireWorkoutWeather(String(insertedRow.id), userId);
            // Fold in a voice memo recorded before this run synced (orphan).
            await reconcileVoiceOrphan(db, userId, String(insertedRow.id), a.start_date, distanceMiles);
          }
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

// True if the (gateway-verified) JWT's role claim is service_role. The Supabase
// edge gateway validates the JWT signature against the project's keys BEFORE
// routing here, so the decoded payload is trustworthy. This accepts ANY current
// service-role token, making auth robust to SUPABASE_SERVICE_ROLE_KEY drifting
// from the live project key (the drift that 403'd both manual and cron calls).
function hasServiceRoleClaim(token: string): boolean {
  try {
    const payload = token.split(".")[1];
    if (!payload) return false;
    const b64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    const claims = JSON.parse(atob(padded));
    return claims?.role === "service_role";
  } catch {
    return false;
  }
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
  if (!constantTimeEq(token, supabaseServiceKey) && !hasServiceRoleClaim(token)) {
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

    // Tolerate the last_synced_at column not existing yet (its migration may
    // not be applied). With it: incremental. Without it: fall back to the
    // lookback window (dedup keeps re-scans harmless).
    const fullSel = "user_id, access_token, refresh_token, expires_at, strava_athlete_id, scope, last_synced_at";
    let credRes = await db.from("strava_credentials").select(fullSel);
    if (credRes.error && /last_synced_at/.test(credRes.error.message ?? "")) {
      console.warn("[strava-sync] last_synced_at column absent — non-incremental fallback");
      credRes = await db
        .from("strava_credentials")
        .select("user_id, access_token, refresh_token, expires_at, strava_athlete_id, scope");
    }
    if (credRes.error) throw new Error(`load credentials failed: ${credRes.error.message}`);
    const creds = (credRes.data ?? []) as CredRow[];

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
