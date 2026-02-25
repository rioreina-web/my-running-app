import { createClient } from "@/lib/supabase/server";

interface ScheduledWorkout {
  id: string;
  scheduled_date: string;
  workout_type: string;
  description: string | null;
  target_distance_miles: number | null;
  target_pace: string | null;
  completed: boolean;
}

interface TrainingPlan {
  id: string;
  plan_name: string;
  start_date: string;
  end_date: string;
  status: string;
}

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
      .gte("scheduled_date", new Date().toISOString().split("T")[0])
      .order("scheduled_date", { ascending: true })
      .limit(28),
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

  const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="font-display text-3xl tracking-wider text-text-primary">
        TRAINING PLAN
      </h1>

      {plan ? (
        <div className="rounded-xl border border-coral/30 bg-bg-card p-4">
          <h2 className="font-medium text-text-primary">{plan.plan_name}</h2>
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
        </div>
      ) : (
        <div className="rounded-xl border border-bg-elevated bg-bg-card p-8 text-center text-sm text-text-tertiary">
          No active training plan. Create one from the iOS app.
        </div>
      )}

      {/* Weekly calendar grid */}
      {Object.keys(weeks).length > 0 && (
        <div className="space-y-4">
          {Object.entries(weeks).map(([weekKey, weekWorkouts]) => {
            const weekDate = new Date(weekKey);
            const weekLabel = `Week of ${weekDate.toLocaleDateString("en-US", {
              month: "short",
              day: "numeric",
            })}`;

            return (
              <div key={weekKey}>
                <h3 className="mb-2 font-mono text-xs tracking-widest text-text-tertiary">
                  {weekLabel.toUpperCase()}
                </h3>
                <div className="grid grid-cols-7 gap-2">
                  {DAYS.map((day, dayIndex) => {
                    const workout = weekWorkouts.find((w) => {
                      const d = new Date(w.scheduled_date);
                      return d.getDay() === dayIndex;
                    });

                    return (
                      <div
                        key={dayIndex}
                        className={`rounded-lg border p-3 text-center ${
                          workout
                            ? workout.completed
                              ? "border-mood-positive/30 bg-mood-positive/5"
                              : "border-bg-elevated bg-bg-card"
                            : "border-bg-elevated/50 bg-bg-base"
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
      )}
    </div>
  );
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1).replace(/_/g, " ");
}
