/* global React */

/* Local copy of the time helper — this file is evaluated standalone by the
   design-system bundle, where the sibling screen file's `sec` is out of scope. */
const secFx = (m, s = 0) => m * 60 + s;
/* ════════════════════════════════════════════════════════════════════
   FIXTURES · four scenarios from outputs/fitness-predictor-scenarios.md
   The component reads `data` and renders accordingly; absent sections
   collapse so empty/injured states don't show garbage.
   ════════════════════════════════════════════════════════════════════ */

/* ─── MAIN · Scenario 5 — depth 3, Sarah, Boston-builder ─────────── */
const FIXTURE_MAIN = {
  scenario: "main",
  date: { eyebrow: "MONDAY · MAY 11", title: "Fitness, today." },
  status: "ACTIVE",

  // One-sentence coach read, with a number cited.
  headline: {
    text: "Anchored on your Apr 19 10K (38:35). Marathon reads 3:01 — tracking ahead of the 3:15 goal.",
  },

  // What the prediction is built on.
  anchor: {
    label: "10K",
    time: "38:35",
    when: "APR 19 · 3 WK AGO",
    sub: "Even splits. Confirmed by MP work May 6 and May 10.",
  },

  // 5 distance predictions.
  // Bands are in seconds; `low/pred/high` drive the visual.
  predictions: [
    {
      id: "mile",  label: "MILE",
      pred: secFx(5, 21), low: secFx(5, 13), high: secFx(5, 29),
      pr: secFx(5, 18), prDate: "JUN ’24",
      state: "wide",
      reasoning: "No work shorter than 400m strides.",
      sharpen: "Add a track mile or a downhill all-out.",
    },
    {
      id: "5k",    label: "5K",
      pred: secFx(18, 40), low: secFx(18, 23), high: secFx(18, 57),
      pr: secFx(19, 24), prDate: "OCT ’24",
      state: "moderate",
      reasoning: "Track sessions — no recent 5K race.",
      sharpen: "A 5K parkrun would tighten this.",
    },
    {
      id: "10k",   label: "10K",
      pred: secFx(38, 35), low: secFx(38, 0), high: secFx(39, 10),
      pr: secFx(38, 35), prDate: "APR ’26",
      state: "tight",
      reasoning: "Race anchor. 3 weeks fresh.",
      sharpen: null,
    },
    {
      id: "half",  label: "HALF",
      pred: secFx(85, 42), low: secFx(84, 25), high: secFx(86, 59),
      pr: secFx(87, 8),  prDate: "MAY ’26",
      state: "moderate",
      reasoning: "Apr 23 tempo · 4mi @ 6:30, solo.",
      sharpen: "7mi @ HMP this week would tighten this.",
    },
    {
      id: "mar",   label: "MARATHON",
      pred: secFx(181, 0), low: secFx(177, 0), high: secFx(185, 0),
      pr: secFx(194, 46), prDate: "BOSTON ’25",
      state: "moderate",
      reasoning: "MP work May 6 + 18mi w/ 6mi MP finish May 10.",
      sharpen: "A second 18mi w/ MP finish narrows this further.",
      goal: true,
    },
  ],

  // Goal vs current — surfaced honestly.
  goal: {
    race: "CHICAGO · OCT 12 · 22 WK OUT",
    target: "3:15",
    current: "3:01",
    deltaSec: -secFx(14, 0),
    interp: "Tracking ahead. Goal is conservative on this fitness.",
  },

  // What would tighten this — bulleted, no prose.
  softSpot: {
    items: [
      { text: "Second 18mi long run w/ MP finish", impact: "Marathon → tight" },
      { text: "7mi @ HMP this week",                impact: "Half → tight" },
      { text: "Race a 5K or parkrun",                impact: "5K · mile → tight" },
    ],
  },

  // Trajectory — predicted marathon over the block (9 wks).
  // Each is a week's snapshot in seconds.
  trajectory: {
    points: [
      { wk: 1, label: "MAR 16", pred: secFx(205, 0) },
      { wk: 2, label: "MAR 23", pred: secFx(202, 30) },
      { wk: 3, label: "MAR 30", pred: secFx(199, 12) },
      { wk: 4, label: "APR 6",  pred: secFx(196, 18) },
      { wk: 5, label: "APR 13", pred: secFx(194, 12) },
      { wk: 6, label: "APR 20", pred: secFx(190, 0) },
      { wk: 7, label: "APR 27", pred: secFx(188, 30) },
      { wk: 8, label: "MAY 4",  pred: secFx(184, 0) },
      { wk: 9, label: "MAY 11", pred: secFx(181, 0), current: true },
    ],
    goalSec: secFx(195, 0),
    deltaText: "↓ 24:00 OVER 9 WK",
  },

  // Context log — workouts where adjustments were applied.
  contextLog: [
    { date: "MAY 10", workout: "18mi long run",   adj: "Last 6mi at MP. Counted to marathon evidence." },
    { date: "MAY 6",  workout: "MP · 6mi",        adj: "+72°F humid · −5 sec/mi · pace adjusted" },
    { date: "APR 26", workout: "Long run · 16mi", adj: "Below 18mi — half-counts for marathon" },
    { date: "APR 19", workout: "10K race",        adj: "Anchor · cool, even splits" },
  ],

  // Data quality — what the predictor could and couldn't read.
  dataQuality: [
    { lbl: "STRUCTURE PARSED", val: "73 / 81", sub: "90% · ok",         tone: "ok" },
    { lbl: "WEATHER DATA",     val: "78 / 81", sub: "96% · ok",         tone: "ok" },
    { lbl: "VOICE LOGS · 14D", val: "9",       sub: "GOOD COVERAGE",    tone: "ok" },
    { lbl: "LAST HARD EFFORT", val: "5d",      sub: "WED · MP 6MI",     tone: "ok" },
  ],
};

/* ─── EMPTY · Scenario 1 — new user, depth 0 ─────────────────────── */
const FIXTURE_EMPTY = {
  scenario: "empty",
  date: { eyebrow: "MONDAY · MAY 11", title: "Not yet." },
  status: "EMPTY",

  // Empty-state copy per the redesign doc.
  emptyState: {
    eyebrow: "WHEN YOU’RE READY",
    body: "Connect Apple Health or log a hard run. One race or one structured workout is enough to start.",
    actions: ["Connect Apple Health", "Record a voice log"],
  },

  // Honest about what would unlock predictions.
  softSpot: {
    items: [
      { text: "Log one race or hard effort", impact: "5 distances unlock" },
      { text: "Sync 14 days of running",     impact: "Trend reads unlock" },
      { text: "Set a goal race",              impact: "Goal-vs-current unlocks" },
    ],
  },
};

/* ─── INJURED · Scenario 9 — returning from a 4-week layoff ──────── */
const FIXTURE_INJURED = {
  scenario: "injured",
  date: { eyebrow: "MONDAY · MAY 11", title: "Back in motion." },
  status: "RETURNING",

  headline: {
    text: "Off a 4-week break + 5 weeks easy. Ranges wide — no recent quality.",
  },

  anchor: {
    label: "10K",
    time: "38:35",
    when: "MAR 8 · 9 WK AGO · DECAYED",
    sub: "Pre-injury proof. Adjusted for the gap and the easy-only return.",
  },

  predictions: [
    { id: "mile",  label: "MILE",
      pred: secFx(5, 40), low: secFx(5, 20), high: secFx(6, 0),
      pr: secFx(5, 18), prDate: "JUN ’24",
      state: "wide",
      reasoning: "No quality work since March.",
      sharpen: "Strides first. Tempo when calf is quiet.",
    },
    { id: "5k",    label: "5K",
      pred: secFx(19, 45), low: secFx(18, 50), high: secFx(20, 40),
      pr: secFx(19, 24), prDate: "OCT ’24",
      state: "wide",
      reasoning: "Decayed prediction. No fresh signal.",
      sharpen: "A tempo or interval session.",
    },
    { id: "10k",   label: "10K",
      pred: secFx(41, 0), low: secFx(39, 30), high: secFx(42, 30),
      pr: secFx(38, 35), prDate: "MAR ’26",
      state: "wide",
      reasoning: "Detraining decay applied (~6%).",
      sharpen: "Re-race a 10K in 4 weeks.",
    },
    { id: "half",  label: "HALF",
      pred: secFx(91, 0), low: secFx(86, 0), high: secFx(96, 0),
      pr: secFx(87, 8), prDate: "MAY ’26",
      state: "wide",
      reasoning: "No HMP work in window.",
      sharpen: "7mi @ HMP when comfortable.",
    },
    { id: "mar",   label: "MARATHON",
      pred: secFx(195, 0), low: secFx(179, 0), high: secFx(211, 0),
      pr: secFx(194, 46), prDate: "BOSTON ’25",
      state: "wide",
      reasoning: "Zero MP work + zero long runs ≥18mi.",
      sharpen: "16mi long run · the next step.",
      goal: true,
    },
  ],

  goal: {
    race: "CHICAGO · OCT 12 · 22 WK OUT",
    target: "3:15",
    current: "3:15",
    deltaSec: 0,
    interp: "Realistic if the next 8 weeks build cleanly.",
  },

  softSpot: {
    items: [
      { text: "First tempo back",            impact: "Half → moderate" },
      { text: "First 12mi long run",         impact: "Marathon → moderate" },
      { text: "No body part flagged 14 days", impact: "Ranges tighten" },
    ],
  },

  contextLog: [
    { date: "MAY 9",  workout: "Easy · 7mi",   adj: "First comfortable run. Pace progressing." },
    { date: "APR 21", workout: "Easy · 5mi",   adj: "Calf quiet. Cleared to build." },
    { date: "APR 8",  workout: "Walk-jog · 3", adj: "Return-to-run start." },
    { date: "MAR 10–APR 5", workout: "Layoff · 4 wk", adj: "Left calf strain. No runs." },
  ],

  dataQuality: [
    { lbl: "STRUCTURE PARSED", val: "9 / 10",  sub: "EASY ONLY",     tone: "warn" },
    { lbl: "WEATHER DATA",     val: "10 / 10", sub: "OK",            tone: "ok" },
    { lbl: "VOICE LOGS · 14D", val: "4",       sub: "MENTION CALF 1×", tone: "warn" },
    { lbl: "LAST HARD EFFORT", val: "63d",     sub: "MAR 8 RACE",    tone: "warn" },
  ],
};

/* ─── GOAL MISMATCH · Scenario 10 — goal is faster than fitness ─── */
const FIXTURE_GOAL_GAP = {
  scenario: "goal-gap",
  date: { eyebrow: "MONDAY · MAY 11", title: "About that 3:00." },
  status: "GAP",

  headline: {
    text: "Fitness reads 3:01–3:09. Goal is 3:00 — at the edge of what training supports.",
  },

  anchor: {
    label: "10K",
    time: "38:35",
    when: "APR 19 · 3 WK AGO",
    sub: "Same data as the happy path. Different ask of the day.",
  },

  predictions: [
    { id: "mile",  label: "MILE",
      pred: secFx(5, 21), low: secFx(5, 13), high: secFx(5, 29),
      pr: secFx(5, 18), prDate: "JUN ’24",
      state: "wide",
      reasoning: "No anaerobic work.",
      sharpen: "A track mile.",
    },
    { id: "5k",    label: "5K",
      pred: secFx(18, 40), low: secFx(18, 23), high: secFx(18, 57),
      pr: secFx(19, 24), prDate: "OCT ’24",
      state: "moderate",
      reasoning: "Track sessions, no recent race.",
      sharpen: "5K parkrun.",
    },
    { id: "10k",   label: "10K",
      pred: secFx(38, 35), low: secFx(38, 0), high: secFx(39, 10),
      pr: secFx(38, 35), prDate: "APR ’26",
      state: "tight",
      reasoning: "Race anchor, 3 weeks fresh.",
      sharpen: null,
    },
    { id: "half",  label: "HALF",
      pred: secFx(85, 42), low: secFx(84, 25), high: secFx(86, 59),
      pr: secFx(87, 8),   prDate: "MAY ’26",
      state: "moderate",
      reasoning: "Tempo work, no race.",
      sharpen: "7mi @ HMP.",
    },
    { id: "mar",   label: "MARATHON",
      pred: secFx(181, 0), low: secFx(177, 0), high: secFx(185, 0),
      pr: secFx(194, 46), prDate: "BOSTON ’25",
      state: "moderate",
      reasoning: "MP work May 6 + 6mi MP finish May 10.",
      sharpen: "Second 18mi w/ MP finish.",
      goal: true,
    },
  ],

  goal: {
    race: "CHICAGO · OCT 12 · 22 WK OUT",
    target: "3:00",
    current: "3:01",
    deltaSec: secFx(1, 0),
    interp: "Achievable on a great day. Not the median.",
    flag: true,
  },

  softSpot: {
    items: [
      { text: "Conversation with coach about the target", impact: "Re-align plan" },
      { text: "Two more MP sessions at 6:52/mi",          impact: "3:00 becomes the read" },
      { text: "20mi long run with MP finish",             impact: "Marathon → tight" },
    ],
  },

  contextLog: [
    { date: "MAY 10", workout: "18mi long run", adj: "Last 6mi at 7:25 — not 6:52" },
    { date: "MAY 6",  workout: "MP · 6mi",       adj: "Held 7:26 — 34 sec/mi off 3:00 pace" },
    { date: "APR 19", workout: "10K race",       adj: "Equivalent marathon ~3:01" },
  ],

  dataQuality: [
    { lbl: "STRUCTURE PARSED", val: "73 / 81", sub: "90% · ok",       tone: "ok" },
    { lbl: "WEATHER DATA",     val: "78 / 81", sub: "96% · ok",       tone: "ok" },
    { lbl: "GOAL vs FITNESS",  val: "−1 min",  sub: "GOAL FASTER",    tone: "warn" },
    { lbl: "LAST HARD EFFORT", val: "5d",      sub: "WED · MP 6MI",   tone: "ok" },
  ],
};

window.FP_FIXTURES = {
  main:     FIXTURE_MAIN,
  empty:    FIXTURE_EMPTY,
  injured:  FIXTURE_INJURED,
  goalGap:  FIXTURE_GOAL_GAP,
};
