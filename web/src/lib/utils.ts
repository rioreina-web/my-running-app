import { displayWorkoutType, normalizeWorkoutType } from "@/lib/workout-label";

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
// Colour only. LABELS LIVE IN lib/workout-label.ts — this map used to carry
// its own `label` field, which is how the web ended up rendering "Tempo" and
// "Interval" months after the taxonomy retired them. Use workoutTypeConfig()
// to get both halves; the label always comes from the canonical mapper.
//
// Three-palette rule: intensity reads as the blue pace ramp, rest/recovery as
// neutral ink. Coral is alert-only and never a workout fill.
const WORKOUT_TYPE_COLOR: Record<string, string> = {
  // Effort
  easy: "bg-pace-easy/15 text-pace-easy-text",
  moderate: "bg-pace-moderate/12 text-pace-moderate",
  steady: "bg-pace-steady/15 text-pace-steady",
  recovery: "bg-text-tertiary/12 text-text-secondary",
  // Structural
  long_run: "bg-pace-steady/15 text-pace-steady",
  long_wo: "bg-pace-hmp/12 text-pace-hmp",
  cross_train: "bg-text-tertiary/12 text-text-secondary",
  strength: "bg-text-tertiary/12 text-text-secondary",
  rest: "bg-text-tertiary/12 text-text-secondary",
  race: "bg-pace-mile/12 text-pace-mile",
  // Session
  threshold: "bg-pace-lt/12 text-pace-lt",
  intervals: "bg-pace-5k/12 text-pace-5k",
  fartlek: "bg-pace-moderate/12 text-pace-moderate",
  progression: "bg-pace-hmp/12 text-pace-hmp",
  // Legacy race-pace zones still stored as types on old rows.
  mp: "bg-pace-mp/12 text-pace-mp",
  hmp: "bg-pace-hmp/12 text-pace-hmp",
  lt: "bg-pace-lt/12 text-pace-lt",
  "10k": "bg-pace-10k/12 text-pace-10k",
  "5k": "bg-pace-5k/12 text-pace-5k",
  "3k": "bg-pace-3k/12 text-pace-3k",
  mile: "bg-pace-mile/12 text-pace-mile",
  hills: "bg-pace-hmp/12 text-pace-hmp",
  strides: "bg-pace-5k/12 text-pace-5k",
  other: "bg-bg-elevated text-text-secondary",
};

/** Label + colour for a stored `workout_type`. The label is always the
 *  canonical one; legacy spellings (`tempo`, `interval`) fold first so they
 *  pick up the right colour too. */
export function workoutTypeConfig(
  workoutType: string | null | undefined,
): { label: string; colorClass: string } {
  const key = normalizeWorkoutType(workoutType);
  return {
    label: displayWorkoutType(workoutType),
    colorClass: (key && WORKOUT_TYPE_COLOR[key]) || WORKOUT_TYPE_COLOR.other,
  };
}

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

/** Resolve a workout_type to a badge {label, colorClass}. Built-ins go through
 *  workoutTypeConfig (canonical label + colour); `custom:<slug>` degrades to a
 *  readable label with a neutral chip, so a raw "custom:" prefix never leaks
 *  into the UI. */
export function workoutTypeBadge(
  workoutType: string
): { label: string; colorClass: string } {
  const custom = prettyCustomWorkoutType(workoutType);
  if (custom) {
    return { label: custom, colorClass: "bg-bg-elevated text-text-secondary" };
  }
  return workoutTypeConfig(workoutType);
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
