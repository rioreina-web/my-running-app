import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// ============================================================================
// Workout Feature Computation
// Analyzes raw pace_segments, HR, distance, and duration to produce
// ML-ready features. No workout-type labels — just the numbers.
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
  mood: string | null;
  source: string | null;
}

// Zone weights for intensity scoring (higher = harder).
//
// Sorted slow → fast. Used by load = intensity_score × duration / 60,
// which feeds intensity-weighted ACWR. Calibrated against typical
// advanced single-session anchors — 10×400m mile, 6×1K @ 5K, 10×1K @
// 10K, 5–7mi HM, 8–13mi MP — to land hard sessions in roughly the same
// load band.
//
// `threshold` and `tempo` deliberately omitted — the labels are too
// fuzzy in practice. A "tempo run" can mean anywhere from MP-feel to
// LT-feel depending on plan. Aliased to `hmp` (3.0) by `effortWeight()`
// below for backward-compat with historical pace_segments; new
// classification should pick a specific pace zone (mile/3K/5K/10K/hmp/
// mp/steady/moderate/easy/recovery).
const ZONE_WEIGHTS: Record<string, number> = {
  recovery: 0.7,    // true active recovery — barely add fatigue
  easy: 1.0,        // reference
  moderate: 1.4,
  steady: 2.1,
  mp: 3.0,          // sustained race-pace work is real load, not "moderate-plus"
  hmp: 3.5,         // sustained sub-threshold — undersold at 3.0
  "10k": 4.0,
  "5k": 6.0,
  interval: 6.0,    // generic "intervals" — typical 5K-pace work
  "3k": 8.0,
  race_pace: 6.0,   // ambiguous label — defaults to 5K-pace; specific
                     // race pace (mile/5k/10k/hm/mp) should be used instead
  mile: 10.0,       // VO2max+ repeats. 1 min at 4:30/mi ≈ 10 min easy.
};

// Backward-compat alias: legacy `threshold` / `tempo` segments map to
// `hmp` (3.0) so historical workouts don't silently re-weight to easy.
// New ingestion paths should classify to a specific pace zone.
function effortWeight(effort: string): number {
  const e = effort.toLowerCase();
  if (e === "threshold" || e === "tempo") return ZONE_WEIGHTS.hmp;
  return ZONE_WEIGHTS[e] ?? 1.0;
}

// Classify as "hard" effort (threshold or above)
function isHardEffort(effort: string): boolean {
  const hard = ["threshold", "tempo", "interval", "race_pace", "mile", "hmp", "5k", "10k", "3k"];
  return hard.includes(effort.toLowerCase());
}

// Classify as "easy" effort
function isEasyEffort(effort: string): boolean {
  const easy = ["easy", "recovery"];
  return easy.includes(effort.toLowerCase());
}

// Parse "M:SS" pace to seconds per mile
function paceToSeconds(pace: string | null): number {
  if (!pace) return 0;
  const parts = pace.split(":");
  if (parts.length !== 2) return 0;
  return parseInt(parts[0]) * 60 + parseInt(parts[1]);
}

// Compute features for a single workout
function computeFeatures(log: TrainingLog, prevWorkout: TrainingLog | null, prevHardWorkout: TrainingLog | null) {
  const segments = log.pace_segments || [];
  const hasPaceSegments = segments.length > 0;

  // --- Volume signals ---
  const totalDistanceMiles = log.workout_distance_miles || 0;
  const totalDurationSeconds = (log.workout_duration_minutes || 0) * 60;
  const avgPaceSeconds = totalDistanceMiles > 0 && totalDurationSeconds > 0
    ? totalDurationSeconds / totalDistanceMiles
    : 0;

  // --- Intensity distribution from segments ---
  let easySeconds = 0;
  let moderateSeconds = 0;
  let thresholdSeconds = 0;
  let hardSeconds = 0;
  let intensityWeightedSum = 0;
  let totalSegmentSeconds = 0;
  let peakPaceSeconds = Infinity;
  const segmentPaces: number[] = [];
  let hardSegmentCount = 0;
  let hardSegmentDurations: number[] = [];
  let hrSum = 0;
  let hrCount = 0;
  let hardHrSum = 0;
  let hardHrCount = 0;
  let easyHrSum = 0;
  let easyHrCount = 0;
  let hasHrData = false;

  // Track segment order for effort distribution
  const segmentIntensities: number[] = [];

  for (const seg of segments) {
    const dur = seg.duration_seconds || 0;
    const pace = paceToSeconds(seg.pace_per_mile);
    const effort = (seg.effort || "easy").toLowerCase();
    const weight = effortWeight(effort);

    totalSegmentSeconds += dur;
    intensityWeightedSum += dur * weight;

    if (pace > 0) {
      segmentPaces.push(pace);
      if (pace < peakPaceSeconds) peakPaceSeconds = pace;
    }

    // Zone bucketing based on effort label from pace classification
    if (isHardEffort(effort)) {
      if (effort === "threshold" || effort === "tempo" || effort === "hmp") {
        thresholdSeconds += dur;
      } else {
        hardSeconds += dur;
      }
      hardSegmentCount++;
      hardSegmentDurations.push(dur);
    } else if (effort === "moderate" || effort === "steady" || effort === "mp") {
      moderateSeconds += dur;
    } else {
      easySeconds += dur;
    }

    segmentIntensities.push(weight);

    // HR aggregation
    if (seg.avg_heart_rate && seg.avg_heart_rate > 0) {
      hasHrData = true;
      hrSum += seg.avg_heart_rate * dur;
      hrCount += dur;

      if (isHardEffort(effort)) {
        hardHrSum += seg.avg_heart_rate * dur;
        hardHrCount += dur;
      }
      if (isEasyEffort(effort)) {
        easyHrSum += seg.avg_heart_rate * dur;
        easyHrCount += dur;
      }
    }
  }

  // If no segments but we have overall workout data, classify the whole thing
  if (!hasPaceSegments && totalDurationSeconds > 0) {
    // Without segments we can't break it down — treat as single effort
    easySeconds = totalDurationSeconds;
    totalSegmentSeconds = totalDurationSeconds;
    intensityWeightedSum = totalDurationSeconds * 1.0;
  }

  const intensityScore = totalSegmentSeconds > 0
    ? intensityWeightedSum / totalSegmentSeconds
    : 0;

  const hardEffortMinutes = (thresholdSeconds + hardSeconds) / 60;

  // Pace variance (stdev of segment paces)
  let paceVariance = 0;
  if (segmentPaces.length > 1) {
    const mean = segmentPaces.reduce((a, b) => a + b, 0) / segmentPaces.length;
    const sqDiffs = segmentPaces.map(p => (p - mean) ** 2);
    paceVariance = Math.sqrt(sqDiffs.reduce((a, b) => a + b, 0) / segmentPaces.length);
  }

  // Effort distribution: where are hard efforts concentrated?
  let effortDistribution = "even";
  if (segmentIntensities.length >= 3) {
    const mid = Math.floor(segmentIntensities.length / 2);
    const firstHalf = segmentIntensities.slice(0, mid);
    const secondHalf = segmentIntensities.slice(mid);
    const firstAvg = firstHalf.reduce((a, b) => a + b, 0) / firstHalf.length;
    const secondAvg = secondHalf.reduce((a, b) => a + b, 0) / secondHalf.length;
    const diff = secondAvg - firstAvg;
    if (diff > 0.5) effortDistribution = "back_loaded";
    else if (diff < -0.5) effortDistribution = "front_loaded";
    else if (paceVariance > 30) effortDistribution = "mixed";
    else effortDistribution = "even";
  }

  // HR metrics
  const avgHeartRate = hrCount > 0 ? Math.round(hrSum / hrCount) : null;
  const hardEffortAvgHr = hardHrCount > 0 ? Math.round(hardHrSum / hardHrCount) : null;
  const easyEffortAvgHr = easyHrCount > 0 ? Math.round(easyHrSum / easyHrCount) : null;
  const hrPaceEfficiency = avgHeartRate && avgPaceSeconds > 0
    ? avgHeartRate / avgPaceSeconds
    : null;

  // Recovery context
  let hoursSinceLastWorkout: number | null = null;
  let hoursSinceLastHard: number | null = null;

  if (prevWorkout?.workout_date) {
    const diff = new Date(log.workout_date).getTime() - new Date(prevWorkout.workout_date).getTime();
    hoursSinceLastWorkout = diff / (1000 * 60 * 60);
  }
  if (prevHardWorkout?.workout_date) {
    const diff = new Date(log.workout_date).getTime() - new Date(prevHardWorkout.workout_date).getTime();
    hoursSinceLastHard = diff / (1000 * 60 * 60);
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
    intensity_score: Math.round(intensityScore * 100) / 100,
    hard_effort_minutes: Math.round(hardEffortMinutes * 10) / 10,
    peak_pace_seconds: peakPaceSeconds === Infinity ? null : Math.round(peakPaceSeconds),
    pace_variance: Math.round(paceVariance * 10) / 10,
    segment_count: segments.length,
    hard_segment_count: hardSegmentCount,
    avg_hard_segment_duration: hardSegmentDurations.length > 0
      ? Math.round(hardSegmentDurations.reduce((a, b) => a + b, 0) / hardSegmentDurations.length)
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
    has_pace_segments: hasPaceSegments,
    has_hr_data: hasHrData,
  };
}

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

  // ACWR: 7-day avg / 28-day avg (per week)
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id, training_log_id, backfill } = await req.json();

    if (!user_id) {
      return new Response(JSON.stringify({ error: "user_id required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch workouts to process
    let query = supabase
      .from("training_logs")
      .select("id, user_id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, pace_segments, mood, source")
      .eq("user_id", user_id)
      .order("workout_date", { ascending: true });

    if (training_log_id && !backfill) {
      // Single workout mode
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

    // Filter out logs with null workout_date (can't compute features without a date)
    let allLogs = (logs as TrainingLog[]).filter(l => l.workout_date != null);
    if (training_log_id && !backfill) {
      const { data: contextLogs } = await supabase
        .from("training_logs")
        .select("id, user_id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, pace_segments, mood, source")
        .eq("user_id", user_id)
        .order("workout_date", { ascending: true });
      if (contextLogs) allLogs = (contextLogs as TrainingLog[]).filter(l => l.workout_date != null);
    }

    // Sort by date
    allLogs.sort((a, b) => new Date(a.workout_date).getTime() - new Date(b.workout_date).getTime());

    // Determine which logs to compute features for
    const targetLogIds = training_log_id && !backfill
      ? new Set([training_log_id])
      : new Set(allLogs.map(l => l.id));

    // If not backfill, skip already-computed features
    if (!backfill && targetLogIds.size > 1) {
      const { data: existing } = await supabase
        .from("workout_features")
        .select("training_log_id")
        .eq("user_id", user_id);
      if (existing) {
        for (const e of existing) {
          targetLogIds.delete(e.training_log_id);
        }
      }
    }

    if (targetLogIds.size === 0) {
      return new Response(JSON.stringify({ message: "All features already computed", computed: 0 }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Compute features for each target workout
    const features: Array<Record<string, unknown>> = [];
    const featuresSoFar: Array<{ workout_date: string; total_distance_miles: number | null; hard_effort_minutes: number | null }> = [];

    for (let i = 0; i < allLogs.length; i++) {
      const log = allLogs[i];

      // Find previous workout and previous hard workout
      const prevWorkout = i > 0 ? allLogs[i - 1] : null;
      let prevHardWorkout: TrainingLog | null = null;
      for (let j = i - 1; j >= 0; j--) {
        const segs = allLogs[j].pace_segments || [];
        const hasHard = segs.some(s => isHardEffort(s.effort || "easy"));
        if (hasHard) {
          prevHardWorkout = allLogs[j];
          break;
        }
      }

      const feat = computeFeatures(log, prevWorkout, prevHardWorkout);

      // Track for rolling aggregates
      featuresSoFar.push({
        workout_date: log.workout_date,
        total_distance_miles: feat.total_distance_miles,
        hard_effort_minutes: feat.hard_effort_minutes,
      });

      if (targetLogIds.has(log.id)) {
        const rolling = computeRollingAggregates(new Date(log.workout_date), featuresSoFar);
        features.push({ ...feat, ...rolling });
      }
    }

    // Upsert features (on conflict update)
    if (features.length > 0) {
      const { error: upsertError } = await supabase
        .from("workout_features")
        .upsert(features, { onConflict: "training_log_id" });

      if (upsertError) throw new Error(`Failed to upsert features: ${upsertError.message}`);
    }

    console.log(`Computed ${features.length} workout features for user ${user_id}`);

    return new Response(
      JSON.stringify({
        success: true,
        computed: features.length,
        user_id,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error computing workout features:", error);
    const message = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({ error: message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
