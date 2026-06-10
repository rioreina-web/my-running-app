/** Shared type definitions used across pages and components */

export interface PaceSegment {
  effort: string;
  distance_miles: number;
  pace_per_mile: string;
  duration_seconds: number;
  avg_heart_rate?: number;
}

export interface TrainingLog {
  id: string;
  created_at: string;
  workout_date: string | null;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null;
  workout_type: string | null;
  mood: string | null;
  cleaned_notes: string | null;
  notes: string | null;
  coach_insight: string | null;
  workout_notes: string | null;
  extracted_data: Record<string, unknown> | null;
  pace_segments: PaceSegment[] | null;
  source: string | null;
  vital_workout_id: string | null;
  processing_status: string | null;
}

export interface VitalSummary {
  averageHr: number | null;
  maxHr: number | null;
  totalElevationGain: number | null;
  movingTime: number | null;
  calories: number | null;
  averageSpeed: number | null;
  steps: number | null;
}

export interface MileSplit {
  mile: number;
  paceMinutes: number;
  isPartial?: boolean;
  partialDistance?: number;
}

export interface Injury {
  id: string;
  body_area: string;
  side: string;
  severity: number;
  status: string;
  first_reported_at: string;
  source_text: string | null;
  ai_analysis: Record<string, unknown> | null;
}

export interface Goal {
  id: string;
  goal_title: string;
  goal_type: string | null;
  target_date: string;
  status: string;
  target_time: string | null;
  notes: string | null;
  created_at: string;
}

export interface ScheduledWorkout {
  id: string;
  scheduled_date: string;
  workout_type: string;
  description: string | null;
  target_distance_miles: number | null;
  target_pace: string | null;
  completed: boolean;
  // Coach's one-line rationale surfaced under each day on the athlete's
  // plan view. Populated by `generate-day-rationale` edge fn (Phase 4).
  // Null for rows that haven't been backfilled yet — UI falls back to a
  // generic placeholder derived from workout_type.
  rationale_short?: string | null;
  // Structured { why_today, why_this_workout, why_this_pace } for the
  // "Why?" drawer. Phase 4.
  rationale_full?: {
    why_today?: string[];
    why_this_workout?: string;
    why_this_pace?: string;
  } | null;
}

// Athlete-driven plan adjustment severity. See migration
// 20260424100000_athlete_plan_ux.sql + docs/athlete-plan-ux.md §3.
export type PlanAdjustmentTier = "green" | "yellow" | "red";

export interface TrainingPlan {
  id: string;
  // DB column is `name`. The web /plan page used to query `plan_name`,
  // which silently failed and rendered the empty state even when the
  // athlete had an active plan. iOS writes to `name`; keep them aligned.
  name: string;
  start_date: string;
  end_date: string;
  status: string;
}
