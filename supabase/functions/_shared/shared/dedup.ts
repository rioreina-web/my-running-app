/**
 * Cross-source workout dedup.
 *
 * The same run can land in `training_logs` 2-3 times — Strava auto-sync, a
 * user-created voice_log, HealthKit auto_sync — with different timestamps but
 * the same workout. Collapse to one row per (calendar day + distance within
 * 0.2mi + duration within 2min), keeping the highest-priority (richest) source.
 *
 * Extracted verbatim from `athlete-state.ts` so the "current workouts" and
 * "block history" passes share one implementation (refactor design R2).
 */

export type WorkoutRow = Record<string, unknown>;

/** Source richness: garmin/vital > strava > auto_sync > voice_log > check_in. */
export function sourcePriority(src: unknown): number {
  switch (src) {
    case "garmin": return 5;
    case "vital": return 5;
    case "strava": return 4;
    case "auto_sync": return 3;
    case "voice_log": return 2;
    case "check_in": return 1;
    default: return 0;
  }
}

/**
 * Returns a NEW array with cross-source duplicates collapsed. Order follows
 * first-seen; when a duplicate with strictly higher source priority appears it
 * REPLACES the kept row in place (identical to the original inline loops).
 */
export function dedupBySourcePriority(rows: WorkoutRow[]): WorkoutRow[] {
  const out: WorkoutRow[] = [];
  for (const row of rows) {
    const day = String(row.workout_date ?? "").slice(0, 10);
    const rDist = row.workout_distance_miles as number;
    const rDur = (row.workout_duration_minutes as number) ?? 0;
    const dupIdx = out.findIndex((existing) => {
      const eDay = String(existing.workout_date ?? "").slice(0, 10);
      if (eDay !== day) return false;
      const eDist = existing.workout_distance_miles as number;
      const eDur = (existing.workout_duration_minutes as number) ?? 0;
      return Math.abs(eDist - rDist) <= 0.2 && Math.abs(eDur - rDur) <= 2;
    });
    if (dupIdx < 0) {
      out.push(row);
    } else if (sourcePriority(row.source) > sourcePriority(out[dupIdx].source)) {
      out[dupIdx] = row;
    }
  }
  return out;
}
