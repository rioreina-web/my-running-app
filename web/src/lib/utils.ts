/** Format seconds into mm:ss or h:mm:ss */
export function formatDuration(minutes: number): string {
  const totalSeconds = Math.round(minutes * 60);
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;

  if (h > 0) {
    return `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
  }
  return `${m}:${s.toString().padStart(2, "0")}`;
}

/** Mood emoji map */
export const MOOD_CONFIG: Record<
  string,
  { emoji: string; label: string; colorClass: string }
> = {
  energized: { emoji: "⚡", label: "Energized", colorClass: "text-mood-energized" },
  positive: { emoji: "😊", label: "Positive", colorClass: "text-mood-positive" },
  neutral: { emoji: "😐", label: "Neutral", colorClass: "text-mood-neutral" },
  tired: { emoji: "😴", label: "Tired", colorClass: "text-mood-tired" },
  struggling: { emoji: "😓", label: "Struggling", colorClass: "text-mood-struggling" },
  injured: { emoji: "🤕", label: "Injured", colorClass: "text-mood-injured" },
};

/** Workout type display config */
export const WORKOUT_TYPE_CONFIG: Record<
  string,
  { label: string; colorClass: string }
> = {
  easy: { label: "Easy", colorClass: "bg-mood-energized/20 text-mood-energized" },
  tempo: { label: "Tempo", colorClass: "bg-mood-tired/20 text-mood-tired" },
  interval: { label: "Interval", colorClass: "bg-coral/20 text-coral" },
  long_run: { label: "Long", colorClass: "bg-[#4A9FFF]/20 text-[#4A9FFF]" },
  recovery: { label: "Recovery", colorClass: "bg-mood-positive/20 text-mood-positive" },
  race: { label: "Race", colorClass: "bg-coral/20 text-coral" },
  other: { label: "Run", colorClass: "bg-bg-elevated text-text-secondary" },
};

/** Parse a YYYY-MM-DD string as local midnight. Using `new Date(str)` parses
 *  as UTC, which shifts the displayed date one day earlier in any negative-
 *  offset timezone — workouts appear one day off from what the coach scheduled.
 *  Always use this when reading bare `date` columns from Postgres.
 */
export function parseLocalDate(s: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (match) {
    return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  }
  return new Date(s);
}

/** Format a date as "Mon, Feb 18" */
export function formatDate(date: string | Date): string {
  const d = typeof date === "string" ? parseLocalDate(date) : date;
  return d.toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
  });
}

/** Days between a date and now */
export function daysUntil(date: string | Date): number {
  const d = typeof date === "string" ? parseLocalDate(date) : date;
  const diff = d.getTime() - Date.now();
  return Math.ceil(diff / (1000 * 60 * 60 * 24));
}

export function daysSince(date: string | Date): number {
  const d = typeof date === "string" ? parseLocalDate(date) : date;
  const diff = Date.now() - d.getTime();
  return Math.floor(diff / (1000 * 60 * 60 * 24));
}
