// Post Run Drip · iOS UI kit · Training — Option B · Two-screen split
// Train splits into two views via a tracked monospaced segmenter:
//   • WEEK  — what to do this week (today card + week strip + mileage)
//   • BLOCK — the longer view (pace mix + recent log + block totals)
// Both views breathe; nothing competes for the eye.

const TRAIN_B_DAYS = [
  { name: "Mon", miles: 6,  type: "Easy",  state: "done" },
  { name: "Tue", miles: 8,  type: "Tempo", state: "done" },
  { name: "Wed", miles: 11, type: "MP",    state: "today" },
  { name: "Thu", miles: "—", type: "Rest", state: "rest" },
  { name: "Fri", miles: 6,  type: "Easy",  state: "future" },
  { name: "Sat", miles: 20, type: "Long",  state: "future" },
  { name: "Sun", miles: "—", type: "Rest", state: "rest" },
];

const TRAIN_B_PACE = [
  { lbl: "EASY",      range: "6:30 – 7:30 / mi", miles: "28.3", pct: 60, color: "var(--ink-2)" },
  { lbl: "STEADY",    range: "6:00 – 6:30 / mi", miles: "11.4", pct: 24, color: "var(--ink-2)" },
  { lbl: "THRESHOLD", range: "5:50 – 6:00 / mi", miles:  "4.2", pct:  9, color: "var(--coral)" },
  { lbl: "VO2",       range: "5:25 – 5:40 / mi", miles:  "2.1", pct:  4, color: "var(--ink-2)" },
  { lbl: "RACE",      range: "5:42 / mi",        miles:  "1.2", pct:  3, color: "var(--ink-2)" },
];

const TRAIN_B_LOGS = [
  { date: "APR 26", type: "LONG RUN", miles: "18 MI", quote: "Felt strong through 14, started to fade on the hills…", mood: "positive" },
  { date: "APR 24", type: "TEMPO",    miles:  "8 MI", quote: "Hit the prescribed paces cleanly. Slight headwind…",     mood: "energized" },
];

const TrainB = () => {
  const [view, setView] = React.useState("week");
  return (
    <div className="page">
      <PlateStrip surface="TRAINING · MARATHON BLOCK" fig="FIG. 6" />
      <div className="page__body">
        {/* Header (shared) */}
        <div className="section section--first">
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>TRAINING&nbsp;&nbsp;·&nbsp;&nbsp;WEEK 09 OF 16</Eyebrow>
            <Eyebrow>MON&nbsp;·&nbsp;APR 27</Eyebrow>
          </div>
          <h1 className="h-display" style={{ fontSize: 32, marginTop: 4 }}>Marathon block.</h1>
          <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", margin: "4px 0 0 0" }}>
            Sub-3:10 · May 18 · 47 days out.
          </p>
        </div>

        {/* Segmenter — tracked monospaced, coral underline on active */}
        <div style={{ display: "flex", marginTop: 18, borderBottom: "1px solid var(--rule)" }}>
          {[["week", "THIS WEEK"], ["block", "THE BLOCK"]].map(([id, lbl]) => (
            <div
              key={id}
              onClick={() => setView(id)}
              style={{
                flex: 1, padding: "12px 0", textAlign: "center", cursor: "pointer",
                fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
                letterSpacing: "0.14em", textTransform: "uppercase",
                color: view === id ? "var(--coral)" : "var(--ink-2)",
                borderBottom: view === id ? "1.5px solid var(--coral)" : "1.5px solid transparent",
                marginBottom: -1, transition: "color .2s, border-color .2s",
              }}
            >{lbl}</div>
          ))}
        </div>

        {view === "week" ? <TrainBWeek /> : <TrainBBlock />}

        <div style={{ height: 24 }} />
      </div>
    </div>
  );
};

const TrainBWeek = () => (
  <>
    <div style={{ height: 18 }} />

    {/* Today card — the hero of the WEEK view */}
    <div style={{ background: "var(--card)", borderRadius: 12, padding: 18, boxShadow: "0 2px 8px rgba(0,0,0,0.06)" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <Eyebrow coral>TODAY · WED · APR 29</Eyebrow>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em" }}>11 MI · MP</span>
      </div>
      <h2 style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 24, margin: "10px 0 0 0", letterSpacing: "-0.01em", color: "var(--ink)" }}>
        Marathon-pace 11.
      </h2>
      <p style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-2)", letterSpacing: "0.06em", marginTop: 6, textTransform: "uppercase" }}>
        2 mi WU · 8 mi @ MP · 1 mi CD
      </p>
      <div style={{ marginTop: 12 }}>
        <CoachQuote>Hold splits, don't chase them — negative is fine, positive is not.</CoachQuote>
      </div>
    </div>

    <div style={{ height: 22 }} />

    <Section eyebrow="THE WEEK">
      <div className="wkstrip">
        {TRAIN_B_DAYS.map(d => (
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

    <div style={{ height: 22 }} />

    <Section eyebrow="WEEKLY MILEAGE" eyebrowRight="+8% VS PRIOR">
      <div style={{ display: "flex", alignItems: "baseline", gap: 6, marginTop: 6 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 40, color: "var(--ink)", lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>47.2</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-2)" }}>MILES</span>
      </div>
    </Section>
  </>
);

const TrainBBlock = () => (
  <>
    <div style={{ height: 22 }} />

    {/* Block totals — three small mono numbers */}
    <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 0 }}>
      {[
        { lbl: "BLOCK TOTAL", val: "342", unit: "MI"   },
        { lbl: "AVG WEEK",    val:  "38", unit: "MI"   },
        { lbl: "LONG TOPS",   val:  "20", unit: "MI"   },
      ].map((s, i, arr) => (
        <div key={s.lbl} style={{ borderRight: i < arr.length - 1 ? "1px solid var(--rule)" : "0", padding: "0 8px" }}>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.12em", textTransform: "uppercase" }}>{s.lbl}</div>
          <div style={{ display: "flex", alignItems: "baseline", gap: 4, marginTop: 6 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 26, color: "var(--ink)", fontVariantNumeric: "tabular-nums" }}>{s.val}</span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)" }}>{s.unit}</span>
          </div>
        </div>
      ))}
    </div>

    <div style={{ height: 24 }} />

    {/* Pace mix — full version (with range column) lives here */}
    <Section eyebrow="PACE & VOLUME · 9 WEEKS">
      <div style={{ display: "flex", flexDirection: "column", gap: 10, paddingTop: 6 }}>
        {TRAIN_B_PACE.map(b => (
          <div key={b.lbl} style={{ display: "grid", gridTemplateColumns: "78px 1fr 50px 36px", alignItems: "center", gap: 10 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em" }}>{b.lbl}</span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)" }}>{b.range}</span>
            <div style={{ background: "var(--paper-deep)", height: 6, borderRadius: 999, overflow: "hidden" }}>
              <div style={{ background: b.color, height: "100%", width: (b.pct * 1.4) + "%" }}></div>
            </div>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink)", fontWeight: 600, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{b.miles}</span>
          </div>
        ))}
      </div>
    </Section>

    <div style={{ height: 22 }} />

    {/* Recent log — short, no coral pace marker (Workout detail owns that) */}
    <Section eyebrow="TRAINING LOG · RECENT" eyebrowRight="VIEW ALL ↗">
      {TRAIN_B_LOGS.map((l, i) => (
        <div key={i} style={{ padding: "12px 0", borderBottom: i < TRAIN_B_LOGS.length - 1 ? "1px solid var(--rule)" : "0" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>{l.date} · {l.type} · {l.miles}</Eyebrow>
            <MoodPill mood={l.mood} />
          </div>
          <p className="quote" style={{ fontSize: 13, margin: "8px 0 0 0", color: "var(--ink-2)" }}>"{l.quote}"</p>
        </div>
      ))}
    </Section>
  </>
);

window.TrainB = TrainB;
