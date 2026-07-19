import { createClient } from "@/lib/supabase/server";
import { Plus } from "lucide-react";
import Link from "next/link";
import { PlateStrip } from "@/components/ui/plate-strip";
import { PageHeader } from "@/components/ui/page-header";
import { Eyebrow } from "@/components/ui/eyebrow";
import { ZoneDot } from "@/components/ui/zone-dot";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import { EmptyState } from "@/components/ui/empty-state";
import { WorkoutTemplateCard } from "@/components/coach/workout-template-card";
import { CoachPortalNav } from "@/components/coach/coach-portal-nav";

// Pace/intensity = single-hue blue depth ramp (source of truth:
// RunningLog/Workouts/PaceSpectrum.swift). Blue = pace, warm = mood,
// coral = alert; the three palettes never share hues. The type color shows
// only as a small dot beside the section label and a soft chip on each card —
// never as a colored heading, never as an emoji.
const WORKOUT_TYPE_COLORS: Record<string, string> = {
  easy: "#93B9D6",
  recovery: "#B4ADA4", // warm gray — below Easy
  long_run: "#578FC0", // steady
  progression: "#3F7CB5", // MP
  tempo: "#27549B", // LT
  intervals: "#1A3679", // 5K
  strides: "#142964", // 3K
  race: "#0E1D4E", // navy — hardest
  rest: "#9B9590", // neutral gray
};

// Human labels for the section headers, in place of the raw enum. Keeps the
// grouping labels editorial ("Long Run", not "long_run").
const WORKOUT_TYPE_LABELS: Record<string, string> = {
  easy: "Easy",
  recovery: "Recovery",
  long_run: "Long Run",
  progression: "Progression",
  tempo: "Tempo",
  intervals: "Intervals",
  strides: "Strides",
  race: "Race",
  rest: "Rest",
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

  const libraryCount = safeTemplates.length;

  return (
    <div className="mx-auto max-w-4xl">
      <PlateStrip
        surface="Workout Library · Coach Portal"
        figure="FIG. — LIB"
        right={libraryCount > 0 ? `${libraryCount} on file` : "Empty"}
        padded={false}
        rule
        className="mb-4"
      />

      <CoachPortalNav />

      <PageHeader
        eyebrow="Workout Library"
        eyebrowRight={libraryCount > 0 ? `${libraryCount} templates` : undefined}
        title="Reusable workouts."
        subtitle="Signature sessions to drag into your training plans — saved once, reused everywhere."
        action={
          <Link
            href="/coach-portal/workouts/new"
            className="inline-flex items-center gap-2 rounded-[10px] bg-coral px-4 py-2.5 font-display text-[15px] font-semibold text-white transition-colors hover:bg-coral-dark focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral focus-visible:ring-offset-2 focus-visible:ring-offset-bg-base"
          >
            <Plus size={16} strokeWidth={2} />
            New Template
          </Link>
        }
      />

      <EditorialDivider className="mt-6" />

      {libraryCount === 0 ? (
        <EmptyState
          variant="optional-empty"
          eyebrow="Workout Library"
          title="No templates yet. Save your signature workouts — a 10×1K set, a long-run progression — and they land here to reuse across plans."
          cta={{ label: "Create your first template ↗", href: "/coach-portal/workouts/new" }}
          className="mt-10"
        />
      ) : (
        <div className="mt-8 space-y-10">
          {(Object.entries(grouped) as [string, typeof safeTemplates][]).map(
            ([type, typeTemplates]) => {
              const color = WORKOUT_TYPE_COLORS[type] ?? "#9B9590";
              const label = WORKOUT_TYPE_LABELS[type] ?? type.replace("_", " ");
              return (
                <section key={type} className="space-y-4">
                  <div className="flex items-center gap-2">
                    <ZoneDot color={color} />
                    <Eyebrow>{label}</Eyebrow>
                    <span className="font-mono text-[10px] text-text-tertiary">
                      {typeTemplates.length}
                    </span>
                  </div>
                  <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                    {typeTemplates.map((template, idx) => (
                      <WorkoutTemplateCard
                        key={template.id}
                        template={template}
                        color={color}
                        refIndex={idx + 1}
                      />
                    ))}
                  </div>
                </section>
              );
            }
          )}
        </div>
      )}
    </div>
  );
}
