/* global window */
/* ============================================================
   PACE × VOLUME — shared data + math
   One realistic 9-week half-marathon build for a ~sub-3:10
   marathoner. Deterministic (seeded) so the picture is stable.
   Exposes window.PV with data, scales, KDE, aggregation, trend.
   ============================================================ */
(function () {
  "use strict";

  // ---- reference paces (sec / mile) -------------------------
  // EASY 8:30 · MP 7:15 · LT 6:35 · 5K 6:00 — a legible spread.
  const ANCHORS = [
    { id: "easy", label: "EASY", paceSeconds: 510 },
    { id: "mp",   label: "MP",   paceSeconds: 435 },
    { id: "lt",   label: "LT",   paceSeconds: 395 },
    { id: "5k",   label: "5K",   paceSeconds: 360 },
  ];

  // ---- zones (slowest → fastest) ----------------------------
  // Cohesive temperature ramp: sage = aerobic/calm, coral = intensity.
  // Two hues + ink only — on brand ("restraint, then intensity").
  const ZONES = [
    { id: "rec",  name: "Recovery",  short: "REC",  lo: 540, hi: 9999, color: "#A8C6B2", ink: "#5E7A68" },
    { id: "easy", name: "Easy",      short: "EASY", lo: 477, hi: 540,  color: "#4A9E6B", ink: "#2D7048" },
    { id: "mod",  name: "Steady",    short: "STDY", lo: 447, hi: 477,  color: "#9A9588", ink: "#6B6560" },
    { id: "mp",   name: "Marathon",  short: "MP",   lo: 415, hi: 447,  color: "#D98A4E", ink: "#B86A30" },
    { id: "lt",   name: "Threshold", short: "LT",   lo: 378, hi: 415,  color: "#D4592A", ink: "#B84420" },
    { id: "vo2",  name: "5K / VO2",  short: "5K",   lo: 0,   hi: 378,  color: "#A8371A", ink: "#8A2C12" },
  ];
  // the 80/20 split line: aerobic (rec+easy+mod) vs quality (mp+lt+vo2)
  const QUALITY_IDS = ["mp", "lt", "vo2"];

  function zoneOf(paceSeconds) {
    for (const z of ZONES) if (paceSeconds >= z.lo && paceSeconds < z.hi) return z;
    return ZONES[ZONES.length - 1];
  }
  const zoneById = (id) => ZONES.find((z) => z.id === id);

  // ---- seeded RNG (mulberry32) ------------------------------
  function rng(seed) {
    return function () {
      seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const r = rng(20260608);
  const jitter = (mag) => (r() - 0.5) * 2 * mag;

  // ---- generate the 9-week block ----------------------------
  // Easy + quality paces drift FASTER across the block (fitness ↑).
  const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const WORKOUTS = [];
  let wid = 0;
  for (let w = 1; w <= 9; w++) {
    const prog = (w - 1) / 8;             // 0 → 1 across the block
    const easyBase = 528 - prog * 22;     // 8:48 → 8:26
    const ltBase   = 408 - prog * 18;     // 6:48 → 6:30
    const mpBase   = 446 - prog * 16;     // 7:26 → 7:10
    const vo2Base  = 372 - prog * 14;     // 6:12 → 5:58

    const push = (type, miles, pace, day) =>
      WORKOUTS.push({ id: "w" + wid++, week: w, day, type, miles: +miles.toFixed(1), paceSeconds: Math.round(pace) });

    // 3 easy runs
    push("Easy", 6 + jitter(1.2), easyBase + jitter(10), "Mon");
    push("Easy", 7 + jitter(1.4), easyBase + jitter(12), "Wed");
    push("Easy", 5 + jitter(1.0), easyBase + 6 + jitter(9), "Fri");
    // recovery (most weeks)
    if (w % 3 !== 0) push("Recovery", 4 + jitter(0.6), easyBase + 34 + jitter(8), "Sat");
    // long run — slow, big mileage; deload week 6 shorter
    const longMi = w === 6 ? 12 : 14 + Math.min(prog * 6, 6) + jitter(1);
    push("Long", longMi, easyBase + 12 + jitter(8), "Sun");
    // one quality session per week, rotating
    const qkind = w % 3;
    if (qkind === 1) push("Tempo",     7 + jitter(0.8), ltBase + jitter(7),  "Tue");
    else if (qkind === 2) push("MP run", 9 + jitter(1.0), mpBase + jitter(6), "Tue");
    else push("Intervals", 6 + jitter(0.7), vo2Base + jitter(8), "Tue");
  }

  // ---- aggregate: miles + share per zone --------------------
  function aggregate(workouts) {
    const by = {};
    ZONES.forEach((z) => (by[z.id] = { zone: z, miles: 0, runs: 0 }));
    let total = 0;
    workouts.forEach((wo) => {
      const z = zoneOf(wo.paceSeconds);
      by[z.id].miles += wo.miles;
      by[z.id].runs += 1;
      total += wo.miles;
    });
    const rows = ZONES.map((z) => ({
      ...by[z.id],
      pct: total ? (by[z.id].miles / total) * 100 : 0,
    }));
    const quality = rows.filter((x) => QUALITY_IDS.includes(x.zone.id))
      .reduce((s, x) => s + x.miles, 0);
    return { rows, total, qualityMiles: quality, easyMiles: total - quality,
             qualityPct: total ? (quality / total) * 100 : 0 };
  }

  // ---- weekly trend: avg easy pace & avg quality pace -------
  function weeklyTrend(workouts) {
    const out = [];
    for (let w = 1; w <= 9; w++) {
      const ww = workouts.filter((x) => x.week === w);
      const easy = ww.filter((x) => x.paceSeconds >= 447);
      const qual = ww.filter((x) => x.paceSeconds < 447);
      const avg = (arr) => arr.length ? arr.reduce((s, x) => s + x.paceSeconds * x.miles, 0) / arr.reduce((s, x) => s + x.miles, 0) : null;
      out.push({ week: w, easy: avg(easy), quality: avg(qual),
                 miles: ww.reduce((s, x) => s + x.miles, 0) });
    }
    return out;
  }

  // ---- KDE density along the pace axis ----------------------
  function kde(workouts, bandwidth) {
    const bw = bandwidth || 16;
    const two = 2 * bw * bw;
    return function densityAt(pace) {
      let s = 0;
      for (const wo of workouts) {
        const dx = pace - wo.paceSeconds;
        s += wo.miles * Math.exp(-(dx * dx) / two);
      }
      return s;
    };
  }

  // ---- pace ↔ x scale (slow on the LEFT, fast on the RIGHT) -
  function makeScale(paceSlow, paceFast) {
    const span = paceSlow - paceFast;
    return {
      paceSlow, paceFast,
      xFromPace: (p, w) => Math.min(Math.max((paceSlow - p) / span, 0), 1) * w,
      paceFromX: (x, w) => paceSlow - (x / Math.max(w, 1)) * span,
    };
  }

  function fmtPace(seconds) {
    const t = Math.round(seconds);
    return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0");
  }

  // axis bounds — ALL vs WORKOUTS (filter the easy mass, tighten)
  const AXIS = {
    all:      { slow: 558, fast: 342, bw: 16 },   // 9:18 → 5:42
    workouts: { slow: 447, fast: 342, bw: 9 },    // MP → 5:42, quality only
  };
  function samplesFor(mode) {
    if (mode === "workouts") return WORKOUTS.filter((w) => w.paceSeconds <= AXIS.workouts.slow);
    return WORKOUTS;
  }

  // ---- block summary (single source of truth for the chrome) -
  const _blockTotal = WORKOUTS.reduce((s, w) => s + w.miles, 0);
  const _longRun = Math.max(...WORKOUTS.filter((w) => w.type === "Long").map((w) => w.miles));
  const SUMMARY = {
    blockTotal: Math.round(_blockTotal),
    avgWeek: Math.round(_blockTotal / 9),
    longRun: Math.round(_longRun),
  };

  window.PV = {
    ANCHORS, ZONES, QUALITY_IDS, WORKOUTS, AXIS, SUMMARY,
    zoneOf, zoneById, aggregate, weeklyTrend, kde, makeScale, fmtPace, samplesFor,
  };
})();
