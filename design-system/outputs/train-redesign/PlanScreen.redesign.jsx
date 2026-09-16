// Post Run Drip · iOS UI kit · Plan tab (full-screen training plan)
//
// Lifts the TrainingPlanSheet content onto a tab-level surface.
// The Plan tab is the canonical training-plan home — pace ladder,
// week / month toggle, and a list of days that each open a full
// workout breakdown (DayDetailSheet, upgraded).

const PLAN_SCREEN_CSS = `
.prd-plan__hero {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 12px;
  align-items: end;
  padding-bottom: 16px;
  border-bottom: 1px solid var(--rule);
}
.prd-plan__hero-headline {
  font-family: var(--font-display);
  font-weight: 700; font-size: 28px;
  color: var(--ink); letter-spacing: -0.01em;
  margin: 0;
}
.prd-plan__hero-meta {
  font-family: var(--font-mono);
  font-size: 9px; letter-spacing: 0.10em;
  color: var(--ink-3); text-transform: uppercase;
  margin-top: 6px;
}
.prd-plan__hero-rhs {
  text-align: right;
}
.prd-plan__hero-target {
  font-family: var(--font-mono);
  font-weight: 600; font-size: 22px;
  color: var(--coral);
  font-variant-numeric: tabular-nums;
}
.prd-plan__hero-target-label {
  font-family: var(--font-mono);
  font-size: 9px; letter-spacing: 0.12em;
  color: var(--ink-3); text-transform: uppercase;
  margin-top: 2px;
}

.prd-plan__ladder {
  display: grid; grid-template-columns: repeat(4, 1fr);
  padding: 14px 0; border-bottom: 1px solid var(--rule);
}
.prd-plan__ladder-cell {
  display: flex; flex-direction: column; align-items: center; gap: 3px;
  border-right: 1px solid var(--rule);
}
.prd-plan__ladder-cell:last-child { border-right: 0; }
.prd-plan__ladder-label {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.12em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-plan__ladder-pace {
  font-family: var(--font-mono); font-weight: 600; font-size: 18px;
  color: var(--ink); font-variant-numeric: tabular-nums;
}
.prd-plan__ladder-unit {
  font-family: var(--font-mono); font-size: 9px;
  color: var(--ink-3); letter-spacing: 0.08em;
}

.prd-plan__mode {
  display: grid; grid-template-columns: 1fr 1fr;
  margin-top: 16px;
  border-bottom: 1px solid var(--rule);
}
.prd-plan__mode-btn {
  padding: 12px 0 12px 0;
  background: transparent; border: 0;
  text-align: center;
  font-family: var(--font-mono); font-size: 11px; font-weight: 500;
  letter-spacing: 0.12em; color: var(--ink-2);
  text-transform: uppercase;
  cursor: pointer;
  position: relative;
}
.prd-plan__mode-btn.is-active { color: var(--coral); }
.prd-plan__mode-btn.is-active::after {
  content: ""; position: absolute; left: 30%; right: 30%; bottom: -1px;
  height: 1.5px; background: var(--coral);
}

.prd-plan__weeknav {
  display: flex; justify-content: space-between; align-items: center;
  padding: 14px 0 8px 0;
}
.prd-plan__weeknav-arrow {
  font-family: var(--font-mono); font-size: 14px; color: var(--ink-2);
  cursor: pointer; padding: 4px 8px;
}
.prd-plan__weeknav-arrow:hover { color: var(--coral); }
.prd-plan__weeknav-label {
  font-family: var(--font-mono);
  font-size: 11px; letter-spacing: 0.14em;
  color: var(--ink); text-transform: uppercase;
  font-weight: 600;
}
.prd-plan__weeknav-sub {
  font-family: var(--font-mono);
  font-size: 9px; letter-spacing: 0.10em;
  color: var(--ink-3); text-transform: uppercase;
  text-align: center; margin-top: 2px;
}

/* Day row */
.prd-plan__day {
  display: grid;
  grid-template-columns: 48px 1fr 72px;
  gap: 12px;
  padding: 14px 0;
  border-bottom: 1px solid var(--rule);
  cursor: pointer;
  align-items: baseline;
}
.prd-plan__day:hover { background: rgba(0,0,0,0.015); }
.prd-plan__day-day {
  font-family: var(--font-mono); font-size: 11px; font-weight: 600;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-plan__day-date {
  font-family: var(--font-mono); font-size: 9px;
  color: var(--ink-3); letter-spacing: 0.08em;
  margin-top: 4px;
}
.prd-plan__day-type {
  font-family: var(--font-mono); font-size: 9px; font-weight: 500;
  letter-spacing: 0.12em; color: var(--coral);
  text-transform: uppercase;
}
.prd-plan__day-name {
  font-family: var(--font-display); font-size: 17px; font-weight: 700;
  color: var(--ink); letter-spacing: -0.01em;
  margin-top: 4px;
}
.prd-plan__day-desc {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3); line-height: 1.45;
  margin-top: 4px;
}
.prd-plan__day-rhs {
  text-align: right;
}
.prd-plan__day-dist {
  font-family: var(--font-mono); font-size: 17px; font-weight: 600;
  color: var(--ink); font-variant-numeric: tabular-nums;
}
.prd-plan__day-dur {
  font-family: var(--font-mono); font-size: 9px;
  color: var(--ink-3); letter-spacing: 0.10em;
  margin-top: 4px;
  text-transform: uppercase;
}

.prd-plan__day.is-today {
  background: rgba(212,89,42,0.04);
  padding-left: 12px; padding-right: 12px;
}
.prd-plan__day.is-today .prd-plan__day-day { color: var(--coral); }
.prd-plan__day.is-today .prd-plan__day-name::after {
  content: " ·  today"; color: var(--coral); font-weight: 500;
  font-family: var(--font-mono); font-size: 10px;
  letter-spacing: 0.10em; text-transform: uppercase;
}
.prd-plan__day.is-done .prd-plan__day-name { color: var(--ink-3); text-decoration: line-through; }
.prd-plan__day.is-done .prd-plan__day-dist { color: var(--ink-3); }
.prd-plan__day.is-rest .prd-plan__day-name { color: var(--ink-2); font-style: italic; font-weight: 400; }
.prd-plan__day.is-rest .prd-plan__day-dist { color: var(--ink-3); }
.prd-plan__day.is-rest .prd-plan__day-type { color: var(--ink-3); }

/* Month / phase row */
.prd-plan__week {
  display: grid;
  grid-template-columns: 56px 1fr 90px;
  gap: 12px;
  padding: 14px 0;
  border-bottom: 1px solid var(--rule);
  cursor: pointer;
  align-items: baseline;
}
.prd-plan__week:hover { background: rgba(0,0,0,0.015); }
.prd-plan__week-num {
  font-family: var(--font-mono); font-size: 10px; font-weight: 600;
  letter-spacing: 0.12em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-plan__week-dates {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.10em; color: var(--ink-3);
  margin-top: 4px;
  text-transform: uppercase;
}
.prd-plan__week-title {
  font-family: var(--font-display); font-size: 17px; font-weight: 700;
  color: var(--ink); letter-spacing: -0.01em;
}
.prd-plan__week-desc {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3); line-height: 1.45;
  margin-top: 4px;
}
.prd-plan__week-rhs { text-align: right; }
.prd-plan__week-miles {
  font-family: var(--font-mono); font-size: 16px; font-weight: 600;
  color: var(--ink); font-variant-numeric: tabular-nums;
}
.prd-plan__week-phase {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.10em; color: var(--coral);
  margin-top: 4px;
  text-transform: uppercase;
}
.prd-plan__week.is-current { background: rgba(212,89,42,0.05); padding-left: 12px; padding-right: 12px; }
.prd-plan__week.is-done .prd-plan__week-miles { color: var(--ink-3); }
.prd-plan__week.is-done .prd-plan__week-title { color: var(--ink-3); }
`;

// ----- Week data -------------------------------------------------------
const PLAN_WEEK = [
  { id: "d1", day: "MON", date: "MAY 4",  type: "EASY",      name: "Easy 6",                  desc: "Aerobic recovery from Sunday long.",       miles: "6.0",  dur: "46 min", state: "done" },
  { id: "d2", day: "TUE", date: "MAY 5",  type: "TEMPO",     name: "MP rhythm session",       desc: "2 wu · 4×20s strides · 7 @ MP · 1.5 cd",   miles: "11.0", dur: "78 min", state: "today" },
  { id: "d3", day: "WED", date: "MAY 6",  type: "EASY",      name: "Easy 7",                  desc: "Conversational. Add 4 strides at end.",    miles: "7.0",  dur: "53 min", state: "future" },
  { id: "d4", day: "THU", date: "MAY 7",  type: "INTERVALS", name: "VO2 — 6 × 800m",          desc: "@ 5K pace · 90s jog recovery between.",    miles: "9.0",  dur: "65 min", state: "future" },
  { id: "d5", day: "FRI", date: "MAY 8",  type: "RECOVERY",  name: "Recovery shakeout",       desc: "Easy 4 — loosen, no watch checking.",      miles: "4.0",  dur: "34 min", state: "future" },
  { id: "d6", day: "SAT", date: "MAY 9",  type: "REST",      name: "Rest day",                desc: "Stretch. Sleep. Hydrate. Coffee.",          miles: "—",   dur: "—",      state: "rest"   },
  { id: "d7", day: "SUN", date: "MAY 10", type: "LONG RUN",  name: "Long run · 20",           desc: "Last 6 at MP. Practice race-day fueling.", miles: "20.0", dur: "2:30",   state: "future" },
];

// ----- Month / block data ----------------------------------------------
const PLAN_BLOCKS = [
  { wk: "WEEK 17", dates: "MAY 4 – 10",  title: "Base — block 3.",       desc: "First MP rhythm. Strides. Long run with MP segment.",     miles: "57", phase: "BASE",     state: "current" },
  { wk: "WEEK 18", dates: "MAY 11 – 17", title: "Specific — block 1.",   desc: "VO2 + longer MP. Saturday test workout.",                miles: "52", phase: "SPECIFIC", state: "future" },
  { wk: "WEEK 19", dates: "MAY 18 – 24", title: "Specific — block 2.",   desc: "Longest MP block of the cycle. Long-run fuel test.",     miles: "55", phase: "SPECIFIC", state: "future" },
  { wk: "WEEK 20", dates: "MAY 25 – 31", title: "Recovery week.",        desc: "Mileage drops 30%. One workout, easy long.",              miles: "38", phase: "RECOVERY", state: "future" },
  { wk: "WEEK 21", dates: "JUN 1 – 7",   title: "Sharpening — block 1.", desc: "Race-pace simulation Saturday. Goal-pace miles.",        miles: "50", phase: "SHARPEN",  state: "future" },
  { wk: "WEEK 22", dates: "JUN 8 – 14",  title: "Sharpening — block 2.", desc: "Final tune-up race or simulation.",                       miles: "44", phase: "SHARPEN",  state: "future" },
  { wk: "WEEK 23", dates: "JUN 15 – 21", title: "Taper — opening.",      desc: "Mileage drops, intensity stays. Don't add anything new.", miles: "36", phase: "TAPER",    state: "future" },
  { wk: "WEEK 24", dates: "JUN 22 – 28", title: "Race week.",            desc: "Two easy 4s, Saturday shakeout, race Sunday.",            miles: "30", phase: "RACE",     state: "future" },
];

const PlanScreen = ({ onOpenDay, onOpenRace, onOpenHistory, embed = false }) => {
  const [mode, setMode] = React.useState("week");
  const [weekIdx, setWeekIdx] = React.useState(0);

  // Highlight the current week regardless of weekIdx — for the demo
  // we always show Week 17.
  const totalMiles = PLAN_WEEK.reduce((s, d) => s + (parseFloat(d.miles) || 0), 0).toFixed(1);
  const doneMiles  = PLAN_WEEK.filter(d => d.state === "done").reduce((s, d) => s + (parseFloat(d.miles) || 0), 0).toFixed(1);

  // Body — pace ladder, week/month toggle, day rows. Shared between
  // the standalone view (page-shell + hero + body) and embed mode
  // (just the body, hosted inside another tab's segmenter).
  const body = (
    <>
      {/* Pace ladder */}
      <div className="prd-plan__ladder">
        {[
          { l: "EASY",      p: "7:30" },
          { l: "MARATHON",  p: "7:15" },
          { l: "THRESHOLD", p: "6:18" },
          { l: "INTERVAL",  p: "5:42" },
        ].map((p, i) => (
          <div key={i} className="prd-plan__ladder-cell">
            <span className="prd-plan__ladder-label">{p.l}</span>
            <span className="prd-plan__ladder-pace">{p.p}</span>
            <span className="prd-plan__ladder-unit">/ MI</span>
          </div>
        ))}
      </div>

      {/* Mode toggle */}
      <div className="prd-plan__mode">
        <button
          className={"prd-plan__mode-btn" + (mode === "week" ? " is-active" : "")}
          onClick={() => setMode("week")}
        >Week</button>
        <button
          className={"prd-plan__mode-btn" + (mode === "month" ? " is-active" : "")}
          onClick={() => setMode("month")}
        >Block</button>
      </div>

      {mode === "week" ? (
        <React.Fragment>
          {/* Week nav */}
          <div className="prd-plan__weeknav">
            <span className="prd-plan__weeknav-arrow" onClick={() => setWeekIdx(i => i - 1)}>←</span>
            <div>
              <div className="prd-plan__weeknav-label">WEEK 17  ·  MAY 4 – MAY 10</div>
              <div className="prd-plan__weeknav-sub">
                {doneMiles} / {totalMiles} MI&nbsp;&nbsp;·&nbsp;&nbsp;BASE — BLOCK 3
              </div>
            </div>
            <span className="prd-plan__weeknav-arrow" onClick={() => setWeekIdx(i => i + 1)}>→</span>
          </div>

          <Hairline />

          {/* Day rows */}
          <div>
            {PLAN_WEEK.map(d => (
              <div
                key={d.id}
                className={
                  "prd-plan__day" +
                  (d.state === "today" ? " is-today" : "") +
                  (d.state === "done"  ? " is-done"  : "") +
                  (d.state === "rest"  ? " is-rest"  : "")
                }
                onClick={() => d.state !== "rest" && onOpenDay && onOpenDay(d)}
              >
                <div>
                  <div className="prd-plan__day-day">{d.day}</div>
                  <div className="prd-plan__day-date">{d.date}</div>
                </div>
                <div>
                  <div className="prd-plan__day-type">{d.type}</div>
                  <div className="prd-plan__day-name">{d.name}</div>
                  <div className="prd-plan__day-desc">{d.desc}</div>
                </div>
                <div className="prd-plan__day-rhs">
                  <div className="prd-plan__day-dist">{d.miles === "—" ? "—" : `${d.miles} mi`}</div>
                  <div className="prd-plan__day-dur">{d.dur}</div>
                </div>
              </div>
            ))}
          </div>

          <div style={{ marginTop: 16, display: "flex", justifyContent: "space-between", paddingTop: 14, borderTop: "1px solid var(--rule)" }}>
            <span className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }}>Adjust week ↗</span>
            <span className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }} onClick={onOpenHistory}>View history ↗</span>
          </div>
        </React.Fragment>
      ) : (
        <React.Fragment>
          <div className="prd-plan__weeknav">
            <span className="prd-plan__weeknav-arrow" />
            <div>
              <div className="prd-plan__weeknav-label">8 WEEKS  ·  MAY 4 – JUN 28</div>
              <div className="prd-plan__weeknav-sub">
                352 MI PLANNED&nbsp;&nbsp;·&nbsp;&nbsp;4 BLOCKS&nbsp;&nbsp;·&nbsp;&nbsp;BOSTON
              </div>
            </div>
            <span className="prd-plan__weeknav-arrow" />
          </div>
          <Hairline />
          <div>
            {PLAN_BLOCKS.map((b, i) => (
              <div
                key={i}
                className={
                  "prd-plan__week" +
                  (b.state === "current" ? " is-current" : "") +
                  (b.state === "done"    ? " is-done"    : "")
                }
                onClick={() => setMode("week")}
              >
                <div>
                  <div className="prd-plan__week-num">{b.wk}</div>
                  <div className="prd-plan__week-dates">{b.dates}</div>
                </div>
                <div>
                  <div className="prd-plan__week-title">{b.title}</div>
                  <div className="prd-plan__week-desc">{b.desc}</div>
                </div>
                <div className="prd-plan__week-rhs">
                  <div className="prd-plan__week-miles">{b.miles} MI</div>
                  <div className="prd-plan__week-phase">{b.phase}</div>
                </div>
              </div>
            ))}
          </div>
        </React.Fragment>
      )}

      <div style={{ height: 24 }} />
    </>
  );

  // Embed mode — host (Train's PLAN segmenter) supplies its own
  // PlateStrip + header. We just render the styles and the body.
  if (embed) {
    return (
      <>
        <style>{PLAN_SCREEN_CSS}</style>
        {body}
      </>
    );
  }

  return (
    <div className="page">
      <style>{PLAN_SCREEN_CSS}</style>
      <PlateStrip surface="PLAN · MARATHON BLOCK" fig="FIG. 33" />

      <div className="page__body">
        {/* Hero */}
        <div className="section section--first">
          <Eyebrow coral>YOUR PLAN&nbsp;&nbsp;·&nbsp;&nbsp;WK 09 OF 16</Eyebrow>
          <div className="prd-plan__hero" style={{ marginTop: 6 }}>
            <div>
              <h1 className="prd-plan__hero-headline">Marathon block.</h1>
              <div className="prd-plan__hero-meta">
                BOSTON&nbsp;&nbsp;·&nbsp;&nbsp;MAY 18&nbsp;&nbsp;·&nbsp;&nbsp;47 DAYS OUT
              </div>
            </div>
            <div className="prd-plan__hero-rhs" onClick={onOpenRace} style={{ cursor: "pointer" }}>
              <div className="prd-plan__hero-target">3:10:00</div>
              <div className="prd-plan__hero-target-label">GOAL ↗</div>
            </div>
          </div>
        </div>

        {body}
      </div>
    </div>
  );
};

window.PlanScreen = PlanScreen;
