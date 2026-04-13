import { createClient } from "@/lib/supabase/server";
import { daysUntil } from "@/lib/utils";
import type { Goal } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { SectionHeader } from "@/components/ui/section-header";
import { EditorialDivider } from "@/components/ui/editorial-divider";

export default async function GoalsPage() {
  const supabase = await createClient();

  const { data } = await supabase
    .from("user_goals")
    .select(
      "id, goal_title, goal_type, target_date, status, target_time, notes, created_at"
    )
    .order("target_date", { ascending: true });

  const goals: Goal[] = data || [];
  const active = goals.filter((g) => g.status === "active");
  const completed = goals.filter((g) => g.status === "completed");

  return (
    <div className="mx-auto max-w-5xl space-y-8">
      <h1 className="font-display text-3xl text-text-primary">Goals</h1>

      {/* Active */}
      <div>
        <SectionHeader title={`Active (${active.length})`} />
        {active.length === 0 ? (
          <Card className="mt-4">
            <p className="text-center text-sm italic text-text-tertiary">
              No active goals. Set one in the iOS app!
            </p>
          </Card>
        ) : (
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            {active.map((goal) => (
              <GoalCard key={goal.id} goal={goal} />
            ))}
          </div>
        )}
      </div>

      {/* Completed */}
      {completed.length > 0 && (
        <>
          <EditorialDivider />
          <div>
            <SectionHeader title={`Completed (${completed.length})`} />
            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              {completed.map((goal) => (
                <GoalCard key={goal.id} goal={goal} completed />
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
}

function GoalCard({
  goal,
  completed = false,
}: {
  goal: Goal;
  completed?: boolean;
}) {
  const days = daysUntil(goal.target_date);
  const targetDateFormatted = new Date(goal.target_date).toLocaleDateString(
    "en-US",
    { month: "long", day: "numeric", year: "numeric" }
  );

  return (
    <Card accent={!completed} className={completed ? "opacity-70" : ""}>
      <div className="flex items-start justify-between">
        <div>
          <h3 className="font-display text-lg text-text-primary">
            {goal.goal_title}
          </h3>
          {goal.goal_type && (
            <span className="mt-1 inline-block rounded-md bg-coral/10 px-2 py-0.5 font-mono text-[10px] text-coral">
              {goal.goal_type}
            </span>
          )}
        </div>
        {!completed && (
          <div className="text-right">
            <div className="font-mono text-2xl font-semibold text-text-primary">
              {days > 0 ? days : days === 0 ? "0" : Math.abs(days)}
            </div>
            <div className="font-mono text-[10px] text-text-tertiary">
              {days > 0 ? "days left" : days === 0 ? "TODAY" : "days past"}
            </div>
          </div>
        )}
      </div>

      <div className="mt-3 flex items-center gap-4 font-mono text-xs text-text-tertiary">
        <span>{targetDateFormatted}</span>
        {goal.target_time && (
          <span className="text-coral">{goal.target_time}</span>
        )}
      </div>

      {goal.notes && (
        <p className="mt-2 text-sm text-text-secondary">{goal.notes}</p>
      )}
    </Card>
  );
}
