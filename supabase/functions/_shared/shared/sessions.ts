/**
 * Session-level grouping.
 *
 * Multiple uploads close together in time (warmup + workout + cooldown saved
 * as separate entries, common from Strava/Garmin) belong to ONE session.
 * Gap-based clustering: two workouts on the same calendar day within 3h start-
 * to-start (or within 1.5h end-to-start using the prior duration) are the same
 * session. Total mileage is still summed per session by callers, but the
 * session COUNT reflects reality. Extracted verbatim from `athlete-state.ts`.
 */

export type WorkoutRow = Record<string, unknown>;

export function groupIntoSessions(rows: WorkoutRow[]): WorkoutRow[][] {
  if (rows.length === 0) return [];
  // Sort ascending by workout_date
  const sorted = [...rows].sort((a, b) =>
    String(a.workout_date ?? "").localeCompare(String(b.workout_date ?? ""))
  );
  const sessions: WorkoutRow[][] = [[sorted[0]]];
  for (let i = 1; i < sorted.length; i++) {
    const prev = sorted[i - 1];
    const cur = sorted[i];
    const prevTime = new Date(prev.workout_date as string).getTime();
    const curTime = new Date(cur.workout_date as string).getTime();
    const sameDay = (prev.workout_date as string)?.slice(0, 10)
      === (cur.workout_date as string)?.slice(0, 10);
    const gapHours = (curTime - prevTime) / 3600000;
    // Also consider prev duration — a 2h run ending at 2pm + next run at 3pm is same session
    const prevDurMin = (prev.workout_duration_minutes as number) ?? 0;
    const prevEndGapHours = (curTime - prevTime) / 3600000 - (prevDurMin / 60);

    if (sameDay && (gapHours <= 3 || prevEndGapHours <= 1.5)) {
      sessions[sessions.length - 1].push(cur);
    } else {
      sessions.push([cur]);
    }
  }
  return sessions;
}
