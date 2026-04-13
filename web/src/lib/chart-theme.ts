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
  speed: "#6B4A8A",
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

/** Workout type colors for chart segments */
export const WORKOUT_CHART_COLORS: Record<string, string> = {
  easy: CHART_COLORS.energized,
  tempo: CHART_COLORS.primaryLight,
  interval: CHART_COLORS.primary,
  long_run: CHART_COLORS.speed,
  recovery: CHART_COLORS.positive,
  race: CHART_COLORS.primaryDark,
  other: CHART_COLORS.neutral,
};
