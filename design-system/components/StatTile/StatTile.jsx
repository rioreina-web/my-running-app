// Post Run Drip · StatTile — tabular Inter numeral under a tracked Akzidenz label.
export function StatTile({ label, value, unit, delta, deltaTone = "pos", accent = false, coral = false, align = "start", style }) {
  const hot = accent || coral; // coral is the legacy prop name
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-1)", alignItems: align === "end" ? "flex-end" : "flex-start", ...style }}>
      <div
        style={{
          fontFamily: "var(--font-label)",
          fontSize: "10px",
          fontWeight: 600,
          letterSpacing: "0.17em",
          textTransform: "uppercase",
          color: "var(--ink-2)",
          whiteSpace: "nowrap",
        }}
      >
        {label}
      </div>
      <div
        style={{
          fontFamily: "var(--font-data)",
          fontWeight: 600,
          fontSize: "var(--t-display-m)",
          letterSpacing: "-0.03em",
          fontVariantNumeric: "tabular-nums",
          lineHeight: 1,
          whiteSpace: "nowrap",
          color: hot ? "var(--red-text)" : "var(--ink)",
        }}
      >
        {value}
        {unit && (
          <span style={{ fontFamily: "var(--font-data)", fontSize: "11px", fontWeight: 500, color: "var(--ink-2)", marginLeft: 2 }}>
            {unit}
          </span>
        )}
      </div>
      {delta && (
        <div
          style={{
            fontFamily: "var(--font-data)",
            fontSize: "10px",
            fontWeight: 500,
            letterSpacing: "0.13em",
            textTransform: "uppercase",
            whiteSpace: "nowrap",
            color: deltaTone === "neg" ? "var(--mood-injured)" : "var(--mood-positive)",
          }}
        >
          {delta}
        </div>
      )}
    </div>
  );
}
