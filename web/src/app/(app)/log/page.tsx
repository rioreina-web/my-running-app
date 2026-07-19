import { createClient, getUserId } from "@/lib/supabase/server";
import type { TrainingLog } from "@/lib/types";
import { JournalView, type NextUp, type Niggle } from "./journal-view";

export default async function TrainingLogPage() {
  const supabase = await createClient();
  const userId = await getUserId();
  const uid = userId || "";

  const now = new Date();
  const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;

  const [logsRes, planRes, nextRes, niggleRes] = await Promise.all([
    supabase
      .from("training_logs")
      .select(
        "id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes, coach_insight, workout_notes, extracted_data, pace_segments, source, vital_workout_id, processing_status"
      )
      .eq("user_id", uid)
      .neq("source", "auto_sync")
      .order("workout_date", { ascending: false, nullsFirst: false })
      .limit(60),
    // Active plan name — the "Boston build" headline in the rail.
    supabase
      .from("training_plans")
      .select("name")
      .eq("status", "active")
      .limit(1)
      .maybeSingle(),
    // Next unfinished scheduled workout (RLS scopes to the athlete).
    supabase
      .from("scheduled_workouts")
      .select("scheduled_date, workout_type, description, target_distance_miles, target_pace")
      .gte("scheduled_date", todayStr)
      .eq("completed", false)
      .order("scheduled_date", { ascending: true })
      .limit(1)
      .maybeSingle(),
    // Recent niggles — body-part mentions surfaced from voice logs.
    supabase
      .from("body_mentions")
      .select("body_area, side, verbatim_quote, severity_hint, mentioned_at")
      .eq("user_id", uid)
      .order("mentioned_at", { ascending: false })
      .limit(12),
  ]);

  const logs: TrainingLog[] = logsRes.data || [];

  const nw = nextRes.data as
    | {
        scheduled_date: string;
        workout_type: string | null;
        description: string | null;
        target_distance_miles: number | null;
        target_pace: string | null;
      }
    | null;

  const nextUp: NextUp | null = nw
    ? {
        planName: (planRes.data as { name: string | null } | null)?.name ?? null,
        date: nw.scheduled_date,
        workoutType: nw.workout_type,
        description: nw.description,
        distanceMiles: nw.target_distance_miles,
      }
    : null;

  const niggles: Niggle[] = (niggleRes.data as Niggle[] | null) || [];

  return <JournalView logs={logs} nextUp={nextUp} niggles={niggles} />;
}
