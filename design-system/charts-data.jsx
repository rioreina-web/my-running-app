/* global React */
/* ════════════════════════════════════════════════════════════════════
   ANALYTICAL CHARTS · DATA + SCALE ENGINE
   One real-feeling run, sampled densely. Pace, HR, elevation respond to
   grade and to a negative-split finish. Shared scale helpers + HR zones.
   ════════════════════════════════════════════════════════════════════ */

const RUN_META = {
  day: "Tuesday",
  date: "MAY 5 · 09:06",
  distance: "6.9",
  time: "51:06",
  pace: "7:24",
  hr: "143",
  elev: "+43",
};

// ── HR zones (editorial mood palette) ───────────────────────────────────
const HR_ZONES = [
  { id: 1, name: "Z1", label: "Recovery",  min: 0,   max: 130, color: "#4A9E6B" },
  { id: 2, name: "Z2", label: "Easy",      min: 130, max: 142, color: "#2D8A4E" },
  { id: 3, name: "Z3", label: "Steady",    min: 142, max: 150, color: "#C4873A" },
  { id: 4, name: "Z4", label: "Threshold", min: 150, max: 158, color: "#C45A3A" },
  { id: 5, name: "Z5", label: "VO₂max",    min: 158, max: 999, color: "#B83A4A" },
];
function zoneForHR(hr) {
  return HR_ZONES.find(z => hr >= z.min && hr < z.max) || HR_ZONES[HR_ZONES.length - 1];
}

// ── Synthesize the run ──────────────────────────────────────────────────
const RUN_MILES = 6.9;
function elevFn(t) {
  // metres: gentle start, a climb peaking ~42% in, rolling texture
  return 22
    + 54 * Math.exp(-Math.pow((t - 0.42) / 0.17, 2))
    + 6 * Math.sin(t * 9.0)
    + 4 * Math.sin(t * 21.0);
}
function buildRun(n) {
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const d = +(t * RUN_MILES).toFixed(3);
    const elev = elevFn(t);
    // grade: slope of elevation over distance (m per mile), normalized
    const h = 1 / n;
    const slope = (elevFn(Math.min(1, t + h)) - elevFn(Math.max(0, t - h))) / (2 * h * RUN_MILES);
    // pace (sec/mi): negative-split base + grade penalty + finish surge
    let pace = 466 - 36 * t;                 // 7:46 → 7:10 drift
    pace += Math.max(-40, Math.min(70, slope * 0.55)); // hills slow you, descents help (capped)
    if (t > 0.84) pace -= (t - 0.84) * 230;  // closing surge
    pace += 4 * Math.sin(t * 30);            // small stride noise
    // hr (bpm): aerobic drift + effort from pace + grade + finish surge
    let hr = 126 + 24 * t;
    hr += Math.max(0, slope) * 0.16;
    hr += Math.max(0, (455 - pace)) * 0.10;
    if (t > 0.84) hr += (t - 0.84) * 90;
    hr += 1.5 * Math.sin(t * 26);
    pts.push({ t, d, elev: +elev.toFixed(1), pace: Math.round(pace), hr: Math.round(hr) });
  }
  return pts;
}
const RUN = buildRun(132);

// ── Per-mile splits (aggregated) ─────────────────────────────────────────
function buildSplits() {
  const splits = [];
  const miles = Math.ceil(RUN_MILES);
  for (let m = 0; m < miles; m++) {
    const lo = m, hi = Math.min(RUN_MILES, m + 1);
    const seg = RUN.filter(p => p.d >= lo && p.d <= hi);
    if (!seg.length) continue;
    const avgPace = Math.round(seg.reduce((s, p) => s + p.pace, 0) / seg.length);
    const avgHR = Math.round(seg.reduce((s, p) => s + p.hr, 0) / seg.length);
    const gain = +(elevFn(hi / RUN_MILES) - elevFn(lo / RUN_MILES)).toFixed(0);
    splits.push({
      mile: hi <= RUN_MILES && hi - lo === 1 ? `${m + 1}` : `${(hi).toFixed(1)}`,
      partial: hi - lo < 1,
      dist: +(hi - lo).toFixed(2),
      pace: avgPace, hr: avgHR, gain,
      zone: zoneForHR(avgHR),
    });
  }
  return splits;
}
const SPLITS = buildSplits();

// ── Formatting ───────────────────────────────────────────────────────────
function fmtPace(sec) {
  const m = Math.floor(sec / 60), s = Math.round(sec % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

// ── Scale factory ─────────────────────────────────────────────────────────
function linScale(dMin, dMax, rMin, rMax) {
  const dd = (dMax - dMin) || 1;
  return v => rMin + ((v - dMin) / dd) * (rMax - rMin);
}
// Build an SVG path "M..L.." from samples given x/y accessors
function linePath(data, x, y) {
  return data.map((p, i) => `${i === 0 ? "M" : "L"} ${x(p).toFixed(2)} ${y(p).toFixed(2)}`).join(" ");
}
function areaPath(data, x, y, yBase) {
  const top = data.map((p, i) => `${i === 0 ? "M" : "L"} ${x(p).toFixed(2)} ${y(p).toFixed(2)}`).join(" ");
  const last = data[data.length - 1], first = data[0];
  return `${top} L ${x(last).toFixed(2)} ${yBase.toFixed(2)} L ${x(first).toFixed(2)} ${yBase.toFixed(2)} Z`;
}
// nearest sample index for a given x pixel, using an x accessor
function nearestIndex(data, x, px) {
  let best = 0, bd = Infinity;
  for (let i = 0; i < data.length; i++) {
    const dx = Math.abs(x(data[i]) - px);
    if (dx < bd) { bd = dx; best = i; }
  }
  return best;
}

Object.assign(window, {
  RUN_META, HR_ZONES, zoneForHR, RUN, SPLITS, RUN_MILES,
  fmtPace, linScale, linePath, areaPath, nearestIndex, elevFn,
});
