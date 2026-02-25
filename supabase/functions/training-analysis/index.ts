/**
 * Training Analysis Edge Function
 *
 * Generates comprehensive training analysis for monthly, yearly, or custom periods.
 * Aggregates quantitative workout data and qualitative notes for AI-powered insights.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.21.0";

import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import { validateEnum, validateRange, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type PeriodType = "month" | "year" | "custom";

interface AnalysisRequest {
  periodType: PeriodType;
  year: number;
  month?: number; // 1-12, required for "month" type
  startDate?: string; // ISO date, for "custom" type
  endDate?: string; // ISO date, for "custom" type
  userId?: string;
}

interface TrainingLog {
  id: string;
  created_at: string;
  workout_date: string | null;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  mood: string | null;
  notes: string | null;
  cleaned_notes: string | null;
  coach_insight: string | null;
}

interface AggregatedStats {
  totalRuns: number;
  totalMiles: number;
  totalMinutes: number;
  averagePace: string;
  averageDistance: number;
  longestRun: number;
  shortestRun: number;
  runsByWeek: { week: number; runs: number; miles: number; isComplete: boolean }[];
  moodDistribution: Record<string, number>;
  daysWithRuns: number;
  restDays: number;
}

interface PeriodProgress {
  totalDays: number;
  elapsedDays: number;
  remainingDays: number;
  percentComplete: number;
  isComplete: boolean;
  currentWeekNumber: number;
  weeksInPeriod: number;
  completedWeeks: number;
}

interface ProjectedStats {
  projectedMiles: number;
  projectedRuns: number;
  milesPerDay: number;
  runsPerWeek: number;
  projectedWeeklyAverage: number;
}

interface QualitativeSummary {
  allNotes: string[];
  themes: string[];
  moodTrend: string;
  notableWorkouts: string[];
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function getDateRange(request: AnalysisRequest): { start: Date; end: Date; label: string } {
  const { periodType, year, month, startDate, endDate } = request;

  if (periodType === "month" && month) {
    const start = new Date(year, month - 1, 1);
    const end = new Date(year, month, 0, 23, 59, 59);
    const monthName = start.toLocaleString("default", { month: "long" });
    return { start, end, label: `${monthName} ${year}` };
  }

  if (periodType === "year") {
    const start = new Date(year, 0, 1);
    const end = new Date(year, 11, 31, 23, 59, 59);
    return { start, end, label: `${year}` };
  }

  if (periodType === "custom" && startDate && endDate) {
    const start = new Date(startDate);
    const end = new Date(endDate);
    end.setHours(23, 59, 59);
    return {
      start,
      end,
      label: `${start.toLocaleDateString()} - ${end.toLocaleDateString()}`,
    };
  }

  // Default to current month
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), 1);
  const end = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);
  const monthName = start.toLocaleString("default", { month: "long" });
  return { start, end, label: `${monthName} ${now.getFullYear()}` };
}

function formatPace(totalMinutes: number, totalMiles: number): string {
  if (totalMiles === 0) return "N/A";
  const totalSecs = Math.round((totalMinutes / totalMiles) * 60);
  const mins = Math.floor(totalSecs / 60);
  const secs = totalSecs % 60;
  return `${mins}:${secs.toString().padStart(2, "0")}/mi`;
}

function calculatePeriodProgress(start: Date, end: Date): PeriodProgress {
  const now = new Date();

  // Calculate total days using date difference (not milliseconds) to avoid off-by-one errors
  // For a week Mon-Sun: (Sun date - Mon date) + 1 = 6 + 1 = 7 days
  const startDate = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  const endDate = new Date(end.getFullYear(), end.getMonth(), end.getDate());
  const daysDiff = Math.round((endDate.getTime() - startDate.getTime()) / (24 * 60 * 60 * 1000));
  const totalDays = daysDiff + 1; // +1 to include both start and end days

  // If period hasn't started yet
  if (now < start) {
    return {
      totalDays,
      elapsedDays: 0,
      remainingDays: totalDays,
      percentComplete: 0,
      isComplete: false,
      currentWeekNumber: 0,
      weeksInPeriod: Math.ceil(totalDays / 7),
      completedWeeks: 0,
    };
  }

  // If period is complete
  if (now > end) {
    return {
      totalDays,
      elapsedDays: totalDays,
      remainingDays: 0,
      percentComplete: 100,
      isComplete: true,
      currentWeekNumber: Math.ceil(totalDays / 7),
      weeksInPeriod: Math.ceil(totalDays / 7),
      completedWeeks: Math.ceil(totalDays / 7),
    };
  }

  // Period is in progress
  // Calculate days elapsed: day 1 = first day, day 2 = second day, etc.
  // We add 1 because if we're on the first day, elapsed time is <24h but we want to count it as day 1
  const elapsedMs = now.getTime() - start.getTime();
  const daysSinceStart = Math.floor(elapsedMs / (24 * 60 * 60 * 1000));
  const elapsedDays = daysSinceStart + 1; // +1 because day 1 is the start day
  const remainingDays = totalDays - elapsedDays;
  const percentComplete = Math.round((elapsedDays / totalDays) * 100);
  const currentWeekNumber = Math.ceil(elapsedDays / 7);
  const weeksInPeriod = Math.ceil(totalDays / 7);
  const completedWeeks = Math.floor(elapsedDays / 7);

  return {
    totalDays,
    elapsedDays,
    remainingDays,
    percentComplete,
    isComplete: false,
    currentWeekNumber,
    weeksInPeriod,
    completedWeeks,
  };
}

function calculateProjections(stats: AggregatedStats, progress: PeriodProgress): ProjectedStats {
  if (progress.isComplete || progress.elapsedDays === 0) {
    // Period is complete - no projection needed
    return {
      projectedMiles: stats.totalMiles,
      projectedRuns: stats.totalRuns,
      milesPerDay: progress.elapsedDays > 0 ? stats.totalMiles / progress.elapsedDays : 0,
      runsPerWeek: progress.completedWeeks > 0 ? stats.totalRuns / progress.completedWeeks : stats.totalRuns,
      projectedWeeklyAverage: progress.weeksInPeriod > 0 ? stats.totalMiles / progress.weeksInPeriod : stats.totalMiles,
    };
  }

  // Calculate daily rate and project to full period
  const milesPerDay = stats.totalMiles / progress.elapsedDays;
  const runsPerDay = stats.totalRuns / progress.elapsedDays;

  const projectedMiles = Math.round(milesPerDay * progress.totalDays * 10) / 10;
  const projectedRuns = Math.round(runsPerDay * progress.totalDays);
  const runsPerWeek = Math.round((stats.totalRuns / progress.elapsedDays) * 7 * 10) / 10;
  const projectedWeeklyAverage = Math.round((projectedMiles / progress.weeksInPeriod) * 10) / 10;

  return {
    projectedMiles,
    projectedRuns,
    milesPerDay: Math.round(milesPerDay * 100) / 100,
    runsPerWeek,
    projectedWeeklyAverage,
  };
}

function getWeekNumber(date: Date): number {
  const startOfYear = new Date(date.getFullYear(), 0, 1);
  const days = Math.floor((date.getTime() - startOfYear.getTime()) / (24 * 60 * 60 * 1000));
  return Math.ceil((days + startOfYear.getDay() + 1) / 7);
}

function aggregateStats(logs: TrainingLog[], start: Date, end: Date, progress?: PeriodProgress): AggregatedStats {
  const runsWithDistance = logs.filter((log) => log.workout_distance_miles && log.workout_distance_miles > 0);

  const totalMiles = runsWithDistance.reduce((sum, log) => sum + (log.workout_distance_miles || 0), 0);
  const totalMinutes = runsWithDistance.reduce((sum, log) => sum + (log.workout_duration_minutes || 0), 0);
  const distances = runsWithDistance.map((log) => log.workout_distance_miles || 0);

  // Group by week
  const weeklyData: Record<number, { runs: number; miles: number }> = {};
  runsWithDistance.forEach((log) => {
    const logDate = new Date(log.workout_date || log.created_at);
    const week = getWeekNumber(logDate);
    if (!weeklyData[week]) {
      weeklyData[week] = { runs: 0, miles: 0 };
    }
    weeklyData[week].runs++;
    weeklyData[week].miles += log.workout_distance_miles || 0;
  });

  // Determine current week to mark incomplete weeks
  const currentWeek = progress ? getWeekNumber(new Date()) : 0;
  const periodIsComplete = progress?.isComplete ?? true;

  const runsByWeek = Object.entries(weeklyData)
    .map(([week, data]) => ({
      week: parseInt(week),
      runs: data.runs,
      miles: Math.round(data.miles * 10) / 10,
      isComplete: periodIsComplete || parseInt(week) < currentWeek,
    }))
    .sort((a, b) => a.week - b.week);

  // Mood distribution
  const moodDistribution: Record<string, number> = {};
  logs.forEach((log) => {
    if (log.mood) {
      moodDistribution[log.mood] = (moodDistribution[log.mood] || 0) + 1;
    }
  });

  // Calculate days in period and rest days
  const daysInPeriod = Math.ceil((end.getTime() - start.getTime()) / (24 * 60 * 60 * 1000));
  const uniqueRunDays = new Set(
    runsWithDistance.map((log) => {
      const date = new Date(log.workout_date || log.created_at);
      return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
    })
  ).size;

  return {
    totalRuns: runsWithDistance.length,
    totalMiles: Math.round(totalMiles * 10) / 10,
    totalMinutes: Math.round(totalMinutes),
    averagePace: formatPace(totalMinutes, totalMiles),
    averageDistance: runsWithDistance.length > 0 ? Math.round((totalMiles / runsWithDistance.length) * 10) / 10 : 0,
    longestRun: distances.length > 0 ? Math.max(...distances) : 0,
    shortestRun: distances.length > 0 ? Math.min(...distances) : 0,
    runsByWeek,
    moodDistribution,
    daysWithRuns: uniqueRunDays,
    restDays: daysInPeriod - uniqueRunDays,
  };
}

function extractQualitativeData(logs: TrainingLog[]): QualitativeSummary {
  const allNotes: string[] = [];
  const notableWorkouts: string[] = [];

  logs.forEach((log) => {
    const note = log.cleaned_notes || log.notes;
    if (note && note.trim()) {
      allNotes.push(note);

      // Identify notable workouts (tempo, intervals, race, PR, long run mentions)
      const notablePhrases = ["tempo", "interval", "race", "pr", "personal", "long run", "workout", "speed", "hard"];
      if (notablePhrases.some((phrase) => note.toLowerCase().includes(phrase))) {
        const date = new Date(log.workout_date || log.created_at);
        notableWorkouts.push(`${date.toLocaleDateString()}: ${note.slice(0, 150)}...`);
      }
    }
  });

  // Calculate mood trend
  const moods = logs.filter((log) => log.mood).map((log) => log.mood!);
  const positiveMoods = moods.filter((m) => ["energized", "strong", "great", "good"].includes(m.toLowerCase())).length;
  const negativeMoods = moods.filter((m) => ["tired", "sluggish", "exhausted", "fatigued"].includes(m.toLowerCase())).length;
  const moodTrend =
    positiveMoods > negativeMoods * 1.5
      ? "predominantly positive"
      : negativeMoods > positiveMoods * 1.5
      ? "showing fatigue patterns"
      : "mixed/balanced";

  return {
    allNotes,
    themes: [], // Will be extracted by AI
    moodTrend,
    notableWorkouts: notableWorkouts.slice(0, 5),
  };
}

function buildAnalysisPrompt(
  periodLabel: string,
  stats: AggregatedStats,
  qualitative: QualitativeSummary,
  progress: PeriodProgress,
  projections: ProjectedStats,
  previousPeriodStats?: AggregatedStats
): string {
  const weeklyBreakdown = stats.runsByWeek
    .map((w) => {
      const incompleteTag = !w.isComplete ? " (in progress)" : "";
      return `Week ${w.week}: ${w.runs} runs, ${w.miles} miles${incompleteTag}`;
    })
    .join("\n");

  const moodBreakdown = Object.entries(stats.moodDistribution)
    .map(([mood, count]) => `${mood}: ${count}`)
    .join(", ");

  const notesExcerpt = qualitative.allNotes.slice(0, 10).join("\n---\n");

  const comparisonSection = previousPeriodStats
    ? `
Previous Period Comparison:
- Previous total miles: ${previousPeriodStats.totalMiles}
- Previous total runs: ${previousPeriodStats.totalRuns}
- Mile change: ${stats.totalMiles > previousPeriodStats.totalMiles ? "+" : ""}${Math.round((stats.totalMiles - previousPeriodStats.totalMiles) * 10) / 10}
- Volume trend: ${stats.totalMiles > previousPeriodStats.totalMiles * 1.1 ? "increasing" : stats.totalMiles < previousPeriodStats.totalMiles * 0.9 ? "decreasing" : "stable"}`
    : "";

  // Build progress/projection section for incomplete periods
  const isIncomplete = !progress.isComplete;

  const periodStatusNote = isIncomplete
    ? `

⚠️ CRITICAL: THIS IS AN INCOMPLETE PERIOD (${progress.percentComplete}% complete, ${progress.elapsedDays} of ${progress.totalDays} days)
- ${progress.remainingDays} days still remaining in this period
- Currently in week ${progress.currentWeekNumber} of ${progress.weeksInPeriod}
- At current pace: ${projections.milesPerDay.toFixed(1)} miles/day → projecting to ${projections.projectedMiles} miles for the full period
- Projected weekly average: ${projections.projectedWeeklyAverage} miles/week

YOU MUST acknowledge this is a partial/incomplete period throughout your analysis. Do NOT discuss totals as if the period is finished.
Instead of "You ran X miles this month", say "You've logged X miles so far this month (${progress.elapsedDays} days in), trending toward ~${projections.projectedMiles} miles at your current pace."
`
    : "";

  const incompleteInstructions = isIncomplete
    ? `
MANDATORY FOR INCOMPLETE PERIODS:
- In PERIOD OVERVIEW: Start by noting this is an in-progress period with ${progress.remainingDays} days remaining
- In VOLUME ANALYSIS: State actual miles SO FAR and the projected total (e.g., "${stats.totalMiles} miles in ${progress.elapsedDays} days, on pace for ~${projections.projectedMiles} miles")
- Always use phrases like "so far", "to date", "currently", "on track for", "trending toward"
- NEVER discuss the totals as if the period is complete
`
    : "";

  return `You are Coach, analyzing a runner's training for ${periodLabel}.

IMPORTANT: Never mention specific coaching methodologies, frameworks, or coach names (e.g., Canova, VDOT, Jack Daniels) in your response. Just apply the principles naturally.
${periodStatusNote}

Coaching Philosophy to Apply:
- Value rest days and recovery - they are productive, not weakness
- Support mobility and active recovery for keeping the body moving well
- If fatigue patterns appear, acknowledge them positively and recommend backing off
- For any injury mentions in notes, flag them seriously - catching issues early prevents bigger problems
- Encourage running relaxed and within yourself, even on hard efforts
- Be understanding and positive - reaffirm the athlete is working hard and progressing toward their goals

QUANTITATIVE DATA:
- Total runs: ${stats.totalRuns}
- Total miles: ${stats.totalMiles}
- Total time: ${Math.floor(stats.totalMinutes / 60)}h ${stats.totalMinutes % 60}m
- Average pace: ${stats.averagePace}
- Average run distance: ${stats.averageDistance} miles
- Longest run: ${stats.longestRun} miles
- Days with runs: ${stats.daysWithRuns}
- Rest days: ${stats.restDays}

Weekly Breakdown:
${weeklyBreakdown}

Mood Distribution: ${moodBreakdown || "No mood data recorded"}
Overall mood trend: ${qualitative.moodTrend}
${comparisonSection}

QUALITATIVE DATA (Runner's Notes):
${notesExcerpt || "No notes recorded this period"}

Notable Workouts:
${qualitative.notableWorkouts.join("\n") || "None identified"}

---
${incompleteInstructions}

Provide a training analysis with these sections (use plain text, no markdown headers or bold):

1. PERIOD OVERVIEW (2-3 sentences summarizing the training block)
${isIncomplete ? `   - REQUIRED: Start with "With ${progress.remainingDays} days remaining in this period..." or similar acknowledgment that this is in-progress` : ""}

2. VOLUME & CONSISTENCY ANALYSIS
- Comment on weekly mileage patterns
- Note any concerning gaps or inconsistencies
- Assess the balance of training days vs rest
${isIncomplete ? `   - REQUIRED: State "${stats.totalMiles} miles logged so far, on pace for approximately ${projections.projectedMiles} miles"` : ""}

3. WORKOUT QUALITY (based on notes and notable workouts)
- Identify what types of training were emphasized
- Note any patterns in workout descriptions

4. RECOVERY & WELL-BEING
- Analyze mood patterns and what they suggest
- If fatigue patterns appear, acknowledge them with understanding and support taking time to recover
- Flag any injury mentions from the notes - emphasize catching issues early
- Comment on rest day balance and mobility/recovery practices

5. KEY INSIGHTS
- 2-3 specific observations unique to this runner's data
- Connect dots between quantitative and qualitative data
- Acknowledge the hard work they've put in${isIncomplete ? " so far" : " this period"}

6. RECOMMENDATIONS FOR ${isIncomplete ? "THE REST OF THIS PERIOD" : "NEXT PERIOD"}
- Specific, actionable suggestions based on the data
- Include mobility and active recovery recommendations
- If showing fatigue, fully support backing off with positive reinforcement
- Encourage running relaxed and within yourself, even on hard efforts
- Reaffirm their progress toward their goals

Write conversationally with understanding and positivity. Reference specific numbers and patterns from the data. Be supportive while providing honest, helpful analysis.`;
}

// ============================================================================
// MAIN HANDLER
// ============================================================================

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  try {
    // Verify authenticated user from JWT
    const userId = await getAuthenticatedUser(req);
    if (!userId) {
      return unauthorizedResponse(corsHeaders);
    }

    // Rate limiting
    if (isRateLimitEnabled()) {
      const rateLimit = await checkFeatureRateLimit(userId, "analysis");
      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({ error: "Rate limit exceeded", remaining: 0, resetAt: rateLimit.resetAt.toISOString() }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    const request = (await req.json()) as AnalysisRequest;
    const { periodType, year, month } = request;

    if (!periodType || !year) {
      return new Response(
        JSON.stringify({ error: "periodType and year are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Input validation
    const periodErr = validateEnum(periodType, "periodType", ["month", "year", "custom"]);
    if (periodErr) return validationErrorResponse(periodErr, corsHeaders);

    const yearErr = validateRange(year, "year", 2020, 2030);
    if (yearErr) return validationErrorResponse(yearErr, corsHeaders);

    if (periodType === "month" && month !== undefined) {
      const monthErr = validateRange(month, "month", 1, 12);
      if (monthErr) return validationErrorResponse(monthErr, corsHeaders);
    }

    // Initialize clients
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) {
      return new Response(
        JSON.stringify({ error: "GEMINI_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get date range for requested period
    const { start, end, label } = getDateRange(request);
    console.log(`Analyzing training for ${label}: ${start.toISOString()} to ${end.toISOString()}`);

    // Fetch training logs for the period
    // Use a broader query with buffer for late entries, then filter precisely in JS
    const bufferDays = 30;
    const queryStart = new Date(start.getTime() - bufferDays * 24 * 60 * 60 * 1000);
    const queryEnd = new Date(end.getTime() + bufferDays * 24 * 60 * 60 * 1000);

    const { data: logs, error: logsError } = await supabase
      .from("training_logs")
      .select("*")
      .gte("created_at", queryStart.toISOString())
      .lte("created_at", queryEnd.toISOString())
      .order("created_at", { ascending: true });

    if (logsError) {
      console.error("Error fetching logs:", logsError);
      throw logsError;
    }

    // Filter logs that actually fall within the date range
    const filteredLogs = (logs || []).filter((log: TrainingLog) => {
      const logDate = new Date(log.workout_date || log.created_at);
      return logDate >= start && logDate <= end;
    });

    console.log(`Found ${filteredLogs.length} training logs for ${label}`);

    // Handle empty period
    if (filteredLogs.length === 0) {
      return new Response(
        JSON.stringify({
          period: label,
          periodType,
          year,
          month,
          stats: {
            totalRuns: 0,
            totalMiles: 0,
            totalMinutes: 0,
            averagePace: "N/A",
            averageDistance: 0,
            longestRun: 0,
            shortestRun: 0,
            runsByWeek: [],
            moodDistribution: {},
            daysWithRuns: 0,
            restDays: 0,
          },
          analysis: "No training data recorded for this period. Start logging your runs to get personalized analysis!",
          processingTime: Date.now() - startTime,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Calculate period progress (is this a complete or in-progress period?)
    const progress = calculatePeriodProgress(start, end);
    console.log(`Period progress: ${progress.percentComplete}% complete (${progress.elapsedDays}/${progress.totalDays} days)`);

    // Aggregate stats
    const stats = aggregateStats(filteredLogs, start, end, progress);
    const qualitative = extractQualitativeData(filteredLogs);

    // Calculate projections for incomplete periods
    const projections = calculateProjections(stats, progress);

    // Fetch previous period for comparison (optional)
    let previousPeriodStats: AggregatedStats | undefined;
    if (periodType === "month" && month) {
      const prevMonth = month === 1 ? 12 : month - 1;
      const prevYear = month === 1 ? year - 1 : year;
      const prevStart = new Date(prevYear, prevMonth - 1, 1);
      const prevEnd = new Date(prevYear, prevMonth, 0, 23, 59, 59);

      const prevQueryStart = new Date(prevStart.getTime() - bufferDays * 24 * 60 * 60 * 1000);
      const prevQueryEnd = new Date(prevEnd.getTime() + bufferDays * 24 * 60 * 60 * 1000);

      const { data: prevLogs } = await supabase
        .from("training_logs")
        .select("*")
        .gte("created_at", prevQueryStart.toISOString())
        .lte("created_at", prevQueryEnd.toISOString());

      const prevFiltered = (prevLogs || []).filter((log: TrainingLog) => {
        const logDate = new Date(log.workout_date || log.created_at);
        return logDate >= prevStart && logDate <= prevEnd;
      });

      if (prevFiltered.length > 0) {
        previousPeriodStats = aggregateStats(prevFiltered, prevStart, prevEnd);
      }
    }

    // Generate AI analysis
    const prompt = buildAnalysisPrompt(label, stats, qualitative, progress, projections, previousPeriodStats);

    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.0-flash",
      generationConfig: {
        maxOutputTokens: 1500,
        temperature: 0.7,
      },
    });

    const result = await model.generateContent(prompt);
    const analysis = result.response.text();

    // Log usage
    if (userId) {
      await supabase.from("usage_tracking").insert({
        user_id: userId,
        feature: "training_analysis",
        model_used: "gemini-2.0-flash",
        input_tokens: Math.round(prompt.length / 4),
        output_tokens: Math.round(analysis.length / 4),
        cached: false,
      });
    }

    const processingTime = Date.now() - startTime;
    console.log(`Analysis generated in ${processingTime}ms`);

    return new Response(
      JSON.stringify({
        period: label,
        periodType,
        year,
        month,
        dateRange: {
          start: start.toISOString(),
          end: end.toISOString(),
        },
        progress: {
          isComplete: progress.isComplete,
          percentComplete: progress.percentComplete,
          elapsedDays: progress.elapsedDays,
          totalDays: progress.totalDays,
          remainingDays: progress.remainingDays,
          currentWeek: progress.currentWeekNumber,
          totalWeeks: progress.weeksInPeriod,
        },
        stats,
        projections: !progress.isComplete
          ? {
              projectedMiles: projections.projectedMiles,
              projectedRuns: projections.projectedRuns,
              milesPerDay: projections.milesPerDay,
              runsPerWeek: projections.runsPerWeek,
              projectedWeeklyAverage: projections.projectedWeeklyAverage,
            }
          : null,
        qualitative: {
          moodTrend: qualitative.moodTrend,
          notableWorkouts: qualitative.notableWorkouts,
          totalNotesRecorded: qualitative.allNotes.length,
        },
        previousPeriod: previousPeriodStats
          ? {
              totalMiles: previousPeriodStats.totalMiles,
              totalRuns: previousPeriodStats.totalRuns,
              milesDiff: Math.round((stats.totalMiles - previousPeriodStats.totalMiles) * 10) / 10,
            }
          : null,
        analysis,
        processingTime,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Training analysis error:", error);
    return internalErrorResponse(corsHeaders);
  }
});
