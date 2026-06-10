// Post Run Drip · iOS UI kit · Injuries screen (Plate 28 — "Active aches")

const DOTS_14 = [false, true, false, false, true, true, false, false, false, true, false, false, false, true];
const ACHILLES_DOTS = [false, true, false, true, true, false, true, false, true, false, true, true, false, true];

const InjuryRow = ({ name, side, days, mentions, miles, load, trend, trendClass, dots, lastQuote, firstLine }) => (
  <div className="injury">
    <div className="injury-head">
      <span className="injury-name">{name}</span>
      <span className="injury-score">{mentions} / 10</span>
    </div>
    <div className="injury-meta">
      <span>{side}</span><span>·</span><span>ACTIVE</span><span>·</span><span>{days}d</span>
    </div>
    <div className="injury-stats">
      <div className="ist"><span className="ilbl">MENTIONS</span><span className="ival">{mentions}×</span></div>
      <div className="ist"><span className="ilbl">AVG VOL</span><span className="ival">{miles} mi</span></div>
      <div className="ist"><span className="ilbl">AVG LOAD</span><span className="ival">{load}</span></div>
      <div className="ist"><span className="ilbl">TREND</span><span className={"ival " + trendClass}>{trend}</span></div>
    </div>
    <div>
      <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase", marginTop: 8 }}>
        MENTIONS · LAST 14 DAYS
      </div>
      <div className="dot-line">
        {dots.map((on, i) => <span key={i} className={"d" + (on ? " on" : "")}></span>)}
      </div>
    </div>
    <div style={{ marginTop: 6 }}>
      <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>LAST MENTIONED</div>
      <p className="quote" style={{ fontSize: 14, marginTop: 4, marginBottom: 0 }}>"{lastQuote}"</p>
      <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", marginTop: 6 }}>{firstLine}</div>
    </div>
    <div style={{ display: "flex", gap: 16, marginTop: 4 }}>
      <a className="link" style={{ fontSize: 12 }}>View detail</a>
      <a className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }}>Update</a>
      <a className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }}>Mark resolved</a>
    </div>
  </div>
);

const InjuriesScreen = ({ onClose }) => (
  <div className="page">
    <PlateStrip surface="INJURY · LIVING LOG" fig="FIG. 28" />
    <div className="page__body">
      <div style={{ display: "flex", justifyContent: "space-between" }}>
        <a className="link" onClick={onClose} style={{ fontSize: 13 }}>Close</a>
        <Eyebrow>INJURIES</Eyebrow>
        <a className="link" style={{ fontSize: 13 }}>+ Add</a>
      </div>

      <div className="section section--first" style={{ marginTop: 14 }}>
        <Eyebrow coral>TRACKING NOW · 2</Eyebrow>
        <h1 className="h-display" style={{ fontSize: 28 }}>Active aches</h1>
        <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", margin: "4px 0 0 0" }}>
          Not medical advice. If anything gets sharper, see a clinician.
        </p>
      </div>

      <Hairline style={{ marginTop: 14 }} />

      <InjuryRow
        name="Knee" side="LEFT" days={5}
        mentions={4} miles={7} load={92}
        trend="EASING" trendClass="injury-trend--easing"
        dots={DOTS_14}
        lastQuote="Knee a little tweaky toward the end of the run today."
        firstLine="First came up — Sat May 3, after 8mi long"
      />
      <InjuryRow
        name="Achilles" side="LEFT" days={18}
        mentions={7} miles={9} load={104}
        trend="STEADY" trendClass="injury-trend--steady"
        dots={ACHILLES_DOTS}
        lastQuote="Felt it warming up. Eased after the first mile."
        firstLine="First mentioned — Apr 19, after a tempo session"
      />

      <div style={{ height: 24 }} />
    </div>
  </div>
);

window.InjuriesScreen = InjuriesScreen;
