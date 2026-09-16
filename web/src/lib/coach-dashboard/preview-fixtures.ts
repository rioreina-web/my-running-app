import type { ChartLap, DashboardDay } from "./types";

/**
 * Design-preview fixture for the redesigned WorkoutDrawer (FIG 24).
 *
 * The canonical Jul 11 example from the redesign spec: a hot, hilly long run
 * cut at 15 mi, logged "struggling", voice note explains the heat + the cut.
 * This is the SAME run drawn in coach-workout-detail-mock.html — the fixture
 * lets us render the production drawer with the mock's data so design and code
 * can be diffed pixel-for-pixel. Fixtures never touch Supabase.
 */

// Per-mile raw pace (sec/mi) — matches the mock's MP[] array exactly.
const MP = [545, 538, 542, 550, 544, 552, 558, 562, 571, 566, 588, 595, 602, 611, 624];
const RAN_MI = 15;

// Telemetry samples at quarter-mile resolution, reproducing the mock's
// paceAt / elevAt / hrAt generators so the ported chart draws the same curve.
function buildLaps(): ChartLap[] {
  const paceAt = (d: number) => {
    const i = Math.min(13.999, Math.max(0, d - 0.5));
    const a = MP[Math.floor(i)];
    const b = MP[Math.ceil(i)];
    const t = i - Math.floor(i);
    return a + (b - a) * t + 5 * Math.sin(d * 1.15 + 0.35);
  };
  const elevAt = (d: number) => 96 + 46 * Math.sin(d * 1.15) + 24 * Math.sin(d * 0.45 + 1);
  const hrAt = (d: number) => Math.round(136 + 1.65 * d + 3 * Math.sin(d * 1.15 + 0.5));
  const laps: ChartLap[] = [];
  for (let i = 0; i <= RAN_MI * 4; i++) {
    const d = i / 4;
    // heat-adjusted pace runs ~30s faster than raw in the hot back half
    const adj = paceAt(d) - (18 + 14 * Math.min(1, d / RAN_MI));
    laps.push({ mi: d, paceSec: paceAt(d), adjPaceSec: adj, hr: hrAt(d), elevFt: elevAt(d) });
  }
  return laps;
}

export const PREVIEW_JUL11_LONG_RUN: DashboardDay = {
  id: "preview-jul11",
  date: "2026-07-11",
  dateLabel: "Jul 11",
  dow: "Sat",
  label: "Long run, cut at 15.",
  zone: "longRun",
  miles: 15,
  actual: "15.0 mi · 9:30/mi",
  delta: "cut at 15",
  onTarget: false,
  key: true,
  mood: "struggling",
  niggle: null,
  note:
    "I had an extremely warm run on a hilly loop and felt like I was dying, despite trying to pace myself. I cut my planned 2 hour 15 minute run short as it wasn’t a good run at all. I’m focusing on recovery today, Sunday, and hoping for a better week.",
  logged: true,
  detail: {
    kpis: [
      { k: "Distance", v: "15.0 mi", sub: "of **16** planned" },
      { k: "Time", v: "2:22:28", sub: "planned **~2:15**" },
      { k: "Pace", v: "9:30/mi", sub: "vs **8:55–9:25**" },
      { k: "Heat-adj", v: "8:59/mi", sub: "**−31s** · in band", accent: true },
    ],
    splitLabel: "Splits · vs 8:55–9:25",
    splits: [
      { name: "Miles 1–5", pace: "9:04", adj: "8:46", onTarget: true },
      { name: "Miles 6–10", pace: "9:22", adj: "8:54", onTarget: true },
      { name: "Miles 11–15", pace: "10:04", adj: "9:21", onTarget: false },
      { name: "Mile 16", pace: null, onTarget: false },
    ],
    prescribed: {
      label: "Long",
      distance: 16,
      window: "8:55–9:25",
      timeEst: "~2:15",
      cutAtMi: -1.0,
    },
    conditions: {
      tempF: 84,
      dewPointF: 71,
      dewHot: true,
      climbFt: 1240,
      hrAvg: 148,
      hrZone: "Z3",
      drift: "+8.4%",
      startTime: "9:41 AM",
      caption:
        "Dew point 71° sits past the 68° hot threshold — every lap carried a heat adjustment. HR drifted **+8.4%** in the back half at falling pace.",
    },
    chart: {
      laps: buildLaps(),
      bandLow: 535,
      bandHigh: 565,
      plannedMi: 16,
      cutAtMi: 15,
      climbLabel: "+1,240 ft",
      caption:
        "In the band through 10 on rolling climbs, then the fade — the last 5 all over 9:45 as the morning warmed, HR still climbing at falling pace. Stopped at 15 with 2:15 already gone.",
    },
    weekContext: {
      runOfWeek: "Run 5 of 6",
      milesSoFar: 38,
      milesPlanned: 44,
      acwr: 1.24,
      acwrBand: "high",
      loadLine:
        "Run 5 of 6 this week · **38.0 of 44 mi** planned. This run brought ACWR to **1.24** — high end of the sweet band.",
      nextKey: { label: "MP 8 mi · Tue Jul 14", zone: "mp" },
    },
    bodyContext: {
      line: "No niggles mentioned on this run.",
      sub: "Left calf last flagged Jul 3 — quiet for 8 days.",
    },
    read: {
      body:
        "Heat, not fitness. The raw 9:30 reads like a miss, but heat-adjusted he ran **8:59** — inside the long-run band — and the fade tracks the 71° dew point more than the hills. He made the call to stop at 15 himself, and had already penciled his own recovery day before you saw this.",
      question:
        "Second struggling mood on a key day this block, both in heat — worth asking how he’s sleeping before Tuesday’s MP session?",
    },
  },
};
