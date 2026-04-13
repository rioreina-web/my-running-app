import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { SectionHeader } from "@/components/ui/section-header";
import { Card } from "@/components/ui/card";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import { WorkoutTemplateCard } from "@/components/coach/workout-template-card";
import { CoachPortalNav } from "@/components/coach/coach-portal-nav";

const WORKOUT_TYPE_COLORS: Record<string, string> = {
  easy: "#4A9E6B",
  tempo: "#E8764A",
  intervals: "#D4592A",
  long_run: "#2D8A4E",
  recovery: "#4A9E6B",
  race: "#D4592A",
  progression: "#E8764A",
  strides: "#2D8A4E",
  rest: "#9B9590",
};

const WORKOUT_TYPE_ICONS: Record<string, string> = {
  easy: "🏃",
  tempo: "⚡",
  intervals: "🔄",
  long_run: "🛣️",
  recovery: "🍃",
  race: "🏁",
  progression: "📈",
  strides: "⚡",
  rest: "😴",
};

export default async function WorkoutTemplatesPage() {
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

  const { data: templates } = await supabase
    .from("workout_templates")
    .select("*")
    .eq("coach_id", coachProfile.id)
    .order("use_count", { ascending: false });

  const safeTemplates = templates ?? [];

  // Group by workout type
  const grouped = safeTemplates.reduce(
    (acc, t) => {
      const type = t.workout_type ?? "easy";
      if (!acc[type]) acc[type] = [];
      acc[type].push(t);
      return acc;
    },
    {} as Record<string, typeof safeTemplates>
  );

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <CoachPortalNav />
      <div className="flex items-center justify-between">
        <div>
          <SectionHeader title="Workout Library" />
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">
            Reusable workouts to drag into your training plans
          </p>
        </div>
        <Link
          href="/coach-portal/workouts/new"
          className="inline-flex items-center gap-2 px-4 py-2 bg-[var(--color-coral)] text-white text-sm font-medium rounded-lg hover:bg-[var(--color-coral-dark)] transition-colors"
        >
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
          New Template
        </Link>
      </div>

      <EditorialDivider />

      {safeTemplates.length === 0 ? (
        <Card className="py-16 text-center">
          <div className="text-4xl mb-4">🏋️</div>
          <h3 className="font-semibold text-[var(--color-text-primary)] mb-2">
            No workout templates yet
          </h3>
          <p className="text-sm text-[var(--color-text-secondary)] mb-6">
            Save your signature workouts — 10×1K, long run progressions — to quickly build plans.
          </p>
          <Link
            href="/coach-portal/workouts/new"
            className="inline-flex items-center gap-2 px-5 py-2.5 bg-[var(--color-coral)] text-white text-sm font-medium rounded-full hover:bg-[var(--color-coral-dark)] transition-colors"
          >
            Create Your First Template
          </Link>
        </Card>
      ) : (
        <div className="space-y-8">
          {(Object.entries(grouped) as [string, typeof safeTemplates][]).map(([type, typeTemplates]) => (
            <div key={type} className="space-y-3">
              <div className="flex items-center gap-2">
                <span className="text-lg">{WORKOUT_TYPE_ICONS[type] ?? "🏃"}</span>
                <h3
                  className="text-sm font-semibold uppercase tracking-wider"
                  style={{ color: WORKOUT_TYPE_COLORS[type] ?? "#D4592A" }}
                >
                  {type.replace("_", " ")}
                </h3>
                <span className="text-xs text-[var(--color-text-tertiary)]">
                  ({typeTemplates.length})
                </span>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {typeTemplates.map((template, idx) => (
                  <WorkoutTemplateCard
                    key={template.id}
                    template={template}
                    color={WORKOUT_TYPE_COLORS[type] ?? "#D4592A"}
                    refIndex={idx + 1}
                  />
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
