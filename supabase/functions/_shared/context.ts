/**
 * Context Compression Module
 * Compresses training logs and goals into minimal tokens
 * Reduces context from ~500+ tokens to ~50 tokens (90% reduction)
 */

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
