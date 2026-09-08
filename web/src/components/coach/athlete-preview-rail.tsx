"use client";

import { useMemo, useState } from "react";
import {
  derivePaceTableFromGoal,
  paceRangeLabel,
  describeWorkoutLine,
  workoutZoneLabel,
  estimatedWorkoutMiles,
  type AthletePaceTable,
  type WorkoutStep,
} from "./workout-helpers";
import { EmptyState } from "@/components/ui/empty-state";

/**
 * Athlete preview rail — the design's core promise made visible: write the
 * block once, every athlete reads it in their own paces, on their own days.
 *
 * Read-only. Picks one of the coach's real athletes and resolves the selected
 * week for them:
 *   - Paces from THEIR anchor (real race > goal), via the same
 *     `derivePaceTableFromGoal` the subscribe-to-plan materializer uses — so
 *     the preview and the scheduled_workouts an athlete gets agree.
 *   - Coach precedence honored: when the coach has set a plan-level pace anchor,
 *     it wins for everyone (absolute targets read the same on every card), so
 *     every athlete resolves against the coach table, not their own.
 *   - Quality/long days remapped onto the athlete's preferred days; AM/PM
 *     doubles stay pinned together on their day.
 *
 * No writes: this rail proposes nothing and mutates nothing. It's a window
 * into what the athlete will see, nothing more.
 *
 * Ports the preview column of prototypes/adaptive-plan-builder.html
 * (`athleteSessionMap`, `sessionBodyHTML`, `renderPreview`).
 */

export interface PreviewAthlete {
  id: string;
  name: string;
  /** Human anchor label, e.g. "3:28 marathon" or "goal · 3:16 marathon". */
  anchorLabel: string;
  /** A confirmed race (real fitness) vs. a goal time (aspiration). */
  anchorIsReal: boolean;
  /** Seconds-per-mile for the anchor race. null = no anchor on file. */
  anchorSecPerMile: number | null;
  /** Distance in `derivePaceTableFromGoal` input form ('marathon' |
   *  'half_marathon' | '10k' | '5k' | 'mile'). null when no anchor. */
  anchorDistance: string | null;
  /** Days the athlete wants quality (0=Mon..6=Sun). null = coach's days. */
  preferredQualityDows: number[] | null;
  /** Day the long run lands on. null = coach's day. */
  longRunDow: number | null;
  /** Athlete-chosen rest days. */
  restDows: number[];
}

/** A placed session from the selected plan week, flattened for the rail. */
export interface PreviewWorkout {
  dayOfWeek: number; // 0=Mon..6=Sun
  session: "am" | "pm";
  workoutType?: string;
  name?: string;
  notes?: string;
  steps: WorkoutStep[];
}

export interface PreviewWeek {
  weekNumber: number;
  phase?: string;
  targetMilesMin?: number;
  targetMilesMax?: number;
  workouts: PreviewWorkout[];
}

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

// Quality workout types that remap onto the athlete's preferred quality days.
// Long runs remap separately (long_run_dow); easy/recovery/strides/rest stay
// put — they fill whatever days the quality/long work leaves open.
const QUALITY_TYPES = new Set([
  "tempo",
  "intervals",
  "threshold",
  "progression",
  "fartlek",
  "race",
]);

/** The athlete's resolved pace table, honoring coach-anchor precedence.
 *  Returns null only when neither the coach nor the athlete has an anchor. */
function resolvePaceTable(
  a: PreviewAthlete,
  coachTable: AthletePaceTable | null,
): AthletePaceTable | null {
  // Coach's plan anchor wins for everyone — the same human decision the
  // materializer applies in resolveAthletePaces step 1.
  if (coachTable) return coachTable;
  if (a.anchorSecPerMile && a.anchorSecPerMile > 0 && a.anchorDistance) {
    return derivePaceTableFromGoal(a.anchorSecPerMile, a.anchorDistance);
  }
  return null;
}

/** originalDow → athlete's preferred dow. Only single-day, un-doubled quality
 *  and long roles move; doubled days stay put so AM and PM never split. */
function buildDayRemap(
  workouts: PreviewWorkout[],
  a: PreviewAthlete,
): Map<number, number> {
  const map = new Map<number, number>();

  // Days that host a PM double never move — the double stays intact.
  const doubledDays = new Set(
    workouts.filter((w) => w.session === "pm").map((w) => w.dayOfWeek),
  );

  // Quality AM days, ascending, mapped positionally onto the athlete's
  // preferred quality days (1st quality → 1st preferred day, etc.).
  const qualityDays = Array.from(
    new Set(
      workouts
        .filter(
          (w) =>
            w.session === "am" &&
            w.workoutType &&
            QUALITY_TYPES.has(w.workoutType),
        )
        .map((w) => w.dayOfWeek),
    ),
  ).sort((x, y) => x - y);
  const prefQ = (a.preferredQualityDows ?? []).slice().sort((x, y) => x - y);
  qualityDays.forEach((d, i) => {
    if (doubledDays.has(d)) return;
    const target = prefQ[i];
    if (typeof target === "number" && target !== d) map.set(d, target);
  });

  // Long run → the athlete's long-run day.
  const longDay = workouts.find(
    (w) => w.session === "am" && w.workoutType === "long_run",
  )?.dayOfWeek;
  if (
    typeof longDay === "number" &&
    typeof a.longRunDow === "number" &&
    a.longRunDow !== longDay &&
    !doubledDays.has(longDay)
  ) {
    map.set(longDay, a.longRunDow);
  }

  return map;
}

function SessionBody({
  w,
  pt,
  moved,
}: {
  w: PreviewWorkout;
  pt: AthletePaceTable;
  moved: boolean;
}) {
  const label = workoutZoneLabel(w.steps, pt) ?? w.name ?? w.workoutType ?? "session";
  const line = describeWorkoutLine(w.steps, pt);
  const miles = estimatedWorkoutMiles(w.steps, pt);
  return (
    <div>
      <div className="flex items-baseline gap-2">
        <span className="text-xs font-medium text-text-primary">{w.name ?? label}</span>
        {moved && (
          <span
            className="font-mono text-[9px] tracking-wider text-text-tertiary"
            title={`moved to this athlete's preferred day`}
          >
            ↷ moved
          </span>
        )}
      </div>
      <div className="text-[11px] text-text-secondary tabular-nums">
        {line ? `${line} · ` : ""}
        {miles > 0 ? `${miles.toFixed(1)} mi` : ""}
      </div>
      {w.notes ? (
        <div className="text-[11px] italic text-text-tertiary mt-0.5">
          &ldquo;{w.notes}&rdquo; <span className="not-italic">— you</span>
        </div>
      ) : null}
    </div>
  );
}

export function AthletePreviewRail({
  athletes,
  week,
  coachPaceTable,
}: {
  athletes: PreviewAthlete[];
  week: PreviewWeek | undefined;
  // The coach's plan-level pace table when a plan anchor is set; null when the
  // coach left paces to each athlete's own anchor. Wins for everyone when set.
  coachPaceTable: AthletePaceTable | null;
}) {
  const [open, setOpen] = useState(false);
  const [selectedId, setSelectedId] = useState(athletes[0]?.id ?? null);

  const athlete = athletes.find((a) => a.id === selectedId) ?? athletes[0];

  const pt = useMemo(
    () => (athlete ? resolvePaceTable(athlete, coachPaceTable) : null),
    [athlete, coachPaceTable],
  );

  // Resolve the week for this athlete: remap days, group by resolved day.
  const byDay = useMemo(() => {
    const out = new Map<number, Array<{ w: PreviewWorkout; moved: boolean }>>();
    if (!week || !athlete) return out;
    const remap = buildDayRemap(week.workouts, athlete);
    for (const w of week.workouts) {
      if (!w.workoutType || w.workoutType === "rest") continue;
      const target = remap.get(w.dayOfWeek) ?? w.dayOfWeek;
      const arr = out.get(target) ?? [];
      arr.push({ w, moved: target !== w.dayOfWeek });
      out.set(target, arr);
    }
    // AM before PM within a day.
    for (const arr of out.values()) {
      arr.sort((p, q) => (p.w.session === q.w.session ? 0 : p.w.session === "am" ? -1 : 1));
    }
    return out;
  }, [week, athlete]);

  const summary = athlete
    ? `${athlete.name} · ${athlete.anchorLabel}`
    : "no athletes on your plans yet";

  return (
    <div className="border border-divider rounded-lg bg-bg-base">
      <button
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-between px-4 py-2.5 text-left"
      >
        <div className="flex items-baseline gap-3">
          <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
            As the athlete runs it
          </span>
          <span className="text-xs text-text-secondary">{summary}</span>
        </div>
        <span className="text-xs text-text-tertiary">{open ? "Hide" : "Preview"}</span>
      </button>

      {open && (
        <div className="px-4 pb-4 border-t border-divider pt-4">
          {athletes.length === 0 ? (
            <EmptyState
              variant="optional-empty"
              eyebrow="Athlete preview"
              title="No athletes are on your plans yet. Once a runner joins, you'll see this week resolved in their paces and on their preferred days."
            />
          ) : (
            <>
              {/* Athlete pills */}
              <div className="flex gap-1.5 flex-wrap mb-4">
                {athletes.map((a) => {
                  const active = a.id === (athlete?.id ?? null);
                  return (
                    <button
                      key={a.id}
                      onClick={() => setSelectedId(a.id)}
                      className={`px-2.5 py-1 text-xs rounded-full border transition-colors ${
                        active
                          ? "bg-text-primary text-white border-text-primary"
                          : "border-divider text-text-secondary hover:text-text-primary hover:border-text-tertiary"
                      }`}
                    >
                      {a.name}
                    </button>
                  );
                })}
              </div>

              {!week ? (
                <EmptyState
                  variant="optional-empty"
                  eyebrow="Athlete preview"
                  title="Select a week to see it resolved for this athlete."
                />
              ) : !pt ? (
                <EmptyState
                  variant="data-pending"
                  eyebrow="No anchor yet"
                  title={`${athlete?.name ?? "This athlete"} has no race result or goal on file, so paces can't resolve. The week's shape still applies; the numbers fill in once an anchor exists.`}
                />
              ) : (
                <>
                  {/* Week header */}
                  <div className="mb-3">
                    <p className="font-display text-lg text-text-primary leading-tight">
                      Week {week.weekNumber}
                      {week.phase ? (
                        <span className="font-mono text-[10px] uppercase tracking-wider text-text-tertiary ml-2">
                          {week.phase}
                        </span>
                      ) : null}
                    </p>
                    <p className="text-[11px] text-text-secondary tabular-nums">
                      {(week.targetMilesMin ?? 0)}–{(week.targetMilesMax ?? 0)} mi ·
                      anchored on {athlete?.anchorLabel}
                      {athlete && !athlete.anchorIsReal && !coachPaceTable ? " (goal)" : ""}
                    </p>
                  </div>

                  {/* Day-by-day resolution */}
                  <div className="space-y-1.5">
                    {DAYS.map((label, dow) => {
                      const entries = byDay.get(dow) ?? [];
                      const isRest = athlete?.restDows.includes(dow);
                      return (
                        <div
                          key={dow}
                          className="flex gap-3 py-1.5 border-b border-divider/60 last:border-b-0"
                        >
                          <span className="font-mono text-[10px] uppercase tracking-wider text-text-tertiary w-8 shrink-0 pt-0.5">
                            {label}
                          </span>
                          <div className="flex-1 min-w-0 space-y-2">
                            {entries.length > 0 ? (
                              entries.map(({ w, moved }, i) => (
                                <div key={i}>
                                  {(entries.length > 1 || w.session === "pm") && (
                                    <span className="font-mono text-[9px] uppercase tracking-wider text-text-tertiary block mb-0.5">
                                      {w.session}
                                    </span>
                                  )}
                                  <SessionBody w={w} pt={pt} moved={moved} />
                                </div>
                              ))
                            ) : isRest ? (
                              <span className="text-[11px] text-text-tertiary">rest</span>
                            ) : (
                              <span className="text-[11px] text-text-tertiary tabular-nums">
                                easy · {paceRangeLabel("easy", undefined, undefined, pt)}
                              </span>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>

                  <p className="text-[11px] text-text-tertiary italic mt-3 leading-relaxed">
                    Absolute targets read the same on every athlete&rsquo;s card;
                    adaptive paces follow {athlete?.name}&rsquo;s anchor. Easy volume
                    spreads across the open days. This preview is read-only.
                  </p>
                </>
              )}
            </>
          )}
        </div>
      )}
    </div>
  );
}
