// Shared run-math helpers for the athlete surfaces (Trends, Train).
// Pure functions only — safe to import from server and client components.

// A voice memo can carry the distance of the run it's about. When that run
// also exists as its own row (Strava / auto-sync), summing both
// double-counts the mileage. `dedupeRuns` keeps each run once: it drops a
// voice_log / check_in row from mileage math when a same-day non-memo run
// is within ~0.3 mi. A standalone memo (no matching run) still counts.
export type MileRow = {
  workout_date: string | null;
  created_at: string;
  workout_distance_miles: number | null;
  source: string | null;
};

export function runDayKey(l: MileRow): number {
  const d = new Date(l.workout_date || l.created_at);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export function dedupeRuns<T extends MileRow>(rows: T[]): T[] {
  const withDist = rows.filter((l) => (l.workout_distance_miles || 0) > 0);
  return withDist.filter((l) => {
    if (l.source !== "voice_log" && l.source !== "check_in") return true;
    const day = runDayKey(l);
    const miles = l.workout_distance_miles!;
    const runAlreadyCounted = withDist.some(
      (r) =>
        r !== l &&
        r.source !== "voice_log" &&
        r.source !== "check_in" &&
        runDayKey(r) === day &&
        Math.abs((r.workout_distance_miles || 0) - miles) <= 0.3
    );
    return !runAlreadyCounted;
  });
}

/** Parse "8:32" (min:sec per mile) → seconds per mile. */
export function paceStrToSec(s: string | null): number | null {
  if (!s) return null;
  const m = s.match(/(\d+):(\d{2})/);
  if (!m) return null;
  return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
}

/** Best-available pace for a run in seconds per mile, or null. */
export function runPaceSec(l: {
  workout_pace_per_mile: string | null;
  workout_duration_minutes: number | null;
  workout_distance_miles: number | null;
}): number | null {
  return (
    paceStrToSec(l.workout_pace_per_mile) ??
    (l.workout_duration_minutes && l.workout_distance_miles
      ? (l.workout_duration_minutes * 60) / l.workout_distance_miles
      : null)
  );
}

/** Local YYYY-MM-DD (timezone-safe — never toISOString for calendar days). */
export function localDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
