// Post Run Drip · iOS UI kit · Trends screen
//
// Combines AnalysisView + FitnessPredictorView into one editorial
// "Trends" surface: 5-second tiles → race predictions → fitness
// trend → load/volume → drill-downs.

const TRENDS_CSS = `
.prd-race-row {
  display: grid;
  grid-template-columns: 56px 1fr 90px 60px;
  gap: 10px;
  align-items: baseline;
  padding: 14px 0;
  border-bottom: 1px solid var(--rule);
}
.prd-race-row__dist {
  font-family: var(--font-mono);
  font-size: 11px; font-weight: 500;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-race-row__name {
  font-family: var(--font-display);
  font-size: 18px; font-weight: 700;
  color: var(--ink); letter-spacing: -0.01em;
}
.prd-race-row__time {
  font-family: var(--font-mono);
  font-size: 18px; font-weight: 600;
  color: var(--ink);
  font-variant-numeric: tabular-nums;
  text-align: right;
}
.prd-race-row__delta {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.08em;
  text-align: right;
}
.prd-race-row.is-goal .prd-race-row__name { color: var(--coral); }
.prd-race-row.is-goal .prd-race-row__time { color: var(--coral); }

.prd-pace-row {
  display: grid;
  grid-template-columns: 1fr 90px;
  gap: 10px;
  padding: 10px 0;
  border-bottom: 1px solid var(--rule);
  align-items: baseline;
}
.prd-pace-row__label {
  font-family: var(--font-display);
  font-size: 14px; font-weight: 500; color: var(--ink);
}
.prd-pace-row__hint {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3);
  display: block; margin-top: 2px;
}
.prd-pace-row__pace {
  font-family: var(--font-mono);
  font-size: 14px; font-weight: 600;
  color: var(--ink);
  font-variant-numeric: tabular-nums;
  text-align: right;
}
`;

const TrendsScreen = ({ onOpenWorkout, onOpenInjuries, onOpenHistory }) => {
  const [period, setPeriod] = React.useState("month"); // month | year | custom

  // Mock race predictions
  const races = [
    { dist: "1 MI", name: "Mile",     time: "5:12", delta: "−4s",  unit: "vs 4w ago" },
    { dist: "5K",   name: "5K",       time: "17:42", delta: "−14s", unit: "vs 4w ago" },
    { dist: "10K",  name: "10K",      time: "36:48", delta: "−26s", unit: "vs 4w ago" },
    { dist: "HALF", name: "Half",     time: "1:21:14", delta: "−54s", unit: "vs 4w ago" },
    { dist: "FULL", name: "Marathon", time: "2:48:32", delta: "GOAL 2:45", unit: "47d out", goal: true },
  ];
  const paces = [
    { label: "Easy",      hint: "Daily aerobic", pace: "8:14 / mi" },
    { label: "Marathon",  hint: "MP blocks",     pace: "6:24 / mi" },
    { label: "Threshold", hint: "Tempo / cruise",pace: "5:58 / mi" },
    { label: "10K",       hint: "Crit. velocity",pace: "5:42 / mi" },
    { label: "Interval",  hint: "VO2 max",       pace: "5:18 / mi" },
  ];

  return (
    <div className="page">
      <style>{TRENDS_CSS}</style>
      <PlateStrip surface="TRENDS · v1 ANALYTICS SURFACE" fig="FIG. 01" />

      <div className="page__body">
        {/* Period selector */}
        <div className="section section--first">
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow coral>OPENING FIGURE</Eyebrow>
            <div style={{ display: "flex", gap: 14 }}>
              {["MONTH", "YEAR", "CUSTOM"].map(p => {
                const id = p.toLowerCase();
                const active = period === id;
                return (
                  <span
                    key={p}
                    onClick={() => setPeriod(id)}
                    style={{
                      fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
                      letterSpacing: "0.12em",
                      color: active ? "var(--coral)" : "var(--ink-3)",
                      borderBottom: active ? "1.5px solid var(--coral)" : "1.5px solid transparent",
                      paddingBottom: 2, cursor: "pointer", textTransform: "uppercase",
                    }}
                  >
                    {p}
                  </span>
                );
              })}
            </div>
          </div>
          <h1 className="h-display" style={{ fontSize: 32 }}>The 5-second view.</h1>
          <div style={{
            fontFamily: "var(--font-body)", fontStyle: "italic",
            fontSize: 13, color: "var(--ink-3)",
          }}>
            — April 2026 · twelve weeks logged. —
          </div>
        </div>

        {/* Stat tiles */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginTop: 14 }}>
          <StatTile label="VOLUME · 7D" value="47.2" unit="MI" delta="+8%  vs 4-WK AVG" />
          <StatTile label="FITNESS"     value="2:48" unit="FULL" delta="−54s  vs 4 WEEKS AGO" />
          <StatTile label="LOAD · ACWR" value="1.18" unit="RATIO" delta="PRODUCTIVE" />
          <StatTile label="INJURY RISK" value="2.4"  unit="/ 10"  delta="LOW · 4W AVG 2.1" />
        </div>

        {/* Race predictions — the FitnessPredictor surface */}
        <div style={{ height: 20 }} />
        <EditorialRule />
        <Section eyebrow="FITNESS · RACE PREDICTIONS" eyebrowRight="UPDATED 2D AGO">
          <div style={{ marginTop: 6 }}>
            {races.map((r, i) => (
              <div key={i} className={"prd-race-row" + (r.goal ? " is-goal" : "")}>
                <span className="prd-race-row__dist">{r.dist}</span>
                <span className="prd-race-row__name">{r.name}</span>
                <span className="prd-race-row__time">{r.time}</span>
                <span className="prd-race-row__delta" style={{
                  color: r.goal ? "var(--coral)" : "var(--mood-energized, #2D8A4E)",
                }}>{r.delta}</span>
              </div>
            ))}
          </div>
          <div style={{
            fontFamily: "var(--font-body)", fontStyle: "italic",
            fontSize: 12, color: "var(--ink-3)", marginTop: 10,
          }}>
            — based on 87 runs across 12 weeks, anchored to your 10K from APR 6. —
          </div>
        </Section>

        {/* Training paces */}
        <Section eyebrow="TRAINING PACES · DERIVED">
          <div style={{ marginTop: 6 }}>
            {paces.map((p, i) => (
              <div key={i} className="prd-pace-row">
                <div>
                  <span className="prd-pace-row__label">{p.label}</span>
                  <span className="prd-pace-row__hint">{p.hint}</span>
                </div>
                <span className="prd-pace-row__pace">{p.pace}</span>
              </div>
            ))}
          </div>
        </Section>

        {/* Fitness trend line */}
        <Section eyebrow="FITNESS · 12-WEEK PROGRESSION" eyebrowRight="TAP TO EXPAND ↗">
          <div className="card" style={{ padding: 14, marginTop: 6 }}>
            <div style={{ display: "flex", justifyContent: "space-between" }}>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em" }}>10K EQ. PACE / MI</span>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em" }}>GOAL  5:36</span>
            </div>
            <LineChart data={[400, 396, 392, 390, 388, 384, 382, 379, 376, 372, 368, 365]} height={70} />
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 4 }}>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em" }}>JAN</span>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em" }}>APR</span>
            </div>
          </div>
        </Section>

        {/* Load × ACWR bars */}
        <Section eyebrow="LOAD · WEEKLY VOLUME × ACWR">
          <div className="card" style={{ padding: 14, marginTop: 6 }}>
            <div style={{ display: "flex", gap: 4, alignItems: "flex-end", height: 64 }}>
              {[28, 30, 26, 32, 36, 38, 34, 42, 44, 40, 46, 44, 47].map((h, i) => (
                <div key={i} style={{
                  flex: 1, height: h * 1.2,
                  background: i === 12 ? "var(--ink)" : "var(--ink-3)",
                  opacity: i === 12 ? 1 : 0.6,
                  borderRadius: "1px 1px 0 0",
                }}/>
              ))}
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 6 }}>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em" }}>13 WEEKS · MILES</span>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--coral)", letterSpacing: "0.10em" }}>ACWR 1.18</span>
            </div>
          </div>
        </Section>

        {/* Drill-downs */}
        <Section eyebrow="DRILL DOWN">
          <div style={{ display: "flex", flexDirection: "column", gap: 0 }}>
            <div onClick={onOpenWorkout} className="prd-pace-row" style={{ cursor: "pointer" }}>
              <span className="prd-pace-row__label">
                ↗ &nbsp;Open last workout
                <span className="prd-pace-row__hint">MAY 7 · 5.01 mi</span>
              </span>
              <span className="prd-pace-row__pace">7:11</span>
            </div>
            <div onClick={onOpenInjuries} className="prd-pace-row" style={{ cursor: "pointer" }}>
              <span className="prd-pace-row__label">
                ↗ &nbsp;Active aches
                <span className="prd-pace-row__hint">2 tracking</span>
              </span>
              <span className="prd-pace-row__pace" style={{ color: "var(--mood-tired, #C4873A)" }}>WATCH</span>
            </div>
            <div onClick={onOpenHistory} className="prd-pace-row" style={{ cursor: "pointer", borderBottom: 0 }}>
              <span className="prd-pace-row__label">
                ↗ &nbsp;All runs
                <span className="prd-pace-row__hint">87 entries</span>
              </span>
              <span className="prd-pace-row__pace">VIEW</span>
            </div>
          </div>
        </Section>

        <div style={{ height: 40 }} />
      </div>
    </div>
  );
};

window.TrendsScreen = TrendsScreen;
