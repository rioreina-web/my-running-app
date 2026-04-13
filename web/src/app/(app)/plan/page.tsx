import { createClient } from "@/lib/supabase/server";
import type { ScheduledWorkout, TrainingPlan } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { SectionHeader } from "@/components/ui/section-header";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import { ComplianceChart } from "@/components/charts/compliance-chart";

export default async function PlanPage() {
  const supabase = await createClient();

  const [plansResult, workoutsResult] = await Promise.all([
    supabase
      .from("training_plans")
      .select("id, plan_name, start_date, end_date, status")
      .eq("status", "active")
      .limit(1)
      .single(),
    supabase
      .from("scheduled_workouts")
      .select(
        "id, scheduled_date, workout_type, description, target_distance_miles, target_pace, completed"
      )
      .gte("scheduled_date", new Date(Date.now() - 28 * 24 * 60 * 60 * 1000).toISOString().split("T")[0])
      .order("scheduled_date", { ascending: true })
      .limit(56),
  ]);

  const plan: TrainingPlan | null = plansResult.data;
  const workouts: ScheduledWorkout[] = workoutsResult.data || [];

  // Group workouts by week
  const weeks: Record<string, ScheduledWorkout[]> = {};
  workouts.forEach((w) => {
    const date = new Date(w.scheduled_date);
    const weekStart = new Date(date);
    weekStart.setDate(date.getDate() - date.getDay());
    const key = weekStart.toISOString().split("T")[0];
    if (!weeks[key]) weeks[key] = [];
    weeks[key].push(w);
  });

  // Compliance chart data (planned vs actual per week)
  const complianceData = Object.entries(weeks).map(([weekKey, weekWorkouts]) => {
    const weekDate = new Date(weekKey);
    return {
      label: weekDate.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      }),
      planned: weekWorkouts.length,
      actual: weekWorkouts.filter((w) => w.completed).length,
    };
  });

  // Only show future weeks in the calendar
  const futureWeeks: Record<string, ScheduledWorkout[]> = {};
  const today = new Date().toISOString().split("T")[0];
  Object.entries(weeks).forEach(([key, ws]) => {
    if (ws.some((w) => w.scheduled_date >= today)) {
      futureWeeks[key] = ws;
    }
  });

  const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

  return (
    <div className="mx-auto max-w-5xl space-y-8">
      <h1 className="font-display text-3xl text-text-primary">
        Training Plan
      </h1>

      {plan ? (
        <Card accent>
          <h2 className="font-display text-lg text-text-primary">
            {plan.plan_name}
          </h2>
          <p className="mt-1 font-mono text-xs text-text-tertiary">
            {new Date(plan.start_date).toLocaleDateString("en-US", {
              month: "short",
              day: "numeric",
            })}{" "}
            &ndash;{" "}
            {new Date(plan.end_date).toLocaleDateString("en-US", {
              month: "short",
              day: "numeric",
              year: "numeric",
            })}
          </p>
        </Card>
      ) : (
        <Card>
          <p className="text-center text-sm italic text-text-tertiary">
            No active training plan. Create one from the iOS app.
          </p>
        </Card>
      )}

      {/* Compliance Chart */}
      {complianceData.length > 0 && (
        <>
          <EditorialDivider />
          <div>
            <SectionHeader title="Plan Compliance" />
            <Card className="mt-4">
              <ComplianceChart data={complianceData} height={180} />
            </Card>
          </div>
        </>
      )}

      {/* Weekly calendar grid */}
      {Object.keys(futureWeeks).length > 0 && (
        <>
          <EditorialDivider />
          <div className="space-y-6">
            {Object.entries(futureWeeks).map(([weekKey, weekWorkouts]) => {
              const weekDate = new Date(weekKey);
              const weekLabel = `Week of ${weekDate.toLocaleDateString("en-US", {
                month: "short",
                day: "numeric",
              })}`;

              return (
                <div key={weekKey}>
                  <SectionHeader title={weekLabel} />
                  <div className="mt-3 grid grid-cols-7 gap-2">
                    {DAYS.map((day, dayIndex) => {
                      const workout = weekWorkouts.find((w) => {
                        const d = new Date(w.scheduled_date);
                        return d.getDay() === dayIndex;
                      });

                      return (
                        <div
                          key={dayIndex}
                          className={`rounded-lg p-3 text-center ${
                            workout
                              ? workout.completed
                                ? "bg-mood-positive/8 border border-mood-positive/20"
                                : "bg-bg-card shadow-[0_2px_8px_rgba(0,0,0,0.06)]"
                              : "bg-bg-elevated/50"
                          }`}
                        >
                          <div className="font-mono text-[10px] text-text-tertiary">
                            {day}
                          </div>
                          {workout ? (
                            <>
                              <div className="mt-1 text-xs font-medium text-text-primary">
                                {capitalize(workout.workout_type)}
                              </div>
                              {workout.target_distance_miles && (
                                <div className="font-mono text-[10px] text-text-secondary">
                                  {workout.target_distance_miles} mi
                                </div>
                              )}
                              {workout.completed && (
                                <div className="mt-1 text-[10px] text-mood-positive">
                                  ✓
                                </div>
                              )}
                            </>
                          ) : (
                            <div className="mt-1 text-xs text-text-tertiary">
                              Rest
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1).replace(/_/g, " ");
}
