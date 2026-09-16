/**
 * buildMoodTrend — pure mood-trend slice.
 *
 * Extracted verbatim from `rebuildAthleteState` (refactor §3, builder split).
 * Broader mood signal than check-ins alone: most athletes don't do dedicated
 * check-ins daily but leave mood hints in voice-log memos, so we union both,
 * sort by date desc, and compare the most-recent 3 against everything older.
 */

export interface MoodCheckIn {
  mood: string;
  created_at: string;
}

export interface MoodLogRow {
  mood?: unknown;
  workout_date?: unknown;
}

const MOOD_SCORES: Record<string, number> = {
  energized: 5, positive: 4, neutral: 3, tired: 2, struggling: 1, injured: 0,
};

/**
 * Returns "improving" | "declining" | "stable", or null when there isn't
 * enough signal.
 *
 * Requires ≥4 sources so the "older" window (everything after the most recent
 * 3) is non-empty. With exactly 3, the older slice is empty → older averages to
 * 0 → any non-zero recent mood would falsely report "improving" (three "tired"
 * entries reading as improving). Below 4, returns null.
 */
export function buildMoodTrend(
  checkIns: MoodCheckIn[],
  logs: MoodLogRow[],
): string | null {
  const moodSources: Array<{ mood: string; at: string }> = [
    ...checkIns.map((c) => ({ mood: c.mood, at: c.created_at })),
    ...logs
      .filter((l) => l.mood && l.workout_date)
      .map((l) => ({ mood: l.mood as string, at: l.workout_date as string })),
  ]
    .filter((m) => m.mood)
    .sort((a, b) => b.at.localeCompare(a.at))
    .slice(0, 8);

  if (moodSources.length < 4) return null;

  const scores = moodSources.map((m) => MOOD_SCORES[m.mood] ?? 3);
  const recent = scores.slice(0, 3).reduce((a, b) => a + b, 0) / 3;
  const olderScores = scores.slice(3);
  const older = olderScores.reduce((a, b) => a + b, 0) / olderScores.length;
  return recent > older + 0.5 ? "improving" : recent < older - 0.5 ? "declining" : "stable";
}
