/**
 * Weekly Analytics — Pure Computation Functions
 *
 * No AI, no side effects. Takes typed data, returns numbers and structured results.
 * Used by weekly-coaching-report edge function.
 */

// ─── Types ───────────────────────────────────────────────────────────────────

export interface WeeklyLoad {
  miles: number;
  minutes: number;
  runCount: number;
  /**
   * Intensity-weighted load in "weighted minutes". This is the input to
   * ACWR — a tempo minute counts ~2× an easy minute, so a 50-mile week
   * with two threshold sessions has a higher weightedLoad than a 50-mile
   * week of all easy running.
   *
   * Computed in two ways depending on what's available per workout:
   *   1. PREFERRED: zone seconds from `workout_features` (easy/moderate/
   *      threshold/hard), each multiplied by its WEIGHTS factor. Most
   *      accurate — reflects what actually happened in the run.
   *   2. FALLBACK: workout_type × duration_minutes when features haven't
   *      been computed yet (compute-workout-features async hasn't run,
   *      or the workout has no HealthKit splits).
   *
   * Units: weighted minutes (i.e. an easy-only week's weightedLoad ≈
   * its `minutes` value; a tempo-heavy week's weightedLoad > `minutes`).
   */
  weightedLoad: number;
}

export interface WorkoutFeaturesRow {
  training_log_id: string;
  /**
   * Time-weighted average of per-segment ZONE_WEIGHTS computed by
   * compute-workout-features (e.g. easy=1.0, mp=2.5, threshold=3.0,
   * 10k=3.5, 5k=4.0, mile=5.0). This is effectively the workout's IF
   * (intensity factor) on a discrete scale — it captures the pace
   * gradient WITHIN a workout, which the 4-zone summary throws away.
   */
  intensity_score: number | null;
  /** Total elapsed seconds for the run. */
  total_duration_seconds: number | null;
}

/**
 * Fallback weights when workout_features hasn't been computed for a log.
 * Multiplied by `workout_duration_minutes`. Calibrated against typical
 * advanced single-session loads:
 *   10×400m mile pace ≈ 6×1K 5K pace ≈ 10×1K 10K pace ≈ 6mi HM ≈ 10mi MP
 * The numbers below are deliberately lower than the per-segment weights
 * in compute-workout-features — fallback assumes a "typical" workout of
 * the given type, including warm-up/cool-down. Real features always tell
 * a more accurate story.
 */
const TYPE_FALLBACK_WEIGHTS: Record<string, number> = {
  easy: 1.0,
  recovery: 0.7,    // matches per-segment recovery weight
  long_run: 1.1,    // mostly aerobic
  long: 1.1,
  strides: 1.5,
  progression: 1.6,
  // "tempo" / "threshold" labels are fuzzy — see compute-workout-features.
  // We weight them at the HMP level (3.5) since most plans use them to
  // mean sustained sub-threshold work. The full session, including WU/CD,
  // averages lower in practice (most logs are ~30% hard, 70% easy), so
  // the per-workout fallback factor is ~half the per-minute weight.
  tempo: 1.8,
  threshold: 1.8,
  // "intervals" assumes 5K–10K pace; mile_repeats handles mile-pace work.
  intervals: 2.5,
  mile_repeats: 3.0,
  // MP simulation runs (e.g. 8–13mi at marathon pace) should land near
  // a 5K-interval session in load — bump fallback to reflect that.
  mp_run: 2.7,
  race: 2.8,
  rest: 0.0,
  cross_training: 0.7,
  strength: 0.5,
};

/**
 * Compute weighted load (in weighted minutes) for a single training log.
 *
 * Preferred path — uses `intensity_score × duration` from workout_features.
 * `intensity_score` is the time-weighted average of per-segment pace
 * weights (mile=5.0, 5k=4.0, 10k=3.5, threshold=3.0, mp=2.5, easy=1.0)
 * computed by compute-workout-features. This captures the within-workout
 * pace gradient — a 10×400m at mile pace gets ~5× the load per minute
 * of an easy run.
 *
 * Fallback path — workout_type × duration when features haven't been
 * computed yet (async hasn't run, or no HealthKit splits).
 *
 * Returns: weighted minutes. An all-easy 60-minute run ≈ 60. A 60-minute
 * tempo run ≈ 60 × 3.0 = 180. A 10-mile MP session for a 5:20 marathoner
 * (~53 min hard at 2.5 + 20 min easy at 1.0) ≈ 152.
 */
export function computeWeightedLoadForLog(
  log: TrainingLogRow,
  features: WorkoutFeaturesRow | undefined,
): number {
  // Preferred path — per-segment intensity from workout_features.
  if (features?.intensity_score && features?.total_duration_seconds) {
    return (features.intensity_score * features.total_duration_seconds) / 60;
  }
  // Fallback — workout_type × duration_minutes.
  const dur = log.workout_duration_minutes ?? 0;
  if (dur <= 0) return 0;
  const type = (log.workout_type ?? "easy").toLowerCase();
  const factor = TYPE_FALLBACK_WEIGHTS[type] ?? 1.0;
  return dur * factor;
}

export interface ScheduledWorkoutRow {
  id: string;
  date: string;
  workout_type: string;
  status: string;
  workout_data: Record<string, unknown> | null;
  completed_workout_id: string | null;
  week_number: number | null;
  notes: string | null;
}

export interface PaceSegmentRow {
  effort: string;
  distance_miles: number;
  duration_seconds: number;
  pace_per_mile: string;
  avg_heart_rate: number | null;
}

export interface TrainingLogRow {
  id: string;
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_type: string | null;
  workout_pace_per_mile: string | null;
  pace_segments: PaceSegmentRow[] | null;
  mood: string | null;
  notes: string | null;
  cleaned_notes: string | null;
  coach_insight: string | null;
}

export interface InjuryRow {
  id: string;
  body_area: string;
  severity: number;
  status: string;
  side: string;
  first_reported_at: string | null;
}

export interface FormCheckRow {
  ai_findings: Record<string, unknown> | null;
  created_at: string;
}

export type Severity = "green" | "yellow" | "orange" | "red";

export type AlertCategory =
  | "overtraining_risk"
  | "injury_risk"
  | "inconsistency"
  | "pace_regression"
  | "volume_high"
  | "volume_low"
  | "goal_timeline";

export interface Alert {
  category: AlertCategory;
  severity: Severity;
  title: string;
  message: string;
  metric_value: number;
  threshold: number;
}

export interface ComputedMetrics {
  totalMiles: number;
  totalMinutes: number;
  runCount: number;
  restDays: number;
  avgPaceSeconds: number;
  longestRunMiles: number;
  complianceScore: number;
  complianceByType: Record<string, number>;
  paceComplianceScore: number;
  acwr: number;
  chronicLoad: number;
  acuteLoad: number;
  volumeChangePct: number;
  moodScore: number;
  moodTrend: string;
  moodDistribution: Record<string, number>;
  easyPaceAvg: number | null;
  workoutPaceAvg: number | null;
  longRunMiles: number | null;
  longRunPace: number | null;
  injuryRisk: InjuryRiskResult;
}

export interface InjuryRiskResult {
  score: number;
  severity: Severity;
  factors: string[];
}

// ─── ACWR ────────────────────────────────────────────────────────────────────

/**
 * ACWR (Acute:Chronic Workload Ratio) — intensity-weighted version.
 *
 * Acute = this week's `weightedLoad` (sum of zone-weighted minutes).
 * Chronic = exponentially-weighted average of the prior 4 weeks'
 * `weightedLoad` (recent-heavy: 4·3·2·1).
 *
 * Same ratio math as the original miles-only ACWR, but the input is
 * volume × intensity instead of bare miles. Two 50-mile weeks now
 * produce different ACWRs if one had more threshold work than the other.
 *
 * Interpretation bands (research-derived, treat as guidance not gospel):
 *   < 0.6  → detraining / volume drop
 *   0.8–1.3 → "sweet spot"
 *   > 1.3  → overreach / elevated injury risk
 *   > 1.5  → spike — recommend pulling back
 */
export function calculateACWR(
  currentWeek: WeeklyLoad,
  previousWeeks: WeeklyLoad[]
): { acwr: number; chronicLoad: number; acuteLoad: number } {
  const acuteLoad = currentWeek.weightedLoad;

  if (previousWeeks.length === 0) {
    return { acwr: 1.0, chronicLoad: acuteLoad, acuteLoad };
  }

  // Exponentially weighted: most recent = 4, then 3, 2, 1
  const weights = [4, 3, 2, 1].slice(0, previousWeeks.length);
  const totalWeight = weights.reduce((s, w) => s + w, 0);
  const chronicLoad =
    previousWeeks.reduce(
      (sum, week, i) => sum + week.weightedLoad * weights[i],
      0,
    ) / totalWeight;

  const acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0;

  return { acwr: Math.round(acwr * 100) / 100, chronicLoad, acuteLoad };
}

// ─── Compliance ──────────────────────────────────────────────────────────────

export function calculateCompliance(
  scheduled: ScheduledWorkoutRow[]
): { overall: number; byType: Record<string, number> } {
  const nonRest = scheduled.filter((w) => w.workout_type !== "rest");
  if (nonRest.length === 0) return { overall: 1.0, byType: {} };

  const completed = nonRest.filter((w) => w.status === "completed");
  const overall = completed.length / nonRest.length;

  const byType: Record<string, number> = {};
  const types = [...new Set(nonRest.map((w) => w.workout_type))];
  for (const type of types) {
    const typeScheduled = nonRest.filter((w) => w.workout_type === type);
    const typeCompleted = typeScheduled.filter((w) => w.status === "completed");
    byType[type] =
      typeScheduled.length > 0 ? typeCompleted.length / typeScheduled.length : 1.0;
  }

  return { overall: Math.round(overall * 100) / 100, byType };
}

// ─── Pace Compliance ─────────────────────────────────────────────────────────

export function calculatePaceCompliance(
  scheduled: ScheduledWorkoutRow[],
  logs: TrainingLogRow[],
  racePaceSecondsPerMile: number | null
): number {
  if (!racePaceSecondsPerMile || logs.length === 0) return 1.0;

  const completedWithData = scheduled.filter(
    (w) => w.status === "completed" && w.workout_data
  );
  if (completedWithData.length === 0) return 1.0;

  const deviations: number[] = [];

  for (const workout of completedWithData) {
    // Find matching log by date
    const log = logs.find(
      (l) =>
        l.workout_date &&
        l.workout_date.startsWith(workout.date) &&
        l.workout_distance_miles &&
        l.workout_duration_minutes
    );
    if (!log || !log.workout_distance_miles || !log.workout_duration_minutes) continue;

    // Extract prescribed pace from workout_data
    const prescribedPace = extractPrescribedPace(
      workout.workout_data,
      racePaceSecondsPerMile
    );
    if (!prescribedPace) continue;

    const actualPace =
      (log.workout_duration_minutes * 60) / log.workout_distance_miles;

    // 5% tolerance, then penalize
    const deviation = Math.abs(actualPace - prescribedPace) / prescribedPace;
    deviations.push(Math.max(0, 1 - Math.max(0, deviation - 0.05) * 2));
  }

  if (deviations.length === 0) return 1.0;
  return (
    Math.round(
      (deviations.reduce((s, d) => s + d, 0) / deviations.length) * 100
    ) / 100
  );
}

function extractPrescribedPace(
  workoutData: Record<string, unknown> | null,
  racePace: number
): number | null {
  if (!workoutData) return null;
  try {
    const steps = workoutData.steps as Array<Record<string, unknown>> | undefined;
    if (!steps || steps.length === 0) return null;

    // Find the main "active" step's pace percentage
    const activeSteps = steps.filter(
      (s) => s.stepType === "active" || s.stepType === "tempo"
    );
    if (activeSteps.length === 0) return null;

    const paceIntensity = activeSteps[0].targetPaceIntensity as
      | Record<string, unknown>
      | undefined;
    if (!paceIntensity || !paceIntensity.percentage) return null;

    const pct = paceIntensity.percentage as number;
    // percentage is relative to race pace: 100% = race pace, 80% = slower
    return racePace / (pct / 100);
  } catch {
    return null;
  }
}

// ─── Mood ────────────────────────────────────────────────────────────────────

const MOOD_SCORES: Record<string, number> = {
  energized: 1.0,
  great: 0.9,
  strong: 0.85,
  positive: 0.8,
  good: 0.75,
  neutral: 0.5,
  ok: 0.45,
  tired: 0.3,
  sluggish: 0.25,
  fatigued: 0.2,
  struggling: 0.15,
  exhausted: 0.1,
  injured: 0.05,
};

export function analyzeMood(
  logs: TrainingLogRow[]
): { score: number; trend: string; distribution: Record<string, number> } {
  const moods = logs.map((l) => l.mood).filter(Boolean) as string[];
  if (moods.length === 0) {
    return { score: 0.5, trend: "no data", distribution: {} };
  }

  const distribution: Record<string, number> = {};
  moods.forEach((m) => {
    const key = m.toLowerCase();
    distribution[key] = (distribution[key] || 0) + 1;
  });

  const scores = moods.map((m) => MOOD_SCORES[m.toLowerCase()] ?? 0.5);
  const avgScore = scores.reduce((s, v) => s + v, 0) / scores.length;

  // Trend: first half vs second half
  const mid = Math.max(1, Math.floor(scores.length / 2));
  const firstHalf = scores.slice(0, mid);
  const secondHalf = scores.slice(mid);
  const firstAvg = firstHalf.reduce((s, v) => s + v, 0) / firstHalf.length;
  const secondAvg = secondHalf.reduce((s, v) => s + v, 0) / secondHalf.length;

  let trend = "stable";
  if (secondAvg > firstAvg + 0.15) trend = "improving";
  else if (secondAvg < firstAvg - 0.15) trend = "declining";

  return {
    score: Math.round(avgScore * 100) / 100,
    trend,
    distribution,
  };
}

// ─── Injury Risk ─────────────────────────────────────────────────────────────

export function calculateInjuryRisk(
  acwr: number,
  moodScore: number,
  activeInjuries: InjuryRow[],
  formChecks: FormCheckRow[],
  volumeChangePct: number
): InjuryRiskResult {
  let score = 0;
  const factors: string[] = [];

  // ACWR deviation (0-0.25)
  if (acwr > 1.3) {
    score += 0.25;
    factors.push(`Workload spike: ACWR ${acwr.toFixed(2)} (above 1.3 threshold)`);
  } else if (acwr > 1.2) {
    score += 0.1;
    factors.push(`Moderate workload increase: ACWR ${acwr.toFixed(2)}`);
  }

  // Mood decline (0-0.2)
  if (moodScore < 0.3) {
    score += 0.2;
    factors.push("Persistent fatigue signals in training logs");
  } else if (moodScore < 0.45) {
    score += 0.1;
    factors.push("Mild fatigue trend in mood data");
  }

  // Active injuries (0-0.3)
  const highSeverity = activeInjuries.filter((i) => i.severity >= 7);
  const moderate = activeInjuries.filter(
    (i) => i.severity >= 4 && i.severity < 7
  );
  if (highSeverity.length > 0) {
    score += 0.3;
    factors.push(
      `High-severity injury: ${highSeverity[0].side !== "unknown" ? highSeverity[0].side + " " : ""}${highSeverity[0].body_area}`
    );
  } else if (moderate.length > 0) {
    score += 0.15;
    factors.push(
      `Active injury being monitored: ${moderate[0].body_area}`
    );
  }

  // Form check concerns (0-0.1)
  const concerns = formChecks.flatMap((fc) => {
    const findings = fc.ai_findings as
      | Array<Record<string, unknown>>
      | null;
    if (!findings) return [];
    return findings.filter(
      (f) => f.severity === "concern" || f.category === "concern"
    );
  });
  if (concerns.length >= 2) {
    score += 0.1;
    factors.push(`Multiple form concerns flagged in recent checks`);
  }

  // Volume jump (0-0.1)
  if (volumeChangePct > 15) {
    score += 0.1;
    factors.push(
      `Volume jump: ${volumeChangePct.toFixed(0)}% increase vs previous week`
    );
  }

  score = Math.min(1, score);
  const severity: Severity =
    score >= 0.6
      ? "red"
      : score >= 0.4
        ? "orange"
        : score >= 0.2
          ? "yellow"
          : "green";

  return { score: Math.round(score * 100) / 100, severity, factors };
}

// ─── Alert Generation ────────────────────────────────────────────────────────

export function generateAlerts(
  metrics: ComputedMetrics,
  context: {
    goalDaysRemaining: number | null;
    fitnessGapSeconds: number | null;
    prescribedEasyPace: number | null;
  }
): Alert[] {
  const alerts: Alert[] = [];

  // ACWR
  if (metrics.acwr > 1.3) {
    alerts.push({
      category: "overtraining_risk",
      severity: metrics.acwr > 1.5 ? "red" : "orange",
      title: "Workload Spike",
      message: `This week's load (${metrics.acuteLoad.toFixed(1)} mi) is ${Math.round((metrics.acwr - 1) * 100)}% above your 4-week average (${metrics.chronicLoad.toFixed(1)} mi).`,
      metric_value: metrics.acwr,
      threshold: 1.3,
    });
  } else if (metrics.acwr < 0.6 && metrics.chronicLoad > 10) {
    alerts.push({
      category: "volume_low",
      severity: "yellow",
      title: "Sharp Volume Drop",
      message: `This week's mileage is ${Math.round((1 - metrics.acwr) * 100)}% below your recent average. Unplanned rest weeks can break momentum.`,
      metric_value: metrics.acwr,
      threshold: 0.6,
    });
  }

  // Low compliance
  if (metrics.complianceScore < 0.6) {
    alerts.push({
      category: "inconsistency",
      severity: metrics.complianceScore < 0.4 ? "orange" : "yellow",
      title: "Low Plan Adherence",
      message: `Only ${Math.round(metrics.complianceScore * 100)}% of scheduled workouts completed this week.`,
      metric_value: metrics.complianceScore,
      threshold: 0.6,
    });
  }

  // Easy runs too fast
  if (metrics.easyPaceAvg && context.prescribedEasyPace) {
    if (metrics.easyPaceAvg < context.prescribedEasyPace * 0.92) {
      alerts.push({
        category: "pace_regression",
        severity: "yellow",
        title: "Easy Runs Too Fast",
        message:
          "Your easy run pace is drifting faster than prescribed. Easy days should feel genuinely easy to allow proper recovery.",
        metric_value: metrics.easyPaceAvg,
        threshold: context.prescribedEasyPace,
      });
    }
  }

  // Goal proximity
  if (
    context.goalDaysRemaining !== null &&
    context.goalDaysRemaining <= 28 &&
    context.fitnessGapSeconds !== null &&
    context.fitnessGapSeconds > 300
  ) {
    alerts.push({
      category: "goal_timeline",
      severity: context.goalDaysRemaining <= 14 ? "red" : "orange",
      title: "Goal Timeline Concern",
      message: `${context.goalDaysRemaining} days to race. Current predicted time is ${formatGap(context.fitnessGapSeconds)} off target.`,
      metric_value: context.fitnessGapSeconds,
      threshold: 300,
    });
  }

  // Injury risk
  if (metrics.injuryRisk.severity !== "green") {
    alerts.push({
      category: "injury_risk",
      severity: metrics.injuryRisk.severity,
      title: "Injury Risk Elevated",
      message:
        metrics.injuryRisk.factors.slice(0, 2).join(". ") + ".",
      metric_value: metrics.injuryRisk.score,
      threshold: 0.2,
    });
  }

  return alerts;
}

// ─── Aggregation ─────────────────────────────────────────────────────────────

/**
 * Sum a week of training logs into a WeeklyLoad. The optional
 * `featuresByLogId` map is used to compute intensity-weighted load
 * (preferred); when no entry is present for a log, the function falls
 * back to workout_type × duration_minutes.
 *
 * For backward compatibility, callers that don't have features yet can
 * pass `undefined` — the resulting `weightedLoad` will use only the
 * fallback path and still be a usable single number.
 */
export function aggregateWeeklyLoad(
  logs: TrainingLogRow[],
  featuresByLogId?: Map<string, WorkoutFeaturesRow>,
): WeeklyLoad {
  let miles = 0;
  let minutes = 0;
  let runCount = 0;
  let weightedLoad = 0;

  for (const log of logs) {
    const distance = log.workout_distance_miles ?? 0;
    if (distance > 0) {
      miles += distance;
      minutes += log.workout_duration_minutes ?? 0;
      runCount++;
    }
    // weightedLoad accrues even for non-distance entries (strength,
    // cross-train) since they contribute load even if they don't add
    // mileage. The fallback weights take care of those.
    weightedLoad += computeWeightedLoadForLog(
      log,
      featuresByLogId?.get(log.id),
    );
  }

  return { miles, minutes, runCount, weightedLoad };
}

export function computeAllMetrics(
  thisWeekLogs: TrainingLogRow[],
  previousWeeksLogs: TrainingLogRow[][],
  scheduledThisWeek: ScheduledWorkoutRow[],
  activeInjuries: InjuryRow[],
  formChecks: FormCheckRow[],
  racePaceSecondsPerMile: number | null,
  /**
   * Optional map keyed by training_log.id → workout_features row. When
   * supplied, ACWR and weeklyLoad become intensity-weighted (preferred).
   * When omitted, the function still returns a sensible answer using
   * the workout_type × duration fallback in computeWeightedLoadForLog.
   */
  featuresByLogId?: Map<string, WorkoutFeaturesRow>,
): ComputedMetrics {
  const thisWeekLoad = aggregateWeeklyLoad(thisWeekLogs, featuresByLogId);
  const prevLoads = previousWeeksLogs.map((logs) =>
    aggregateWeeklyLoad(logs, featuresByLogId),
  );

  // ACWR
  const { acwr, chronicLoad, acuteLoad } = calculateACWR(thisWeekLoad, prevLoads);

  // Volume change vs last week
  const lastWeekMiles = prevLoads.length > 0 ? prevLoads[0].miles : thisWeekLoad.miles;
  const volumeChangePct =
    lastWeekMiles > 0
      ? ((thisWeekLoad.miles - lastWeekMiles) / lastWeekMiles) * 100
      : 0;

  // Compliance
  const { overall: complianceScore, byType: complianceByType } =
    calculateCompliance(scheduledThisWeek);

  // Pace compliance
  const paceComplianceScore = calculatePaceCompliance(
    scheduledThisWeek,
    thisWeekLogs,
    racePaceSecondsPerMile
  );

  // Mood
  const { score: moodScore, trend: moodTrend, distribution: moodDistribution } =
    analyzeMood(thisWeekLogs);

  // Pace averages — use scheduled workout type if available, fall back to log's own workout_type
  const logsWithPace = thisWeekLogs.filter(
    (l) => l.workout_distance_miles && l.workout_duration_minutes
  );

  const getEffectiveType = (log: TrainingLogRow): string | null => {
    // First try matching against scheduled workout
    const matched = scheduledThisWeek.find(
      (s) =>
        s.date &&
        log.workout_date &&
        log.workout_date.startsWith(s.date) &&
        s.workout_type !== "rest"
    );
    if (matched) return matched.workout_type;
    // Fall back to the log's own workout_type
    return log.workout_type || null;
  };

  const easyLogs = logsWithPace.filter((l) => {
    const type = getEffectiveType(l);
    return type === "easy" || type === "recovery";
  });
  const workoutLogs = logsWithPace.filter((l) => {
    const type = getEffectiveType(l);
    return type !== null && type !== "easy" && type !== "recovery" && type !== "rest" && type !== "run";
  });

  const avgPace = (logs: TrainingLogRow[]): number | null => {
    if (logs.length === 0) return null;
    const paces = logs.map(
      (l) => (l.workout_duration_minutes! * 60) / l.workout_distance_miles!
    );
    return paces.reduce((s, p) => s + p, 0) / paces.length;
  };

  // Long run
  const longRunLog = logsWithPace.reduce<TrainingLogRow | null>((best, l) => {
    if (!best || l.workout_distance_miles! > best.workout_distance_miles!) return l;
    return best;
  }, null);

  // Rest days (days with no log or rest scheduled)
  const daysInWeek = 7;
  const restDays = daysInWeek - thisWeekLoad.runCount;

  // Overall avg pace
  const overallAvgPace =
    thisWeekLoad.miles > 0
      ? (thisWeekLoad.minutes * 60) / thisWeekLoad.miles
      : 0;

  // Injury risk
  const injuryRisk = calculateInjuryRisk(
    acwr,
    moodScore,
    activeInjuries,
    formChecks,
    volumeChangePct
  );

  return {
    totalMiles: Math.round(thisWeekLoad.miles * 10) / 10,
    totalMinutes: Math.round(thisWeekLoad.minutes),
    runCount: thisWeekLoad.runCount,
    restDays,
    avgPaceSeconds: Math.round(overallAvgPace),
    longestRunMiles: longRunLog
      ? Math.round(longRunLog.workout_distance_miles! * 10) / 10
      : 0,
    complianceScore,
    complianceByType,
    paceComplianceScore,
    acwr,
    chronicLoad: Math.round(chronicLoad * 10) / 10,
    acuteLoad: Math.round(acuteLoad * 10) / 10,
    volumeChangePct: Math.round(volumeChangePct * 10) / 10,
    moodScore,
    moodTrend,
    moodDistribution,
    easyPaceAvg: avgPace(easyLogs),
    workoutPaceAvg: avgPace(workoutLogs),
    longRunMiles: longRunLog
      ? Math.round(longRunLog.workout_distance_miles! * 10) / 10
      : null,
    longRunPace:
      longRunLog && longRunLog.workout_duration_minutes && longRunLog.workout_distance_miles
        ? Math.round(
            (longRunLog.workout_duration_minutes * 60) /
              longRunLog.workout_distance_miles
          )
        : null,
    injuryRisk,
  };
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatGap(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.round(seconds % 60);
  if (mins >= 60) {
    const hrs = Math.floor(mins / 60);
    const remMins = mins % 60;
    return `${hrs}h ${remMins}m`;
  }
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

export function formatPace(secondsPerMile: number): string {
  if (secondsPerMile <= 0 || secondsPerMile > 1200) return "--:--";
  const totalSecs = Math.round(secondsPerMile);
  const mins = Math.floor(totalSecs / 60);
  const secs = totalSecs % 60;
  return `${mins}:${secs.toString().padStart(2, "0")}/mi`;
}

export function formatDuration(totalMinutes: number): string {
  const hrs = Math.floor(totalMinutes / 60);
  const mins = Math.round(totalMinutes % 60);
  if (hrs > 0) return `${hrs}h ${mins}m`;
  return `${mins}m`;
}

/**
 * Get Monday-Sunday boundaries for the most recently completed week.
 */
export function getLastWeekBounds(
  referenceDate: Date = new Date()
): { weekStart: string; weekEnd: string } {
  const d = new Date(referenceDate);
  // Go to most recent Sunday (end of last week)
  const dayOfWeek = d.getDay(); // 0=Sun, 1=Mon...
  // If it's Monday-Saturday, last Sunday was (dayOfWeek) days ago
  // If it's Sunday, last Sunday was today (7 days ago for the PREVIOUS week)
  const daysToLastSunday = dayOfWeek === 0 ? 0 : dayOfWeek;
  d.setDate(d.getDate() - daysToLastSunday);
  const weekEnd = d.toISOString().split("T")[0];

  // Monday is 6 days before Sunday
  d.setDate(d.getDate() - 6);
  const weekStart = d.toISOString().split("T")[0];

  return { weekStart, weekEnd };
}
