// Post Run Drip · iOS UI kit · Injury-related sheets
//
// AddInjurySheet      — manually log a new injury
// InjuryDetailSheet   — view + edit a single injury record

const INJURY_SHEETS_CSS = `
.prd-inj__grid {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 8px;
  margin-top: 10px;
}
.prd-inj__area {
  padding: 14px 6px;
  border: 1px solid var(--rule);
  border-radius: 10px;
  background: var(--card);
  text-align: center;
  cursor: pointer;
  font-family: var(--font-display);
  font-size: 13px; font-weight: 600;
  color: var(--ink-2);
  letter-spacing: -0.01em;
}
.prd-inj__area.is-active {
  border-color: var(--coral);
  color: var(--coral);
}
.prd-inj__sev-track {
  height: 4px; border-radius: 999px;
  background: var(--rule);
  position: relative;
  margin-top: 4px;
}
.prd-inj__sev-fill {
  position: absolute; top: 0; left: 0; bottom: 0;
  border-radius: 999px;
  background: var(--coral);
  transition: width .2s ease-out, background .2s ease-out;
}
.prd-inj__sev-input {
  width: 100%;
  -webkit-appearance: none; appearance: none;
  background: transparent;
  height: 32px;
  margin-top: -32px;
  position: relative; z-index: 2;
}
.prd-inj__sev-input::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 22px; height: 22px; border-radius: 999px;
  background: var(--coral);
  border: 3px solid var(--paper);
  box-shadow: 0 1px 4px rgba(0,0,0,0.18);
  cursor: pointer;
}
.prd-inj__sev-input::-moz-range-thumb {
  width: 22px; height: 22px; border-radius: 999px;
  background: var(--coral);
  border: 3px solid var(--paper);
  box-shadow: 0 1px 4px rgba(0,0,0,0.18);
  cursor: pointer;
}
.prd-inj__sev-labels {
  display: flex; justify-content: space-between;
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.10em; text-transform: uppercase;
  margin-top: 6px;
}
.prd-inj__status-row {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 8px;
}
.prd-inj__status {
  padding: 10px 6px;
  border-radius: 999px;
  background: var(--card);
  border: 1px solid var(--rule);
  text-align: center;
  font-family: var(--font-mono); font-size: 11px; font-weight: 500;
  letter-spacing: 0.10em; text-transform: uppercase;
  color: var(--ink-2);
  cursor: pointer;
}
.prd-inj__status.is-active { color: var(--coral); border-color: var(--coral); }
.prd-inj__timeline-row {
  display: grid;
  grid-template-columns: 12px 1fr 80px;
  gap: 10px;
  align-items: baseline;
  padding: 10px 0;
  border-bottom: 1px solid var(--rule);
}
.prd-inj__timeline-dot {
  width: 8px; height: 8px; border-radius: 999px;
  background: var(--coral);
  margin-top: 4px;
}
.prd-inj__timeline-label {
  font-family: var(--font-display); font-size: 14px; font-weight: 500; color: var(--ink);
}
.prd-inj__timeline-meta {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3);
  display: block; margin-top: 2px;
}
.prd-inj__timeline-date {
  font-family: var(--font-mono); font-size: 10px;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
  text-align: right;
  font-variant-numeric: tabular-nums;
}
`;

const BODY_AREAS = [
  "ANKLE", "ACHILLES", "ARCH",
  "CALF", "SHIN", "KNEE",
  "ITB", "QUAD", "HAMSTRING",
  "HIP", "GLUTE", "LOW BACK",
  "FOOT", "TOE", "OTHER",
];
const SIDES = [
  { v: "left", l: "LEFT" },
  { v: "right", l: "RIGHT" },
  { v: "both", l: "BOTH" },
  { v: "unknown", l: "N/A" },
];

const sevColor = (s) => {
  if (s <= 3) return "var(--mood-energized, #2D8A4E)";
  if (s <= 5) return "var(--mood-tired, #C4873A)";
  if (s <= 7) return "var(--mood-struggling, #C45A3A)";
  return "var(--mood-injured, #B83A4A)";
};
const sevLabel = (s) => {
  if (s <= 3) return "MILD";
  if (s <= 5) return "MODERATE";
  if (s <= 7) return "ELEVATED";
  return "SEVERE";
};

// ---- AddInjurySheet ----------------------------------------------------
const AddInjurySheet = ({ onClose, onSave }) => {
  const [area, setArea] = React.useState(null);
  const [side, setSide] = React.useState("unknown");
  const [severity, setSeverity] = React.useState(5);
  const [notes, setNotes] = React.useState("");

  const canSave = !!area;
  return (
    <Sheet
      surface="INJURIES · ADD"
      onClose={onClose}
      action={canSave ? () => { onSave && onSave({ area, side, severity, notes }); onClose && onClose(); } : null}
      actionLabel="Save ↗"
    >
      <style>{INJURY_SHEETS_CSS}</style>

      <Eyebrow coral>ACTIVE ACHES</Eyebrow>
      <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>Log a new ache.</h1>
      <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
        — quick capture. The coach will read it Sunday and adjust the plan if it persists. —
      </p>

      <div className="prd-fieldrow" style={{ borderBottom: 0 }}>
        <span className="prd-fieldrow__label">BODY AREA</span>
        <div className="prd-inj__grid">
          {BODY_AREAS.map(a => (
            <div
              key={a}
              className={"prd-inj__area" + (area === a ? " is-active" : "")}
              onClick={() => setArea(a)}
            >
              {a}
            </div>
          ))}
        </div>
      </div>

      <div className="prd-fieldrow">
        <span className="prd-fieldrow__label">SIDE</span>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr", gap: 8, paddingTop: 4 }}>
          {SIDES.map(s => (
            <div
              key={s.v}
              className={"prd-chip" + (side === s.v ? " is-active" : "")}
              style={{ textAlign: "center" }}
              onClick={() => setSide(s.v)}
            >
              {s.l}
            </div>
          ))}
        </div>
      </div>

      <div className="prd-fieldrow">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <span className="prd-fieldrow__label">SEVERITY</span>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 14, fontWeight: 600,
            letterSpacing: "0.06em",
            color: sevColor(severity),
            fontVariantNumeric: "tabular-nums",
          }}>
            {severity} / 10  ·  {sevLabel(severity)}
          </span>
        </div>
        <div className="prd-inj__sev-track">
          <div
            className="prd-inj__sev-fill"
            style={{ width: ((severity - 1) / 9 * 100) + "%", background: sevColor(severity) }}
          />
        </div>
        <input
          className="prd-inj__sev-input"
          type="range" min="1" max="10" step="1"
          value={severity}
          onChange={(e) => setSeverity(parseInt(e.target.value))}
        />
        <div className="prd-inj__sev-labels" style={{ color: "var(--ink-3)" }}>
          <span>MILD</span><span>MODERATE</span><span>SEVERE</span>
        </div>
      </div>

      <div className="prd-fieldrow">
        <span className="prd-fieldrow__label">NOTES  ·  OPTIONAL</span>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder="What happened? How does it feel?"
          style={{
            width: "100%", minHeight: 100,
            background: "transparent", border: 0, outline: "none", resize: "none",
            fontFamily: "var(--font-body)", fontStyle: notes ? "normal" : "italic",
            fontSize: 14, color: "var(--ink)", padding: 0,
          }}
        />
      </div>

      <div style={{
        marginTop: 8,
        fontFamily: "var(--font-body)", fontStyle: "italic",
        fontSize: 12, color: "var(--ink-3)", lineHeight: 1.5,
      }}>
        — not medical advice. If anything gets sharper, see a clinician. —
      </div>

      <button
        className="btn btn--primary"
        style={{ marginTop: 18, opacity: canSave ? 1 : 0.5 }}
        onClick={() => { if (canSave) { onSave && onSave({ area, side, severity, notes }); onClose && onClose(); } }}
      >
        Add ache
      </button>
    </Sheet>
  );
};

// ---- InjuryDetailSheet -------------------------------------------------
const MOCK_INJURY = {
  area: "ACHILLES",
  side: "left",
  severity: 4,
  status: "monitoring", // active | monitoring | resolved
  firstSeen: "APR 14",
  daysOpen: 24,
  source: "VOICE MEMO",
  notes: "Tight in the morning, loosens after the first half mile. Worse on hills. Rolling and calf raises seem to help.",
  timeline: [
    { date: "MAY 5",  label: "Logged again",   meta: "Mentioned in voice memo · sev 4"  },
    { date: "APR 28", label: "Coach reviewed", meta: "Suggested dropping hill repeats"   },
    { date: "APR 21", label: "Severity drop",  meta: "From 6 → 4 over a week"            },
    { date: "APR 14", label: "First reported", meta: "Voice memo after Sunday long run"  },
  ],
};

const InjuryDetailSheet = ({ injury = MOCK_INJURY, onClose }) => {
  const [status, setStatus] = React.useState(injury.status);
  const [severity, setSeverity] = React.useState(injury.severity);
  const [notes, setNotes] = React.useState(injury.notes);

  const statuses = [
    { v: "active",     l: "ACTIVE" },
    { v: "monitoring", l: "MONITORING" },
    { v: "resolved",   l: "RESOLVED" },
  ];

  return (
    <Sheet
      surface={`INJURY · ${injury.area}`}
      onClose={onClose}
    >
      <style>{INJURY_SHEETS_CSS}</style>

      <Eyebrow coral>ACTIVE ACHE  ·  {injury.side.toUpperCase()}</Eyebrow>
      <h1 className="h-display" style={{ fontSize: 38, marginTop: 4 }}>{injury.area.toLowerCase().replace(/^./, c => c.toUpperCase())}.</h1>
      <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", letterSpacing: "0.10em", marginTop: 6 }}>
        OPEN {injury.daysOpen} DAYS  ·  FROM {injury.source}  ·  SINCE {injury.firstSeen}
      </div>

      <div style={{ height: 16 }} />
      <EditorialRule />

      <div className="prd-fieldrow">
        <span className="prd-fieldrow__label">STATUS</span>
        <div className="prd-inj__status-row" style={{ paddingTop: 4 }}>
          {statuses.map(s => (
            <div
              key={s.v}
              className={"prd-inj__status" + (status === s.v ? " is-active" : "")}
              onClick={() => setStatus(s.v)}
            >
              {s.l}
            </div>
          ))}
        </div>
      </div>

      <div className="prd-fieldrow">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <span className="prd-fieldrow__label">SEVERITY  ·  CURRENT</span>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 14, fontWeight: 600,
            color: sevColor(severity),
            fontVariantNumeric: "tabular-nums",
          }}>
            {severity} / 10  ·  {sevLabel(severity)}
          </span>
        </div>
        <div className="prd-inj__sev-track">
          <div
            className="prd-inj__sev-fill"
            style={{ width: ((severity - 1) / 9 * 100) + "%", background: sevColor(severity) }}
          />
        </div>
        <input
          className="prd-inj__sev-input"
          type="range" min="1" max="10" step="1"
          value={severity}
          onChange={(e) => setSeverity(parseInt(e.target.value))}
        />
      </div>

      <div className="prd-fieldrow">
        <span className="prd-fieldrow__label">FROM YOUR COACH</span>
        <div style={{ marginTop: 6 }}>
          <CoachQuote>
            Two weeks of consistent severity 4. We've dropped hill repeats already. If it doesn't tick down by next Friday, see a sports physio — don't push the marathon.
          </CoachQuote>
        </div>
      </div>

      <div className="prd-fieldrow">
        <span className="prd-fieldrow__label">NOTES</span>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          style={{
            width: "100%", minHeight: 80, marginTop: 4,
            background: "transparent", border: 0, outline: "none", resize: "none",
            fontFamily: "var(--font-body)", fontSize: 14, color: "var(--ink)", padding: 0,
          }}
        />
      </div>

      <div className="prd-fieldrow" style={{ borderBottom: 0 }}>
        <span className="prd-fieldrow__label">TIMELINE</span>
        <div style={{ marginTop: 6 }}>
          {injury.timeline.map((t, i) => (
            <div key={i} className="prd-inj__timeline-row">
              <div className="prd-inj__timeline-dot" style={{ background: i === 0 ? "var(--coral)" : "var(--ink-3)" }} />
              <div>
                <span className="prd-inj__timeline-label">{t.label}</span>
                <span className="prd-inj__timeline-meta">{t.meta}</span>
              </div>
              <span className="prd-inj__timeline-date">{t.date}</span>
            </div>
          ))}
        </div>
      </div>

      <div style={{
        marginTop: 14,
        fontFamily: "var(--font-body)", fontStyle: "italic",
        fontSize: 12, color: "var(--ink-3)", lineHeight: 1.5,
      }}>
        — not medical advice. If anything gets sharper, see a clinician. —
      </div>

      <div style={{ marginTop: 18, display: "flex", justifyContent: "space-between" }}>
        <span className="link" style={{ fontSize: 13 }}>Mark resolved ↗</span>
        <span className="link" style={{ fontSize: 13, color: "var(--mood-injured, #B83A4A)", borderColor: "var(--mood-injured, #B83A4A)" }}>Delete</span>
      </div>
    </Sheet>
  );
};

window.AddInjurySheet = AddInjurySheet;
window.InjuryDetailSheet = InjuryDetailSheet;
