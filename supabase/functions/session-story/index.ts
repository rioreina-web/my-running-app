/**
 * session-story — lazy per-session detail endpoint backing the iOS
 * Session Story sheet (Trends ▸ Key sessions ▸ tap a session).
 *
 * Where `trends-timeline` answers "what happened across the block" in one
 * cheap list call, this answers "tell me THIS session, whole" — segments with
 * heart rate, heat/grade-adjusted paces, drift, the day's conditions, the
 * voice memo, and the niggles — for one session plus an optional comparison
 * session the client picked (the previous comparable key session).
 *
 * This is the lazy path trends-timeline explicitly deferred to: per-second
 * `external_streams` blobs are too heavy for the list load, but for one or
 * two sessions the split-grade adjustment is affordable, so hills are scored
 * from the real altitude profile here whenever the stream exists.
 *
 * NO LLM, NO writes. Auth: user-JWT or service-role (dual-mode), mirroring
 * `trends-timeline`. All reads filtered by the resolved `user_id`.
 *
 * Request:  POST { log_id, compare_log_id?, user_id? }
 * Response: { session: StoryOut, compare: StoryOut | null, generated_at }
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import type { ZoneTable } from "../_shared/quality-volume.ts";
import type { FSStream } from "../trends-timeline/fastSegments.ts";
import {
  buildStory,
  type StoryLapRow,
  type StoryLogRow,
  type StoryMentionRow,
} from "./story.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const LOG_COLS =
  "id, workout_date, workout_distance_miles, workout_duration_minutes, notes, cleaned_notes, mood, weather_actual";
const LAP_COLS =
  "workout_id, lap_index, is_rest, distance_meters, avg_pace_sec_per_mile, moving_time_seconds, avg_heart_rate, max_heart_rate, total_elevation_gain, stream_start_index, stream_end_index";

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

    const logId = typeof body?.log_id === "string" ? body.log_id : null;
    const compareId = typeof body?.compare_log_id === "string" ? body.compare_log_id : null;
    if (!logId) {
      return json({ error: "log_id required" }, 400);
    }

    const zones = await fetchPaceZones(userId);
    const session = await fetchAndBuild(userId, logId, zones);
    if (!session) return json({ error: "session not found" }, 404);
    const compare = compareId && compareId !== logId
      ? await fetchAndBuild(userId, compareId, zones)
      : null;

    return json(
      { session, compare, generated_at: new Date().toISOString() },
      200,
    );
  } catch (err) {
    console.error("[session-story] error:", err);
    return json({ error: (err as Error).message ?? "Internal error" }, 500);
  }
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Fetch one session's rows and build its story. null when the log doesn't
 *  exist (or isn't this athlete's — same thing to the caller). */
async function fetchAndBuild(
  userId: string,
  logId: string,
  zones: ZoneTable,
) {
  const logRes = await supabase
    .from("training_logs")
    .select(LOG_COLS)
    .eq("user_id", userId)
    .eq("id", logId)
    .maybeSingle();
  if (logRes.error || !logRes.data) return null;
  const log = logRes.data as unknown as StoryLogRow;

  const [laps, structure, stream, mentions] = await Promise.all([
    fetchLaps(userId, logId),
    fetchStructure(logId),
    fetchStream(userId, logId),
    fetchMentions(userId, String(log.workout_date).slice(0, 10)),
  ]);

  return buildStory({ log, laps, structure, stream, mentions }, zones);
}

async function fetchLaps(userId: string, logId: string): Promise<StoryLapRow[]> {
  const { data, error } = await supabase
    .from("running_workout_laps")
    .select(LAP_COLS)
    .eq("user_id", userId)
    .eq("workout_id", logId)
    .order("lap_index", { ascending: true });
  if (error) return []; // degrade — the story still carries memo + niggles
  return (data ?? []) as unknown as StoryLapRow[];
}

async function fetchStructure(logId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from("workout_features")
    .select("workout_structure")
    .eq("training_log_id", logId)
    .maybeSingle();
  if (error || !data) return null;
  return (data.workout_structure as string | null) ?? null;
}

/** The per-second altitude stream — the split-grade input. Additive: any
 *  failure or malformed blob just means the net-grade fallback. */
async function fetchStream(userId: string, logId: string): Promise<FSStream | null> {
  const { data, error } = await supabase
    .from("training_logs")
    .select("external_streams")
    .eq("user_id", userId)
    .eq("id", logId)
    .maybeSingle();
  if (error || !data) return null;
  const es = data.external_streams as Record<string, unknown> | null;
  if (!es) return null;
  const time = es.time, distance = es.distance, altitude = es.altitude;
  if (
    Array.isArray(time) && Array.isArray(distance) && Array.isArray(altitude) &&
    altitude.length > 0
  ) {
    return {
      time: time as number[],
      distance: distance as number[],
      altitude: altitude as number[],
    };
  }
  return null;
}

/** Niggles within ±1 day of the session — the "what the body said" lane.
 *  Verbatim quotes only; interpretation is nobody's job (CLAUDE.md). */
async function fetchMentions(userId: string, dateISO: string): Promise<StoryMentionRow[]> {
  const t = Date.parse(`${dateISO}T00:00:00Z`);
  if (Number.isNaN(t)) return [];
  const dayMs = 24 * 60 * 60 * 1000;
  const lo = new Date(t - dayMs).toISOString().split("T")[0];
  const hi = new Date(t + dayMs).toISOString().split("T")[0];
  const { data, error } = await supabase
    .from("body_mentions")
    .select("body_area, side, severity_hint, verbatim_quote")
    .eq("user_id", userId)
    .gte("mentioned_at", lo)
    .lte("mentioned_at", hi);
  if (error) return [];
  return (data ?? []) as unknown as StoryMentionRow[];
}

/**
 * The athlete's pace zones from `athlete_state.pace_zones`, as the ZoneTable
 * the fast-segment analyzer consumes. Mirrors `trends-timeline.fetchPaceZones`
 * (including the `hm ?? hmp` key tolerance) so this surface classifies against
 * exactly the same table as every other quality surface.
 */
async function fetchPaceZones(userId: string): Promise<ZoneTable> {
  const { data } = await supabase
    .from("athlete_state")
    .select("pace_zones")
    .eq("user_id", userId)
    .maybeSingle();
  const z = (data?.pace_zones ?? {}) as Record<string, unknown>;
  const num = (v: unknown): number | undefined =>
    typeof v === "number" && v > 0 ? v : undefined;
  return {
    mp: num(z.mp),
    hm: num(z.hm) ?? num(z.hmp),
    tenK: num(z.tenK),
    fiveK: num(z.fiveK),
    threeK: num(z.threeK),
    mile: num(z.mile),
    steady: num(z.steady),
    moderate: num(z.moderate),
    easy: num(z.easy),
  };
}
