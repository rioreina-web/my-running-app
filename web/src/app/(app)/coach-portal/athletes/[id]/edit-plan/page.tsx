import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  LivePlanEditorClient,
  type EditableWorkout,
} from "@/components/coach/live-plan-editor-client";
import { PlanEditTextBox } from "@/components/coach/plan-edit-textbox";

// Coach "Edit live plan" screen (R5, Phase B / build-plan B5). Loads the
// athlete's active plan and its FUTURE scheduled_workouts, then hands off to
// the client editor which posts to /api/rewrite-block. Past weeks are never
// loaded here — they're immutable history and the edge fn rejects them anyway.

export default async function EditLivePlanPage({
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

  // Same ownership gate as the athlete detail page: the coach must own a plan
  // template this athlete is actively subscribed to.
  const { data: gateRow } = await supabase
    .from("athlete_plan_subscriptions")
    .select("id, plan_template:plan_templates!inner(coach_id)")
    .eq("athlete_user_id", id)
    .eq("status", "active")
    .eq("plan_template.coach_id", coachProfile.id)
    .limit(1)
    .maybeSingle();
  if (!gateRow) notFound();

  const { data: plan } = await supabase
    .from("training_plans")
    .select("id, name, end_date")
    .eq("user_id", id)
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!plan) notFound();

  // Future-dated workouts only (UTC "today", matching the edge fn's cutoff).
  const today = new Date().toISOString().slice(0, 10);
  const { data: rows } = await supabase
    .from("scheduled_workouts")
    .select("id, date, day_of_week, week_number, workout_type, workout_data, notes")
    .eq("plan_id", plan.id)
    .gt("date", today)
    .order("date", { ascending: true });

  const workouts = (rows ?? []) as EditableWorkout[];

  return (
    <div className="mx-auto max-w-3xl px-4 py-8 space-y-8">

      <Link
        href={`/coach-portal/athletes/${id}`}
        className="inline-block text-xs text-text-tertiary hover:text-coral transition-colors"
      >
        ← Back to athlete
      </Link>

      <PlanEditTextBox athleteUserId={id} />

      <LivePlanEditorClient
        athleteUserId={id}
        planId={plan.id}
        planName={plan.name ?? "Training plan"}
        raceEndDate={plan.end_date ?? null}
        workouts={workouts}
      />
    </div>
  );
}
