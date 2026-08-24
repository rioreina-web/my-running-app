/* global React */
/* ════════════════════════════════════════════════════════════════════
   WORKOUT DETAIL · REDESIGN — DATA LAYER
   Interval / tempo session (the screenshot: 2K·1K·1K·2K·1K·1K threshold).

   Mirrors the real Strava stream shape the app already ingests
   (ExternalStreamAdapter.swift): time, heartrate, velocity_smooth,
   cadence, altitude, grade_smooth, temp, latlng + rep-level laps with
   distance. Weather (temp_f, dew_point_f, heat-adjusted pace) comes from
   the workout's weather_actual_jsonb / WorkoutRepChart fields.

   Streams are synthesized procedurally from a segment plan (seeded, so
   deterministic) — keeps this file small while producing dense, real-
   looking charts.
   ════════════════════════════════════════════════════════════════════ */

/* ─── tiny tweaks store (shared across all 3 artboards) ──────────────── */
const wdStore = {
  state: {
    units: "mi",          // "mi" | "km"
    weatherAdjust: false, // show heat-adjusted paces
    colorByZone: false,   // color rep bars / route by HR zone
    comparison: "recent", // "recent" | "thisSession" | "best"
  },
  listeners: new Set(),
  set(patch) {
    this.state = { ...this.state, ...patch };
    this.listeners.forEach((l) => l());
  },
  use() {
    const [, force] = React.useState(0);
    React.useEffect(() => {
      const l = () => force((x) => x + 1);
      this.listeners.add(l);
      return () => this.listeners.delete(l);
    }, []);
    return this.state;
  },
};

/* ─── workout meta ───────────────────────────────────────────────────── */
const WK = {
  type: "TEMPO",
  title: "2K·1K·1K·2K·1K·1K",
  prescription: "2 × (2k + 2×1k) threshold",
  target: "8×1000m @ 3:15 w/ 80s rec",
  date: "Thursday",
  fullDate: "May 21, 2026",
  time: "09:06",
  source: "Strava",
  place: "Lady Bird Lake · Austin, TX",
  // session totals
  workDistMi: 4.97,
  workTime: "26:08",
  totalDistMi: 9.4,
  totalTime: "1:14:20",
  avgWorkPaceSec: 315,   // 5:15/mi
  avgHr: 173,
  maxHr: 175,
  hrReserve: 188,        // max hr for zone calc
  spreadSec: 11,
  avgCadence: 186,
  avgPowerW: 312,
  elevGainFt: 142,
  calories: 712,
};

/* weather — woven into analysis copy; drives heat-adjust toggle */
const WX = {
  tempF: 74,
  dewPointF: 66,         // sticky — "moderate-hard" heat category
  humidity: 78,
  windMph: 6,
  condition: "Humid, overcast",
  heatCategory: "MODERATE",
  // dew-point heat-index adjustment (PaceCalculator.calculateDewPointAdjustment shape)
  adjustPct: 2.4,        // +2.4% slower equivalent effort
  adjustSecPerMi: 8,     // ≈ 8 sec/mi
};

/* ─── rep plan (laps) — each rep carries DISTANCE (the missing field) ── */
const REP_PLAN = [
  { i: 1, label: "2K", distMi: 1.243, paceSec: 318, hr: 168, cad: 184, rest: 80, watts: 305, elevFt: 14 },
  { i: 2, label: "1K", distMi: 0.621, paceSec: 312, hr: 174, cad: 186, rest: 80, watts: 312, elevFt: -6 },
  { i: 3, label: "1K", distMi: 0.621, paceSec: 312, hr: 175, cad: 187, rest: 80, watts: 314, elevFt: 8 },
  { i: 4, label: "2K", distMi: 1.243, paceSec: 321, hr: 175, cad: 185, rest: 80, watts: 308, elevFt: 18 },
  { i: 5, label: "1K", distMi: 0.621, paceSec: 310, hr: 175, cad: 188, rest: 80, watts: 318, elevFt: -10 },
  { i: 6, label: "1K", distMi: 0.621, paceSec: 314, hr: 175, cad: 187, rest: null, watts: 313, elevFt: 4 },
];

/* ─── HR zones (pct of max 188) ──────────────────────────────────────── */
const HR_ZONES = [
  { id: "Z1", name: "Recovery",  lo: 0,   hi: 132, color: "#9B9590" },
  { id: "Z2", name: "Aerobic",   lo: 132, hi: 150, color: "#4A9E6B" },
  { id: "Z3", name: "Tempo",     lo: 150, hi: 165, color: "#C4873A" },
  { id: "Z4", name: "Threshold", lo: 165, hi: 178, color: "#D4592A" },
  { id: "Z5", name: "VO2",       lo: 178, hi: 200, color: "#B83A4A" },
];
const zoneOf = (hr) => HR_ZONES.find((z) => hr >= z.lo && hr < z.hi) || HR_ZONES[HR_ZONES.length - 1];

/* ─── segment plan → per-sample streams (2s cadence) ─────────────────── */
/* seeded RNG so charts are stable across renders */
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function buildSegments() {
  const segs = [];
  segs.push({ kind: "warmup", dur: 720, pace0: 540, pace1: 470, hr0: 96, hr1: 150, cad: 168 });
  REP_PLAN.forEach((r, idx) => {
    const dur = Math.round(r.distMi * r.paceSec);
    segs.push({
      kind: "rep", rep: r.i, label: r.label, dur,
      pace0: r.paceSec + 10, pace1: r.paceSec - 6, paceSec: r.paceSec,
      hr0: idx === 0 ? 150 : 146, hr1: r.hr, cad: r.cad, watts: r.watts,
    });
    if (r.rest) segs.push({ kind: "rest", dur: r.rest, pace0: 600, pace1: 540, hr0: r.hr, hr1: 142, cad: 158 });
  });
  segs.push({ kind: "cooldown", dur: 560, pace0: 520, pace1: 600, hr0: 168, hr1: 104, cad: 162 });
  return segs;
}

function synth() {
  const rnd = mulberry32(20260521);
  const segs = buildSegments();
  const STEP = 2; // seconds per sample
  const time = [], hr = [], pace = [], cad = [], alt = [], grade = [], distance = [];
  const repBands = []; // {rep,label,startSec,endSec,kind}
  let t = 0, distM = 0, elevM = 30;

  segs.forEach((s) => {
    const n = Math.max(1, Math.round(s.dur / STEP));
    const startSec = t;
    for (let k = 0; k < n; k++) {
      const f = k / (n - 1 || 1);
      // ease the transition a touch
      const ef = f < 0.15 ? f / 0.15 * 0.5 : 0.5 + (f - 0.15) / 0.85 * 0.5;
      const pV = s.pace0 + (s.pace1 - s.pace0) * ef + (rnd() - 0.5) * 6;
      const hrV = s.hr0 + (s.hr1 - s.hr0) * Math.min(1, f * 1.3) + (rnd() - 0.5) * 3;
      const cadV = s.cad + (rnd() - 0.5) * 4 + (s.kind === "rep" ? 2 : 0);
      // elevation: gentle rolling sine + drift
      elevM += Math.sin((t / 240) * Math.PI) * 0.18 + (rnd() - 0.5) * 0.25;
      const gr = Math.sin((t / 240) * Math.PI) * 2.2 + (rnd() - 0.5) * 0.8;
      time.push(t);
      pace.push(Math.round(pV));
      hr.push(Math.round(hrV));
      cad.push(Math.round(cadV));
      alt.push(elevM);
      grade.push(+gr.toFixed(1));
      // advance distance by speed (m per STEP): speed m/s = 1609.34 / paceSecPerMile
      const speed = 1609.34 / pV;
      distM += speed * STEP;
      distance.push(distM);
      t += STEP;
    }
    if (s.kind === "rep") repBands.push({ rep: s.rep, label: s.label, startSec, endSec: t, kind: "rep" });
    if (s.kind === "rest") repBands.push({ kind: "rest", startSec, endSec: t });
  });

  return { time, hr, pace, cad, alt, grade, distance, repBands, totalSec: t, totalDistM: distM };
}

const STREAM = synth();

/* per-rep HR-recovery traces (drop in the 60s rest after each rep) */
const REP_RECOVERY = REP_PLAN.filter((r) => r.rest).map((r) => {
  const peak = r.hr;
  const drop = 34 + Math.round((r.i % 3) * 2.5); // bpm dropped over 60s
  const pts = [];
  for (let s = 0; s <= 60; s += 5) {
    const f = s / 60;
    pts.push(Math.round(peak - drop * (1 - Math.pow(1 - f, 1.7))));
  }
  return { rep: r.i, peak, end: pts[pts.length - 1], drop, pts };
});

/* ─── time-in-zone (seconds), computed from the HR stream ────────────── */
const TIZ = (() => {
  const acc = {}; HR_ZONES.forEach((z) => (acc[z.id] = 0));
  STREAM.hr.forEach((h) => { acc[zoneOf(h).id] += 2; });
  return acc;
})();

/* ─── comparison sets — "recent tempos" / "this session" / "best" ────── */
const COMPARE = {
  recent: {
    label: "RECENT TEMPOS",
    sub: "last 6 threshold sessions",
    series: [
      { d: "Apr 09", paceSec: 322, hr: 171, this: false },
      { d: "Apr 16", paceSec: 320, hr: 172, this: false },
      { d: "Apr 30", paceSec: 319, hr: 174, this: false },
      { d: "May 07", paceSec: 318, hr: 173, this: false },
      { d: "May 14", paceSec: 317, hr: 174, this: false },
      { d: "May 21", paceSec: 315, hr: 173, this: true },
    ],
  },
  thisSession: {
    label: "THIS SESSION · HISTORY",
    sub: "every time you ran 2×(2k+2×1k)",
    series: [
      { d: "Feb 12", paceSec: 328, hr: 176, this: false },
      { d: "Mar 05", paceSec: 324, hr: 175, this: false },
      { d: "Apr 02", paceSec: 320, hr: 174, this: false },
      { d: "May 21", paceSec: 315, hr: 173, this: true },
    ],
  },
  best: {
    label: "VS YOUR BEST",
    sub: "fastest avg work pace at this effort",
    series: [
      { d: "Best · Mar 05", paceSec: 311, hr: 177, this: false },
      { d: "May 21", paceSec: 315, hr: 173, this: true },
    ],
  },
};

/* recent-tempo per-metric averages for delta chips */
const RECENT_AVG = { paceSec: 319, hr: 173, cad: 184, elevFt: 120 };

/* ─── formatting helpers (respect units toggle) ─────────────────────── */
const fmtClock = (s) => {
  const m = Math.floor(s / 60), ss = Math.round(s) % 60;
  return `${m}:${String(ss).padStart(2, "0")}`;
};
const fmtPaceVal = (secPerMi, units, adjust) => {
  let v = secPerMi;
  if (adjust) v += WX.adjustSecPerMi;
  if (units === "km") v = v / 1.60934;
  return fmtClock(v);
};
const paceUnit = (units) => (units === "km" ? "/km" : "/mi");
const distVal = (mi, units) => (units === "km" ? mi * 1.60934 : mi);
const distUnit = (units) => (units === "km" ? "km" : "mi");
const elevVal = (ft, units) => (units === "km" ? Math.round(ft * 0.3048) : ft);
const elevUnit = (units) => (units === "km" ? "m" : "ft");

/* shared style atoms */
const wd = {
  mono: { fontFamily: "var(--font-mono)", fontVariantNumeric: "tabular-nums" },
  eyebrow: { fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500, letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--ink-2)" },
  eyebrowSm: { fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 500, letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--ink-3)" },
  italic: { fontFamily: "var(--font-body)", fontStyle: "italic", color: "var(--ink-2)", lineHeight: 1.5 },
};

Object.assign(window, {
  wdStore, WK, WX, REP_PLAN, HR_ZONES, zoneOf, STREAM, REP_RECOVERY, TIZ,
  COMPARE, RECENT_AVG, fmtClock, fmtPaceVal, paceUnit, distVal, distUnit,
  elevVal, elevUnit, wd,
});
