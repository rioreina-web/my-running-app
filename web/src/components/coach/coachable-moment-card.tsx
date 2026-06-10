"use client";

import { useTransition } from "react";
import { Card } from "@/components/ui/card";
import {
  handleMomentAction,
  dismissMomentAction,
} from "@/app/(app)/coach-portal/athletes/[id]/actions";

// One coachable_moment rendered as a single attention card. Top-of-page on
// the athlete deep-dive. Tap "Take Action" to mark handled (the deep-dive
// is the action — the coach reviews source workouts, sends a message, etc.
// before flipping status); tap "Dismiss" to close it without a follow-up.
//
// Severity colors: low = slate, med = amber, high = rose. The left stripe
// is the only severity affordance — keeps the card itself readable.
//
// Spec: docs/specs/coachable_moment.md

export interface CoachableMomentRow {
  id: string;
  athlete_user_id: string;
  rule_id: string;
  severity: "low" | "med" | "high";
  action_type:
    | "send_check_in"
    | "suggest_deload"
    | "recommend_evaluation"
    | "monitor";
  summary: string;
  source_log_ids: string[] | null;
  triggered_at: string;
}

const SEVERITY_META: Record<
  CoachableMomentRow["severity"],
  { stripe: string; tag: string; label: string }
> = {
  low:  { stripe: "bg-slate-300",   tag: "text-slate-700 bg-slate-100",   label: "Low priority" },
  med:  { stripe: "bg-amber-400",   tag: "text-amber-700 bg-amber-100",   label: "Medium priority" },
  high: { stripe: "bg-rose-500",    tag: "text-rose-700 bg-rose-100",     label: "Needs attention" },
};

const ACTION_LABEL: Record<CoachableMomentRow["action_type"], string> = {
  send_check_in: "Send check-in",
  suggest_deload: "Suggest deload",
  recommend_evaluation: "Recommend evaluation",
  monitor: "Monitor",
};

export function CoachableMomentCard({ moment }: { moment: CoachableMomentRow }) {
  const [isPending, startTransition] = useTransition();
  const meta = SEVERITY_META[moment.severity];

  return (
    <Card padding="md" className="relative overflow-hidden">
      <div
        className={`absolute left-0 top-0 bottom-0 w-1 ${meta.stripe}`}
        aria-hidden
      />
      <div className="pl-3 flex items-start justify-between gap-4 flex-wrap">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <span
              className={`px-1.5 py-0.5 rounded text-[10px] font-medium ${meta.tag}`}
            >
              {meta.label}
            </span>
            <span className="text-[10px] tracking-wider uppercase text-[var(--color-text-tertiary)]">
              {moment.rule_id.replace(/_/g, " ")}
            </span>
            <span className="text-[10px] text-[var(--color-text-tertiary)]">
              · {timeAgo(moment.triggered_at)}
            </span>
          </div>
          <p className="mt-2 text-sm text-[var(--color-text-primary)] leading-relaxed">
            {moment.summary}
          </p>
          <p className="mt-1 text-xs text-[var(--color-text-secondary)]">
            Suggested action: {ACTION_LABEL[moment.action_type]}
          </p>
        </div>
        <div className="flex flex-col gap-2 shrink-0">
          <button
            type="button"
            disabled={isPending}
            onClick={() =>
              startTransition(async () => {
                await handleMomentAction(moment.id, moment.athlete_user_id);
              })
            }
            className="px-3 py-1.5 rounded-md text-xs font-medium bg-[var(--color-coral)] text-white hover:bg-[var(--color-coral)]/90 disabled:opacity-50"
          >
            Take action
          </button>
          <button
            type="button"
            disabled={isPending}
            onClick={() =>
              startTransition(async () => {
                await dismissMomentAction(moment.id, moment.athlete_user_id);
              })
            }
            className="px-3 py-1.5 rounded-md text-xs border border-[var(--color-divider)] text-[var(--color-text-secondary)] hover:border-[var(--color-coral)] hover:text-[var(--color-coral)] disabled:opacity-50"
          >
            Dismiss
          </button>
        </div>
      </div>
    </Card>
  );
}

function timeAgo(isoTimestamp: string): string {
  const ms = Date.now() - new Date(isoTimestamp).getTime();
  const m = Math.floor(ms / 60_000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}
