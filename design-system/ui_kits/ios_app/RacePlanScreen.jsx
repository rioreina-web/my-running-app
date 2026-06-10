// Post Run Drip · iOS UI kit · Race Plan sheet
//
// Race-day cockpit for the upcoming target race. Reached from the
// Training screen GOAL row ("Sub-3:10 · May 18 · 47 DAYS OUT"). Mirrors
// the editorial DNA of WorkoutDetailScreen — stat strip, narrated charts,
// splits table — but everything is forecast, not retrospective.

const RACE_CSS = `
.prd-race__count {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  padding: 14px 0;
  border-top: 1px solid var(--rule);
  border-bottom: 1px solid var(--rule);
}
.prd-race__count-cell {
  display: flex; flex-direction: column; align-items: center; gap: 4px;
  border-right: 1px solid var(--rule);
}
.prd-race__count-cell:last-child { border-right: 0; }
.prd-race__count-num {
  font-family: var(--font-mono);
  font-weight: 600; font-size: 26px;
  color: var(--ink);
  font-variant-numeric: tabular-nums;
  line-height: 1;
}
.prd-race__count-lbl {
  font-family: var(--font-mono);
  font-size: 9px; letter-spacing: 0.12em;
  color: var(--ink-2); text-transform: uppercase;
}
.prd-race__split {
  display: grid;
  grid-template-columns: 28px 56px 1fr 50px 36px;
  align-items: center;
  gap: 10px;
  padding: 9px 0;
  border-bottom: 1px solid var(--rule);
  font-family: var(--font-mono);
  font-variant-numeric: tabular-nums;
}
.prd-race__split:last-child { border-bottom: 0; }
.prd-race__split-mi   { font-size: 11px; color: var(--ink-2); }
.prd-race__split-pace { font-size: 13px; font-weight: 600; color: var(--ink); }
.prd-race__split-bar  { height: 6px; background: var(--paper-deep); border-radius: 999px; overflow: hidden; }
.prd-race__split-bar-fill { height: 100%; background: var(--ink); }
.prd-race__split.is-fast .prd-race__split-bar-fill { background: var(--coral); }
.prd-race__split-elev { font-size: 11px; color: var(--ink-3); text-align: right; }
.prd-race__split-cum  { font-size: 11px; color: var(--ink-2); text-align: right; }

.prd-race__phase {
  padding: 12px 0;
  border-bottom: 1px solid var(--rule);
}
.prd-race__phase:last-child { border-bottom: 0; }
.prd-race__phase-head {
  display: flex; justify-content: space-between; align-items: baseline;
}
.prd-race__phase-num {
  font-family: var(--font-mono);
  font-size: 10px; letter-spacing: 0.14em;
  color: var(--coral); text-transform: uppercase;
}
.prd-race__phase-name {
  font-family: var(--font-display);
  font-weight: 700; font-size: 18px;
  color: var(--ink); margin-top: 2px;
}
.prd-race__phase-meta {
  font-family: var(--font-mono);
  font-size: 10px; color: var(--ink-2);
  letter-spacing: 0.10em; text-transform: uppercase;
  font-variant-numeric: tabular-nums;
}
.prd-race__phase-note {
  font-family: var(--font-body); font-style: italic;
  font-size: 13px; color: var(--ink-2);
  margin-top: 6px;
}

.prd-race__taper {
  display: grid; grid-template-columns: repeat(3, 1fr); gap: 0;
  border: 1px solid var(--rule);
  border-radius: 8px;
  overflow: hidden;
}
.prd-race__taper-week {
  padding: 12px;
  border-right: 1px solid var(--rule);
  display: flex; flex-direction: column; gap: 6px;
}
.prd-race__taper-week:last-child { border-right: 0; }
.prd-race__taper-wk {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.12em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-race__taper-miles {
  font-family: var(--font-mono); font-weight: 600;
  font-size: 22px; color: var(--ink);
  font-variant-numeric: tabular-nums;
  display: flex; align-items: baseline; gap: 4px;
}
.prd-race__taper-miles span {
  font-size: 10px; color: var(--ink-2); font-weight: 500;
}
.prd-race__taper-note {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.08em; color: var(--ink-3);
  text-transform: uppercase;
}
.prd-race__taper-week.is-race {
  background: rgba(212,89,42,0.06);
}
.prd-race__taper-week.is-race .prd-race__taper-wk,
.prd-race__taper-week.is-race .prd-race__taper-note { color: var(--coral); }

.prd-race__check {
  display: grid; grid-template-columns: 14px 1fr auto;
  align-items: center; gap: 12px;
  padding: 10px 0;
  border-bottom: 1px solid var(--rule);
  cursor: pointer;
}
.prd-race__check:last-child { border-bottom: 0; }
.prd-race__check-box {
  width: 14px; height: 14px; border-radius: 3px;
  border: 1.5px solid var(--ink-3); box-sizing: border-box;
}
.prd-race__check.is-on .prd-race__check-box {
  background: var(--coral); border-color: var(--coral);
  position: relative;
}
.prd-race__check.is-on .prd-race__check-box::after {
  content: ""; position: absolute; top: 1px; left: 4px;
  width: 4px; height: 7px;
  border: 1.5px solid #fff; border-top: 0; border-left: 0;
  transform: rotate(45deg);
}
.prd-race__check-label {
  font-family: var(--font-body); font-size: 14px;
  color: var(--ink);
}
.prd-race__check.is-on .prd-race__check-label {
  color: var(--ink-3); text-decoration: line-through;
}
.prd-race__check-tag {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.10em; color: var(--ink-3);
  text-transform: uppercase;
}
`;

// Strategic splits — 5-mile checkpoints for a 26.2 marathon plan.
// "rel" = 0..1 relative shading; "fast" = highlighted mile.
const RACE_SPLITS = [
  { mi: "1–5",   pace: "7:18", rel: 0.40, elev: "+45 ft",  cum: "36:30", note: "Hold back" },
  { mi: "6–10",  pace: "7:14", rel: 0.55, elev: "+22 ft",  cum: "1:12:36", note: "Settle in" },
  { mi: "11–15", pace: "7:12", rel: 0.60, elev: "−18 ft",  cum: "1:48:36", note: "Locked in", fast: true },
  { mi: "16–20", pace: "7:14", rel: 0.55, elev: "+86 ft",  cum: "2:24:50", note: "Stay patient" },
  { mi: "21–26", pace: "7:08", rel: 0.70, elev: "−54 ft",  cum: "3:09:30", note: "Empty the tank", fast: true },
  { mi: ".2",    pace: "6:42", rel: 0.85, elev: "+0 ft",   cum: "3:10:51", note: "Finish",         fast: true },
];

const RACE_PHASES = [
  { num: "PHASE 01", name: "Hold back.",       miles: "MI 1 – 6",   pace: "7:18 / mi", note: "Adrenaline says go. Resist. Aim for 5–10s/mi slower than goal pace for the first 5K." },
  { num: "PHASE 02", name: "Settle in.",       miles: "MI 6 – 16",  pace: "7:14 / mi", note: "Goal pace. Drink at every aid station — 4–6oz fluid, gel at mile 8 and 14." },
  { num: "PHASE 03", name: "Stay patient.",    miles: "MI 16 – 20", pace: "7:14 / mi", note: "The Newton hills. Run by effort, not pace — let the watch drift +5–10s/mi if it has to." },
  { num: "PHASE 04", name: "Empty the tank.",  miles: "MI 20 – 26.2", pace: "≤ 7:10 / mi", note: "Heartbreak is behind you. Every mile faster from here is fitness, not luck." },
];

const TAPER_WEEKS = [
  { wk: "WK 13 · CUTBACK",   miles: 42, label: "Last long run" },
  { wk: "WK 14 · TAPER",     miles: 32, label: "Sharpen, don't sharpen" },
  { wk: "WK 15 · RACE WEEK", miles: 18, label: "MAY 17 · RACE −1", race: true },
];

const KIT_DEFAULT = [
  { id: "k1", label: "Race kit set out the night before", tag: "−1" },
  { id: "k2", label: "Two gels in shorts, two pinned on bib", tag: "−1" },
  { id: "k3", label: "Watch charged + AM workout file synced", tag: "−1" },
  { id: "k4", label: "Bib, chip, safety pins", tag: "RACE" },
  { id: "k5", label: "Race-flats — Vaporfly 3 (already broken in)", tag: "RACE" },
  { id: "k6", label: "Throwaway long-sleeve for the corral", tag: "RACE" },
  { id: "k7", label: "Bagel + black coffee, 3hr before gun", tag: "+0" },
  { id: "k8", label: "Mile 13 gel, mile 18 gel, mile 22 caffeine gel", tag: "+0" },
];

const RacePlanScreen = ({ onClose }) => {
  const [checks, setChecks] = React.useState({});
  const toggle = (id) => setChecks(c => ({ ...c, [id]: !c[id] }));
  const done = Object.values(checks).filter(Boolean).length;

  return (
    <div className="page">
      <style>{RACE_CSS}</style>
      <PlateStrip surface="RACE PLAN · TARGET" fig="FIG. 31" />
      <div className="page__body">
        {/* Sheet chrome */}
        <div style={{ display: "flex", justifyContent: "space-between", paddingTop: 0 }}>
          <a className="link" onClick={onClose} style={{ fontSize: 13 }}>Back</a>
          <a className="link" style={{ fontSize: 13 }}>Share</a>
        </div>

        {/* Title */}
        <div className="section section--first" style={{ marginTop: 14 }}>
          <Eyebrow coral>TARGET RACE&nbsp;&nbsp;·&nbsp;&nbsp;MARATHON</Eyebrow>
          <h1 className="h-display" style={{ fontSize: 32 }}>Boston, May 18.</h1>
          <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
            — Hopkinton to Boylston. Wave 2, corral 4. Bib #14782. —
          </div>
        </div>

        {/* Countdown */}
        <div style={{ height: 16 }} />
        <div className="prd-race__count">
          {[
            { n: "47",  l: "DAYS" },
            { n: "06",  l: "WEEKS" },
            { n: "AM",  l: "10:00 START" },
            { n: "62°", l: "FORECAST" },
          ].map((c, i) => (
            <div key={i} className="prd-race__count-cell">
              <span className="prd-race__count-num">{c.n}</span>
              <span className="prd-race__count-lbl">{c.l}</span>
            </div>
          ))}
        </div>

        {/* Goal vs predicted */}
        <Section eyebrow="GOAL  ·  PREDICTED">
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginTop: 4 }}>
            <div className="card" style={{ padding: 14 }}>
              <Eyebrow coral>GOAL</Eyebrow>
              <div style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 26, marginTop: 6, fontVariantNumeric: "tabular-nums" }}>
                3:10:00
              </div>
              <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em", marginTop: 4, textTransform: "uppercase" }}>
                7:15 / MI  ·  BQ −5:00
              </div>
            </div>
            <div className="card" style={{ padding: 14 }}>
              <Eyebrow>PREDICTED</Eyebrow>
              <div style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 26, marginTop: 6, fontVariantNumeric: "tabular-nums" }}>
                3:09:30
              </div>
              <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--mood-energized)", letterSpacing: "0.10em", marginTop: 4, textTransform: "uppercase" }}>
                ON PACE  ·  −0:30 VS GOAL
              </div>
            </div>
          </div>

          <p className="quote" style={{ fontSize: 13, marginTop: 14, marginBottom: 4 }}>
            "Your last three long runs averaged 7:31 — your aerobic ceiling has lifted. Sub-3:10 is well within range if the day is honest."
          </p>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase" }}>
            COACH · APR 27
          </div>
        </Section>

        <Hairline style={{ marginTop: 18 }} />

        {/* Pacing strategy — splits table */}
        <Section eyebrow="PACING STRATEGY  ·  NEGATIVE-SPLIT" eyebrowRight="GOAL 3:10:00">
          <div style={{ marginTop: 6 }}>
            {RACE_SPLITS.map((s, i) => (
              <div key={i} className={"prd-race__split" + (s.fast ? " is-fast" : "")}>
                <span className="prd-race__split-mi">{s.mi}</span>
                <span className="prd-race__split-pace">{s.pace}</span>
                <div className="prd-race__split-bar">
                  <div className="prd-race__split-bar-fill" style={{ width: (s.rel * 100) + "%" }} />
                </div>
                <span className="prd-race__split-elev">{s.elev}</span>
                <span className="prd-race__split-cum">{s.cum}</span>
              </div>
            ))}
          </div>
          <p className="quote" style={{ fontSize: 13, marginTop: 10, marginBottom: 0 }}>
            "Run the first half a hair slow. The Newton hills (16–20) cost you nothing if you start at 7:18. The last 10K is yours."
          </p>
        </Section>

        <Hairline style={{ marginTop: 18 }} />

        {/* Elevation profile */}
        <Section eyebrow="COURSE  ·  ELEVATION" eyebrowRight="HOPKINTON → BOSTON">
          <div style={{ paddingTop: 6 }}>
            <svg viewBox="0 0 280 80" preserveAspectRatio="none" style={{ width: "100%", height: 80 }}>
              {/* Gridline */}
              <line x1="0" y1="68" x2="280" y2="68" stroke="var(--rule)" />
              {/* Net-downhill course with the Newton hills */}
              <path
                d="M 0,38 L 28,46 L 52,52 L 80,58 L 110,62 L 140,55 L 168,42 L 188,30 L 208,38 L 230,48 L 252,58 L 280,66"
                fill="none" stroke="var(--ink)" strokeWidth="1.5" strokeLinejoin="round"
              />
              {/* Newton hills shading */}
              <rect x="140" y="0" width="60" height="80" fill="rgba(212,89,42,0.08)" />
              <text x="170" y="14" fontFamily="ui-monospace" fontSize="8" fill="var(--coral)" textAnchor="middle" letterSpacing="0.05em">NEWTON</text>
              {/* Start & finish dots */}
              <circle cx="0" cy="38" r="3" fill="var(--ink)" />
              <circle cx="280" cy="66" r="3" fill="var(--coral)" />
            </svg>
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 4 }}>
              {[
                { l: "MI 0", v: "490 FT" },
                { l: "MI 16", v: "148 FT" },
                { l: "MI 20", v: "236 FT" },
                { l: "MI 26", v: "10 FT" },
              ].map((p, i) => (
                <div key={i} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 2 }}>
                  <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase" }}>{p.l}</span>
                  <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", fontVariantNumeric: "tabular-nums" }}>{p.v}</span>
                </div>
              ))}
            </div>
          </div>
        </Section>

        <Hairline style={{ marginTop: 18 }} />

        {/* Phases */}
        <Section eyebrow="THE RACE  ·  IN FOUR PHASES">
          <div style={{ marginTop: 4 }}>
            {RACE_PHASES.map((p, i) => (
              <div key={i} className="prd-race__phase">
                <div className="prd-race__phase-head">
                  <div>
                    <div className="prd-race__phase-num">{p.num}</div>
                    <div className="prd-race__phase-name">{p.name}</div>
                  </div>
                  <div style={{ textAlign: "right" }}>
                    <div className="prd-race__phase-meta">{p.miles}</div>
                    <div className="prd-race__phase-meta" style={{ color: "var(--coral)", marginTop: 2 }}>{p.pace}</div>
                  </div>
                </div>
                <div className="prd-race__phase-note">{p.note}</div>
              </div>
            ))}
          </div>
        </Section>

        <Hairline style={{ marginTop: 18 }} />

        {/* Taper plan */}
        <Section eyebrow="TAPER  ·  NEXT 3 WEEKS">
          <div className="prd-race__taper" style={{ marginTop: 6 }}>
            {TAPER_WEEKS.map((w, i) => (
              <div key={i} className={"prd-race__taper-week" + (w.race ? " is-race" : "")}>
                <div className="prd-race__taper-wk">{w.wk}</div>
                <div className="prd-race__taper-miles">{w.miles}<span>mi</span></div>
                <div className="prd-race__taper-note">{w.label}</div>
              </div>
            ))}
          </div>
          <p className="quote" style={{ fontSize: 13, marginTop: 10, marginBottom: 0 }}>
            "Volume drops, intensity stays. Two race-pace MP cuts in week 14 — short, sharp, confidence-building."
          </p>
        </Section>

        <Hairline style={{ marginTop: 18 }} />

        {/* Kit checklist */}
        <Section
          eyebrow="RACE-WEEK CHECKLIST"
          eyebrowRight={<span style={{ color: "var(--coral)" }}>{done} / {KIT_DEFAULT.length}</span>}
        >
          <div style={{ marginTop: 4 }}>
            {KIT_DEFAULT.map(k => (
              <div
                key={k.id}
                className={"prd-race__check" + (checks[k.id] ? " is-on" : "")}
                onClick={() => toggle(k.id)}
              >
                <div className="prd-race__check-box" />
                <div className="prd-race__check-label">{k.label}</div>
                <div className="prd-race__check-tag">{k.tag}</div>
              </div>
            ))}
          </div>
        </Section>

        <Hairline style={{ marginTop: 18 }} />

        {/* Footnote */}
        <Section eyebrow="LAST UPDATED">
          <p className="quote" style={{ fontSize: 13, marginTop: 4, marginBottom: 4 }}>
            Plan revised after the Apr 26 long run · 18mi @ 7:32.
          </p>
          <div style={{ display: "flex", gap: 14, marginTop: 8 }}>
            <span className="link" style={{ fontSize: 13 }}>Edit plan ↗</span>
            <span className="link" style={{ fontSize: 13 }}>Add to calendar ↗</span>
          </div>
        </Section>

        <div style={{ height: 32 }} />
      </div>
    </div>
  );
};

window.RacePlanScreen = RacePlanScreen;
