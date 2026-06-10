// Post Run Drip · iOS UI kit · Training screen (Plate 06)

const TRAINING_DAYS = [
  { name: "Mon", miles: 6,  type: "Easy",  state: "done" },
  { name: "Tue", miles: 8,  type: "Tempo", state: "done" },
  { name: "Wed", miles: 11, type: "MP",    state: "today" },
  { name: "Thu", miles: "—", type: "Rest", state: "rest" },
  { name: "Fri", miles: 6,  type: "Easy",  state: "future" },
  { name: "Sat", miles: 20, type: "Long",  state: "future" },
  { name: "Sun", miles: "—", type: "Rest", state: "rest" },
];

const PACE_BUCKETS = [
  { lbl: "EASY",      range: "6:30 – 7:30 / mi", miles: "28.3", pct: 60, color: "var(--mood-energized)" },
  { lbl: "STEADY",    range: "6:00 – 6:30 / mi", miles: "11.4", pct: 24, color: "var(--ink-2)" },
  { lbl: "THRESHOLD", range: "5:50 – 6:00 / mi", miles: "4.2",  pct:  9, color: "var(--coral)" },
  { lbl: "VO2",       range: "5:25 – 5:40 / mi", miles: "2.1",  pct:  4, color: "var(--ink)" },
  { lbl: "RACE",      range: "5:42 / mi",         miles: "1.2",  pct:  3, color: "var(--ink)" },
];

const RECENT_LOGS = [
  { date: "APR 26", type: "LONG RUN", miles: "18 MI",  pace: "2:34",  quote: "Felt strong through 14, started to fade on the hills…", mood: "positive" },
  { date: "APR 24", type: "TEMPO",    miles: "8 MI",   pace: "1:12",  quote: "Hit the prescribed paces cleanly. Slight headwind on the way…", mood: "energized" },
  { date: "APR 22", type: "EASY",     miles: "6 MI",   pace: null,    text: "TEXT ONLY", quote: "Legs heavy, took it easy and kept HR low. Tomorrow should be…", mood: "tired" },
];

const TrainingScreen = () => (
  <div className="page">
    <PlateStrip surface="TRAINING · RE-TUNING" fig="FIG. 6" />
    <div className="page__body">
      {/* Header */}
      <div className="section section--first">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <Eyebrow coral>TRAINING&nbsp;&nbsp;·&nbsp;&nbsp;WEEK 09 OF 16</Eyebrow>
          <Eyebrow>MON&nbsp;·&nbsp;APR 27</Eyebrow>
        </div>
        <h1 className="h-display" style={{ fontSize: 32 }}>Marathon block</h1>
      </div>

      <div style={{ display: "flex", alignItems: "baseline", gap: 12, marginTop: 14 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--coral)", letterSpacing: "0.10em", textTransform: "uppercase" }}>GOAL</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--ink)", fontWeight: 600 }}>Sub-3:10</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.05em", textTransform: "uppercase" }}>· May 18 · 47 DAYS OUT</span>
        <span className="link" style={{ marginLeft: "auto", fontSize: 12 }}>Edit ↗</span>
      </div>

      <Hairline style={{ marginTop: 14 }} />

      {/* Weekly mileage */}
      <Section eyebrow="WEEKLY MILEAGE">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", marginTop: 4 }}>
          <div>
            <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 36, color: "var(--ink)" }}>47.2</span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-2)", marginLeft: 4 }}>MILES</span>
          </div>
          <div style={{ display: "flex", gap: 4, alignItems: "flex-end", height: 38 }}>
            <div style={{ width: 16, height: 24, background: "var(--ink-3)", opacity: 0.6 }}></div>
            <div style={{ width: 16, height: 28, background: "var(--ink-3)", opacity: 0.6 }}></div>
            <div style={{ width: 16, height: 26, background: "var(--ink-3)", opacity: 0.6 }}></div>
            <div style={{ width: 16, height: 36, background: "var(--coral)" }}></div>
          </div>
        </div>
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.08em", textTransform: "uppercase", marginTop: 6 }}>
          <span style={{ color: "var(--mood-energized)" }}>+8%</span>&nbsp;&nbsp;VS LAST WEEK&nbsp;&nbsp;·&nbsp;&nbsp;188 MI THIS MONTH&nbsp;&nbsp;·&nbsp;&nbsp;LAST 4 WEEKS
        </div>
      </Section>

      <div style={{ height: 16 }} />

      {/* Coach's plan week strip */}
      <Section eyebrow="COACH'S PLAN · WEEK 09" eyebrowRight="4 OF 7 · 27 / 47 MI">
        <div className="wkstrip">
          {TRAINING_DAYS.map(d => (
            <div key={d.name} className={"wkday" + (d.state === "today" ? " is-today" : d.state === "done" ? " is-done" : d.state === "rest" ? " is-rest" : "")}>
              <span className="wkname">{d.name}</span>
              <span className="wkdot"></span>
              <span className="wkmiles">{d.miles}</span>
              <span className="wktype">{d.type}</span>
            </div>
          ))}
        </div>
      </Section>

      <div style={{ height: 18 }} />

      {/* Pace & volume */}
      <Section eyebrow="PACE  &  VOLUME" eyebrowRight="WEEK">
        <div style={{ display: "flex", flexDirection: "column", gap: 8, paddingTop: 4 }}>
          {PACE_BUCKETS.map(b => (
            <div key={b.lbl} style={{ display: "grid", gridTemplateColumns: "70px 1fr 50px 30px", alignItems: "center", gap: 10 }}>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em" }}>{b.lbl}</span>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)" }}>{b.range}</span>
              <div style={{ background: "var(--paper-deep)", height: 7, borderRadius: 999, overflow: "hidden", position: "relative" }}>
                <div style={{ background: b.color, height: "100%", width: (b.pct * 1.4) + "%" }}></div>
              </div>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink)", fontWeight: 600, textAlign: "right" }}>{b.miles}<span style={{ color: "var(--ink-2)", marginLeft: 2 }}>mi</span></span>
            </div>
          ))}
        </div>
      </Section>

      <div style={{ height: 22 }} />

      {/* Recent log */}
      <Section eyebrow="TRAINING LOG · RECENT" eyebrowRight="VIEW ALL ↗">
        {RECENT_LOGS.map((l, i) => (
          <div key={i} style={{ padding: "12px 0", borderBottom: i < RECENT_LOGS.length - 1 ? "1px solid var(--rule)" : "0" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <Eyebrow>{l.date} · {l.type} · {l.miles}</Eyebrow>
              {l.pace
                ? <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--coral)", fontWeight: 600 }}>▸ {l.pace}</span>
                : <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em" }}>{l.text}</span>
              }
            </div>
            <p className="quote" style={{ fontSize: 13, margin: "6px 0 4px 0" }}>"{l.quote}"</p>
            <MoodPill mood={l.mood} />
          </div>
        ))}
      </Section>

      <div style={{ height: 24 }} />
    </div>
  </div>
);

window.TrainingScreen = TrainingScreen;
