/**
 * buildLoadMetrics — pure load/volume slice.
 *
 * Extracted verbatim from `rebuildAthleteState` (refactor §3, builder split).
 * Owns cross-source dedup of the workout set, the 7d/28d rolling volume, the
 * intensity-weighted ACWR, hard/easy session classification, session counts,
 * and the 14-day longest run.
 *
 * Behavior is identical to the previous inline block — same dedup, same
 * hard-session rules, same windows.
 */

import {
  computeWeightedLoadForLog,
  type TrainingLogRow as WeeklyAnalyticsLogRow,
  type WorkoutFeaturesRow,
} from "../weeklyAnalytics.ts";
import { dedupBySourcePriority } from "../shared/dedup.ts";
import { groupIntoSessions } from "../shared/sessions.ts";

export type WorkoutRow = Record<string, unknown>;

export interface LoadMetricsInput {
  /** Recent training logs (the 28-day `logs` set in rebuild). */
  logs: WorkoutRow[];
  /** training_log.id → workout_features row, for intensity-weighted load. */
  featuresByLogId: Map<string, WorkoutFeaturesRow>;
  /** Latest fitness snapshot (read for predicted_marathon_seconds → MP pace). */
  snapshot: Record<string, unknown> | undefined;
  sevenDaysAgo: string;
  fourteenDaysAgo: string;
  twentyEightDaysAgo: string;
}

export interface LoadMetrics {
  /** Deduped workouts with miles > 0 (consumed widely downstream). */
  workoutsWithMiles: WorkoutRow[];
  /** Deduped workouts in the trailing 7 days. */
  last7d: WorkoutRow[];
  rolling7dMiles: number;
  rolling28dMiles: number;
  weeklyAvg28d: number;
  /** Intensity-weighted acute:chronic ratio, or null when no chronic load. */
  acwr: number | null;
  hardSessions7d: number;
  easySessions7d: number;
  longestRun14d: number;
  /** Session count (deduped warmup/cool-down uploads) in the trailing 7 days. */
  runsLast7d: number;
}

export function buildLoadMetrics(input: LoadMetricsInput): LoadMetrics {
  const { logs, featuresByLogId, snapshot, sevenDaysAgo, fourteenDaysAgo, twentyEightDaysAgo } = input;

  const workoutsWithMilesRaw = logs.filter(
    (l) => (l.workout_distance_miles as number) > 0
  );

  // Cross-source dedup. The same run can appear 2-3 times in training_logs
  // (Strava auto-sync, a user voice_log, HealthKit auto_sync) with different
  // timestamps. Collapse to one per (day + distance±0.2mi + duration±2min),
  // keeping the richest source. See _shared/shared/dedup.ts.
  const workoutsWithMiles = dedupBySourcePriority(workoutsWithMilesRaw);

  const last7d = workoutsWithMiles.filter(
    (l) => new Date(l.workout_date as string) >= new Date(sevenDaysAgo)
  );
  const last28d = workoutsWithMiles.filter(
    (l) => new Date(l.workout_date as string) >= new Date(twentyEightDaysAgo)
  );
  const sessions7d = groupIntoSessions(last7d);

  const rolling7dMiles = last7d.reduce(
    (s, l) => s + ((l.workout_distance_miles as number) || 0), 0
  );
  const rolling28dMiles = last28d.reduce(
    (s, l) => s + ((l.workout_distance_miles as number) || 0), 0
  );

  const weeklyAvg28d = rolling28dMiles / 4;

  // ── Intensity-weighted load (drives ACWR) ──
  // For each training log, derive a weighted-minutes load using the
  // shared helper. Preferred path: workout_features.intensity_score ×
  // duration_seconds / 60. Fallback: workout_type × duration_minutes
  // when features haven't been computed for that log yet.
  function computeLoadForLog(l: Record<string, unknown>): number {
    return computeWeightedLoadForLog(
      l as unknown as WeeklyAnalyticsLogRow,
      featuresByLogId.get(l.id as string),
    );
  }
  const rolling7dLoad = last7d.reduce((s, l) => s + computeLoadForLog(l), 0);
  const rolling28dLoad = last28d.reduce((s, l) => s + computeLoadForLog(l), 0);
  const weeklyAvgLoad28d = rolling28dLoad / 4;
  const acwr = weeklyAvgLoad28d > 0 ? rolling7dLoad / weeklyAvgLoad28d : null;

  // Compute MP pace early — needed for hard session classification below.
  const marathonSec = (snapshot?.predicted_marathon_seconds as number) || 0;
  const earlyMpPace = marathonSec > 0 ? marathonSec / 26.2188 : 0;

  // Tempo, intervals, race, progression are always hard.
  // Long runs are hard only if 18+ miles OR run at 80%+ of MP (faster pace = lower number).
  const alwaysHardTypes = new Set(["tempo", "intervals", "interval", "race", "progression"]);
  const easyTypes = new Set(["easy", "recovery"]);

  const mpPace = earlyMpPace;
  function isHardSession(log: Record<string, unknown>): boolean {
    // Prefer the Observer-parsed type so this agrees with the block
    // quality classifier (which reads parsed_structure.type). v1 read only
    // raw workout_type here, so the two load views could disagree about the
    // same week (e.g. an auto-synced interval session with no workout_type).
    const parsed = log.parsed_structure as Record<string, unknown> | null;
    const parsedType = parsed && typeof parsed === "object"
      ? (parsed["type"] as string | undefined)
      : undefined;
    if (parsedType && ["interval", "tempo", "progression", "race"].includes(parsedType)) return true;
    if (alwaysHardTypes.has(log.workout_type as string)) return true;
    if (log.workout_type === "long_run") {
      const miles = (log.workout_distance_miles as number) || 0;
      if (miles >= 18) return true;
      // Check if pace is 80%+ of MP (i.e., pace <= MP / 0.80)
      // Since lower pace = faster, "80% of MP effort" means pace is at most MP * 1.25
      if (mpPace > 0) {
        const duration = (log.workout_duration_minutes as number) || 0;
        if (duration > 0 && miles > 0) {
          const avgPaceSec = (duration * 60) / miles;
          if (avgPaceSec <= mpPace * 1.25) return true; // faster than 80% MP effort
        }
      }
    }
    return false;
  }

  // Easy counting mirrors isHardSession's source priority: prefer the
  // Observer-parsed type, fall back to raw workout_type. Auto-synced runs
  // (Strava/HealthKit) routinely have workout_type = null but a parsed
  // structure — v1 read only workout_type here, so a fully-parsed easy week
  // reported "N hard, 0 easy" and looked falsely polarized in the prompt.
  function isEasySession(log: Record<string, unknown>): boolean {
    if (isHardSession(log)) return false;
    const parsed = log.parsed_structure as Record<string, unknown> | null;
    const parsedType = parsed && typeof parsed === "object"
      ? (parsed["type"] as string | undefined)
      : undefined;
    if (parsedType && easyTypes.has(parsedType)) return true;
    return easyTypes.has(log.workout_type as string);
  }

  const hardSessions7d = last7d.filter(isHardSession).length;
  const easySessions7d = last7d.filter(isEasySession).length;

  const last14d = workoutsWithMiles.filter(
    (l) => new Date(l.workout_date as string) >= new Date(fourteenDaysAgo)
  );
  const longestRun14d = last14d.reduce(
    (max, l) => Math.max(max, (l.workout_distance_miles as number) || 0), 0
  );

  return {
    workoutsWithMiles,
    last7d,
    rolling7dMiles,
    rolling28dMiles,
    weeklyAvg28d,
    acwr,
    hardSessions7d,
    easySessions7d,
    longestRun14d,
    runsLast7d: sessions7d.length,
  };
}
