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

/**
 * Mood display config. Post Run Drip communicates mood through a tracked
 * uppercase label + a low-chroma dot/pill — never an emoji face (design-system
 * README: "No emoji. Mood is communicated through tracked uppercase pills + dot
 * color, not faces."). `colorClass` sets the text/dot color; `dot` is the raw
 * hex for when a token class isn't convenient.
 */
export const MOOD_CONFIG: Record<
  string,
  { label: string; colorClass: string; dot: string }
> = {
  energized: { label: "Energized", colorClass: "text-mood-energized", dot: "#2D8A4E" },
  positive: { label: "Positive", colorClass: "text-mood-positive", dot: "#4A9E6B" },
  neutral: { label: "Neutral", colorClass: "text-mood-neutral", dot: "#9B9590" },
  tired: { label: "Tired", colorClass: "text-mood-tired", dot: "#C4873A" },
  struggling: { label: "Struggling", colorClass: "text-mood-struggling", dot: "#C45A3A" },
  injured: { label: "Injured", colorClass: "text-mood-injured", dot: "#B83A4A" },
};

/**
 * Workout-type display config. Colors follow the three-palette rule: pace is a
 * single-hue blue depth ramp (source of truth RunningLog/Workouts/
 * PaceSpectrum.swift), warm gray is neutral, coral is reserved for alerts. No
 * mood hues (amber/green) leak into pace here.
 */
export const WORKOUT_TYPE_CONFIG: Record<
  string,
  { label: string; colorClass: string }
> = {
  easy: { label: "Easy", colorClass: "bg-pace-easy/15 text-pace-easy-text" },
  steady: { label: "Steady", colorClass: "bg-pace-steady/15 text-pace-steady" },
  tempo: { label: "Tempo", colorClass: "bg-pace-lt/12 text-pace-lt" },
  interval: { label: "Interval", colorClass: "bg-pace-5k/12 text-pace-5k" },
  fartlek: { label: "Fartlek", colorClass: "bg-pace-moderate/12 text-pace-moderate" },
  long_run: { label: "Long", colorClass: "bg-pace-steady/15 text-pace-steady" },
  long_wo: { label: "Long WO", colorClass: "bg-pace-hmp/12 text-pace-hmp" },
  recovery: { label: "Recovery", colorClass: "bg-text-tertiary/12 text-text-secondary" },
  race: { label: "Race", colorClass: "bg-pace-mile/12 text-pace-mile" },
  other: { label: "Run", colorClass: "bg-bg-elevated text-text-secondary" },
};

/** Namespace prefix for coach-defined custom workout types. A workout whose
 *  `workout_type` is `custom:<slug>` renders from the coach's saved label
 *  library (coach_workout_labels); this prefix is the only escape hatch past
 *  the built-in vocabulary CHECK constraint. */
export const CUSTOM_TYPE_PREFIX = "custom:";

/** Slugify a coach's custom label into a stable machine key
 *  ("Hill repeats" → "hill-repeats"). */
export function slugifyWorkoutLabel(name: string): string {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

/** Readable fallback for a `custom:<slug>` type when the coach's label row
 *  isn't available in the current context ("custom:hill-repeats" → "Hill
 *  Repeats"). Returns null for built-in types. */
export function prettyCustomWorkoutType(workoutType: string): string | null {
  if (!workoutType.startsWith(CUSTOM_TYPE_PREFIX)) return null;
  return workoutType
    .slice(CUSTOM_TYPE_PREFIX.length)
    .split(/[-_]/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

/** Resolve a workout_type to a badge {label, colorClass}. Handles built-ins
 *  via WORKOUT_TYPE_CONFIG and degrades `custom:<slug>` to a readable label
 *  with a neutral chip, so a raw "custom:" prefix never leaks into the UI. */
export function workoutTypeBadge(
  workoutType: string
): { label: string; colorClass: string } {
  const custom = prettyCustomWorkoutType(workoutType);
  if (custom) {
    return { label: custom, colorClass: "bg-bg-elevated text-text-secondary" };
  }
  return WORKOUT_TYPE_CONFIG[workoutType] ?? WORKOUT_TYPE_CONFIG.other;
}

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
