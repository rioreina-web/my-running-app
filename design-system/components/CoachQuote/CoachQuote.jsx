// Post Run Drip · CoachQuote — the one place a coloured left border appears. Do not generalize.
export function CoachQuote({ children, style }) {
  return (
    <p
      style={{
        margin: 0,
        borderLeft: "2px solid rgba(212,89,42,0.5)",
        paddingLeft: "var(--space-3)",
        fontFamily: "var(--font-body)",
        fontStyle: "italic",
        fontSize: "var(--t-body)",
        lineHeight: 1.55,
        color: "var(--ink)",
        textWrap: "pretty",
        ...style,
      }}
    >
      {children}
    </p>
  );
}
