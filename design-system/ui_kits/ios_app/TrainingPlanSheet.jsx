// Post Run Drip · iOS UI kit · Training Plan sheet (full calendar)
//
// Mirrors TrainingPlanView.swift — goal line, pace ladder strip,
// WEEK / MONTH toggle, then either a week of cards or a month of
// week-summary rows. Editorial vocabulary throughout.

const TRAINING_PLAN_CSS = `
.prd-tp__goalline {
  display: flex; justify-content: space-between; align-items: baseline;
  padding-bottom: 14px;
  border-bottom: 1px solid var(--rule);
}
.prd-tp__goalline-title {
  font-family: var(--font-display);
  font-size: 22px; font-weight: 700; color: var(--ink); letter-spacing: -0.01em;
}
.prd-tp__goalline-meta {
  font-family: var(--font-mono); font-size: 10px;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
}

.prd-tp__ladder {
  display: grid; grid-template-columns: repeat(4, 1fr);
  padding: 14px 0; border-bottom: 1px solid var(--rule);
}
.prd-tp__ladder-cell {
  display: flex; flex-direction: column; align-items: center; gap: 3px;
  border-right: 1px solid var(--rule);
}
.prd-tp__ladder-cell:last-child { border-right: 0; }
.prd-tp__ladder-label {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.12em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-tp__ladder-pace {
  font-family: var(--font-mono); font-weight: 600; font-size: 16px;
  color: var(--ink); font-variant-numeric: tabular-nums;
}

.prd-tp__mode {
  display: grid; grid-template-columns: 1fr 1fr;
  margin-top: 18px;
  border-top: 1px solid var(--rule);
  border-bottom: 1px solid var(--rule);
}
.prd-tp__mode-btn {
  padding: 12px 0 0 0;
  background: transparent; border: 0;
  text-align: center;
  font-family: var(--font-mono); font-size: 11px; font-weight: 500;
  letter-spacing: 0.12em; color: var(--ink-2);
  text-transform: uppercase;
  cursor: pointer;
}
.prd-tp__mode-btn.is-active { color: var(--coral); }
.prd-tp__mode-rail {
  height: 2px; background: transparent; margin-top: 8px;
}
.prd-tp__mode-btn.is-active .prd-tp__mode-rail { background: var(--coral); }

/* Week list — one row per day */
.prd-tp__day-row {
  display: grid;
  grid-template-columns: 56px 1fr 70px;
  gap: 12px;
  padding: 16px 0;
  border-bottom: 1px solid var(--rule);
  cursor: pointer;
  align-items: baseline;
}
.prd-tp__day-row:hover { background: rgba(0,0,0,0.015); }
.prd-tp__day-name {
  font-family: var(--font-mono); font-size: 11px; font-weight: 500;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-tp__day-date {
  font-family: var(--font-mono); font-size: 9px;
  color: var(--ink-3); letter-spacing: 0.10em;
  margin-top: 4px;
}
.prd-tp__day-type {
  font-family: var(--font-mono); font-size: 10px; font-weight: 500;
  letter-spacing: 0.10em; color: var(--coral);
  text-transform: uppercase;
}
.prd-tp__day-name-w {
  font-family: var(--font-display); font-size: 18px; font-weight: 700;
  color: var(--ink); letter-spacing: -0.01em;
  margin-top: 4px;
}
.prd-tp__day-desc {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3); line-height: 1.4;
  margin-top: 4px;
}
.prd-tp__day-rhs {
  text-align: right;
}
.prd-tp__day-dist {
  font-family: var(--font-mono); font-size: 16px; font-weight: 600;
  color: var(--ink); font-variant-numeric: tabular-nums;
}
.prd-tp__day-dur {
  font-family: var(--font-mono); font-size: 9px;
  color: var(--ink-3); letter-spacing: 0.10em;
  margin-top: 4px;
}
.prd-tp__day-row.is-today .prd-tp__day-name { color: var(--coral); }
.prd-tp__day-row.is-done .prd-tp__day-name-w { color: var(--ink-3); text-decoration: line-through; }
.prd-tp__day-row.is-rest .prd-tp__day-name-w { color: var(--ink-2); font-style: italic; font-weight: 400; }
.prd-tp__day-row.is-rest .prd-tp__day-dist { color: var(--ink-3); }

/* Week summary row (month view) */
.prd-tp__week-row {
  display: grid;
  grid-template-columns: 56px 1fr 90px;
  gap: 12px;
  padding: 16px 0;
  border-bottom: 1px solid var(--rule);
  cursor: pointer;
  align-items: baseline;
}
.prd-tp__week-num {
  font-family: var(--font-mono); font-size: 10px; font-weight: 500;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-tp__week-title {
  font-family: var(--font-display); font-size: 16px; font-weight: 700;
  color: var(--ink); letter-spacing: -0.01em;
}
.prd-tp__week-desc {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3);
  margin-top: 4px;
}
.prd-tp__week-rhs {
  text-align: right;
}
.prd-tp__week-mileage {
  font-family: var(--font-mono); font-size: 16px; font-weight: 600;
  color: var(--ink); font-variant-numeric: tabular-nums;
}
.prd-tp__week-phase {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.10em; color: var(--coral);
  margin-top: 4px;
  text-transform: uppercase;
}
.prd-tp__week-row.is-current { background: rgba(212,89,42,0.04); padding-left: 12px; padding-right: 12px; }
.prd-tp__week-row.is-done .prd-tp__week-mileage { color: var(--ink-3); }
`;

// ----- Week data -------------------------------------------------------
const WEEK = [
  { day: "MON", date: "MAY 4",  type: "EASY",      name: "Easy 6",                  desc: "Aerobic recovery from Sunday long",        miles: "6.0",  dur: "46 min", state: "done" },
  { day: "TUE", date: "MAY 5",  type: "TEMPO",     name: "MP rhythm session",       desc: "2 wu · 4×20s strides · 7 @ MP · 1.5 cd",   miles: "11.0", dur: "78 min", state: "today" },
  { day: "WED", date: "MAY 6",  type: "EASY",      name: "Easy 7",                  desc: "Conversational. Add 4 strides at end.",    miles: "7.0",  dur: "53 min", state: "future" },
  { day: "THU", date: "MAY 7",  type: "INTERVALS", name: "VO2 — 6×800",             desc: "@ 5K pace · 90s jog recovery between",     miles: "9.0",  dur: "65 min", state: "future" },
  { day: "FRI", date: "MAY 8",  type: "RECOVERY",  name: "Recovery shakeout",       desc: "Easy 4 mi — loosen, no watch checking",    miles: "4.0",  dur: "34 min", state: "future" },
  { day: "SAT", date: "MAY 9",  type: "REST",      name: "Rest day",                desc: "Stretch. Sleep. Hydrate. Coffee.",          miles: "—",     dur: "—",      state: "rest"   },
  { day: "SUN", date: "MAY 10", type: "LONG RUN",  name: "Long run · 20",           desc: "Last 6 at marathon pace. Practice fueling.", miles: "20.0", dur: "2:30",   state: "future" },
];

// ----- Month data ------------------------------------------------------
const MONTHS = [
  { wk: "WEEK 17", title: "Base build — block 3.",     desc: "First MP rhythm. Strides. Long run with MP segment.",      miles: "47", phase: "BASE", state: "current" },
  { wk: "WEEK 18", title: "Specific — block 1.",       desc: "VO2 + longer MP. Test workout Saturday.",                  miles: "52", phase: "SPECIFIC", state: "future" },
  { wk: "WEEK 19", title: "Specific — block 2.",       desc: "Longest MP block of the cycle. Long run with fuel test.",  miles: "55", phase: "SPECIFIC", state: "future" },
  { wk: "WEEK 20", title: "Recovery week.",            desc: "Mileage drops 30%. One workout, easy long.",               miles: "38", phase: "RECOVERY", state: "future" },
  { wk: "WEEK 21", title: "Sharpening — block 1.",     desc: "Race-pace simulation Saturday. Goal-pace miles.",          miles: "50", phase: "SHARPEN", state: "future" },
  { wk: "WEEK 22", title: "Sharpening — block 2.",     desc: "Final tune-up race or simulation.",                        miles: "44", phase: "SHARPEN", state: "future" },
  { wk: "WEEK 23", title: "Taper — opening.",          desc: "Mileage drops, intensity stays. Don't add anything new.",  miles: "36", phase: "TAPER", state: "future" },
  { wk: "WEEK 24", title: "Race week.",                desc: "Two easy 4s, shakeout Saturday, race Sunday.",              miles: "30", phase: "RACE", state: "future" },
];

const TrainingPlanSheet = ({ onClose, onOpenDay }) => {
  const [mode, setMode] = React.useState("week");

  return (
    <Sheet
      surface="PLAN · MARATHON BLOCK"
      onClose={onClose}
    >
      <style>{TRAINING_PLAN_CSS}</style>

      {/* Goal */}
      <Eyebrow coral>YOUR PLAN</Eyebrow>
      <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>Marathon block.</h1>
      <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
        — 47 days out. 2:48 goal. Building Pfitz-style with adjustments. —
      </div>

      <div style={{ height: 18 }} />
      <div className="prd-tp__goalline">
        <div>
          <span className="prd-tp__goalline-title">2:48:00</span>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", marginTop: 2 }}>
            BOSTON MARATHON  ·  JUNE 24
          </div>
        </div>
        <span className="prd-tp__goalline-meta">EDIT GOAL ↗</span>
      </div>

      {/* Pace ladder */}
      <div className="prd-tp__ladder">
        {[
          { l: "EASY",      p: "8:14" },
          { l: "MARATHON",  p: "6:24" },
          { l: "THRESHOLD", p: "5:58" },
          { l: "INTERVAL",  p: "5:18" },
        ].map((p, i) => (
          <div key={i} className="prd-tp__ladder-cell">
            <span className="prd-tp__ladder-label">{p.l}</span>
            <span className="prd-tp__ladder-pace">{p.p}</span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.08em" }}>/ MI</span>
          </div>
        ))}
      </div>

      {/* Mode toggle */}
      <div className="prd-tp__mode">
        <button className={"prd-tp__mode-btn" + (mode === "week" ? " is-active" : "")} onClick={() => setMode("week")}>
          Week
          <div className="prd-tp__mode-rail" />
        </button>
        <button className={"prd-tp__mode-btn" + (mode === "month" ? " is-active" : "")} onClick={() => setMode("month")}>
          Month
          <div className="prd-tp__mode-rail" />
        </button>
      </div>

      {mode === "week" ? (
        <React.Fragment>
          <div style={{ paddingTop: 16, display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>WEEK 17  ·  MAY 4 – MAY 10</Eyebrow>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", letterSpacing: "0.10em" }}>57.0 MI PLANNED</span>
          </div>
          <div style={{ marginTop: 6 }}>
            {WEEK.map((d, i) => (
              <div
                key={i}
                className={
                  "prd-tp__day-row" +
                  (d.state === "today" ? " is-today" : "") +
                  (d.state === "done" ? " is-done" : "") +
                  (d.state === "rest" ? " is-rest" : "")
                }
                onClick={() => d.state !== "rest" && onOpenDay && onOpenDay(d)}
              >
                <div>
                  <div className="prd-tp__day-name">{d.day}</div>
                  <div className="prd-tp__day-date">{d.date}</div>
                </div>
                <div>
                  <div className="prd-tp__day-type">{d.type}</div>
                  <div className="prd-tp__day-name-w">{d.name}</div>
                  <div className="prd-tp__day-desc">{d.desc}</div>
                </div>
                <div className="prd-tp__day-rhs">
                  <div className="prd-tp__day-dist">{d.miles === "—" ? "—" : `${d.miles} mi`}</div>
                  <div className="prd-tp__day-dur">{d.dur}</div>
                </div>
              </div>
            ))}
          </div>
        </React.Fragment>
      ) : (
        <React.Fragment>
          <div style={{ paddingTop: 16, display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>8 WEEKS  ·  MAY 4 – JUNE 28</Eyebrow>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", letterSpacing: "0.10em" }}>352 MI · 4 BLOCKS</span>
          </div>
          <div style={{ marginTop: 6 }}>
            {MONTHS.map((m, i) => (
              <div
                key={i}
                className={
                  "prd-tp__week-row" +
                  (m.state === "current" ? " is-current" : "") +
                  (m.state === "done" ? " is-done" : "")
                }
                onClick={() => setMode("week")}
              >
                <div className="prd-tp__week-num">{m.wk}</div>
                <div>
                  <div className="prd-tp__week-title">{m.title}</div>
                  <div className="prd-tp__week-desc">{m.desc}</div>
                </div>
                <div className="prd-tp__week-rhs">
                  <div className="prd-tp__week-mileage">{m.miles} MI</div>
                  <div className="prd-tp__week-phase">{m.phase}</div>
                </div>
              </div>
            ))}
          </div>
        </React.Fragment>
      )}

      <div style={{ height: 14 }} />
      <div style={{ display: "flex", justifyContent: "space-between", paddingTop: 14, borderTop: "1px solid var(--rule)" }}>
        <span className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }}>Import plan ↗</span>
        <span className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }}>Adjust week ↗</span>
        <span className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }}>Reschedule ↗</span>
      </div>
    </Sheet>
  );
};

window.TrainingPlanSheet = TrainingPlanSheet;
