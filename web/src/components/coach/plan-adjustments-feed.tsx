// Read-only feed of plan_adjustments for one athlete — newest first,
// tier-colored. Surfaces BOTH the athlete's Phase A moves (shift_day /
// reshape_week, written by the shift-day edge fn) AND coach rewrites
// (rewrite_block, written by rewrite-block). Phase B, R5/R4 visibility.
// Spec: outputs/adaptive-coach-plan-builder-spec-2026-07-03.md §4/§6.3,
// outputs/phase-b-live-plan-editing-buildplan-2026-07-03.md B2.
//
// Purely presentational — no interactivity, so this is a server component.
//
// NOTE (prod drift, 2026-07-03): `tier`, `reason_code`, `reason_text`,
// `week_number` land with migrations 20260424100000 + 20260703120000, which
// are PENDING db push. Until then those fields are undefined and the row
// degrades gracefully (no tier stripe, no reason line). The page fetches with
// select("*") so a missing column never errors the query.

export interface PlanAdjustmentRow {
  id: string;
  trigger_type: string | null;
  action_type: string | null;
  tier?: "green" | "yellow" | "red" | null;
  reason_code?: string | null;
  reason_text?: string | null;
  week_number?: number | null;
  applied_at: string | null;
  auto_applied?: boolean | null;
}

// Routine reads neutral, never green (three-palette rule: green is
// mood-only). Flagged is the amber warning; needs-review is coral alert.
const TIER_META: Record<string, { stripe: string; label: string }> = {
  green:  { stripe: "bg-text-tertiary", label: "Routine" },
  yellow: { stripe: "bg-warning",       label: "Flagged" },
  red:    { stripe: "bg-coral",         label: "Needs review" },
};

// Who initiated the change — drives the lead word on each row.
const ACTOR: Record<string, string> = {
  coach_rewrite: "You",
  user_action: "Athlete",
};

const ACTION_VERB: Record<string, string> = {
  shift_day: "moved a day",
  reshape_week: "reshaped the week",
  rewrite_block: "rewrote a block",
  reduce_volume: "reduced volume",
  cap_volume: "capped volume",
  reprice_future_paces: "adjusted paces",
  propose_swap: "proposed a swap",
  pause_quality: "paused quality",
  update_fitness: "updated fitness",
};

// Readable reasons across both vocabularies (move-day + coach-rewrite).
const REASON_LABEL: Record<string, string> = {
  work: "work",
  fatigue: "fatigue",
  schedule_conflict: "schedule conflict",
  weather: "weather",
  travel: "travel",
  feeling_good: "feeling good",
  sickness: "sickness",
  injury_niggle: "a niggle",
  race_change: "a race change",
  life_event: "a life event",
  performance: "performance",
  other: "other",
  // legacy 2026-04 buckets
  shift_day: null as unknown as string,
  flat_week: "a flat week",
  extra_rest_day: "an extra rest day",
  extra_day: "an extra day",
};

function actorLabel(triggerType: string | null): string {
  if (triggerType && ACTOR[triggerType]) return ACTOR[triggerType];
  return "System";
}

function summarize(a: PlanAdjustmentRow): string {
  const actor = actorLabel(a.trigger_type);
  const verb = (a.action_type && ACTION_VERB[a.action_type]) || "made a change";
  const wk = typeof a.week_number === "number" ? ` · week ${a.week_number}` : "";
  const reason =
    a.reason_code && REASON_LABEL[a.reason_code]
      ? ` (${REASON_LABEL[a.reason_code]})`
      : "";
  return `${actor} ${verb}${wk}${reason}`;
}

function timeAgo(iso: string | null): string {
  if (!iso) return "";
  const ms = Date.now() - new Date(iso).getTime();
  const m = Math.floor(ms / 60_000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  if (d < 30) return `${d}d ago`;
  return `${Math.floor(d / 30)}mo ago`;
}

export function PlanAdjustmentsFeed({ adjustments }: { adjustments: PlanAdjustmentRow[] }) {
  return (
    <ul className="mt-4 space-y-2">
      {adjustments.map((a) => {
        const tier = a.tier ? TIER_META[a.tier] : null;
        return (
          <li
            key={a.id}
            className="relative overflow-hidden rounded-md border border-divider bg-bg-card pl-3 pr-4 py-3"
          >
            <span
              className={`absolute left-0 top-0 bottom-0 w-1 ${tier?.stripe ?? "bg-divider"}`}
              aria-hidden
            />
            <div className="flex items-baseline justify-between gap-3 flex-wrap">
              <p className="font-body text-sm text-text-primary">{summarize(a)}</p>
              <span className="font-body text-[11px] text-text-tertiary shrink-0">
                {timeAgo(a.applied_at)}
              </span>
            </div>
            {a.reason_text ? (
              <p className="mt-1 font-body text-xs text-text-secondary leading-relaxed">
                “{a.reason_text}”
              </p>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}
