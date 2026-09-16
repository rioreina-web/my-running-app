import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import {
  WorkoutTemplateForm,
  type DuplicateSeed,
} from "@/components/coach/workout-template-form";

export default async function NewWorkoutTemplatePage({
  searchParams,
}: {
  searchParams: Promise<{ from?: string }>;
}) {
  const { from } = await searchParams;
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

  // Duplicate flow — `?from=<templateId>` pre-fills the editor with a clone
  // of the source template (name suffixed " (copy)", matching
  // plan-builder-client's duplicateTemplate convention). Nothing is written
  // to the DB until the coach saves. Scoped to the coach's own templates;
  // an unknown or foreign id silently falls back to a blank editor.
  let seed: DuplicateSeed | null = null;
  if (from) {
    const { data: source } = await supabase
      .from("workout_templates")
      .select("id, name, workout_type, description, tags, workout_data")
      .eq("id", from)
      .eq("coach_id", coachProfile.id)
      .maybeSingle();

    if (source) {
      seed = {
        sourceTemplateId: source.id,
        name: `${source.name} (copy)`,
        workout_type: source.workout_type,
        description: source.description,
        tags: source.tags,
        workout_data: source.workout_data,
      };
    }
  }

  return <WorkoutTemplateForm coachId={coachProfile.id} seed={seed} />;
}
