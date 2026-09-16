import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { SectionHeader } from "@/components/ui/section-header";
import { Card } from "@/components/ui/card";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import { PlanTemplateRow } from "@/components/coach/plan-template-row";
import { CoachSetupPrompt } from "@/components/coach/coach-setup-prompt";
import { EmptyState } from "@/components/ui/empty-state";

export default async function CoachPlansPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  // Check for coach profile
  const { data: coachProfile } = await supabase
    .from("coach_profiles")
    .select("*")
    .eq("user_id", user.id)
    .maybeSingle();

  if (!coachProfile) {
    return <CoachSetupPrompt />;
  }

  // Load plan templates
  const { data: plans } = await supabase
    .from("plan_templates")
    .select("*")
    .eq("coach_id", coachProfile.id)
    .order("created_at", { ascending: false });

  const planList = plans ?? [];

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <SectionHeader title="Training Plans" />
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">
            Build 12–16 week plan templates for athletes to subscribe to
          </p>
        </div>
        <Link
          href="/coach-portal/plans/new"
          className="inline-flex items-center gap-2 px-4 py-2 bg-[var(--color-coral)] text-white text-sm font-medium rounded-lg hover:bg-[var(--color-coral-dark)] transition-colors"
        >
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
          New Plan
        </Link>
      </div>

      <EditorialDivider />

      {/* Plan list */}
      {planList.length === 0 ? (
        <Card className="py-6">
          <EmptyState
            variant="setup-needed"
            eyebrow="Training plans"
            title="Create a 12–16 week plan template that athletes can subscribe to."
            cta={{ label: "Build your first plan", href: "/coach-portal/plans/new" }}
          />
        </Card>
      ) : (
        <div className="space-y-0 border border-[var(--color-divider)] rounded-xl overflow-hidden">
          {planList.map((plan, idx) => (
            <PlanTemplateRow
              key={plan.id}
              plan={plan}
              isLast={idx === planList.length - 1}
            />
          ))}
        </div>
      )}

      <EditorialDivider />

      {/* Quick stats */}
      <div className="grid grid-cols-3 gap-4">
        <Card className="text-center py-4">
          <div className="font-mono text-2xl text-[var(--color-text-primary)]">
            {planList.length}
          </div>
          <div className="text-xs text-[var(--color-text-tertiary)] mt-1">Plans Created</div>
        </Card>
        <Card className="text-center py-4">
          <div className="font-mono text-2xl text-[var(--color-text-primary)]">
            {planList.filter((p) => p.is_published).length}
          </div>
          <div className="text-xs text-[var(--color-text-tertiary)] mt-1">Published</div>
        </Card>
        <Card className="text-center py-4">
          <div className="font-mono text-2xl text-[var(--color-text-primary)]">
            {planList.reduce((sum, p) => sum + (p.subscriber_count ?? 0), 0)}
          </div>
          <div className="text-xs text-[var(--color-text-tertiary)] mt-1">Athletes</div>
        </Card>
      </div>
    </div>
  );
}
