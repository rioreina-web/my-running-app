import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { WorkoutTemplateForm } from "@/components/coach/workout-template-form";

export default async function NewWorkoutTemplatePage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: coachProfile } = await supabase
    .from("coach_profiles")
    .select("id")
    .eq("user_id", user.id)
    .maybeSingle();

  if (!coachProfile) redirect("/coach-portal/plans");

  return <WorkoutTemplateForm coachId={coachProfile.id} />;
}
