/**
 * compare-workouts — "The Effort" comparison tool (Trends).
 *
 * Spec: workoutcomparisonspec.md. Two strictly separated layers:
 *
 *   Layer 1 (deterministic, `_shared/workoutComparison.ts`): segment both
 *   workouts via the canonical `segmentFromLaps`, align the comparable
 *   bouts, compute the structured diff + comparability score. Math, never
 *   AI. Every number in the response is auditable or explicitly absent.
 *
 *   Layer 2 (advisory, `workout-comparison-verdict.v1`): the model reads
 *   the Layer-1 fact lines and writes the coach's read — one sentence plus
 *   at most one caveat. It cannot introduce a number that isn't in Layer 1:
 *   every numeric token in its output is checked against the fact lines and
 *   ANY violation (or parse failure, or a missing API key) falls back to
 *   the bare diff with `annotated: false`. The diff always renders; the
 *   verdict is a bonus, never a dependency. AI advises, never acts —
 *   nothing here writes to the DB.
 *
 * Two front doors, one engine (spec):
 *   • Auto  — body `{ workout_id }`: the function scans prior quality
 *     sessions (last 180 days, features-prefiltered) and picks the fairest
 *     comparison. 404-style `no_candidate` result when nothing qualifies.
 *   • Manual — body `{ workout_id, compare_to_id }`: any two workouts.
 *     Never refuses on a mismatch — the comparability score and hedged
 *     verdict say how loosely to read it. The only refusal is an
 *     unreadable session ("couldn't read this session's structure").
 *
 * Request body:
 *   { workout_id: string, compare_to_id?: string }
 *
 * Response:
 *   { success: true, mode: "auto" | "manual", annotated: boolean,
 *     comparison: ComparisonResult, verdict: { verdict, caveat } | null,
 *     suggestion?: { id, score, confidence } }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";

import { corsHeaders } from "../_shared/cors.ts";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { captureException, flushSentry } from "../_shared/sentry.ts";
import type { PaceZones } from "../_shared/workoutSegmentation.ts";
import {
  allowedNumberTokens,
  compareWorkouts,
  findBestComparison,
  firstDisallowedNumber,
  verdictNumbersAllowed,
  RECENCY_FLOOR_DAYS,
  type ComparisonLap,
  type ComparisonWorkout,
} from "../_shared/workoutComparison.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

/** Max prior sessions we pull laps for in auto mode — the top feature-ranked
 *  matches (all workout types), not a blanket recent-N. */
const MAX_AUTO_CANDIDATES = 12;
// v2 verdict is a short analysis (2–4 sentences), not a single line.
const MAX_VERDICT_CHARS = 700;
const MAX_CAVEAT_CHARS = 200;

const LAP_COLUMNS =
  "workout_id, lap_index, is_rest, distance_meters, avg_pace_sec_per_mile, moving_time_seconds, elapsed_time_seconds, avg_heart_rate, heat_adjusted_pace_sec_per_mile, heat_category, total_elevation_gain";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

interface LogRow {
  id: string;
  workout_date: string;
  weather_actual: Record<string, unknown> | null;
}

/** Athlete pace zones from athlete_state — same graceful-degradation shape
 *  as compute-workout-features (`fetchPaceZones`). */
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

/** Laps for a set of workouts, grouped by workout_id (chunked IN lists). */
async function fetchLapsByWorkout(
  userId: string,
  workoutIds: string[],
): Promise<Map<string, ComparisonLap[]>> {
  const byId = new Map<string, ComparisonLap[]>();
  for (let i = 0; i < workoutIds.length; i += 200) {
    const chunk = workoutIds.slice(i, i + 200);
    const { data, error } = await supabase
      .from("running_workout_laps")
      .select(LAP_COLUMNS)
      .eq("user_id", userId)
      .in("workout_id", chunk)
      .order("lap_index", { ascending: true });
    if (error) throw new Error(`Failed to fetch laps: ${error.message}`);
    for (const lap of (data ?? []) as Array<Record<string, unknown>>) {
      const wid = String(lap.workout_id);
      const arr = byId.get(wid) ?? [];
      arr.push(lap as ComparisonLap);
      byId.set(wid, arr);
    }
  }
  return byId;
}

/** `workout_features.workout_structure` labels for the compared logs. */
async function fetchStructureLabels(
  userId: string,
  logIds: string[],
): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const { data } = await supabase
    .from("workout_features")
    .select("training_log_id, workout_structure")
    .eq("user_id", userId)
    .in("training_log_id", logIds);
  for (const row of data ?? []) {
    if (typeof row.workout_structure === "string" && row.workout_structure.trim()) {
      out.set(String(row.training_log_id), row.workout_structure.trim());
    }
  }
  return out;
}

function toComparisonWorkout(
  log: LogRow,
  laps: ComparisonLap[] | undefined,
  structureLabel?: string | null,
): ComparisonWorkout {
  const wx = log.weather_actual;
  return {
    id: log.id,
    workout_date: log.workout_date,
    laps: laps ?? [],
    weather: wx && typeof wx === "object"
      ? {
        temp_f: typeof wx.temp_f === "number" ? wx.temp_f : null,
        dew_point_f: typeof wx.dew_point_f === "number" ? wx.dew_point_f : null,
        heat_category: typeof wx.heat_category === "string" ? wx.heat_category : null,
      }
      : null,
    structure_label: structureLabel ?? null,
  };
}

const FEATURE_COLUMNS =
  "training_log_id, workout_date, total_distance_miles, avg_pace_seconds, total_duration_seconds, easy_seconds, moderate_seconds, threshold_seconds, hard_seconds, workout_structure";

interface FeatureRow {
  training_log_id: string;
  workout_date: string;
  total_distance_miles: number | null;
  avg_pace_seconds: number | null;
  total_duration_seconds: number | null;
  easy_seconds: number | null;
  moderate_seconds: number | null;
  threshold_seconds: number | null;
  hard_seconds: number | null;
  workout_structure: string | null;
}

/** Coarse workout type from the zone-seconds distribution — the bucket holding
 *  the most time. Cheap pre-rank signal; the precise dominant Zone is derived
 *  from laps in the final scoring pass. */
function dominantBucket(f: FeatureRow): "hard" | "threshold" | "moderate" | "easy" {
  const buckets: Array<["hard" | "threshold" | "moderate" | "easy", number]> = [
    ["hard", Number(f.hard_seconds ?? 0)],
    ["threshold", Number(f.threshold_seconds ?? 0)],
    ["moderate", Number(f.moderate_seconds ?? 0)],
    ["easy", Number(f.easy_seconds ?? 0)],
  ];
  buckets.sort((a, b) => b[1] - a[1]);
  return buckets[0][1] > 0 ? buckets[0][0] : "easy";
}

const ADJACENT_BUCKETS: ReadonlyArray<ReadonlySet<string>> = [
  new Set(["easy", "moderate"]),
  new Set(["threshold", "hard"]),
  new Set(["moderate", "threshold"]),
];

/**
 * Cheap feature-only similarity for pre-ranking candidates without touching
 * laps — the five athlete-facing signals (type, distance, pace, volume,
 * structure) straight off `workout_features`. Surfaces the top handful; the
 * lap-based `scoreComparability` makes the final call.
 */
function featureSimilarity(t: FeatureRow, c: FeatureRow): number {
  // Type (dominant bucket): exact = 1, adjacent = 0.5, else 0.
  const tb = dominantBucket(t), cb = dominantBucket(c);
  let typeS = 0;
  if (tb === cb) typeS = 1;
  else if (ADJACENT_BUCKETS.some((s) => s.has(tb) && s.has(cb))) typeS = 0.5;

  // Distance/volume band.
  const td = Number(t.total_distance_miles ?? 0), cd = Number(c.total_distance_miles ?? 0);
  let distS = 0;
  if (td > 0 && cd > 0) {
    const ratio = Math.min(td, cd) / Math.max(td, cd);
    distS = ratio >= 0.7 ? 1 : Math.max(0, (ratio - 0.35) / (0.7 - 0.35));
  }

  // Pace proximity.
  const tp = Number(t.avg_pace_seconds ?? 0), cp = Number(c.avg_pace_seconds ?? 0);
  let paceS = 0;
  if (tp > 0 && cp > 0) {
    const gap = Math.abs(tp - cp);
    paceS = gap <= 15 ? 1 : gap >= 90 ? 0 : 1 - (gap - 15) / (90 - 15);
  }

  // Structure (tie-break only).
  const ts = (t.workout_structure ?? "").trim().toLowerCase();
  const cs = (c.workout_structure ?? "").trim().toLowerCase();
  const structS = ts && cs && ts === cs ? 1 : 0;

  return typeS * 0.4 + distS * 0.25 + paceS * 0.25 + structS * 0.1;
}

/**
 * Auto mode candidates across ALL workout types (2026-07-20, Rio: "find all
 * types of similar workout types, even easy ones"). Scans the recency window on
 * `workout_features`, pre-ranks every prior session by feature similarity to the
 * target (type/distance/pace/volume/structure), and returns the top handful —
 * so we pull laps for ~10 likely matches, not six months of runs. Falls back to
 * most-recent when the target has no features row yet.
 */
async function fetchAutoCandidates(
  userId: string,
  target: LogRow,
): Promise<LogRow[]> {
  const targetTime = new Date(target.workout_date).getTime();
  const windowStart = new Date(targetTime - RECENCY_FLOOR_DAYS * 86400000)
    .toISOString();

  const [{ data: targetFeat }, { data, error }] = await Promise.all([
    supabase
      .from("workout_features")
      .select(FEATURE_COLUMNS)
      .eq("user_id", userId)
      .eq("training_log_id", target.id)
      .maybeSingle(),
    supabase
      .from("workout_features")
      .select(FEATURE_COLUMNS)
      .eq("user_id", userId)
      .gte("workout_date", windowStart)
      .lt("workout_date", target.workout_date)
      .order("workout_date", { ascending: false })
      .limit(300),
  ]);
  if (error) throw new Error(`Failed to fetch candidates: ${error.message}`);

  const rows = ((data ?? []) as FeatureRow[])
    .filter((f) => String(f.training_log_id) !== target.id);
  if (rows.length === 0) return [];

  // Pre-rank by feature similarity when the target's features exist; otherwise
  // fall back to recency (rows already come newest-first).
  const ranked = targetFeat
    ? rows
      .map((c) => ({ id: String(c.training_log_id), s: featureSimilarity(targetFeat as FeatureRow, c) }))
      .sort((a, b) => b.s - a.s)
    : rows.map((c) => ({ id: String(c.training_log_id), s: 0 }));
  const topIds = ranked.slice(0, MAX_AUTO_CANDIDATES).map((r) => r.id);
  if (topIds.length === 0) return [];

  const { data: logs, error: logsError } = await supabase
    .from("training_logs")
    .select("id, workout_date, weather_actual")
    .eq("user_id", userId)
    .in("id", topIds);
  if (logsError) throw new Error(`Failed to fetch candidate logs: ${logsError.message}`);
  return (logs ?? []) as LogRow[];
}

// ── Layer-2 verdict (validated; falls back to the bare diff) ──

interface Verdict {
  verdict: string;
  caveat: string | null;
}

/**
 * Parse + validate the model output. Returns null on ANY violation —
 * unparseable JSON, wrong shapes, over-length text, or a numeric token not
 * present in the Layer-1 fact lines — so the caller falls back to the
 * unannotated diff. Same wholesale-rejection discipline as
 * suggest-workout-progression's `validateRanking`.
 */
export function validateVerdict(
  text: string,
  factLines: string[],
): Verdict | null {
  let raw = text.trim();
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenced) raw = fenced[1].trim();

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object") return null;
  const { verdict, caveat } = parsed as { verdict?: unknown; caveat?: unknown };

  if (typeof verdict !== "string" || verdict.trim().length === 0) return null;
  const cleanVerdict = verdict.trim();
  if (cleanVerdict.length > MAX_VERDICT_CHARS) return null;

  let cleanCaveat: string | null = null;
  if (caveat != null) {
    if (typeof caveat !== "string") return null;
    const t = caveat.trim();
    if (t.length > MAX_CAVEAT_CHARS) return null;
    cleanCaveat = t.length > 0 ? t : null;
  }

  // The hard Layer-2 rule: no number the diff doesn't contain.
  const allowed = allowedNumberTokens(factLines);
  const combined = cleanCaveat ? `${cleanVerdict} ${cleanCaveat}` : cleanVerdict;
  if (!verdictNumbersAllowed(combined, allowed)) return null;

  return { verdict: cleanVerdict, caveat: cleanCaveat };
}

async function generateVerdict(
  factLines: string[],
  confidence: string,
): Promise<Verdict | null> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    // Advisory layer only — the diff still renders without it.
    console.error("compare-workouts: GEMINI_API_KEY not configured");
    return null;
  }
  try {
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
    const prompt = loadPrompt("workout-comparison-verdict.v2", {
      factLines: factLines.join("\n"),
      confidence,
    });
    const result = await model.generateContent({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.2, maxOutputTokens: 1024 },
    });
    const rawText = result.response.text();
    const verdict = validateVerdict(rawText, factLines);
    // TEMP DIAGNOSTIC (2026-07-20): why is the read empty/weak? Log the raw
    // model output and, on rejection, the exact offending number. Remove once
    // the verdict is confirmed rendering in prod.
    if (!verdict) {
      const bad = firstDisallowedNumber(rawText, allowedNumberTokens(factLines));
      console.error(
        `compare-workouts VERDICT REJECTED. offendingNumber=${bad ?? "none (parse/shape/length)"} rawLen=${rawText.length} raw=${rawText.slice(0, 500)}`,
      );
    } else {
      console.log(`compare-workouts VERDICT OK. len=${verdict.verdict.length} text=${verdict.verdict.slice(0, 300)}`);
    }
    return verdict;
  } catch (llmError) {
    console.error("compare-workouts: LLM call failed", llmError);
    return null;
  }
}

// ── Handler ──

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const userId = await getAuthenticatedUser(req);
    if (!userId) return unauthorizedResponse(corsHeaders);

    const rlBlocked = await enforceFeatureRateLimit(userId, "workout_comparison", corsHeaders);
    if (rlBlocked) return rlBlocked;
    const monthlyCapped = await enforceMonthlyCap(userId, "workout_comparison", corsHeaders);
    if (monthlyCapped) return monthlyCapped;

    const body = await req.json().catch(() => null);
    const workoutId = body?.workout_id;
    const compareToId = body?.compare_to_id;
    if (typeof workoutId !== "string" || workoutId.length === 0) {
      return jsonResponse({ error: "Missing required field: workout_id" }, 400);
    }
    if (compareToId != null && (typeof compareToId !== "string" || compareToId.length === 0)) {
      return jsonResponse({ error: "compare_to_id must be a non-empty string" }, 400);
    }
    if (compareToId === workoutId) {
      return jsonResponse({ error: "Cannot compare a workout to itself" }, 400);
    }
    const mode: "auto" | "manual" = compareToId ? "manual" : "auto";

    // Target log — scoped to the authenticated athlete, always.
    const { data: targetLog, error: targetError } = await supabase
      .from("training_logs")
      .select("id, workout_date, weather_actual")
      .eq("user_id", userId)
      .eq("id", workoutId)
      .maybeSingle();
    if (targetError) throw new Error(`Failed to fetch workout: ${targetError.message}`);
    if (!targetLog) return jsonResponse({ error: "Workout not found" }, 404);
    const target = targetLog as LogRow;

    const zones = await fetchPaceZones(userId);

    // Resolve the other side of the pair.
    let other: LogRow | null = null;
    let suggestion: { id: string; score: number; confidence: string } | null = null;

    if (mode === "manual") {
      const { data: otherLog, error: otherError } = await supabase
        .from("training_logs")
        .select("id, workout_date, weather_actual")
        .eq("user_id", userId)
        .eq("id", compareToId)
        .maybeSingle();
      if (otherError) throw new Error(`Failed to fetch comparison workout: ${otherError.message}`);
      if (!otherLog) return jsonResponse({ error: "Comparison workout not found" }, 404);
      other = otherLog as LogRow;
    } else {
      const candidates = await fetchAutoCandidates(userId, target);
      if (candidates.length > 0) {
        const lapsByWorkout = await fetchLapsByWorkout(userId, [
          target.id,
          ...candidates.map((c) => c.id),
        ]);
        const best = findBestComparison(
          toComparisonWorkout(target, lapsByWorkout.get(target.id)),
          candidates.map((c) => toComparisonWorkout(c, lapsByWorkout.get(c.id))),
          zones,
        );
        if (best) {
          other = candidates.find((c) => c.id === best.id) ?? null;
          suggestion = { id: best.id, score: best.score, confidence: best.confidence };
        }
      }
      if (!other) {
        // Honest empty state: nothing fair to compare against. The client
        // falls back to the manual two-slot picker.
        return jsonResponse({
          success: true,
          mode,
          annotated: false,
          comparison: null,
          verdict: null,
          no_candidate: true,
        });
      }
    }

    // Laps + display labels, then the deterministic Layer-1 engine.
    const lapsByWorkout = await fetchLapsByWorkout(userId, [target.id, other.id]);
    const labels = await fetchStructureLabels(userId, [target.id, other.id]);
    const comparison = compareWorkouts(
      toComparisonWorkout(target, lapsByWorkout.get(target.id), labels.get(target.id)),
      toComparisonWorkout(other, lapsByWorkout.get(other.id), labels.get(other.id)),
      zones,
    );

    // Unreadable session → the diff cannot exist; say so, never compare
    // garbage (spec guardrail). 200 because the request itself succeeded.
    if (!comparison.ok) {
      return jsonResponse({
        success: true,
        mode,
        annotated: false,
        comparison,
        verdict: null,
        ...(suggestion ? { suggestion } : {}),
      });
    }

    // Layer 2 — advisory verdict on top of the facts. Any failure → bare diff.
    const verdict = await generateVerdict(
      comparison.factLines!,
      comparison.comparability!.confidence,
    );

    return jsonResponse({
      success: true,
      mode,
      annotated: verdict != null,
      comparison,
      verdict,
      ...(suggestion ? { suggestion } : {}),
    });
  } catch (error) {
    console.error("compare-workouts error:", error);
    captureException(error, { fn: "compare-workouts" });
    await flushSentry();
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: "Failed to compare workouts", details: message }, 500);
  }
});
