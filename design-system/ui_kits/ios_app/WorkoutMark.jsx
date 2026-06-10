// Post Run Drip · iOS UI kit · Workout marks
// Small geometric SVG marks for each workout type — designed to feel
// like editorial typographic glyphs, not iOS-style icons.
// All 14×14, 1.5px stroke, currentColor, no fills (matching the brand
// icon system: stroked, not filled).
//
// Color is set by parent (uses currentColor). Use the type's accent
// color when the workout is the focus, ink-2 otherwise.

const WORKOUT_MARK_COLORS = {
  easy:        "#4A9E6B",
  tempo:       "#E8764A",
  intervals:   "#D4592A",
  threshold:   "#D4592A",
  mp:          "#D4592A",
  quality:     "#D4592A",
  long_run:    "#2D8A4E",
  long:        "#2D8A4E",
  recovery:    "#4A9E6B",
  race:        "#D4592A",
  progression: "#E8764A",
  strides:     "#D4592A",
  rest:        "#9B9590",
};

const MARK_PATHS = {
  // Three horizontal flowing lines — easy / calm
  easy: (
    <g>
      <path d="M2.5 4.5 H 9.5" />
      <path d="M2 7 H 12" />
      <path d="M3.5 9.5 H 9" />
    </g>
  ),
  // Flame — tempo / sustained heat
  tempo: (
    <path d="M5.5 12 C 4 10, 4 7.5, 6 5.5 C 6 7, 7 7, 7 6 C 7 4.5, 7.5 3, 8.5 2 C 8.5 4, 10 5, 10 8 C 10 10, 8.5 12, 7 12 C 6 12, 5.5 12, 5.5 12 Z" />
  ),
  // Lightning bolt — intervals / threshold / MP / quality
  quality: (
    <path d="M8 1.5 L 4 7.5 H 7 L 6 12.5 L 10 6.5 H 7 Z" />
  ),
  // Open arc with end-dot — long run / arc of distance
  long: (
    <g>
      <path d="M1.5 11 C 1.5 4, 12.5 4, 12.5 11" />
      <circle cx="12.5" cy="11" r="1.1" fill="currentColor" stroke="none" />
    </g>
  ),
  // Crescent — recovery / quiet
  recovery: (
    <path d="M10.5 2.5 A 5 5 0 1 0 10.5 11.5 A 3.8 3.8 0 0 1 10.5 2.5 Z" />
  ),
  // Pennant flag — race
  race: (
    <g>
      <path d="M3 12.5 V 1.5" />
      <path d="M3 1.5 L 10.5 3.5 L 7.5 5.5 L 10.5 7.5 L 3 7.5" />
    </g>
  ),
  // Rising steps — progression
  progression: (
    <path d="M1.5 11 H 4.5 V 8 H 7.5 V 5 H 10.5 V 2" />
  ),
  // Three verticals — strides (short bursts)
  strides: (
    <g>
      <path d="M3 10 V 4" />
      <path d="M7 11 V 3" />
      <path d="M11 10 V 4" />
    </g>
  ),
  // Pause inside circle — rest
  rest: (
    <g>
      <circle cx="7" cy="7" r="4.8" />
      <path d="M4.8 7 H 9.2" />
    </g>
  ),
};

const TYPE_TO_MARK = {
  easy:        "easy",
  recovery:    "recovery",
  tempo:       "tempo",
  intervals:   "quality",
  threshold:   "quality",
  mp:          "quality",
  quality:     "quality",
  long_run:    "long",
  long:        "long",
  race:        "race",
  progression: "progression",
  strides:     "strides",
  rest:        "rest",
};

const WorkoutMark = ({ type, size = 14, color, style }) => {
  const key = TYPE_TO_MARK[String(type || "").toLowerCase()] || "easy";
  const path = MARK_PATHS[key];
  const c = color || "currentColor";
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 14 14"
      fill="none"
      stroke={c}
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      style={{ flexShrink: 0, ...(style || {}) }}
    >
      {path}
    </svg>
  );
};

const workoutColor = (type) => WORKOUT_MARK_COLORS[String(type || "").toLowerCase()] || "var(--ink-2)";

window.WorkoutMark = WorkoutMark;
window.workoutColor = workoutColor;
window.WORKOUT_MARK_COLORS = WORKOUT_MARK_COLORS;
