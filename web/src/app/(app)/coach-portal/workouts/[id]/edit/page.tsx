import { createClient } from "@/lib/supabase/server";
import { redirect, notFound } from "next/navigation";
import { WorkoutTemplateForm, type ExistingWorkout } from "@/components/coach/workout-template-form";

export default async function EditWorkoutTemplatePage({
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
    .select("id")
    .eq("user_id", user.id)
    .maybeSingle();

  if (!coachProfile) redirect("/coach-portal/plans");

  const { data: workout } = await supabase
    .from("workout_templates")
    .select("*")
    .eq("id", id)
    .eq("coach_id", coachProfile.id)
    .maybeSingle();

  if (!workout) notFound();

  return (
    <WorkoutTemplateForm
      coachId={coachProfile.id}
      existingWorkout={workout as ExistingWorkout}
    />
  );
}
