import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { PlanBuilderClient } from "@/components/coach/plan-builder-client";

export default async function NewPlanPage() {
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

  const { data: workoutTemplates } = await supabase
    .from("workout_templates")
    .select("*")
    .eq("coach_id", coachProfile.id)
    .order("use_count", { ascending: false });

  return (
    <PlanBuilderClient
      coachId={coachProfile.id}
      workoutTemplates={workoutTemplates ?? []}
      existingPlan={null}
    />
  );
}
