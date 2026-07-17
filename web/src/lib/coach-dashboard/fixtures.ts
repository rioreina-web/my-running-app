// Coach athlete dashboard — Maya fixtures.
//
// Illustrative-but-coherent sample data for the canonical persona (Maya Chen:
// 3:28 marathon PB chasing a 3:16 BQ). Shaped to the real tables so the swap
// to live Supabase reads in get-dashboard.ts is mechanical. Pace zones are the
// real PaceZone union; the 10-zone ladder derives from the 3:28:41 anchor
// (MP 7:57) per CLAUDE.md.
//
// Not wired to the DB. Only get-dashboard.ts imports this.

import type {
  AthleteHeader,
  Acwr,
  CoachableMoment,
  DashboardDay,
  NiggleGroup,
  Progression,
  WatchItem,
  WeeklyVolumeWeek,
} from "./types";

export const mayaHeader: AthleteHeader = {
  name: "Maya Chen",
  initials: "MC",
  planName: "Fall Marathon Block",
  bio: "Self-coached, chasing a Boston qualifier. ~40 mpw base, races every fall. Journals every run — reads honest observation over prescription.",
  weekNumber: 9,
  totalWeeks: 16,
  goalTime: "3:16:00",
  goalNote: "Boston qualifier",
  anchorTime: "3:28:41",
  anchorRace: "marathon · Mar 15, 2026",
  marathonPace: "7:57",
  newRaceNudge: {
    text: "**New race on file:** 1:36:12 half, Jun 1 — predicts a **~3:22** marathon. Paces are still anchored on March's 3:28. Re-anchoring is a coach action (Phase 2).",
  },
};

export const mayaWatchList: WatchItem[] = [
  {
    severity: "warn",
    title: "Left calf — **3 mentions / 4 weeks**",
    detail: "Most recent Jul 11 on the LT reps. Recurrence flagged.",
  },
  {
    severity: "mid",
    title: "Easy pace drifting **faster**",
    detail: "Easy runs 16s/mi quicker than 6 weeks ago at the same HR.",
  },
  {
    severity: "mid",
    title: "Newer race than anchor",
    detail: "Jun half predicts ~3:22; plan paces still on the March 3:28.",
  },
];

export const mayaMoments: CoachableMoment[] = [
  {
    id: "cm-mood-1",
    kind: "Mood pattern",
    when: "This block",
    observation:
      "Mood dips to **struggling** only on the hardest sessions — the Jul 8 MP and the Jul 11 LT. Positive or energized on the easy days around them.",
    softQuestion: "Is the hard/easy contrast landing where you'd want it?",
    severity: "med",
  },
  {
    id: "cm-niggle-1",
    kind: "Niggle cluster",
    when: "4 weeks",
    observation:
      "Left calf surfaced **3 times**, always on quality days, always self-managed. Never on easy runs.",
    softQuestion: "She keeps backing off rather than stopping — worth a look.",
    severity: "high",
  },
  {
    id: "cm-fitness-1",
    kind: "Fitness trend",
    when: "6 weeks",
    observation:
      "Easy runs **16s/mi faster** at the same heart rate — a real aerobic gain, consistent with the June half.",
    softQuestion: "Do the plan paces still reflect the engine?",
    severity: "low",
  },
];

export const mayaOverlayRead = {
  body: "The three quality spikes — **MP Jul 8**, **LT Jul 11** — line up cleanly with the only two **struggling** mood days and the recent **calf** ticks. Easy days between them stay green. The pattern is load, not a bad patch.",
  question:
    "The engine's fine on easy days. It's the back half of the hard week that's costing her — worth re-sequencing?",
};

export const mayaProgression: Progression = {
  prediction: {
    low: "3:19",
    high: "3:24",
    confidence: "high",
    basis: "4 marathon-pace workouts and a recent half (1:36:12, Jun 1)",
  },
  goalTime: "3:16:00",
  gapLabel: "3–8 min from range",
  trendArrow: "up",
  trendText:
    "**Trending up.** Easy runs averaging **9:02/mi** vs. 9:18 six weeks ago at the same heart rate (~145 bpm).",
  fitnessSeries: [
    46, 47, 48, 49, 51, 50, 52, 54, 53, 55, 57, 56, 58, 54, 60, 62, 61, 63, 66,
    64, 67, 69, 68, 70, 71, 68,
  ],
  fitnessMonths: [
    { label: "Jan", weekIndex: 0.5 },
    { label: "Feb", weekIndex: 4.5 },
    { label: "Mar", weekIndex: 8.5 },
    { label: "Apr", weekIndex: 13 },
    { label: "May", weekIndex: 17.5 },
    { label: "Jun", weekIndex: 21.5 },
    { label: "Jul", weekIndex: 25 },
  ],
  races: [
    { weekIndex: 10, label: "3:28 mar" },
    { weekIndex: 16, label: "40:12 10K" },
    { weekIndex: 21, label: "1:36 half" },
  ],
  projection: { rangeLabel: "3:19–3:24", goalLabel: "GOAL", xLabel: "~SEP" },
};

// 12 weekly volume buckets, oldest → newest. Zone keys are real PaceZone
// values; the current (in-progress) week gets the coral outline.
export const mayaWeeklyVolume: WeeklyVolumeWeek[] = [
  { label: "Apr 27", zoneMiles: { easy: 30, steady: 5, mp: 5 }, targetMiles: 42 },
  { label: "May 4", zoneMiles: { easy: 32, steady: 6, threshold: 4 }, targetMiles: 44 },
  { label: "May 11", zoneMiles: { easy: 33, moderate: 5, mp: 6 }, targetMiles: 46 },
  { label: "May 18", zoneMiles: { easy: 30, steady: 4 }, targetMiles: 44 },
  { label: "May 25", zoneMiles: { easy: 36, steady: 6, mp: 6 }, targetMiles: 48 },
  { label: "Jun 1", zoneMiles: { easy: 33, hm: 13 }, targetMiles: 48 },
  { label: "Jun 8", zoneMiles: { easy: 40, steady: 6, threshold: 5 }, targetMiles: 50 },
  { label: "Jun 15", zoneMiles: { easy: 42, mp: 8 }, targetMiles: 52 },
  { label: "Jun 22", zoneMiles: { easy: 44, steady: 6, tenK: 6 }, targetMiles: 54 },
  { label: "Jun 29", zoneMiles: { easy: 40, mp: 8, fiveK: 4 }, targetMiles: 52 },
  { label: "Jul 6", zoneMiles: { easy: 38, threshold: 6, hm: 4 }, targetMiles: 50 },
  { label: "Jul 13", zoneMiles: { easy: 30, mp: 6 }, targetMiles: 40, current: true },
];

export const mayaAcwr: Acwr = {
  value: 1.12,
  band: "sweet",
  bandLabel: "Sweet spot",
  monotony7d: 1.5,
  strain7d: 412,
};

// One resolved niggle outside the 35-day window — get-dashboard appends it to
// the derived (in-window) groups so the panel shows a struck-through item.
export const mayaResolvedNiggles: NiggleGroup[] = [
  {
    area: "Left hamstring",
    mentions: 1,
    latestDate: "May 30",
    latestQuote: "hammy tight during strides, loosened up.",
    otherDates: [],
    recurrence: false,
    resolved: true,
  },
];

// 35 daily entries (Jun 12 → Jul 16, 2026), oldest → newest.
export const mayaDays: DashboardDay[] = [
  { id: "2026-06-12", date: "2026-06-12", dateLabel: "Jun 12", dow: "Fri", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:08/mi", delta: "on target", onTarget: true, key: false, mood: "positive", niggle: null, note: "" },
  { id: "2026-06-13", date: "2026-06-13", dateLabel: "Jun 13", dow: "Sat", label: "Easy 5 mi", zone: "easy", miles: 5, actual: "5.0 mi · 9:12/mi", delta: "steady", onTarget: false, key: false, mood: "energized", niggle: null, note: "" },
  { id: "2026-06-14", date: "2026-06-14", dateLabel: "Jun 14", dow: "Sun", label: "Long 13 mi", zone: "longRun", miles: 13, actual: "13.1 mi · 9:00/mi", delta: "steady", onTarget: false, key: true, mood: "positive", niggle: null, note: "Comfortable long run, rolled the last three downhill.",
    detail: { kpis: [{ k: "Distance", v: "13.1 mi" }, { k: "Avg pace", v: "9:00/mi" }, { k: "Type", v: "Aerobic long" }, { k: "Mood", v: "positive" }], splitLabel: "Splits by third", splits: [{ name: "First 4 mi", pace: "9:06", onTarget: false }, { name: "Middle 5 mi", pace: "9:01", onTarget: false }, { name: "Last 4 mi", pace: "8:52", onTarget: true }] } },
  { id: "2026-06-15", date: "2026-06-15", dateLabel: "Jun 15", dow: "Mon", label: "Easy 5 mi", zone: "easy", miles: 5, actual: "5.0 mi · 9:14/mi", delta: "on target", onTarget: true, key: false, mood: "neutral", niggle: { area: "Right foot · arch", quote: "arch a touch sore first mile, faded" }, note: "Arch a touch sore early, went away once warm." },
  { id: "2026-06-16", date: "2026-06-16", dateLabel: "Jun 16", dow: "Tue", label: "MP 7 mi", zone: "mp", miles: 7, actual: "7.0 mi · 7:58/mi", delta: "on pace", onTarget: true, key: true, mood: "positive", niggle: null, note: "Marathon pace felt smooth and controlled the whole way.",
    detail: { kpis: [{ k: "Distance", v: "7.0 mi" }, { k: "MP avg", v: "7:58/mi" }, { k: "Vs target 7:57", v: "on pace" }, { k: "Mood", v: "positive" }], splitLabel: "MP miles vs 7:57", splits: [{ name: "Mile 1", pace: "7:59", onTarget: false }, { name: "Mile 2", pace: "7:58", onTarget: false }, { name: "Mile 3", pace: "7:58", onTarget: false }, { name: "Mile 4", pace: "7:57", onTarget: true }, { name: "Mile 5", pace: "7:57", onTarget: true }, { name: "Mile 6", pace: "7:56", onTarget: true }, { name: "Mile 7", pace: "7:58", onTarget: false }] } },
  { id: "2026-06-17", date: "2026-06-17", dateLabel: "Jun 17", dow: "Wed", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:10/mi", delta: "on target", onTarget: true, key: false, mood: "positive", niggle: null, note: "" },
  { id: "2026-06-18", date: "2026-06-18", dateLabel: "Jun 18", dow: "Thu", label: "Easy 5 mi", zone: "easy", miles: 5, actual: "5.0 mi · 9:15/mi", delta: "steady", onTarget: false, key: false, mood: "energized", niggle: null, note: "" },
  { id: "2026-06-19", date: "2026-06-19", dateLabel: "Jun 19", dow: "Fri", label: "LT 5×1mi", zone: "threshold", miles: 5, actual: "5×1mi · 7:31/mi", delta: "on target", onTarget: true, key: true, mood: "tired", niggle: { area: "Left calf", quote: "calf a little tight on the reps, manageable" }, note: "Calf a little tight but held the paces through all five.",
    detail: { kpis: [{ k: "Reps", v: "5 × 1 mi" }, { k: "LT avg", v: "7:31/mi" }, { k: "Vs target 7:31", v: "on target" }, { k: "Mood", v: "tired" }], splitLabel: "Reps vs 7:31", splits: [{ name: "Rep 1", pace: "7:33", onTarget: false }, { name: "Rep 2", pace: "7:31", onTarget: true }, { name: "Rep 3", pace: "7:31", onTarget: true }, { name: "Rep 4", pace: "7:30", onTarget: true }, { name: "Rep 5", pace: "7:30", onTarget: true }] } },
  { id: "2026-06-20", date: "2026-06-20", dateLabel: "Jun 20", dow: "Sat", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:12/mi", delta: "steady", onTarget: false, key: false, mood: "neutral", niggle: null, note: "" },
  { id: "2026-06-21", date: "2026-06-21", dateLabel: "Jun 21", dow: "Sun", label: "Long 14 mi", zone: "longRun", miles: 14, actual: "14.0 mi · 8:58/mi", delta: "neg split", onTarget: true, key: true, mood: "positive", niggle: null, note: "Best long run in a while — negative split without forcing it.",
    detail: { kpis: [{ k: "Distance", v: "14.0 mi" }, { k: "Avg pace", v: "8:58/mi" }, { k: "Finish", v: "negative split" }, { k: "Mood", v: "positive" }], splitLabel: "Splits by third", splits: [{ name: "First 5 mi", pace: "9:05", onTarget: false }, { name: "Middle 5 mi", pace: "8:58", onTarget: true }, { name: "Last 4 mi", pace: "8:49", onTarget: true }] } },
  { id: "2026-06-22", date: "2026-06-22", dateLabel: "Jun 22", dow: "Mon", label: "Rest", zone: null, miles: 0, actual: null, delta: null, onTarget: false, key: false, mood: "positive", niggle: null, note: "" },
  { id: "2026-06-23", date: "2026-06-23", dateLabel: "Jun 23", dow: "Tue", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:09/mi", delta: "on target", onTarget: true, key: false, mood: "energized", niggle: null, note: "" },
  { id: "2026-06-24", date: "2026-06-24", dateLabel: "Jun 24", dow: "Wed", label: "HM 5 mi", zone: "hm", miles: 5, actual: "5.0 mi · 7:43/mi", delta: "1s under", onTarget: false, key: true, mood: "neutral", niggle: { area: "Right foot · arch", quote: "arch sore after, fine walking around" }, note: "Tight to start, arch sore after but nothing sharp.",
    detail: { kpis: [{ k: "Distance", v: "5.0 mi" }, { k: "HM avg", v: "7:43/mi" }, { k: "Vs target 7:42", v: "1s over" }, { k: "Mood", v: "neutral" }], splitLabel: "Miles vs 7:42", splits: [{ name: "Mile 1", pace: "7:49", onTarget: false }, { name: "Mile 2", pace: "7:44", onTarget: false }, { name: "Mile 3", pace: "7:42", onTarget: true }, { name: "Mile 4", pace: "7:41", onTarget: true }, { name: "Mile 5", pace: "7:39", onTarget: true }] } },
  { id: "2026-06-25", date: "2026-06-25", dateLabel: "Jun 25", dow: "Thu", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:11/mi", delta: "on target", onTarget: true, key: false, mood: "positive", niggle: null, note: "" },
  { id: "2026-06-26", date: "2026-06-26", dateLabel: "Jun 26", dow: "Fri", label: "Easy 5 mi", zone: "easy", miles: 5, actual: "5.0 mi · 9:13/mi", delta: "steady", onTarget: false, key: false, mood: "positive", niggle: null, note: "" },
  { id: "2026-06-27", date: "2026-06-27", dateLabel: "Jun 27", dow: "Sat", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:08/mi", delta: "on target", onTarget: true, key: false, mood: "energized", niggle: null, note: "" },
  { id: "2026-06-28", date: "2026-06-28", dateLabel: "Jun 28", dow: "Sun", label: "Long 15 mi", zone: "longRun", miles: 15, actual: "15.0 mi · 9:01/mi", delta: "peak long", onTarget: false, key: true, mood: "tired", niggle: null, note: "Longest of the block — legs cooked at the end but fueling was dialed.",
    detail: { kpis: [{ k: "Distance", v: "15.0 mi" }, { k: "Avg pace", v: "9:01/mi" }, { k: "Note", v: "peak long" }, { k: "Mood", v: "tired" }], splitLabel: "Splits by third", splits: [{ name: "First 5 mi", pace: "9:04", onTarget: false }, { name: "Middle 5 mi", pace: "9:00", onTarget: true }, { name: "Last 5 mi", pace: "8:59", onTarget: true }] } },
  { id: "2026-06-29", date: "2026-06-29", dateLabel: "Jun 29", dow: "Mon", label: "Rest", zone: null, miles: 0, actual: null, delta: null, onTarget: false, key: false, mood: "neutral", niggle: null, note: "" },
  { id: "2026-06-30", date: "2026-06-30", dateLabel: "Jun 30", dow: "Tue", label: "MP 8 mi", zone: "mp", miles: 8, actual: "8.0 mi · 7:58/mi", delta: "on pace", onTarget: true, key: true, mood: "positive", niggle: { area: "Left calf", quote: "felt the calf warming up, settled once going" }, note: "Calf spoke early then went quiet — MP dialed after that.",
    detail: { kpis: [{ k: "Distance", v: "8.0 mi" }, { k: "MP avg", v: "7:58/mi" }, { k: "Vs target 7:57", v: "on pace" }, { k: "Mood", v: "positive" }], splitLabel: "MP miles vs 7:57", splits: [{ name: "Mile 1", pace: "8:00", onTarget: false }, { name: "Mile 2", pace: "7:59", onTarget: false }, { name: "Mile 3", pace: "7:58", onTarget: false }, { name: "Mile 4", pace: "7:58", onTarget: false }, { name: "Mile 5", pace: "7:57", onTarget: true }, { name: "Mile 6", pace: "7:57", onTarget: true }, { name: "Mile 7", pace: "7:57", onTarget: true }, { name: "Mile 8", pace: "7:56", onTarget: true }] } },
  { id: "2026-07-01", date: "2026-07-01", dateLabel: "Jul 1", dow: "Wed", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:10/mi", delta: "on target", onTarget: true, key: false, mood: "positive", niggle: null, note: "" },
  { id: "2026-07-02", date: "2026-07-02", dateLabel: "Jul 2", dow: "Thu", label: "Easy 5 mi", zone: "easy", miles: 5, actual: "5.0 mi · 9:16/mi", delta: "steady", onTarget: false, key: false, mood: "energized", niggle: null, note: "" },
  { id: "2026-07-03", date: "2026-07-03", dateLabel: "Jul 3", dow: "Fri", label: "LT 6×1mi", zone: "threshold", miles: 6, actual: "6×1mi · 7:30/mi", delta: "1s under", onTarget: true, key: true, mood: "tired", niggle: null, note: "All six reps on — best threshold session of the block yet.",
    detail: { kpis: [{ k: "Reps", v: "6 × 1 mi" }, { k: "LT avg", v: "7:30/mi" }, { k: "Vs target 7:31", v: "1s under" }, { k: "Mood", v: "tired" }], splitLabel: "Reps vs 7:31", splits: [{ name: "Rep 1", pace: "7:31", onTarget: true }, { name: "Rep 2", pace: "7:30", onTarget: true }, { name: "Rep 3", pace: "7:30", onTarget: true }, { name: "Rep 4", pace: "7:31", onTarget: true }, { name: "Rep 5", pace: "7:29", onTarget: true }, { name: "Rep 6", pace: "7:30", onTarget: true }] } },
  { id: "2026-07-04", date: "2026-07-04", dateLabel: "Jul 4", dow: "Sat", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:12/mi", delta: "steady", onTarget: false, key: false, mood: "positive", niggle: null, note: "" },
  { id: "2026-07-05", date: "2026-07-05", dateLabel: "Jul 5", dow: "Sun", label: "Long 13 mi", zone: "longRun", miles: 13, actual: "13.1 mi · 9:00/mi", delta: "steady", onTarget: false, key: true, mood: "positive", niggle: null, note: "Easy long, base feels deep right now.",
    detail: { kpis: [{ k: "Distance", v: "13.1 mi" }, { k: "Avg pace", v: "9:00/mi" }, { k: "Type", v: "Aerobic long" }, { k: "Mood", v: "positive" }], splitLabel: "Splits by third", splits: [{ name: "First 4 mi", pace: "9:03", onTarget: false }, { name: "Middle 5 mi", pace: "9:00", onTarget: true }, { name: "Last 4 mi", pace: "8:57", onTarget: true }] } },
  { id: "2026-07-06", date: "2026-07-06", dateLabel: "Jul 6", dow: "Mon", label: "Rest", zone: null, miles: 0, actual: null, delta: null, onTarget: false, key: false, mood: "positive", niggle: null, note: "" },
  { id: "2026-07-07", date: "2026-07-07", dateLabel: "Jul 7", dow: "Tue", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:11/mi", delta: "on target", onTarget: true, key: false, mood: "neutral", niggle: null, note: "" },
  { id: "2026-07-08", date: "2026-07-08", dateLabel: "Jul 8", dow: "Wed", label: "MP 8 mi", zone: "mp", miles: 8, actual: "8.0 mi · 7:58/mi", delta: "on pace", onTarget: true, key: true, mood: "struggling", niggle: null, note: "Grind. Legs heavy from the week and it never clicked, but I got the paces done. Glad it is behind me.",
    detail: { kpis: [{ k: "Distance", v: "8.0 mi" }, { k: "MP avg", v: "7:58/mi" }, { k: "Vs target 7:57", v: "on pace" }, { k: "Mood", v: "struggling" }], splitLabel: "MP miles vs 7:57", splits: [{ name: "Mile 1", pace: "7:56", onTarget: true }, { name: "Mile 2", pace: "7:57", onTarget: true }, { name: "Mile 3", pace: "7:58", onTarget: false }, { name: "Mile 4", pace: "7:59", onTarget: false }, { name: "Mile 5", pace: "7:58", onTarget: false }, { name: "Mile 6", pace: "7:59", onTarget: false }, { name: "Mile 7", pace: "7:58", onTarget: false }, { name: "Mile 8", pace: "7:57", onTarget: true }] } },
  { id: "2026-07-09", date: "2026-07-09", dateLabel: "Jul 9", dow: "Thu", label: "Easy 5 mi", zone: "easy", miles: 5, actual: "4.9 mi · 9:20/mi", delta: "short on time", onTarget: false, key: false, mood: "tired", niggle: null, note: "Legs flat, kept it short and easy." },
  { id: "2026-07-10", date: "2026-07-10", dateLabel: "Jul 10", dow: "Fri", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:08/mi", delta: "on target", onTarget: true, key: false, mood: "positive", niggle: null, note: "" },
  { id: "2026-07-11", date: "2026-07-11", dateLabel: "Jul 11", dow: "Sat", label: "LT 6×1mi", zone: "threshold", miles: 5, actual: "5×1mi · 7:29/mi", delta: "cut 1 rep", onTarget: false, key: true, mood: "struggling", niggle: { area: "Left calf", quote: "cut it one rep short, left calf talking on the reps" }, note: "Cut it one rep short, left calf talking on the reps. Backed off to be safe rather than push through — paces were on when I ran.",
    detail: { kpis: [{ k: "Reps", v: "5 of 6 × 1 mi" }, { k: "LT avg", v: "7:29/mi" }, { k: "Vs target 7:31", v: "2s under" }, { k: "Mood", v: "struggling" }], splitLabel: "Reps vs 7:31", splits: [{ name: "Rep 1", pace: "7:30", onTarget: true }, { name: "Rep 2", pace: "7:29", onTarget: true }, { name: "Rep 3", pace: "7:29", onTarget: true }, { name: "Rep 4", pace: "7:28", onTarget: true }, { name: "Rep 5", pace: "7:31", onTarget: true }, { name: "Rep 6", pace: null, onTarget: false }] } },
  { id: "2026-07-12", date: "2026-07-12", dateLabel: "Jul 12", dow: "Sun", label: "Long 14 · MP 6", zone: "longRun", miles: 14, actual: "14.0 mi · MP segs 7:55", delta: "2s under", onTarget: true, key: true, mood: "positive", niggle: null, note: "Held marathon pace better than expected in the back half. Calf quiet with the easy warm-up in front of it.",
    detail: { kpis: [{ k: "Distance", v: "14.0 mi" }, { k: "MP-seg avg", v: "7:55/mi" }, { k: "Vs target 7:57", v: "2s under" }, { k: "Mood", v: "positive" }], splitLabel: "Structure", splits: [{ name: "Warm-up 4 mi", pace: "9:08", onTarget: false }, { name: "MP mi 1", pace: "7:58", onTarget: false }, { name: "MP mi 2", pace: "7:56", onTarget: true }, { name: "MP mi 3", pace: "7:55", onTarget: true }, { name: "MP mi 4", pace: "7:55", onTarget: true }, { name: "MP mi 5", pace: "7:53", onTarget: true }, { name: "MP mi 6", pace: "7:52", onTarget: true }, { name: "Cool-down 4 mi", pace: "9:10", onTarget: false }] } },
  { id: "2026-07-13", date: "2026-07-13", dateLabel: "Jul 13", dow: "Mon", label: "Rest", zone: null, miles: 0, actual: null, delta: null, onTarget: false, key: false, mood: "positive", niggle: null, note: "" },
  { id: "2026-07-14", date: "2026-07-14", dateLabel: "Jul 14", dow: "Tue", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.1 mi · 9:04/mi", delta: "2s under", onTarget: false, key: false, mood: "energized", niggle: null, note: "Legs springy this morning, calf quiet today. Nice way to open the week." },
  { id: "2026-07-15", date: "2026-07-15", dateLabel: "Jul 15", dow: "Wed", label: "Moderate 7 mi", zone: "moderate", miles: 7, actual: "7.0 mi · 8:30/mi", delta: "2s under", onTarget: false, key: false, mood: "positive", niggle: null, note: "Flat but fine, humid out. Just moved through it." },
  { id: "2026-07-16", date: "2026-07-16", dateLabel: "Jul 16", dow: "Thu", label: "Easy 6 mi", zone: "easy", miles: 6, actual: "6.0 mi · 9:07/mi", delta: "on target", onTarget: true, key: false, mood: "energized", niggle: null, note: "" },
];
