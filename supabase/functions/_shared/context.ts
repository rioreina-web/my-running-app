/**
 * Context Compression Module
 * Compresses training logs and goals into minimal tokens
 * Reduces context from ~500+ tokens to ~50 tokens (90% reduction)
 */

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

import {
  loadCoachContext,
  formatPacesBlock,
  classifyPace,
  findSimilarPriorWorkout,
  formatProgressionBlock,
  formatSplitsBlock,
  splitsFromLaps,
  splitsFromPaceSegments,
  splitsFromExtractedIntervals,
  splitsFromParsedBlocks,
  isQualityWorkoutType,
  type WorkoutSplit,
} from "./coach-context.ts";
import { firstAthleteNote } from "./athleteNoteText.ts";
import { detectInjury } from "./injuries.ts";
import type { SessionShape } from "./session-questions.ts";

export interface TrainingLog {
  created_at: string;
  workout_date?: string; // The actual date of the workout (use this for ordering)
  workout_distance_miles?: number;
  workout_duration_minutes?: number;
  mood?: string;
  cleaned_notes?: string;
  notes?: string;
}

/**
 * Get the effective date for a training log
 * Prefers workout_date (when run happened) over created_at (when logged)
 */
export function getLogDate(log: TrainingLog | ExtendedTrainingLog): Date {
  return new Date(log.workout_date || log.created_at);
}

export interface UserGoal {
  goal_title: string;
  target_date: string;
}

/**
 * Compress training logs into a concise summary
 * Input: Array of full log objects (~500+ tokens)
 * Output: Compressed summary (~50 tokens)
 * IMPORTANT: Logs should be sorted by workout_date (most recent first)
 */
export function compressTrainingContext(logs: TrainingLog[]): string {
  if (!logs || logs.length === 0) {
    return "No recent training data available.";
  }

  // Sort logs by workout_date (most recent first)
  const sortedLogs = [...logs].sort((a, b) => {
    const dateA = getLogDate(a);
    const dateB = getLogDate(b);
    return dateB.getTime() - dateA.getTime();
  });

  // Calculate totals
  const totalMiles = sortedLogs.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
  const totalMinutes = sortedLogs.reduce((sum, l) => sum + (l.workout_duration_minutes || 0), 0);

  // Calculate average pace
  let avgPace = "N/A";
  if (totalMinutes > 0 && totalMiles > 0) {
    const totalSecs = Math.round((totalMinutes / totalMiles) * 60);
    const paceMin = Math.floor(totalSecs / 60);
    const paceSec = totalSecs % 60;
    avgPace = `${paceMin}:${paceSec.toString().padStart(2, "0")}`;
  }

  // Analyze moods
  const moods = sortedLogs.map((l) => l.mood).filter(Boolean) as string[];
  const moodSummary = moods.length > 0
    ? moods.slice(0, 3).join(", ")
    : "not recorded";

  // Detect volume trend (compare recent vs older)
  const midpoint = Math.floor(sortedLogs.length / 2);
  const recentLogs = sortedLogs.slice(0, midpoint || 1);
  const olderLogs = sortedLogs.slice(midpoint || 1);

  const recentMiles = recentLogs.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
  const olderMiles = olderLogs.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);

  let trend = "steady";
  if (olderMiles > 0) {
    const changeRatio = recentMiles / olderMiles;
    if (changeRatio > 1.15) trend = "increasing";
    else if (changeRatio < 0.85) trend = "decreasing";
  }

  // Get most recent notes (by workout_date, truncated)
  const latestNotes = sortedLogs[0]?.cleaned_notes || sortedLogs[0]?.notes || "No notes";
  const truncatedNotes = latestNotes.length > 100
    ? latestNotes.slice(0, 100) + "..."
    : latestNotes;

  // Calculate date range using workout_date
  const oldestDate = getLogDate(sortedLogs[sortedLogs.length - 1]);
  const newestDate = getLogDate(sortedLogs[0]);
  const daySpan = Math.ceil((newestDate.getTime() - oldestDate.getTime()) / (1000 * 60 * 60 * 24));

  // Compressed format (~50 tokens)
  return `Training summary (${sortedLogs.length} runs, past ${daySpan} days):
- Total: ${totalMiles.toFixed(1)} mi in ${Math.round(totalMinutes)} min
- Avg pace: ${avgPace} /mi
- Volume trend: ${trend}
- Recent moods: ${moodSummary}
- Latest: ${truncatedNotes}`;
}

/**
 * Compress goals into a concise summary
 * Shows goals with days remaining
 * Framed as context to reference when relevant, not to force into every answer
 */
export function compressGoalsContext(goals: UserGoal[], isTrainingRelated: boolean = false): string {
  if (!goals || goals.length === 0) {
    return "";
  }

  const today = new Date();
  const goalLines = goals.map((g) => {
    const targetDate = new Date(g.target_date);
    const daysUntil = Math.ceil((targetDate.getTime() - today.getTime()) / (1000 * 60 * 60 * 24));

    if (daysUntil < 0) {
      return `- ${g.goal_title} (${Math.abs(daysUntil)} days OVERDUE)`;
    } else if (daysUntil === 0) {
      return `- ${g.goal_title} (TODAY!)`;
    } else if (daysUntil <= 7) {
      return `- ${g.goal_title} (${daysUntil} days - THIS WEEK)`;
    } else if (daysUntil <= 30) {
      return `- ${g.goal_title} (${daysUntil} days - this month)`;
    } else {
      const weeks = Math.floor(daysUntil / 7);
      return `- ${g.goal_title} (${weeks} weeks away)`;
    }
  });

  // Add contextual framing based on query type
  const urgentGoals = goals.filter((g) => {
    const daysUntil = Math.ceil((new Date(g.target_date).getTime() - today.getTime()) / (1000 * 60 * 60 * 24));
    return daysUntil <= 30 && daysUntil >= 0;
  });

  let framing = "";
  if (isTrainingRelated && urgentGoals.length > 0) {
    framing = " (consider these when giving training advice)";
  } else {
    framing = " (reference if directly relevant to the question)";
  }

  return `\nRunner's goals${framing}:\n${goalLines.join("\n")}`;
}

/**
 * Check if a query is training-related
 */
export function isTrainingRelatedQuery(query: string): boolean {
  const trainingPatterns = [
    /training/i,
    /run(ning)?/i,
    /workout/i,
    /pace/i,
    /mileage/i,
    /distance/i,
    /tempo/i,
    /interval/i,
    /long run/i,
    /easy run/i,
    /recovery/i,
    /rest day/i,
    /week/i,
    /schedule/i,
    /plan/i,
    /race/i,
    /marathon/i,
    /half/i,
    /5k|10k/i,
    /taper/i,
    /peak/i,
    /base/i,
    /build/i,
    /speed/i,
    /endurance/i,
    /volume/i,
    /how (should|do|can) i/i,
    /what should i/i,
    /this week/i,
    /today/i,
    /tomorrow/i,
  ];

  return trainingPatterns.some((pattern) => pattern.test(query));
}

/**
 * Check if query is asking about "this week" specifically
 */
export function isThisWeekQuery(query: string): boolean {
  const thisWeekPatterns = [
    /this week/i,
    /my week/i,
    /the week/i,
    /so far this week/i,
    /week('s| is)? training/i,
    /weekly/i,
  ];
  return thisWeekPatterns.some((pattern) => pattern.test(query));
}

/**
 * Get Monday of the current week (start of week)
 */
function getMonday(date: Date): Date {
  const d = new Date(date);
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1); // Adjust when day is Sunday
  d.setDate(diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

/**
 * Build a focused "this week" training summary
 * Only includes workouts from Monday to now
 */
export function buildThisWeekContext(logs: TrainingLog[] | ExtendedTrainingLog[]): string {
  if (!logs || logs.length === 0) {
    return "No training data available.";
  }

  const now = new Date();
  const monday = getMonday(now);

  // Filter to only this week's workouts (by workout_date)
  const thisWeekLogs = logs.filter((log) => {
    const logDate = getLogDate(log);
    return logDate >= monday && logDate <= now;
  });

  // Sort by workout_date (oldest first for chronological summary)
  const sortedLogs = [...thisWeekLogs].sort((a, b) => {
    const dateA = getLogDate(a);
    const dateB = getLogDate(b);
    return dateA.getTime() - dateB.getTime();
  });

  if (sortedLogs.length === 0) {
    return "No runs logged this week yet (since Monday).";
  }

  // Calculate this week's stats
  const totalMiles = sortedLogs.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
  const totalMinutes = sortedLogs.reduce((sum, l) => sum + (l.workout_duration_minutes || 0), 0);

  let avgPace = "N/A";
  if (totalMinutes > 0 && totalMiles > 0) {
    const totalSecs = Math.round((totalMinutes / totalMiles) * 60);
    const mins = Math.floor(totalSecs / 60);
    const secs = totalSecs % 60;
    avgPace = `${mins}:${secs.toString().padStart(2, "0")}/mi`;
  }

  // Build daily breakdown
  const dailyBreakdown = sortedLogs.map((log) => {
    const logDate = getLogDate(log);
    const dayName = logDate.toLocaleDateString("en-US", { weekday: "long" });
    const distance = log.workout_distance_miles?.toFixed(1) || "?";
    const duration = log.workout_duration_minutes ? `${Math.round(log.workout_duration_minutes)} min` : "";
    const mood = log.mood ? ` [${log.mood}]` : "";
    const note = (log as ExtendedTrainingLog).cleaned_notes || log.notes;
    const noteSnippet = note ? `: ${note.slice(0, 80)}${note.length > 80 ? "..." : ""}` : "";
    return `- ${dayName}: ${distance} mi ${duration}${mood}${noteSnippet}`;
  }).join("\n");

  // Calculate days run vs rest
  const daysRun = sortedLogs.length;
  const daysSinceMonday = Math.floor((now.getTime() - monday.getTime()) / (1000 * 60 * 60 * 24)) + 1;
  const restDays = daysSinceMonday - daysRun;

  return `THIS WEEK'S TRAINING (Monday ${monday.toLocaleDateString()} - Today):

Stats: ${daysRun} runs, ${totalMiles.toFixed(1)} total miles, avg pace ${avgPace}
Run days: ${daysRun} | Rest days: ${restDays}

Daily breakdown:
${dailyBreakdown}`;
}

/**
 * Build a full compressed context string for the AI
 * Combines training summary + goals into minimal tokens
 */
export function buildCompressedContext(
  logs: TrainingLog[],
  goals: UserGoal[]
): string {
  const training = compressTrainingContext(logs);
  const goalsContext = compressGoalsContext(goals);

  return `${training}${goalsContext}`;
}

/**
 * Estimate token count for a string (rough approximation)
 * ~4 characters per token on average
 */
export function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

/**
 * Extended Training Log interface with all fields
 */
export interface ExtendedTrainingLog {
  id?: string;
  created_at: string;
  workout_date?: string;
  workout_distance_miles?: number;
  workout_duration_minutes?: number;
  workout_type?: string;
  workout_pace_per_mile?: string;
  pace_segments?: Array<{ effort: string; distance_miles: number; pace_per_mile: string; duration_seconds: number; avg_heart_rate?: number }>;
  mood?: string;
  cleaned_notes?: string;
  notes?: string;
  coach_insight?: string;
  workout_notes?: string;
  extracted_data?: {
    rpe?: number;
    weather?: string;
    terrain?: string;
    running_partners?: string[];
    shoe?: string;
    sleep_quality?: string;
    fueling?: string;
    effort_level?: string;
    injured_area?: string;
    [key: string]: unknown;
  };
}

/**
 * Build a comprehensive training period document
 * WEIGHTED: Recent training (last 4 weeks) gets full detail
 * Older training (rest of period) gets compressed summary
 * Used for moderate/complex coaching queries
 */
export function buildTrainingPeriodDocument(
  logs: ExtendedTrainingLog[],
  periodMonths: number = 3
): string {
  if (!logs || logs.length === 0) {
    return "\nNo training history available for this period.";
  }

  const now = new Date();
  const fourWeeksAgo = new Date(now.getTime() - 28 * 24 * 60 * 60 * 1000);
  const periodStart = new Date(now.getTime() - periodMonths * 30 * 24 * 60 * 60 * 1000);

  // Filter logs to the period
  const periodLogs = logs.filter((log) => {
    const logDate = new Date(log.workout_date || log.created_at);
    return logDate >= periodStart;
  });

  if (periodLogs.length === 0) {
    return "\nNo training data in the specified period.";
  }

  // Split into recent (last 4 weeks) and older training
  const recentLogs = periodLogs.filter((log) => {
    const logDate = new Date(log.workout_date || log.created_at);
    return logDate >= fourWeeksAgo;
  });

  const olderLogs = periodLogs.filter((log) => {
    const logDate = new Date(log.workout_date || log.created_at);
    return logDate < fourWeeksAgo;
  });

  // Sort both by date chronologically
  const sortedRecent = [...recentLogs].sort((a, b) => {
    const dateA = new Date(a.workout_date || a.created_at);
    const dateB = new Date(b.workout_date || b.created_at);
    return dateA.getTime() - dateB.getTime();
  });

  const sortedOlder = [...olderLogs].sort((a, b) => {
    const dateA = new Date(a.workout_date || a.created_at);
    const dateB = new Date(b.workout_date || b.created_at);
    return dateA.getTime() - dateB.getTime();
  });

  // ====== HELPER: Calculate stats for a set of logs ======
  const calculateStats = (logSet: ExtendedTrainingLog[]) => {
    const runsWithDistance = logSet.filter((l) => l.workout_distance_miles && l.workout_distance_miles > 0);
    const totalMiles = runsWithDistance.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
    const totalMinutes = runsWithDistance.reduce((sum, l) => sum + (l.workout_duration_minutes || 0), 0);

    let avgPace = "N/A";
    if (totalMinutes > 0 && totalMiles > 0) {
      const totalSecs = Math.round((totalMinutes / totalMiles) * 60);
      const mins = Math.floor(totalSecs / 60);
      const secs = totalSecs % 60;
      avgPace = `${mins}:${secs.toString().padStart(2, "0")}/mi`;
    }

    const distances = runsWithDistance.map((l) => l.workout_distance_miles || 0);
    const longestRun = distances.length > 0 ? Math.max(...distances) : 0;

    return { runsWithDistance, totalMiles, totalMinutes, avgPace, longestRun };
  };

  // ====== HELPER: Get weekly breakdown ======
  const getWeeklyData = (logSet: ExtendedTrainingLog[]) => {
    const weeklyData: Record<string, { runs: number; miles: number; minutes: number; moods: string[]; notes: string[] }> = {};

    logSet.forEach((log) => {
      const logDate = new Date(log.workout_date || log.created_at);
      const weekStart = new Date(logDate);
      weekStart.setDate(logDate.getDate() - logDate.getDay() + 1);
      const weekKey = weekStart.toISOString().split("T")[0];

      if (!weeklyData[weekKey]) {
        weeklyData[weekKey] = { runs: 0, miles: 0, minutes: 0, moods: [], notes: [] };
      }

      weeklyData[weekKey].runs++;
      weeklyData[weekKey].miles += log.workout_distance_miles || 0;
      weeklyData[weekKey].minutes += log.workout_duration_minutes || 0;
      if (log.mood) weeklyData[weekKey].moods.push(log.mood);

      const note = log.cleaned_notes || log.notes;
      if (note && note.trim()) {
        weeklyData[weekKey].notes.push(note.trim());
      }
    });

    return weeklyData;
  };

  // ====== HELPER: Format pace ======
  const formatPace = (minutes: number, miles: number): string => {
    if (minutes <= 0 || miles <= 0) return "N/A";
    const totalSecs = Math.round((minutes / miles) * 60);
    const mins = Math.floor(totalSecs / 60);
    const secs = totalSecs % 60;
    return `${mins}:${secs.toString().padStart(2, "0")}/mi`;
  };

  // ====== RECENT TRAINING (Last 4 weeks) - FULL DETAIL ======
  const recentStats = calculateStats(sortedRecent);
  const recentWeeklyData = getWeeklyData(sortedRecent);

  // Full weekly breakdown for recent training
  const recentWeeklySummaries = Object.entries(recentWeeklyData)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([weekStart, data]) => {
      const weekDate = new Date(weekStart);
      const weekLabel = `Week of ${weekDate.toLocaleDateString("en-US", { month: "short", day: "numeric" })}`;
      const avgPaceWeek = formatPace(data.minutes, data.miles);
      const moodSummary = data.moods.length > 0 ? data.moods.join(", ") : "no mood logged";
      const noteSummary = data.notes.length > 0 ? `\n    Notes: ${data.notes.slice(0, 3).map(n => n.slice(0, 100)).join(" | ")}` : "";

      return `${weekLabel}: ${data.runs} runs, ${data.miles.toFixed(1)} mi, avg pace ${avgPaceWeek}, moods: ${moodSummary}${noteSummary}`;
    });

  // Get all recent runs with full detail — workout type, pace segments, notes
  const recentNotes = sortedRecent
    .map((log) => {
      const logDate = new Date(log.workout_date || log.created_at);
      const dayName = logDate.toLocaleDateString("en-US", { weekday: "short" });
      const dateStr = logDate.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      const distance = log.workout_distance_miles ? `${log.workout_distance_miles.toFixed(1)}mi` : "";
      const type = log.workout_type ? log.workout_type.replace(/_/g, " ").toUpperCase() : "";
      const pace = (log.workout_distance_miles && log.workout_duration_minutes)
        ? formatPace(log.workout_duration_minutes, log.workout_distance_miles)
        : "";
      const mood = log.mood ? ` [${log.mood}]` : "";

      let line = `${dayName} ${dateStr}: ${type} ${distance} @ ${pace}${mood}`;

      // Add pace segment detail for workouts that have it
      if (log.pace_segments && log.pace_segments.length > 1) {
        const segs = log.pace_segments
          .map(s => `${s.effort}: ${s.distance_miles.toFixed(1)}mi @ ${s.pace_per_mile}/mi${s.avg_heart_rate ? ` ${s.avg_heart_rate}bpm` : ""}`)
          .join(", ");
        line += ` | Segments: ${segs}`;
      }

      // Voice memo context (what the runner said + what the AI extracted)
      const note = log.cleaned_notes || log.notes;
      if (note && note.trim()) {
        line += `\n  Voice: "${note.trim().slice(0, 150)}"`;
      }

      // Coach insight from the voice memo
      if (log.coach_insight && log.coach_insight.trim()) {
        line += `\n  Coach noted: ${log.coach_insight.trim().slice(0, 120)}`;
      }

      // Extracted context (RPE, weather, terrain, partners, sleep, fueling)
      if (log.extracted_data) {
        const ctx: string[] = [];
        if (log.extracted_data.rpe) ctx.push(`RPE: ${log.extracted_data.rpe}/10`);
        if (log.extracted_data.weather) ctx.push(`Weather: ${log.extracted_data.weather}`);
        if (log.extracted_data.terrain) ctx.push(`Terrain: ${log.extracted_data.terrain}`);
        if (log.extracted_data.running_partners?.length) ctx.push(`With: ${log.extracted_data.running_partners.join(", ")}`);
        if (log.extracted_data.sleep_quality) ctx.push(`Sleep: ${log.extracted_data.sleep_quality}`);
        if (log.extracted_data.fueling) ctx.push(`Fueling: ${log.extracted_data.fueling}`);
        if (log.extracted_data.effort_level) ctx.push(`Effort: ${log.extracted_data.effort_level}`);
        if (log.extracted_data.shoe) ctx.push(`Shoes: ${log.extracted_data.shoe}`);
        if (log.extracted_data.injured_area) ctx.push(`Injury: ${log.extracted_data.injured_area}`);
        if (ctx.length > 0) {
          line += `\n  Context: ${ctx.join(" | ")}`;
        }
      }

      return (distance || note) ? line : null;
    })
    .filter(Boolean);

  // Recent mood analysis
  const recentMoods = sortedRecent.map((l) => l.mood).filter(Boolean) as string[];
  const recentMoodCounts: Record<string, number> = {};
  recentMoods.forEach((mood) => {
    recentMoodCounts[mood] = (recentMoodCounts[mood] || 0) + 1;
  });

  const recentPositive = recentMoods.filter((m) =>
    ["energized", "strong", "great", "good", "positive"].includes(m.toLowerCase())
  ).length;
  const recentNegative = recentMoods.filter((m) =>
    ["tired", "sluggish", "exhausted", "fatigued", "struggling"].includes(m.toLowerCase())
  ).length;

  let recentMoodTrend = "balanced";
  if (recentPositive > recentNegative * 1.5) recentMoodTrend = "predominantly positive";
  else if (recentNegative > recentPositive * 1.5) recentMoodTrend = "showing fatigue";

  // ====== OLDER TRAINING (Before 4 weeks) - COMPRESSED SUMMARY ======
  const olderStats = calculateStats(sortedOlder);

  // Monthly summary for older training (compressed)
  const olderMonthlyData: Record<string, { runs: number; miles: number; minutes: number }> = {};
  sortedOlder.forEach((log) => {
    const logDate = new Date(log.workout_date || log.created_at);
    const monthKey = `${logDate.getFullYear()}-${(logDate.getMonth() + 1).toString().padStart(2, "0")}`;

    if (!olderMonthlyData[monthKey]) {
      olderMonthlyData[monthKey] = { runs: 0, miles: 0, minutes: 0 };
    }

    olderMonthlyData[monthKey].runs++;
    olderMonthlyData[monthKey].miles += log.workout_distance_miles || 0;
    olderMonthlyData[monthKey].minutes += log.workout_duration_minutes || 0;
  });

  const olderMonthlySummaries = Object.entries(olderMonthlyData)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([monthKey, data]) => {
      const [year, month] = monthKey.split("-");
      const monthName = new Date(parseInt(year), parseInt(month) - 1).toLocaleDateString("en-US", { month: "short", year: "numeric" });
      const avgPaceMonth = formatPace(data.minutes, data.miles);
      return `${monthName}: ${data.runs} runs, ${data.miles.toFixed(1)} mi, avg ${avgPaceMonth}`;
    });

  // ====== INJURY/PAIN MENTIONS (from all logs) ======
  const allNotes = periodLogs
    .map((log) => {
      const logDate = new Date(log.workout_date || log.created_at);
      const note = log.cleaned_notes || log.notes;
      if (note && note.trim()) {
        return `${logDate.toLocaleDateString()}: ${note.trim()}`;
      }
      return null;
    })
    .filter(Boolean);

  const injuryKeywords = ["pain", "injury", "hurt", "sore", "tight", "ache", "strain", "pull", "tweak", "niggle", "tender"];
  const injuryMentions = allNotes
    .filter((note) => note && injuryKeywords.some((kw) => note.toLowerCase().includes(kw)))
    .slice(0, 5);

  // ====== BUILD THE WEIGHTED DOCUMENT ======
  let document = `
=== TRAINING ANALYSIS (Weighted: Recent > Historical) ===

⚠️ IMPORTANT: Weight the RECENT TRAINING section most heavily when giving advice.
The last 3-4 weeks best reflects current fitness, fatigue, and training patterns.
Historical data provides context but should not override recent trends.

`;

  // ===== RECENT TRAINING SECTION (PRIMARY) =====
  document += `═══════════════════════════════════════════════════════════
📍 RECENT TRAINING (Last 4 weeks) - PRIMARY FOCUS
═══════════════════════════════════════════════════════════

CURRENT FITNESS SNAPSHOT:
- Runs: ${recentStats.runsWithDistance.length}
- Miles: ${recentStats.totalMiles.toFixed(1)}
- Time: ${Math.floor(recentStats.totalMinutes / 60)}h ${Math.round(recentStats.totalMinutes % 60)}m
- Avg pace: ${recentStats.avgPace}
- Longest run: ${recentStats.longestRun.toFixed(1)} mi
- Mood trend: ${recentMoodTrend} (${Object.entries(recentMoodCounts).map(([m, c]) => `${m}:${c}`).join(", ") || "no data"})

WEEKLY BREAKDOWN (detailed):
${recentWeeklySummaries.join("\n\n")}`;

  if (recentNotes.length > 0) {
    document += `

RECENT RUN NOTES (full detail):
${recentNotes.map((n) => `• ${n}`).join("\n")}`;
  }

  // ===== HISTORICAL CONTEXT SECTION (SECONDARY) =====
  if (sortedOlder.length > 0) {
    document += `

───────────────────────────────────────────────────────────
📊 TRAINING HISTORY (Before 4 weeks) - BACKGROUND CONTEXT
───────────────────────────────────────────────────────────

HISTORICAL SUMMARY:
- Total runs: ${olderStats.runsWithDistance.length}
- Total miles: ${olderStats.totalMiles.toFixed(1)}
- Avg pace: ${olderStats.avgPace}

MONTHLY OVERVIEW (compressed):
${olderMonthlySummaries.join("\n")}`;
  }

  // ===== INJURY MENTIONS (from all time) =====
  if (injuryMentions.length > 0) {
    document += `

⚠️ INJURY/DISCOMFORT MENTIONS (review carefully):
${injuryMentions.map((n) => `• ${n}`).join("\n")}`;
  }

  // ===== VOLUME TREND COMPARISON =====
  if (sortedOlder.length > 0 && sortedRecent.length > 0) {
    const recentWeeklyAvg = recentStats.totalMiles / 4;
    const olderWeeks = Math.max(1, Math.ceil(sortedOlder.length / 4));
    const olderWeeklyAvg = olderStats.totalMiles / olderWeeks;

    let volumeTrend = "stable";
    if (recentWeeklyAvg > olderWeeklyAvg * 1.15) volumeTrend = "INCREASING ↑";
    else if (recentWeeklyAvg < olderWeeklyAvg * 0.85) volumeTrend = "DECREASING ↓";

    document += `

📈 VOLUME TREND:
- Recent avg: ${recentWeeklyAvg.toFixed(1)} mi/week
- Historical avg: ${olderWeeklyAvg.toFixed(1)} mi/week
- Trend: ${volumeTrend}`;
  }

  document += `

=== END TRAINING ANALYSIS ===`;

  return document;
}

/**
 * Format conversation history for AI context
 * Keeps full conversation with smart truncation for very long messages
 */
export function compressConversationHistory(
  messages: Array<{ role: string; content: string }>,
  maxMessages: number = 12,
  maxContentLength: number = 600
): string {
  if (!messages || messages.length === 0) {
    return "";
  }

  // Keep more recent messages, but include all if under limit
  const recentMessages = messages.slice(-maxMessages);

  const formatted = recentMessages.map((msg, index) => {
    const role = msg.role === "user" ? "Runner" : "Coach";
    // Only truncate very long messages, and keep more of recent ones
    const isRecent = index >= recentMessages.length - 4;
    const limit = isRecent ? maxContentLength * 2 : maxContentLength;
    const content = msg.content.length > limit
      ? msg.content.slice(0, limit) + "..."
      : msg.content;
    return `${role}: ${content}`;
  });

  return `\nConversation history:\n${formatted.join("\n\n")}`;
}

// ============================================================================
// Token-budgeted prompt assembly (TASKS.md C.2)
//
// Coaching-agent (and any other multi-context LLM caller) concatenates
// 20+ context blocks unconditionally. Several overlap. A drive-by edit
// that bumps one block's content size compounds across every call —
// silent cost growth.
//
// `assembleWithBudget` takes named blocks with priority levels and a
// token budget. Required blocks always get included (they're the gate
// for "the model has enough info to be safe"). Preferred blocks get
// included in order until the budget is tight. Optional blocks get
// dropped first.
//
// Truncation, not silent overflow:
//   If a single block exceeds its remaining share, it gets truncated
//   with a "[…truncated]" marker so the model knows context was cut.
//   The result still respects the budget.
//
// Telemetry:
//   Returns `used` (tokens consumed), `dropped` (block names that
//   didn't fit), `truncated` (block names that were cut mid-content).
//   Callers should log these — pre-existing `usage_tracking` writes
//   become anomaly-detection-able when the budget context is recorded.
// ============================================================================

/** Priority of a prompt block for budgeting. */
export type BlockPriority = "required" | "preferred" | "optional";

/** A single context block to be assembled. */
export interface PromptBlock {
  /** Stable name for telemetry. Keep short. */
  name: string;
  /** The block's content. Empty/whitespace-only blocks are dropped silently. */
  content: string;
  /** required: always included. preferred: included if budget allows. optional: dropped first under budget pressure. */
  priority: BlockPriority;
  /** Optional per-block hard cap. Block is truncated to this many tokens before assembly. */
  maxTokens?: number;
}

/** Result of `assembleWithBudget`. */
export interface AssembledContext {
  /** The assembled string ready to drop into a prompt. */
  text: string;
  /** Approximate tokens used (via `estimateTokens`). */
  used: number;
  /** Token budget passed in. */
  budget: number;
  /** Block names that were skipped entirely because the budget filled up. */
  dropped: string[];
  /** Block names that were partially included (content was truncated). */
  truncated: string[];
  /** Block names that made it in whole. */
  included: string[];
}

const TRUNCATION_MARKER = "\n[…truncated for budget]";

/**
 * Truncate a block's content to fit `maxTokens` worth, preserving the
 * start (heads are usually summaries and most informative). The marker
 * is itself counted toward the budget.
 */
function truncateBlock(content: string, maxTokens: number): string {
  const targetChars = Math.max(0, maxTokens * 4 - TRUNCATION_MARKER.length);
  if (content.length <= targetChars) return content;
  return content.slice(0, targetChars) + TRUNCATION_MARKER;
}

/**
 * Assemble prompt blocks with a token budget. Used by coaching-agent
 * and any other caller wanting bounded context size.
 *
 * Algorithm:
 *   1. Drop blocks whose content is empty/whitespace-only.
 *   2. Apply each block's own maxTokens cap (truncate, mark).
 *   3. Required blocks go in first. If they exceed budget, log warning
 *      and continue — required is required (safety > budget).
 *   4. Preferred blocks go in next, in declared order. If a block would
 *      overflow, truncate it to fit the remaining budget. If less than
 *      ~50 tokens of room remain, drop it instead.
 *   5. Optional blocks last, same logic as preferred.
 *
 * The 50-token floor for inclusion prevents trailing dribble (a 30-token
 * fragment of an optional block is rarely useful and clutters the prompt).
 */
export function assembleWithBudget(
  blocks: PromptBlock[],
  budget: number,
): AssembledContext {
  const dropped: string[] = [];
  const truncated: string[] = [];
  const included: string[] = [];
  const parts: string[] = [];
  let used = 0;

  // Step 1+2: pre-filter and pre-cap.
  const prepped = blocks
    .filter((b) => b.content && b.content.trim().length > 0)
    .map((b) => {
      const maxTokens = b.maxTokens ?? Infinity;
      const currentTokens = estimateTokens(b.content);
      if (currentTokens > maxTokens) {
        truncated.push(b.name);
        return { ...b, content: truncateBlock(b.content, maxTokens) };
      }
      return b;
    });

  const byPriority = {
    required:  prepped.filter((b) => b.priority === "required"),
    preferred: prepped.filter((b) => b.priority === "preferred"),
    optional:  prepped.filter((b) => b.priority === "optional"),
  };

  const MIN_INCLUDE_TOKENS = 50;

  // Step 3: required blocks always in.
  for (const block of byPriority.required) {
    parts.push(block.content);
    used += estimateTokens(block.content);
    included.push(block.name);
  }

  if (used > budget) {
    console.warn(
      `[assembleWithBudget] required blocks exceed budget (${used} > ${budget}). ` +
        `Required blocks: ${byPriority.required.map((b) => b.name).join(", ")}. ` +
        `Increase the budget for this complexity tier or move blocks to "preferred".`,
    );
  }

  // Step 4+5: preferred then optional, with truncation under pressure.
  for (const tier of [byPriority.preferred, byPriority.optional] as const) {
    for (const block of tier) {
      const blockTokens = estimateTokens(block.content);
      const remaining = budget - used;

      if (remaining < MIN_INCLUDE_TOKENS) {
        dropped.push(block.name);
        continue;
      }

      if (blockTokens <= remaining) {
        parts.push(block.content);
        used += blockTokens;
        included.push(block.name);
      } else {
        // Truncate to fit.
        const truncatedContent = truncateBlock(block.content, remaining);
        parts.push(truncatedContent);
        used += estimateTokens(truncatedContent);
        included.push(block.name);
        truncated.push(block.name);
      }
    }
  }

  return {
    text: parts.join(""),
    used,
    budget,
    dropped,
    truncated,
    included,
  };
}

/**
 * Default per-complexity budgets for `assembleWithBudget`. Numbers picked
 * to match the `coaching-agent` complexity tiers — simple/moderate/complex.
 * Adjust by passing your own budget directly to assembleWithBudget.
 *
 * Rationale:
 *   simple   — quick FAQ-style; doesn't need history, mostly answers from
 *              athleteContext + memories + docs. 1k = ~4kB of text.
 *   moderate — most coaching chat; needs training context + plan + memories.
 *              4k = ~16kB; comfortable headroom for the DCO + 4-week detail.
 *   complex  — multi-step reasoning across history. 8k = ~32kB; cap before
 *              prompt-caching savings (C.3) bring effective cost down further.
 */
export const COMPLEXITY_CONTEXT_BUDGETS: Record<string, number> = {
  simple:   1000,
  moderate: 4000,
  complex:  8000,
};

/**
 * Build a compact "## Training context" block from the athlete_state Dynamic
 * Context Object — the same coach-grade signals the Daily Read consumes. The
 * insight reads the workout THROUGH this (load, recency, injury, fitness),
 * not as a standalone. Returns "" when there's no state yet. All fields are
 * read defensively because athlete_state columns are JSON.
 */
export async function buildAthleteStateBlock(
  supabase: SupabaseClient,
  userId: string,
): Promise<string> {
  try {
    const { data } = await supabase
      .from("athlete_state")
      .select(
        "recent_training_summary, weekly_avg_miles, rolling_28d_miles, fitness_prediction, fitness_trend, confirmed_races, load_distribution, fitness_signal, injury_risk_score, possible_injuries, niggle_recurrence, patterns, fitness_vs_6mo_ago_label, goal_race, goal_time_seconds, current_phase, active_goals",
      )
      .eq("user_id", userId)
      .maybeSingle();
    const st = data as Record<string, unknown> | null;
    if (!st) return "";

    const lines: string[] = [];

    // M:SS / H:MM:SS formatter for predicted/race times.
    const fmtT = (s: number): string => {
      const t = Math.round(s);
      const h = Math.floor(t / 3600);
      const m = Math.floor((t % 3600) / 60);
      const sec = t % 60;
      return h > 0
        ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`
        : `${m}:${String(sec).padStart(2, "0")}`;
    };

    // Volume — so the coach NEVER has to ask "what's your weekly mileage?".
    const wk = typeof st.weekly_avg_miles === "number" ? st.weekly_avg_miles : null;
    const d28 = typeof st.rolling_28d_miles === "number" ? st.rolling_28d_miles : null;
    if (wk != null) {
      lines.push(`- Weekly volume: ~${wk} mpw (28d avg)${d28 != null ? `, ${d28} mi over 28d` : ""}`);
    }

    // Fitness — predicted race RANGES + confidence (never a single time; hard rule #7).
    const fp = st.fitness_prediction as Record<string, unknown> | null;
    if (fp && fp.ranges && typeof fp.ranges === "object") {
      const r = fp.ranges as Record<string, { low?: number; high?: number } | null>;
      const order: Array<[string, string]> = [["5K", "5K"], ["10K", "10K"], ["half", "HM"], ["marathon", "M"]];
      const parts: string[] = [];
      for (const [key, label] of order) {
        const rg = r[key];
        if (rg && typeof rg.low === "number" && typeof rg.high === "number") {
          parts.push(`${label} ${fmtT(rg.low)}–${fmtT(rg.high)}`);
        }
      }
      if (parts.length) {
        const conf = typeof fp.confidence_tier === "string" ? ` [${fp.confidence_tier} conf]` : "";
        lines.push(`- Predicted race times (ranges, not points): ${parts.join(", ")}${conf}`);
      }
    }
    if (typeof st.fitness_trend === "string" && st.fitness_trend.length > 0) {
      lines.push(`- Fitness trend: ${st.fitness_trend}`);
    }

    // Declared races — the "recent race time" the coach would otherwise ask for.
    const races = (st.confirmed_races as Array<Record<string, unknown>>) ?? [];
    if (races.length > 0) {
      const recent = [...races]
        .sort((a, b) => String(b.date ?? "").localeCompare(String(a.date ?? "")))
        .slice(0, 2)
        .map((rc) => {
          const dist = String(rc.distance ?? "race");
          const sec = Number(rc.finish_time_seconds);
          const when = String(rc.date ?? "").slice(0, 10);
          return Number.isFinite(sec) && sec > 0 ? `${dist} ${fmtT(sec)} (${when})` : `${dist} (${when})`;
        });
      lines.push(`- Recent races: ${recent.join(", ")}`);
    }

    // DIRECTION — what they're training toward + where they are in the arc. The
    // insight was previously blind to this (it read fitness/races = reality, but
    // not the goal = direction). Carried as quiet context: the coach reads a run
    // THROUGH the goal, it does not recite the goal every time.
    if (typeof st.current_phase === "string" && st.current_phase.length > 0) {
      lines.push(`- Training phase: ${st.current_phase}`);
    }
    const goals = (st.active_goals as Array<Record<string, unknown>>) ?? [];
    const g = goals[0]; // soonest upcoming goal
    if (g) {
      const bits: string[] = [String(g.title ?? "goal")];
      const days = Number(g.days_until);
      if (Number.isFinite(days)) bits.push(days >= 0 ? `${days} days out` : `${Math.abs(days)} days ago`);
      const tgtPace = typeof g.target_pace_per_mile === "string" ? g.target_pace_per_mile : "";
      if (tgtPace) bits.push(`target ${tgtPace}/mi`);
      const gap = Number(g.gap_vs_current_sec_per_mile);
      if (Number.isFinite(gap) && gap !== 0) {
        bits.push(gap > 0 ? `${gap}s/mi off current fitness` : `${Math.abs(gap)}s/mi ahead of target`);
      }
      lines.push(`- Goal: ${bits.join(", ")}`);
    } else if (typeof st.goal_race === "string" && st.goal_race.length > 0) {
      const gt = typeof st.goal_time_seconds === "number" && st.goal_time_seconds > 0
        ? ` in ${fmtT(st.goal_time_seconds)}`
        : "";
      lines.push(`- Goal: ${st.goal_race}${gt}`);
    }

    const ld = st.load_distribution as Record<string, unknown> | null;
    if (ld) {
      const bits: string[] = [];
      if (typeof ld.load_trend === "string") bits.push(String(ld.load_trend).replace(/_/g, " "));
      if (typeof ld.load_vs_chronic_pct === "number") {
        bits.push(`${ld.load_vs_chronic_pct >= 0 ? "+" : ""}${ld.load_vs_chronic_pct}% vs chronic`);
      }
      const rr = ld.recovery_read as Record<string, unknown> | null;
      if (rr?.down_week === true) bits.push("down week");
      if (typeof rr?.avg_days_between_hard === "number") bits.push(`~${rr.avg_days_between_hard}d between hard`);
      if (bits.length) lines.push(`- Training load: ${bits.join(", ")}`);
    }

    const fs = st.fitness_signal as Record<string, unknown> | null;
    if (fs && typeof fs.summary === "string" && fs.summary.length > 0) {
      lines.push(`- Fitness: ${fs.summary}`);
    } else if (typeof st.fitness_vs_6mo_ago_label === "string") {
      lines.push(`- Fitness vs 6mo ago: ${st.fitness_vs_6mo_ago_label}`);
    }

    // Niggles/injury — SURFACE only, never diagnosed (hard rule #2).
    const injBits: string[] = [];
    const niggles = (st.niggle_recurrence as Array<Record<string, unknown>>) ?? [];
    for (const n of niggles.slice(0, 2)) {
      injBits.push(`${n.body_area} ${n.occurrences}× (${n.worst_severity})`);
    }
    const possible = (st.possible_injuries as Array<Record<string, unknown>>) ?? [];
    for (const p of possible.slice(0, 1)) {
      if (typeof p.excerpt === "string") injBits.push(`"${p.excerpt}" (${p.body_area})`);
    }
    if (injBits.length) lines.push(`- Niggles mentioned: ${injBits.join("; ")}`);

    const patterns = (st.patterns as Array<Record<string, unknown>>) ?? [];
    for (const p of patterns.slice(0, 2)) {
      if (typeof p.statement === "string" && p.statement.length > 0) lines.push(`- Pattern: ${p.statement}`);
    }

    if (typeof st.recent_training_summary === "string" && st.recent_training_summary.length > 0) {
      lines.push(`- Recent: ${st.recent_training_summary}`);
    }

    return lines.length > 0 ? `## Training context\n${lines.join("\n")}` : "";
  } catch (err) {
    console.warn("buildAthleteStateBlock failed:", err);
    return "";
  }
}

// ══════════════════════════════════════════════════════════════════════
// Session context — one workout, assembled for a prompt
//
// Moved here from `generate-workout-insight/index.ts` (SESSION-ASK-APPLY
// §5.4) so the workout insight and the session ask read a session through
// exactly ONE assembly. Two surfaces each deriving their own splits /
// zone / structure view is how the taxonomies drift apart.
//
// `buildSessionBlock` is the only new code below; everything else is a
// verbatim lift with `adminClient` replaced by an injected client.
// ══════════════════════════════════════════════════════════════════════

export interface TrainingLogRow {
  id: string;
  user_id: string;
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null;
  workout_type: string | null;
  mood: string | null;
  cleaned_notes: string | null;
  notes: string | null;
  /** Parsed/structured workout description ("6×800m @ 2:35 w/ 90s rec") — from
   *  the voice memo, or derived from laps when the memo didn't describe it.
   *  This is how the insight knows WHAT the session was. */
  workout_notes: string | null;
  /** Parsed structure headline (parse-workout-structure output). `blocks` are
   *  the recovery-segmented EXECUTION (one work_rep per detected bout, continuous
   *  efforts already merged); `intent_pattern` describes what was actually run.
   *  These are the source of truth for rep structure — above raw laps. */
  parsed_structure:
    | {
        pattern?: string | null;
        intent_pattern?: string | null;
        blocks?: Array<{
          role?: string;
          rep_num?: number | null;
          distance_miles?: number | string;
          duration_s?: number | string;
          avg_pace_per_mile?: string;
          avg_hr?: number | null;
        }> | null;
      }
    | null;
  coach_insight: string | null;
  scheduled_workout_id: string | null;
  /** Garmin/HealthKit-derived rep splits. */
  pace_segments: Array<{
    effort?: string;
    distance_miles?: number | string;
    pace_per_mile?: string;
    avg_heart_rate?: number;
  }> | null;
  /** Voice-memo-extracted structured data (intervals/splits). */
  extracted_data: Record<string, unknown> | null;
}

export interface ScheduledLite {
  id: string;
  workout_type: string | null;
  workout_data: Record<string, unknown> | null;
  notes: string | null;
  /** The plan's intent. Optional so this stays structurally compatible with
   *  `CoachScheduledLite`, which comparePrescribedToExecuted consumes. */
  is_key_session?: boolean | null;
}

/**
 * A row of recent training history.
 *
 * v6 (2026-08-18) widened this from {date, distance, type, mood}. The old
 * shape is why the insight could never notice anything longitudinal: it read
 * the CURRENT run's notes but every prior run arrived as bare numbers, so
 * "third week you've mentioned that knee" was unsayable except via the
 * pre-aggregated niggle counter. The notes fields are what the read is for;
 * duration is here because `workout_pace_per_mile` is populated on only a
 * handful of rows (6 of 49 over 28d on the primary athlete), so pace has to be
 * derived from distance + duration.
 */
export interface RecentRow {
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null;
  workout_type: string | null;
  mood: string | null;
  felt_rpe: number | null;
  cleaned_notes: string | null;
  workout_notes: string | null;
  notes: string | null;
}

/** A row from running_workout_laps — the actual lap presses (true rep
 *  structure). Preferred over pace_segments as the splits source. */
export interface TrainingLap {
  lap_index: number | null;
  distance_meters: number | string | null;
  moving_time_seconds: number | null;
  avg_pace_sec_per_mile: number | string | null;
  avg_heart_rate: number | null;
  is_rest: boolean | null;
}

/** Parse a "M:SS" pace string to seconds/mile, or null. */
export function parsePaceSec(s: string | null | undefined): number | null {
  if (!s) return null;
  const m = s.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return null;
  const min = parseInt(m[1]);
  const sec = parseInt(m[2]);
  if (isNaN(min) || isNaN(sec)) return null;
  return min * 60 + sec;
}

/** Compute average pace from distance + duration, or null. */
export function deriveAveragePace(distanceMi: number | null, durationMin: number | null): number | null {
  if (!distanceMi || !durationMin || distanceMi <= 0 || durationMin <= 0) return null;
  return Math.round((durationMin * 60) / distanceMi);
}

/** Per-note ceiling in the recent-log block. Matches the 200-char memo excerpt
 *  used by the memory writer — enough to carry a complaint and its severity
 *  wording, short enough that 40 rows stay affordable. */
export const RECENT_NOTE_MAX_CHARS = 200;

/**
 * "## Recent training log" — the athlete's own words over the fetched window,
 * newest first, one line per run.
 *
 * This block is the point of v6. Everything else the insight sees about the
 * past is pre-aggregated (counters, trends, summaries); this is the raw
 * language, dated, so the read can quote it and say when it was said.
 *
 * Notes precedence mirrors the current-run enrichment: `cleaned_notes` (the
 * transcribed/cleaned memo) is the athlete's voice, `workout_notes` is the
 * parsed workout description, and raw `notes` is last because on imported rows
 * it is the provider's boilerplate ("Morning Run\nDistance: ...") rather than
 * anything the athlete said. Rows with nothing to quote still contribute their
 * numbers — an unremarked easy day is real signal about the shape of a block.
 */
export function formatRecentLogsBlock(rows: RecentRow[]): string {
  if (rows.length === 0) return "";

  const lines: string[] = [];
  for (const r of rows) {
    const day = (r.workout_date ?? "").slice(0, 10);
    if (!day) continue;

    const facts: string[] = [];
    if (r.workout_type) facts.push(r.workout_type);
    if (typeof r.workout_distance_miles === "number") {
      facts.push(`${r.workout_distance_miles.toFixed(1)} mi`);
    }
    // Prefer the stored pace string; derive it when absent (usual case).
    const paceSec = parsePaceSec(r.workout_pace_per_mile)
      ?? deriveAveragePace(r.workout_distance_miles, r.workout_duration_minutes);
    if (paceSec != null) {
      const m = Math.floor(paceSec / 60);
      const s = Math.round(paceSec % 60);
      facts.push(`${m}:${String(s).padStart(2, "0")}/mi`);
    }
    if (r.mood) facts.push(`mood ${r.mood}`);
    if (typeof r.felt_rpe === "number") facts.push(`RPE ${r.felt_rpe}`);

    const note = firstAthleteNote(r.cleaned_notes, r.workout_notes, r.notes);

    const head = `- ${day}${facts.length ? ` — ${facts.join(", ")}` : ""}`;
    if (note) {
      const clipped = note.length > RECENT_NOTE_MAX_CHARS
        ? `${note.slice(0, RECENT_NOTE_MAX_CHARS).trimEnd()}…`
        : note;
      lines.push(`${head}: "${clipped}"`);
    } else {
      lines.push(head);
    }
  }

  if (lines.length === 0) return "";
  return `## Recent training log (athlete's own words, newest first)\n${lines.join("\n")}`;
}

export function summarizeRecent(rows: RecentRow[]): string {
  if (rows.length === 0) return "no other runs in the last week";
  const totalMi = rows.reduce(
    (s, r) => s + (r.workout_distance_miles ?? 0),
    0
  );
  const types = rows.map((r) => r.workout_type).filter((t): t is string => !!t);
  const typeCounts: Record<string, number> = {};
  for (const t of types) typeCounts[t] = (typeCounts[t] ?? 0) + 1;
  const typeStr = Object.entries(typeCounts)
    .map(([t, n]) => `${n} ${t}`)
    .join(", ");
  return `${rows.length} runs (${totalMi.toFixed(1)} mi) — ${typeStr || "mix"}`;
}

/**
 * One line telling the read whether this run was a declared key session.
 *
 * Two sources, and the athlete's beats the plan's: `day_overrides` holds the
 * athlete's own assignment (field 'is_key_session'), and a row exists ONLY
 * when they have expressed a preference — clearing it deletes the row, so
 * absence means "no opinion", never false. Falls back to the plan's
 * `scheduled_workouts.is_key_session`.
 *
 * Returns "" when neither source says anything, which is the common case and
 * a correct one — a plan is optional, and an unflagged day is just a day. An
 * empty string leaves no trace in the prompt rather than asserting "not a key
 * session", which would be a claim we cannot support.
 */
export async function resolveKeySessionLine(
  supabase: SupabaseClient,
  userId: string,
  workoutDay: string,
  plannedKeySession: boolean | null,
): Promise<string> {
  let athleteSaid: boolean | null = null;
  try {
    const { data } = await supabase
      .from("day_overrides")
      .select("value")
      .eq("user_id", userId)
      .eq("date", workoutDay)
      .eq("field", "is_key_session")
      .maybeSingle<{ value: unknown }>();
    if (typeof data?.value === "boolean") athleteSaid = data.value;
  } catch (err) {
    // Never let the override lookup break the insight.
    console.warn("resolveKeySessionLine: override lookup failed:", err);
  }

  const isKey = athleteSaid ?? plannedKeySession;
  if (isKey !== true) return "";
  return athleteSaid === true
    ? "- Key session: yes (athlete flagged this day as a key session)"
    : "- Key session: yes (the plan marks this a key session)";
}

/**
 * "## This run's conditions" — terrain (elevation), weather (heat/humidity)
 * and device signals, so the coach reads a run THROUGH its conditions instead
 * of treating every session as flat and cool.
 *
 * Descriptive CONTEXT to reason over, NOT a correction stamped on the splits:
 * weather comes from `weather_actual` (Open-Meteo, dew-point heat model),
 * terrain from `external_streams.meta`. Returns "" when neither says anything.
 */
export function formatConditionsBlock(
  m: Record<string, unknown> | null,
  wx: Record<string, unknown> | null,
): string {
  const bits: string[] = [];

  if (m && typeof m === "object") {
    const elevM = Number(m.total_elevation_gain);
    if (Number.isFinite(elevM) && elevM > 0) bits.push(`elevation gain ${Math.round(elevM * 3.28084)} ft`);
    const cad = Number(m.average_cadence);
    if (Number.isFinite(cad) && cad > 0) bits.push(`avg cadence ${Math.round(cad * 2)} spm`);
    const suffer = Number(m.suffer_score);
    if (Number.isFinite(suffer) && suffer > 0) bits.push(`relative effort ${Math.round(suffer)}`);
  }

  // Weather from weather_actual (dew-point heat model). `surfacing` gates how
  // much to make of it: apply (hot) / mention (mildly humid) / none (cool).
  let heatLine = "";
  if (wx && typeof wx === "object") {
    const temp = Number(wx.temp_f);
    const dew = Number(wx.dew_point_f);
    const surfacing = String(wx.surfacing ?? "");
    const cat = String(wx.heat_category ?? "").replace("_", " ");
    const pct = Number(wx.adjustment_pct); // continuous-run basis
    if (Number.isFinite(temp) && Number.isFinite(dew) && surfacing !== "none") {
      const wbits = [`${Math.round(temp)}°F`, `${Math.round(dew)}°F dew point`];
      if (cat) wbits.push(cat);
      bits.push(wbits.join(", "));
      if (surfacing === "apply" && Number.isFinite(pct) && pct > 0) {
        const contPct = (pct * 100).toFixed(1);
        const repPct = (pct * 50).toFixed(1); // short reps ≈ half (rep-length scaled)
        heatLine = `\n- Heat model (reference, not a correction): conditions cost ~${contPct}% on continuous efforts (tempo/easy), about half (~${repPct}%) on short interval reps since the body cools during recoveries. Read paces as honest-for-effort; do not restate corrected splits.`;
      } else if (surfacing === "mention") {
        heatLine = `\n- Mildly humid — worth a nod for how the run felt, but not enough to adjust pace.`;
      }
    }
  }

  if (bits.length === 0 && !heatLine) return "";
  return `## This run's conditions\n- ${bits.join(" · ")}${heatLine}`;
}

/**
 * Everything one session contributes to a prompt.
 *
 * `parts` are the substitution values for `session-ask.v1` — deliberately the
 * same placeholder set as `generate-workout-insight.v6`, so one assembly feeds
 * both prompts and the two can be evaluated against the same fixtures.
 * `block` is the same material rendered as ONE string for `assembleWithBudget`,
 * and `shape` is what `pickQuestions` gates the suggested rail on.
 */
export interface SessionContext {
  log: TrainingLogRow;
  parts: {
    workoutType: string;
    distance: string;
    pace: string;
    duration: string;
    mood: string;
    athleteNotes: string;
    pacesBlock: string;
    classificationLine: string;
    splitsBlock: string;
    prescribedBlock: string;
    progressionBlock: string;
    /** Kept separate from `progressionBlock` (which carries both into the
     *  prompt's fixed placeholder set) so the provenance line can name
     *  conditions only when conditions were actually read. */
    conditionsBlock: string;
    keySessionLine: string;
    recentLogs: string;
    recentSummary: string;
  };
  block: string;
  shape: SessionShape;
}

/**
 * Assemble one workout for a prompt: laps, parsed structure, pace zones,
 * conditions, memo, mood — plus the 28-day log in the athlete's own words.
 *
 * Ownership is enforced HERE (`.eq("user_id", userId)`) rather than trusted
 * from the caller: this reads one athlete's private training row by id, and a
 * caller that forgets the check is an IDOR. A row that isn't theirs is
 * indistinguishable from one that doesn't exist — both return null.
 *
 * The splits/structure precedence below is lifted verbatim from
 * `generateInsight`; see the comments there for why parsed blocks beat laps
 * beat watch segments beat voice recall.
 */
export async function buildSessionBlock(
  supabase: SupabaseClient,
  userId: string,
  logId: string,
): Promise<SessionContext | null> {
  // Same select as generate-workout-insight, including the deliberate omission
  // of `scheduled_workout_id` (no such column on training_logs — selecting it
  // makes PostgREST reject the whole query).
  const { data, error } = await supabase
    .from("training_logs")
    .select(
      "id, user_id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes, workout_notes, parsed_structure, coach_insight, pace_segments, extracted_data, weather_actual, stream_meta:external_streams->meta",
    )
    .eq("id", logId)
    .eq("user_id", userId)
    .maybeSingle<
      TrainingLogRow & {
        weather_actual?: Record<string, unknown> | null;
        stream_meta?: Record<string, unknown> | null;
      }
    >();

  if (error) {
    console.warn("buildSessionBlock: load failed:", error.message);
    return null;
  }
  if (!data) return null;
  const log = data;

  const executedPaceSec = parsePaceSec(log.workout_pace_per_mile)
    ?? deriveAveragePace(log.workout_distance_miles, log.workout_duration_minutes);

  const twentyEightDaysAgo = new Date(
    new Date(log.workout_date).getTime() - 28 * 86400000,
  );

  const priorPromise = (log.workout_type && log.workout_distance_miles && executedPaceSec)
    ? findSimilarPriorWorkout(supabase, userId, {
        workoutType: log.workout_type,
        distanceMiles: log.workout_distance_miles,
        paceSecPerMile: executedPaceSec,
      }, new Date(log.workout_date))
    : Promise.resolve(null);

  const [recentRes, coachCtx, prior, lapsRes, keySessionLine] = await Promise.all([
    supabase
      .from("training_logs")
      .select(
        "workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, felt_rpe, cleaned_notes, workout_notes, notes",
      )
      .eq("user_id", userId)
      .gte("workout_date", twentyEightDaysAgo.toISOString())
      .lt("workout_date", log.workout_date)
      .order("workout_date", { ascending: false })
      .limit(40),
    loadCoachContext(supabase, userId),
    priorPromise,
    supabase
      .from("running_workout_laps")
      .select("lap_index, distance_meters, moving_time_seconds, avg_pace_sec_per_mile, avg_heart_rate, is_rest")
      .eq("workout_id", log.id)
      .order("lap_index", { ascending: true }),
    // No scheduled_workout_id column yet, so the plan's own flag is
    // unreachable from here; the athlete's day_override still is.
    resolveKeySessionLine(supabase, userId, (log.workout_date ?? "").slice(0, 10), null),
  ]);

  const recent = (recentRes.data ?? []) as RecentRow[];
  const laps = (lapsRes.data ?? []) as TrainingLap[];

  // "Last 7 days:" must keep meaning 7 days even though `recent` spans 28.
  const sevenDayCutoff = new Date(
    new Date(log.workout_date).getTime() - 7 * 86400000,
  ).getTime();
  const recentSummary = summarizeRecent(
    recent.filter((r) => {
      const t = new Date(r.workout_date).getTime();
      return Number.isFinite(t) && t >= sevenDayCutoff;
    }),
  );
  const recentLogs = formatRecentLogsBlock(recent);

  const pacesBlock = formatPacesBlock(coachCtx);
  const classificationLine = executedPaceSec != null && coachCtx.zones
    ? classifyPace(executedPaceSec, coachCtx.zones).summary
    : "";

  const parsedBlockSplits = splitsFromParsedBlocks(log.parsed_structure?.blocks);
  const lapSplits = splitsFromLaps(laps);
  const watchSplits = splitsFromPaceSegments(log.pace_segments);
  const extractedIntervals = (log.extracted_data?.intervals ?? null) as
    | Array<{ distance?: string; time?: string; rest?: string; count?: number }>
    | null;
  const voiceSplits = splitsFromExtractedIntervals(extractedIntervals);
  const workRepCount = (s: WorkoutSplit[]) => s.filter((x) => x.effortKind === "work").length;
  const splits = workRepCount(parsedBlockSplits) >= 2
    ? parsedBlockSplits
    : lapSplits.length >= 2
    ? lapSplits
    : watchSplits.length > 0
    ? watchSplits
    : voiceSplits;
  const isQuality = isQualityWorkoutType(log.workout_type);
  const splitsBlock = formatSplitsBlock(
    splits,
    coachCtx.zones,
    isQuality ? { detectPattern: true } : { detectPattern: true, largeDropoffOnly: true },
  );

  // No linkage column, so there is never a prescription to compare against.
  // Kept as an explicit empty rather than dropped, so the day the column
  // lands this is the one place to wire it.
  const prescribedBlock = "";

  const conditionsBlock = formatConditionsBlock(
    (log.stream_meta ?? null) as Record<string, unknown> | null,
    (log.weather_actual ?? null) as Record<string, unknown> | null,
  );

  const progressionBlock = (prior && log.workout_type && log.workout_distance_miles && executedPaceSec)
    ? (formatProgressionBlock(
        {
          workoutType: log.workout_type,
          distanceMiles: log.workout_distance_miles,
          paceSecPerMile: executedPaceSec,
        },
        prior,
      )?.block ?? "")
    : "";

  const workoutDescription = (log.parsed_structure?.intent_pattern?.trim())
    || (log.workout_notes?.trim())
    || (log.parsed_structure?.pattern?.trim() ?? "");
  const athleteNotes = [
    workoutDescription ? `Workout: ${workoutDescription}` : "",
    (log.cleaned_notes ?? log.notes ?? "").trim(),
  ].filter((s) => s.length > 0).join("\n") || "—";

  const parts = {
    workoutType: log.workout_type ?? "run",
    distance: log.workout_distance_miles != null ? String(log.workout_distance_miles) : "?",
    pace: log.workout_pace_per_mile ?? "?",
    duration: log.workout_duration_minutes != null ? String(log.workout_duration_minutes) : "?",
    mood: log.mood ?? "—",
    athleteNotes,
    pacesBlock,
    classificationLine,
    splitsBlock,
    prescribedBlock,
    progressionBlock: [progressionBlock, conditionsBlock]
      .filter((s) => s.trim().length > 0).join("\n\n"),
    conditionsBlock,
    keySessionLine,
    recentLogs,
    recentSummary,
  };

  // One budgetable string. `recentLogs` is NOT folded in — it is its own
  // (preferred) block so the budgeter can drop the 28-day history without
  // taking the session itself with it.
  const block = [
    "## This session",
    `- Type: ${parts.workoutType}`,
    `- Distance: ${parts.distance} mi`,
    `- Pace: ${parts.pace}/mi`,
    `- Duration: ${parts.duration} min`,
    `- Mood: ${parts.mood}`,
    `- Athlete notes: ${parts.athleteNotes}`,
    keySessionLine,
    pacesBlock,
    classificationLine,
    splitsBlock,
    prescribedBlock,
    progressionBlock,
    conditionsBlock,
  ].filter((s) => s && s.trim().length > 0).join("\n\n");

  const hasHeartRate = laps.some((l) => typeof l.avg_heart_rate === "number" && l.avg_heart_rate > 0)
    || (log.pace_segments ?? []).some((s) => typeof s.avg_heart_rate === "number" && s.avg_heart_rate > 0)
    || (log.parsed_structure?.blocks ?? []).some((b) => typeof b.avg_hr === "number" && b.avg_hr > 0);

  const streamMeta = (log.stream_meta ?? null) as Record<string, unknown> | null;
  const elevGainM = Number(streamMeta?.total_elevation_gain);

  const noteText = [log.cleaned_notes, log.workout_notes, log.notes]
    .filter((s): s is string => typeof s === "string" && s.length > 0)
    .join(" ");

  const shape: SessionShape = {
    workoutType: log.workout_type,
    distanceMiles: log.workout_distance_miles,
    repCount: workRepCount(splits),
    hasSplits: splits.length > 0,
    hasHeartRate,
    hasElevation: Number.isFinite(elevGainM) && elevGainM > 0,
    hasConditions: log.weather_actual != null && Object.keys(log.weather_actual).length > 0,
    hasNotes: noteText.trim().length > 0,
    // No scheduled_workout_id column — nothing can be linked yet.
    hasPrescription: false,
    hasComparable: prior != null,
    hasBodyMention: noteText.length > 0 && detectInjury(noteText) != null,
    hasGoal: coachCtx.goal != null,
  };

  return { log, parts, block, shape };
}
