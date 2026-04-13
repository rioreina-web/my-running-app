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
}

export interface TrainingPlan {
  id: string;
  plan_name: string;
  start_date: string;
  end_date: string;
  status: string;
}
