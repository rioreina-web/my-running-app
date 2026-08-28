import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { CoachAthleteDashboard } from "@/components/coach/dashboard/coach-dashboard";
import { buildDashboardFromSupabase } from "@/lib/coach-dashboard/from-supabase";

// Coach athlete deep-dive (Phase 1). Gates coach access, then renders the
// dashboard from this athlete's live data (training_logs / coachable_moments
// via the coach's RLS client; athlete_state / body_mentions via service role,
// scoped to this already-authorized athlete). The mapping lives in
// buildDashboardFromSupabase; the view is shared with the /design preview.
export default async function CoachAthleteDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: coachProfile } = await supabase
    .from("coach_profiles")
    .select("id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (!coachProfile) return null;

  // Coach must own an active subscription with this athlete (same gate the
  // roster uses — through plan_templates.coach_id).
  const { data: gateRow } = await supabase
    .from("athlete_plan_subscriptions")
    .select("id, plan_template:plan_templates!inner(coach_id)")
    .eq("athlete_user_id", id)
    .eq("status", "active")
    .eq("plan_template.coach_id", coachProfile.id)
    .limit(1)
    .maybeSingle();
  if (!gateRow) notFound();

  const data = await buildDashboardFromSupabase(id);

  return (
    <div>
      <div className="mx-auto max-w-[1060px] px-4 pt-4">
        <Link
          href="/coach-portal/athletes"
          className="font-mono text-[11px] uppercase tracking-[0.08em] text-text-secondary transition-colors hover:text-coral"
        >
          ← Back to roster
        </Link>
      </div>
      <CoachAthleteDashboard data={data} />
    </div>
  );
}
