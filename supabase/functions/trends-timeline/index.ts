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

const LOG_COLS_BASE =
  "id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, mood, source";

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

    // 2) workout_features for those logs (intensity). Skipped when no logs.
    let features: TimelineFeature[] = [];
    const logIds = logs.map((l) => l.id);
    if (logIds.length > 0) {
      const featRes = await supabase
        .from("workout_features")
        .select("training_log_id, intensity_score, total_duration_seconds")
        .in("training_log_id", logIds);
      // Features are an optimization — a failure here degrades to the
      // workout_type fallback rather than failing the whole request.
      if (!featRes.error) features = (featRes.data ?? []) as TimelineFeature[];
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

    const timeline = buildTrendsTimeline({ logs, features, mentions }, weeks);
    const flagged = flaggedRuns(logs);
    const trimmed = trimmedRuns(logs);

    return new Response(
      JSON.stringify({ weeks: timeline, flagged, trimmed, generated_at: new Date().toISOString() }),
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
