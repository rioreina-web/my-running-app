// Post Run Drip · iOS UI kit · Training screen
// Train tab as "the current block." Three lenses behind one segmenter:
//
//   THIS WEEK  — today's session, this week's plan, week's mileage
//   THE BLOCK  — block-level narrative, totals, pace × volume, race countdown
//   THE PLAN   — multi-week calendar (PlanScreen hosted in embed mode)
//
// Notes:
//   • Today's coach intent (per-workout) is inline within the hero — NOT
//     a separate "FROM YOUR COACH" section. Source: planned_workout.coach_intent.
//   • The weekly meta-narrative (per-week, generated) sits at the top of
//     THE BLOCK as "BLOCK NOTE". Source: weekly_coaching_reports.coaching_narrative.
//   • Recent log dropped — Runs tab owns the chronological history.
//
// Coral discipline: max 2 corals per visible cluster. See handoff doc.

const TRAIN_DAYS = [
  { name: "Mon", miles: 6,  type: "Easy",  state: "done" },
  { name: "Tue", miles: 8,  type: "Tempo", state: "done" },
  { name: "Wed", miles: 11, type: "MP",    state: "today" },
  { name: "Thu", miles: "—", type: "Rest", state: "rest" },
  { name: "Fri", miles: 6,  type: "Easy",  state: "future" },
  { name: "Sat", miles: 20, type: "Long",  state: "future" },
  { name: "Sun", miles: "—", type: "Rest", state: "rest" },
];

const TRAIN_PACE = [
  { lbl: "EASY",      range: "6:30 – 7:30 / mi", miles: "28.3", pct: 60, color: "var(--ink-2)" },
  { lbl: "STEADY",    range: "6:00 – 6:30 / mi", miles: "11.4", pct: 24, color: "var(--ink-2)" },
  { lbl: "THRESHOLD", range: "5:50 – 6:00 / mi", miles:  "4.2", pct:  9, color: "var(--coral)" },
  { lbl: "VO2",       range: "5:25 – 5:40 / mi", miles:  "2.1", pct:  4, color: "var(--ink-2)" },
  { lbl: "RACE",      range: "5:42 / mi",        miles:  "1.2", pct:  3, color: "var(--ink-2)" },
];

const TrainingScreen = ({ onOpenDay, onOpenPlan, onOpenWorkout, onOpenRace, onOpenHistory }) => {
  const [view, setView] = React.useState("week"); // "week" | "block" | "plan"
  return (
    <div className="page">
      <PlateStrip surface="TRAINING · MARATHON BLOCK" fig="FIG. 6" />
      <div className="page__body">

        {/* Header — shared across all three views */}
        <div className="section section--first">
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>TRAINING&nbsp;&nbsp;·&nbsp;&nbsp;WEEK 09 OF 16</Eyebrow>
            <Eyebrow>MON&nbsp;·&nbsp;APR 27</Eyebrow>
          </div>
          <h1 className="h-display" style={{ fontSize: 32, marginTop: 4 }}>Marathon block.</h1>
          <p style={{
            fontFamily: "var(--font-body)", fontStyle: "italic",
            fontSize: 13, color: "var(--ink-2)", margin: "4px 0 0 0",
          }}>
            Sub-3:10&nbsp;·&nbsp;May 18&nbsp;·&nbsp;47 days out.
            <span onClick={onOpenRace} style={{ marginLeft: 8, cursor: "pointer", fontStyle: "normal", borderBottom: "1px solid var(--rule)", paddingBottom: 1 }}>Race plan ↗</span>
          </p>
        </div>

        {/* Segmenter */}
        <div role="tablist" style={{ display: "flex", marginTop: 18, borderBottom: "1px solid var(--rule)" }}>
          {[["week", "THIS WEEK"], ["block", "THE BLOCK"], ["plan", "THE PLAN"]].map(([id, lbl]) => (
            <div
              key={id}
              role="tab"
              aria-selected={view === id}
              onClick={() => setView(id)}
              style={{
                flex: 1, padding: "12px 0", textAlign: "center", cursor: "pointer",
                fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
                letterSpacing: "0.12em", textTransform: "uppercase",
                color: view === id ? "var(--coral)" : "var(--ink-2)",
                borderBottom: view === id ? "1.5px solid var(--coral)" : "1.5px solid transparent",
                marginBottom: -1, transition: "color .2s, border-color .2s",
              }}
            >{lbl}</div>
          ))}
        </div>

        {view === "week"  && <TrainingWeekView onOpenWorkout={onOpenWorkout} onOpenDay={onOpenDay} />}
        {view === "block" && <TrainingBlockView onOpenHistory={onOpenHistory} onOpenRace={onOpenRace} />}
        {view === "plan"  && <PlanScreen embed onOpenDay={onOpenDay} onOpenRace={onOpenRace} onOpenHistory={onOpenHistory} />}

        <div style={{ height: 24 }} />
      </div>
    </div>
  );
};

// ───────────────────────────────────────────────────────────────
// WEEK · today as editorial headline (with coach intent inline)
// + week strip + weekly mileage
// ───────────────────────────────────────────────────────────────
const TrainingWeekView = ({ onOpenWorkout, onOpenDay }) => (
  <>
    <div style={{ height: 24 }} />

    {/* TODAY hero — editorial, not a card. Coach intent sits inline
        between the prescription and the action. */}
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <Eyebrow coral>TODAY&nbsp;·&nbsp;WED&nbsp;·&nbsp;APR 29</Eyebrow>
        <Eyebrow>11 MI&nbsp;·&nbsp;MP</Eyebrow>
      </div>
      <h2 className="h-display" style={{ fontSize: 30, marginTop: 6, letterSpacing: "-0.012em" }}>
        Marathon-pace 11.
      </h2>
      <p style={{
        fontFamily: "var(--font-mono)", fontSize: 11,
        color: "var(--ink-2)", letterSpacing: "0.10em",
        textTransform: "uppercase", marginTop: 10,
      }}>
        2 MI WU&nbsp;&nbsp;·&nbsp;&nbsp;8 MI @ MP&nbsp;&nbsp;·&nbsp;&nbsp;1 MI CD
      </p>

      {/* Coach intent for THIS workout — italic serif inline, no eyebrow,
          no left bar. Source: planned_workout.coach_intent. */}
      <p style={{
        fontFamily: "var(--font-body)", fontStyle: "italic",
        fontSize: 14, color: "var(--ink-2)", lineHeight: 1.5,
        margin: "12px 0 0 0",
      }}>
        "Hold splits, don't chase them — negative is fine, positive is not."
      </p>

      <div style={{ marginTop: 18 }}>
        <span onClick={onOpenWorkout} className="link" style={{ fontSize: 14, cursor: "pointer" }}>
          Mark complete ↗
        </span>
      </div>
    </div>

    <div style={{ height: 28 }} />
    <EditorialRule />
    <div style={{ height: 18 }} />

    {/* Week strip */}
    <Section eyebrow="THE WEEK">
      <div className="wkstrip">
        {TRAIN_DAYS.map(d => (
          <div
            key={d.name}
            onClick={() => d.state !== "rest" && onOpenDay && onOpenDay()}
            className={"wkday" + (d.state === "today" ? " is-today" : d.state === "done" ? " is-done" : d.state === "rest" ? " is-rest" : "")}
            style={{ cursor: d.state !== "rest" ? "pointer" : "default" }}
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

    {/* Weekly mileage — quiet. The chart belongs to BLOCK. */}
    <Section eyebrow="WEEKLY MILEAGE" eyebrowRight="+8% VS PRIOR">
      <div style={{ display: "flex", alignItems: "baseline", gap: 6, marginTop: 6 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 40, color: "var(--ink)", lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>47.2</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-2)" }}>MILES</span>
      </div>
    </Section>
  </>
);

// ───────────────────────────────────────────────────────────────
// BLOCK · weekly narrative + block totals + pace × volume +
// race countdown + quiet link to Runs
// ───────────────────────────────────────────────────────────────
const TrainingBlockView = ({ onOpenHistory, onOpenRace }) => (
  <>
    <div style={{ height: 22 }} />

    {/* Block note — the weekly meta-narrative. Source:
        weekly_coaching_reports.coaching_narrative for the current week,
        with local fallback (narrativeString). */}
    <Eyebrow coral>BLOCK NOTE&nbsp;·&nbsp;WEEK 09</Eyebrow>
    <p style={{
      fontFamily: "var(--font-body)", fontStyle: "italic",
      fontSize: 14, color: "var(--ink)", lineHeight: 1.5,
      margin: "10px 0 0 0",
    }}>
      "Volume holding steady. Mood trending up. Sunday's 20-miler is the marquee — execute that and the block stays on rails."
    </p>

    <div style={{ height: 26 }} />
    <EditorialRule />
    <div style={{ height: 18 }} />

    {/* Block totals — three borderless columns */}
    <Eyebrow>BLOCK TOTALS</Eyebrow>
    <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", marginTop: 12 }}>
      {[
        { lbl: "TO DATE",    val: "342", unit: "MI" },
        { lbl: "AVG WEEK",   val:  "38", unit: "MI" },
        { lbl: "LONG TOPS",  val:  "20", unit: "MI" },
      ].map((s, i, arr) => (
        <div key={s.lbl} style={{ borderRight: i < arr.length - 1 ? "1px solid var(--rule)" : "0", padding: "0 10px" }}>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.12em", textTransform: "uppercase" }}>{s.lbl}</div>
          <div style={{ display: "flex", alignItems: "baseline", gap: 4, marginTop: 6 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 26, color: "var(--ink)", fontVariantNumeric: "tabular-nums", lineHeight: 1 }}>{s.val}</span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)" }}>{s.unit}</span>
          </div>
        </div>
      ))}
    </div>

    <div style={{ height: 26 }} />

    {/* Pace × volume — full version with ranges */}
    <Section eyebrow="PACE  &  VOLUME · 9 WEEKS">
      <div style={{ display: "flex", flexDirection: "column", gap: 10, paddingTop: 8 }}>
        {TRAIN_PACE.map(b => (
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

    <div style={{ height: 26 }} />
    <EditorialRule />
    <div style={{ height: 18 }} />

    {/* Race countdown — close out BLOCK with the destination */}
    <div onClick={onOpenRace} style={{ cursor: "pointer" }}>
      <Eyebrow>THE RACE</Eyebrow>
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", marginTop: 8 }}>
        <h3 className="h-display" style={{ fontSize: 26, margin: 0, letterSpacing: "-0.012em" }}>
          Boston Marathon.
        </h3>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--coral)", fontWeight: 600, letterSpacing: "0.10em" }}>
          47 D ↗
        </span>
      </div>
      <p style={{
        fontFamily: "var(--font-mono)", fontSize: 10,
        color: "var(--ink-2)", letterSpacing: "0.10em",
        textTransform: "uppercase", margin: "6px 0 0 0",
      }}>
        MAY 18&nbsp;&nbsp;·&nbsp;&nbsp;HOPKINTON → BOYLSTON&nbsp;&nbsp;·&nbsp;&nbsp;PREDICTED 3:11:14
      </p>
    </div>

    <div style={{ height: 24 }} />

    {/* Quiet link out to Runs — Runs owns the chronological history,
        Train owns the analysis. No duplication. */}
    <div style={{ display: "flex", justifyContent: "center" }}>
      <span
        onClick={onOpenHistory}
        style={{
          fontFamily: "var(--font-mono)", fontSize: 10,
          color: "var(--ink-2)", letterSpacing: "0.12em",
          textTransform: "uppercase", cursor: "pointer",
          borderBottom: "1px solid var(--rule)", paddingBottom: 1,
        }}
      >
        RECENT RUNS&nbsp;&nbsp;·&nbsp;&nbsp;OPEN RUNS ↗
      </span>
    </div>
  </>
);

window.TrainingScreen = TrainingScreen;
