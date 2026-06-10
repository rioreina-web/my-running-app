import { createClient } from "@/lib/supabase/server";
import { PaceChartClient } from "./pace-chart-client";

// Server entry. Fetches the canonical pace profile (current paces) and the
// latest fitness snapshot (projected fitness), then hands both to the client
// so the user can toggle between Current / Projected / Goal / Custom anchors.

export default async function PaceChartPage() {
  const supabase = await createClient();

  const [profileRes, snapshotRes] = await Promise.all([
    supabase
      .from("athlete_pace_profiles")
      .select(
        "goal_race_distance, goal_time_seconds, easy_pace_seconds, easy_pace_confidence, marathon_pace_seconds, marathon_pace_confidence, half_pace_seconds, half_pace_confidence, ten_k_pace_seconds, ten_k_pace_confidence, five_k_pace_seconds, five_k_pace_confidence, mile_pace_seconds, mile_pace_confidence, generated_at"
      )
      .order("generated_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from("fitness_snapshots")
      .select(
        "predicted_mile_seconds, predicted_5k_seconds, predicted_10k_seconds, predicted_half_seconds, predicted_marathon_seconds, confidence, created_at"
      )
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
  ]);

  return (
    <PaceChartClient
      profile={profileRes.data ?? null}
      snapshot={snapshotRes.data ?? null}
    />
  );
}
