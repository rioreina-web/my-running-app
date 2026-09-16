/* Mileage · By Day — SKYLINE, refined.
   Three takes on the same idea: bars rise from a shared baseline, height = miles,
   fill = zone. They differ only in how much the numerals speak. */

const ZONE = { easy: "#A8B394", aerobic: "#C49B52", hard: "#C04E27" };
const ZONE_NAME = { easy: "EASY", aerobic: "AEROBIC", hard: "THRESHOLD" };
const CORAL = "#D4592A";
const MAX = 14;

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

const weekTotal = (w) => w.cells.reduce((s, c) => s + (c.m || 0), 0);
const peakIdx = (w) => {
  let best = -1, bi = -1;
  w.cells.forEach((c, i) => { if ((c.m || 0) > best) { best = c.m; bi = i; } });
  return bi;
};

/* ---- chrome ------------------------------------------------------- */
const sky = {
  paper: { background: "var(--paper)", padding: "24px 22px 22px", fontFamily: "var(--font-body)",
    color: "var(--ink)", height: "100%", boxSizing: "border-box", WebkitFontSmoothing: "antialiased" },
  head: { display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 18 },
  eyebrow: { fontFamily: "var(--font-mono)", fontSize: 11, letterSpacing: ".12em",
    color: "var(--ink-2)", textTransform: "uppercase", fontWeight: 600 },
  tap: { fontFamily: "var(--font-mono)", fontSize: 11, letterSpacing: ".12em",
    color: "var(--ink-3)", textTransform: "uppercase" },
  colhead: { display: "grid", gridTemplateColumns: "56px repeat(7,1fr)", columnGap: 5, marginBottom: 4 },
  colh: { fontFamily: "var(--font-mono)", fontSize: 9, letterSpacing: ".08em", color: "var(--ink-3)", textAlign: "center" },
  row: { display: "grid", gridTemplateColumns: "56px repeat(7,1fr)", columnGap: 5, alignItems: "stretch",
    borderBottom: "1px solid var(--rule)" },
  gutter: { alignSelf: "stretch", display: "flex", flexDirection: "column", justifyContent: "center", paddingRight: 6 },
  glabel: { fontFamily: "var(--font-mono)", fontSize: 9, letterSpacing: ".06em", color: "var(--ink-2)" },
  gtotal: { fontFamily: "var(--font-mono)", fontSize: 11, fontWeight: 600, color: "var(--ink)",
    fontVariantNumeric: "tabular-nums", marginTop: 2 },
};

const BARW = 12, ROWH = 66, FLOOR = 4, RANGE = 48;

function Bar({ c, label }) {
  // rest / future
  if (c.r) return (
    <div style={{ height: "100%", display: "flex", alignItems: "flex-end", justifyContent: "center", paddingBottom: 5 }}>
      <span style={{ width: 7, height: 7, borderRadius: 999, border: "1px solid var(--ink-3)", opacity: 0.5, boxSizing: "border-box" }} />
    </div>
  );
  if (c.f) return (
    <div style={{ height: "100%", display: "flex", alignItems: "flex-end", justifyContent: "center", paddingBottom: 6 }}>
      <span style={{ width: 7, height: 1, background: "var(--rule)" }} />
    </div>
  );
  const h = FLOOR + (c.m / MAX) * RANGE;
  const showNum = label === "all" || (label === "peak" && c.peak) || c.sel;
  return (
    <div style={{ position: "relative", height: "100%", display: "flex", flexDirection: "column",
      alignItems: "center", justifyContent: "flex-end", paddingBottom: 5 }}>
      {showNum && (
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, lineHeight: 1, marginBottom: 5,
          color: c.sel ? "var(--ink)" : "var(--ink-2)", fontWeight: c.sel ? 700 : 500,
          fontVariantNumeric: "tabular-nums" }}>{c.m.toFixed(1)}</span>
      )}
      <span style={{ width: BARW, height: h, borderRadius: "2px 2px 0 0", background: ZONE[c.z] }} />
      {c.sel && (
        <span style={{ position: "absolute", bottom: -1, width: BARW, height: 2.5, background: CORAL }} />
      )}
    </div>
  );
}

function Skyline({ label, showTotal }) {
  return (
    <div style={sky.paper}>
      <div style={sky.head}>
        <span style={sky.eyebrow}>Mileage · By Day</span>
        <span style={sky.tap}>{showTotal ? "MI / WK" : "Tap a day"}</span>
      </div>
      <div style={sky.colhead}>
        <div />
        {DAYS.map((d, i) => <div key={i} style={sky.colh}>{d}</div>)}
      </div>
      <div>
        {WEEKS.map((w, wi) => {
          const pk = peakIdx(w);
          return (
            <div key={wi} style={{ ...sky.row, height: ROWH }}>
              <div style={sky.gutter}>
                <span style={sky.glabel}>{w.label}</span>
                {showTotal && <span style={sky.gtotal}>{weekTotal(w).toFixed(0)}</span>}
              </div>
              {w.cells.map((c, ci) => (
                <Bar key={ci} c={{ ...c, peak: ci === pk }} label={label} />
              ))}
            </div>
          );
        })}
      </div>
      <Footer />
    </div>
  );
}

function Footer() {
  return (
    <div style={{ marginTop: 18, paddingTop: 14, borderTop: "1px solid var(--rule)",
      display: "flex", justifyContent: "space-between", alignItems: "flex-end" }}>
      <div>
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: ".1em",
          color: "var(--ink)", marginBottom: 4 }}>MAY 11 · EASY · 7.3 MI</div>
        <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 16, color: "var(--ink)" }}>
          “Morning Run”
        </div>
      </div>
      <div style={{ display: "flex", gap: 12 }}>
        {["easy", "aerobic", "hard"].map((z) => (
          <span key={z} style={{ display: "flex", alignItems: "center", gap: 5,
            fontFamily: "var(--font-mono)", fontSize: 8.5, letterSpacing: ".06em", color: "var(--ink-3)" }}>
            <span style={{ width: 7, height: 7, borderRadius: 1, background: ZONE[z] }} />
            {ZONE_NAME[z]}
          </span>
        ))}
      </div>
    </div>
  );
}

/* ---- canvas ------------------------------------------------------- */
function App() {
  return (
    <DesignCanvas>
      <DCSection id="skyline" title="Mileage · By Day — Skyline" subtitle="Bars rise from a shared baseline · height = miles · fill = zone. Pick how much the numbers speak.">
        <DCArtboard id="s1" label="S1 · Quiet — bars only, totals in gutter, number on tap" width={390} height={560}>
          <Skyline label="sel" showTotal={true} />
        </DCArtboard>
        <DCArtboard id="s3" label="S3 · Peak-labeled — only the week's longest run is named" width={390} height={560}>
          <Skyline label="peak" showTotal={true} />
        </DCArtboard>
        <DCArtboard id="s2" label="S2 · Full — every day labeled above its bar" width={390} height={560}>
          <Skyline label="all" showTotal={false} />
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
