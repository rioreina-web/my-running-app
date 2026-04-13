/**
 * Athlete Profile Builder
 *
 * Aggregates up to 5 years of training history into a comprehensive,
 * recency-weighted athlete profile. This profile captures patterns,
 * trajectory, injury history, and preferences that make AI coaching
 * deeply personalized — even on the first message of a new conversation.
 *
 * Recency weighting tiers:
 *   Last 6 months  → 1.0x (current fitness & habits)
 *   6–12 months    → 0.6x (recent history)
 *   1–2 years      → 0.3x (established patterns)
 *   2+ years       → 0.15x (long-term baseline)
 */

// ─── Types ──────────────────────────────────────────────────────────────────

export interface TrainingLogRow {
  id?: string;
  created_at: string;
  workout_date?: string;
  workout_distance_miles?: number;
  workout_duration_minutes?: number;
  mood?: string;
  cleaned_notes?: string;
  notes?: string;
  coach_insight?: string;
  workout_type?: string;
}

export interface InjuryRow {
  id: string;
  body_area: string;
  side: string;
  severity: number;
  status: string;
  onset_date?: string;
  resolved_date?: string;
  created_at: string;
  notes?: string;
}

export interface FitnessSnapshotRow {
  predicted_marathon_seconds: number;
  predicted_half_seconds: number;
  predicted_10k_seconds: number;
  predicted_5k_seconds: number;
  confidence: string;
  created_at: string;
}

export interface FormCheckRow {
  ai_analysis?: Record<string, unknown> | null;
  ai_findings?: Array<Record<string, unknown>> | null;
  created_at: string;
}

export interface BiomechanicsRow {
  overall_score?: number;
  ai_analysis?: Record<string, unknown> | null;
  created_at: string;
}

export interface GoalRow {
  goal_title: string;
  target_date: string;
  status: string;
  created_at: string;
}

export interface TrainingPlanRow {
  name: string;
  target_race_distance?: string;
  target_time_seconds?: number;
  start_date: string;
  end_date?: string;
  status: string;
}

// ─── Recency Weights ────────────────────────────────────────────────────────

const RECENCY_TIERS = [
  { label: "last_6_months", months: 6, weight: 1.0 },
  { label: "6_to_12_months", months: 12, weight: 0.6 },
  { label: "1_to_2_years", months: 24, weight: 0.3 },
  { label: "2_plus_years", months: 60, weight: 0.15 },
] as const;

function getRecencyWeight(date: Date, now: Date): number {
  const monthsAgo = (now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24 * 30.44);
  if (monthsAgo <= 6) return 1.0;
  if (monthsAgo <= 12) return 0.6;
  if (monthsAgo <= 24) return 0.3;
  return 0.15;
}

function getRecencyTier(date: Date, now: Date): string {
  const monthsAgo = (now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24 * 30.44);
  if (monthsAgo <= 6) return "last_6_months";
  if (monthsAgo <= 12) return "6_to_12_months";
  if (monthsAgo <= 24) return "1_to_2_years";
  return "2_plus_years";
}

function getLogDate(log: TrainingLogRow): Date {
  return new Date(log.workout_date || log.created_at);
}

// ─── Profile Structure ──────────────────────────────────────────────────────

export interface AthleteProfile {
  built_at: string;
  data_span_months: number;
  total_logs: number;

  // Volume patterns by recency tier
  volume: {
    tier: string;
    weight: number;
    total_runs: number;
    total_miles: number;
    avg_weekly_miles: number;
    peak_weekly_miles: number;
    avg_runs_per_week: number;
    avg_run_distance: number;
  }[];

  // Overall volume summary
  volume_summary: {
    current_weekly_avg: number;
    peak_weekly_ever: number;
    longest_run_ever: number;
    total_lifetime_miles: number;
    consistency_score: number; // 0-1, how often they run vs skip
  };

  // Pace trajectory
  pace: {
    tier: string;
    avg_pace_seconds_per_mile: number;
    easy_pace: number;
    fastest_pace: number;
  }[];

  // Performance trajectory (from fitness snapshots)
  performance_trajectory: {
    date: string;
    predicted_5k: string;
    predicted_10k: string;
    predicted_half: string;
    predicted_marathon: string;
  }[];

  // Injury history
  injury_history: {
    body_area: string;
    side: string;
    occurrences: number;
    most_recent: string;
    avg_severity: number;
    is_recurring: boolean;
  }[];

  // Recovery patterns
  recovery: {
    avg_mood_positive_pct: number;
    fatigue_after_high_volume_weeks: boolean;
    typical_easy_day_frequency: number; // easy days per week
  };

  // Training preferences
  preferences: {
    most_common_workout_types: string[];
    avg_long_run_distance: number;
    preferred_run_days: string[]; // day names
    trains_consecutively: boolean; // back-to-back days common
  };

  // Biomechanics summary (if available)
  biomechanics?: {
    latest_score: number;
    trend: "improving" | "stable" | "declining";
    key_findings: string[];
  };

  // Goal history
  goal_history: {
    completed: number;
    active: number;
    race_distances_targeted: string[];
  };

  // Pace development by workout type (faster paces over time = development)
  workout_pace_development: {
    workout_type: string;
    current_avg_pace: number;     // seconds/mi (last 6 weeks)
    previous_avg_pace: number;    // seconds/mi (6 weeks before that)
    change_seconds: number;       // negative = faster = improving
    sample_size: number;
  }[];

  // Training response: how athlete handles hard sessions
  training_response: {
    hard_session_recovery_mood: number;  // avg mood score day after hard sessions (0-1)
    easy_after_hard_pct: number;         // % of time an easy day follows a hard day
    bounce_back_quality: "strong" | "moderate" | "poor"; // overall assessment
  };

  // Long run quality
  long_run_quality: {
    avg_distance: number;
    avg_pace: number;              // seconds/mi
    pace_consistency: number;      // 0-1 (1 = very steady across long runs)
    progression_trend: "building" | "steady" | "declining";
    recent_long_runs: { date: string; distance: number; pace: string }[];
  };

  // Overall development status
  development_status: {
    rating: "developing" | "maintaining" | "detraining";
    confidence: "high" | "medium" | "low";
    signals: string[];             // human-readable reasons for the rating
    volume_trend: "increasing" | "stable" | "decreasing";
    pace_trend: "faster" | "stable" | "slower";
    fitness_trend: "improving" | "stable" | "declining";
  };
}

// ─── Profile Builder ────────────────────────────────────────────────────────

export function buildAthleteProfile(opts: {
  logs: TrainingLogRow[];
  injuries: InjuryRow[];
  fitnessSnapshots: FitnessSnapshotRow[];
  formChecks: FormCheckRow[];
  biomechanics: BiomechanicsRow[];
  goals: GoalRow[];
  plans: TrainingPlanRow[];
}): AthleteProfile {
  const now = new Date();
  const { logs, injuries, fitnessSnapshots, formChecks, biomechanics, goals, plans } = opts;

  // Sort logs by date
  const sortedLogs = [...logs].sort((a, b) => getLogDate(b).getTime() - getLogDate(a).getTime());

  // Calculate data span
  const oldestLog = sortedLogs.length > 0 ? getLogDate(sortedLogs[sortedLogs.length - 1]) : now;
  const dataSpanMonths = Math.ceil((now.getTime() - oldestLog.getTime()) / (1000 * 60 * 60 * 24 * 30.44));

  // ── Volume by recency tier ──
  const volumeByTier = buildVolumeByTier(sortedLogs, now);

  // ── Volume summary ──
  const volumeSummary = buildVolumeSummary(sortedLogs, now);

  // ── Pace by tier ──
  const paceByTier = buildPaceByTier(sortedLogs, now);

  // ── Performance trajectory ──
  const performanceTrajectory = buildPerformanceTrajectory(fitnessSnapshots);

  // ── Injury history ──
  const injuryHistory = buildInjuryHistory(injuries);

  // ── Recovery patterns ──
  const recovery = buildRecoveryPatterns(sortedLogs, now);

  // ── Training preferences ──
  const preferences = buildPreferences(sortedLogs, now);

  // ── Biomechanics ──
  const biomechanicsSummary = buildBiomechanicsSummary(biomechanics);

  // ── Goal history ──
  const goalHistory = buildGoalHistory(goals, plans);

  // ── Workout pace development ──
  const workoutPaceDev = buildWorkoutPaceDevelopment(sortedLogs, now);

  // ── Training response quality ──
  const trainingResponse = buildTrainingResponse(sortedLogs, now);

  // ── Long run quality ──
  const longRunQuality = buildLongRunQuality(sortedLogs, now);

  // ── Overall development status ──
  const developmentStatus = buildDevelopmentStatus(
    sortedLogs, fitnessSnapshots, workoutPaceDev, volumeByTier, now
  );

  return {
    built_at: now.toISOString(),
    data_span_months: dataSpanMonths,
    total_logs: sortedLogs.length,
    volume: volumeByTier,
    volume_summary: volumeSummary,
    pace: paceByTier,
    performance_trajectory: performanceTrajectory,
    injury_history: injuryHistory,
    recovery,
    preferences,
    biomechanics: biomechanicsSummary,
    goal_history: goalHistory,
    workout_pace_development: workoutPaceDev,
    training_response: trainingResponse,
    long_run_quality: longRunQuality,
    development_status: developmentStatus,
  };
}

// ─── Volume by Tier ─────────────────────────────────────────────────────────

function buildVolumeByTier(
  logs: TrainingLogRow[],
  now: Date
): AthleteProfile["volume"] {
  const tiers: Record<string, { weight: number; logs: TrainingLogRow[]; weeks: Set<string> }> = {};

  for (const tier of RECENCY_TIERS) {
    tiers[tier.label] = { weight: tier.weight, logs: [], weeks: new Set() };
  }

  for (const log of logs) {
    const date = getLogDate(log);
    const tierLabel = getRecencyTier(date, now);
    if (tiers[tierLabel]) {
      tiers[tierLabel].logs.push(log);
      // Week key for counting unique weeks
      const weekStart = new Date(date);
      weekStart.setDate(date.getDate() - date.getDay() + 1);
      tiers[tierLabel].weeks.add(weekStart.toISOString().split("T")[0]);
    }
  }

  return Object.entries(tiers)
    .filter(([_, data]) => data.logs.length > 0)
    .map(([label, data]) => {
      const totalMiles = data.logs.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
      const numWeeks = Math.max(1, data.weeks.size);

      // Weekly miles breakdown for peak calculation
      const weeklyMiles: Record<string, number> = {};
      for (const log of data.logs) {
        const date = getLogDate(log);
        const weekStart = new Date(date);
        weekStart.setDate(date.getDate() - date.getDay() + 1);
        const key = weekStart.toISOString().split("T")[0];
        weeklyMiles[key] = (weeklyMiles[key] || 0) + (log.workout_distance_miles || 0);
      }
      const peakWeek = Math.max(...Object.values(weeklyMiles), 0);

      return {
        tier: label,
        weight: data.weight,
        total_runs: data.logs.length,
        total_miles: round(totalMiles),
        avg_weekly_miles: round(totalMiles / numWeeks),
        peak_weekly_miles: round(peakWeek),
        avg_runs_per_week: round(data.logs.length / numWeeks, 1),
        avg_run_distance: round(totalMiles / Math.max(1, data.logs.length)),
      };
    });
}

// ─── Volume Summary ─────────────────────────────────────────────────────────

function buildVolumeSummary(
  logs: TrainingLogRow[],
  now: Date
): AthleteProfile["volume_summary"] {
  // Current weekly average (last 4 weeks)
  const fourWeeksAgo = new Date(now.getTime() - 28 * 24 * 60 * 60 * 1000);
  const recentLogs = logs.filter((l) => getLogDate(l) >= fourWeeksAgo);
  const recentMiles = recentLogs.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
  const currentWeeklyAvg = recentMiles / 4;

  // All-time weekly miles for peak
  const weeklyMiles: Record<string, number> = {};
  let longestRun = 0;
  let totalMiles = 0;

  for (const log of logs) {
    const dist = log.workout_distance_miles || 0;
    totalMiles += dist;
    if (dist > longestRun) longestRun = dist;

    const date = getLogDate(log);
    const weekStart = new Date(date);
    weekStart.setDate(date.getDate() - date.getDay() + 1);
    const key = weekStart.toISOString().split("T")[0];
    weeklyMiles[key] = (weeklyMiles[key] || 0) + dist;
  }

  const peakWeekly = Math.max(...Object.values(weeklyMiles), 0);

  // Consistency: what % of weeks in the last 6 months had at least 1 run
  const sixMonthsAgo = new Date(now.getTime() - 183 * 24 * 60 * 60 * 1000);
  const recentWeeks = new Set<string>();
  for (const log of logs) {
    const date = getLogDate(log);
    if (date >= sixMonthsAgo) {
      const weekStart = new Date(date);
      weekStart.setDate(date.getDate() - date.getDay() + 1);
      recentWeeks.add(weekStart.toISOString().split("T")[0]);
    }
  }
  const totalPossibleWeeks = Math.ceil(183 / 7);
  const consistencyScore = Math.min(1, recentWeeks.size / totalPossibleWeeks);

  return {
    current_weekly_avg: round(currentWeeklyAvg),
    peak_weekly_ever: round(peakWeekly),
    longest_run_ever: round(longestRun),
    total_lifetime_miles: round(totalMiles),
    consistency_score: round(consistencyScore, 2),
  };
}

// ─── Pace by Tier ───────────────────────────────────────────────────────────

function buildPaceByTier(
  logs: TrainingLogRow[],
  now: Date
): AthleteProfile["pace"] {
  const tiers: Record<string, { paces: number[] }> = {};

  for (const log of logs) {
    const dist = log.workout_distance_miles || 0;
    const dur = log.workout_duration_minutes || 0;
    if (dist <= 0 || dur <= 0) continue;

    const paceSecsPerMile = (dur / dist) * 60;
    // Filter unreasonable paces (sub-4:00 or over 15:00)
    if (paceSecsPerMile < 240 || paceSecsPerMile > 900) continue;

    const tier = getRecencyTier(getLogDate(log), now);
    if (!tiers[tier]) tiers[tier] = { paces: [] };
    tiers[tier].paces.push(paceSecsPerMile);
  }

  return Object.entries(tiers).map(([tier, data]) => {
    const sorted = [...data.paces].sort((a, b) => a - b);
    const avg = sorted.reduce((a, b) => a + b, 0) / sorted.length;
    // Easy pace = 75th percentile (slower runs)
    const easyIdx = Math.floor(sorted.length * 0.75);
    // Fastest pace = 10th percentile
    const fastIdx = Math.floor(sorted.length * 0.1);

    return {
      tier,
      avg_pace_seconds_per_mile: Math.round(avg),
      easy_pace: Math.round(sorted[easyIdx] || avg),
      fastest_pace: Math.round(sorted[fastIdx] || avg),
    };
  });
}

// ─── Performance Trajectory ─────────────────────────────────────────────────

function buildPerformanceTrajectory(
  snapshots: FitnessSnapshotRow[]
): AthleteProfile["performance_trajectory"] {
  // Take up to 12 snapshots spread over time
  const sorted = [...snapshots].sort(
    (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
  );

  // Sample evenly if too many
  let sampled = sorted;
  if (sorted.length > 12) {
    const step = Math.floor(sorted.length / 12);
    sampled = [];
    for (let i = 0; i < sorted.length; i += step) {
      sampled.push(sorted[i]);
    }
    // Always include most recent
    if (sampled[sampled.length - 1] !== sorted[sorted.length - 1]) {
      sampled.push(sorted[sorted.length - 1]);
    }
  }

  return sampled.map((s) => ({
    date: new Date(s.created_at).toISOString().split("T")[0],
    predicted_5k: formatTime(s.predicted_5k_seconds),
    predicted_10k: formatTime(s.predicted_10k_seconds),
    predicted_half: formatTime(s.predicted_half_seconds),
    predicted_marathon: formatTime(s.predicted_marathon_seconds),
  }));
}

// ─── Injury History ─────────────────────────────────────────────────────────

function buildInjuryHistory(injuries: InjuryRow[]): AthleteProfile["injury_history"] {
  // Group by body_area + side
  const groups: Record<string, InjuryRow[]> = {};
  for (const injury of injuries) {
    const key = `${injury.body_area}|${injury.side}`;
    if (!groups[key]) groups[key] = [];
    groups[key].push(injury);
  }

  return Object.entries(groups).map(([key, items]) => {
    const [bodyArea, side] = key.split("|");
    const sorted = items.sort(
      (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    );
    const avgSeverity = items.reduce((sum, i) => sum + i.severity, 0) / items.length;

    return {
      body_area: bodyArea,
      side,
      occurrences: items.length,
      most_recent: sorted[0].created_at.split("T")[0],
      avg_severity: round(avgSeverity, 1),
      is_recurring: items.length >= 2,
    };
  });
}

// ─── Recovery Patterns ──────────────────────────────────────────────────────

function buildRecoveryPatterns(
  logs: TrainingLogRow[],
  now: Date
): AthleteProfile["recovery"] {
  // Use last 6 months for recovery analysis
  const sixMonthsAgo = new Date(now.getTime() - 183 * 24 * 60 * 60 * 1000);
  const recentLogs = logs.filter((l) => getLogDate(l) >= sixMonthsAgo);

  // Mood analysis
  const moods = recentLogs.map((l) => l.mood).filter(Boolean) as string[];
  const positiveMoods = ["energized", "strong", "great", "good", "positive", "motivated", "happy"];
  const positiveCount = moods.filter((m) => positiveMoods.includes(m.toLowerCase())).length;
  const moodPositivePct = moods.length > 0 ? positiveCount / moods.length : 0.5;

  // Check for fatigue after high-volume weeks
  const weeklyData: Record<string, { miles: number; nextWeekMoods: string[] }> = {};
  for (const log of recentLogs) {
    const date = getLogDate(log);
    const weekStart = new Date(date);
    weekStart.setDate(date.getDate() - date.getDay() + 1);
    const key = weekStart.toISOString().split("T")[0];
    if (!weeklyData[key]) weeklyData[key] = { miles: 0, nextWeekMoods: [] };
    weeklyData[key].miles += log.workout_distance_miles || 0;
  }

  // Easy day frequency: runs with pace > 75th percentile
  const pacedLogs = recentLogs.filter(
    (l) => (l.workout_distance_miles || 0) > 0 && (l.workout_duration_minutes || 0) > 0
  );
  const paces = pacedLogs.map(
    (l) => ((l.workout_duration_minutes || 0) / (l.workout_distance_miles || 1)) * 60
  );
  const sortedPaces = [...paces].sort((a, b) => a - b);
  const p75 = sortedPaces[Math.floor(sortedPaces.length * 0.65)] || 0;
  const easyRuns = paces.filter((p) => p >= p75).length;
  const weeksCount = Math.max(1, new Set(
    recentLogs.map((l) => {
      const d = getLogDate(l);
      const ws = new Date(d);
      ws.setDate(d.getDate() - d.getDay() + 1);
      return ws.toISOString().split("T")[0];
    })
  ).size);
  const easyDayFreq = easyRuns / weeksCount;

  return {
    avg_mood_positive_pct: round(moodPositivePct, 2),
    fatigue_after_high_volume_weeks: false, // simplified — would need next-week mood correlation
    typical_easy_day_frequency: round(easyDayFreq, 1),
  };
}

// ─── Training Preferences ───────────────────────────────────────────────────

function buildPreferences(
  logs: TrainingLogRow[],
  now: Date
): AthleteProfile["preferences"] {
  // Use last 6 months for current preferences
  const sixMonthsAgo = new Date(now.getTime() - 183 * 24 * 60 * 60 * 1000);
  const recentLogs = logs.filter((l) => getLogDate(l) >= sixMonthsAgo);

  // Workout types
  const typeCounts: Record<string, number> = {};
  for (const log of recentLogs) {
    const type = log.workout_type || "unknown";
    typeCounts[type] = (typeCounts[type] || 0) + 1;
  }
  const sortedTypes = Object.entries(typeCounts)
    .sort((a, b) => b[1] - a[1])
    .filter(([t]) => t !== "unknown")
    .slice(0, 5)
    .map(([t]) => t);

  // Long run distance (runs > 10 miles or top 10% by distance)
  const distances = recentLogs
    .map((l) => l.workout_distance_miles || 0)
    .filter((d) => d > 0)
    .sort((a, b) => b - a);
  const longRunThreshold = Math.max(10, distances[Math.floor(distances.length * 0.1)] || 10);
  const longRuns = distances.filter((d) => d >= longRunThreshold);
  const avgLongRun = longRuns.length > 0
    ? longRuns.reduce((a, b) => a + b, 0) / longRuns.length
    : 0;

  // Preferred run days
  const dayCounts: Record<string, number> = {};
  const dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  for (const log of recentLogs) {
    const day = dayNames[getLogDate(log).getDay()];
    dayCounts[day] = (dayCounts[day] || 0) + 1;
  }
  const preferredDays = Object.entries(dayCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 4)
    .map(([day]) => day);

  // Consecutive running days
  const dateSet = new Set(
    recentLogs.map((l) => getLogDate(l).toISOString().split("T")[0])
  );
  let consecutiveCount = 0;
  let totalChecked = 0;
  for (const dateStr of dateSet) {
    const nextDay = new Date(dateStr);
    nextDay.setDate(nextDay.getDate() + 1);
    if (dateSet.has(nextDay.toISOString().split("T")[0])) {
      consecutiveCount++;
    }
    totalChecked++;
  }
  const trainsConsecutively = totalChecked > 0 && (consecutiveCount / totalChecked) > 0.5;

  return {
    most_common_workout_types: sortedTypes,
    avg_long_run_distance: round(avgLongRun),
    preferred_run_days: preferredDays,
    trains_consecutively: trainsConsecutively,
  };
}

// ─── Biomechanics Summary ───────────────────────────────────────────────────

function buildBiomechanicsSummary(
  biomechanics: BiomechanicsRow[]
): AthleteProfile["biomechanics"] | undefined {
  if (biomechanics.length === 0) return undefined;

  const sorted = [...biomechanics].sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  );

  const latest = sorted[0];
  const latestScore = latest.overall_score || 0;

  // Trend from last 3 analyses
  let trend: "improving" | "stable" | "declining" = "stable";
  if (sorted.length >= 2) {
    const scores = sorted.slice(0, 3).map((b) => b.overall_score || 0);
    const newest = scores[0];
    const oldest = scores[scores.length - 1];
    if (newest > oldest + 0.5) trend = "improving";
    else if (newest < oldest - 0.5) trend = "declining";
  }

  // Key findings from latest analysis
  const keyFindings: string[] = [];
  if (latest.ai_analysis) {
    const analysis = latest.ai_analysis as Record<string, unknown>;
    if (analysis.form_assessment && typeof analysis.form_assessment === "string") {
      keyFindings.push(analysis.form_assessment.slice(0, 200));
    }
    const findings = (analysis.findings as Array<Record<string, unknown>>) || [];
    for (const finding of findings.slice(0, 3)) {
      if (finding.observation && typeof finding.observation === "string") {
        keyFindings.push(finding.observation.slice(0, 100));
      }
    }
  }

  return {
    latest_score: latestScore,
    trend,
    key_findings: keyFindings,
  };
}

// ─── Goal History ───────────────────────────────────────────────────────────

function buildGoalHistory(
  goals: GoalRow[],
  plans: TrainingPlanRow[]
): AthleteProfile["goal_history"] {
  const completed = goals.filter((g) => g.status === "completed").length;
  const active = goals.filter((g) => g.status === "active").length;

  const raceDistances = new Set<string>();
  for (const plan of plans) {
    if (plan.target_race_distance) {
      raceDistances.add(plan.target_race_distance);
    }
  }
  for (const goal of goals) {
    const title = goal.goal_title.toLowerCase();
    if (title.includes("marathon") && !title.includes("half")) raceDistances.add("marathon");
    if (title.includes("half")) raceDistances.add("half_marathon");
    if (title.includes("10k")) raceDistances.add("10k");
    if (title.includes("5k")) raceDistances.add("5k");
  }

  return {
    completed,
    active,
    race_distances_targeted: Array.from(raceDistances),
  };
}

// ─── Workout Pace Development ────────────────────────────────────────────────

function buildWorkoutPaceDevelopment(
  logs: TrainingLogRow[],
  now: Date
): AthleteProfile["workout_pace_development"] {
  const sixWeeksAgo = new Date(now.getTime() - 42 * 24 * 60 * 60 * 1000);
  const twelveWeeksAgo = new Date(now.getTime() - 84 * 24 * 60 * 60 * 1000);

  // Workout types we care about for pace development
  const trackedTypes = ["easy", "recovery", "long_run", "tempo", "threshold", "interval", "steady", "marathon_pace", "moderate"];

  const results: AthleteProfile["workout_pace_development"] = [];

  for (const wType of trackedTypes) {
    const recentLogs = logs.filter((l) => {
      const d = getLogDate(l);
      return d >= sixWeeksAgo && normalizeWorkoutType(l.workout_type) === wType &&
        (l.workout_distance_miles || 0) > 0 && (l.workout_duration_minutes || 0) > 0;
    });
    const previousLogs = logs.filter((l) => {
      const d = getLogDate(l);
      return d >= twelveWeeksAgo && d < sixWeeksAgo && normalizeWorkoutType(l.workout_type) === wType &&
        (l.workout_distance_miles || 0) > 0 && (l.workout_duration_minutes || 0) > 0;
    });

    if (recentLogs.length < 2 || previousLogs.length < 2) continue;

    const avgPace = (logsArr: TrainingLogRow[]) => {
      const paces = logsArr.map((l) => ((l.workout_duration_minutes || 0) / (l.workout_distance_miles || 1)) * 60)
        .filter((p) => p >= 240 && p <= 900); // reasonable paces
      return paces.length > 0 ? paces.reduce((a, b) => a + b, 0) / paces.length : 0;
    };

    const currentPace = avgPace(recentLogs);
    const previousPace = avgPace(previousLogs);

    if (currentPace > 0 && previousPace > 0) {
      results.push({
        workout_type: wType,
        current_avg_pace: Math.round(currentPace),
        previous_avg_pace: Math.round(previousPace),
        change_seconds: Math.round(currentPace - previousPace),
        sample_size: recentLogs.length + previousLogs.length,
      });
    }
  }

  return results;
}

function normalizeWorkoutType(type?: string): string {
  if (!type) return "unknown";
  const t = type.toLowerCase().replace(/[_\s-]+/g, "_");
  if (t.includes("easy") || t.includes("recovery")) return t.includes("recovery") ? "recovery" : "easy";
  if (t.includes("long")) return "long_run";
  if (t.includes("tempo") || t.includes("threshold")) return "tempo";
  if (t.includes("interval") || t.includes("repeat") || t.includes("speed")) return "interval";
  if (t.includes("steady") || t.includes("moderate")) return "steady";
  if (t.includes("marathon") || t.includes("mp")) return "marathon_pace";
  return t;
}

// ─── Training Response Quality ──────────────────────────────────────────────

function buildTrainingResponse(
  logs: TrainingLogRow[],
  now: Date
): AthleteProfile["training_response"] {
  const sixMonthsAgo = new Date(now.getTime() - 183 * 24 * 60 * 60 * 1000);
  const recentLogs = logs
    .filter((l) => getLogDate(l) >= sixMonthsAgo)
    .sort((a, b) => getLogDate(a).getTime() - getLogDate(b).getTime());

  const hardTypes = new Set(["tempo", "threshold", "interval", "speed", "repeat", "race", "time_trial"]);
  const easyTypes = new Set(["easy", "recovery"]);
  const positiveMoods = new Set(["energized", "strong", "great", "good", "positive", "motivated"]);
  const negativeMoods = new Set(["tired", "sluggish", "fatigued", "struggling", "exhausted"]);

  let hardDays = 0;
  let easyAfterHard = 0;
  let dayAfterHardMoodScores: number[] = [];

  for (let i = 0; i < recentLogs.length - 1; i++) {
    const current = recentLogs[i];
    const next = recentLogs[i + 1];
    const currentType = normalizeWorkoutType(current.workout_type);

    if (hardTypes.has(currentType) || currentType === "long_run") {
      hardDays++;

      // Check if next day is within 2 days
      const dayGap = (getLogDate(next).getTime() - getLogDate(current).getTime()) / (1000 * 60 * 60 * 24);
      if (dayGap <= 2) {
        const nextType = normalizeWorkoutType(next.workout_type);
        if (easyTypes.has(nextType)) easyAfterHard++;

        // Score mood: positive=1, neutral=0.5, negative=0
        const mood = (next.mood || "").toLowerCase();
        if (positiveMoods.has(mood)) dayAfterHardMoodScores.push(1);
        else if (negativeMoods.has(mood)) dayAfterHardMoodScores.push(0);
        else if (mood) dayAfterHardMoodScores.push(0.5);
      }
    }
  }

  const avgMood = dayAfterHardMoodScores.length > 0
    ? dayAfterHardMoodScores.reduce((a, b) => a + b, 0) / dayAfterHardMoodScores.length
    : 0.5;
  const easyPct = hardDays > 0 ? easyAfterHard / hardDays : 0;

  let bounceBack: "strong" | "moderate" | "poor" = "moderate";
  if (avgMood >= 0.6 && easyPct >= 0.5) bounceBack = "strong";
  else if (avgMood < 0.4 || easyPct < 0.3) bounceBack = "poor";

  return {
    hard_session_recovery_mood: round(avgMood, 2),
    easy_after_hard_pct: round(easyPct, 2),
    bounce_back_quality: bounceBack,
  };
}

// ─── Long Run Quality ───────────────────────────────────────────────────────

function buildLongRunQuality(
  logs: TrainingLogRow[],
  now: Date
): AthleteProfile["long_run_quality"] {
  const sixMonthsAgo = new Date(now.getTime() - 183 * 24 * 60 * 60 * 1000);

  // Identify long runs: type contains "long" OR top 15% distance within last 6 months
  const recentLogs = logs.filter((l) => getLogDate(l) >= sixMonthsAgo && (l.workout_distance_miles || 0) > 0);
  const distances = recentLogs.map((l) => l.workout_distance_miles || 0).sort((a, b) => b - a);
  const longThreshold = Math.max(8, distances[Math.floor(distances.length * 0.15)] || 8);

  const longRuns = recentLogs.filter((l) => {
    const type = normalizeWorkoutType(l.workout_type);
    const dist = l.workout_distance_miles || 0;
    return type === "long_run" || dist >= longThreshold;
  }).filter((l) => (l.workout_duration_minutes || 0) > 0)
    .sort((a, b) => getLogDate(a).getTime() - getLogDate(b).getTime());

  if (longRuns.length === 0) {
    return {
      avg_distance: 0,
      avg_pace: 0,
      pace_consistency: 0,
      progression_trend: "steady",
      recent_long_runs: [],
    };
  }

  const paces = longRuns.map((l) => ((l.workout_duration_minutes || 0) / (l.workout_distance_miles || 1)) * 60);
  const avgDist = longRuns.reduce((s, l) => s + (l.workout_distance_miles || 0), 0) / longRuns.length;
  const avgPace = paces.reduce((a, b) => a + b, 0) / paces.length;

  // Pace consistency: only score runs that are true steady-effort long runs.
  // Structured long runs (fartleks, progressions, repeats, broken thresholds)
  // will naturally have variable pacing — don't penalize those.
  const steadyLongRuns = longRuns.filter((l) => {
    const type = normalizeWorkoutType(l.workout_type);
    const structuredTypes = new Set(["fartlek", "progression", "interval", "repeat", "tempo", "threshold"]);
    // Also check notes for structured workout indicators
    const notes = (l.cleaned_notes || l.notes || "").toLowerCase();
    const structuredNotes = /fartlek|progression|repeat|broken|cutdown|negative split|pick.?up/i.test(notes);
    return !structuredTypes.has(type) && !structuredNotes;
  });
  const steadyPaces = steadyLongRuns
    .filter((l) => (l.workout_duration_minutes || 0) > 0)
    .map((l) => ((l.workout_duration_minutes || 0) / (l.workout_distance_miles || 1)) * 60);
  const consistencyPaces = steadyPaces.length >= 2 ? steadyPaces : paces;
  const consistencyAvg = consistencyPaces.reduce((a, b) => a + b, 0) / consistencyPaces.length;
  const stdDev = Math.sqrt(consistencyPaces.reduce((s, p) => s + Math.pow(p - consistencyAvg, 2), 0) / consistencyPaces.length);
  // Normalize: stdDev of 0 = perfect (1.0), stdDev of 60s+ = poor (0.0)
  const consistency = Math.max(0, Math.min(1, 1 - stdDev / 60));

  // Progression: compare first half vs second half distances
  const mid = Math.floor(longRuns.length / 2);
  const firstHalfDist = longRuns.slice(0, mid).reduce((s, l) => s + (l.workout_distance_miles || 0), 0) / Math.max(1, mid);
  const secondHalfDist = longRuns.slice(mid).reduce((s, l) => s + (l.workout_distance_miles || 0), 0) / Math.max(1, longRuns.length - mid);

  let progression: "building" | "steady" | "declining" = "steady";
  if (secondHalfDist > firstHalfDist * 1.1) progression = "building";
  else if (secondHalfDist < firstHalfDist * 0.85) progression = "declining";

  // Last 5 long runs for detail
  const recentFive = longRuns.slice(-5).map((l) => ({
    date: getLogDate(l).toISOString().split("T")[0],
    distance: round(l.workout_distance_miles || 0),
    pace: formatPace(((l.workout_duration_minutes || 0) / (l.workout_distance_miles || 1)) * 60),
  }));

  return {
    avg_distance: round(avgDist),
    avg_pace: Math.round(avgPace),
    pace_consistency: round(consistency, 2),
    progression_trend: progression,
    recent_long_runs: recentFive,
  };
}

// ─── Development Status ─────────────────────────────────────────────────────

function buildDevelopmentStatus(
  logs: TrainingLogRow[],
  fitnessSnapshots: FitnessSnapshotRow[],
  workoutPaceDev: AthleteProfile["workout_pace_development"],
  volumeByTier: AthleteProfile["volume"],
  now: Date
): AthleteProfile["development_status"] {
  const signals: string[] = [];
  let volumeScore = 0;  // positive = increasing
  let paceScore = 0;    // positive = faster
  let fitnessScore = 0; // positive = improving

  // ── Volume trend: compare last 6 months avg weekly to 6-12 months ──
  const currentTier = volumeByTier.find((v) => v.tier === "last_6_months");
  const previousTier = volumeByTier.find((v) => v.tier === "6_to_12_months");

  if (currentTier && previousTier && previousTier.avg_weekly_miles > 0) {
    const volChange = (currentTier.avg_weekly_miles - previousTier.avg_weekly_miles) / previousTier.avg_weekly_miles;
    if (volChange > 0.1) {
      volumeScore = 1;
      signals.push(`Volume up ${Math.round(volChange * 100)}% (${previousTier.avg_weekly_miles} → ${currentTier.avg_weekly_miles} mi/wk)`);
    } else if (volChange < -0.15) {
      volumeScore = -1;
      signals.push(`Volume down ${Math.round(Math.abs(volChange) * 100)}% (${previousTier.avg_weekly_miles} → ${currentTier.avg_weekly_miles} mi/wk)`);
    } else {
      signals.push(`Volume stable (~${currentTier.avg_weekly_miles} mi/wk)`);
    }
  }

  // ── Consistency check: recent 8 weeks ──
  const eightWeeksAgo = new Date(now.getTime() - 56 * 24 * 60 * 60 * 1000);
  const recentWeeks = new Map<string, number>();
  for (const log of logs) {
    const d = getLogDate(log);
    if (d >= eightWeeksAgo) {
      const ws = new Date(d);
      ws.setDate(d.getDate() - d.getDay() + 1);
      const key = ws.toISOString().split("T")[0];
      recentWeeks.set(key, (recentWeeks.get(key) || 0) + (log.workout_distance_miles || 0));
    }
  }
  const weeksWithRuns = [...recentWeeks.values()].filter((m) => m > 0).length;
  if (weeksWithRuns < 5) {
    volumeScore -= 1;
    signals.push(`Only ${weeksWithRuns}/8 recent weeks with training — inconsistency risk`);
  }

  // ── Pace trend: aggregate workout pace improvements ──
  const improvingTypes = workoutPaceDev.filter((w) => w.change_seconds < -5);
  const slowingTypes = workoutPaceDev.filter((w) => w.change_seconds > 5);

  if (improvingTypes.length > slowingTypes.length && improvingTypes.length >= 2) {
    paceScore = 1;
    const examples = improvingTypes.slice(0, 2).map(
      (w) => `${w.workout_type} ${Math.abs(w.change_seconds)}s faster`
    );
    signals.push(`Paces improving: ${examples.join(", ")}`);
  } else if (slowingTypes.length > improvingTypes.length && slowingTypes.length >= 2) {
    paceScore = -1;
    const examples = slowingTypes.slice(0, 2).map(
      (w) => `${w.workout_type} ${w.change_seconds}s slower`
    );
    signals.push(`Paces slowing: ${examples.join(", ")}`);
  } else if (workoutPaceDev.length > 0) {
    signals.push("Paces holding steady across workout types");
  }

  // ── Fitness snapshot trend ──
  const sorted = [...fitnessSnapshots]
    .sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());

  if (sorted.length >= 3) {
    const recent = sorted.slice(-2);
    const older = sorted.slice(0, Math.ceil(sorted.length / 2));

    const recentAvg = recent.reduce((s, r) => s + r.predicted_marathon_seconds, 0) / recent.length;
    const olderAvg = older.reduce((s, r) => s + r.predicted_marathon_seconds, 0) / older.length;
    const delta = olderAvg - recentAvg; // positive = getting faster

    if (delta > 60) {
      fitnessScore = 1;
      signals.push(`Predicted marathon improving by ~${formatTime(delta)}`);
    } else if (delta < -60) {
      fitnessScore = -1;
      signals.push(`Predicted marathon declined by ~${formatTime(Math.abs(delta))}`);
    } else {
      signals.push("Race predictions stable");
    }
  }

  // ── Overall rating ──
  const totalScore = volumeScore + paceScore + fitnessScore;
  let rating: "developing" | "maintaining" | "detraining";
  if (totalScore >= 2) rating = "developing";
  else if (totalScore <= -2) rating = "detraining";
  else if (totalScore >= 1) rating = "developing";
  else if (totalScore <= -1) rating = "detraining";
  else rating = "maintaining";

  // Confidence based on data availability
  const dataPoints = [
    workoutPaceDev.length >= 2,
    fitnessSnapshots.length >= 3,
    (currentTier?.total_runs || 0) >= 15,
    (previousTier?.total_runs || 0) >= 10,
  ].filter(Boolean).length;

  const confidence = dataPoints >= 3 ? "high" : dataPoints >= 2 ? "medium" : "low";

  const volumeTrend = volumeScore > 0 ? "increasing" : volumeScore < 0 ? "decreasing" : "stable";
  const paceTrend = paceScore > 0 ? "faster" : paceScore < 0 ? "slower" : "stable";
  const fitnessTrend = fitnessScore > 0 ? "improving" : fitnessScore < 0 ? "declining" : "stable";

  return {
    rating,
    confidence,
    signals,
    volume_trend: volumeTrend as "increasing" | "stable" | "decreasing",
    pace_trend: paceTrend as "faster" | "stable" | "slower",
    fitness_trend: fitnessTrend as "improving" | "stable" | "declining",
  };
}

// ─── Context Formatter ──────────────────────────────────────────────────────

/**
 * Format the athlete profile as a concise context block for AI prompts.
 * Designed to be injected alongside training data for deeper personalization.
 * Typically ~200-400 tokens.
 */
export function buildAthleteProfileContext(profile: AthleteProfile): string {
  if (!profile || profile.total_logs === 0) {
    return "";
  }

  const parts: string[] = [];

  // Header
  parts.push(`\n=== ATHLETE PROFILE (${profile.data_span_months} months of data, ${profile.total_logs} logged runs) ===`);

  // Volume evolution
  if (profile.volume.length > 0) {
    parts.push("\nTraining Volume (recency-weighted):");
    for (const tier of profile.volume) {
      parts.push(`  ${formatTierLabel(tier.tier)} (weight ${tier.weight}x): ${tier.avg_weekly_miles} mi/wk avg, ${tier.peak_weekly_miles} mi/wk peak, ${tier.avg_runs_per_week} runs/wk`);
    }
  }

  // Current snapshot
  const vs = profile.volume_summary;
  parts.push(`\nCurrent Fitness Snapshot:`);
  parts.push(`  Weekly avg: ${vs.current_weekly_avg} mi | Peak ever: ${vs.peak_weekly_ever} mi/wk | Longest run: ${vs.longest_run_ever} mi`);
  parts.push(`  Lifetime miles: ${vs.total_lifetime_miles} | Consistency: ${Math.round(vs.consistency_score * 100)}%`);

  // Pace evolution
  if (profile.pace.length > 0) {
    parts.push("\nPace Evolution:");
    for (const tier of profile.pace) {
      parts.push(`  ${formatTierLabel(tier.tier)}: avg ${formatPace(tier.avg_pace_seconds_per_mile)}, easy ${formatPace(tier.easy_pace)}, fast ${formatPace(tier.fastest_pace)}`);
    }
  }

  // Performance trajectory
  if (profile.performance_trajectory.length >= 2) {
    const first = profile.performance_trajectory[0];
    const last = profile.performance_trajectory[profile.performance_trajectory.length - 1];
    parts.push(`\nPerformance Trajectory:`);
    parts.push(`  ${first.date}: 5K ${first.predicted_5k} | 10K ${first.predicted_10k} | Half ${first.predicted_half} | Marathon ${first.predicted_marathon}`);
    parts.push(`  ${last.date}: 5K ${last.predicted_5k} | 10K ${last.predicted_10k} | Half ${last.predicted_half} | Marathon ${last.predicted_marathon}`);
  }

  // Injury history
  if (profile.injury_history.length > 0) {
    parts.push("\nInjury History:");
    for (const injury of profile.injury_history.slice(0, 5)) {
      const recurring = injury.is_recurring ? " [RECURRING]" : "";
      parts.push(`  ${injury.side !== "unknown" ? injury.side + " " : ""}${injury.body_area}: ${injury.occurrences}x, severity ${injury.avg_severity}/10, last ${injury.most_recent}${recurring}`);
    }
  }

  // Recovery
  parts.push(`\nRecovery Profile:`);
  parts.push(`  Mood: ${Math.round(profile.recovery.avg_mood_positive_pct * 100)}% positive | Easy days: ~${profile.recovery.typical_easy_day_frequency}/week`);

  // Preferences
  const prefs = profile.preferences;
  if (prefs.most_common_workout_types.length > 0) {
    parts.push(`\nTraining Preferences:`);
    parts.push(`  Workout types: ${prefs.most_common_workout_types.join(", ")}`);
    if (prefs.avg_long_run_distance > 0) {
      parts.push(`  Avg long run: ${prefs.avg_long_run_distance} mi`);
    }
    parts.push(`  Preferred days: ${prefs.preferred_run_days.join(", ")}`);
    parts.push(`  Runs consecutive days: ${prefs.trains_consecutively ? "yes" : "rarely"}`);
  }

  // Biomechanics
  if (profile.biomechanics) {
    parts.push(`\nBiomechanics: score ${profile.biomechanics.latest_score}/10, trend ${profile.biomechanics.trend}`);
    if (profile.biomechanics.key_findings.length > 0) {
      parts.push(`  ${profile.biomechanics.key_findings[0]}`);
    }
  }

  // Goals
  if (profile.goal_history.race_distances_targeted.length > 0) {
    parts.push(`\nGoal History: ${profile.goal_history.completed} completed, ${profile.goal_history.active} active`);
    parts.push(`  Race distances: ${profile.goal_history.race_distances_targeted.join(", ")}`);
  }

  // Development Status (headline insight)
  if (profile.development_status) {
    const ds = profile.development_status;
    const ratingLabel = ds.rating === "developing" ? "DEVELOPING" : ds.rating === "detraining" ? "DETRAINING" : "MAINTAINING";
    parts.push(`\n*** DEVELOPMENT STATUS: ${ratingLabel} (${ds.confidence} confidence) ***`);
    parts.push(`  Volume: ${ds.volume_trend} | Paces: ${ds.pace_trend} | Fitness: ${ds.fitness_trend}`);
    for (const signal of ds.signals.slice(0, 4)) {
      parts.push(`  - ${signal}`);
    }
  }

  // Workout Pace Development (the specific type-by-type trends)
  if (profile.workout_pace_development && profile.workout_pace_development.length > 0) {
    parts.push("\nPace Development by Workout Type (last 6wk vs previous 6wk):");
    for (const wp of profile.workout_pace_development) {
      const direction = wp.change_seconds < 0 ? `${Math.abs(wp.change_seconds)}s FASTER` :
        wp.change_seconds > 0 ? `${wp.change_seconds}s slower` : "unchanged";
      parts.push(`  ${wp.workout_type}: ${formatPace(wp.current_avg_pace)} (was ${formatPace(wp.previous_avg_pace)}) → ${direction} [n=${wp.sample_size}]`);
    }
  }

  // Long Run Quality
  if (profile.long_run_quality && profile.long_run_quality.avg_distance > 0) {
    const lr = profile.long_run_quality;
    const steadiness = lr.pace_consistency >= 0.8 ? "very steady" : lr.pace_consistency >= 0.6 ? "moderately steady" : "inconsistent";
    parts.push(`\nLong Run Quality:`);
    parts.push(`  Avg distance: ${lr.avg_distance} mi at ${formatPace(lr.avg_pace)} | Pacing: ${steadiness} (${Math.round(lr.pace_consistency * 100)}%) | Trend: ${lr.progression_trend}`);
    if (lr.recent_long_runs.length > 0) {
      parts.push(`  Recent: ${lr.recent_long_runs.map((r) => `${r.date} ${r.distance}mi @ ${r.pace}`).join(" | ")}`);
    }
  }

  // Training Response
  if (profile.training_response) {
    const tr = profile.training_response;
    parts.push(`\nTraining Response: bounce-back ${tr.bounce_back_quality}`);
    parts.push(`  Mood after hard sessions: ${Math.round(tr.hard_session_recovery_mood * 100)}% positive | Easy day after hard: ${Math.round(tr.easy_after_hard_pct * 100)}%`);
  }

  parts.push("\n=== END ATHLETE PROFILE ===");

  return parts.join("\n");
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function round(n: number, decimals: number = 1): number {
  const factor = Math.pow(10, decimals);
  return Math.round(n * factor) / factor;
}

function formatTime(totalSeconds: number): string {
  if (!totalSeconds || totalSeconds <= 0) return "N/A";
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = Math.round(totalSeconds % 60);
  if (hours > 0) {
    return `${hours}:${minutes.toString().padStart(2, "0")}:${seconds.toString().padStart(2, "0")}`;
  }
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

function formatPace(secondsPerMile: number): string {
  if (!secondsPerMile || secondsPerMile <= 0) return "N/A";
  const mins = Math.floor(secondsPerMile / 60);
  const secs = Math.round(secondsPerMile % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}/mi`;
}

function formatTierLabel(tier: string): string {
  switch (tier) {
    case "last_6_months": return "Last 6mo";
    case "6_to_12_months": return "6-12mo ago";
    case "1_to_2_years": return "1-2yr ago";
    case "2_plus_years": return "2+ yr ago";
    default: return tier;
  }
}
