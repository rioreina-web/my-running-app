/* Mileage · By Day — redesign explorations
   Real data + real palette pulled from TrainingTabView / IntensityRamp. */

const ZONE = { easy: "#A8B394", aerobic: "#C49B52", hard: "#C04E27" };
const ZONE_NAME = { easy: "EASY", aerobic: "AEROBIC", hard: "THRESHOLD" };
const MAX = 14; // peak weekly long run in the window

// rows = weeks, cells = M T W T F S S.  z = hardest zone that day.
const WEEKS = [
  { label: "MAY 11", cells: [
    { m: 7.3, z: "aerobic", sel: true }, { m: 13.2, z: "hard" }, { m: 7.0, z: "easy" },
    { m: 13.0, z: "easy" }, { m: 11.5, z: "aerobic" }, { m: 13.1, z: "hard" }, { m: 7.0, z: "easy" } ] },
  { label: "MAY 18", cells: [
    { m: 7.5, z: "easy" }, { m: 7.0, z: "easy" }, { m: 9.5, z: "hard" }, { m: 6.9, z: "easy" },
    { m: 9.9, z: "easy" }, { m: 2.5, z: "easy" }, { m: 14.0, z: "hard" } ] },
  { label: "MAY 25", cells: [
    { m: 8.2, z: "hard" }, { r: true }, { m: 9.2, z: "aerobic" }, { m: 12.4, z: "hard" },
    { m: 7.0, z: "aerobic" }, { r: true }, { m: 3.0, z: "easy" } ] },
  { label: "JUN 1", cells: [
    { m: 12.1, z: "easy" }, { m: 8.7, z: "hard" }, { m: 6.8, z: "easy" }, { m: 8.7, z: "easy" },
    { m: 3.1, z: "easy" }, { m: 11.4, z: "hard" }, { m: 4.2, z: "easy" } ] },
  { label: "JUN 8", cells: [
    { m: 7.9, z: "easy" }, { m: 9.4, z: "hard" }, { m: 11.8, z: "easy" },
    { f: true }, { f: true }, { f: true }, { f: true } ] },
];

const DAYS = ["M", "T", "W", "T", "F", "S", "S"];

/* ---- shared chrome ------------------------------------------------ */
const mileageStyles = {
  paper: {
    background: "var(--paper)", padding: "24px 22px 22px",
    fontFamily: "var(--font-body)", color: "var(--ink)",
    height: "100%", boxSizing: "border-box",
    WebkitFontSmoothing: "antialiased",
  },
  head: { display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 16 },
  eyebrow: { fontFamily: "var(--font-mono)", fontSize: 11, letterSpacing: ".12em",
    color: "var(--ink-2)", textTransform: "uppercase", fontWeight: 600 },
  tap: { fontFamily: "var(--font-mono)", fontSize: 11, letterSpacing: ".12em",
    color: "var(--ink-3)", textTransform: "uppercase" },
  colhead: { display: "grid", gridTemplateColumns: "44px repeat(7,1fr)", columnGap: 4, marginBottom: 8 },
  colh: { fontFamily: "var(--font-mono)", fontSize: 9, letterSpacing: ".08em",
    color: "var(--ink-3)", textAlign: "center" },
  rowlabel: { fontFamily: "var(--font-mono)", fontSize: 9, letterSpacing: ".06em",
    color: "var(--ink-3)", alignSelf: "center" },
  row: { display: "grid", gridTemplateColumns: "44px repeat(7,1fr)", columnGap: 4, alignItems: "stretch" },
};

function Frame({ children }) {
  return (
    <div style={mileageStyles.paper}>
      <div style={mileageStyles.head}>
        <span style={mileageStyles.eyebrow}>Mileage · By Day</span>
        <span style={mileageStyles.tap}>Tap a day</span>
      </div>
      <div style={mileageStyles.colhead}>
        <div />
        {DAYS.map((d, i) => <div key={i} style={mileageStyles.colh}>{d}</div>)}
      </div>
      {children}
    </div>
  );
}

function Rows({ rowH, renderCell, gap = 0 }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", rowGap: gap }}>
      {WEEKS.map((w, wi) => (
        <div key={wi} style={{ ...mileageStyles.row }}>
          <div style={mileageStyles.rowlabel}>{w.label}</div>
          {w.cells.map((c, ci) => (
            <div key={ci} style={{ height: rowH }}>{renderCell(c)}</div>
          ))}
        </div>
      ))}
    </div>
  );
}

function Footer() {
  return (
    <div style={{ marginTop: 18, paddingTop: 14, borderTop: "1px solid var(--rule)" }}>
      <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: ".1em",
        color: "var(--ink)", marginBottom: 4 }}>MAY 11 · EASY · 7.3 MI</div>
      <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 16, color: "var(--ink)" }}>
        “Morning Run”
      </div>
    </div>
  );
}

const tint = (hex, a) => {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
};

/* ═══ CURRENT (reference) ═══ */
function Current() {
  const cell = (c) => {
    if (c.r) return <Mid>{<span style={dot}>·</span>}</Mid>;
    if (c.f) return <Mid>{<span style={dot}>–</span>}</Mid>;
    return (
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 4,
        padding: "8px 0", ...(c.sel ? selBox : null) }}>
        <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 12,
          color: "var(--ink)", fontVariantNumeric: "tabular-nums" }}>{c.m.toFixed(1)}</span>
        <span style={{ width: 14, height: 3, borderRadius: 1, background: ZONE[c.z] }} />
      </div>
    );
  };
  const dot = { fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--ink-3)" };
  const selBox = { border: "1px solid var(--ink)", borderRadius: 2, background: "var(--card)" };
  return <Frame><Rows rowH={46} renderCell={cell} /><Footer /></Frame>;
}
function Mid({ children }) {
  return <div style={{ height: "100%", display: "flex", alignItems: "center", justifyContent: "center" }}>{children}</div>;
}

/* ═══ A · SKYLINE — magnitude as height ═══ */
function Skyline() {
  const H = 38;
  const cell = (c) => {
    if (c.r || c.f) {
      return (
        <div style={{ height: "100%", display: "flex", alignItems: "flex-end", justifyContent: "center", paddingBottom: 2 }}>
          <span style={{ width: 6, height: 2, borderRadius: 1, background: "var(--rule)", opacity: c.f ? 0.5 : 1 }} />
        </div>
      );
    }
    const h = 5 + (c.m / MAX) * H;
    return (
      <div style={{ height: "100%", display: "flex", flexDirection: "column", alignItems: "center",
        justifyContent: "flex-end" }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 8.5, lineHeight: 1, marginBottom: 4,
          color: c.sel ? "var(--ink)" : "var(--ink-3)", fontWeight: c.sel ? 700 : 400,
          fontVariantNumeric: "tabular-nums" }}>{c.m.toFixed(1)}</span>
        <span style={{ width: 11, height: h, borderRadius: "2px 2px 0 0", background: ZONE[c.z],
          outline: c.sel ? "1.5px solid var(--ink)" : "none", outlineOffset: 1 }} />
      </div>
    );
  };
  return (
    <Frame>
      <div style={{ borderBottom: "1px solid var(--rule)" }}>
        <Rows rowH={60} renderCell={cell} gap={2} />
      </div>
      <Footer />
    </Frame>
  );
}

/* ═══ B · CONSTELLATION — magnitude as area, color as zone ═══ */
function Constellation() {
  const cell = (c) => {
    if (c.r) return <Mid><span style={{ width: 9, height: 9, borderRadius: 999,
      border: "1.5px solid var(--ink-3)", opacity: 0.55 }} /></Mid>;
    if (c.f) return <Mid><span style={{ width: 4, height: 4, borderRadius: 999,
      background: "var(--ink-3)", opacity: 0.4 }} /></Mid>;
    const d = 9 + (Math.sqrt(c.m) / Math.sqrt(MAX)) * 27;
    return (
      <Mid>
        <div style={{ position: "relative", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <span style={{ width: d, height: d, borderRadius: 999, background: ZONE[c.z],
            boxShadow: c.sel ? "0 0 0 2px var(--paper), 0 0 0 3.5px var(--ink)" : "none" }} />
          {c.sel && (
            <span style={{ position: "absolute", top: "calc(100% + 4px)", fontFamily: "var(--font-mono)",
              fontSize: 9, fontWeight: 700, color: "var(--ink)", fontVariantNumeric: "tabular-nums",
              whiteSpace: "nowrap" }}>{c.m.toFixed(1)}</span>
          )}
        </div>
      </Mid>
    );
  };
  return (
    <Frame>
      <Rows rowH={48} renderCell={cell} gap={4} />
      <div style={{ display: "flex", gap: 16, marginTop: 14 }}>
        {["easy", "aerobic", "hard"].map((z) => (
          <span key={z} style={{ display: "flex", alignItems: "center", gap: 6,
            fontFamily: "var(--font-mono)", fontSize: 9, letterSpacing: ".08em", color: "var(--ink-3)" }}>
            <span style={{ width: 8, height: 8, borderRadius: 999, background: ZONE[z] }} />
            {ZONE_NAME[z]}
          </span>
        ))}
      </div>
      <Footer />
    </Frame>
  );
}

/* ═══ C · GAUGE — fill rises behind the numeral ═══ */
function Gauge() {
  const cell = (c) => {
    if (c.r) return <Mid><span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--ink-3)" }}>·</span></Mid>;
    if (c.f) return <Mid><span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--ink-3)", opacity: 0.5 }}>–</span></Mid>;
    const fillH = 12 + (c.m / MAX) * 88; // percent
    return (
      <div style={{ position: "relative", height: "100%", borderRadius: 2, overflow: "hidden",
        border: c.sel ? "1px solid var(--ink)" : "1px solid transparent",
        background: c.sel ? "rgba(0,0,0,0.015)" : "transparent" }}>
        <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: `${fillH}%`,
          background: tint(ZONE[c.z], 0.16), borderTop: `2px solid ${ZONE[c.z]}` }} />
        <div style={{ position: "relative", height: "100%", display: "flex", alignItems: "center",
          justifyContent: "center" }}>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 12.5, fontWeight: c.sel ? 700 : 600,
            color: "var(--ink)", fontVariantNumeric: "tabular-nums" }}>{c.m.toFixed(1)}</span>
        </div>
      </div>
    );
  };
  return (
    <Frame>
      <Rows rowH={42} renderCell={cell} gap={5} />
      <Footer />
    </Frame>
  );
}

/* ---- canvas ------------------------------------------------------- */
function App() {
  return (
    <DesignCanvas>
      <DCSection id="mileage" title="Mileage · By Day" subtitle="Same data, same palette — three ways to make the week's shape legible at a glance">
        <DCArtboard id="cur" label="Current · flat numerals + tick" width={390} height={560}><Current /></DCArtboard>
        <DCArtboard id="c" label="C · Gauge — fill behind the number" width={390} height={520}><Gauge /></DCArtboard>
        <DCArtboard id="a" label="A · Skyline — magnitude as height" width={390} height={560}><Skyline /></DCArtboard>
        <DCArtboard id="b" label="B · Constellation — area + zone color" width={390} height={560}><Constellation /></DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
