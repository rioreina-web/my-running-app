/**
 * Real-Time Data Analysis for Coaching Intelligence
 *
 * Computes analytics from raw data and generates coaching signals —
 * data-driven insights that help the AI make decisions and ask
 * proactive questions during conversations.
 *
 * Used by coaching-agent to give the AI real-time awareness of:
 * - Workload trends (ACWR, volume changes)
 * - Compliance with training plan
 * - Mood and fatigue patterns
 * - Injury risk factors
 * - Fitness trajectory (predicted race times)
 * - Biomechanical concerns (form checks)
 */

import {
  computeAllMetrics,
  aggregateWeeklyLoad,
  formatPace,
  formatDuration,
  type TrainingLogRow,
  type ScheduledWorkoutRow,
  type InjuryRow,
  type FormCheckRow,
  type ComputedMetrics,
} from "./weeklyAnalytics.ts";

// ─── Types ──────────────────────────────────────────────────────────────────

export interface CoachingSignal {
  category: string;
  priority: "high" | "medium" | "low";
  insight: string;
  suggestedQuestion?: string;
}

export interface FitnessSnapshot {
  predicted_marathon_seconds: number;
  predicted_half_seconds: number;
  predicted_10k_seconds: number;
  predicted_5k_seconds: number;
  confidence: string;
  created_at: string;
}

export interface FormCheckResult {
  ai_analysis?: Record<string, unknown> | null;
  ai_findings?: Array<Record<string, unknown>> | null;
  created_at: string;
}

export interface AnalysisResult {
  metrics: ComputedMetrics | null;
  signals: CoachingSignal[];
  context: string;
}

// ─── Main Analysis Function ─────────────────────────────────────────────────

/**
 * Compute real-time analytics and generate coaching signals.
 * Call this from the coaching agent with data fetched in parallel.
 */
export function analyzeTrainingData(opts: {
  thisWeekLogs: TrainingLogRow[];
  previousWeeksLogs: TrainingLogRow[][];
  scheduledThisWeek: ScheduledWorkoutRow[];
  activeInjuries: InjuryRow[];
  formChecks: FormCheckResult[];
  fitnessSnapshots: FitnessSnapshot[];
  goalDaysRemaining: number | null;
  targetTimeSeconds: number | null;
  targetDistance: string | null;
  /** When false, metrics are computed but coaching signals (proactive questions) are excluded from context */
  includeSignals?: boolean;
}): AnalysisResult {
  const {
    thisWeekLogs,
    previousWeeksLogs,
    scheduledThisWeek,
    activeInjuries,
    formChecks,
    fitnessSnapshots,
    goalDaysRemaining,
    targetTimeSeconds,
    targetDistance,
    includeSignals = true,
  } = opts;

  // Need at least some data to analyze
  if (thisWeekLogs.length === 0 && previousWeeksLogs.every((w) => w.length === 0)) {
    return { metrics: null, signals: [], context: "" };
  }

  // Cast form checks to the type expected by weeklyAnalytics
  const formCheckRows: FormCheckRow[] = formChecks.map((fc) => ({
    ai_findings: (fc.ai_findings || fc.ai_analysis) as Record<string, unknown> | null,
    created_at: fc.created_at,
  }));

  // Compute metrics
  const metrics = computeAllMetrics(
    thisWeekLogs,
    previousWeeksLogs,
    scheduledThisWeek,
    activeInjuries as InjuryRow[],
    formCheckRows,
    null // race pace — we don't have it here, compliance still works without it
  );

  // Compute fitness gap
  let fitnessGapSeconds: number | null = null;
  if (targetTimeSeconds && fitnessSnapshots.length > 0 && targetDistance) {
    const predicted = getPredictedTime(fitnessSnapshots[0], targetDistance);
    if (predicted) {
      fitnessGapSeconds = predicted - targetTimeSeconds;
    }
  }

  // Generate coaching signals (only when Smart Insights is enabled)
  const signals = includeSignals
    ? generateCoachingSignals(
        metrics,
        formChecks,
        fitnessSnapshots,
        activeInjuries,
        goalDaysRemaining,
        fitnessGapSeconds
      )
    : [];

  // Compute workout type distribution from all available logs
  const allLogs = [...thisWeekLogs, ...previousWeeksLogs.flat()];
  const workoutTypeCounts: Record<string, number> = {};
  for (const log of allLogs) {
    const wType = log.workout_type || "unknown";
    if (wType !== "unknown") {
      workoutTypeCounts[wType] = (workoutTypeCounts[wType] || 0) + 1;
    }
  }

  // Extract fatigue signals from training log notes (last 2 weeks)
  const recentForFatigue = [...thisWeekLogs, ...(previousWeeksLogs[0] || [])];
  const fatigueSignals = extractFatigueSignals(recentForFatigue);

  // Assess quality of training volume (last 5 weeks)
  const qualityVolume = assessQualityVolume(allLogs, scheduledThisWeek);

  // Add fatigue-based coaching signals
  if (includeSignals) {
    signals.push(...generateFatigueSignals(fatigueSignals));
  }

  // Build context string — metrics always included, signals only when enabled
  const context = buildFullContext(metrics, signals, formChecks, fitnessSnapshots, fitnessGapSeconds, workoutTypeCounts, fatigueSignals, qualityVolume);

  return { metrics, signals, context };
}

// ─── Fatigue Signal Extraction from Training Log Notes ──────────────────────

interface FatigueSignal {
  type: "injury_mention" | "pace_struggle" | "underrecovery" | "overwork" | "pain" | "motivation";
  severity: "high" | "medium" | "low";
  text: string;          // the matched text from notes
  date: string;          // workout date
  source: "notes" | "mood";
}

const FATIGUE_PATTERNS: {
  type: FatigueSignal["type"];
  severity: FatigueSignal["severity"];
  patterns: RegExp[];
}[] = [
  // Injury mentions — runner is describing something hurting
  {
    type: "injury_mention",
    severity: "high",
    patterns: [
      /(?:sharp|stabbing|shooting)\s+pain/i,
      /(?:knee|achilles|calf|hamstring|shin|hip|ankle|foot|plantar|it band|quad|glute)\s+(?:is|was|felt|feeling|been|still)\s+(?:sore|tight|painful|hurting|aching|swollen|stiff|bothering)/i,
      /(?:sore|tight|painful|hurting|aching|swollen|stiff)\s+(?:knee|achilles|calf|hamstring|shin|hip|ankle|foot|plantar|quad|glute)/i,
      /(?:pulled|strained|tweaked|aggravated)\s+(?:my\s+)?(?:calf|hamstring|quad|hip|groin|achilles)/i,
      /limping|couldn't walk|hobbling/i,
    ],
  },
  {
    type: "pain",
    severity: "medium",
    patterns: [
      /(?:felt|feeling|noticed)\s+(?:a\s+)?(?:twinge|niggle|tightness|discomfort|pain)/i,
      /(?:knee|achilles|calf|hamstring|shin|hip|ankle|foot)\s+(?:acting up|flared|bugging)/i,
      /something\s+(?:felt|doesn't feel)\s+(?:off|wrong|weird)/i,
      /(?:had to|needed to)\s+(?:stop|cut it short|walk)\s+(?:because|due to)/i,
    ],
  },
  // Struggling to hit paces
  {
    type: "pace_struggle",
    severity: "high",
    patterns: [
      /couldn'?t\s+(?:hold|hit|maintain|sustain)\s+(?:the\s+)?(?:pace|tempo|target|goal)/i,
      /(?:fell off|dropped off|blew up|faded|died|bonked|cracked)\s+(?:at|after|in|during|the last)/i,
      /(?:way|much)\s+(?:slower|harder)\s+than\s+(?:expected|planned|it should|usual)/i,
      /(?:legs|body)\s+(?:just\s+)?(?:weren'?t|wasn'?t|not)\s+(?:there|responding|having it)/i,
    ],
  },
  {
    type: "pace_struggle",
    severity: "medium",
    patterns: [
      /(?:harder|tougher|more difficult)\s+than\s+(?:it should|expected|usual|normal)/i,
      /(?:pace|splits)\s+(?:were|was)\s+(?:all over|inconsistent|off|slow)/i,
      /(?:struggled|fighting|grinding|suffering|laboring)/i,
      /(?:felt like|running through)\s+(?:mud|concrete|quicksand)/i,
      /(?:HR|heart rate)\s+(?:was\s+)?(?:way\s+)?(?:higher|elevated|spiked)/i,
    ],
  },
  // Underrecovery signals
  {
    type: "underrecovery",
    severity: "high",
    patterns: [
      /(?:legs|body)\s+(?:were|was|felt)\s+(?:dead|trashed|destroyed|wrecked|shot|heavy|cement)/i,
      /(?:still|really|very|extremely|completely)\s+(?:tired|fatigued|exhausted|spent|drained|wiped)/i,
      /(?:no|zero|barely any)\s+(?:energy|power|pop|spring|legs)/i,
      /(?:didn'?t|don'?t)\s+(?:recover|sleep|rest)\s+(?:well|enough|at all)/i,
    ],
  },
  {
    type: "underrecovery",
    severity: "medium",
    patterns: [
      /(?:tired|fatigued|flat|sluggish|lethargic|heavy)\s+(?:legs|body|today|from|the whole)/i,
      /(?:felt|feeling)\s+(?:tired|beat up|run down|worn out|flat)/i,
      /(?:not|didn'?t feel)\s+(?:great|good|fresh|recovered|rested)/i,
      /sleep\s+(?:was|has been)\s+(?:bad|poor|terrible|rough|awful)/i,
      /(?:sore|stiff)\s+(?:all over|everywhere|from yesterday)/i,
    ],
  },
  // Overwork/burnout signals
  {
    type: "overwork",
    severity: "medium",
    patterns: [
      /(?:burned out|burnt out|over ?trained|running on empty)/i,
      /(?:too much|overdid it|pushed too hard|should have rested)/i,
      /(?:need|needed)\s+(?:a\s+)?(?:break|rest|day off|recovery)/i,
      /(?:body|legs)\s+(?:are|were)\s+(?:telling|begging)\s+(?:me to)/i,
    ],
  },
  // Motivation/mental signals
  {
    type: "motivation",
    severity: "low",
    patterns: [
      /(?:didn'?t|don'?t)\s+(?:want to|feel like)\s+(?:run|going|doing)/i,
      /(?:forced|dragged|made)\s+(?:myself|me)\s+(?:out|to run|through)/i,
      /(?:dreading|hated|awful|miserable)\s+(?:this|the|today)/i,
      /(?:mental|mentally)\s+(?:tough|hard|not there|checked out)/i,
    ],
  },
];

/**
 * Extract fatigue signals from training log notes.
 * Scans cleaned_notes and notes fields for injury mentions, pace struggles,
 * underrecovery signals, and motivation issues.
 */
function extractFatigueSignals(logs: TrainingLogRow[]): FatigueSignal[] {
  const signals: FatigueSignal[] = [];

  for (const log of logs) {
    const text = log.cleaned_notes || log.notes || "";
    if (text.length < 5) continue;

    const date = log.workout_date || "";

    for (const { type, severity, patterns } of FATIGUE_PATTERNS) {
      for (const pattern of patterns) {
        const match = text.match(pattern);
        if (match) {
          // Extract context around the match (up to 80 chars)
          const start = Math.max(0, (match.index || 0) - 20);
          const end = Math.min(text.length, (match.index || 0) + match[0].length + 40);
          const context = text.slice(start, end).trim();

          signals.push({
            type,
            severity,
            text: context,
            date,
            source: "notes",
          });
          break; // Only one match per pattern group per log
        }
      }
    }

    // Also flag negative moods as fatigue signals
    const mood = (log.mood || "").toLowerCase();
    if (["exhausted", "injured", "struggling"].includes(mood)) {
      signals.push({
        type: mood === "injured" ? "injury_mention" : "underrecovery",
        severity: mood === "injured" ? "high" : "medium",
        text: `Mood: ${mood}`,
        date,
        source: "mood",
      });
    }
  }

  // Sort by severity (high first) then by date (most recent first)
  const severityOrder = { high: 0, medium: 1, low: 2 };
  signals.sort((a, b) => {
    const sev = severityOrder[a.severity] - severityOrder[b.severity];
    if (sev !== 0) return sev;
    return b.date.localeCompare(a.date);
  });

  return signals;
}

/**
 * Build a fatigue narrative from extracted signals for the AI prompt.
 */
function buildFatigueContext(signals: FatigueSignal[]): string {
  if (signals.length === 0) return "";

  const high = signals.filter((s) => s.severity === "high");
  const medium = signals.filter((s) => s.severity === "medium");

  const lines: string[] = ["\nFatigue & recovery signals from training log notes:"];

  if (high.length > 0) {
    lines.push("RED FLAGS:");
    for (const s of high.slice(0, 3)) {
      lines.push(`  [${s.date}] ${s.type}: "${s.text}"`);
    }
  }

  if (medium.length > 0) {
    lines.push("WATCH:");
    for (const s of medium.slice(0, 4)) {
      lines.push(`  [${s.date}] ${s.type}: "${s.text}"`);
    }
  }

  // Summary counts
  const injuryMentions = signals.filter((s) => s.type === "injury_mention" || s.type === "pain").length;
  const paceStruggles = signals.filter((s) => s.type === "pace_struggle").length;
  const recoveryIssues = signals.filter((s) => s.type === "underrecovery" || s.type === "overwork").length;

  const summary: string[] = [];
  if (injuryMentions > 0) summary.push(`${injuryMentions} injury/pain mention${injuryMentions > 1 ? "s" : ""}`);
  if (paceStruggles > 0) summary.push(`${paceStruggles} pace struggle${paceStruggles > 1 ? "s" : ""}`);
  if (recoveryIssues > 0) summary.push(`${recoveryIssues} recovery issue${recoveryIssues > 1 ? "s" : ""}`);

  if (summary.length > 0) {
    lines.push(`Summary: ${summary.join(", ")} in recent training logs`);
  }

  return lines.join("\n");
}

// ─── Quality Volume Assessment ──────────────────────────────────────────────

interface ZoneVolume {
  miles: number;
  runs: number;
  avgPace: number; // seconds per mile
}

interface QualityVolumeResult {
  totalMiles: number;
  qualityMiles: number;     // miles at faster-than-easy effort
  qualityPct: number;       // percentage of total
  easyMiles: number;
  longRunMiles: number;
  zones: Record<string, ZoneVolume>; // e.g. "easy", "tempo", "threshold", "race_pace", "interval", "long_run", "recovery"
  workoutBreakdown: { type: string; miles: number; avgPace: number }[];
  assessment: string;       // plain-language assessment
}

/**
 * Assess quality of training volume — not just how many miles, but what kind.
 * Quality miles = miles at paces faster than easy (tempo, threshold, MP, intervals, steady).
 * Uses the runner's own easy pace as the reference point.
 */
// Map raw workout_type values to canonical training zones
const ZONE_MAP: Record<string, string> = {
  easy: "easy",
  recovery: "recovery",
  long_run: "long_run",
  tempo: "tempo",
  threshold: "threshold",
  steady: "threshold",       // steady-state ≈ threshold effort
  interval: "interval",
  speed: "interval",
  repeat: "interval",
  fartlek: "interval",
  marathon_pace: "race_pace",
  race_pace: "race_pace",
  race: "race_pace",
  time_trial: "race_pace",
  moderate: "tempo",
  progression: "tempo",
  run: "easy",               // generic "run" defaults to easy
};

const QUALITY_ZONES = new Set(["tempo", "threshold", "interval", "race_pace"]);

function assessQualityVolume(
  logs: TrainingLogRow[],
  scheduledWorkouts?: ScheduledWorkoutRow[]
): QualityVolumeResult {
  let totalMiles = 0;
  let qualityMiles = 0;
  let easyMiles = 0;
  let longRunMiles = 0;

  // Determine the runner's easy pace from their data (65th percentile = slower runs)
  const pacedLogs = logs.filter(
    (l) => (l.workout_distance_miles || 0) > 0 && (l.workout_duration_minutes || 0) > 0
  );
  const allPaces = pacedLogs.map(
    (l) => ((l.workout_duration_minutes || 0) / (l.workout_distance_miles || 1)) * 60
  ).filter((p) => p >= 240 && p <= 900);
  const sortedPaces = [...allPaces].sort((a, b) => a - b);
  const easyPaceThreshold = sortedPaces[Math.floor(sortedPaces.length * 0.65)] || 600;

  // Zone accumulators
  const zones: Record<string, { miles: number; runs: number; paces: number[] }> = {};
  const addToZone = (zone: string, dist: number, pace: number) => {
    if (!zones[zone]) zones[zone] = { miles: 0, runs: 0, paces: [] };
    zones[zone].miles += dist;
    zones[zone].runs++;
    if (pace > 0) zones[zone].paces.push(pace);
  };

  // Per-type breakdown (raw types, not zones)
  const workoutTypes: Record<string, { miles: number; paces: number[] }> = {};

  for (const log of logs) {
    const dist = log.workout_distance_miles || 0;
    const dur = log.workout_duration_minutes || 0;
    if (dist <= 0) continue;

    totalMiles += dist;
    const pace = dur > 0 ? (dur / dist) * 60 : 0;

    // Use pace_segments for per-segment zone breakdown when available
    if (log.pace_segments && log.pace_segments.length > 0) {
      for (const seg of log.pace_segments) {
        const segZone = ZONE_MAP[seg.effort] || "easy";
        const parts = seg.pace_per_mile.split(":").map(Number);
        const segPace = parts.length === 2 ? parts[0] * 60 + parts[1] : 0;
        addToZone(segZone, seg.distance_miles, segPace);

        if (QUALITY_ZONES.has(segZone)) {
          qualityMiles += seg.distance_miles;
        } else if (segZone === "long_run") {
          longRunMiles += seg.distance_miles;
        } else {
          easyMiles += seg.distance_miles;
        }
      }
    } else {
      // Fallback: whole-run classification
      // Determine workout type: log's own type first, then scheduled workout fallback
      let rawType = (log.workout_type || "").toLowerCase();
      if (!rawType || rawType === "other") {
        if (scheduledWorkouts) {
          const matched = scheduledWorkouts.find(
            (s) => s.date && log.workout_date && log.workout_date.startsWith(s.date)
          );
          if (matched) rawType = (matched.workout_type || "").toLowerCase();
        }
      }

      // Map to canonical zone
      let zone = ZONE_MAP[rawType.replace(/[_\s-]+/g, "_")] || null;

      // If no type tag, classify by pace
      if (!zone && pace > 0) {
        if (pace >= easyPaceThreshold) {
          zone = "easy";
        } else if (pace >= easyPaceThreshold - 30) {
          zone = "tempo"; // within 30s/mi of easy = tempo-ish
        } else {
          zone = "interval"; // significantly faster
        }
      }

      // Override: long runs by distance (>= 25% of weekly average or >= 10 mi)
      const isLongRun = zone === "long_run" || dist >= 10;
      if (isLongRun) zone = "long_run";

      zone = zone || "easy"; // ultimate fallback

      addToZone(zone, dist, pace);

      // Accumulate quality/easy/long
      if (isLongRun) {
        longRunMiles += dist;
        // Partial quality credit for fast long runs
        if (pace > 0 && pace < easyPaceThreshold - 15) qualityMiles += dist * 0.5;
      } else if (QUALITY_ZONES.has(zone)) {
        qualityMiles += dist;
      } else {
        easyMiles += dist;
      }
    }

    // Raw type tracking
    const rawType = (log.workout_type || "").toLowerCase();
    if (rawType && rawType !== "rest" && pace > 0) {
      if (!workoutTypes[rawType]) workoutTypes[rawType] = { miles: 0, paces: [] };
      workoutTypes[rawType].miles += dist;
      workoutTypes[rawType].paces.push(pace);
    }
  }

  const qualityPct = totalMiles > 0 ? Math.round((qualityMiles / totalMiles) * 100) : 0;

  // Build zone output
  const zoneOutput: Record<string, ZoneVolume> = {};
  for (const [z, data] of Object.entries(zones)) {
    if (data.miles < 0.1) continue;
    zoneOutput[z] = {
      miles: Math.round(data.miles * 10) / 10,
      runs: data.runs,
      avgPace: data.paces.length > 0
        ? Math.round(data.paces.reduce((a, b) => a + b, 0) / data.paces.length)
        : 0,
    };
  }

  // Build workout breakdown (by raw type)
  const workoutBreakdown = Object.entries(workoutTypes)
    .filter(([_, data]) => data.miles > 0.5)
    .map(([type, data]) => ({
      type,
      miles: Math.round(data.miles * 10) / 10,
      avgPace: Math.round(data.paces.reduce((a, b) => a + b, 0) / data.paces.length),
    }))
    .sort((a, b) => b.miles - a.miles);

  // Assessment
  let assessment: string;
  if (totalMiles === 0) {
    assessment = "No volume data available";
  } else if (qualityPct > 25) {
    assessment = `High quality volume ratio (${qualityPct}% of miles at workout effort). Watch for overtraining if sustained.`;
  } else if (qualityPct >= 15) {
    assessment = `Good quality volume mix (${qualityPct}% at workout effort). Solid stimulus for development.`;
  } else if (qualityPct >= 8) {
    assessment = `Moderate quality volume (${qualityPct}%). Could add more workout-pace miles for faster development.`;
  } else {
    assessment = `Low quality volume (${qualityPct}%). Mostly easy running. Fine for base building, but needs faster work to improve race fitness.`;
  }

  return {
    totalMiles: Math.round(totalMiles * 10) / 10,
    qualityMiles: Math.round(qualityMiles * 10) / 10,
    qualityPct,
    easyMiles: Math.round(easyMiles * 10) / 10,
    longRunMiles: Math.round(longRunMiles * 10) / 10,
    zones: zoneOutput,
    workoutBreakdown,
    assessment,
  };
}

// ─── Coaching Signal Generation ─────────────────────────────────────────────

function generateCoachingSignals(
  metrics: ComputedMetrics,
  formChecks: FormCheckResult[],
  fitnessSnapshots: FitnessSnapshot[],
  activeInjuries: InjuryRow[],
  goalDaysRemaining: number | null,
  fitnessGapSeconds: number | null
): CoachingSignal[] {
  const signals: CoachingSignal[] = [];

  // ── Workload Signals ──────────────────────────────────────────────────

  if (metrics.acwr > 1.3) {
    signals.push({
      category: "workload",
      priority: "high",
      insight: `Mileage spiked ${metrics.volumeChangePct > 0 ? "+" : ""}${metrics.volumeChangePct.toFixed(0)}% this week. ACWR at ${metrics.acwr} — injury risk territory.`,
      suggestedQuestion: "That's a big jump in mileage. Was that planned, or did it just happen?",
    });
  } else if (metrics.acwr < 0.6 && metrics.chronicLoad > 10) {
    signals.push({
      category: "workload",
      priority: "medium",
      insight: `Volume dropped sharply — only ${metrics.totalMiles.toFixed(1)} miles vs ${metrics.chronicLoad.toFixed(1)} average. ACWR: ${metrics.acwr}.`,
      suggestedQuestion: "Volume's way down this week. Taking a planned easy week, or something going on?",
    });
  }

  // ── Compliance Signals ────────────────────────────────────────────────

  if (metrics.complianceScore < 0.5 && metrics.complianceScore > 0) {
    signals.push({
      category: "compliance",
      priority: "medium",
      insight: `Only ${Math.round(metrics.complianceScore * 100)}% of scheduled workouts completed this week.`,
      suggestedQuestion: "You've missed a few workouts this week. What's been getting in the way?",
    });
  } else if (metrics.complianceScore < 0.7 && metrics.complianceScore > 0) {
    signals.push({
      category: "compliance",
      priority: "low",
      insight: `Plan compliance at ${Math.round(metrics.complianceScore * 100)}% — slightly below target.`,
    });
  }

  // ── Mood & Fatigue Signals ────────────────────────────────────────────

  if (metrics.moodTrend === "declining") {
    signals.push({
      category: "fatigue",
      priority: "high",
      insight: `Mood trending down through the week. Average score: ${metrics.moodScore.toFixed(2)}.`,
      suggestedQuestion: "You've seemed more tired as the week went on. How's recovery been — sleep, stress, nutrition?",
    });
  } else if (metrics.moodScore < 0.3) {
    signals.push({
      category: "fatigue",
      priority: "high",
      insight: `Persistent low energy this week (mood score: ${metrics.moodScore.toFixed(2)}).`,
      suggestedQuestion: "Energy's been low. Is this just a tough week, or has something changed?",
    });
  }

  // ── Injury Risk Signals ───────────────────────────────────────────────

  if (metrics.injuryRisk.severity === "red" || metrics.injuryRisk.severity === "orange") {
    signals.push({
      category: "injury_risk",
      priority: "high",
      insight: `Injury risk elevated (${metrics.injuryRisk.severity}): ${metrics.injuryRisk.factors.slice(0, 2).join(". ")}.`,
      suggestedQuestion: "Multiple risk factors are showing up right now. How's your body actually feeling?",
    });
  }

  // Active injuries that haven't been discussed recently
  for (const injury of activeInjuries.slice(0, 2)) {
    const side = injury.side !== "unknown" ? `${injury.side} ` : "";
    if (injury.severity >= 5) {
      signals.push({
        category: "injury_followup",
        priority: "medium",
        insight: `Active injury: ${side}${injury.body_area} (severity ${injury.severity}/10).`,
        suggestedQuestion: `How's the ${side}${injury.body_area} feeling? Any better, or still bothering you?`,
      });
      break; // Only one injury question per conversation
    }
  }

  // ── Form Check Signals ────────────────────────────────────────────────

  const recentFormIssues = extractFormIssues(formChecks);
  if (recentFormIssues.length > 0) {
    signals.push({
      category: "form",
      priority: "low",
      insight: `Recent form analysis flagged: ${recentFormIssues.slice(0, 3).join(", ")}.`,
      suggestedQuestion: "Your recent form check flagged a couple things. Have you noticed anything different when you run?",
    });
  }

  // ── Fitness Trajectory Signals ────────────────────────────────────────

  if (fitnessSnapshots.length >= 2) {
    const latest = fitnessSnapshots[0];
    const previous = fitnessSnapshots[1];
    const marathonDelta = latest.predicted_marathon_seconds - previous.predicted_marathon_seconds;

    if (marathonDelta > 120) {
      // Predicted time got 2+ minutes slower
      signals.push({
        category: "fitness",
        priority: "medium",
        insight: `Predicted marathon time slipped ${formatTimeDelta(marathonDelta)} since last check.`,
        suggestedQuestion: "Fitness predictions dipped a bit. Could be noise, or could mean something. How are workouts feeling effort-wise?",
      });
    } else if (marathonDelta < -120) {
      // Got 2+ minutes faster
      signals.push({
        category: "fitness",
        priority: "low",
        insight: `Predicted marathon time improved by ${formatTimeDelta(Math.abs(marathonDelta))}.`,
      });
    }
  }

  // ── Goal Proximity Signals ────────────────────────────────────────────

  if (goalDaysRemaining !== null && goalDaysRemaining <= 28) {
    if (fitnessGapSeconds !== null && fitnessGapSeconds > 300) {
      signals.push({
        category: "goal",
        priority: "high",
        insight: `Race in ${goalDaysRemaining} days. Current fitness is ${formatTimeDelta(fitnessGapSeconds)} off target.`,
        suggestedQuestion: "Your race is coming up. How are you feeling about where fitness is right now?",
      });
    } else if (goalDaysRemaining <= 14) {
      signals.push({
        category: "goal",
        priority: "medium",
        insight: `Race in ${goalDaysRemaining} days. Taper time.`,
        suggestedQuestion: "Race is close. Are you feeling ready, or is the taper making you anxious?",
      });
    }
  }

  // ── Injury-Load Correlation ─────────────────────────────────────────

  if (activeInjuries.length > 0 && metrics.acwr > 1.1) {
    const recurringInjuries = activeInjuries.filter((inj: any) => inj.occurrences > 1 || inj.is_recurring);
    if (recurringInjuries.length > 0) {
      const inj = recurringInjuries[0];
      const side = inj.side !== "unknown" ? `${inj.side} ` : "";
      signals.push({
        category: "injury_load",
        priority: "high",
        insight: `ACWR is ${metrics.acwr} and ${side}${inj.body_area} has been injured before. Last time load spiked this high, this injury flared. Current volume: ${metrics.totalMiles} mi this week.`,
        suggestedQuestion: `Your ${side}${inj.body_area} has come back before when you ramped up too fast. How's it feeling right now?`,
      });
    }
  } else if (metrics.acwr > 1.2 && activeInjuries.length === 0) {
    // No active injuries but load is high — preemptive warning
    const anyPastRecurring = activeInjuries.length === 0; // We only have active injuries here, but flag anyway
    if (metrics.acwr > 1.3) {
      signals.push({
        category: "injury_load",
        priority: "medium",
        insight: `ACWR at ${metrics.acwr} — historically this is when soft-tissue injuries happen. No active injuries yet, but prevention matters.`,
      });
    }
  }

  // ── Easy Pace Drift ───────────────────────────────────────────────────

  if (metrics.easyPaceAvg && metrics.workoutPaceAvg) {
    // If easy pace is within 30 sec/mi of workout pace, easy runs are too fast
    if (metrics.workoutPaceAvg - metrics.easyPaceAvg < 30) {
      signals.push({
        category: "pacing",
        priority: "medium",
        insight: `Easy runs (${formatPace(metrics.easyPaceAvg)}) are close to workout pace (${formatPace(metrics.workoutPaceAvg)}). Recovery is compromised.`,
        suggestedQuestion: "Your easy runs look pretty fast. Are you running by feel or chasing a number?",
      });
    }
  }

  // Sort by priority
  const priorityOrder = { high: 0, medium: 1, low: 2 };
  signals.sort((a, b) => priorityOrder[a.priority] - priorityOrder[b.priority]);

  return signals;
}

// ─── Context Building ───────────────────────────────────────────────────────

function buildFullContext(
  metrics: ComputedMetrics,
  signals: CoachingSignal[],
  formChecks: FormCheckResult[],
  fitnessSnapshots: FitnessSnapshot[],
  fitnessGapSeconds: number | null,
  workoutTypeCounts?: Record<string, number>,
  fatigueSignals?: FatigueSignal[],
  qualityVolume?: QualityVolumeResult
): string {
  const parts: string[] = [];

  // Real-time analytics summary
  parts.push(buildMetricsSummary(metrics));

  // Workout type distribution (last 5 weeks)
  if (workoutTypeCounts && Object.keys(workoutTypeCounts).length > 0) {
    const total = Object.values(workoutTypeCounts).reduce((s, c) => s + c, 0);
    const sorted = Object.entries(workoutTypeCounts).sort((a, b) => b[1] - a[1]);
    const breakdown = sorted.map(([type, count]) => `${type}: ${count} (${Math.round(count / total * 100)}%)`).join(", ");
    const easyCount = (workoutTypeCounts["easy"] || 0) + (workoutTypeCounts["recovery"] || 0);
    const hardCount = total - easyCount - (workoutTypeCounts["long_run"] || 0);
    const easyPct = Math.round(easyCount / total * 100);

    let assessment = "";
    if (easyPct < 70 && total >= 4) {
      assessment = ` ⚠️ Only ${easyPct}% easy/recovery runs — should be ~80%. Too much intensity.`;
    } else if (easyPct >= 80) {
      assessment = ` Good 80/20 balance.`;
    }

    parts.push(`\nWorkout type distribution (last 5 weeks, ${total} runs):\n- ${breakdown}${assessment}`);
  }

  // Fitness trajectory
  const fitnessCtx = buildFitnessContext(fitnessSnapshots, fitnessGapSeconds);
  if (fitnessCtx) parts.push(fitnessCtx);

  // Form check findings
  const formCtx = buildFormCheckContext(formChecks);
  if (formCtx) parts.push(formCtx);

  // Fatigue signals from training log notes
  if (fatigueSignals && fatigueSignals.length > 0) {
    parts.push(buildFatigueContext(fatigueSignals));
  }

  // Quality volume assessment
  if (qualityVolume && qualityVolume.totalMiles > 0) {
    parts.push(buildQualityVolumeContext(qualityVolume));
  }

  // Coaching signals (data-driven insights + suggested questions)
  if (signals.length > 0) {
    parts.push(buildSignalsContext(signals));
  }

  return parts.join("\n");
}

function buildMetricsSummary(metrics: ComputedMetrics): string {
  const lines: string[] = ["\nThis week's analytics (computed from data):"];

  lines.push(`- Miles: ${metrics.totalMiles} | Runs: ${metrics.runCount} | Rest days: ${metrics.restDays}`);
  lines.push(`- ACWR: ${metrics.acwr}${metrics.acwr > 1.2 ? " (ELEVATED)" : metrics.acwr < 0.7 ? " (LOW)" : ""} | 4-week avg: ${metrics.chronicLoad.toFixed(1)}mi`);
  lines.push(`- Volume change: ${metrics.volumeChangePct > 0 ? "+" : ""}${metrics.volumeChangePct.toFixed(0)}% vs last week`);

  if (metrics.complianceScore < 1) {
    lines.push(`- Plan compliance: ${Math.round(metrics.complianceScore * 100)}%`);
  }

  lines.push(`- Mood: ${metrics.moodScore.toFixed(2)} (${metrics.moodTrend})`);

  if (metrics.injuryRisk.severity !== "green") {
    lines.push(`- Injury risk: ${metrics.injuryRisk.severity} — ${metrics.injuryRisk.factors[0]}`);
  }

  if (metrics.easyPaceAvg) {
    lines.push(`- Easy pace avg: ${formatPace(metrics.easyPaceAvg)}`);
  }

  if (metrics.longRunMiles) {
    lines.push(`- Long run: ${metrics.longRunMiles}mi${metrics.longRunPace ? ` @ ${formatPace(metrics.longRunPace)}` : ""}`);
  }

  // Pacing adherence: flag if easy runs are too fast
  if (metrics.easyPaceAvg && metrics.workoutPaceAvg) {
    const gap = metrics.workoutPaceAvg - metrics.easyPaceAvg;
    if (gap < 30) {
      lines.push(`- ⚠️ PACING: Easy runs (${formatPace(metrics.easyPaceAvg)}) are only ${gap}s/mi slower than workout pace (${formatPace(metrics.workoutPaceAvg)}). Easy runs should be 60-90s/mi slower. Runner is not recovering on easy days.`);
    } else if (gap >= 60) {
      lines.push(`- Pacing: Good separation — easy ${formatPace(metrics.easyPaceAvg)} vs workout ${formatPace(metrics.workoutPaceAvg)} (${gap}s/mi gap)`);
    }
  }

  return lines.join("\n");
}

function buildFitnessContext(
  snapshots: FitnessSnapshot[],
  gapSeconds: number | null
): string {
  if (snapshots.length === 0) return "";

  const latest = snapshots[0];
  const lines: string[] = ["\nFitness predictions (latest):"];
  lines.push(`- Marathon: ${formatTotalTime(latest.predicted_marathon_seconds)} | Half: ${formatTotalTime(latest.predicted_half_seconds)} | 10K: ${formatTotalTime(latest.predicted_10k_seconds)} | 5K: ${formatTotalTime(latest.predicted_5k_seconds)}`);
  lines.push(`- Confidence: ${latest.confidence}`);

  if (gapSeconds !== null) {
    const sign = gapSeconds > 0 ? "+" : "";
    lines.push(`- Gap to goal: ${sign}${formatTimeDelta(Math.abs(gapSeconds))} (${gapSeconds > 0 ? "behind" : "ahead"})`);
  }

  // Trajectory narrative: tell the AI in plain language whether the runner is improving
  if (snapshots.length >= 2) {
    const oldest = snapshots[snapshots.length - 1];
    const marathonDelta = latest.predicted_marathon_seconds - oldest.predicted_marathon_seconds;
    const halfDelta = latest.predicted_half_seconds - oldest.predicted_half_seconds;
    const fivekDelta = latest.predicted_5k_seconds - oldest.predicted_5k_seconds;

    const daySpan = Math.ceil(
      (new Date(latest.created_at).getTime() - new Date(oldest.created_at).getTime()) / (1000 * 60 * 60 * 24)
    );

    if (Math.abs(marathonDelta) > 60) {
      const direction = marathonDelta < 0 ? "improved" : "regressed";
      lines.push(`- Trend: Marathon prediction ${direction} by ${formatTimeDelta(Math.abs(marathonDelta))} over last ${snapshots.length} snapshots`);
    }

    // Plain-language fitness trajectory for the AI to reference
    const improving = marathonDelta < -60 && halfDelta < -30;
    const declining = marathonDelta > 120 && halfDelta > 60;
    const plateaued = Math.abs(marathonDelta) <= 60 && Math.abs(fivekDelta) <= 15;

    if (improving) {
      lines.push(`- FITNESS TRAJECTORY: Runner is IMPROVING — times have gotten ${formatTimeDelta(Math.abs(marathonDelta))} faster (marathon) and ${formatTimeDelta(Math.abs(fivekDelta))} faster (5K) over ${daySpan} days. Training is working.`);
    } else if (declining) {
      lines.push(`- FITNESS TRAJECTORY: Runner is DECLINING — times ${formatTimeDelta(marathonDelta)} slower (marathon) over ${daySpan} days. May need recovery block or training change.`);
    } else if (plateaued && daySpan > 30) {
      lines.push(`- FITNESS TRAJECTORY: Runner has PLATEAUED — predictions unchanged over ${daySpan} days. May need new training stimulus (speed work, longer long runs, or recovery block).`);
    }
  }

  return lines.join("\n");
}

function buildFormCheckContext(formChecks: FormCheckResult[]): string {
  if (formChecks.length === 0) return "";

  const issues = extractFormIssues(formChecks);
  if (issues.length === 0) return "";

  return `\nRecent form analysis findings:\n- ${issues.join("\n- ")}`;
}

function buildSignalsContext(signals: CoachingSignal[]): string {
  const lines: string[] = [
    "\nCoaching signals (data-driven — use these to inform your response and ask relevant questions):",
  ];

  for (const signal of signals.slice(0, 5)) {
    const priority = signal.priority === "high" ? "[!]" : signal.priority === "medium" ? "[~]" : "[-]";
    lines.push(`${priority} ${signal.insight}`);
    if (signal.suggestedQuestion) {
      lines.push(`   Ask: "${signal.suggestedQuestion}"`);
    }
  }

  return lines.join("\n");
}

const ZONE_LABELS: Record<string, string> = {
  easy: "Easy",
  recovery: "Recovery",
  long_run: "Long Run",
  tempo: "Tempo",
  threshold: "Threshold",
  interval: "Interval/Speed",
  race_pace: "Race Pace",
};

function buildQualityVolumeContext(qv: QualityVolumeResult): string {
  const lines: string[] = ["\nVolume by training zone (last 5 weeks):"];

  // Zone breakdown — ordered by intensity
  const zoneOrder = ["easy", "recovery", "long_run", "tempo", "threshold", "race_pace", "interval"];
  const zoneLines: string[] = [];
  for (const zone of zoneOrder) {
    const data = qv.zones[zone];
    if (!data || data.miles < 0.1) continue;
    const pct = qv.totalMiles > 0 ? Math.round((data.miles / qv.totalMiles) * 100) : 0;
    const label = ZONE_LABELS[zone] || zone;
    const paceStr = data.avgPace > 0 ? ` @ ${formatPace(data.avgPace)}` : "";
    zoneLines.push(`  ${label}: ${data.miles}mi (${pct}%, ${data.runs} runs${paceStr})`);
  }

  if (zoneLines.length > 0) {
    lines.push(...zoneLines);
  }

  lines.push(`- Total: ${qv.totalMiles} mi | Quality: ${qv.qualityMiles} mi (${qv.qualityPct}%) | Easy: ${qv.easyMiles} mi | Long runs: ${qv.longRunMiles} mi`);
  lines.push(`- Assessment: ${qv.assessment}`);
  return lines.join("\n");
}

/**
 * Generate coaching signals from fatigue extraction results.
 */
function generateFatigueSignals(fatigueSignals: FatigueSignal[]): CoachingSignal[] {
  const signals: CoachingSignal[] = [];

  const injuryMentions = fatigueSignals.filter((s) => s.type === "injury_mention" || s.type === "pain");
  const paceStruggles = fatigueSignals.filter((s) => s.type === "pace_struggle");
  const recoveryIssues = fatigueSignals.filter((s) => s.type === "underrecovery" || s.type === "overwork");

  if (injuryMentions.length >= 2) {
    signals.push({
      category: "fatigue_notes",
      priority: "high",
      insight: `Multiple injury/pain mentions in recent logs (${injuryMentions.length}x). Latest: "${injuryMentions[0].text}"`,
      suggestedQuestion: "I noticed some pain mentions in your recent logs. Can you tell me more about what's going on?",
    });
  } else if (injuryMentions.length === 1 && injuryMentions[0].severity === "high") {
    signals.push({
      category: "fatigue_notes",
      priority: "high",
      insight: `Injury mention in recent log: "${injuryMentions[0].text}"`,
      suggestedQuestion: "You mentioned something hurting recently. How's that feeling now?",
    });
  }

  if (paceStruggles.length >= 2) {
    signals.push({
      category: "fatigue_notes",
      priority: "medium",
      insight: `Repeated pace struggles noted (${paceStruggles.length}x in recent logs). May indicate accumulated fatigue or undertaper.`,
      suggestedQuestion: "You've mentioned struggling with paces a few times recently. Are workouts feeling harder than they should?",
    });
  }

  if (recoveryIssues.length >= 2) {
    signals.push({
      category: "fatigue_notes",
      priority: "high",
      insight: `Multiple recovery concerns in recent logs (${recoveryIssues.length}x). Runner may be under-recovered.`,
      suggestedQuestion: "Your logs mention feeling tired/under-recovered several times. What does recovery look like right now — sleep, nutrition, stress?",
    });
  }

  return signals;
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function extractFormIssues(formChecks: FormCheckResult[]): string[] {
  const issues: string[] = [];

  for (const fc of formChecks) {
    // Try ai_findings first (array of findings), then ai_analysis (object)
    const findings = fc.ai_findings || (fc.ai_analysis as any)?.findings;
    if (Array.isArray(findings)) {
      for (const f of findings) {
        if (f.severity === "concern" || f.category === "concern" || f.priority === "high") {
          issues.push(String(f.description || f.title || f.finding || "Unknown concern"));
        }
      }
    } else if (fc.ai_analysis) {
      // Try to extract from narrative analysis
      const analysis = fc.ai_analysis as Record<string, unknown>;
      if (analysis.concerns && Array.isArray(analysis.concerns)) {
        issues.push(...(analysis.concerns as string[]).slice(0, 3));
      }
      if (analysis.areas_for_improvement && Array.isArray(analysis.areas_for_improvement)) {
        issues.push(...(analysis.areas_for_improvement as string[]).slice(0, 3));
      }
    }
  }

  return [...new Set(issues)]; // deduplicate
}

function getPredictedTime(snapshot: FitnessSnapshot, distance: string): number | null {
  switch (distance) {
    case "marathon":
      return snapshot.predicted_marathon_seconds;
    case "half_marathon":
    case "half":
      return snapshot.predicted_half_seconds;
    case "10k":
      return snapshot.predicted_10k_seconds;
    case "5k":
      return snapshot.predicted_5k_seconds;
    default:
      return null;
  }
}

function formatTotalTime(totalSeconds: number): string {
  if (!totalSeconds || totalSeconds <= 0) return "--:--";
  const hrs = Math.floor(totalSeconds / 3600);
  const mins = Math.floor((totalSeconds % 3600) / 60);
  const secs = Math.round(totalSeconds % 60);
  if (hrs > 0) {
    return `${hrs}:${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
  }
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function formatTimeDelta(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.round(seconds % 60);
  if (mins === 0) return `${secs}s`;
  if (secs === 0) return `${mins}m`;
  return `${mins}m ${secs}s`;
}

/**
 * Split historical logs into weekly buckets (most recent first).
 * Used by coaching agent to prepare data for ACWR calculation.
 */
export function splitLogsIntoWeeks(
  logs: TrainingLogRow[],
  currentWeekStartDate: Date
): TrainingLogRow[][] {
  const weeks: TrainingLogRow[][] = [];

  for (let i = 1; i <= 4; i++) {
    const weekEnd = new Date(currentWeekStartDate);
    weekEnd.setDate(weekEnd.getDate() - (i - 1) * 7 - 1);
    const weekStart = new Date(weekEnd);
    weekStart.setDate(weekStart.getDate() - 6);

    const weekLogs = logs.filter((l) => {
      if (!l.workout_date) return false;
      const d = new Date(l.workout_date);
      return d >= weekStart && d <= weekEnd;
    });

    weeks.push(weekLogs);
  }

  return weeks;
}

/**
 * Get the Monday of the current week.
 */
export function getCurrentWeekMonday(): Date {
  const now = new Date();
  const day = now.getDay(); // 0=Sun, 1=Mon...
  const diff = day === 0 ? 6 : day - 1; // Days since Monday
  const monday = new Date(now);
  monday.setDate(now.getDate() - diff);
  monday.setHours(0, 0, 0, 0);
  return monday;
}
