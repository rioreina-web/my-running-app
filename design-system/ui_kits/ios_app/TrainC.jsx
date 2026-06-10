// Post Run Drip · iOS UI kit · Training — Option C · Today-first hero
// The whole Train tab reframes around today's prescribed session:
//   • Today's workout becomes the editorial hero (display headline + intent)
//   • Week ribbon slides under as context
//   • "Block at a glance" is a single compressed strip — no charts
//   • Pace mix is one line of text (EASY 60% · STEADY 24% · WORK 16%)
//   • Closer in spirit to the Log surface than the analytics-page version

const TRAIN_C_DAYS = [
  { name: "Mon", miles: 6,  type: "Easy",  state: "done" },
  { name: "Tue", miles: 8,  type: "Tempo", state: "done" },
  { name: "Wed", miles: 11, type: "MP",    state: "today" },
  { name: "Thu", miles: "—", type: "Rest", state: "rest" },
  { name: "Fri", miles: 6,  type: "Easy",  state: "future" },
  { name: "Sat", miles: 20, type: "Long",  state: "future" },
  { name: "Sun", miles: "—", type: "Rest", state: "rest" },
];

const TrainC = () => (
  <div className="page">
    <PlateStrip surface="TRAINING · TODAY" fig="FIG. 6" />
    <div className="page__body">
      {/* Quiet eyebrow — week + day out, no chunky goal row */}
      <div className="section section--first">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <Eyebrow coral>WED · APR 29</Eyebrow>
          <Eyebrow>WK 09 / 16 · 47 D OUT</Eyebrow>
        </div>
      </div>

      {/* HERO — today's prescribed workout, set like an editorial headline.
          Four things only: title, the prescription, target pace, the one action. */}
      <div style={{ marginTop: 8 }}>
        <h1 className="h-display" style={{ fontSize: 36, letterSpacing: "-0.012em" }}>
          Marathon-pace 11.
        </h1>
        <p style={{
          fontFamily: "var(--font-mono)", fontSize: 11,
          color: "var(--ink-2)", letterSpacing: "0.10em",
          textTransform: "uppercase", marginTop: 12,
        }}>
          2 MI WU&nbsp;&nbsp;·&nbsp;&nbsp;8 MI @ MP&nbsp;&nbsp;·&nbsp;&nbsp;1 MI CD
        </p>

        <div style={{ marginTop: 22 }}>
          <span className="link" style={{ fontSize: 14, cursor: "pointer" }}>Mark complete ↗</span>
        </div>
      </div>

      <div style={{ height: 28 }} />
      <EditorialRule />
      <div style={{ height: 20 }} />

      {/* Coach note — moved out of the hero into its own quiet section */}
      <Eyebrow coral>FROM YOUR COACH</Eyebrow>
      <div style={{ marginTop: 10 }}>
        <CoachQuote>
          Hold splits, don't chase them — negative is fine, positive is not.
        </CoachQuote>
      </div>

      <div style={{ height: 30 }} />
      <EditorialRule />
      <div style={{ height: 22 }} />

      {/* Week ribbon — same compoenent, lower presence in the hierarchy */}
      <Eyebrow>THE WEEK AHEAD</Eyebrow>
      <div className="wkstrip" style={{ paddingTop: 14 }}>
        {TRAIN_C_DAYS.map(d => (
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

      <div style={{ height: 32 }} />
      <EditorialRule />
      <div style={{ height: 22 }} />

      {/* Block at a glance — three compressed stats, no chart */}
      <Eyebrow>BLOCK AT A GLANCE</Eyebrow>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", marginTop: 14 }}>
        {[
          { lbl: "THIS WEEK",   val: "47.2", unit: "MI"     },
          { lbl: "BLOCK TOTAL", val: "342",  unit: "MI"     },
          { lbl: "LONG RUN",    val: "20",   unit: "MI · SAT" },
        ].map((s, i, arr) => (
          <div key={s.lbl} style={{ borderRight: i < arr.length - 1 ? "1px solid var(--rule)" : "0", padding: "0 10px" }}>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.12em", textTransform: "uppercase" }}>{s.lbl}</div>
            <div style={{ display: "flex", alignItems: "baseline", gap: 4, marginTop: 6 }}>
              <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 24, color: "var(--ink)", fontVariantNumeric: "tabular-nums", lineHeight: 1 }}>{s.val}</span>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)" }}>{s.unit}</span>
            </div>
          </div>
        ))}
      </div>

      <div style={{ height: 18 }} />

      {/* Pace mix collapsed to a single mono line */}
      <p style={{
        fontFamily: "var(--font-mono)", fontSize: 10,
        color: "var(--ink-2)", letterSpacing: "0.10em",
        textTransform: "uppercase", textAlign: "left", margin: 0,
      }}>
        PACE MIX&nbsp;&nbsp;·&nbsp;&nbsp;EASY 60%&nbsp;&nbsp;·&nbsp;&nbsp;STEADY 24%&nbsp;&nbsp;·&nbsp;&nbsp;WORK 16%
      </p>

      <div style={{ height: 28 }} />
      <EditorialRule />
      <div style={{ height: 14 }} />

      {/* Quiet exit to the analytics surface */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <Eyebrow>RECENT RUNS</Eyebrow>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em", cursor: "pointer", borderBottom: "1px solid var(--rule)", paddingBottom: 1 }}>
          OPEN RUNS ↗
        </span>
      </div>

      <div style={{ height: 24 }} />
    </div>
  </div>
);

window.TrainC = TrainC;
