// Post Run Drip · iOS UI kit · Weekly Review sheet
//
// The full "weekly report" the coach references in CoachScreen.jsx. Reached
// from the "Read the report ↗" link on the Coach tab card.
//
// Editorial structure: dateline, lede headline, coach blockquote opener,
// stat strip, "What worked / what didn't" two-column, training-load chart,
// session-by-session table, and a "Next week" forecast block.

const WREVIEW_CSS = `
.prd-wrv__divider {
  display: flex; align-items: center; gap: 10px;
  font-family: var(--font-mono); font-size: 10px;
  letter-spacing: 0.14em; color: var(--ink-3);
  text-transform: uppercase;
  margin: 22px 0 14px 0;
}
.prd-wrv__divider::before,
.prd-wrv__divider::after {
  content: ""; flex: 1; height: 1px; background: var(--rule);
}

.prd-wrv__verdict {
  display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
  margin-top: 6px;
}
.prd-wrv__verdict-card {
  border: 1px solid var(--rule);
  border-radius: 8px;
  padding: 14px;
  display: flex; flex-direction: column; gap: 8px;
}
.prd-wrv__verdict-eyebrow {
  font-family: var(--font-mono); font-size: 10px;
  letter-spacing: 0.14em; text-transform: uppercase;
}
.prd-wrv__verdict-eyebrow.is-pos { color: var(--mood-energized); }
.prd-wrv__verdict-eyebrow.is-neg { color: var(--coral); }
.prd-wrv__verdict-card ul {
  margin: 0; padding-left: 16px;
  font-family: var(--font-body); font-size: 13px;
  line-height: 1.5; color: var(--ink);
}
.prd-wrv__verdict-card li { padding-bottom: 4px; }
.prd-wrv__verdict-card li::marker { color: var(--ink-3); }

.prd-wrv__session {
  display: grid;
  grid-template-columns: 44px 1fr 64px;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid var(--rule);
}
.prd-wrv__session:last-child { border-bottom: 0; }
.prd-wrv__session-day {
  font-family: var(--font-mono); font-size: 11px;
  font-weight: 600; letter-spacing: 0.10em;
  color: var(--ink-2); text-transform: uppercase;
}
.prd-wrv__session-type {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.12em; color: var(--ink-3);
  text-transform: uppercase; margin-top: 4px;
}
.prd-wrv__session-name {
  font-family: var(--font-display);
  font-weight: 700; font-size: 16px;
  color: var(--ink); margin-top: 2px;
}
.prd-wrv__session-note {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-2); margin-top: 4px;
}
.prd-wrv__session-stat {
  font-family: var(--font-mono);
  font-variant-numeric: tabular-nums;
  text-align: right;
}
.prd-wrv__session-stat-v {
  font-weight: 600; font-size: 14px; color: var(--ink);
}
.prd-wrv__session-stat-u {
  font-size: 9px; letter-spacing: 0.10em;
  color: var(--ink-3); text-transform: uppercase;
}
.prd-wrv__session.is-key .prd-wrv__session-name { color: var(--coral); }

.prd-wrv__bar {
  display: flex; height: 10px; border-radius: 2px;
  overflow: hidden; margin-top: 6px;
}
.prd-wrv__legend {
  display: flex; gap: 14px; margin-top: 8px;
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-wrv__legend-dot {
  display: inline-block; width: 7px; height: 7px;
  border-radius: 2px; margin-right: 6px;
  vertical-align: middle;
}

.prd-wrv__next-card {
  background: var(--ink);
  color: var(--paper);
  border-radius: 12px;
  padding: 18px;
  margin-top: 6px;
}
.prd-wrv__next-card .eyebrow { color: rgba(245,243,240,0.65); }
.prd-wrv__next-card .h-display { color: var(--paper); }
.prd-wrv__next-card .body-sm { color: rgba(245,243,240,0.75); }
.prd-wrv__next-row {
  display: grid; grid-template-columns: repeat(3, 1fr);
  margin-top: 14px;
  border-top: 1px solid rgba(245,243,240,0.18);
  padding-top: 12px;
}
.prd-wrv__next-row .cell {
  display: flex; flex-direction: column; gap: 4px;
  border-right: 1px solid rgba(245,243,240,0.18);
  padding-right: 10px;
}
.prd-wrv__next-row .cell:last-child { border-right: 0; padding-right: 0; }
.prd-wrv__next-row .l {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.12em; color: rgba(245,243,240,0.55);
  text-transform: uppercase;
}
.prd-wrv__next-row .v {
  font-family: var(--font-mono); font-weight: 600;
  font-size: 18px; color: var(--paper);
  font-variant-numeric: tabular-nums;
}
.prd-wrv__next-row .s {
  font-family: var(--font-mono); font-size: 9px;
  color: rgba(245,243,240,0.55);
}
`;

const WREVIEW_STATS = [
  { l: "MILES",     v: "47.2",  s: "+8% W/W"        },
  { l: "SESSIONS",  v: "5 / 5", s: "1 KEY · 4 SUPP" },
  { l: "TIME",      v: "5:54",  s: "ON FEET"        },
  { l: "AVG HR",    v: "144",   s: "Z2 · −2 BPM"    },
];

const WREVIEW_WORKED = [
  "Easy paces settled — 7:32 avg on Sunday's 18mi long.",
  "Tuesday tempo: hit 6:18 for 4mi, HR ceiling held at 162.",
  "Sleep 7h12m avg — first +7 week of the block.",
];
const WREVIEW_FALTERED = [
  "Knee tightness Mon → Tue. Swap held; pain gone by Thu.",
  "Friday's cadence drifted to 172 — fatigue tell.",
  "Caffeine after 2pm three days running. Watch it.",
];

const WREVIEW_SESSIONS = [
  { day: "MON", type: "RECOVERY", name: "Easy 6.",      note: "HR 137. Held back as planned.",                    stat: "6.0", unit: "MI",     key: false },
  { day: "TUE", type: "QUALITY",  name: "Tempo 4 × 1mi.", note: "Fastest set 6:14. Strong, controlled.",          stat: "8.0", unit: "MI",     key: true  },
  { day: "WED", type: "REST",     name: "Rest day.",    note: "Mobility 25min. Knee fine by evening.",             stat: "—",   unit: "",       key: false },
  { day: "THU", type: "RECOVERY", name: "Easy 5.",      note: "Aerobic strong. Drift +2.8%.",                      stat: "5.0", unit: "MI",     key: false },
  { day: "FRI", type: "RECOVERY", name: "Easy 8.",      note: "Cadence 172 → slow it next time.",                  stat: "8.0", unit: "MI",     key: false },
  { day: "SUN", type: "LONG",     name: "Long 18.",     note: "Felt strong through 14. Last 4mi @ 7:18 — boom.",   stat: "18.0",unit: "MI",     key: true  },
];

const WeeklyReviewScreen = ({ onClose }) => {
  return (
    <div className="page">
      <style>{WREVIEW_CSS}</style>
      <PlateStrip surface="WEEKLY REVIEW · FROM COACH" fig="FIG. 32" />
      <div className="page__body">
        {/* Sheet chrome */}
        <div style={{ display: "flex", justifyContent: "space-between", paddingTop: 0 }}>
          <a className="link" onClick={onClose} style={{ fontSize: 13 }}>Back</a>
          <a className="link" style={{ fontSize: 13 }}>Share</a>
        </div>

        {/* Dateline */}
        <div className="section section--first" style={{ marginTop: 14 }}>
          <Eyebrow coral>WEEKLY REPORT&nbsp;&nbsp;·&nbsp;&nbsp;WEEK 17</Eyebrow>
          <h1 className="h-display" style={{ fontSize: 30 }}>The base is taking.</h1>
          <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
            — Apr 28 – May 4 · marathon block, week 9 of 16. —
          </div>
        </div>

        {/* Coach blockquote opener */}
        <div style={{ marginTop: 14 }}>
          <CoachQuote>
            Three good weeks in a row. Easy paces have settled a beat slower without losing fitness — that's the signal the aerobic base is taking. Hold the volume; the next test is Wednesday's MP block.
          </CoachQuote>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", marginTop: 6, textTransform: "uppercase" }}>
            COACH · SUN 7:42 PM · 4 MIN READ
          </div>
        </div>

        <Hairline style={{ marginTop: 18 }} />

        {/* Stat strip */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", padding: "14px 0", borderBottom: "1px solid var(--rule)" }}>
          {WREVIEW_STATS.map((s, i) => (
            <div key={i} style={{
              borderRight: i < 3 ? "1px solid var(--rule)" : 0,
              display: "flex", flexDirection: "column", gap: 4,
              paddingLeft: i === 0 ? 0 : 12, paddingRight: 12,
            }}>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>{s.l}</span>
              <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 20, color: "var(--ink)", fontVariantNumeric: "tabular-nums" }}>{s.v}</span>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.08em", textTransform: "uppercase" }}>{s.s}</span>
            </div>
          ))}
        </div>

        {/* Load chart */}
        <Section eyebrow="TRAINING LOAD · 4-WEEK ROLLING" eyebrowRight="ACWR 1.12 · GREEN">
          <div style={{ paddingTop: 6 }}>
            <svg viewBox="0 0 280 110" preserveAspectRatio="none" style={{ width: "100%", height: 110 }}>
              {/* Sweet-spot band */}
              <rect x="0" y="46" width="280" height="22" fill="rgba(45,138,78,0.10)" />
              <text x="6" y="42" fontFamily="ui-monospace" fontSize="8" fill="var(--mood-energized)">SWEET SPOT 0.8–1.3</text>

              {/* Chronic line */}
              <polyline points="0,70 35,68 70,64 105,60 140,57 175,55 210,52 245,50 280,48"
                fill="none" stroke="var(--ink)" strokeWidth="1.5" strokeLinejoin="round" />
              {/* Acute line */}
              <polyline points="0,80 35,74 70,72 105,62 140,68 175,52 210,46 245,54 280,42"
                fill="none" stroke="var(--coral)" strokeWidth="1.5" strokeLinejoin="round" />
              <circle cx="280" cy="42" r="3.5" fill="var(--coral)" />
            </svg>
            <div className="prd-wrv__legend">
              <span><span className="prd-wrv__legend-dot" style={{ background: "var(--ink)" }} />CHRONIC</span>
              <span><span className="prd-wrv__legend-dot" style={{ background: "var(--coral)" }} />ACUTE</span>
              <span style={{ marginLeft: "auto", color: "var(--ink-3)" }}>9 WK</span>
            </div>
          </div>
          <p className="quote" style={{ fontSize: 13, marginTop: 10, marginBottom: 0 }}>
            "Acute is +18% above chronic — exactly where we want it 6 weeks out. One more progressive week, then the cutback."
          </p>
        </Section>

        <div className="prd-wrv__divider">VERDICT</div>

        {/* What worked / faltered */}
        <div className="prd-wrv__verdict">
          <div className="prd-wrv__verdict-card">
            <div className="prd-wrv__verdict-eyebrow is-pos">+ WHAT WORKED</div>
            <ul>
              {WREVIEW_WORKED.map((l, i) => <li key={i}>{l}</li>)}
            </ul>
          </div>
          <div className="prd-wrv__verdict-card">
            <div className="prd-wrv__verdict-eyebrow is-neg">− WHAT FALTERED</div>
            <ul>
              {WREVIEW_FALTERED.map((l, i) => <li key={i}>{l}</li>)}
            </ul>
          </div>
        </div>

        <Hairline style={{ marginTop: 18 }} />

        {/* Session-by-session */}
        <Section eyebrow="SESSION × SESSION" eyebrowRight="5 RUNS · 47.2 MI">
          <div style={{ marginTop: 4 }}>
            {WREVIEW_SESSIONS.map((s, i) => (
              <div key={i} className={"prd-wrv__session" + (s.key ? " is-key" : "")}>
                <div>
                  <div className="prd-wrv__session-day">{s.day}</div>
                  <div className="prd-wrv__session-type">{s.type}</div>
                </div>
                <div>
                  <div className="prd-wrv__session-name">{s.name}</div>
                  <div className="prd-wrv__session-note">{s.note}</div>
                </div>
                <div className="prd-wrv__session-stat">
                  <div className="prd-wrv__session-stat-v">{s.stat}</div>
                  <div className="prd-wrv__session-stat-u">{s.unit}</div>
                </div>
              </div>
            ))}
          </div>
        </Section>

        <Hairline style={{ marginTop: 18 }} />

        {/* Pace distribution bar */}
        <Section eyebrow="PACE DISTRIBUTION" eyebrowRight="WEEK 17">
          <div className="prd-wrv__bar">
            <div style={{ background: "var(--mood-energized)", width: "62%" }} />
            <div style={{ background: "var(--ink-2)", width: "20%" }} />
            <div style={{ background: "var(--coral)", width: "12%" }} />
            <div style={{ background: "var(--ink)", width: "6%" }} />
          </div>
          <div className="prd-wrv__legend" style={{ flexWrap: "wrap" }}>
            <span><span className="prd-wrv__legend-dot" style={{ background: "var(--mood-energized)" }} />EASY 62%</span>
            <span><span className="prd-wrv__legend-dot" style={{ background: "var(--ink-2)" }} />STEADY 20%</span>
            <span><span className="prd-wrv__legend-dot" style={{ background: "var(--coral)" }} />THRESHOLD 12%</span>
            <span><span className="prd-wrv__legend-dot" style={{ background: "var(--ink)" }} />VO2 6%</span>
          </div>
          <p className="quote" style={{ fontSize: 13, marginTop: 10, marginBottom: 0 }}>
            "82% easy/steady — textbook polarized. We earned the threshold work this week."
          </p>
        </Section>

        <div className="prd-wrv__divider">NEXT WEEK</div>

        {/* Next week card — dark */}
        <div className="prd-wrv__next-card">
          <Eyebrow>FORECAST  ·  WEEK 18</Eyebrow>
          <div className="h-display" style={{ fontSize: 22, marginTop: 6 }}>Hold the volume.</div>
          <p className="body-sm" style={{ marginTop: 8 }}>
            One key session — Wednesday MP block (3 × 2mi @ 7:05). Long run sticks at 18mi. Friday off entirely if Thursday lingers.
          </p>
          <div className="prd-wrv__next-row">
            <div className="cell">
              <span className="l">MILES</span>
              <span className="v">48</span>
              <span className="s">+2 W/W</span>
            </div>
            <div className="cell">
              <span className="l">KEY DAY</span>
              <span className="v">WED</span>
              <span className="s">MP BLOCK</span>
            </div>
            <div className="cell">
              <span className="l">LONG</span>
              <span className="v">18</span>
              <span className="s">SUN · MI</span>
            </div>
          </div>
        </div>

        <div style={{ marginTop: 16, display: "flex", gap: 14 }}>
          <span className="link" style={{ fontSize: 13 }}>Reply to coach ↗</span>
          <span className="link" style={{ fontSize: 13 }}>View plan ↗</span>
        </div>

        <div style={{ height: 32 }} />
      </div>
    </div>
  );
};

window.WeeklyReviewScreen = WeeklyReviewScreen;
