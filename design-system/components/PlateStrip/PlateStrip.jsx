// Post Run Drip · PlateStrip — the plate header at the top of every editorial surface.
export function PlateStrip({ surface = "TRENDS · v1 ANALYTICS SURFACE", fig, right, style }) {
  const base = {
    fontFamily: "var(--font-mono)",
    fontSize: "var(--t-meta)",
    fontWeight: 500,
    letterSpacing: "var(--tracking-meta)",
    textTransform: "uppercase",
    color: "var(--ink-2)",
  };
  return (
    <div style={{ ...base, display: "flex", justifyContent: "space-between", alignItems: "flex-start", ...style }}>
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        <span style={{ color: "var(--ink)" }}>Running Log</span>
        <span>— {surface}</span>
      </div>
      {(fig || right) && (
        <div style={{ display: "flex", flexDirection: "column", gap: 2, textAlign: "right" }}>
          {fig && <span style={{ color: "var(--ink)" }}>{fig}</span>}
          {right && <span>{right}</span>}
        </div>
      )}
    </div>
  );
}
