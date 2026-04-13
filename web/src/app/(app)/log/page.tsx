import { createClient, getUserId } from "@/lib/supabase/server";
import type { TrainingLog } from "@/lib/types";
import { JournalView } from "./journal-view";

export default async function TrainingLogPage() {
  const supabase = await createClient();
  const userId = await getUserId();

  const { data } = await supabase
    .from("training_logs")
    .select(
      "id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes, coach_insight, workout_notes, extracted_data, pace_segments, source, vital_workout_id, processing_status"
    )
    .eq("user_id", userId || "")
    .neq("source", "auto_sync")
    .order("workout_date", { ascending: false, nullsFirst: false })
    .limit(60);

  const logs: TrainingLog[] = data || [];

  return <JournalView logs={logs} />;
}
