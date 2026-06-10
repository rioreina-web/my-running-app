/**
 * Shared types for the V1 coachable_moment rule evaluators.
 *
 * Spec: docs/specs/coachable_moment.md
 *
 * Each rule is a pure function: (RuleContext) => CoachableMomentInsert | null.
 * The main edge function fetches data once, builds the context, and runs every
 * rule against it. Pure rules are trivial to unit-test.
 */

import type { TrainingLogRow } from "../weeklyAnalytics.ts";

// ─── Mood vocabulary ──────────────────────────────────────────────────────────
// Matches the labels written by process-training-memo / process-check-in.
// Anything in LOW_MOOD_LABELS counts as a "low mood" log for rule 2.
export const ALL_MOOD_LABELS = [
  "energized",
  "positive",
  "neutral",
  "tired",
  "struggling",
  "injured",
] as const;

export const LOW_MOOD_LABELS: ReadonlySet<string> = new Set([
  "tired",
  "struggling",
  "injured",
]);

// ─── Injury keyword scan ──────────────────────────────────────────────────────
// Matched case-insensitively against notes, cleaned_notes, workout_notes.
// Tuned for false-positive tolerance: V1 firing more often is fine because
// coaches can dismiss; missing real injury mentions is much worse.
export const INJURY_KEYWORDS: readonly string[] = [
  "hurt",
  "pain",
  "sore",
  "tight",
  "stiff",
  "injured",
  "ache",
  "achy",
  "tweak",
  "tweaked",
  "niggle",
  "twinge",
  "strain",
  "strained",
  "pulled",
  "swelling",
  "swollen",
  "limping",
];

// ─── Quality workout type vocabulary ──────────────────────────────────────────
// Used by weather_impacted_quality to decide whether a workout's pace targets
// "matter" (i.e., heat penalty is meaningful). Easy/recovery runs are excluded
// because pace cost on those runs isn't a coaching signal.
export const QUALITY_WORKOUT_TOKENS: readonly string[] = [
  "tempo",
  "threshold",
  "interval",
  "intervals",
  "repeat",
  "repeats",
  "long_run",
  "long",
  "marathon_pace",
  "mp",
  "race",
  "time_trial",
  "tt",
  "progression",
];

// ─── Scheduled workout row (subset we consume) ────────────────────────────────
export interface ScheduledWorkoutRow {
  id: string;
  date: string; // ISO date (YYYY-MM-DD)
  status: "scheduled" | "completed" | "skipped" | "modified";
  workout_type: string;
}

// ─── Weather-aware training log augmentation ──────────────────────────────────
// Optional fields read from training_logs.weather_actual (JSONB) and
// training_logs.weather_adjusted_pace_delta_seconds_per_mile.
//
// Most rules can ignore these. The weather_impacted_quality rule reads them.
export interface WeatherActual {
  temp_f?: number | null;
  dewpoint_f?: number | null;
  humidity_pct?: number | null;
  heat_index_f?: number | null;
  composite?: number | null;
  conditions?: string | null;
  [key: string]: unknown;
}

export interface WeatherAwareTrainingLogRow extends TrainingLogRow {
  /** Raw weather payload at workout time, or null if unavailable. */
  weather_actual?: WeatherActual | Record<string, unknown> | null;
  /**
   * Heat-adjusted pace delta in seconds per mile. Positive = the heat slowed
   * the athlete by N s/mi vs cool-condition expectation. Null if not computed.
   */
  weather_adjusted_pace_delta_seconds_per_mile?: number | null;
}

// ─── Confirmed race / goal context (Phase 2 race anchoring) ───────────────────
// Shape matches athlete_state.confirmed_races entries (see _shared/paces.ts
// ConfirmedRace — duplicated structurally here so rule types stay dependency-
// light; the two are assignable in both directions).
export interface ConfirmedRaceSummary {
  date: string; // ISO date
  distance: string;
  finish_time_seconds: number;
  official?: boolean;
  event_name?: string | null;
}

export interface GoalRaceInfo {
  /** ISO date of the goal race (training_plans.end_date or user_goals.target_date). */
  date: string;
  /** Race distance key when known (training_plans.target_race_distance); null for user_goals. */
  distance: string | null;
}

// ─── Rule context ─────────────────────────────────────────────────────────────
export interface RuleContext {
  athleteUserId: string;
  coachId: string;
  /** Reference "now" — pure function tests can pass a fixed date. */
  now: Date;
  /**
   * All training_logs for the athlete in the last 28 days, ordered newest-first.
   * Includes optional weather fields; rules that don't need them can ignore.
   */
  logs: WeatherAwareTrainingLogRow[];
  /** Scheduled workouts for the athlete from current week (Mon-Sun). */
  scheduledThisWeek: ScheduledWorkoutRow[];

  // ── Optional race-anchoring context (Phase 2 sub-task F). Rules that
  // don't need these ignore them; the evaluator populates them when the
  // athlete has confirmed races / an upcoming goal. ──────────────────────
  /** User-declared races from athlete_state.confirmed_races, newest-first. */
  confirmedRaces?: ConfirmedRaceSummary[] | null;
  /** The athlete's next goal race, when one is stated. */
  goalRace?: GoalRaceInfo | null;
  /**
   * training_logs from the build window before the anchor race
   * (race-day −63d to −21d — the build, excluding the taper).
   * Only populated when an anchor race exists.
   */
  priorCycleLogs?: WeatherAwareTrainingLogRow[] | null;
}

// ─── Coachable moment insert payload ──────────────────────────────────────────
export type Severity = "low" | "med" | "high";
export type ActionType =
  | "send_check_in"
  | "suggest_deload"
  | "recommend_evaluation"
  | "monitor"
  | "suggest_extra_recovery"
  // Pure pattern observation — no operational ask. Surfaces the athlete's
  // current build measured against a prior race cycle (Phase 2 sub-task F).
  // DB CHECK extended in 20260609220000_add_journey_comparison_action.sql.
  | "journey_comparison";

export interface CoachableMomentInsert {
  athlete_user_id: string;
  coach_id: string;
  rule_id: string;
  severity: Severity;
  action_type: ActionType;
  summary: string;
  source_log_ids: string[];
}

export type RuleEvaluator = (ctx: RuleContext) => CoachableMomentInsert | null;
