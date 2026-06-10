/**
 * Training Analysis Edge Function
 *
 * Generates comprehensive training analysis for monthly, yearly, or custom periods.
 * Aggregates quantitative workout data and qualitative notes for AI-powered insights.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";

import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import { validateEnum, validateRange, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";
import { buildAthleteProfileContext, type AthleteProfile } from "../_shared/athleteProfile.ts";
import { legacyZonesFromSnapshot, rangesFromSnapshot, type PaceZoneRanges } from "../_shared/pace-engine.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

import { corsHeaders } from "../_shared/cors.ts";
type PeriodType = "month" | "year" | "custom";

interface AnalysisRequest {
  periodType: PeriodType;
  year: number;
  month?: number; // 1-12, required for "month" type
  startDate?: string; // ISO date, for "custom" type
  endDate?: string; // ISO date, for "custom" type
  userId?: string;
}

interface PaceSegmentRow {
  effort: string;
  distance_miles: number;
  duration_seconds: number;
  pace_per_mile: string;
  avg_heart_rate: number | null;
}

interface TrainingLog {
  id: string;
  created_at: string;
  workout_date: string | null;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_type: string | null;
  workout_pace_per_mile: string | null;
  pace_segments: PaceSegmentRow[] | null;
  mood: string | null;
  notes: string | null;
  cleaned_notes: string | null;
  coach_insight: string | null;
  workout_notes: string | null;
}

interface ZoneVolume {
  miles: number;
  runs: number;
  avgPace: string;
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
  workoutTypeDistribution: Record<string, number>;
  zoneVolume: Record<string, ZoneVolume>;
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

  // Workout type distribution
  const workoutTypeDistribution: Record<string, number> = {};
  runsWithDistance.forEach((log) => {
    const type = (log as TrainingLog).workout_type || "untagged";
    workoutTypeDistribution[type] = (workoutTypeDistribution[type] || 0) + 1;
  });

  // Zone volume — group miles by training zone
  // When pace_segments are available, use per-segment data for accurate zone breakdown
  const zoneMap: Record<string, string> = {
    easy: "easy", recovery: "recovery", long_run: "long_run",
    tempo: "tempo", threshold: "threshold", steady: "threshold",
    interval: "interval", speed: "interval", repeat: "interval", fartlek: "interval",
    marathon_pace: "race_pace", race_pace: "race_pace", race: "race_pace", time_trial: "race_pace",
    moderate: "tempo", progression: "tempo", run: "easy",
  };
  const zoneAccum: Record<string, { miles: number; runs: number; totalPaceSecs: number; paceCount: number }> = {};
  const addToZone = (zone: string, miles: number, paceSecs: number) => {
    if (!zoneAccum[zone]) zoneAccum[zone] = { miles: 0, runs: 0, totalPaceSecs: 0, paceCount: 0 };
    zoneAccum[zone].miles += miles;
    if (paceSecs > 0) {
      zoneAccum[zone].totalPaceSecs += paceSecs;
      zoneAccum[zone].paceCount++;
    }
  };
  runsWithDistance.forEach((log) => {
    const typedLog = log as TrainingLog;
    const dist = log.workout_distance_miles || 0;
    const dur = log.workout_duration_minutes || 0;

    // If pace segments exist, use them for per-segment zone breakdown
    if (typedLog.pace_segments && typedLog.pace_segments.length > 0) {
      // Helper: parse pace string "M:SS" to seconds
      const parsePaceSecs = (p: string) => {
        const parts = p.split(":").map(Number);
        return parts.length === 2 ? parts[0] * 60 + parts[1] : 0;
      };

      // Check if all segments share the same effort label (watch didn't differentiate)
      const uniqueEfforts = new Set(typedLog.pace_segments.map(s => s.effort));
      const allSameLabel = uniqueEfforts.size === 1;

      // If all same label, classify by pace instead of label
      if (allSameLabel && typedLog.pace_segments.length >= 3) {
        const runnableSegs = typedLog.pace_segments.filter(s => {
          const p = parsePaceSecs(s.pace_per_mile);
          return s.distance_miles >= 0.05 && p > 0 && p < 900;
        });
        const paces = runnableSegs.map(s => parsePaceSecs(s.pace_per_mile)).sort((a, b) => a - b);
        const medianPace = paces.length > 0 ? paces[Math.floor(paces.length / 2)] : 0;
        const fastestPace = paces.length > 0 ? paces[0] : 0;
        const paceSpread = medianPace > 0 ? (medianPace - fastestPace) / medianPace : 0;

        if (paceSpread > 0.15) {
          // Classify by pace: fast segments → interval, slow/standing → skip, rest → easy
          const threshold = fastestPace + (medianPace - fastestPace) * 0.4;
          for (const seg of typedLog.pace_segments) {
            const p = parsePaceSecs(seg.pace_per_mile);
            if (p <= 0 || seg.distance_miles < 0.02) continue; // skip standing/zero
            if (p >= 900) continue; // skip segments > 15:00/mi (standing around)
            const zone = p <= threshold ? "interval" : "easy";
            addToZone(zone, seg.distance_miles, p);
          }
        } else {
          // Low variance — all genuinely the same effort
          for (const seg of typedLog.pace_segments) {
            const p = parsePaceSecs(seg.pace_per_mile);
            if (p >= 900 || seg.distance_miles < 0.02) continue; // skip standing
            const segZone = zoneMap[seg.effort] || "easy";
            addToZone(segZone, seg.distance_miles, p);
          }
        }
      } else {
        // Multiple effort labels — use them directly, but still skip standing
        for (const seg of typedLog.pace_segments) {
          const paceSecs = parsePaceSecs(seg.pace_per_mile);
          if (paceSecs >= 900 || seg.distance_miles < 0.02) continue; // skip standing
          const segZone = zoneMap[seg.effort] || "easy";
          addToZone(segZone, seg.distance_miles, paceSecs);
        }
      }

      // Count as one run in the dominant zone (by miles)
      const validSegs = typedLog.pace_segments.filter(s => {
        const p = parsePaceSecs(s.pace_per_mile);
        return s.distance_miles >= 0.02 && p > 0 && p < 900;
      });
      if (validSegs.length > 0) {
        const dominantSeg = validSegs.reduce((best, seg) =>
          seg.distance_miles > best.distance_miles ? seg : best
        );
        const mappedDominant = zoneMap[dominantSeg.effort] || "easy";
        if (!zoneAccum[mappedDominant]) zoneAccum[mappedDominant] = { miles: 0, runs: 0, totalPaceSecs: 0, paceCount: 0 };
        zoneAccum[mappedDominant].runs++;
      }
    } else {
      // Fallback: whole-run classification
      const rawType = (typedLog.workout_type || "").toLowerCase().replace(/[_\s-]+/g, "_");
      let zone = zoneMap[rawType] || "easy";
      if (zone === "easy" && dist >= 10) zone = "long_run";
      if (!zoneAccum[zone]) zoneAccum[zone] = { miles: 0, runs: 0, totalPaceSecs: 0, paceCount: 0 };
      zoneAccum[zone].miles += dist;
      zoneAccum[zone].runs++;
      if (dur > 0 && dist > 0) {
        zoneAccum[zone].totalPaceSecs += (dur / dist) * 60;
        zoneAccum[zone].paceCount++;
      }
    }
  });
  const zoneVolume: Record<string, ZoneVolume> = {};
  for (const [zone, data] of Object.entries(zoneAccum)) {
    if (data.miles < 0.1) continue;
    const avgPaceSecs = data.paceCount > 0 ? data.totalPaceSecs / data.paceCount : 0;
    zoneVolume[zone] = {
      miles: Math.round(data.miles * 10) / 10,
      runs: data.runs,
      avgPace: avgPaceSecs > 0 ? (() => { const m = Math.floor(avgPaceSecs / 60); const s = Math.round(avgPaceSecs % 60); return `${m}:${s.toString().padStart(2, "0")}/mi`; })() : "N/A",
    };
  }

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
    workoutTypeDistribution,
    zoneVolume,
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

interface QualitySession {
  date: string;
  totalMiles: number;
  workoutType: string;
  description: string;      // human-readable: "6x800m @ 3:08-3:12 w/ 400m jog"
  fastPace: string;         // avg pace of hard segments
  fastMiles: number;
  warmupCooldownMiles: number;
  splits: string[];          // per-rep splits: ["1mi @ 6:05", "1mi @ 6:08", ...]
  mood: string;
  notes: string;
  workoutNotes: string;     // structured workout notes from voice memo (e.g. "Intervals: 6x800m @ 2:50")
  paceZoneLabel: string;    // e.g. "@ 10K pace", "between HM and marathon pace"
}

/** Equivalent pace zones derived from fitness predictions (seconds per mile) */
interface PaceZones {
  easy: number;       // ~75% of VDOT effort, roughly marathon pace + 90s
  marathon: number;
  halfMarathon: number;
  threshold: number;  // ~LT, roughly between 10K and HM pace
  tenK: number;
  fiveK: number;
}

/**
 * Pace zones come from the central PaceEngine. See _shared/pace-engine.ts.
 * Local function kept as a thin shim so existing call sites (and the local
 * PaceZones interface) don't need to change in this migration.
 */
function computePaceZones(snapshots: { predicted_marathon_seconds?: number; predicted_half_seconds?: number; predicted_10k_seconds?: number; predicted_5k_seconds?: number }): PaceZones | null {
  return legacyZonesFromSnapshot(snapshots);
}

/**
 * Label a pace (seconds/mile) relative to the runner's known pace zones.
 * Returns a string like "@ 10K pace", "faster than 5K pace", "between HM and marathon pace"
 */
function labelPaceZone(paceSecsPerMile: number, zones: PaceZones): string {
  const tolerance = 8; // seconds tolerance for "at" vs "near"

  // Threshold dropped from the canonical chart — HMP covers that effort
  // band per the unified pace spectrum.
  const zoneDefs = [
    { name: "5K pace", pace: zones.fiveK },
    { name: "10K pace", pace: zones.tenK },
    { name: "HM pace", pace: zones.halfMarathon },
    { name: "marathon pace", pace: zones.marathon },
    { name: "easy pace", pace: zones.easy },
  ];

  // Check if it's faster than 5K pace
  if (paceSecsPerMile < zones.fiveK - tolerance) {
    return "faster than 5K pace";
  }

  // Check each zone for a match
  for (const z of zoneDefs) {
    if (Math.abs(paceSecsPerMile - z.pace) <= tolerance) {
      return `@ ${z.name}`;
    }
  }

  // Between zones — find the two closest
  for (let i = 0; i < zoneDefs.length - 1; i++) {
    const faster = zoneDefs[i];
    const slower = zoneDefs[i + 1];
    if (paceSecsPerMile > faster.pace && paceSecsPerMile < slower.pace) {
      return `between ${faster.name} and ${slower.name}`;
    }
  }

  // Slower than easy
  if (paceSecsPerMile > zones.easy + tolerance) {
    return "recovery pace";
  }

  return "";
}

/**
 * Extract structured quality sessions from workouts with pace_segments.
 * Reconstructs actual workout structure: intervals, tempo blocks, etc.
 * When paceZones are available, labels each hard segment relative to known training paces.
 */
function extractQualitySessions(logs: TrainingLog[], paceZones: PaceZones | null): QualitySession[] {
  const sessions: QualitySession[] = [];

  for (const log of logs) {
    if (!log.pace_segments || log.pace_segments.length < 2) continue;

    const date = new Date(log.workout_date || log.created_at);
    const dateStr = `${date.getMonth() + 1}/${date.getDate()}`;

    const hardEfforts = ["interval", "tempo", "threshold", "race_pace", "speed", "moderate"];
    const easyEfforts = ["easy", "recovery", "warmup", "cooldown"];

    // Parse pace to seconds for each segment
    const parsePace = (p: string) => {
      const parts = p.split(":").map(Number);
      return parts.length === 2 ? parts[0] * 60 + parts[1] : 0;
    };

    // Filter out standing/walking segments (> 15:00/mi or tiny distance) from all processing
    const isRunning = (s: PaceSegmentRow) => {
      const p = parsePace(s.pace_per_mile);
      return s.distance_miles >= 0.05 && p > 0 && p < 900;
    };
    const runningSegs = log.pace_segments.filter(isRunning);
    if (runningSegs.length < 2) continue;

    let hardSegs = runningSegs.filter(s => hardEfforts.includes(s.effort));
    let easySegs = runningSegs.filter(s => !hardEfforts.includes(s.effort));

    // FALLBACK: If no segments are labeled hard, detect fast reps by pace
    // This handles watches that label everything "easy" even during intervals
    if (hardSegs.length === 0) {
      // Find the median pace of runnable segments (standing already filtered)
      const paces = runningSegs.map(s => parsePace(s.pace_per_mile)).sort((a, b) => a - b);
      const medianPace = paces[Math.floor(paces.length / 2)];

      // If there's meaningful pace variance (fastest is >15% faster than median),
      // the fast segments are likely interval reps
      const fastestPace = paces[0];
      const paceSpread = (medianPace - fastestPace) / medianPace;

      if (paceSpread > 0.15) {
        // Threshold: segments faster than midpoint between fastest and median are "hard"
        const threshold = fastestPace + (medianPace - fastestPace) * 0.4;
        hardSegs = runningSegs.filter(s => {
          const p = parsePace(s.pace_per_mile);
          return p > 0 && p <= threshold;
        });
        easySegs = runningSegs.filter(s => !hardSegs.includes(s));
      }

      if (hardSegs.length === 0) continue;
    }

    const fastMiles = hardSegs.reduce((sum, s) => sum + s.distance_miles, 0);
    const easyMiles = easySegs.reduce((sum, s) => sum + s.distance_miles, 0);

    // Calculate avg fast pace
    const totalFastSecs = hardSegs.reduce((sum, s) => sum + s.duration_seconds, 0);
    const avgFastPaceSecs = fastMiles > 0 ? totalFastSecs / fastMiles : 0;
    const fastPaceMin = Math.floor(avgFastPaceSecs / 60);
    const fastPaceSec = Math.round(avgFastPaceSecs % 60);
    const fastPace = `${fastPaceMin}:${String(fastPaceSec).padStart(2, "0")}/mi`;

    // Determine workout type from segments
    let workoutType = "quality";
    const dominantEffort = hardSegs.reduce((best, s) =>
      s.distance_miles > best.distance_miles ? s : best
    ).effort;

    // Build human-readable description
    let description = "";

    // Detect if hard segments are interleaved with recovery (= repeats, not continuous)
    // Look at the original segment order: hard-easy-hard-easy = repeats
    const sustainedEfforts = ["tempo", "threshold", "moderate"];
    let hasInterleavedRecovery = false;
    if (hardSegs.length >= 2) {
      const segOrder = runningSegs.map(s => hardSegs.includes(s) ? "H" : "E");
      // Pattern like H-E-H or H-E-H-E-H indicates repeats with recovery
      const pattern = segOrder.join("");
      hasInterleavedRecovery = /H.+E.+H/.test(pattern);
    }

    // Check if segments are similar distance (repeats pattern)
    const hardDistances = hardSegs.map(s => s.distance_miles);
    const avgHardDist = hardDistances.reduce((a, b) => a + b, 0) / hardDistances.length;
    const allSimilarDist = hardDistances.every(d => Math.abs(d - avgHardDist) / avgHardDist < 0.15);

    // It's only a true sustained effort if:
    // 1. Hard segments are NOT interleaved with recovery jogs, OR
    // 2. There's only 1 hard segment, OR
    // 3. Hard segments are NOT similar distances (truly merged continuous effort)
    const isSustainedRun = sustainedEfforts.includes(dominantEffort) &&
      !hasInterleavedRecovery &&
      (hardSegs.length === 1 || !allSimilarDist);

    if (isSustainedRun) {
      // Tempo/threshold/moderate: continuous hard effort
      const tempoMiles = hardSegs.reduce((sum, s) => sum + s.distance_miles, 0);
      const tempoSecs = hardSegs.reduce((sum, s) => sum + s.duration_seconds, 0);
      const tempoPaceS = tempoMiles > 0 ? tempoSecs / tempoMiles : 0;
      const tpm = Math.floor(tempoPaceS / 60);
      const tps = Math.round(tempoPaceS % 60);
      const effortLabel = dominantEffort === "moderate" ? "steady" : dominantEffort;
      description = `${tempoMiles.toFixed(1)}mi ${effortLabel} @ ${tpm}:${String(tps).padStart(2, "0")}/mi`;
      workoutType = dominantEffort === "moderate" ? "tempo" : dominantEffort;

    } else if (hardSegs.length >= 2) {
      // Intervals/repeats: multiple hard segments
      const paces = hardSegs.map(s => {
        const parts = s.pace_per_mile.split(":").map(Number);
        return parts.length === 2 ? parts[0] * 60 + parts[1] : 0;
      });

      const fastestPace = Math.min(...paces.filter(p => p > 0));
      const slowestPace = Math.max(...paces.filter(p => p > 0));
      const fmtPace = (s: number) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;

      // Find recovery segments between hard efforts
      const recoverSegs = easySegs.filter(s =>
        s.distance_miles < 0.5 && s.distance_miles > 0);
      const avgRecoveryDist = recoverSegs.length > 0
        ? recoverSegs.reduce((sum, s) => sum + s.distance_miles, 0) / recoverSegs.length
        : 0;

      if (allSimilarDist) {
        // Repeats: "6x1mi @ 6:05-6:12 w/ 400m recovery"
        const distLabel = formatDistanceLabel(avgHardDist);
        const paceRange = fastestPace === slowestPace
          ? fmtPace(fastestPace)
          : `${fmtPace(fastestPace)}-${fmtPace(slowestPace)}`;
        const recoveryStr = avgRecoveryDist > 0
          ? ` w/ ${formatDistanceLabel(avgRecoveryDist)} recovery`
          : "";
        description = `${hardSegs.length}x${distLabel} @ ${paceRange}${recoveryStr}`;
      } else {
        // Mixed intervals: "3 hard efforts (0.5-1.0mi) @ 5:45-6:10"
        const minDist = Math.min(...hardDistances);
        const maxDist = Math.max(...hardDistances);
        const paceRange = `${fmtPace(fastestPace)}-${fmtPace(slowestPace)}`;
        description = `${hardSegs.length} hard efforts (${minDist.toFixed(1)}-${maxDist.toFixed(1)}mi) @ ${paceRange}`;
      }
      workoutType = "interval";

    } else {
      // Single hard segment
      const seg = hardSegs[0];
      description = `${seg.distance_miles.toFixed(1)}mi ${seg.effort} @ ${seg.pace_per_mile}`;
      workoutType = seg.effort;
    }

    // Build per-rep splits for hard segments, with pace zone labels when available
    const splits = hardSegs.map(s => {
      const distLabel = formatDistanceLabel(s.distance_miles);
      const zoneLabel = paceZones ? ` (${labelPaceZone(parsePace(s.pace_per_mile), paceZones)})` : "";
      return `${distLabel} @ ${s.pace_per_mile}${zoneLabel}`;
    });

    // Label the overall hard effort pace zone
    let paceZoneLabel = "";
    if (paceZones && avgFastPaceSecs > 0) {
      paceZoneLabel = labelPaceZone(avgFastPaceSecs, paceZones);
    }

    // Add warmup/cooldown context
    const warmupSeg = runningSegs.find((s, i) => s.effort === "warmup" || (easySegs.includes(s) && i === 0));
    const cooldownSeg = runningSegs.find((s, i) => s.effort === "cooldown" || (easySegs.includes(s) && i === runningSegs.length - 1));
    const wcParts: string[] = [];
    if (warmupSeg && warmupSeg.distance_miles > 0.3) wcParts.push(`${warmupSeg.distance_miles.toFixed(1)}mi warmup`);
    if (cooldownSeg && cooldownSeg !== warmupSeg && cooldownSeg.distance_miles > 0.3) wcParts.push(`${cooldownSeg.distance_miles.toFixed(1)}mi cooldown`);
    if (wcParts.length > 0) description += ` (${wcParts.join(", ")})`;

    // Use workout_notes from voice memo as the primary structured description when available
    const workoutNotesStr = log.workout_notes || "";

    sessions.push({
      date: dateStr,
      totalMiles: log.workout_distance_miles || 0,
      workoutType,
      description,
      fastPace,
      fastMiles: Math.round(fastMiles * 100) / 100,
      warmupCooldownMiles: Math.round(easyMiles * 100) / 100,
      splits,
      mood: log.mood || "",
      notes: (log.cleaned_notes || log.notes || "").slice(0, 100),
      workoutNotes: workoutNotesStr,
      paceZoneLabel,
    });
  }

  // Sort by date
  return sessions;
}

/**
 * Analyze training load patterns: volume jumps, intensity shifts, back-to-back hard days.
 * Returns a human-readable summary for the AI prompt.
 * Note: volume increases are NORMAL in training — only flag genuinely risky spikes (>30%),
 * not progressive overload.
 */
function analyzeLoadPatterns(logs: TrainingLog[]): string {
  const findings: string[] = [];
  const hardEfforts = ["interval", "tempo", "threshold", "race_pace", "speed"];

  // Group runs by week with intensity data
  const weeklyLoad: Record<number, { miles: number; hardMinutes: number; runs: number; hardDays: number; moods: string[] }> = {};
  const runDates: { date: Date; isHard: boolean; miles: number }[] = [];

  for (const log of logs) {
    if (!log.workout_distance_miles || log.workout_distance_miles <= 0) continue;
    const date = new Date(log.workout_date || log.created_at);
    const week = getWeekNumber(date);
    if (!weeklyLoad[week]) weeklyLoad[week] = { miles: 0, hardMinutes: 0, runs: 0, hardDays: 0, moods: [] };
    weeklyLoad[week].miles += log.workout_distance_miles;
    weeklyLoad[week].runs++;
    if (log.mood) weeklyLoad[week].moods.push(log.mood);

    // Calculate hard minutes from pace_segments
    let isHard = false;
    if (log.pace_segments && log.pace_segments.length > 0) {
      for (const seg of log.pace_segments) {
        if (hardEfforts.includes(seg.effort)) {
          weeklyLoad[week].hardMinutes += seg.duration_seconds / 60;
          isHard = true;
        }
      }
    } else if (log.workout_type && ["interval", "tempo", "race"].includes(log.workout_type)) {
      // Fallback: whole workout classified as hard
      weeklyLoad[week].hardMinutes += (log.workout_duration_minutes || 0);
      isHard = true;
    }
    if (isHard) weeklyLoad[week].hardDays++;
    runDates.push({ date, isHard, miles: log.workout_distance_miles });
  }

  const weeks = Object.entries(weeklyLoad)
    .map(([w, d]) => ({ week: parseInt(w), ...d }))
    .sort((a, b) => a.week - b.week);

  // 1. Volume jumps — only flag truly big spikes (>30% week-over-week), not progressive buildup
  for (let i = 1; i < weeks.length; i++) {
    const prev = weeks[i - 1];
    const curr = weeks[i];
    if (prev.miles > 5) { // only if prev week had meaningful mileage
      const pctChange = ((curr.miles - prev.miles) / prev.miles) * 100;
      if (pctChange > 30) {
        findings.push(`VOLUME SPIKE: Week ${curr.week} jumped ${Math.round(pctChange)}% (${prev.miles.toFixed(0)}→${curr.miles.toFixed(0)} miles). Progressive build is fine, but >30% in one week is aggressive.`);
      }
      // Also flag big drops that might indicate injury/burnout
      if (pctChange < -40 && prev.miles > 15) {
        findings.push(`VOLUME DROP: Week ${curr.week} dropped ${Math.round(Math.abs(pctChange))}% (${prev.miles.toFixed(0)}→${curr.miles.toFixed(0)} miles). Planned recovery or forced rest?`);
      }
    }
  }

  // 2. Intensity jumps — hard minutes surging week over week
  for (let i = 1; i < weeks.length; i++) {
    const prev = weeks[i - 1];
    const curr = weeks[i];
    if (prev.hardMinutes > 10 && curr.hardMinutes > prev.hardMinutes * 1.5) {
      findings.push(`INTENSITY SPIKE: Hard minutes jumped from ${Math.round(prev.hardMinutes)} to ${Math.round(curr.hardMinutes)} in week ${curr.week}. Volume may be similar but intensity is significantly higher.`);
    }
    // Same volume, much more intensity
    if (Math.abs(curr.miles - prev.miles) / (prev.miles || 1) < 0.15 && curr.hardMinutes > prev.hardMinutes * 1.8 && curr.hardMinutes > 20) {
      findings.push(`HIDDEN INTENSITY INCREASE: Week ${curr.week} had similar volume (${curr.miles.toFixed(0)}mi) but hard minutes nearly doubled (${Math.round(prev.hardMinutes)}→${Math.round(curr.hardMinutes)}). The body feels intensity even when mileage looks flat.`);
    }
  }

  // 3. Back-to-back hard days
  runDates.sort((a, b) => a.date.getTime() - b.date.getTime());
  let consecutiveHardDays = 0;
  for (let i = 1; i < runDates.length; i++) {
    if (!runDates[i].isHard) { consecutiveHardDays = 0; continue; }
    const gap = (runDates[i].date.getTime() - runDates[i - 1].date.getTime()) / (24 * 60 * 60 * 1000);
    if (gap <= 1.5 && runDates[i - 1].isHard) {
      consecutiveHardDays++;
      if (consecutiveHardDays >= 2) {
        const dateStr = `${runDates[i].date.getMonth() + 1}/${runDates[i].date.getDate()}`;
        findings.push(`BACK-TO-BACK HARD: ${consecutiveHardDays + 1} consecutive days with hard efforts around ${dateStr}. Recovery between hard sessions matters.`);
        consecutiveHardDays = 0; // don't double-report
      }
    } else {
      consecutiveHardDays = runDates[i].isHard ? 1 : 0;
    }
  }

  // 4. Mood + load correlation
  for (const w of weeks) {
    const tiredCount = w.moods.filter(m => m === "tired" || m === "struggling").length;
    if (tiredCount >= 2 && w.miles > 0) {
      // Check if this was also a high volume/intensity week
      const avgMiles = weeks.reduce((s, wk) => s + wk.miles, 0) / weeks.length;
      if (w.miles > avgMiles * 1.1 || w.hardMinutes > 30) {
        findings.push(`FATIGUE SIGNAL: Week ${w.week} had ${tiredCount} tired/struggling moods alongside ${w.miles.toFixed(0)} miles and ${Math.round(w.hardMinutes)} hard minutes. The body may be asking for recovery.`);
      }
    }
  }

  // 5. Week-by-week summary table for the AI
  const weekSummary = weeks.map(w => {
    const hardPct = w.miles > 0 && w.hardMinutes > 0 ? Math.round((w.hardMinutes / (w.runs * 30)) * 100) : 0; // rough estimate
    return `  Wk${w.week}: ${w.miles.toFixed(0)}mi, ${w.runs} runs, ${Math.round(w.hardMinutes)}min hard, ${w.hardDays} hard days`;
  }).join("\n");

  let section = `\nLOAD ANALYSIS (volume + intensity per week — from ALL data sources: GPS, watch, voice):\n${weekSummary}\n`;
  if (findings.length > 0) {
    section += `\nLoad flags:\n${findings.map(f => `  ⚡ ${f}`).join("\n")}\n`;
    section += `NOTE: Volume increases are normal in training. Only mention load flags if the pattern is genuinely concerning (spike without recovery, intensity creeping up unnoticed, mood declining alongside high load). Progressive overload is good — sudden jumps without adaptation time are the risk.\n`;
  }
  return section;
}

/** Convert decimal miles to a readable label: 0.5 → "800m", 0.25 → "400m", 1.0 → "1mi" */
function formatDistanceLabel(miles: number): string {
  if (Math.abs(miles - 0.25) < 0.03) return "400m";
  if (Math.abs(miles - 0.31) < 0.03) return "500m";
  if (Math.abs(miles - 0.37) < 0.03) return "600m";
  if (Math.abs(miles - 0.43) < 0.03) return "700m";
  if (Math.abs(miles - 0.50) < 0.04) return "800m";
  if (Math.abs(miles - 0.62) < 0.04) return "1K";
  if (Math.abs(miles - 0.75) < 0.04) return "1200m";
  if (Math.abs(miles - 1.0) < 0.06) return "1mi";
  if (Math.abs(miles - 1.24) < 0.06) return "2K";
  if (miles < 0.5) return `${Math.round(miles * 1609)}m`;
  return `${miles.toFixed(1)}mi`;
}

interface RunnerContext {
  planName?: string;
  raceDistance?: string;
  goalTime?: string;
  currentWeek?: number;
  totalWeeks?: number;
  predictedMarathon?: string;
  predicted5k?: string;
  predicted10k?: string;
  predictedHalf?: string;
  runDetails: string[];
  qualitySessions?: QualitySession[];
}

function buildAnalysisPrompt(
  periodLabel: string,
  stats: AggregatedStats,
  qualitative: QualitativeSummary,
  progress: PeriodProgress,
  projections: ProjectedStats,
  previousPeriodStats?: AggregatedStats,
  runnerContext?: RunnerContext,
  athleteProfileContext?: string,
  monthlyTrend?: { label: string; miles: number; runs: number; avgPace: string; qualitySessions: number }[],
  paceZones?: PaceZones | null,
  loadAnalysis?: string,
  paceRanges?: PaceZoneRanges
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

  const notesExcerpt = qualitative.allNotes.slice(0, 25).join("\n---\n");

  // Build fitness trend section
  let comparisonSection = "";
  if (monthlyTrend && monthlyTrend.length > 0) {
    const trendLines = monthlyTrend.map(m =>
      `  ${m.label}: ${m.miles}mi, ${m.runs} runs, avg ${m.avgPace}, ${m.qualitySessions} quality sessions`
    );
    // Add current period
    const currentLabel = periodLabel;
    const currentQuality = runnerContext?.qualitySessions?.length || 0;
    trendLines.push(`  ${currentLabel} (current): ${stats.totalMiles}mi, ${stats.totalRuns} runs, avg ${stats.averagePace}, ${currentQuality} quality sessions${!progress.isComplete ? " (in progress)" : ""}`);

    comparisonSection = `
FITNESS TREND (last ${monthlyTrend.length + 1} months):
${trendLines.join("\n")}`;

    if (previousPeriodStats) {
      const milesDiff = Math.round((stats.totalMiles - previousPeriodStats.totalMiles) * 10) / 10;
      comparisonSection += `\nVs last month: ${milesDiff > 0 ? "+" : ""}${milesDiff} miles (${Math.round((milesDiff / previousPeriodStats.totalMiles) * 100)}%)`;
    }
  } else if (previousPeriodStats) {
    const milesDiff = Math.round((stats.totalMiles - previousPeriodStats.totalMiles) * 10) / 10;
    comparisonSection = `
Previous Month: ${previousPeriodStats.totalMiles}mi, ${previousPeriodStats.totalRuns} runs
Change: ${milesDiff > 0 ? "+" : ""}${milesDiff} miles`;
  }

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

  // Runner context section
  let runnerSection = "";
  if (runnerContext) {
    const parts: string[] = [];
    if (runnerContext.planName) parts.push(`Training Plan: ${runnerContext.planName}`);
    if (runnerContext.raceDistance && runnerContext.goalTime) {
      parts.push(`Goal: ${runnerContext.raceDistance} in ${runnerContext.goalTime}`);
    } else if (runnerContext.raceDistance) {
      parts.push(`Training for: ${runnerContext.raceDistance}`);
    }
    if (runnerContext.currentWeek && runnerContext.totalWeeks) {
      parts.push(`Plan progress: Week ${runnerContext.currentWeek} of ${runnerContext.totalWeeks}`);
    }
    if (runnerContext.predictedMarathon || runnerContext.predicted5k) {
      const preds: string[] = [];
      if (runnerContext.predicted5k) preds.push(`5K: ${runnerContext.predicted5k}`);
      if (runnerContext.predicted10k) preds.push(`10K: ${runnerContext.predicted10k}`);
      if (runnerContext.predictedHalf) preds.push(`Half: ${runnerContext.predictedHalf}`);
      if (runnerContext.predictedMarathon) preds.push(`Marathon: ${runnerContext.predictedMarathon}`);
      parts.push(`Current fitness predictions: ${preds.join(", ")}`);
    }
    if (parts.length > 0) {
      runnerSection = `\nRUNNER CONTEXT:\n${parts.join("\n")}\n`;
    }
  }

  // Training pace reference — effort zones as RANGES (engine band output),
  // race anchors as single targets. Coach-honest framing — no midpoints.
  let paceReferenceSection = "";
  if (paceZones) {
    const fmtPace = (s: number) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}/mi`;
    const r = paceRanges ?? {};
    const effortLines: string[] = [];
    if (r.easy)      effortLines.push(`  Easy: ${fmtPace(r.easy.paceFast)}–${fmtPace(r.easy.paceSlow)} (${r.easy.effortPercent})`);
    if (r.moderate)  effortLines.push(`  Moderate: ${fmtPace(r.moderate.paceFast)}–${fmtPace(r.moderate.paceSlow)} (${r.moderate.effortPercent})`);
    if (r.steady)    effortLines.push(`  Steady: ${fmtPace(r.steady.paceFast)}–${fmtPace(r.steady.paceSlow)} (${r.steady.effortPercent})`);
    if (r.hmp) effortLines.push(`  HMP: ${fmtPace(r.hmp.paceFast)}–${fmtPace(r.hmp.paceSlow)}`);
    paceReferenceSection = `\nTRAINING PACE REFERENCE (this runner's current fitness-based paces):
${effortLines.join("\n")}
  Marathon pace: ${fmtPace(paceZones.marathon)}
  Half-marathon pace: ${fmtPace(paceZones.halfMarathon)}
  10K pace: ${fmtPace(paceZones.tenK)}
  5K pace: ${fmtPace(paceZones.fiveK)}
IMPORTANT: When discussing workouts, ALWAYS reference these pace zones (e.g. "mile repeats at 10K pace" or "tempo at half-marathon effort") rather than just stating raw paces. The runner thinks in terms of race-effort paces, not arbitrary numbers. Each quality session below includes a pace zone label — use it.\n`;
  }

  // Quality sessions — structured workouts with parsed fast segments
  let qualitySessionsSection = "";
  if (runnerContext?.qualitySessions?.length) {
    const sessionLines = runnerContext.qualitySessions.map(s => {
      const moodStr = s.mood ? ` [${s.mood}]` : "";
      const noteStr = s.notes ? ` — ${s.notes}` : "";
      const zoneStr = s.paceZoneLabel ? ` → ${s.paceZoneLabel}` : "";
      const splitsStr = s.splits.length > 1
        ? `\n    Splits: ${s.splits.join(", ")}`
        : "";
      // Include voice memo workout notes when available (structured description from runner)
      const voiceNotesStr = s.workoutNotes
        ? `\n    Runner's workout notes: ${s.workoutNotes}`
        : "";
      return `  ${s.date}: ${s.description}${zoneStr}${moodStr}${noteStr}${splitsStr}${voiceNotesStr}`;
    });

    // Pace progression for interval/tempo sessions
    const tempoSessions = runnerContext.qualitySessions.filter(s => s.workoutType === "tempo" || s.workoutType === "threshold");
    const intervalSessions = runnerContext.qualitySessions.filter(s => s.workoutType === "interval");

    let progressionNote = "";
    if (tempoSessions.length >= 2) {
      progressionNote += `\n  Tempo pace progression: ${tempoSessions.map(s => `${s.date}: ${s.fastPace}`).join(" → ")}`;
    }
    if (intervalSessions.length >= 2) {
      progressionNote += `\n  Interval pace progression: ${intervalSessions.map(s => `${s.date}: ${s.fastPace}`).join(" → ")}`;
    }

    qualitySessionsSection = `\nQUALITY SESSIONS (parsed from pace segments — these are the actual workouts):\n${sessionLines.join("\n")}${progressionNote}\n`;
  }

  // Per-run details
  const runDetailsSection = runnerContext?.runDetails?.length
    ? `\nINDIVIDUAL RUN LOG (★ = quality session detailed above):\n${runnerContext.runDetails.join("\n")}\n`
    : "";

  // Pre-compute substitution strings for the template.
  const zoneVolumeBlock = (() => {
    const zoneMilesTotal = Object.values(stats.zoneVolume).reduce((sum, d) => sum + d.miles, 0);
    const denom = zoneMilesTotal > 0 ? zoneMilesTotal : stats.totalMiles;
    return Object.entries(stats.zoneVolume).map(([zone, data]) => {
      const pct = denom > 0 ? Math.round((data.miles / denom) * 100) : 0;
      return `  ${zone.replace(/_/g, " ")}: ${data.miles}mi (${pct}%, ${data.runs} runs, avg ${data.avgPace})`;
    }).join("\n") || "  No zone data";
  })();
  const easyHardSplit = (() => {
    const zoneMilesTotal = Object.values(stats.zoneVolume).reduce((sum, d) => sum + d.miles, 0);
    const denom = zoneMilesTotal > 0 ? zoneMilesTotal : stats.totalMiles;
    const easyZones = ["easy", "recovery", "long_run"];
    const easyMiles = Object.entries(stats.zoneVolume).filter(([z]) => easyZones.includes(z)).reduce((sum, [, d]) => sum + d.miles, 0);
    const easyPct = denom > 0 ? Math.round((easyMiles / denom) * 100) : 0;
    return `Easy/hard split: ${easyPct}% easy / ${100 - easyPct}% quality (target: ~80/20)`;
  })();
  const workoutTypesLine = Object.entries(stats.workoutTypeDistribution)
    .map(([type, count]) => `${type.replace(/_/g, " ")}: ${count}`)
    .join(", ") || "none tagged";

  return loadPrompt("training-analysis.v1", {
    periodLabel,
    runnerSection,
    athleteProfileContext: athleteProfileContext || "",
    periodStatusNote,
    totalRuns: stats.totalRuns,
    totalMiles: stats.totalMiles,
    totalTimeStr: `${Math.floor(stats.totalMinutes / 60)}h ${stats.totalMinutes % 60}m`,
    averagePace: stats.averagePace,
    averageDistance: stats.averageDistance,
    longestRun: stats.longestRun,
    daysWithRuns: stats.daysWithRuns,
    restDays: stats.restDays,
    workoutTypesLine,
    zoneVolumeBlock,
    easyHardSplit,
    weeklyBreakdown,
    moodBreakdown: moodBreakdown || "No mood data",
    moodTrend: qualitative.moodTrend,
    comparisonSection,
    loadAnalysis: loadAnalysis || "",
    paceReferenceSection,
    qualitySessionsSection,
    runDetailsSection,
    notesExcerpt: notesExcerpt || "None",
    notableWorkouts: qualitative.notableWorkouts.join("\n") || "None identified",
    incompleteInstructions,
    bigPictureNote: isIncomplete ? `This period has ${progress.remainingDays} days left. Frame as "so far" and project where it's heading.` : "",
    weeklyVolumeNote: isIncomplete ? `${stats.totalMiles} miles so far, tracking toward ~${projections.projectedMiles}.` : "",
  });
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
    // Parse request body first (stream can only be read once)
    const request = (await req.json()) as AnalysisRequest;
    const { periodType, year, month } = request;

    // Verify authenticated user from JWT, fall back to userId from request body
    let userId = await getAuthenticatedUser(req);
    if (!userId && request.userId) {
      // Fallback: accept userId from request body (for expired sessions)
      // Validate the userId is a valid UUID format
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (uuidRegex.test(request.userId)) {
        userId = request.userId;
        console.log("Using fallback userId from request body:", userId);
      }
    }
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
      .eq("user_id", userId)
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
    // Quality sessions will be extracted after pace zones are computed (below)

    // Calculate projections for incomplete periods
    const projections = calculateProjections(stats, progress);

    // Fetch previous 3 months for trend comparison
    let previousPeriodStats: AggregatedStats | undefined;
    const monthlyTrend: { label: string; miles: number; runs: number; avgPace: string; qualitySessions: number }[] = [];
    if (periodType === "month" && month) {
      // Query the last 3 months in one go (90 days before period start)
      const trendStart = new Date(year, month - 4, 1); // 3 months before
      const trendEnd = new Date(start.getTime() - 1); // day before current period

      const { data: trendLogs } = await supabase
        .from("training_logs")
        .select("*")
        .eq("user_id", userId)
        .gte("created_at", trendStart.toISOString())
        .lte("created_at", trendEnd.toISOString());

      if (trendLogs && trendLogs.length > 0) {
        // Group into months
        for (let i = 1; i <= 3; i++) {
          const m = month - i <= 0 ? month - i + 12 : month - i;
          const y = month - i <= 0 ? year - 1 : year;
          const mStart = new Date(y, m - 1, 1);
          const mEnd = new Date(y, m, 0, 23, 59, 59);
          const mLogs = trendLogs.filter((log: TrainingLog) => {
            const d = new Date(log.workout_date || log.created_at);
            return d >= mStart && d <= mEnd;
          });
          if (mLogs.length > 0) {
            const mStats = aggregateStats(mLogs, mStart, mEnd);
            const mQuality = extractQualitySessions(mLogs, null);
            const monthName = mStart.toLocaleString("default", { month: "short" });
            monthlyTrend.push({
              label: `${monthName} ${y}`,
              miles: mStats.totalMiles,
              runs: mStats.totalRuns,
              avgPace: mStats.averagePace,
              qualitySessions: mQuality.length,
            });
            // Most recent previous month
            if (i === 1) previousPeriodStats = mStats;
          }
        }
        monthlyTrend.reverse(); // chronological order
      }
    }

    // Fetch cached athlete profile
    const { data: cachedAthleteProfile } = await supabase
      .from("athlete_profiles")
      .select("profile_data")
      .eq("user_id", userId)
      .single();

    let athleteProfileCtx = "";
    if (cachedAthleteProfile?.profile_data) {
      try {
        athleteProfileCtx = buildAthleteProfileContext(cachedAthleteProfile.profile_data as AthleteProfile);
      } catch (e) {
        console.error("Error building athlete profile context:", e);
      }
    }

    // Fetch runner context: training plan + fitness snapshot
    const runnerContext: RunnerContext = { runDetails: [] };

    // Active training plan
    const { data: plans } = await supabase
      .from("training_plans")
      .select("name, target_race_distance, target_time_seconds, start_date, end_date, status")
      .eq("user_id", userId)
      .eq("status", "active")
      .limit(1);

    if (plans && plans.length > 0) {
      const plan = plans[0];
      runnerContext.planName = plan.name;
      runnerContext.raceDistance = plan.target_race_distance;
      if (plan.target_time_seconds) {
        const h = Math.floor(plan.target_time_seconds / 3600);
        const m = Math.floor((plan.target_time_seconds % 3600) / 60);
        const s = plan.target_time_seconds % 60;
        runnerContext.goalTime = `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
      }
      if (plan.start_date) {
        const planStart = new Date(plan.start_date);
        const now = new Date();
        const weeksElapsed = Math.floor((now.getTime() - planStart.getTime()) / (7 * 24 * 60 * 60 * 1000)) + 1;
        const planEnd = plan.end_date ? new Date(plan.end_date) : now;
        const totalWeeks = Math.ceil((planEnd.getTime() - planStart.getTime()) / (7 * 24 * 60 * 60 * 1000)) + 1;
        runnerContext.currentWeek = Math.max(1, Math.min(weeksElapsed, totalWeeks));
        runnerContext.totalWeeks = totalWeeks;
      }
    }

    // Latest fitness snapshot
    const { data: snapshots } = await supabase
      .from("fitness_snapshots")
      .select("predicted_marathon_seconds, predicted_half_seconds, predicted_10k_seconds, predicted_5k_seconds")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1);

    let paceZones: PaceZones | null = null;
    let paceRanges: PaceZoneRanges | undefined;

    if (snapshots && snapshots.length > 0) {
      const snap = snapshots[0];
      const fmtTime = (secs: number) => {
        const h = Math.floor(secs / 3600);
        const m = Math.floor((secs % 3600) / 60);
        const s = secs % 60;
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}` : `${m}:${String(s).padStart(2, "0")}`;
      };
      if (snap.predicted_marathon_seconds) runnerContext.predictedMarathon = fmtTime(snap.predicted_marathon_seconds);
      if (snap.predicted_half_seconds) runnerContext.predictedHalf = fmtTime(snap.predicted_half_seconds);
      if (snap.predicted_10k_seconds) runnerContext.predicted10k = fmtTime(snap.predicted_10k_seconds);
      if (snap.predicted_5k_seconds) runnerContext.predicted5k = fmtTime(snap.predicted_5k_seconds);

      // Compute training pace zones for labeling workouts
      paceZones = computePaceZones(snap);
      // Range form for the prompt (effort zones rendered as bands).
      paceRanges = rangesFromSnapshot(snap);
    }

    // Extract quality sessions now that pace zones are available
    const qualitySessions = extractQualitySessions(filteredLogs, paceZones);

    // Build per-run detail lines
    const runsWithData = filteredLogs.filter((log: TrainingLog) => log.workout_distance_miles && log.workout_distance_miles > 0);
    runnerContext.runDetails = runsWithData.slice(0, 40).map((log: TrainingLog) => {
      const date = new Date(log.workout_date || log.created_at);
      const dateStr = `${date.getMonth() + 1}/${date.getDate()}`;
      const dist = log.workout_distance_miles?.toFixed(1) || "?";
      const dur = log.workout_duration_minutes || 0;
      let pace = "";
      if (dur > 0 && log.workout_distance_miles && log.workout_distance_miles > 0) {
        const paceMin = dur / log.workout_distance_miles;
        const pm = Math.floor(paceMin);
        const ps = Math.round((paceMin - pm) * 60);
        pace = ` @ ${pm}:${String(ps).padStart(2, "0")}/mi`;
      }
      const type = log.workout_type ? ` (${log.workout_type.replace(/_/g, " ")})` : "";
      const mood = log.mood ? ` [${log.mood}]` : "";
      // Prefer workout_notes (structured: "Intervals: 4x800m @ 2:50") over cleaned_notes (feelings)
      const note = (log.workout_notes || log.cleaned_notes || log.notes || "").slice(0, 120);
      const noteStr = note ? ` — ${note}` : "";

      // Mark runs that have quality session detail (parsed separately)
      // For quality runs, skip the overall pace — it's misleading (includes warmup/cooldown)
      const hasQuality = log.pace_segments && log.pace_segments.length > 1 &&
        log.pace_segments.some((s: PaceSegmentRow) =>
          ["interval", "tempo", "threshold", "race_pace", "speed"].includes(s.effort)
        );
      const qualityTag = hasQuality ? " ★" : "";
      const displayPace = hasQuality ? "" : pace;

      return `${dateStr}: ${dist}mi in ${dur}min${displayPace}${type}${mood}${qualityTag}${noteStr}`;
    });

    // Attach quality sessions to runner context
    runnerContext.qualitySessions = qualitySessions;

    // Generate AI analysis
    // Analyze load patterns from ALL data sources (GPS, watch, voice)
    const loadAnalysis = analyzeLoadPatterns(filteredLogs);

    const prompt = buildAnalysisPrompt(label, stats, qualitative, progress, projections, previousPeriodStats, runnerContext, athleteProfileCtx, monthlyTrend, paceZones, loadAnalysis, paceRanges);

    const genAI = new GoogleGenerativeAI(geminiKey);
    const modelChain = [
      { name: "gemini-2.5-flash", config: { maxOutputTokens: 4000, temperature: 0.85 } },
      { name: "gemini-2.5-pro", config: { maxOutputTokens: 4000, temperature: 0.85, thinkingConfig: { thinkingBudget: 1024 } } },
    ];

    const isRetryable = (err: unknown) => {
      const msg = err instanceof Error ? err.message : String(err);
      return /\b(429|500|502|503|504)\b|Service Unavailable|overloaded|rate/i.test(msg);
    };

    let analysis = "";
    let modelUsed = "";
    let lastErr: unknown = null;
    outer: for (const m of modelChain) {
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const model = genAI.getGenerativeModel({ model: m.name, generationConfig: m.config });
          const result = await model.generateContent(prompt);
          analysis = result.response.text();
          modelUsed = m.name;
          break outer;
        } catch (err) {
          lastErr = err;
          console.warn(`[training-analysis] ${m.name} attempt ${attempt + 1} failed:`, err instanceof Error ? err.message : err);
          if (!isRetryable(err)) break; // non-retryable: move to next model
          if (attempt === 0) await new Promise((r) => setTimeout(r, 1000));
        }
      }
    }

    if (!analysis) {
      throw lastErr instanceof Error ? lastErr : new Error("All analysis models failed");
    }

    // Log usage
    if (userId) {
      await supabase.from("usage_tracking").insert({
        user_id: userId,
        feature: "training_analysis",
        model_used: modelUsed,
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
    const message = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({ error: `Analysis failed: ${message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
