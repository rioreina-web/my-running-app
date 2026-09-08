"use client";

import type { LatestSession, Mood, WorkoutDetail } from "@/lib/coach-dashboard/types";
import { useOpenWorkout } from "./drawer-context";
import { Rich } from "./rich-text";

const MOOD_LABEL: Record<Mood, string> = {
  energized: "Energized",
  positive: "Positive",
  neutral: "Neutral",
  tired: "Tired",
  struggling: "Struggling",
  injured: "Injured",
};

/**
 * WorkoutSheet — §01, the workout.
 *
 * Replaces LatestBand's summary strip with the full sheet the mockup
 * specifies: the big three, the session as written (a machine reading, set
 * roman against the athlete's own words, set italic, further down), splits as
 * numbers (a pace bar has to be inverted to read correctly, and inverted bars
 * lie), conditions, and the athlete's log notes verbatim.
 *
 * `detail` is the day's full WorkoutDetail (DashboardData.latestDetail) — the
 * sheet reads it directly rather than through LatestSession's lossier
 * `facts`/`splits` mapping, which several v2 surfaces still consume.
 */
export function WorkoutSheet({
  latest,
  detail,
}: {
  latest: LatestSession;
  detail?: WorkoutDetail;
}) {
  const open = useOpenWorkout();
  const [distKpi, timeKpi, paceKpi] = detail?.kpis ?? [];
  const bigThree = [distKpi, timeKpi, paceKpi].filter((k): k is NonNullable<typeof distKpi> => Boolean(k));
  const cond = detail?.conditions;

  return (
    <div className="border-b border-divider py-6">
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <span className="drip-eyebrow">
          {latest.whenLabel}
          {cond?.startTime ? ` · ${cond.startTime}` : ""}
        </span>
        <span
          className="font-mono text-[10.5px] font-bold uppercase tracking-[0.1em] text-text-tertiary"
          style={latest.key ? { color: "var(--session)" } : undefined}
        >
          {latest.key ? "Keyed session · " : ""}
          {MOOD_LABEL[latest.mood] ?? latest.mood}
        </span>
      </div>

      <button
        type="button"
        onClick={() => open(latest.dayId)}
        className="drip-title mt-2.5 block text-left text-[36px] leading-none hover:underline"
      >
        {latest.title}
      </button>

      {/* The big three — Dist / Time / Pace. */}
      {bigThree.length ? (
        <div className="mt-5 grid grid-cols-3 border-t-2 border-text-primary border-b border-divider">
          {bigThree.map((k) => (
            <div key={k.k} className="min-w-0 border-r border-divider py-4 pr-5 last:border-r-0">
              <span className="drip-eyebrow block">{k.k}</span>
              <span className="drip-stat mt-2 block whitespace-nowrap text-[34px] leading-none tracking-[-0.03em]">
                {k.v}
              </span>
              {k.sub ? (
                <span className="drip-eyebrow mt-1.5 block whitespace-normal text-[9px] text-text-tertiary">
                  <Rich text={k.sub} strongClassName="font-semibold text-text-secondary" />
                </span>
              ) : null}
            </div>
          ))}
        </div>
      ) : null}

      {/* The session as written — training_logs.workout_notes, a machine
          reading, set roman (never italic — that posture is the athlete's). */}
      {detail?.sessionAsWritten ? (
        <div className="mt-5 border-l-2 pl-4" style={{ borderColor: "var(--session)" }}>
          <span className="drip-eyebrow block" style={{ color: "var(--session)" }}>
            The session
          </span>
          <p className="drip-ai mt-2 text-[12px] leading-relaxed">{detail.sessionAsWritten}</p>
          {detail.effortLine ? (
            <span className="drip-eyebrow mt-2 block text-text-tertiary">{detail.effortLine}</span>
          ) : null}
        </div>
      ) : null}

      {/* Splits — pace above, avg HR below, numbers only. A pace bar has to be
          inverted to read correctly, and inverted bars lie. */}
      {detail?.splits?.length ? (
        <>
          <div className="mt-5 grid grid-cols-4 gap-x-3 border-t border-divider md:grid-cols-7">
            {detail.splits.map((sp, i) => (
              <div key={`${sp.name}-${i}`} className="min-w-0 pt-3">
                <span
                  className={`drip-stat block text-[14px] ${
                    sp.onTarget ? "text-text-primary" : "text-text-secondary"
                  }`}
                >
                  {sp.pace ?? "—"}
                </span>
                <span className={`mt-1.5 block h-[2px] ${sp.onTarget ? "bg-text-primary" : "bg-divider"}`} />
                <span className="drip-stat mt-1.5 block text-[10.5px] text-text-tertiary">
                  {sp.hrAvg != null ? sp.hrAvg : ""}
                </span>
                <span className="drip-eyebrow mt-1 block truncate text-[9px] text-text-tertiary">{sp.name}</span>
              </div>
            ))}
          </div>
          <span className="drip-eyebrow mt-3 block text-text-tertiary">{detail.splitLabel}</span>
        </>
      ) : null}

      {/* Conditions — the dew point is the one that can go red. */}
      {cond ? (
        <div className="mt-6 grid grid-cols-2 border-t border-b border-divider sm:grid-cols-3 md:grid-cols-5">
          <ConditionCell label="Temp" value={cond.tempF} unit="°F" />
          <ConditionCell label="Dew point" value={cond.dewPointF} unit="°F" hot={cond.dewHot} />
          {cond.heatCostPct != null ? <ConditionCell label="Heat cost" value={cond.heatCostPct} unit="%" /> : null}
          {cond.humidityPct != null ? <ConditionCell label="Humidity" value={cond.humidityPct} unit="%" /> : null}
          <ConditionCell label="Avg HR" value={cond.hrAvg} unit="bpm" />
        </div>
      ) : null}

      {/* The log notes — the athlete's own words, verbatim. A neutral rule:
          this block is set apart, not mood (the left-rule rule, CLAUDE.md). */}
      {latest.note ? (
        <div className="mt-6 border-l-2 border-divider pl-4">
          <span className="drip-eyebrow mb-2 block text-text-tertiary">Training log · in their words</span>
          <p className="drip-voice text-[12.5px] leading-relaxed">&ldquo;{latest.note}&rdquo;</p>
        </div>
      ) : null}
    </div>
  );
}

function ConditionCell({
  label,
  value,
  unit,
  hot,
}: {
  label: string;
  value: number;
  unit: string;
  hot?: boolean;
}) {
  return (
    <div className="min-w-0 border-r border-divider py-3 pr-4 last:border-r-0">
      <span className="drip-eyebrow block">{label}</span>
      <span className={`drip-stat mt-1.5 block whitespace-nowrap text-[18px] ${hot ? "text-coral-dark" : ""}`}>
        {value}
        <span className="ml-0.5 text-[10px] font-medium text-text-tertiary">{unit}</span>
      </span>
    </div>
  );
}
