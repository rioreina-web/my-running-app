import { createClient } from "@/lib/supabase/server";
import { daysUntil, formatDate } from "@/lib/utils";

interface Goal {
  id: string;
  goal_title: string;
  goal_type: string | null;
  target_date: string;
  status: string;
  target_time: string | null;
  notes: string | null;
  created_at: string;
}

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
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="font-display text-3xl tracking-wider text-text-primary">
        GOALS
      </h1>

      {/* Active */}
      <div>
        <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
          ACTIVE ({active.length})
        </h2>
        {active.length === 0 ? (
          <div className="rounded-xl border border-bg-elevated bg-bg-card p-8 text-center text-sm text-text-tertiary">
            No active goals. Set one in the iOS app!
          </div>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">
            {active.map((goal) => (
              <GoalCard key={goal.id} goal={goal} />
            ))}
          </div>
        )}
      </div>

      {/* Completed */}
      {completed.length > 0 && (
        <div>
          <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
            COMPLETED ({completed.length})
          </h2>
          <div className="grid gap-4 sm:grid-cols-2">
            {completed.map((goal) => (
              <GoalCard key={goal.id} goal={goal} completed />
            ))}
          </div>
        </div>
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
    <div
      className={`rounded-xl border p-5 space-y-3 ${
        completed
          ? "border-bg-elevated bg-bg-card/50"
          : "border-coral/30 bg-bg-card"
      }`}
    >
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <span>{completed ? "✅" : "🏁"}</span>
            <h3 className="font-medium text-text-primary">
              {goal.goal_title}
            </h3>
          </div>
          {goal.goal_type && (
            <span className="mt-1 inline-block rounded-md bg-coral/10 px-2 py-0.5 font-mono text-[10px] text-coral">
              {goal.goal_type}
            </span>
          )}
        </div>
        {!completed && (
          <div className="text-right">
            <div className="font-mono text-2xl font-bold text-text-primary">
              {days > 0 ? days : days === 0 ? "🔥" : Math.abs(days)}
            </div>
            <div className="font-mono text-[10px] text-text-tertiary">
              {days > 0 ? "days left" : days === 0 ? "TODAY" : "days past"}
            </div>
          </div>
        )}
      </div>

      <div className="flex items-center gap-4 font-mono text-xs text-text-tertiary">
        <span>{targetDateFormatted}</span>
        {goal.target_time && (
          <span className="text-coral">{goal.target_time}</span>
        )}
      </div>

      {goal.notes && (
        <p className="text-sm text-text-secondary">{goal.notes}</p>
      )}
    </div>
  );
}
