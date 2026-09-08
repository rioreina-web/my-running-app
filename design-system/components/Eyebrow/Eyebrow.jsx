// Post Run Drip · Eyebrow — the tracked mono section label.
export function Eyebrow({ children, coral = false, style }) {
  return (
    <div
      style={{
        fontFamily: "var(--font-mono)",
        fontSize: "var(--t-meta)",
        fontWeight: 500,
        letterSpacing: "var(--tracking-label)",
        textTransform: "uppercase",
        color: coral ? "var(--coral)" : "var(--ink-2)",
        ...style,
      }}
    >
      {children}
    </div>
  );
}
