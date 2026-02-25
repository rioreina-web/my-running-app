import { createClient } from "@/lib/supabase/server";
import { TrainingLogList } from "./training-log-list";

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
}

export default async function TrainingLogPage() {
  const supabase = await createClient();

  const { data } = await supabase
    .from("training_logs")
    .select(
      "id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes, coach_insight, workout_notes, extracted_data"
    )
    .order("workout_date", { ascending: false, nullsFirst: false })
    .limit(50);

  const logs: TrainingLog[] = data || [];

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="font-display text-3xl tracking-wider text-text-primary">
          TRAINING LOG
        </h1>
        <span className="font-mono text-xs text-text-tertiary">
          {logs.length} entries
        </span>
      </div>

      {logs.length === 0 ? (
        <div className="rounded-xl border border-bg-elevated bg-bg-card p-12 text-center">
          <p className="text-text-tertiary">
            No training logs yet. Log a run from the iOS app to see it here.
          </p>
        </div>
      ) : (
        <TrainingLogList initialLogs={logs} />
      )}
    </div>
  );
}
