// Post Run Drip · iOS UI kit · Workout detail (Plate 23 — "Pace, narrated")
// Telemetry section is the interactive analytical charts (Combined / Stacked /
// Splits), driven by the shared run in charts-data.jsx — drag to scrub.

const WorkoutDetailScreen = ({ onClose }) => (
  <div className="page">
    <PlateStrip surface="WORKOUT DETAIL · SHARPENED" fig="FIG. 23" />
    <div className="page__body">
      <div style={{ display: "flex", justifyContent: "space-between", paddingTop: 0 }}>
        <a className="link" onClick={onClose} style={{ fontSize: 13 }}>Back</a>
        <a className="link" style={{ fontSize: 13 }}>Share</a>
      </div>

      {/* Date header */}
      <div className="section section--first" style={{ marginTop: 14 }}>
        <Eyebrow coral>TUESDAY&nbsp;&nbsp;·&nbsp;&nbsp;LOG</Eyebrow>
        <h1 className="h-display" style={{ fontSize: 32 }}>May 5</h1>
        <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)" }}>
          6.9 mi · 51:06 · Strava
        </div>
      </div>

      <Hairline style={{ marginTop: 12 }} />

      {/* 4-stat strip */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", padding: "14px 0", borderBottom: "1px solid var(--rule)" }}>
        {[
          { l: "DISTANCE", v: "6.9",  u: "mi", sub: "+141 ft elev" },
          { l: "DURATION", v: "51:06", u: "", sub: "7:24 avg" },
          { l: "GAP",      v: "7:18",  u: "/mi", sub: "grade-adjusted" },
          { l: "LOAD",     v: "168",   u: "", sub: "+18 vs typ" },
        ].map((s, i) => (
          <div key={i} style={{ borderRight: i < 3 ? "1px solid var(--rule)" : "0", display: "flex", flexDirection: "column", gap: 4, paddingLeft: i === 0 ? 0 : 14, paddingRight: 14 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>{s.l}</span>
            <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 22, color: "var(--ink)", fontVariantNumeric: "tabular-nums" }}>
              {s.v}<span style={{ fontSize: 10, color: "var(--ink-2)", marginLeft: 2 }}>{s.u}</span>
            </span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.05em" }}>{s.sub}</span>
          </div>
        ))}
      </div>

      {/* secondary strip */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", padding: "12px 0", borderBottom: "1px solid var(--rule)" }}>
        {[
          { l: "CADENCE", v: "176",  u: "spm" },
          { l: "DRIFT",   v: "+3.1%", u: "Pa:Hr" },
          { l: "EF",      v: "1.03",  u: "pace/HR" },
          { l: "HR AVG",  v: "143",   u: "Z3" },
          { l: "WEEK",    v: "4 / 5", u: "28 mi" },
        ].map((s, i) => (
          <div key={i} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 3, borderRight: i < 4 ? "1px solid var(--rule)" : "0" }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>{s.l}</span>
            <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 15, color: "var(--ink)" }}>{s.v}</span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)" }}>{s.u}</span>
          </div>
        ))}
      </div>

      {/* Interactive telemetry — Combined / Stacked / Splits, drag to scrub */}
      <Section eyebrow="TELEMETRY  ·  PACE × HR × ELEVATION" eyebrowRight="DRAG TO SCRUB">
        <div style={{ paddingTop: 4 }}>
          <WorkoutTelemetry initial="combined" />
        </div>
        <p className="quote" style={{ fontSize: 13, marginTop: 12, marginBottom: 0 }}>
          "Climbed early, came home fast. Mile 6 closing surge under threshold — HR drift held to +3.1%. Aerobic-strong."
        </p>
      </Section>

      <Hairline style={{ marginTop: 16 }} />

      {/* Weekly context */}
      <Section eyebrow="WEEKLY CONTEXT">
        <p className="quote" style={{ fontSize: 13, marginTop: 4, marginBottom: 4, color: "var(--ink)" }}>
          Run 4 of 5 this week. 28 mi banked.
        </p>
        <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12, color: "var(--ink-3)", margin: 0 }}>
          This run added +9% to your chronic load — bringing ACWR to 1.18.
        </p>
      </Section>

      <div style={{ height: 24 }} />
    </div>
  </div>
);

window.WorkoutDetailScreen = WorkoutDetailScreen;
