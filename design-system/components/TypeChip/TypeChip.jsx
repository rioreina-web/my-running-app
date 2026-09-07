// Post Run Drip · TypeChip — what kind of session this was.
// Keyed work is a solid blue chip; everything easy is a hairline outline.
// Never more than one keyed chip in a row of entries.
export function TypeChip({ children, keyed = false, style }) {
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        fontFamily: "var(--font-label)",
        fontSize: "9px",
        fontWeight: 700,
        letterSpacing: "0.16em",
        textTransform: "uppercase",
        whiteSpace: "nowrap",
        padding: "4px 7px 5px",
        color: keyed ? "#fff" : "var(--ink-2)",
        background: keyed ? "var(--session)" : "transparent",
        border: keyed ? "1px solid var(--session)" : "1px solid var(--rule)",
        ...style,
      }}
    >
      {children}
    </span>
  );
}
