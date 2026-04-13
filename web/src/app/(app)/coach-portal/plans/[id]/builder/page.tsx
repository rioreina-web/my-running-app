import { createClient } from "@/lib/supabase/server";
import { redirect, notFound } from "next/navigation";
import { PlanBuilderClient } from "@/components/coach/plan-builder-client";

export default async function EditPlanBuilderPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: coachProfile } = await supabase
    .from("coach_profiles")
    .select("*")
    .eq("user_id", user.id)
    .maybeSingle();

  if (!coachProfile) redirect("/coach-portal/plans");

  const { data: plan } = await supabase
    .from("plan_templates")
    .select("*")
    .eq("id", id)
    .eq("coach_id", coachProfile.id)
    .maybeSingle();

  if (!plan) notFound();

  const { data: workoutTemplates } = await supabase
    .from("workout_templates")
    .select("*")
    .eq("coach_id", coachProfile.id)
    .order("use_count", { ascending: false });

  return (
    <PlanBuilderClient
      coachId={coachProfile.id}
      workoutTemplates={workoutTemplates ?? []}
      existingPlan={plan}
    />
  );
}
