/**
 * trends-insights — narrative trend cards for the "Trends 2" tab.
 *
 * The read-only, LLM-free companion to `trends-timeline`. Where the timeline
 * builds the chart substrate, this reads that same substrate and emits the
 * "What the chart shows" cards ({ id, group, status, headline, body,
 * evidence, confidence }). NO writes, NO LLM — so it doesn't trip the
 * eval-coverage CI gate. Pure detection lives in `detect.ts` + `detectors*.ts`
 * (unit-tested without the server).
 *
 * Auth: user-JWT or service-role (dual-mode), reads filtered by the resolved
 * user_id — matches `trends-timeline`.
 *
 * Reuse, don't refetch differently: this fetches the SAME core rows the
 * timeline reads and calls the exported, pure `buildTrendsTimeline`, so a
 * card can never disagree with the bars. Group A needs no laps/streams, so
 * the fetch stays lean (logs + features + mentions + MP anchor).
 *
 * Request:  POST { user_id?, weeks? }   weeks ∈ [4, 26], default 26.
 * Response: { cards: TrendCard[], generated_at }
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import {
  buildDailyTimeline,
  buildTrendsTimeline,
  type TimelineFeature,
  type TimelineLog,
  type TimelineMention,
  type TrendsWeekOut,
} from "../trends-timeline/timeline.ts";
import { runDetectors } from "./detect.ts";
import { dayMs } from "./contract.ts";
import { pickStream, type StreamRun } from "./streams.ts";
import { buildKeySessions } from "../trends-timeline/keySessions.ts";
import { fetchQualityLaps } from "../_shared/qualityLaps.ts";
import type { PaceZones } from "../_shared/workoutSegmentation.ts";

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

    // Window a little wider than `weeks` to be safe against partial edges.
    const sinceMs = Date.now() - (weeks + 1) * 7 * 24 * 60 * 60 * 1000;
    const since = new Date(sinceMs).toISOString().split("T")[0];

    // 1) Logs (graceful fallback if stats_excluded isn't migrated).
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

    // 2) workout_features for those logs (intensity drives key-pace).
    let features: TimelineFeature[] = [];
    const logIds = logs.map((l) => l.id);
    if (logIds.length > 0) {
      const featRes = await supabase
        .from("workout_features")
        .select("training_log_id, intensity_score, total_duration_seconds")
        .in("training_log_id", logIds);
      // Features are an optimization — a failure degrades to the
      // workout_type fallback rather than failing the request.
      if (!featRes.error) {
        features = (featRes.data ?? []) as TimelineFeature[];
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

    // 4) Athlete pace zones (the quality boundary + rep classification).
    const zones = await fetchPaceZones(userId);

    // Rep-level laps (native/derived + the athlete's fix-reps correction) and
    // the work-bout key pace they yield — so A3 ("the engine is growing")
    // trends the 5:10 reps, not the 6:20 whole-workout blend. Same helper
    // trends-timeline uses, so the card can never disagree with the chart.
    const lapsByWorkout = await fetchQualityLaps(supabase, userId, logIds);
    let keyWorkPaceByLog = new Map<string, number>();
    try {
      const keyLogs = logs.map((l) => ({
        id: l.id,
        workout_date: l.workout_date,
        workout_distance_miles: l.workout_distance_miles,
        workout_duration_minutes: l.workout_duration_minutes ?? null,
      }));
      const sessions = buildKeySessions(keyLogs, lapsByWorkout, new Map(), zones);
      keyWorkPaceByLog = new Map(
        sessions.filter((s) => s.kind === "quality" && s.work_pace_sec > 0)
          .map((s) => [s.log_id, s.work_pace_sec]),
      );
    } catch (e) {
      console.error("[trends-insights] key work pace skipped:", e);
    }

    // Build the SAME weekly substrate the chart renders — now with the corrected
    // rep pace, so a card can't disagree with the ladder.
    const timelineInput = {
      logs, features, mentions,
      mpSecPerMile: zones.mp ?? null,
      lapsByWorkout,
      keyWorkPaceByLog,
    };
    const timeline = buildTrendsTimeline(timelineInput, weeks);
    // Daily substrate — only A4 (weekday rhythm) reads it; same builder the
    // calendar uses, so the card can't disagree with the grid.
    const days = buildDailyTimeline(timelineInput, weeks);

    // 5) Per-second streams for Group B (HR × pace, decoupling, rep recovery).
    //    Capped + fetched in parallel — the blobs are large (~65 KB each). Any
    //    failure degrades to zero B cards, never a failed request or a slow one
    //    that the client cancels on a tab switch.
    const streamRuns = await buildStreamRuns(userId, logs, timeline).catch((e) => {
      console.error("[trends-insights] stream fetch failed, skipping Group B:", e);
      return [] as StreamRun[];
    });

    const cards = runDetectors({ weeks: timeline, mentions, streamRuns, days });

    return new Response(
      JSON.stringify({ cards, generated_at: new Date().toISOString() }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("[trends-insights] error:", err);
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

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const NON_RUNNING = new Set(["cross_training", "strength", "rest"]);
const STREAM_CAP = 60; // most-recent running logs to pull streams for (blobs ~65 KB each)

function chunkArray<T>(xs: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < xs.length; i += size) out.push(xs.slice(i, i + size));
  return out;
}

/** The week window a run's date lands in, and that week's label. */
function weekIndexFor(weeks: TrendsWeekOut[], dateStr: string): { idx: number; label: string } {
  const t = dayMs(dateStr);
  for (let i = 0; i < weeks.length; i++) {
    const s = dayMs(weeks[i].week_start);
    if (t >= s && t < s + WEEK_MS) return { idx: i, label: weeks[i].date_label };
  }
  return { idx: -1, label: "" };
}

/**
 * Build the Group-B `StreamRun[]`: per-second HR / velocity / cadence for the
 * window's running logs, plus work-rep end indices for HRR60. Capped to the
 * most recent `STREAM_CAP` runs and chunked, since `external_streams` blobs
 * are heavy; a partial fetch simply yields fewer B cards.
 */
async function buildStreamRuns(
  userId: string,
  logs: TimelineLog[],
  weeks: TrendsWeekOut[],
): Promise<StreamRun[]> {
  const runLogs = logs
    .filter((l) => !NON_RUNNING.has((l.workout_type ?? "").toLowerCase()) && (l.workout_distance_miles ?? 0) > 0)
    .sort((a, b) => String(b.workout_date).localeCompare(String(a.workout_date)));

  const capped = runLogs.slice(0, STREAM_CAP);
  if (capped.length < runLogs.length) {
    console.log(`[trends-insights] stream fetch capped at ${STREAM_CAP} of ${runLogs.length} runs`);
  }
  const ids = capped.map((l) => l.id);
  if (ids.length === 0) return [];

  // Streams, chunked small (blobs are large) and fetched in PARALLEL — the
  // sequential version was slow enough that the client cancelled on tab switch.
  const streamsById = new Map<string, Record<string, unknown>>();
  const streamChunks: string[][] = [];
  for (let i = 0; i < ids.length; i += 15) streamChunks.push(ids.slice(i, i + 15));
  const streamResults = await Promise.all(
    streamChunks.map((chunk) =>
      supabase.from("training_logs").select("id, external_streams").eq("user_id", userId).in("id", chunk)
    ),
  );
  for (const { data, error } of streamResults) {
    if (error) continue;
    for (const row of (data ?? []) as Array<Record<string, unknown>>) {
      const es = row.external_streams as Record<string, unknown> | null;
      if (es) streamsById.set(String(row.id), es);
    }
  }

  // Work-rep end indices (is_rest=false laps with a stream_end_index).
  const repEndsById = new Map<string, number[]>();
  const lapResults = await Promise.all(
    chunkArray(ids, 200).map((chunk) =>
      supabase
        .from("running_workout_laps")
        .select("workout_id, is_rest, stream_end_index")
        .eq("user_id", userId)
        .in("workout_id", chunk)
        .order("lap_index", { ascending: true })
    ),
  );
  for (const { data, error } of lapResults) {
    if (error) continue;
    for (const lap of (data ?? []) as Array<Record<string, unknown>>) {
      if (lap.is_rest === true) continue;
      const end = lap.stream_end_index;
      if (typeof end !== "number") continue;
      const wid = String(lap.workout_id);
      const arr = repEndsById.get(wid) ?? [];
      arr.push(end);
      repEndsById.set(wid, arr);
    }
  }

  const out: StreamRun[] = [];
  for (const l of capped) {
    const es = streamsById.get(l.id);
    if (!es) continue;
    const hr = pickStream(es, "heartrate");
    const vel = pickStream(es, "velocity_smooth");
    if (hr.length === 0 || vel.length === 0) continue; // B needs both
    const { idx, label } = weekIndexFor(weeks, String(l.workout_date));
    out.push({
      logId: l.id,
      date: String(l.workout_date),
      type: l.workout_type ?? null,
      weekIndex: idx,
      weekLabel: label,
      time: pickStream(es, "time"),
      hr,
      vel,
      cadence: pickStream(es, "cadence"),
      repEndIdx: repEndsById.get(l.id) ?? [],
    });
  }
  return out;
}

/** The athlete's full pace zones from `athlete_state.pace_zones` — the boundary
 *  for quality + rep classification. Mirrors `trends-timeline.fetchPaceZones`. */
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
