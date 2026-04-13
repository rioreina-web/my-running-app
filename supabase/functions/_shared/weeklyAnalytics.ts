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

export function calculateACWR(
  currentWeek: WeeklyLoad,
  previousWeeks: WeeklyLoad[]
): { acwr: number; chronicLoad: number; acuteLoad: number } {
  const acuteLoad = currentWeek.miles;

  if (previousWeeks.length === 0) {
    return { acwr: 1.0, chronicLoad: acuteLoad, acuteLoad };
  }

  // Exponentially weighted: most recent = 4, then 3, 2, 1
  const weights = [4, 3, 2, 1].slice(0, previousWeeks.length);
  const totalWeight = weights.reduce((s, w) => s + w, 0);
  const chronicLoad =
    previousWeeks.reduce((sum, week, i) => sum + week.miles * weights[i], 0) /
    totalWeight;

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

export function aggregateWeeklyLoad(logs: TrainingLogRow[]): WeeklyLoad {
  let miles = 0;
  let minutes = 0;
  let runCount = 0;

  for (const log of logs) {
    if (log.workout_distance_miles && log.workout_distance_miles > 0) {
      miles += log.workout_distance_miles;
      minutes += log.workout_duration_minutes || 0;
      runCount++;
    }
  }

  return { miles, minutes, runCount };
}

export function computeAllMetrics(
  thisWeekLogs: TrainingLogRow[],
  previousWeeksLogs: TrainingLogRow[][],
  scheduledThisWeek: ScheduledWorkoutRow[],
  activeInjuries: InjuryRow[],
  formChecks: FormCheckRow[],
  racePaceSecondsPerMile: number | null
): ComputedMetrics {
  const thisWeekLoad = aggregateWeeklyLoad(thisWeekLogs);
  const prevLoads = previousWeeksLogs.map(aggregateWeeklyLoad);

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
