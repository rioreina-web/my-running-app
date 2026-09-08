/**
 * compute-fitness-snapshot
 *
 * Server-side writer for `fitness_snapshots`. Historically snapshots were only
 * written by the iOS app, on-device, when a user opened the predictor screen —
 * so the nightly athlete-state rebuild and the Coach Read read stale-or-absent
 * fitness data. This worker regenerates a snapshot for an athlete using the
 * SAME algorithm the app shows (ported to _shared/fitnessPrediction.ts), so the
 * app and server never diverge. See
 * outputs/fitness-snapshot-writer-diagnosis-2026-07-02.md.
 *
 * Modes (mirrors rebuild-athlete-state):
 *   { user_id }  — compute one athlete. The nightly cron fans out one
 *                  http_post per active athlete.
 *   { batch: N } — compute up to N active athletes (a workout in the last 45d).
 *
 * Upsert semantics match the iOS app: at most one row per calendar day per
 * user — today's row is updated if it exists, otherwise inserted.
 *
 * Auth: service-role only (decoded-claim check), like the drain-* workers and
 * rebuild-athlete-state. The upsert runs under the service-role admin client so
 * RLS never blocks it.
 */

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import {
  generateFitnessPrediction,
  RACE_TYPE_LABEL,
  RACE_TYPE_TOLERANCE,
  type RaceType,
} from "../_shared/fitnessPrediction.ts";
// The assembly moved to _shared so the backtest harness can replay the SAME
// inputs rather than re-implementing the fetch (2026-08-24). Production passes
// no options, which is byte-for-byte the previous behavior.
import { buildPredictionInput, num, RACE_TYPE_MILES } from "../_shared/fitnessInputs.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(supabaseUrl, supabaseServiceKey);

const DEFAULT_BATCH = 25;
const MAX_BATCH = 100;
const ACTIVE_LOOKBACK_DAYS = 45;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);
  const token = authHeader.slice("Bearer ".length).trim();
  if (!isServiceRoleJWT(token)) return json({ error: "Service role required" }, 403);

  let body: { user_id?: string; batch?: number } = {};
  try {
    body = (await req.json()) as { user_id?: string; batch?: number };
  } catch {
    /* empty body ok */
  }

  const start = Date.now();

  // --- Single-athlete mode (nightly cron fan-out) ---
  if (body.user_id !== undefined) {
    const userId = body.user_id.trim();
    if (!userId) return json({ error: "empty user_id" }, 400); // guards the empty-id bug
    try {
      const result = await computeAndUpsert(admin, userId);
      return json({ user_id: userId, ...result, elapsed_ms: Date.now() - start });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`compute-fitness-snapshot: ${userId} failed:`, msg);
      return json({ error: `compute failed: ${msg}` }, 500);
    }
  }

  // --- Batch mode (manual / backfill) ---
  const batch = Math.min(Math.max(1, body.batch ?? DEFAULT_BATCH), MAX_BATCH);
  const sinceDate = new Date(Date.now() - ACTIVE_LOOKBACK_DAYS * 86400000).toISOString().slice(0, 10);

  const { data: activeRows, error: activeErr } = await admin
    .from("training_logs")
    .select("user_id")
    .gte("workout_date", sinceDate)
    .not("user_id", "is", null)
    .limit(5000);
  if (activeErr) return json({ error: activeErr.message }, 500);

  const activeIds = [...new Set((activeRows ?? []).map((r) => r.user_id as string).filter((id) => id && id.trim()))].slice(0, batch);

  let written = 0;
  let skipped = 0;
  const errors: string[] = [];
  for (const id of activeIds) {
    try {
      const res = await computeAndUpsert(admin, id);
      if (res.wrote) written++;
      else skipped++;
    } catch (e) {
      errors.push(`${id}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  return json({ active: activeIds.length, written, skipped, errors: errors.slice(0, 5), elapsed_ms: Date.now() - start });
});

// ---------------------------------------------------------------------------
// Core: fetch inputs → run the ported predictor → upsert today's row.
// ---------------------------------------------------------------------------

async function computeAndUpsert(
  db: SupabaseClient,
  userId: string,
): Promise<{ wrote: boolean; reason?: string; confidence?: string; estimated_10k_pace_seconds?: number; race_candidates_tagged?: number }> {
  const now = new Date();
  const { input, logRows } = await buildPredictionInput(db, userId, now);
  const prediction = generateFitnessPrediction(input);

  if (!prediction) return { wrote: false, reason: "no usable fitness signal" };

  const rowData = {
    user_id: userId,
    predicted_mile_seconds: prediction.predictedMileSeconds,
    predicted_5k_seconds: prediction.predicted5kSeconds,
    predicted_10k_seconds: prediction.predicted10kSeconds,
    predicted_half_seconds: prediction.predictedHalfSeconds,
    predicted_marathon_seconds: prediction.predictedMarathonSeconds,
    estimated_10k_pace_seconds: prediction.estimated10kPaceSeconds,
    confidence: prediction.confidence,
    confidence_tier: prediction.confidenceTier,
    data_source: prediction.dataSource,
    workout_count: prediction.workoutCount,
    range_mile_seconds: prediction.rangeMileSeconds,
    range_5k_seconds: prediction.range5kSeconds,
    range_10k_seconds: prediction.range10kSeconds,
    range_half_seconds: prediction.rangeHalfSeconds,
    range_marathon_seconds: prediction.rangeMarathonSeconds,
    // The anchor, persisted (migration 20260817210000). This is the whole
    // point of the canonical row: consumers read what the estimate rests on
    // instead of re-picking and re-normalizing a race themselves. Raw is
    // what she ran; neutral is what it proves — never swap them.
    anchor_race_log_id: prediction.anchor?.sourceWorkoutId ?? null,
    anchor_distance_key: prediction.anchor?.distanceKey ?? null,
    anchor_raw_seconds: prediction.anchor?.rawSeconds ?? null,
    anchor_neutral_seconds: prediction.anchor?.neutralSeconds ?? null,
    anchor_date: prediction.anchor?.date ?? null,
    anchor_weeks_ago: prediction.anchor?.weeksAgo ?? null,
    anchor_conditions: prediction.anchor?.conditions ?? null,
    lifetime_prs: prediction.lifetimePRs ?? null,
    // The last two things the device still computed for itself (migration
    // 20260817220000). Persisting them lets iOS delete its duplicate model
    // rather than run 851 lines to produce a summary line and two counts.
    summary: prediction.summary ?? null,
    supporting_training: prediction.supportingTraining ?? null,
    // The workings (migration 20260817230000) — every stage between the anchor
    // and the published number, so tuning arguments can be settled by query.
    diagnostics: prediction.diagnostics ?? null,
  };

  // Upsert today's row (one per calendar day), matching the iOS behavior.
  const startOfToday = new Date(now);
  startOfToday.setUTCHours(0, 0, 0, 0);
  const { data: todayRow } = await db
    .from("fitness_snapshots")
    .select("id")
    .eq("user_id", userId)
    .gte("created_at", startOfToday.toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (todayRow?.id) {
    const { error } = await db.from("fitness_snapshots").update(rowData).eq("id", todayRow.id);
    if (error) throw new Error(`update: ${error.message}`);
  } else {
    const { error } = await db.from("fitness_snapshots").insert(rowData);
    if (error) throw new Error(`insert: ${error.message}`);
  }

  // ── Race-candidate gathering (2026-07-17) ──
  // Detection-not-decision: runs that LOOK like races (standard distance,
  // ≥15% faster than the athlete's average) get tagged on their own log row
  // (`extracted_data.race_candidate`, status "pending") for the app to ask
  // "was this a race?". Confirm → the app writes race_result and the race
  // joins the anchors; dismiss → status "dismissed", never asked again.
  // Best-effort: a failure here must never block the snapshot write.
  let candidatesTagged = 0;
  try {
    candidatesTagged = await tagRaceCandidates(db, userId, logRows ?? [], now);
  } catch (e) {
    console.error(`race-candidate tagging failed (non-fatal): ${(e as Error).message}`);
  }

  return {
    wrote: true,
    confidence: prediction.confidence,
    estimated_10k_pace_seconds: prediction.estimated10kPaceSeconds,
    race_candidates_tagged: candidatesTagged,
  };
}

// ---------------------------------------------------------------------------
// Race-candidate detection (2026-07-17). Mirrors the model's Phase-2 GPS race
// detection thresholds (standard distance ± tolerance, pace ≥15% faster than
// the athlete's average) but runs against raw rows so candidates can be tagged
// back onto their source training_logs row.
// ---------------------------------------------------------------------------

async function tagRaceCandidates(
  db: SupabaseClient,
  userId: string,
  rows: Array<Record<string, unknown>>,
  now: Date,
): Promise<number> {
  // Athlete's average pace over the fetched window (all runs, any type).
  const paces: number[] = [];
  for (const row of rows) {
    const miles = num(row.workout_distance_miles);
    const durationMinutes = num(row.workout_duration_minutes);
    if (miles > 0.5 && durationMinutes > 0) paces.push((durationMinutes * 60) / miles);
  }
  if (paces.length < 10) return 0; // not enough context to call anything "fast"
  const avgPace = paces.reduce((s, p) => s + p, 0) / paces.length;

  const candidates: Array<{ id: string; raceType: RaceType; finishSeconds: number }> = [];
  for (const row of rows) {
    if (String(row.workout_type ?? "") === "race") continue;
    if (row.race_result != null) continue;
    const miles = num(row.workout_distance_miles);
    const durationMinutes = num(row.workout_duration_minutes);
    if (!(miles > 0.5 && durationMinutes > 0) || !row.id) continue;
    const pace = (durationMinutes * 60) / miles;
    if (pace >= avgPace * 0.85) continue; // not a race-level effort

    for (const rt of Object.keys(RACE_TYPE_MILES) as RaceType[]) {
      if (Math.abs(miles - RACE_TYPE_MILES[rt]) <= RACE_TYPE_TOLERANCE[rt]) {
        candidates.push({ id: String(row.id), raceType: rt, finishSeconds: Math.round(durationMinutes * 60) });
        break;
      }
    }
  }
  if (candidates.length === 0) return 0;

  // Only tag rows that have never been asked about (any prior status stands).
  const { data: existing } = await db
    .from("training_logs")
    .select("id, extracted_data")
    .in("id", candidates.map((c) => c.id));
  const extractedById = new Map<string, Record<string, unknown>>();
  for (const row of existing ?? []) {
    extractedById.set(String(row.id), (row.extracted_data as Record<string, unknown>) ?? {});
  }

  let tagged = 0;
  for (const c of candidates) {
    const extracted = extractedById.get(c.id) ?? {};
    if (extracted.race_candidate != null) continue;
    const merged = {
      ...extracted,
      race_candidate: {
        race_type: c.raceType,
        race_label: RACE_TYPE_LABEL[c.raceType],
        finish_time_seconds: c.finishSeconds,
        detected_at: now.toISOString(),
        status: "pending",
      },
    };
    const { error } = await db
      .from("training_logs")
      .update({ extracted_data: merged })
      .eq("id", c.id)
      .eq("user_id", userId);
    if (!error) tagged++;
  }
  return tagged;
}

// ---------------------------------------------------------------------------
// Response + auth helpers. The snake_case→camelCase mapping helpers moved to
// _shared/fitnessInputs.ts with the assembly (2026-08-24).
// ---------------------------------------------------------------------------

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** True if `token` is a non-expired service-role JWT (signature already
 *  verified by the gateway; we only read the claims). */
function isServiceRoleJWT(token: string): boolean {
  try {
    const seg = token.split(".")[1];
    if (!seg) return false;
    const b64 = seg.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(seg.length / 4) * 4, "=");
    const payload = JSON.parse(atob(b64)) as { role?: string; exp?: number };
    if (payload.role !== "service_role") return false;
    if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now()) return false;
    return true;
  } catch {
    return false;
  }
}
