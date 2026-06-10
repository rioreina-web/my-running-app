// Post Run Drip · iOS UI kit · Workout detail (Plate 23 — "Pace, narrated")

const SPLITS = [
  { mi: 1, pace: "7:36", gap: "7:34", hr: 133, load: 21, w: 38 },
  { mi: 2, pace: "7:10", gap: "7:08", hr: 142, load: 22, w: 42 },
  { mi: 3, pace: "7:25", gap: "7:24", hr: 143, load: 21, w: 40 },
  { mi: 4, pace: "7:11", gap: "7:09", hr: 148, load: 23, w: 44 },
  { mi: 5, pace: "6:34", gap: "6:32", hr: 157, load: 27, w: 54, fastest: true },
  { mi: 6, pace: "7:04", gap: "7:01", hr: 155, load: 13, w: 28 },
];

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
        <Eyebrow coral>THURSDAY&nbsp;&nbsp;·&nbsp;&nbsp;LOG</Eyebrow>
        <h1 className="h-display" style={{ fontSize: 32 }}>May 7</h1>
        <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)" }}>
          5.01 mi · 35:59 · Strava
        </div>
      </div>

      <Hairline style={{ marginTop: 12 }} />

      {/* 4-stat strip */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", padding: "14px 0", borderBottom: "1px solid var(--rule)" }}>
        {[
          { l: "DISTANCE", v: "5.01", u: "mi", sub: "+55 ft elev" },
          { l: "DURATION", v: "35:59", u: "", sub: "7:11 avg" },
          { l: "GAP",      v: "7:09",  u: "/mi", sub: "grade-adjusted" },
          { l: "LOAD",     v: "127",   u: "", sub: "+12 vs typ" },
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
          { l: "CADENCE", v: "178",  u: "spm" },
          { l: "DRIFT",   v: "+2.8%", u: "Pa:Hr" },
          { l: "EF",      v: "1.05",  u: "pace/HR" },
          { l: "HR AVG",  v: "143",   u: "Z2" },
          { l: "WEEK",    v: "4 / 5", u: "24 mi" },
        ].map((s, i) => (
          <div key={i} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 3, borderRight: i < 4 ? "1px solid var(--rule)" : "0" }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>{s.l}</span>
            <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 15, color: "var(--ink)" }}>{s.v}</span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)" }}>{s.u}</span>
          </div>
        ))}
      </div>

      {/* Pace × HR chart */}
      <Section eyebrow="PACE × HR  ·  OVER DISTANCE" eyebrowRight="— PACE  · — HR">
        <div style={{ paddingTop: 4 }}>
          <svg viewBox="0 0 280 100" preserveAspectRatio="none" style={{ width: "100%", height: 100 }}>
            <line x1="0" y1="50" x2="280" y2="50" stroke="var(--rule)" strokeDasharray="3 3" />
            <text x="6" y="46" fontFamily="ui-monospace" fontSize="8" fill="var(--ink-3)">AVG 7:11</text>
            <polyline points="0,68 56,38 112,72 168,52 224,18 280,42" fill="none" stroke="var(--ink)" strokeWidth="1.5" strokeLinejoin="round" />
            <polyline points="0,76 56,50 112,46 168,42 224,32 280,42" fill="none" stroke="var(--coral)" strokeWidth="1.5" strokeLinejoin="round" />
          </svg>
          <div style={{ display: "flex", justifyContent: "space-between", marginTop: 4 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase" }}>MI 1</span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase" }}>MI 5</span>
          </div>
        </div>
        <p className="quote" style={{ fontSize: 13, marginTop: 10, marginBottom: 0 }}>
          "Mile 5 at 6:34 — fastest of the run, HR 157 (Z3). Negative split −0:30 from mile 1. Cardiac drift +2.8% — aerobic-strong."
        </p>
      </Section>

      <Hairline style={{ marginTop: 14 }} />

      {/* Splits */}
      <Section eyebrow="SPLITS" eyebrowRight="FASTEST 6:34  ·  SLOWEST 7:36">
        <table className="splits">
          <thead>
            <tr><th>MI</th><th>PACE</th><th>GAP</th><th>HR</th><th>LOAD</th></tr>
          </thead>
          <tbody>
            {SPLITS.map(s => (
              <tr key={s.mi} className={s.fastest ? "fastest" : ""}>
                <td>{s.mi}</td>
                <td>{s.pace}</td>
                <td>{s.gap}</td>
                <td>{s.hr}</td>
                <td><span className={"lbar" + (s.fastest ? " fast" : "")} style={{ width: s.w }}></span>{s.load}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>

      <Hairline style={{ marginTop: 14 }} />

      {/* HR zones */}
      <Section eyebrow="HR ZONES · TIME IN ZONE" eyebrowRight="AVG 143 · MAX 162">
        <div style={{ paddingTop: 6 }}>
          <ZoneBar zones={[
            { color: "#C0BFB9", pct: 6 },
            { color: "var(--mood-energized)", pct: 42 },
            { color: "var(--coral)", pct: 44 },
            { color: "var(--ink)", pct: 8 },
          ]} />
          <div style={{ display: "grid", gridTemplateColumns: "6% 42% 44% 8%", marginTop: 6 }}>
            {[{l:"Z1",t:"2m"},{l:"Z2",t:"14m"},{l:"Z3",t:"16m"},{l:"Z4",t:"3m"}].map((z, i) => (
              <div key={i} style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: i === 2 ? "var(--coral)" : "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>
                {z.l}<br/>{z.t}
              </div>
            ))}
          </div>
        </div>
      </Section>

      <Hairline style={{ marginTop: 16 }} />

      {/* Weekly context */}
      <Section eyebrow="WEEKLY CONTEXT">
        <p className="quote" style={{ fontSize: 13, marginTop: 4, marginBottom: 4, color: "var(--ink)" }}>
          Run 4 of 5 this week. 24.3 mi banked.
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
