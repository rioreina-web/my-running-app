// Coach athlete dashboard — data contract (Phase 1).
//
// These types are the seam between the UI and the database. The components
// under components/coach/dashboard/* render *only* from `DashboardData`; they
// never touch Supabase. `getAthleteDashboard(id)` returns this shape — today
// from fixtures, later from real reads — so swapping the source is one file.
//
// Field shapes intentionally mirror the real/target tables so the swap is a
// mechanical mapping, not a redesign:
//   - DashboardDay        ← training_logs (+ its scheduled_workouts prescription
//                            + body_mentions for the day)
//   - FitnessPrediction   ← athlete_state.fitness_prediction (jsonb)
//   - Progression.trend*  ← athlete_state.fitness_trend / fitness_vs_6mo_ago_label
//   - Acwr                ← athlete_state.acwr / monotony_7d / strain_7d
//   - NiggleGroup         ← body_mentions grouped by body_area (+ recurrence)
//   - CoachableMoment     ← coachable_moments (summary → observation)
//   - WeeklyVolumeWeek    ← training_logs bucketed by week × pace zone
//
// See outputs/coach-athlete-dashboard-spec-2026-07-16.md.

import type { PaceZone } from "@/components/coach/workout-helpers";

// Closed mood vocabulary — stored as a TEXT label, never coerced to a number
// (CLAUDE.md). Mirrors training_logs.mood.
export type Mood =
  | "energized"
  | "positive"
  | "neutral"
  | "tired"
  | "struggling"
  | "injured";

// One prescribed-vs-actual split row inside a key session's drill-down.
export interface WorkoutSplit {
  /** e.g. "Rep 3", "MP mile 4", "First 5 mi". */
  name: string;
  /** Actual pace, e.g. "7:29". `null` = prescribed but not run (a cut rep). */
  pace: string | null;
  /** At or under target (renders blue); false = over (renders gray). */
  onTarget: boolean;
  /** Heat-adjusted pace, e.g. "8:46" (blue text beside the raw pace). Absent
   *  when no lap-level heat adjustment exists for this bucket. */
  adj?: string;
}

// ── Enrichment blocks (spec §4) ──────────────────────────────────────────
// Every block below is OPTIONAL. The drawer renders what it gets, so a thin
// live row (only kpis + splits) and a fully-enriched fixture both stay valid.
// Sources map 1:1 to tables that exist today — no schema change.

// §3 row 1 — the prescription this run was measured against.
export interface WorkoutPrescribed {
  /** Zone label, e.g. "Long", "MP", "LT". */
  label: string;
  /** Prescribed distance in miles (the planned target). */
  distance: number;
  /** Prescribed pace window, e.g. "8:55–9:25". */
  window: string;
  /** Estimated time for the prescription, e.g. "~2:15". */
  timeEst?: string;
  /** Present when the athlete cut/extended the run: signed miles vs. plan. */
  cutAtMi?: number;
}

// §3 row 4 — conditions strip. Dew point past 68°F renders coral (alert).
export interface WorkoutConditions {
  tempF: number;
  dewPointF: number;
  /** True when dew point sits past the 68°F hot threshold (renders coral). */
  dewHot?: boolean;
  climbFt: number;
  hrAvg: number;
  /** Avg HR zone label, e.g. "Z3". */
  hrZone?: string;
  /** Pa:HR decoupling, e.g. "+8.4%". Absent until derived/stored. */
  drift?: string;
  /** Start time, e.g. "9:41 AM". */
  startTime?: string;
  /** Narrated caption; every claim cites a number. */
  caption?: string;
}

// §3 row 3 — one telemetry sample (per-lap or per-quarter-mile).
export interface ChartLap {
  /** Cumulative distance at this sample, in miles. */
  mi: number;
  /** Raw pace, seconds per mile. */
  paceSec: number;
  /** Heat-adjusted pace, seconds per mile (optional). */
  adjPaceSec?: number;
  /** Heart rate, bpm (optional — line hidden when absent). */
  hr?: number;
  /** Elevation at this sample, feet. */
  elevFt: number;
}

// §3 row 3 — the ported CombinedChart's data + coach layers.
export interface WorkoutChart {
  laps: ChartLap[];
  /** Prescribed pace band, seconds per mile (band low = faster edge). */
  bandLow: number;
  bandHigh: number;
  /** Total prescribed distance, so the chart can ghost the unrun tail. */
  plannedMi: number;
  /** Distance the run was cut at, in miles (draws the cut marker). */
  cutAtMi?: number;
  /** Total climb for the elevation caption, e.g. "+1,240 ft". */
  climbLabel?: string;
  /** Narrated caption below the chart; every claim cites a number. */
  caption?: string;
}

// §3 row 8 — the run's place in the week + load after it.
export interface WeekContext {
  /** e.g. "Run 5 of 6 this week". */
  runOfWeek: string;
  milesSoFar: number;
  milesPlanned: number;
  /** ACWR after this run. */
  acwr: number;
  /** ACWR band, e.g. "high" — only "spike" gets coral (three-palette rule). */
  acwrBand: "detraining" | "low" | "sweet" | "high" | "spike";
  /** Narrated load line; every claim cites a number. */
  loadLine: string;
  /** Next key session, e.g. "MP 8 mi · Tue Jul 14". */
  nextKey?: { label: string; zone: PaceZone };
}

// §3 row 7 — body/niggle context. Absence is information, never an empty cell.
export interface BodyContext {
  /** Primary line, e.g. "No niggles mentioned on this run." */
  line: string;
  /** Recency sub-line, e.g. "Left calf last flagged Jul 3 — quiet for 8 days." */
  sub?: string;
}

// §3 row 9 — the AI read. Feeling first, numbers cited, one soft question,
// never a directive (hard rule #2). `body` may carry `**…**` emphasis.
export interface WorkoutRead {
  body: string;
  question: string;
}

// Drill-down detail for a key session — populated for `key` days.
export interface WorkoutDetail {
  /** Headline strip cells. `sub` is the planned-vs-ran line under the value;
   *  `accent` renders the value in the blue pace ramp (the heat-adj cell). */
  kpis: Array<{ k: string; v: string; sub?: string; accent?: boolean }>;
  splitLabel: string;
  splits: WorkoutSplit[];
  /** Enrichment blocks (spec §4) — all optional. */
  prescribed?: WorkoutPrescribed;
  conditions?: WorkoutConditions;
  chart?: WorkoutChart;
  weekContext?: WeekContext;
  bodyContext?: BodyContext;
  read?: WorkoutRead;
  /** Verdict-as-title override, e.g. "Long run, cut at 15." When absent the
   *  drawer falls back to the day's normal label. */
  verdictTitle?: string;
}

// A single day of training — the atomic unit of the overlay and the log.
// Maps to one training_logs row joined to its scheduled_workouts prescription
// and any body_mentions for the day.
export interface DashboardDay {
  /** training_logs.id (or a synthetic date id for rest days). */
  id: string;
  /** ISO date, YYYY-MM-DD (parsed as local for day-of-week). */
  date: string;
  /** Short display date, e.g. "Jul 11". */
  dateLabel: string;
  /** Short weekday, e.g. "Sat". */
  dow: string;
  /** Prescribed label, e.g. "LT 6×1mi", "Long 14 · MP 6", "Rest". */
  label: string;
  /** Headline pace zone (highest-intensity of the day) for coloring; `null` for
   *  a rest day. */
  zone: PaceZone | null;
  /** Per-pace-zone miles for the day — the stacked segments in the overlay,
   *  aggregating every upload on this calendar day. Absent → the overlay falls
   *  back to a single `zone` bar of height `miles` (fixtures). */
  zoneMiles?: Partial<Record<PaceZone, number>>;
  /** Total actual distance in miles (0 for rest). */
  miles: number;
  /** Actual result line, e.g. "5×1mi · 7:29/mi". `null` for rest. */
  actual: string | null;
  /** Prescribed-vs-actual read, e.g. "2s under", "on pace". `null` for rest. */
  delta: string | null;
  /** Whether the delta reads as on/under target (styling only). */
  onTarget: boolean;
  /** Key session — a long, MP, HM, LT, or race worth drilling into. */
  key: boolean;
  mood: Mood;
  /** Latest body mention for the day (verbatim), or null. */
  niggle: { area: string; quote: string } | null;
  /** Voice-note / cleaned_notes text (may be empty). */
  note: string;
  /** False for a calendar day with no logged activity (rendered faint, not a
   *  mood color). Absent/true for logged days and all fixtures. */
  logged?: boolean;
  /** Drill-down detail — present on key days. */
  detail?: WorkoutDetail;
}

// athlete_state.fitness_prediction (jsonb). Range + confidence tier ONLY —
// never a single seconds-precision point (CLAUDE.md hard rule #7).
export interface FitnessPrediction {
  /** Optimistic-to-conservative bracket, e.g. "3:19" … "3:24". */
  low: string;
  high: string;
  confidence: "low" | "moderate" | "high";
  /** Plain-language basis, e.g. "4 marathon-pace workouts and a recent half". */
  basis: string;
}

// A row on the fitness curve's race-anchor markers.
export interface RaceAnchor {
  /** Index into the fitness series (which week the race sits on). */
  weekIndex: number;
  /** Short label, e.g. "3:28 mar", "1:36 half". */
  label: string;
}

export interface Progression {
  /** Range + confidence. Absent when there's no proper range (never a point). */
  prediction?: FitnessPrediction;
  goalTime: string;
  /** e.g. "3–8 min from range". */
  gapLabel: string;
  trendArrow: "up" | "down" | "flat";
  /** Plain-language trend, `**…**` marks emphasis. Every claim cites a number. */
  trendText: string;
  /** Relative fitness (CTL-like) weekly series for the 26-week chart. */
  fitnessSeries: number[];
  fitnessMonths: Array<{ label: string; weekIndex: number }>;
  races: RaceAnchor[];
  /** Projection fan toward the goal race (drawn into the chart's right margin). */
  projection: { rangeLabel: string; goalLabel: string; xLabel: string };
}

export interface WeeklyVolumeWeek {
  /** Week-start label, e.g. "Jul 13". */
  label: string;
  zoneMiles: Partial<Record<PaceZone, number>>;
  targetMiles: number;
  /** Current (in-progress) week — gets the coral outline. */
  current?: boolean;
}

// athlete_state.acwr / monotony_7d / strain_7d. Band drives the gauge read;
// only the spike band is coral (three-palette rule).
export interface Acwr {
  value: number;
  band: "detraining" | "low" | "sweet" | "high" | "spike";
  bandLabel: string;
  monotony7d: number;
  strain7d: number;
}

// coachable_moments — AI observation, kept observational (no directives).
export interface CoachableMoment {
  id: string;
  /** Rule family label, e.g. "Mood pattern", "Niggle cluster". */
  kind: string;
  /** Recency, e.g. "This block", "4 weeks". */
  when: string;
  /** Observation text; `**…**` marks emphasis. */
  observation: string;
  /** Soft question for the coach to sit with (never a directive). */
  softQuestion: string;
  severity: "high" | "med" | "low";
}

export interface WatchItem {
  severity: "warn" | "mid";
  /** Title with optional `**…**` emphasis. */
  title: string;
  detail: string;
}

// body_mentions grouped by body_area. Surface, never interpret (hard rule #2):
// verbatim quotes, counts, recency — no diagnosis or severity scoring by us.
export interface NiggleGroup {
  area: string;
  mentions: number;
  latestDate: string;
  latestQuote: string;
  otherDates: string[];
  /** athlete_state_niggle_recurrence — gets the one coral accent per cluster. */
  recurrence: boolean;
  resolved?: boolean;
  /** DashboardDay.id to open in the drawer, if the mention links to a session. */
  linkDayId?: string;
}

export interface MoodSummary {
  /** Last 28 days, oldest → newest. `logged: false` days render faint. */
  strip: Array<{ date: string; dateLabel: string; mood: Mood; logged?: boolean }>;
  distribution: Array<{ mood: Mood; count: number }>;
  /** Caption with optional `**…**` emphasis. */
  caption: string;
}

export interface AthleteHeader {
  name: string;
  initials: string;
  planName: string;
  /**
   * The athlete's user_id. Present on the live route (enables the profile
   * editor); absent in static fixtures/design preview, where editing is off.
   */
  athleteId?: string;
  /**
   * The raw stored display name (undefined when none is set yet). Distinct
   * from `name`, which falls back to the "Athlete <id>" placeholder for
   * display — `profileName` prefills the editor so the placeholder is never
   * mistaken for a real saved value.
   */
  profileName?: string;
  /** Short free-text profile note. Editable inline on the detail page. */
  bio?: string;
  /** Signed URL of the athlete's profile photo, if set (else show monogram). */
  avatarUrl?: string;
  /** 0 when there is no active plan (the week pill is hidden). */
  weekNumber: number;
  totalWeeks: number;
  // Anchor line — all optional; absent for an athlete with no goal/anchor set.
  goalTime?: string;
  goalNote?: string;
  anchorTime?: string;
  anchorRace?: string;
  marathonPace?: string;
  /** New-race nudge (a newer confirmed race than the current anchor). */
  newRaceNudge?: { text: string };
}

// The full payload one coach dashboard needs. Everything the UI renders.
export interface DashboardData {
  header: AthleteHeader;
  watchList: WatchItem[];
  moments: CoachableMoment[];
  /** 35 daily entries, oldest → newest — source for the overlay and the log. */
  days: DashboardDay[];
  /** The overlay's plain-language "read" (AI narrative). Absent for live data. */
  overlayRead?: { body: string; question: string };
  /** Absent when there's not enough data yet (e.g. no plan / no anchors). */
  progression?: Progression;
  weeklyVolume: WeeklyVolumeWeek[];
  /** Absent when there's no athlete_state row to read acute:chronic from. */
  acwr?: Acwr;
  niggles: NiggleGroup[];
  mood: MoodSummary;
  /** Pace key for the overlay — the athlete's pace per zone, when a calibrated
   *  pace table exists. Absent → the overlay shows a plain color ramp. */
  paceKey?: Array<{ zone: PaceZone; label: string; pace: string }>;
}
