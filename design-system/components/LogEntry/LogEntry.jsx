// Post Run Drip · LogEntry — one run in the feed.
// Headline states the session (never editorialises it), prose is what the
// athlete wrote, voice is the raw transcript in italic mono.
const MOODS = {
  energized: "var(--mood-energized)",
  positive: "var(--mood-positive)",
  neutral: "var(--mood-neutral)",
  tired: "var(--mood-tired)",
  struggling: "var(--mood-struggling)",
  injured: "var(--mood-injured)",
};

export function LogEntry({ date, mood = "neutral", type, keyed = false, title, prose, voice, stats = [], byline, style }) {
  const label = {
    fontFamily: "var(--font-label)",
    fontSize: "10px",
    fontWeight: 600,
    letterSpacing: "0.16em",
    textTransform: "uppercase",
    color: "var(--ink-2)",
    whiteSpace: "nowrap",
  };
  return (
    <article style={{ padding: "20px 0", borderBottom: "1px solid var(--rule)", ...style }}>
      <div style={{ display: "flex", alignItems: "center", gap: 9, marginBottom: 9 }}>
        <span style={{ width: 7, height: 7, borderRadius: 999, flex: "none", background: MOODS[mood] || MOODS.neutral }} />
        <span style={label}>{date}</span>
        {type && (
          <span style={{ marginLeft: "auto" }}>
            <TypeChipInline keyed={keyed}>{type}</TypeChipInline>
          </span>
        )}
      </div>
      <h2 style={{ fontFamily: "var(--font-display)", fontSize: "27px", fontWeight: 700, letterSpacing: "-0.035em", lineHeight: 1.02, margin: 0 }}>
        {title}
      </h2>
      {prose && (
        <p style={{ fontFamily: "var(--font-prose)", fontSize: "18px", lineHeight: 1.45, color: "var(--ink)", margin: "10px 0 0", textWrap: "pretty" }}>
          {prose}
        </p>
      )}
      {voice && (
        <p style={{ fontFamily: "var(--font-mono)", fontStyle: "italic", fontSize: "13px", lineHeight: 1.55, color: "var(--ink)", margin: "10px 0 0" }}>
          {voice}
        </p>
      )}
      {stats.length > 0 && (
        <div style={{ display: "flex", marginTop: 13, borderTop: "1px solid var(--rule)", paddingTop: 10 }}>
          {stats.map((s, i) => (
            <div
              key={i}
              style={{
                flex: 1,
                display: "flex",
                flexDirection: "column",
                gap: 5,
                paddingRight: 10,
                borderRight: i === stats.length - 1 ? 0 : "1px solid var(--rule)",
                alignItems: i === stats.length - 1 ? "flex-end" : "flex-start",
              }}
            >
              <span style={{ ...label, fontSize: "9px", letterSpacing: "0.17em" }}>{s.label}</span>
              <span style={{ fontFamily: "var(--font-data)", fontSize: "18px", fontWeight: 600, letterSpacing: "-0.03em", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
                {s.value}
                {s.unit && <i style={{ fontStyle: "normal", fontSize: "10px", fontWeight: 500, color: "var(--ink-2)", marginLeft: 1 }}>{s.unit}</i>}
              </span>
            </div>
          ))}
        </div>
      )}
      {byline && (
        <p style={{ fontFamily: "var(--font-data)", fontSize: "10px", fontWeight: 500, letterSpacing: "0.13em", textTransform: "uppercase", color: "var(--ink-2)", margin: "11px 0 0" }}>
          {byline}
        </p>
      )}
    </article>
  );
}

function TypeChipInline({ children, keyed }) {
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
      }}
    >
      {children}
    </span>
  );
}
