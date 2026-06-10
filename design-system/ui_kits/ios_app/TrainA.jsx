// Post Run Drip · iOS UI kit · Training — Option A · Strip back
// Same architecture as the current TrainingScreen, but trimmed for restraint:
//   • Race plan link killed (the goal row carries it)
//   • Range column killed from Pace Mix (bucket label implies the range)
//   • Recent log removed entirely — that surface belongs to Runs
//   • One coral per cluster: header has "Sub-3:10" only; week strip has the
//     today dot only; weekly mileage chart is ink-only; pace mix highlights
//     only THRESHOLD; no other coral on the screen.
//   • Result: 4 sections + breathing room.

const TRAIN_A_DAYS = [
  { name: "Mon", miles: 6,  type: "Easy",  state: "done" },
  { name: "Tue", miles: 8,  type: "Tempo", state: "done" },
  { name: "Wed", miles: 11, type: "MP",    state: "today" },
  { name: "Thu", miles: "—", type: "Rest", state: "rest" },
  { name: "Fri", miles: 6,  type: "Easy",  state: "future" },
  { name: "Sat", miles: 20, type: "Long",  state: "future" },
  { name: "Sun", miles: "—", type: "Rest", state: "rest" },
];

const TRAIN_A_PACE = [
  { lbl: "EASY",      miles: "28.3", pct: 60, color: "var(--ink-2)"  },
  { lbl: "STEADY",    miles: "11.4", pct: 24, color: "var(--ink-2)"  },
  { lbl: "THRESHOLD", miles:  "4.2", pct:  9, color: "var(--coral)"  },
  { lbl: "VO2",       miles:  "2.1", pct:  4, color: "var(--ink-2)"  },
  { lbl: "RACE",      miles:  "1.2", pct:  3, color: "var(--ink-2)"  },
];

const TrainA = () => (
  <div className="page">
    <PlateStrip surface="TRAINING · RE-TUNING" fig="FIG. 6" />
    <div className="page__body">
      {/* Header — quieter goal line */}
      <div className="section section--first">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <Eyebrow>TRAINING&nbsp;&nbsp;·&nbsp;&nbsp;WEEK 09 OF 16</Eyebrow>
          <Eyebrow>MON&nbsp;·&nbsp;APR 27</Eyebrow>
        </div>
        <h1 className="h-display" style={{ fontSize: 34, marginTop: 6 }}>Marathon block.</h1>
        <p style={{
          fontFamily: "var(--font-body)", fontStyle: "italic",
          fontSize: 14, color: "var(--ink-2)", margin: "8px 0 0 0", lineHeight: 1.45,
        }}>
          <span style={{ color: "var(--coral)", fontStyle: "normal", fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 13, letterSpacing: "0.04em" }}>Sub-3:10</span>
          <span> · May 18 · 47 days out.</span>
        </p>
      </div>

      <div style={{ height: 28 }} />

      {/* Week strip — single coral element: today's dot */}
      <Section eyebrow="THIS WEEK">
        <div className="wkstrip">
          {TRAIN_A_DAYS.map(d => (
            <div
              key={d.name}
              className={"wkday" + (d.state === "today" ? " is-today" : d.state === "done" ? " is-done" : d.state === "rest" ? " is-rest" : "")}
            >
              <span className="wkname">{d.name}</span>
              <span className="wkdot"></span>
              <span className="wkmiles">{d.miles}</span>
              <span className="wktype">{d.type}</span>
            </div>
          ))}
        </div>
      </Section>

      <div style={{ height: 28 }} />

      {/* Weekly mileage — bigger number, no coral. The +8% is in the eyebrow line. */}
      <Section eyebrow="WEEKLY MILEAGE" eyebrowRight="+8% VS PRIOR">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", marginTop: 6 }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: 6 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 44, color: "var(--ink)", lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>47.2</span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-2)" }}>MI</span>
          </div>
          <div style={{ display: "flex", gap: 5, alignItems: "flex-end", height: 36 }}>
            {[24, 28, 26, 36].map((h, i) => (
              <div key={i} style={{ width: 16, height: h, background: "var(--ink-3)", opacity: i === 3 ? 0.85 : 0.35 }}></div>
            ))}
          </div>
        </div>
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase", marginTop: 8 }}>
          LAST 4 WEEKS · CURRENT FILLED
        </div>
      </Section>

      <div style={{ height: 30 }} />

      {/* Pace mix — three columns: label · bar · miles. Range column dropped. */}
      <Section eyebrow="PACE MIX · WEEK">
        <div style={{ display: "flex", flexDirection: "column", gap: 12, paddingTop: 8 }}>
          {TRAIN_A_PACE.map(b => (
            <div key={b.lbl} style={{ display: "grid", gridTemplateColumns: "98px 1fr 60px", alignItems: "center", gap: 12 }}>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.12em" }}>{b.lbl}</span>
              <div style={{ background: "var(--paper-deep)", height: 7, borderRadius: 999, overflow: "hidden" }}>
                <div style={{ background: b.color, height: "100%", width: (b.pct * 1.4) + "%" }}></div>
              </div>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--ink)", fontWeight: 600, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>
                {b.miles}<span style={{ color: "var(--ink-2)", marginLeft: 2, fontSize: 10, fontWeight: 500 }}>mi</span>
              </span>
            </div>
          ))}
        </div>
      </Section>

      <div style={{ height: 26 }} />

      {/* A single quiet link out, in case the runner wants the long version. */}
      <p style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase", textAlign: "center" }}>
        recent runs in <span style={{ color: "var(--ink-2)", borderBottom: "1px solid var(--rule)", paddingBottom: 1, cursor: "pointer" }}>Runs ↗</span>
      </p>

      <div style={{ height: 24 }} />
    </div>
  </div>
);

window.TrainA = TrainA;
