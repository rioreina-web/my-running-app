// Post Run Drip · MoodPill — tracked uppercase pill at 12% wash. Never a full fill.
const MOODS = {
  energized: { c: "#2D8A4E", bg: "rgba(45,138,78,0.12)" },
  positive: { c: "#4A9E6B", bg: "rgba(74,158,107,0.12)" },
  neutral: { c: "#6B6560", bg: "rgba(155,149,144,0.18)" },
  tired: { c: "#C4873A", bg: "rgba(196,135,58,0.12)" },
  struggling: { c: "#C45A3A", bg: "rgba(196,90,58,0.12)" },
  injured: { c: "#B83A4A", bg: "rgba(184,58,74,0.12)" },
};

export function MoodPill({ mood = "neutral", style }) {
  const m = MOODS[mood] || MOODS.neutral;
  return (
    <span
      style={{
        display: "inline-block",
        fontFamily: "var(--font-mono)",
        fontSize: "var(--t-meta-sm)",
        fontWeight: 500,
        letterSpacing: "var(--tracking-caption)",
        textTransform: "uppercase",
        color: m.c,
        background: m.bg,
        borderRadius: "var(--r-pill)",
        padding: "4px 10px",
        ...style,
      }}
    >
      {mood}
    </span>
  );
}
