// Post Run Drip · iOS UI kit · shared primitives
// Components are exported to window at the bottom for cross-file use.

// ---- Eyebrow & rule ------------------------------------------------------
const Eyebrow = ({ children, coral, style }) => (
  <div className={"eyebrow" + (coral ? " eyebrow--coral" : "")} style={style}>{children}</div>
);

const EditorialRule = () => (
  <div className="e-rule"><span className="dot"></span></div>
);

const Hairline = ({ style }) => <div className="hairline" style={style}></div>;

// ---- Plate strip — top of each editorial surface ------------------------
const PlateStrip = ({ surface = "TRENDS · v1 ANALYTICS SURFACE", fig, right = "NEGATIVE SPLITS · 04.2026" }) => (
  <div className="plate-strip">
    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
      <span style={{ color: "var(--ink)" }}>RUNNING LOG</span>
      <span>— {surface}</span>
    </div>
    {(fig || right) && (
      <div style={{ display: "flex", flexDirection: "column", gap: 2, textAlign: "right" }}>
        {fig && <span style={{ color: "var(--ink)" }}>{fig}</span>}
        <span>{right}</span>
      </div>
    )}
  </div>
);

// ---- Mood pill ----------------------------------------------------------
const MOOD_COLORS = {
  energized:  { c: "#2D8A4E", bg: "rgba(45,138,78,0.12)" },
  positive:   { c: "#4A9E6B", bg: "rgba(74,158,107,0.12)" },
  neutral:    { c: "#6B6560", bg: "rgba(155,149,144,0.18)" },
  tired:      { c: "#C4873A", bg: "rgba(196,135,58,0.12)" },
  struggling: { c: "#C45A3A", bg: "rgba(196,90,58,0.12)" },
  injured:    { c: "#B83A4A", bg: "rgba(184,58,74,0.12)" },
};
const MoodPill = ({ mood }) => {
  const m = MOOD_COLORS[mood] || MOOD_COLORS.neutral;
  return <span className="mood-pill" style={{ color: m.c, background: m.bg }}>{mood.toUpperCase()}</span>;
};

// ---- Mood radio cluster (Today: how are you feeling?) ------------------
const MoodRadio = ({ value, onChange }) => {
  const moods = ["energized", "positive", "neutral", "tired", "struggling"];
  return (
    <div className="mood-radio-row">
      {moods.map(m => (
        <div key={m} className={"mood-radio" + (value === m ? " is-active" : "")} onClick={() => onChange && onChange(m)}>
          <div className="mdot"></div>
          <div className="mname">{m}</div>
        </div>
      ))}
    </div>
  );
};

// ---- Stat tile ----------------------------------------------------------
const StatTile = ({ label, value, unit, delta, deltaTone = "pos" }) => (
  <div className="stat-tile">
    <div className="stat-label">{label}</div>
    <div className="stat-value">{value}{unit && <span className="stat-unit">{unit}</span>}</div>
    {delta && <div className={"stat-delta " + (deltaTone === "pos" ? "delta-pos" : "delta-neg")}>{delta}</div>}
  </div>
);

// ---- Section header ----------------------------------------------------
const Section = ({ eyebrow, eyebrowRight, eyebrowCoral, children, first }) => (
  <div className={"section" + (first ? " section--first" : "")}>
    {(eyebrow || eyebrowRight) && (
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        {eyebrow && <Eyebrow coral={eyebrowCoral}>{eyebrow}</Eyebrow>}
        {eyebrowRight && <Eyebrow>{eyebrowRight}</Eyebrow>}
      </div>
    )}
    {children}
  </div>
);

// ---- Tab bar -----------------------------------------------------------
const TAB_DEFS = [
  { id: "log",     label: "Log" },
  { id: "train",   label: "Train" },
  { id: "trends",  label: "Trends" },
  { id: "coach",   label: "Coach" },
  { id: "runs",    label: "Runs" },
];
const TabBar = ({ active, onChange }) => (
  <div className="tab-bar">
    {TAB_DEFS.map(t => (
      <div key={t.id} className={"tab" + (active === t.id ? " is-active" : "")} onClick={() => onChange(t.id)}>
        <div className="tdot"></div>
        <div className="tlbl">{t.label}</div>
      </div>
    ))}
  </div>
);

// ---- Coach quote (blockquote with coral left bar) ----------------------
const CoachQuote = ({ children }) => (
  <p className="coach-quote">"{children}"</p>
);

// ---- Tiny SVG line chart -----------------------------------------------
const LineChart = ({ data, height = 90, color = "var(--ink)", dotColor = "var(--coral)" }) => {
  if (!data || data.length < 2) return null;
  const w = 280, h = height;
  const xs = data.map((_, i) => (i / (data.length - 1)) * w);
  const min = Math.min(...data), max = Math.max(...data);
  const yScale = v => h - ((v - min) / (max - min || 1)) * (h - 14) - 6;
  const path = xs.map((x, i) => `${i === 0 ? "M" : "L"} ${x} ${yScale(data[i])}`).join(" ");
  const lastX = xs[xs.length - 1], lastY = yScale(data[data.length - 1]);
  return (
    <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" style={{ width: "100%", height }}>
      <path d={path} fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={lastX} cy={lastY} r="3.5" fill={dotColor} />
    </svg>
  );
};

// ---- Zone bar ---------------------------------------------------------
const ZoneBar = ({ zones }) => (
  <div style={{ display: "flex", height: 12, borderRadius: 3, overflow: "hidden" }}>
    {zones.map((z, i) => (
      <div key={i} style={{ background: z.color, width: z.pct + "%" }} />
    ))}
  </div>
);

// ---- Toggle ----------------------------------------------------------
const Toggle = ({ on, onChange }) => (
  <div className={"toggle" + (on ? " on" : "")} onClick={() => onChange && onChange(!on)}>
    <div className="knob"></div>
  </div>
);

// Expose to window so other Babel scripts can use them
Object.assign(window, {
  Eyebrow, EditorialRule, Hairline, PlateStrip,
  MOOD_COLORS, MoodPill, MoodRadio,
  StatTile, Section, TabBar, CoachQuote,
  LineChart, ZoneBar, Toggle,
});
