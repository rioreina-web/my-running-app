/* ════════════════════════════════════════════════════════════════════
   Athlete-site mockup · mock data

   One coherent story so every surface agrees with every other one.
   The athlete is Maya, the canonical persona from
   outputs/maya-data-aware-journey-2026-05-28.md:

     · self-coached endurance runner, ~40 mpw baseline
     · 3:28:14 marathon PB (Houston, Jan 18 2026) — the race anchor
     · chasing a 3:16 Boston qualifier at CIM, Dec 6 2026
     · journals by voice after most runs

   "Today" is Thursday, September 3, 2026 — week 5 of an 18-week build.

   Nothing in here is wired to Supabase. When the real screens get built,
   each `Mock*` type below maps onto an existing table (noted inline) so
   the shapes can be swapped for live queries without redesigning.
   ════════════════════════════════════════════════════════════════════ */

export type Mood =
  | "energized"
  | "positive"
  | "neutral"
  | "tired"
  | "struggling"
  | "injured";

/** Pace-zone label taxonomy (CLAUDE.md · "Pace zones"). Workout labels
 *  ARE pace-zone labels; "Tempo" / "Threshold" are deliberately absent. */
export type ZoneLabel =
  | "Easy"
  | "Moderate"
  | "Steady"
  | "MP"
  | "HMP"
  | "LT"
  | "10K"
  | "5K"
  | "3K"
  | "Mile"
  | "Long"
  | "Long wo"
  | "Cross-train"
  | "Strength"
  | "Rest"
  | "Race";

export const ATHLETE = {
  firstName: "Maya",
  email: "maya@postrundrip.com",
  units: "imperial" as const,
  longRunDay: "Sunday",
  /** data_depth 3 — 21+ days of data AND a goal set. Full editorial register. */
  dataDepth: 3,
};

export const TODAY = {
  weekday: "Thursday",
  short: "THU",
  date: "Sep 3",
  dateUpper: "SEP 3",
  long: "September 3, 2026",
  iso: "2026-09-03",
};

/* ── Race anchors (maps to `confirmed_races`) ─────────────────────── */

export type MockRace = {
  id: string;
  name: string;
  distance: "Marathon" | "Half" | "10K" | "5K";
  date: string;
  dateUpper: string;
  time: string;
  pace: string;
  official: boolean;
  anchor?: boolean;
  note: string;
};

export const RACES: MockRace[] = [
  {
    id: "houston-2026",
    name: "Houston Marathon",
    distance: "Marathon",
    date: "Jan 18, 2026",
    dateUpper: "JAN 18 · 2026",
    time: "3:28:14",
    pace: "7:57 / mi",
    official: true,
    anchor: true,
    note: "Even splits until 22, faded 40 seconds over the last four. The PB that anchors everything.",
  },
  {
    id: "brooklyn-half-2026",
    name: "Brooklyn Half",
    distance: "Half",
    date: "May 16, 2026",
    dateUpper: "MAY 16 · 2026",
    time: "1:37:52",
    pace: "7:28 / mi",
    official: true,
    note: "Negative split by 40 seconds. Cool morning, big crowd.",
  },
  {
    id: "firecracker-5k-2026",
    name: "Firecracker 5K",
    distance: "5K",
    date: "Jul 4, 2026",
    dateUpper: "JUL 4 · 2026",
    time: "21:12",
    pace: "6:50 / mi",
    official: false,
    note: "Ran it as a hard effort inside a training week. Not chip-timed.",
  },
  {
    id: "turkey-trot-2025",
    name: "Turkey Trot 10K",
    distance: "10K",
    date: "Nov 27, 2025",
    dateUpper: "NOV 27 · 2025",
    time: "44:38",
    pace: "7:11 / mi",
    official: true,
    note: "Cold, windy, and a good sign six weeks before Houston.",
  },
  {
    id: "chicago-2024",
    name: "Chicago Marathon",
    distance: "Marathon",
    date: "Oct 13, 2024",
    dateUpper: "OCT 13 · 2024",
    time: "3:41:05",
    pace: "8:26 / mi",
    official: true,
    note: "First marathon off a 35 mpw base. Walked the aid stations after 20.",
  },
];

/** A race the HealthKit back-fill detected but Maya hasn't confirmed. */
export const DETECTED_RACE = {
  date: "Aug 15, 2026",
  dateUpper: "AUG 15 · 2026",
  guess: "Looks like a 10K effort",
  time: "43:51",
  pace: "7:04 / mi",
};

/* ── Goal (maps to `goals` + `user_profiles.goal_*`) ──────────────── */

export const GOAL = {
  race: "California International Marathon",
  short: "CIM",
  date: "Dec 6, 2026",
  dateUpper: "DEC 6 · 2026",
  time: "3:16:00",
  mp: "7:29 / mi",
  daysOut: 94,
  why: "A Boston qualifier with a four-minute cushion.",
  planName: "CIM build",
  planWeeks: 18,
  planWeek: 5,
  planTemplate: "Marathon · 18 weeks · up to 55 mi",
};

/* ── Fitness read (maps to `fitness_snapshots`) ───────────────────────
   Always a range + confidence, never a point. Hard rule #7.            */

export const FITNESS = {
  rangeLow: "3:19",
  rangeHigh: "3:25",
  midpoint: "3:22",
  confidence: "MEDIUM" as const,
  direction: "BUILDING",
  basis: "based on 3 marathon-pace sessions and a half in May",
  predictions: [
    { dist: "MILE", name: "Mile", range: "5:58 – 6:10", confidence: "LOW", basis: "no recent short effort" },
    { dist: "5K", name: "5K", range: "20:40 – 21:15", confidence: "MEDIUM", basis: "July 4 effort" },
    { dist: "10K", name: "10K", range: "43:10 – 44:20", confidence: "MEDIUM", basis: "Aug 15 detected effort" },
    { dist: "HALF", name: "Half", range: "1:34 – 1:37", confidence: "HIGH", basis: "Brooklyn Half + MP work" },
    { dist: "FULL", name: "Marathon", range: "3:19 – 3:25", confidence: "MEDIUM", basis: "3 MP sessions + a May half", goal: true },
  ],
};

/* ── 26-week fitness arc · weekly marathon-equivalent, in minutes ────
   Mar 9 → Sep 3. Lower is fitter. Race anchors plotted as markers.     */

export const FITNESS_ARC = [
  212, 211, 211, 210, 209, 208, 207, 206, 205, 204, // Mar–May (post-Houston base, half build)
  203, 203, 204, 205, 206, 206,                     // May–Jun (post-half lull, heat)
  205, 205, 204, 204, 203, 203,                     // Jul–Aug (base again)
  203, 202, 202, 202,                               // Aug–Sep (build weeks 1–5)
];
export const FITNESS_ARC_LABELS = ["MAR", "MAY", "JUL", "SEP"];
export const FITNESS_ARC_MARKERS = [
  { index: 10, label: "BROOKLYN HALF", short: "HALF" },
  { index: 17, label: "5K", short: "5K" },
];
/** Goal line: 3:16 = 196 minutes. Plotted at the bottom of the arc. */
export const FITNESS_ARC_GOAL = 196;

/* ── Volume · last 13 weeks (maps to weekly rollups) ─────────────── */

export const WEEKLY_MILES = [34, 36, 31, 38, 40, 37, 39, 38, 40, 42, 45, 44.6];
export const VOLUME = {
  last7: "44.6",
  fourWeekAvg: "41.2",
  deltaVsAvg: "+8%",
  weeksAbove40: 3,
};
export const ACWR = { value: "1.12", label: "PRODUCTIVE" };

/* ── Pace zones · anchored on Houston (race anchor beats goal) ────────
   Math mirrors web/src/components/coach/workout-helpers.ts
   (derivePaceTableFromGoal). Aerobic zones ship as ranges, race-pace
   zones as exact targets. "At goal" column is the same math off 3:16. */

export type PaceZoneRow = {
  zone: ZoneLabel;
  hint: string;
  anchor: string;
  goal: string;
  kind: "aerobic" | "race";
};

export const PACE_ZONES: PaceZoneRow[] = [
  { zone: "Easy", hint: "Aerobic, conversational", anchor: "9:55 – 11:20", goal: "9:21 – 10:41", kind: "aerobic" },
  { zone: "Moderate", hint: "Upper aerobic", anchor: "8:55 – 9:50", goal: "8:24 – 9:16", kind: "aerobic" },
  { zone: "Steady", hint: "Marathon-prep aerobic", anchor: "8:00 – 8:45", goal: "7:32 – 8:15", kind: "aerobic" },
  { zone: "MP", hint: "Marathon pace", anchor: "7:56", goal: "7:29", kind: "race" },
  { zone: "HMP", hint: "Half marathon pace", anchor: "7:35", goal: "7:08", kind: "race" },
  { zone: "LT", hint: "One-hour race pace", anchor: "7:24", goal: "7:00", kind: "race" },
  { zone: "10K", hint: "10K race pace", anchor: "7:15", goal: "6:50", kind: "race" },
  { zone: "5K", hint: "5K race pace", anchor: "6:59", goal: "6:35", kind: "race" },
  { zone: "3K", hint: "3K race pace", anchor: "6:42", goal: "6:19", kind: "race" },
  { zone: "Mile", hint: "Mile race pace", anchor: "6:17", goal: "5:56", kind: "race" },
];

/* ── This week (maps to `scheduled_workouts` + `training_logs`) ────── */

export type DayState = "done" | "today" | "future" | "rest";

export type MockDay = {
  id: string;
  dow: string;
  date: string;
  dateUpper: string;
  zone: ZoneLabel;
  title: string;
  structure: string;
  plannedMiles: number;
  actualMiles?: number;
  actualPace?: string;
  state: DayState;
  intent: string;
  workoutId?: string;
};

export const THIS_WEEK: MockDay[] = [
  {
    id: "mon", dow: "MON", date: "Aug 31", dateUpper: "AUG 31", zone: "Easy", title: "Easy 6.",
    structure: "6 MI EASY", plannedMiles: 6, actualMiles: 6.1, actualPace: "10:12", state: "done",
    intent: "Conversational the whole way. If it isn't easy, slow down.", workoutId: "w-0831",
  },
  {
    id: "tue", dow: "TUE", date: "Sep 1", dateUpper: "SEP 1", zone: "MP", title: "MP 6.",
    structure: "2 MI WU · 6 MI @ MP · 1 MI CD", plannedMiles: 9, actualMiles: 9.0, actualPace: "8:24", state: "done",
    intent: "Hold splits, don't chase them. Negative is fine, positive is not.", workoutId: "w-0901",
  },
  {
    id: "wed", dow: "WED", date: "Sep 2", dateUpper: "SEP 2", zone: "Easy", title: "Easy 5 + strides.",
    structure: "5 MI EASY · 4 × 20S STRIDES", plannedMiles: 5.5, actualMiles: 5.5, actualPace: "10:20", state: "done",
    intent: "Legs lively, load light. Strides are form work, not speed work.", workoutId: "w-0902",
  },
  {
    id: "thu", dow: "THU", date: "Sep 3", dateUpper: "SEP 3", zone: "LT", title: "LT 4.",
    structure: "2 MI WU · 4 MI @ LT · 1 MI CD", plannedMiles: 7, state: "today",
    intent: "Comfortably hard. The last mile should feel like you could do one more.",
  },
  {
    id: "fri", dow: "FRI", date: "Sep 4", dateUpper: "SEP 4", zone: "Rest", title: "Rest.",
    structure: "REST", plannedMiles: 0, state: "rest",
    intent: "Sleep is the workout.",
  },
  {
    id: "sat", dow: "SAT", date: "Sep 5", dateUpper: "SEP 5", zone: "Easy", title: "Easy 7.",
    structure: "7 MI EASY", plannedMiles: 7, state: "future",
    intent: "Shakeout before the long run. Keep the watch face on the time of day.",
  },
  {
    id: "sun", dow: "SUN", date: "Sep 6", dateUpper: "SEP 6", zone: "Long", title: "Long 16.",
    structure: "16 MI · EASY TO MODERATE", plannedMiles: 16, state: "future",
    intent: "Start slower than feels necessary. Practice the fueling you'll race with.",
  },
];

export const WEEK_TOTALS = {
  planned: 50.5,
  done: 20.6,
  runsDone: 3,
  runsPlanned: 6,
  label: "WEEK 05 OF 18",
  range: "AUG 31 – SEP 6",
};

/* ── Calendar · Aug 31 → Oct 4 (five weeks) ──────────────────────── */

export type CalCell = {
  day: number;
  month: "AUG" | "SEP" | "OCT";
  zone?: ZoneLabel;
  miles?: string;
  state: DayState | "past-empty";
  workoutId?: string;
};

const cal = (day: number, month: CalCell["month"], zone: ZoneLabel | undefined, miles: string | undefined, state: CalCell["state"], workoutId?: string): CalCell => ({ day, month, zone, miles, state, workoutId });

export const CALENDAR: CalCell[][] = [
  [
    cal(31, "AUG", "Easy", "6.1", "done", "w-0831"),
    cal(1, "SEP", "MP", "9.0", "done", "w-0901"),
    cal(2, "SEP", "Easy", "5.5", "done", "w-0902"),
    cal(3, "SEP", "LT", "7", "today"),
    cal(4, "SEP", "Rest", undefined, "rest"),
    cal(5, "SEP", "Easy", "7", "future"),
    cal(6, "SEP", "Long", "16", "future"),
  ],
  [
    cal(7, "SEP", "Easy", "6", "future"),
    cal(8, "SEP", "MP", "10", "future"),
    cal(9, "SEP", "Easy", "6", "future"),
    cal(10, "SEP", "5K", "7", "future"),
    cal(11, "SEP", "Rest", undefined, "rest"),
    cal(12, "SEP", "Easy", "7", "future"),
    cal(13, "SEP", "Long wo", "17", "future"),
  ],
  [
    cal(14, "SEP", "Easy", "6", "future"),
    cal(15, "SEP", "HMP", "10", "future"),
    cal(16, "SEP", "Easy", "6", "future"),
    cal(17, "SEP", "LT", "8", "future"),
    cal(18, "SEP", "Rest", undefined, "rest"),
    cal(19, "SEP", "Easy", "7", "future"),
    cal(20, "SEP", "Long", "18", "future"),
  ],
  [
    cal(21, "SEP", "Easy", "5", "future"),
    cal(22, "SEP", "Easy", "7", "future"),
    cal(23, "SEP", "Easy", "5", "future"),
    cal(24, "SEP", "Steady", "7", "future"),
    cal(25, "SEP", "Rest", undefined, "rest"),
    cal(26, "SEP", "Easy", "6", "future"),
    cal(27, "SEP", "Long", "13", "future"),
  ],
  [
    cal(28, "SEP", "Easy", "6", "future"),
    cal(29, "SEP", "MP", "11", "future"),
    cal(30, "SEP", "Easy", "6", "future"),
    cal(1, "OCT", "LT", "8", "future"),
    cal(2, "OCT", "Rest", undefined, "rest"),
    cal(3, "OCT", "Easy", "7", "future"),
    cal(4, "OCT", "Long wo", "18", "future"),
  ],
];

export const CALENDAR_WEEK_NOTES = [
  { wk: "WK 05", miles: "50.5", phase: "BUILD" },
  { wk: "WK 06", miles: "53", phase: "BUILD" },
  { wk: "WK 07", miles: "55", phase: "BUILD" },
  { wk: "WK 08", miles: "43", phase: "RECOVERY" },
  { wk: "WK 09", miles: "56", phase: "SPECIFIC" },
];

/* ── Journal (maps to `training_logs` + `voice_logs` + `body_mentions`) */

export type Niggle = { part: string; side?: "L" | "R"; quote: string };

export type MockEntry = {
  id: string;
  dow: string;
  date: string;
  dateUpper: string;
  zone: ZoneLabel;
  miles?: string;
  pace?: string;
  duration?: string;
  source: "Apple Watch" | "Manual" | "HealthKit";
  kind: "voice" | "text" | "none";
  voiceLength?: string;
  mood?: Mood;
  body?: string;
  niggles?: Niggle[];
  life?: string[];
  workoutId?: string;
};

export const JOURNAL: MockEntry[] = [
  {
    id: "j-0902", dow: "Wednesday", date: "Sep 2", dateUpper: "SEP 2", zone: "Easy", miles: "5.5", pace: "10:20 / mi", duration: "56:50",
    source: "Apple Watch", kind: "voice", voiceLength: "1:12", mood: "tired",
    body: "Four hours of sleep, deadline at work. Legs felt like wood the first two miles and the strides woke them up a little. Nothing hurt. Just flat.",
    life: ["SLEEP · 4H", "WORK · DEADLINE"], workoutId: "w-0902",
  },
  {
    id: "j-0901", dow: "Tuesday", date: "Sep 1", dateUpper: "SEP 1", zone: "MP", miles: "9.0", pace: "8:24 / mi", duration: "1:15:40",
    source: "Apple Watch", kind: "voice", voiceLength: "2:41", mood: "energized",
    body: "Six at marathon pace and they came easy. Seven thirty-eights without forcing it, which four weeks ago took real work. Hamstring on the right was a touch tight on the cool-down, same as last Tuesday. Not sore now, just aware of it.",
    niggles: [{ part: "Hamstring", side: "R", quote: "a touch tight on the cool-down, same as last Tuesday" }],
    life: ["WEATHER · 68°F"], workoutId: "w-0901",
  },
  {
    id: "j-0831", dow: "Monday", date: "Aug 31", dateUpper: "AUG 31", zone: "Easy", miles: "6.1", pace: "10:12 / mi", duration: "1:02:14",
    source: "Apple Watch", kind: "text", mood: "positive",
    body: "Easy and actually easy. Kept it above ten minutes on purpose. Good podcast, no watch checking.",
    workoutId: "w-0831",
  },
  {
    id: "j-0830", dow: "Sunday", date: "Aug 30", dateUpper: "AUG 30", zone: "Long", miles: "15.0", pace: "9:48 / mi", duration: "2:27:00",
    source: "Apple Watch", kind: "voice", voiceLength: "3:05", mood: "positive",
    body: "Hot. Eighty-four and humid by the end. Held nine-fifties and the last two picked up on their own. Took two gels and a bottle at the car. Tired in the good way.",
    life: ["WEATHER · 84°F · HUMID"], workoutId: "w-0830",
  },
  {
    id: "j-0829", dow: "Saturday", date: "Aug 29", dateUpper: "AUG 29", zone: "Strength", duration: "40 min",
    source: "HealthKit", kind: "none",
  },
  {
    id: "j-0827", dow: "Thursday", date: "Aug 27", dateUpper: "AUG 27", zone: "LT", miles: "7.0", pace: "8:31 / mi", duration: "59:37",
    source: "Apple Watch", kind: "voice", voiceLength: "1:58", mood: "positive",
    body: "Four at threshold, seven twenty-six average. Breathing was the limiter, not the legs. Right hamstring grumbled in the first warm-up mile and then went quiet.",
    niggles: [{ part: "Hamstring", side: "R", quote: "grumbled in the first warm-up mile and then went quiet" }],
    workoutId: "w-0827",
  },
  {
    id: "j-0826", dow: "Wednesday", date: "Aug 26", dateUpper: "AUG 26", zone: "Cross-train", duration: "45 min",
    source: "HealthKit", kind: "text", mood: "neutral",
    body: "Spin bike, easy. Rain.",
  },
  {
    id: "j-0825", dow: "Tuesday", date: "Aug 25", dateUpper: "AUG 25", zone: "MP", miles: "8.0", pace: "8:36 / mi", duration: "1:08:48",
    source: "Apple Watch", kind: "voice", voiceLength: "2:10", mood: "neutral",
    body: "Five at marathon pace, seven forty-twos. Had to dig for the last one. Coffee late yesterday, slept badly. Right hamstring tight again after, stretched it out in the kitchen.",
    niggles: [{ part: "Hamstring", side: "R", quote: "tight again after, stretched it out in the kitchen" }],
    life: ["SLEEP · POOR"],
  },
  {
    id: "j-0823", dow: "Sunday", date: "Aug 23", dateUpper: "AUG 23", zone: "Long", miles: "14.0", pace: "9:55 / mi", duration: "2:18:50",
    source: "Apple Watch", kind: "voice", voiceLength: "2:30", mood: "positive",
    body: "Fourteen with the Sunday group. Talked the whole way, which is the point. Felt strong at the end.",
  },
  {
    id: "j-0818", dow: "Tuesday", date: "Aug 18", dateUpper: "AUG 18", zone: "MP", miles: "8.0", pace: "8:40 / mi", duration: "1:09:20",
    source: "Apple Watch", kind: "voice", voiceLength: "1:40", mood: "positive",
    body: "First marathon-pace session of the build. Seven forty-fours, a little ragged. Right hamstring felt tight on the cool-down, first time I've noticed it.",
    niggles: [{ part: "Hamstring", side: "R", quote: "felt tight on the cool-down, first time I've noticed it" }],
  },
];

export const JOURNAL_TOTAL_ENTRIES = 168;
export const JOURNAL_WINDOW = "LAST 6 MONTHS";

/* ── Niggles (maps to `body_mentions`) ─────────────────────────────── */

export type MockNiggle = {
  id: string;
  part: string;
  side: string;
  status: "ACTIVE" | "QUIET";
  days: number;
  mentions: number;
  firstLine: string;
  lastQuote: string;
  lastDate: string;
  dots14: boolean[];
  timeline: { date: string; after: string; quote: string }[];
};

export const NIGGLES: MockNiggle[] = [
  {
    id: "r-hamstring",
    part: "Hamstring",
    side: "RIGHT",
    status: "ACTIVE",
    days: 16,
    mentions: 4,
    firstLine: "First mentioned Aug 18, after MP 5",
    lastQuote: "a touch tight on the cool-down, same as last Tuesday",
    lastDate: "SEP 1",
    // Aug 21 → Sep 3
    dots14: [false, false, false, false, true, false, true, false, false, false, false, true, false, false],
    timeline: [
      { date: "SEP 1", after: "MP 6 · 9.0 mi", quote: "a touch tight on the cool-down, same as last Tuesday" },
      { date: "AUG 27", after: "LT 4 · 7.0 mi", quote: "grumbled in the first warm-up mile and then went quiet" },
      { date: "AUG 25", after: "MP 5 · 8.0 mi", quote: "tight again after, stretched it out in the kitchen" },
      { date: "AUG 18", after: "MP 5 · 8.0 mi", quote: "felt tight on the cool-down, first time I've noticed it" },
    ],
  },
  {
    id: "l-calf",
    part: "Calf",
    side: "LEFT",
    status: "QUIET",
    days: 41,
    mentions: 1,
    firstLine: "Mentioned once, Jul 24, after Easy 6",
    lastQuote: "calf was cranky on the hill, fine after",
    lastDate: "JUL 24",
    dots14: [false, false, false, false, false, false, false, false, false, false, false, false, false, false],
    timeline: [
      { date: "JUL 24", after: "Easy 6 · 6.0 mi", quote: "calf was cranky on the hill, fine after" },
    ],
  },
];

/* ── Workout detail (maps to `training_logs` + HealthKit samples) ──── */

export type MockWorkout = {
  id: string;
  dow: string;
  date: string;
  dateUpper: string;
  zone: ZoneLabel;
  title: string;
  miles: string;
  duration: string;
  avgPace: string;
  gap: string;
  elev: string;
  load: string;
  loadDelta: string;
  cadence: string;
  drift: string;
  hrAvg: string;
  hrZone: string;
  weekIndex: string;
  weekMiles: string;
  splits: { mi: string; pace: string; hr: number; sec: number; key?: boolean }[];
  paceSeries: number[];
  hrSeries: number[];
  elevSeries: number[];
  entryId?: string;
};

export const WORKOUTS: Record<string, MockWorkout> = {
  "w-0901": {
    id: "w-0901",
    dow: "TUESDAY",
    date: "Sep 1",
    dateUpper: "SEP 1",
    zone: "MP",
    title: "MP 6.",
    miles: "9.0",
    duration: "1:15:40",
    avgPace: "8:24",
    gap: "8:19",
    elev: "+212 ft",
    load: "146",
    loadDelta: "+14 vs typ",
    cadence: "174",
    drift: "+2.4%",
    hrAvg: "156",
    hrZone: "Z3",
    weekIndex: "2 / 6",
    weekMiles: "15.1",
    splits: [
      { mi: "1", pace: "9:58", hr: 128, sec: 598 },
      { mi: "2", pace: "9:41", hr: 136, sec: 581 },
      { mi: "3", pace: "7:41", hr: 154, sec: 461, key: true },
      { mi: "4", pace: "7:39", hr: 158, sec: 459, key: true },
      { mi: "5", pace: "7:38", hr: 160, sec: 458, key: true },
      { mi: "6", pace: "7:37", hr: 162, sec: 457, key: true },
      { mi: "7", pace: "7:36", hr: 164, sec: 456, key: true },
      { mi: "8", pace: "7:37", hr: 166, sec: 457, key: true },
      { mi: "9", pace: "10:14", hr: 142, sec: 614 },
    ],
    paceSeries: [598, 590, 581, 470, 461, 459, 458, 458, 457, 456, 456, 457, 600, 614],
    hrSeries: [124, 130, 136, 150, 154, 158, 160, 161, 162, 164, 165, 166, 150, 142],
    elevSeries: [10, 14, 22, 30, 28, 26, 40, 48, 44, 36, 30, 24, 18, 12],
    entryId: "j-0901",
  },
  "w-0902": {
    id: "w-0902",
    dow: "WEDNESDAY",
    date: "Sep 2",
    dateUpper: "SEP 2",
    zone: "Easy",
    title: "Easy 5 + strides.",
    miles: "5.5",
    duration: "56:50",
    avgPace: "10:20",
    gap: "10:16",
    elev: "+96 ft",
    load: "52",
    loadDelta: "typical",
    cadence: "168",
    drift: "+1.1%",
    hrAvg: "134",
    hrZone: "Z1",
    weekIndex: "3 / 6",
    weekMiles: "20.6",
    splits: [
      { mi: "1", pace: "10:31", hr: 126, sec: 631 },
      { mi: "2", pace: "10:24", hr: 131, sec: 624 },
      { mi: "3", pace: "10:18", hr: 134, sec: 618 },
      { mi: "4", pace: "10:20", hr: 135, sec: 620 },
      { mi: "5", pace: "10:12", hr: 138, sec: 612 },
      { mi: "0.5", pace: "9:04", hr: 146, sec: 544, key: true },
    ],
    paceSeries: [631, 628, 624, 620, 618, 619, 620, 616, 612, 560, 544],
    hrSeries: [124, 128, 131, 133, 134, 134, 135, 136, 138, 144, 146],
    elevSeries: [8, 10, 14, 18, 16, 14, 12, 10, 12, 10, 8],
    entryId: "j-0902",
  },
  "w-0831": {
    id: "w-0831",
    dow: "MONDAY",
    date: "Aug 31",
    dateUpper: "AUG 31",
    zone: "Easy",
    title: "Easy 6.",
    miles: "6.1",
    duration: "1:02:14",
    avgPace: "10:12",
    gap: "10:08",
    elev: "+118 ft",
    load: "58",
    loadDelta: "typical",
    cadence: "167",
    drift: "+0.8%",
    hrAvg: "132",
    hrZone: "Z1",
    weekIndex: "1 / 6",
    weekMiles: "6.1",
    splits: [
      { mi: "1", pace: "10:22", hr: 125, sec: 622 },
      { mi: "2", pace: "10:15", hr: 130, sec: 615 },
      { mi: "3", pace: "10:10", hr: 132, sec: 610 },
      { mi: "4", pace: "10:12", hr: 133, sec: 612 },
      { mi: "5", pace: "10:08", hr: 134, sec: 608 },
      { mi: "6", pace: "10:05", hr: 136, sec: 605 },
    ],
    paceSeries: [622, 618, 615, 612, 610, 611, 612, 610, 608, 606, 605],
    hrSeries: [122, 126, 130, 131, 132, 133, 133, 134, 134, 135, 136],
    elevSeries: [6, 10, 16, 20, 18, 14, 12, 14, 12, 10, 8],
    entryId: "j-0831",
  },
  "w-0830": {
    id: "w-0830",
    dow: "SUNDAY",
    date: "Aug 30",
    dateUpper: "AUG 30",
    zone: "Long",
    title: "Long 15.",
    miles: "15.0",
    duration: "2:27:00",
    avgPace: "9:48",
    gap: "9:41",
    elev: "+402 ft",
    load: "182",
    loadDelta: "+38 vs typ",
    cadence: "170",
    drift: "+4.6%",
    hrAvg: "146",
    hrZone: "Z2",
    weekIndex: "6 / 6",
    weekMiles: "45.0",
    splits: [
      { mi: "1–5", pace: "9:58", hr: 136, sec: 598 },
      { mi: "6–10", pace: "9:50", hr: 145, sec: 590 },
      { mi: "11–13", pace: "9:46", hr: 152, sec: 586 },
      { mi: "14–15", pace: "9:22", hr: 158, sec: 562, key: true },
    ],
    paceSeries: [600, 598, 596, 594, 590, 590, 588, 586, 586, 584, 570, 562],
    hrSeries: [130, 135, 138, 141, 144, 146, 148, 150, 152, 154, 156, 158],
    elevSeries: [10, 20, 40, 60, 55, 50, 70, 80, 75, 60, 40, 20],
    entryId: "j-0830",
  },
  "w-0827": {
    id: "w-0827",
    dow: "THURSDAY",
    date: "Aug 27",
    dateUpper: "AUG 27",
    zone: "LT",
    title: "LT 4.",
    miles: "7.0",
    duration: "59:37",
    avgPace: "8:31",
    gap: "8:27",
    elev: "+140 ft",
    load: "121",
    loadDelta: "+9 vs typ",
    cadence: "176",
    drift: "+2.9%",
    hrAvg: "158",
    hrZone: "Z3",
    weekIndex: "4 / 6",
    weekMiles: "33.0",
    splits: [
      { mi: "1", pace: "10:02", hr: 128, sec: 602 },
      { mi: "2", pace: "9:44", hr: 138, sec: 584 },
      { mi: "3", pace: "7:29", hr: 162, sec: 449, key: true },
      { mi: "4", pace: "7:27", hr: 166, sec: 447, key: true },
      { mi: "5", pace: "7:25", hr: 169, sec: 445, key: true },
      { mi: "6", pace: "7:23", hr: 171, sec: 443, key: true },
      { mi: "7", pace: "10:18", hr: 146, sec: 618 },
    ],
    paceSeries: [602, 592, 584, 452, 449, 447, 446, 445, 444, 443, 600, 618],
    hrSeries: [126, 132, 138, 158, 162, 165, 166, 168, 169, 171, 152, 146],
    elevSeries: [8, 12, 18, 22, 20, 18, 24, 26, 22, 18, 14, 10],
    entryId: "j-0827",
  },
};

/* ── Day detail · today's prescription (Plate 22) ─────────────────── */

export const DAY_DETAILS: Record<string, {
  eyebrow: string;
  title: string;
  subtitle: string;
  stats: { l: string; v: string; u: string; s: string }[];
  shape: { kind: "wu" | "main" | "cd" | "rest"; flex: number; h: number; label?: string }[];
  steps: { n: string; name: string; hint: string; pace: string; hr: string; rpe: string; dist: string; dur: string; key?: boolean }[];
  note: string;
}> = {
  thu: {
    eyebrow: "THURSDAY · PLAN · WK 05 · TODAY",
    title: "LT 4.",
    subtitle: "Sep 3 · second threshold session of the build.",
    stats: [
      { l: "DISTANCE", v: "7", u: "mi", s: "LT" },
      { l: "DURATION", v: "58", u: "min", s: "EST." },
      { l: "TARGET", v: "7:24", u: "/mi", s: "LT · ANCHORED" },
      { l: "LOAD", v: "118", u: "", s: "+8 VS TYP" },
    ],
    shape: [
      { kind: "wu", flex: 2, h: 30, label: "WARM-UP" },
      { kind: "main", flex: 4, h: 85, label: "LT · 4 MI" },
      { kind: "cd", flex: 1, h: 22, label: "CD" },
    ],
    steps: [
      { n: "01", name: "Warm-up", hint: "Easy aerobic. Let the hamstring tell you it is ready before you lean in.", pace: "10:20 / mi", hr: "Z1 · 125–140", rpe: "3", dist: "2.0 mi", dur: "21 min" },
      { n: "02", name: "LT block", hint: "Comfortably hard and even. The last mile should feel like one more was possible.", pace: "7:24 / mi", hr: "Z3–4 · 160–170", rpe: "7", dist: "4.0 mi", dur: "30 min", key: true },
      { n: "03", name: "Cool-down", hint: "Float home. Slower than feels necessary.", pace: "10:30 / mi", hr: "Z1", rpe: "2", dist: "1.0 mi", dur: "11 min" },
    ],
    note: "From the plan template: threshold work is about rhythm, not heroics. Even splits beat a fast first mile every time.",
  },
  sun: {
    eyebrow: "SUNDAY · PLAN · WK 05 · KEY",
    title: "Long 16.",
    subtitle: "Sep 6 · the workout of the week. Fuel like race day.",
    stats: [
      { l: "DISTANCE", v: "16", u: "mi", s: "LONG" },
      { l: "DURATION", v: "2:36", u: "", s: "EST." },
      { l: "TARGET", v: "9:30", u: "/mi", s: "EASY → MOD" },
      { l: "LOAD", v: "188", u: "", s: "+40 VS TYP" },
    ],
    shape: [
      { kind: "wu", flex: 10, h: 38, label: "EASY · 10 MI" },
      { kind: "main", flex: 6, h: 55, label: "MODERATE · 6 MI" },
    ],
    steps: [
      { n: "01", name: "Easy 10", hint: "Start slower than feels necessary. Gel at 45 and 90 minutes.", pace: "9:55 – 10:20 / mi", hr: "Z1–2", rpe: "3", dist: "10.0 mi", dur: "1:42" },
      { n: "02", name: "Moderate 6", hint: "Let the pace come down on its own. Nothing forced.", pace: "9:00 – 9:20 / mi", hr: "Z2", rpe: "5", dist: "6.0 mi", dur: "55 min", key: true },
    ],
    note: "From the plan template: long runs earn the marathon. Finish wanting one more mile, not needing the couch.",
  },
};

/* ── Coach · The Read (maps to `coaching_daily_reads`) ─────────────── */

export const COACH_READ = {
  eyebrow: "THURSDAY · SEP 3 · THE READ",
  headline: "The work is real.",
  paragraph:
    "Wood-legged Wednesday after four hours of sleep, and yet Tuesday's marathon-pace miles came in at 7:38 without forcing it, a few seconds quicker than the same session four weeks back. Three weeks above 40 now, which is settling into rhythm rather than straining for it. The right hamstring has shown up on three Tuesdays in a row, always on the cool-down and always gone by morning. Worth watching.",
  questions: [
    "How did the legs feel this morning after a full night?",
    "Is Tuesday's cool-down the place to add a few easier minutes?",
  ],
  sources: "READ FROM 14 DAYS · 9 RUNS · 7 MEMOS",
};

export const COACH_LENSES = [
  "How does fitness compare to the Houston build?",
  "Read this week through the recovery lens.",
  "Anything with the hamstring I should notice?",
  "How is the volume settling?",
];

export const COACH_LENS_ANSWERS: Record<string, { headline: string; paragraph: string; questions: string[] }> = {
  "How does fitness compare to the Houston build?": {
    headline: "Ahead of where you were.",
    paragraph:
      "Five weeks into this build, marathon-pace miles are coming in around 7:38 at a lower heart rate than the same point before Houston, when they sat closer to 7:52. Volume is tracking a few miles a week higher and the long runs are landing on Sundays without the Monday hangover you were logging last winter. The half in May is doing quiet work underneath all of it.",
    questions: ["What felt different about the Houston build at week five?"],
  },
  "Read this week through the recovery lens.": {
    headline: "One rough night, not a pattern.",
    paragraph:
      "Wednesday's memo reads flat, and the sleep note explains most of it. Monday and Tuesday both read fresh, Sunday's long run ended strong, and the resting heart rate stayed where it has been. One poor night inside a good week is a poor night.",
    questions: ["Would a later start on Thursday buy back some of the sleep?"],
  },
  "Anything with the hamstring I should notice?": {
    headline: "Tuesdays, cool-downs, quiet by morning.",
    paragraph:
      "Four mentions over sixteen days, three of them after marathon-pace sessions and always in the cool-down. Each one reads as tightness rather than pain in your own words, and none has carried into the next day's run. The pattern is specific enough to be worth noticing.",
    questions: ["Does it show up on the days you stretch before the cool-down, or only on the days you don't?"],
  },
  "How is the volume settling?": {
    headline: "Settling into rhythm.",
    paragraph:
      "Three weeks above 40 now, with the acute-to-chronic ratio sitting in the productive band. Easy days are staying easy, which is what lets the weekly total climb without the memos turning tired. The recovery week in week eight is where the last four weeks get absorbed.",
    questions: ["Which day of the week feels heaviest right now?"],
  },
};

export const PAST_READS = [
  { date: "AUG 27", headline: "Three weeks above 40." },
  { date: "AUG 20", headline: "The first marathon-pace miles." },
  { date: "AUG 13", headline: "Heat is a training partner." },
];

/* ── Profile (derived, nightly) ───────────────────────────────────── */

export const PROFILE = {
  weeklyAvg: "41.2",
  weeklyDelta: "+11% vs Houston build",
  longest: "16.0",
  longestWhen: "AUG 16 · 2:38:40",
  easyAvg: "10:14",
  easyHr: "Z1 · 133 BPM",
  mpAvg: "7:38",
  mpDelta: "−6s vs 4w ago",
  sleep: "6H 48M",
  rhr: "52 BPM",
  surface: "ROAD · 91%",
};

/* ── Settings ─────────────────────────────────────────────────────── */

export const SETTINGS_SECTIONS = [
  {
    title: "Account",
    rows: [
      { l: "Email", v: "maya@postrundrip.com", hint: "Used for sign-in and the weekly digest." },
      { l: "Connected services", v: "APPLE HEALTH", hint: "Where your runs, sleep, and strength sessions come from." },
      { l: "HealthKit back-fill", v: "2 YEARS · SYNCED", hint: "Imported on sign-up. Races detected from it need your confirmation." },
    ],
  },
  {
    title: "Coach",
    rows: [
      { l: "The Read", v: "ON DEMAND", hint: "Coach only reads when you ask. Nothing arrives uninvited.", coral: true },
      { l: "Pattern observations", v: "ON", hint: "Mood arcs, niggle clusters, fitness trends surfaced in the Read.", coral: true },
      { l: "Coach connection", v: "NONE", hint: "Self-coached. Join a coach's plan from Train when you have one." },
    ],
  },
  {
    title: "Training",
    rows: [
      { l: "Pace zones", v: "ANCHORED · HOUSTON", hint: "Derived from your 3:28:14. Goal time is direction, not the anchor.", coral: true },
      { l: "Units", v: "IMPERIAL", hint: "Miles and minutes per mile." },
      { l: "Long-run day", v: "SUNDAY", hint: "Where the week anchors its volume." },
      { l: "Maximum heart rate", v: "186 BPM", hint: "Used for heart-rate zones." },
    ],
  },
  {
    title: "Data",
    rows: [
      { l: "Backup", v: "EXPORT JSON ↗", hint: "Everything in one file. Yours to keep." },
      { l: "Export logs", v: "EXPORT CSV ↗", hint: "For Excel, Numbers, R, Python." },
      { l: "Privacy", v: "READ ↗", hint: "What is collected. What is not." },
    ],
  },
];

/* ── Site map · every athlete surface in this mockup ─────────────── */

export const SITE_MAP = [
  {
    group: "Entry",
    items: [
      { href: "/mockup/sign-in", label: "Sign in", hint: "Email + Apple. The quiet front door." },
      { href: "/mockup/onboarding", label: "Onboarding", hint: "Four steps. Connect data, confirm races, set a goal." },
    ],
  },
  {
    group: "The four tabs",
    items: [
      { href: "/mockup/log", label: "Log", hint: "Voice-first capture on top, six months of journal below." },
      { href: "/mockup/trends", label: "Trends", hint: "The 5-second view. Fitness range, volume, niggles, the arc." },
      { href: "/mockup/train", label: "Train", hint: "Current, calendar, history. Works with or without a plan." },
      { href: "/mockup/coach", label: "Coach", hint: "The Read, on demand. Observation, never prescription." },
    ],
  },
  {
    group: "Detail surfaces",
    items: [
      { href: "/mockup/workouts/w-0901", label: "Workout detail", hint: "Pace, narrated by the data. Splits, telemetry, the memo." },
      { href: "/mockup/log/j-0901", label: "Journal entry", hint: "The full memo, the mood, the niggle, the life context." },
      { href: "/mockup/train/day/thu", label: "Day detail", hint: "Today's prescription, step by step." },
    ],
  },
  {
    group: "Index",
    items: [
      { href: "/mockup/niggles", label: "Niggles", hint: "Body-part mentions, in your own words. Detection, not diagnosis." },
      { href: "/mockup/goals", label: "Goals", hint: "What you are chasing, and what you already caught." },
      { href: "/mockup/races", label: "Races", hint: "Race history, the anchor, and the one still to run." },
      { href: "/mockup/pace-chart", label: "Pace chart", hint: "Ten zones, anchored on a real race." },
      { href: "/mockup/profile", label: "Profile", hint: "The athlete, derived nightly from the data." },
      { href: "/mockup/settings", label: "Settings", hint: "Every knob, nothing hidden." },
    ],
  },
];
