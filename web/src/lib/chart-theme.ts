// THE THREE-PALETTE RULE: blue = pace, warm = mood, coral = alert. The
// three palettes never share hues. Pace = single-hue blue depth ramp,
// Easy -> Mile (source of truth: RunningLog/Workouts/PaceSpectrum.swift).
export const CHART_COLORS = {
  primary: "#D4592A",
  primaryLight: "#E8764A",
  primaryDark: "#B84420",
  energized: "#2D8A4E",
  positive: "#4A9E6B",
  neutral: "#9B9590",
  tired: "#C4873A",
  struggling: "#C45A3A",
  injured: "#B83A4A",
  // Pace ramp (was a single plum `speed` token, #6B4A8A — removed).
  paceEasy: "#93B9D6",
  paceModerate: "#74A8CC",
  paceSteady: "#578FC0",
  paceMp: "#3F7CB5",
  paceHmp: "#2F66A8",
  paceLt: "#27549B",
  pace10k: "#20448B",
  pace5k: "#1A3679",
  pace3k: "#142964",
  paceMile: "#0E1D4E",
  paceFast: "#0E1D4E",
} as const;

export const CHART_AXIS = {
  fontFamily: "var(--font-mono)",
  fontSize: 10,
  fill: "#9B9590",
  tickLine: false,
  axisLine: { stroke: "#E8E4E0" },
} as const;

export const CHART_GRID = {
  strokeDasharray: "2 4",
  stroke: "#E8E4E0",
  opacity: 0.5,
  vertical: false,
} as const;

export const CHART_TOOLTIP = {
  contentStyle: {
    background: "#FFFFFF",
    border: "1px solid #E8E4E0",
    borderRadius: "8px",
    fontFamily: "var(--font-mono)",
    fontSize: "11px",
    color: "#1A1815",
    boxShadow: "0 2px 8px rgba(0,0,0,0.06)",
  },
  cursor: { stroke: "#E8E4E0", strokeDasharray: "2 4" },
} as const;

/** Mood colors for chart segments */
export const MOOD_CHART_COLORS: Record<string, string> = {
  energized: CHART_COLORS.energized,
  positive: CHART_COLORS.positive,
  neutral: CHART_COLORS.neutral,
  tired: CHART_COLORS.tired,
  struggling: CHART_COLORS.struggling,
  injured: CHART_COLORS.injured,
};

/** Workout type colors for chart segments — blue pace ramp by intensity
 *  (blue = pace, never mood-green or coral). */
export const WORKOUT_CHART_COLORS: Record<string, string> = {
  easy: CHART_COLORS.paceEasy,
  recovery: CHART_COLORS.neutral,   // warm gray — below Easy
  long_run: CHART_COLORS.paceSteady,
  tempo: CHART_COLORS.paceLt,
  interval: CHART_COLORS.pace5k,
  race: CHART_COLORS.paceMile,
  other: CHART_COLORS.neutral,
};
