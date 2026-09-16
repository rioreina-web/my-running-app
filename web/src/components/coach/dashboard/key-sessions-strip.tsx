"use client";

import type { KeySessionMark } from "@/lib/coach-dashboard/types";
import { useOpenWorkout } from "./drawer-context";
import { isMiss } from "./editorial";

/**
 * KeySessionsStrip — §02. Every keyed session in the window against the target
 * it was set at, oldest first, so the strip reads left to right the way the
 * block was run. A turn is visible without reading a word.
 *
 * The delta is HEAT-ADJUSTED (workout_reconciliations.adjusted_pace_delta_seconds):
 * an athlete 10 s/mi slow in 80°F dew has not slipped, and the raw delta would
 * say they had. A session with no reconciliation shows "not scored" rather
 * than a zero — the two are different answers.
 */
export function KeySessionsStrip({
  sessions,
  read,
}: {
  sessions: KeySessionMark[];
  read?: string;
}) {
  if (!sessions.length) {
    return (
      <p className="drip-prose py-5 text-[14px] text-text-secondary">
        No keyed sessions in this window. The strip fills in as the plan marks
        them, or as the athlete does.
      </p>
    );
  }

  return (
    <>
      <div className="grid grid-cols-2 border-b border-divider sm:grid-cols-3 lg:grid-cols-6">
        {sessions.map((k) => (
          <button
            key={k.dayId}
            type="button"
            onClick={() => undefined}
            className={`border-r border-t-2 border-divider py-4 pr-3.5 text-left last:border-r-0 ${
              k.latest ? "border-t-pace-hmp bg-bg-elevated" : "border-t-transparent"
            }`}
          >
            <KeyCell k={k} />
          </button>
        ))}
      </div>
      {read ? <p className="drip-prose mt-4 max-w-[68ch] text-[15px]">{read}</p> : null}
    </>
  );
}

function KeyCell({ k }: { k: KeySessionMark }) {
  const open = useOpenWorkout();
  const delta = k.deltaSec;
  const hasVerdict = delta !== null || Boolean(k.deltaLabel);

  // A real reconciliation exists — show its verdict, colored (a miss reads
  // slow or short; onTarget alone is not the color, see isMiss).
  // No reconciliation but the athlete has a calibrated pace table — show
  // where the session landed against their OWN zones. This is a placement,
  // never a verdict: with no prescription there is nothing to miss, so it
  // never colors red.
  const label = hasVerdict
    ? (k.deltaLabel ??
      (delta === 0 ? "On pace" : `${delta! > 0 ? "+" : "−"}${Math.abs(delta!)} s`))
    : (k.zoneLabel ?? "Not scored");
  const missed = hasVerdict && (delta === null ? isMiss(k.deltaLabel) : delta > 5);
  const tone = missed ? "text-coral-dark" : hasVerdict ? "text-text-primary" : "text-text-tertiary";
  const caption = hasVerdict
    ? k.compare
    : k.zoneLabel && k.zoneDeltaSec != null
      ? `${k.zoneDeltaSec > 0 ? "+" : "−"}${Math.abs(k.zoneDeltaSec)} s/mi vs own ${k.zoneLabel}`
      : undefined;

  return (
    <span
      onClick={() => open(k.dayId)}
      className="block cursor-pointer"
      role="presentation"
    >
      <span className="drip-eyebrow block text-text-tertiary">
        {k.dateLabel}
        {k.latest ? " · Last" : ""}
      </span>
      <span className="mt-2.5 block min-h-[34px] font-body text-[12.5px] leading-snug text-text-primary">
        {k.title}
      </span>
      <span className={`drip-stat mt-3 block text-[19px] ${tone}`}>{label}</span>
      {caption ? (
        <span className="drip-eyebrow mt-1.5 block text-[9px] text-text-tertiary">{caption}</span>
      ) : null}
    </span>
  );
}
