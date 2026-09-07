// Card component for the coach roster dashboard.
import { Check } from "lucide-react";
//
// Three signals live in the body:
//   1. Mileage trend — 6-week sparkline with the current week highlighted
//   2. Pace adherence — single colored pill (on track / slipping / way off)
//   3. Wellness flags — small icon row with reasons on hover
//
// Pace adherence and wellness flags are typed as enums/string literals so
// we can swap the prototype's stubbed values for real data without
// touching the component.

import Link from "next/link";
import { Card } from "@/components/ui/card";

export type PaceAdherenceState = "on_track" | "slipping" | "way_off" | "unknown";
/// Wellness flag taxonomy. Today the page derives these from athlete_state:
///   fatigue       — last_mood IN ('tired','struggling') OR mood_trend declining
///   injury_risk   — injury_risk_score ≥ 5 OR active_injuries non-empty
///   overreaching  — ACWR > 1.5
/// hr_drift / sleep / soreness stay reserved for when Vital readiness data
/// gets wired into athlete_state.
export type WellnessFlag =
  | "fatigue"
  | "hr_drift"
  | "sleep"
  | "soreness"
  | "injury_risk"
  | "overreaching";

export interface RosterAthlete {
  subscriptionId: string;
  athleteId: string;
  displayName: string;
  planName: string;
  weeksIn: number;
  totalWeeks: number;
  /// Six entries, oldest week first, current week last. Miles per week.
  mileageTrend: number[];
  paceAdherence: PaceAdherenceState;
  wellnessFlags: WellnessFlag[];
}

// Three-palette rule: on-track is the safe zone, and safe reads NEUTRAL
// gray, never green (green is mood-only). Slipping gets the amber warning
// tone; off-pace is the alert — coral.
const PACE_LABELS: Record<PaceAdherenceState, { label: string; bg: string; fg: string }> = {
  on_track: {
    label: "On pace",
    bg: "bg-bg-calendar",
    fg: "text-text-secondary",
  },
  slipping: {
    label: "Slipping",
    bg: "bg-warning/12",
    fg: "text-warning",
  },
  way_off: {
    label: "Off pace",
    bg: "bg-coral/12",
    fg: "text-coral-dark",
  },
  unknown: {
    label: "No data",
    bg: "bg-bg-calendar",
    fg: "text-text-tertiary",
  },
};

// Label-only — emojis dropped per the editorial style applied across
// the roster + athlete pages. Each flag renders as a small text pill in
// the amber warning wash (set by the consumer below).
const WELLNESS_META: Record<WellnessFlag, { label: string }> = {
  fatigue: { label: "Fatigue" },
  hr_drift: { label: "HR drift" },
  sleep: { label: "Sleep" },
  soreness: { label: "Soreness" },
  injury_risk: { label: "Injury risk" },
  overreaching: { label: "Overreaching" },
};

export function AthleteRosterCard({ athlete }: { athlete: RosterAthlete }) {
  const pace = PACE_LABELS[athlete.paceAdherence];
  const total = athlete.mileageTrend.reduce((s, n) => s + n, 0);
  const thisWeek = athlete.mileageTrend[athlete.mileageTrend.length - 1] ?? 0;
  const prevWeek = athlete.mileageTrend[athlete.mileageTrend.length - 2] ?? 0;
  const weekDelta = thisWeek - prevWeek;

  return (
    <Link
      href={`/coach-portal/athletes/${athlete.athleteId}`}
      className="block transition-transform hover:-translate-y-0.5"
    >
      <Card className="p-4 h-full hover:border-[var(--color-coral)] transition-colors">
        {/* Header */}
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <div className="font-medium text-sm truncate text-[var(--color-text-primary)]">
              {athlete.displayName}
            </div>
            <div className="text-xs text-[var(--color-text-secondary)] truncate">
              {athlete.planName} · Week {athlete.weeksIn} of {athlete.totalWeeks}
            </div>
          </div>
          <span
            className={`shrink-0 px-2 py-0.5 rounded-full text-[10px] font-medium ${pace.bg} ${pace.fg}`}
          >
            {pace.label}
          </span>
        </div>

        {/* Mileage sparkline */}
        <div className="mt-4">
          <div className="flex items-end justify-between gap-1 h-12">
            {athlete.mileageTrend.map((miles, i) => {
              const max = Math.max(1, ...athlete.mileageTrend);
              const heightPct = Math.max(8, (miles / max) * 100);
              const isCurrent = i === athlete.mileageTrend.length - 1;
              return (
                <div
                  key={i}
                  className={`flex-1 rounded-sm ${
                    isCurrent ? "bg-coral" : "bg-bg-calendar"
                  }`}
                  style={{ height: `${heightPct}%` }}
                  title={`${miles.toFixed(1)} mi`}
                />
              );
            })}
          </div>
          <div className="mt-1 flex items-baseline justify-between text-xs">
            <span className="text-[var(--color-text-secondary)]">
              {thisWeek.toFixed(1)} mi this week
            </span>
            {prevWeek > 0 && (
              <span
                className={
                  weekDelta >= 0 ? "text-text-secondary" : "text-warning"
                }
              >
                {weekDelta >= 0 ? "+" : ""}
                {weekDelta.toFixed(1)}
              </span>
            )}
          </div>
        </div>

        {/* Wellness flags */}
        <div className="mt-3 pt-3 border-t border-[var(--color-divider)]">
          {athlete.wellnessFlags.length === 0 ? (
            <div className="flex items-center gap-1.5 text-xs text-text-tertiary">
              <Check size={13} strokeWidth={2} aria-hidden />
              <span>No flags</span>
            </div>
          ) : (
            <div className="flex items-center gap-2 flex-wrap">
              {athlete.wellnessFlags.map((flag) => {
                const meta = WELLNESS_META[flag];
                // Injury risk gets coral — the alert color, and the
                // strongest "look at this athlete" signal. Everything
                // else is the amber warning tone.
                const tone =
                  flag === "injury_risk"
                    ? "bg-coral/12 text-coral-dark"
                    : "bg-warning/12 text-warning";
                return (
                  <span
                    key={flag}
                    className={`text-[11px] px-2 py-0.5 rounded-full ${tone}`}
                  >
                    {meta.label}
                  </span>
                );
              })}
            </div>
          )}
        </div>

        {/* Footer hint */}
        <div className="mt-3 text-[10px] text-[var(--color-text-tertiary)]">
          Last 6 weeks · {total.toFixed(0)} mi total
        </div>
      </Card>
    </Link>
  );
}
