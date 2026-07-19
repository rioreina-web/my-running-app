import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
import { captureException, flushSentry } from "../_shared/sentry.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import {
  segmentFromLaps,
  segmentFromPaceSegments,
  segmentFromOverall,
  ZONE_WEIGHTS,
  type LapInput,
  type PaceSegmentInput,
  type PaceZones,
  type SegmentationResult,
} from "../_shared/workoutSegmentation.ts";
import { deriveWorkoutNotes } from "../_shared/workout-notes.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// ============================================================================
// Workout Feature Computation (WS1 rewrite)
//
// Sources intensity from rep-level `running_workout_laps` and classifies every
// bout by ACTUAL pace against the athlete's pace zones — via the shared
// _shared/workoutSegmentation.ts module (the same one athlete-state's
// execution block uses). The old path read per-mile `pace_segments` and a
// stored `effort` LABEL, which averaged rep structure into easy splits and
// scored quality work as easy. See the module header for the full story.
// ============================================================================

interface PaceSegment {
  effort: string;
  distance_miles: number;
  duration_seconds: number;
  pace_per_mile: string | null;
  avg_heart_rate?: number | null;
}

interface TrainingLog {
  id: string;
  user_id: string;
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null;
  pace_segments: PaceSegment[] | null;
  workout_type: string | null;
  workout_notes: string | null;
  mood: string | null;
  source: string | null;
}

// Threshold + hard seconds above this floor marks a session as "quality" for
// the recovery-spacing read (avoids treating a few warmup strides as a hard day).
const QUALITY_SECONDS_FLOOR = 240;

/** Segment one workout, preferring rep-level laps, then per-mile segments,
 *  then an undifferentiated easy block. */
function segmentLog(
  log: TrainingLog,
  laps: LapInput[] | undefined,
  zones: PaceZones,
): SegmentationResult {
  if (laps && laps.length > 0) return segmentFromLaps(laps, zones);
  if (log.pace_segments && log.pace_segments.length > 0) {
    return segmentFromPaceSegments(log.pace_segments as PaceSegmentInput[], zones);
  }
  const durSec = (log.workout_duration_minutes || 0) * 60;
  return segmentFromOverall(durSec, log.workout_distance_miles || 0);
}

/** Is this session a hard day (drives hard-day spacing / recovery context)? */
function isQualitySession(seg: SegmentationResult): boolean {
  return seg.thresholdSeconds + seg.hardSeconds >= QUALITY_SECONDS_FLOOR;
}

// Compute features for a single workout from its segmentation.
function computeFeatures(
  log: TrainingLog,
  seg: SegmentationResult,
  prevWorkout: TrainingLog | null,
  prevHardWorkout: TrainingLog | null,
) {
  // --- Volume signals (from the logged totals, not the lap sum) ---
  const totalDistanceMiles = log.workout_distance_miles || 0;
  const totalDurationSeconds = (log.workout_duration_minutes || 0) * 60;
  const avgPaceSeconds = totalDistanceMiles > 0 && totalDurationSeconds > 0
    ? totalDurationSeconds / totalDistanceMiles
    : 0;

  // --- Intensity from segmentation (pace-classified bouts) ---
  const easySeconds = Math.round(seg.easySeconds);
  const moderateSeconds = Math.round(seg.moderateSeconds);
  const thresholdSeconds = Math.round(seg.thresholdSeconds);
  const hardSeconds = Math.round(seg.hardSeconds);
  const intensityScore = seg.intensityScore;
  const hardEffortMinutes = (thresholdSeconds + hardSeconds) / 60;

  // Peak pace = fastest work bout.
  const workPaces = seg.bouts.filter((b) => b.isWork && b.paceSecPerMile > 0).map((b) => b.paceSecPerMile);
  const peakPaceSeconds = workPaces.length > 0 ? Math.round(Math.min(...workPaces)) : null;

  // Pace variance = stdev of bout paces (work + easy), like the old metric.
  const boutPaces = seg.bouts.map((b) => b.paceSecPerMile).filter((p) => p > 0);
  let paceVariance = 0;
  if (boutPaces.length > 1) {
    const mean = boutPaces.reduce((a, b) => a + b, 0) / boutPaces.length;
    paceVariance = Math.sqrt(boutPaces.map((p) => (p - mean) ** 2).reduce((a, b) => a + b, 0) / boutPaces.length);
  }

  // Effort distribution: where is the hard work concentrated (front/back)?
  const intensities = seg.bouts.map((b) => ZONE_WEIGHTS[b.zone]);
  let effortDistribution = "even";
  if (intensities.length >= 3) {
    const mid = Math.floor(intensities.length / 2);
    const firstAvg = avg(intensities.slice(0, mid));
    const secondAvg = avg(intensities.slice(mid));
    const diff = secondAvg - firstAvg;
    if (diff > 0.5) effortDistribution = "back_loaded";
    else if (diff < -0.5) effortDistribution = "front_loaded";
    else if (paceVariance > 30) effortDistribution = "mixed";
  }

  // --- HR aggregation from bouts ---
  let hrSum = 0, hrCount = 0, hardHrSum = 0, hardHrCount = 0, easyHrSum = 0, easyHrCount = 0;
  let hasHrData = false;
  for (const b of seg.bouts) {
    if (b.avgHr != null && b.avgHr > 0) {
      hasHrData = true;
      hrSum += b.avgHr * b.seconds; hrCount += b.seconds;
      if (b.isWork) { hardHrSum += b.avgHr * b.seconds; hardHrCount += b.seconds; }
      else { easyHrSum += b.avgHr * b.seconds; easyHrCount += b.seconds; }
    }
  }
  const avgHeartRate = hrCount > 0 ? Math.round(hrSum / hrCount) : null;
  const hardEffortAvgHr = hardHrCount > 0 ? Math.round(hardHrSum / hardHrCount) : null;
  const easyEffortAvgHr = easyHrCount > 0 ? Math.round(easyHrSum / easyHrCount) : null;
  const hrPaceEfficiency = avgHeartRate && avgPaceSeconds > 0 ? avgHeartRate / avgPaceSeconds : null;

  // --- Recovery context ---
  let hoursSinceLastWorkout: number | null = null;
  let hoursSinceLastHard: number | null = null;
  if (prevWorkout?.workout_date) {
    hoursSinceLastWorkout =
      (new Date(log.workout_date).getTime() - new Date(prevWorkout.workout_date).getTime()) / 3600000;
  }
  if (prevHardWorkout?.workout_date) {
    hoursSinceLastHard =
      (new Date(log.workout_date).getTime() - new Date(prevHardWorkout.workout_date).getTime()) / 3600000;
  }

  return {
    user_id: log.user_id,
    training_log_id: log.id,
    workout_date: log.workout_date,
    total_distance_miles: totalDistanceMiles || null,
    total_duration_seconds: totalDurationSeconds || null,
    avg_pace_seconds: avgPaceSeconds || null,
    easy_seconds: easySeconds,
    moderate_seconds: moderateSeconds,
    threshold_seconds: thresholdSeconds,
    hard_seconds: hardSeconds,
    intensity_score: intensityScore,
    hard_effort_minutes: Math.round(hardEffortMinutes * 10) / 10,
    peak_pace_seconds: peakPaceSeconds,
    pace_variance: Math.round(paceVariance * 10) / 10,
    segment_count: seg.bouts.length,
    hard_segment_count: seg.repCount,
    avg_hard_segment_duration: seg.reps.length > 0
      ? Math.round(avg(seg.reps.map((r) => r.seconds)))
      : null,
    effort_distribution: effortDistribution,
    avg_heart_rate: avgHeartRate,
    hard_effort_avg_hr: hardEffortAvgHr,
    easy_effort_avg_hr: easyEffortAvgHr,
    hr_pace_efficiency: hrPaceEfficiency ? Math.round(hrPaceEfficiency * 1000) / 1000 : null,
    hours_since_last_workout: hoursSinceLastWorkout ? Math.round(hoursSinceLastWorkout * 10) / 10 : null,
    hours_since_last_hard: hoursSinceLastHard ? Math.round(hoursSinceLastHard * 10) / 10 : null,
    mood: log.mood,
    data_source: log.source,
    has_pace_segments: (log.pace_segments?.length ?? 0) > 0,
    has_hr_data: hasHrData,
    // WS1: derived classification (persisted so the Read can name the session).
    workout_type: seg.workoutKind,
    workout_structure: seg.structure,
  };
}

function avg(xs: number[]): number {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;
}

// Workout-notes fallback (deriveWorkoutNotes) lives in
// ../_shared/workout-notes.ts so it's importable + unit-tested. The voice memo
// is the primary source; this only fills workout_notes when it's empty.

// Compute rolling aggregates for a workout given history
function computeRollingAggregates(
  workoutDate: Date,
  history: Array<{ workout_date: string; total_distance_miles: number | null; hard_effort_minutes: number | null }>
) {
  const daysBefore = (days: number) => {
    const cutoff = new Date(workoutDate.getTime() - days * 24 * 60 * 60 * 1000);
    return history.filter(w => {
      const d = new Date(w.workout_date);
      return d >= cutoff && d < workoutDate;
    });
  };

  const sumMiles = (logs: typeof history) =>
    logs.reduce((sum, w) => sum + (w.total_distance_miles || 0), 0);
  const sumHard = (logs: typeof history) =>
    logs.reduce((sum, w) => sum + (w.hard_effort_minutes || 0), 0);

  const last7 = daysBefore(7);
  const last14 = daysBefore(14);
  const last28 = daysBefore(28);
  const last42 = daysBefore(42);

  const rolling7dMiles = sumMiles(last7);
  const rolling28dMiles = sumMiles(last28);

  // Monotony: stdev(daily_miles) / mean(daily_miles) over 7 days
  const dailyMiles: number[] = [];
  for (let i = 0; i < 7; i++) {
    const dayStart = new Date(workoutDate.getTime() - (i + 1) * 24 * 60 * 60 * 1000);
    const dayEnd = new Date(workoutDate.getTime() - i * 24 * 60 * 60 * 1000);
    const dayTotal = history
      .filter(w => {
        const d = new Date(w.workout_date);
        return d >= dayStart && d < dayEnd;
      })
      .reduce((sum, w) => sum + (w.total_distance_miles || 0), 0);
    dailyMiles.push(dayTotal);
  }

  const meanDaily = dailyMiles.reduce((a, b) => a + b, 0) / 7;
  const stdevDaily = Math.sqrt(
    dailyMiles.map(d => (d - meanDaily) ** 2).reduce((a, b) => a + b, 0) / 7
  );
  const monotony = meanDaily > 0 ? stdevDaily / meanDaily : 0;

  // ACWR: 7-day avg / 28-day avg (per week). NOTE (WS3): ACWR is retained as an
  // INTERNAL injury-risk input only — it is no longer surfaced to the athlete.
  // The surfaced load story is intensity-weighted load + hard/easy balance.
  const acuteWeekly = rolling7dMiles;
  const chronicWeekly = rolling28dMiles / 4;
  const acwr = chronicWeekly > 0 ? acuteWeekly / chronicWeekly : null;

  return {
    rolling_7d_miles: Math.round(rolling7dMiles * 10) / 10,
    rolling_14d_miles: Math.round(sumMiles(last14) * 10) / 10,
    rolling_28d_miles: Math.round(rolling28dMiles * 10) / 10,
    rolling_42d_miles: Math.round(sumMiles(last42) * 10) / 10,
    rolling_7d_hard_minutes: Math.round(sumHard(last7) * 10) / 10,
    rolling_28d_hard_minutes: Math.round(sumHard(last28) * 10) / 10,
    monotony_7d: Math.round(monotony * 100) / 100,
    strain_7d: Math.round(rolling7dMiles * monotony * 10) / 10,
    acwr: acwr ? Math.round(acwr * 100) / 100 : null,
  };
}

/** Pull the athlete's pace zones from athlete_state. Returns an empty object
 *  when missing — the classifier degrades gracefully (volume still computes;
 *  zone classification falls back to easy). */
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

/** Fetch rep-level laps for a set of workout ids, grouped by workout_id. */
async function fetchLapsByWorkout(
  userId: string,
  workoutIds: string[],
): Promise<Map<string, LapInput[]>> {
  const byId = new Map<string, LapInput[]>();
  if (workoutIds.length === 0) return byId;
  // Chunk to keep the IN list sane.
  for (let i = 0; i < workoutIds.length; i += 200) {
    const chunk = workoutIds.slice(i, i + 200);
    const { data } = await supabase
      .from("running_workout_laps")
      .select("workout_id, lap_index, is_rest, distance_meters, avg_pace_sec_per_mile, moving_time_seconds, elapsed_time_seconds, avg_heart_rate")
      .eq("user_id", userId)
      .in("workout_id", chunk)
      .order("lap_index", { ascending: true });
    for (const lap of (data ?? []) as Array<Record<string, unknown>>) {
      const wid = String(lap.workout_id);
      const arr = byId.get(wid) ?? [];
      arr.push(lap as LapInput);
      byId.set(wid, arr);
    }
  }
  return byId;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id: bodyUserId, training_log_id, backfill } = await req.json();

    // H3 fix (2026-07-15): this function previously trusted body.user_id with
    // NO auth gate — any anon-key caller could read AND overwrite another
    // athlete's workout data (types/notes backfill). Callers: iOS
    // (user JWT + user_id in body; the helper 403s on a mismatch) and ops
    // scripts (service-role key + user_id; the helper 400s if it's missing).
    // Same pattern as its sibling correct-workout-structure.
    const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
    if ("response" in auth) return auth.response;
    const { userId: user_id } = auth;

    const cols = "id, user_id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, pace_segments, workout_type, workout_notes, mood, source";

    // Fetch workouts to process
    let query = supabase
      .from("training_logs")
      .select(cols)
      .eq("user_id", user_id)
      .order("workout_date", { ascending: true });

    if (training_log_id && !backfill) {
      query = query.eq("id", training_log_id);
    }

    const { data: logs, error: fetchError } = await query;
    if (fetchError) throw new Error(`Failed to fetch logs: ${fetchError.message}`);
    if (!logs || logs.length === 0) {
      return new Response(JSON.stringify({ message: "No workouts found", computed: 0 }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // For single-workout mode we still need full history for rolling aggregates.
    let allLogs = (logs as TrainingLog[]).filter(l => l.workout_date != null);
    if (training_log_id && !backfill) {
      const { data: contextLogs } = await supabase
        .from("training_logs")
        .select(cols)
        .eq("user_id", user_id)
        .order("workout_date", { ascending: true });
      if (contextLogs) allLogs = (contextLogs as TrainingLog[]).filter(l => l.workout_date != null);
    }

    allLogs.sort((a, b) => new Date(a.workout_date).getTime() - new Date(b.workout_date).getTime());

    // Determine which logs to compute features for
    const targetLogIds = training_log_id && !backfill
      ? new Set([training_log_id])
      : new Set(allLogs.map(l => l.id));

    if (!backfill && targetLogIds.size > 1) {
      const { data: existing } = await supabase
        .from("workout_features")
        .select("training_log_id")
        .eq("user_id", user_id);
      if (existing) {
        for (const e of existing) targetLogIds.delete(e.training_log_id);
      }
    }

    if (targetLogIds.size === 0) {
      return new Response(JSON.stringify({ message: "All features already computed", computed: 0 }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // --- WS1: pull pace zones + laps ---
    const zones = await fetchPaceZones(user_id);
    const lapsByWorkout = await fetchLapsByWorkout(user_id, allLogs.map(l => l.id));

    // Segment every log once (chronological), so recovery context can see the
    // most recent prior HARD session by its real classification.
    const segById = new Map<string, SegmentationResult>();
    for (const log of allLogs) {
      segById.set(log.id, segmentLog(log, lapsByWorkout.get(log.id), zones));
    }

    const features: Array<Record<string, unknown>> = [];
    const typeBackfill: Array<{ id: string; workout_type: string }> = [];
    const notesBackfill: Array<{ id: string; workout_notes: string }> = [];
    const featuresSoFar: Array<{ workout_date: string; total_distance_miles: number | null; hard_effort_minutes: number | null }> = [];

    for (let i = 0; i < allLogs.length; i++) {
      const log = allLogs[i];
      const seg = segById.get(log.id)!;

      const prevWorkout = i > 0 ? allLogs[i - 1] : null;
      let prevHardWorkout: TrainingLog | null = null;
      for (let j = i - 1; j >= 0; j--) {
        if (isQualitySession(segById.get(allLogs[j].id)!)) { prevHardWorkout = allLogs[j]; break; }
      }

      const feat = computeFeatures(log, seg, prevWorkout, prevHardWorkout);

      featuresSoFar.push({
        workout_date: log.workout_date,
        total_distance_miles: feat.total_distance_miles,
        hard_effort_minutes: feat.hard_effort_minutes,
      });

      if (targetLogIds.has(log.id)) {
        const rolling = computeRollingAggregates(new Date(log.workout_date), featuresSoFar);
        features.push({ ...feat, ...rolling });
        // Backfill the untyped training_logs (don't clobber a set type).
        if (!log.workout_type && seg.workoutKind) {
          typeBackfill.push({ id: log.id, workout_type: seg.workoutKind });
        }
        // Backfill workout_notes from laps ONLY when the voice memo left it
        // empty (no spoken workout description). Voice always wins; this is the
        // AI-from-laps fallback so the session still knows what it was.
        if (!log.workout_notes || log.workout_notes.trim().length === 0) {
          const derived = deriveWorkoutNotes(seg, lapsByWorkout.get(log.id));
          if (derived) notesBackfill.push({ id: log.id, workout_notes: derived });
        }
      }
    }

    // Upsert. workout_type/workout_structure require migration
    // 20260613200000. Deploy order is migration-first, but guard against the
    // function landing first (this repo has been bitten by deploy ordering):
    // on a missing-column error, retry without the two new fields.
    if (features.length > 0) {
      let { error: upsertError } = await supabase
        .from("workout_features")
        .upsert(features, { onConflict: "training_log_id" });
      if (upsertError && /workout_type|workout_structure|column/i.test(upsertError.message)) {
        const stripped = features.map(({ workout_type: _wt, workout_structure: _ws, ...rest }) => rest);
        ({ error: upsertError } = await supabase
          .from("workout_features")
          .upsert(stripped, { onConflict: "training_log_id" }));
      }
      if (upsertError) throw new Error(`Failed to upsert features: ${upsertError.message}`);
    }

    // Backfill training_logs.workout_type for untyped imports.
    let typesBackfilled = 0;
    for (const t of typeBackfill) {
      const { error } = await supabase
        .from("training_logs")
        .update({ workout_type: t.workout_type })
        .eq("id", t.id)
        .is("workout_type", null);
      if (!error) typesBackfilled++;
    }

    // Backfill training_logs.workout_notes from laps for sessions the athlete
    // didn't describe. The `.is("workout_notes", null)` guard makes the write
    // a hard no-op against any row that already has a spoken description.
    let notesBackfilled = 0;
    for (const n of notesBackfill) {
      const { error } = await supabase
        .from("training_logs")
        .update({ workout_notes: n.workout_notes })
        .eq("id", n.id)
        .is("workout_notes", null);
      if (!error) notesBackfilled++;
    }

    console.log(`Computed ${features.length} workout features for user ${user_id}; backfilled ${typesBackfilled} types, ${notesBackfilled} notes`);

    return new Response(
      JSON.stringify({ success: true, computed: features.length, types_backfilled: typesBackfilled, notes_backfilled: notesBackfilled, user_id }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error computing workout features:", error);
    captureException(error, { fn: "compute-workout-features" });
    await flushSentry();
    const message = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
