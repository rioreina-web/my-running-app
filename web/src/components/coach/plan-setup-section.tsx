"use client";

import { useState } from "react";
import { PACE_ZONES, PACE_ZONE_COLORS, paceShort, type ZoneMiles } from "./workout-helpers";

/**
 * Plan setup — the plan-level skeleton for adaptive plans.
 *
 * Three clusters, one idea: the coach says ONCE how a week is shaped
 * ("Tue speed, Thu medium, Sat long, Mon rest, ramp 40→55"), and the
 * per-week grids only need the actual workout content.
 *
 *   1. Weekly skeleton — day-role chips (quality / long run / rest)
 *      → plan_templates.day_structure
 *   2. Mileage ramp — per-week min/max with fill helpers
 *      → weeks[i].targetMilesMin/Max + plan_templates.weekly_mileage_targets
 *   3. Shape flags — strides before quality, recovery after long, phases
 *      → plan_templates.auto_strides_on_pre_quality / recovery_after_long_run
 *      → phase_config.phases via per-week phase tags
 *
 * Spec: outputs/adaptive-coach-plan-builder-spec-2026-07-03.md §R1–R3.
 * Materializer counterpart: supabase/functions/subscribe-to-plan
 * (buildPlanStructure / buildWeekTargets).
 */

export interface DayStructureEntry {
  dayOfWeek: number; // 0=Mon..6=Sun
  role: "rest" | "easy" | "speed" | "moderate" | "long_run" | "recovery" | "strides";
}

export interface WeekRange {
  weekNumber: number;
  targetMilesMin?: number;
  targetMilesMax?: number;
}

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

// Click cycle for a day chip. "unset" = day is materializer-filled easy.
const ROLE_CYCLE = ["unset", "speed", "long_run", "rest"] as const;
type ChipRole = (typeof ROLE_CYCLE)[number];

const ROLE_LABELS: Record<ChipRole, string> = {
  unset: "easy fill",
  speed: "quality",
  long_run: "long run",
  rest: "rest",
};

const PHASES = ["base", "build", "specific", "down", "taper"] as const;
export type Phase = (typeof PHASES)[number];

export function PlanSetupSection({
  dayStructure,
  onDayStructureChange,
  weeks,
  onBulkRange,
  autoStrides,
  onAutoStridesChange,
  recoveryAfterLong,
  onRecoveryAfterLongChange,
  weekPhases,
  onWeekPhasesChange,
  zoneMilesByWeek,
  selectedWeekNumber,
  onSelectWeek,
}: {
  dayStructure: DayStructureEntry[];
  onDayStructureChange: (next: DayStructureEntry[]) => void;
  weeks: WeekRange[];
  onBulkRange: (ranges: Array<{ weekNumber: number; min: number; max: number }>) => void;
  autoStrides: boolean;
  onAutoStridesChange: (v: boolean) => void;
  recoveryAfterLong: boolean;
  onRecoveryAfterLongChange: (v: boolean) => void;
  weekPhases: Record<number, Phase>;
  onWeekPhasesChange: (next: Record<number, Phase>) => void;
  // Placed quality miles per zone, keyed by week number. Drives the
  // pace-colored stacked ramp. Absent = no workouts placed yet (bars show
  // pure easy-fill from the target ramp).
  zoneMilesByWeek?: Record<number, ZoneMiles>;
  // The currently-selected week (parent-owned). A bar renders with an
  // outline when it matches; clicking a bar calls onSelectWeek.
  selectedWeekNumber?: number;
  onSelectWeek?: (weekNumber: number) => void;
}) {
  const [open, setOpen] = useState(false);
  const [rampStart, setRampStart] = useState<number | "">("");
  const [rampEnd, setRampEnd] = useState<number | "">("");
  const [rampBand, setRampBand] = useState<number>(10); // range width in miles

  const roleFor = (dow: number): ChipRole => {
    const entry = dayStructure.find((d) => d.dayOfWeek === dow);
    if (!entry) return "unset";
    if (entry.role === "speed" || entry.role === "moderate") return "speed";
    if (entry.role === "long_run") return "long_run";
    if (entry.role === "rest") return "rest";
    return "unset";
  };

  const cycleDay = (dow: number) => {
    const current = roleFor(dow);
    const next = ROLE_CYCLE[(ROLE_CYCLE.indexOf(current) + 1) % ROLE_CYCLE.length];
    const without = dayStructure.filter((d) => d.dayOfWeek !== dow);
    onDayStructureChange(
      next === "unset" ? without : [...without, { dayOfWeek: dow, role: next }]
    );
  };

  const summary = (() => {
    const q = dayStructure.filter((d) => d.role === "speed" || d.role === "moderate").length;
    const lr = dayStructure.find((d) => d.role === "long_run");
    const rest = dayStructure.filter((d) => d.role === "rest").length;
    const parts: string[] = [];
    if (q > 0) parts.push(`${q} quality`);
    if (lr) parts.push(`long ${DAYS[lr.dayOfWeek]}`);
    if (rest > 0) parts.push(`${rest} rest`);
    return parts.length > 0 ? parts.join(" · ") : "not set";
  })();

  // ── Ramp helpers — every helper writes whole miles ──────────────────

  const applyLinearRamp = () => {
    if (rampStart === "" || rampEnd === "" || weeks.length < 2) return;
    const n = weeks.length;
    const ranges = weeks.map((w, i) => {
      const mid = rampStart + ((rampEnd - rampStart) * i) / (n - 1);
      const min = Math.round(mid - rampBand / 2);
      const max = Math.round(mid + rampBand / 2);
      return { weekNumber: w.weekNumber, min: Math.max(0, min), max };
    });
    onBulkRange(ranges);
  };

  const applyDownWeeks = () => {
    // Every 4th week is a cutback: scaled off the PRIOR week (0.78 / 0.82),
    // not its own value, and tagged `down` so the ramp warn-exemption and the
    // materializer both recognize it. Mirrors the prototype's renderRamp.
    const ranges = weeks
      .map((w, i) => ({ w, i }))
      .filter(({ i }) => i > 0 && (i + 1) % 4 === 0)
      .map(({ w, i }) => {
        const prev = weeks[i - 1];
        return {
          weekNumber: w.weekNumber,
          min: Math.round((prev.targetMilesMin ?? 0) * 0.78),
          max: Math.round((prev.targetMilesMax ?? 0) * 0.82),
        };
      })
      .filter((r) => r.max > 0);
    onBulkRange(ranges);
    const nextPhases = { ...weekPhases };
    for (const r of ranges) nextPhases[r.weekNumber] = "down";
    onWeekPhasesChange(nextPhases);
  };

  const applyTaper = () => {
    if (weeks.length < 3) return;
    // Taper off the PLAN PEAK (max mid across all weeks), not each week's own
    // range — so an unfilled taper week still gets a real fraction of peak.
    // Penultimate = 0.70–0.78 × peak, final = 0.50–0.58 × peak; both `taper`.
    const peak = Math.max(
      ...weeks.map((w) => ((w.targetMilesMin ?? 0) + (w.targetMilesMax ?? 0)) / 2),
      1
    );
    const factorPairs = [
      { min: 0.7, max: 0.78 }, // penultimate week
      { min: 0.5, max: 0.58 }, // final week
    ];
    const ranges = factorPairs.map((f, i) => {
      const w = weeks[weeks.length - 2 + i];
      return {
        weekNumber: w.weekNumber,
        min: Math.round(peak * f.min),
        max: Math.round(peak * f.max),
      };
    });
    onBulkRange(ranges);
    const nextPhases = { ...weekPhases };
    for (const r of ranges) nextPhases[r.weekNumber] = "taper";
    onWeekPhasesChange(nextPhases);
  };

  const setWeekRange = (weekNumber: number, field: "min" | "max", value: number) => {
    const w = weeks.find((x) => x.weekNumber === weekNumber);
    if (!w) return;
    onBulkRange([
      {
        weekNumber,
        min: field === "min" ? value : w.targetMilesMin ?? 0,
        max: field === "max" ? value : w.targetMilesMax ?? 0,
      },
    ]);
  };

  const setPhase = (weekNumber: number, phase: Phase | "") => {
    const next = { ...weekPhases };
    if (phase === "") delete next[weekNumber];
    else next[weekNumber] = phase;
    onWeekPhasesChange(next);
  };

  // ── Ramp chart derivations ──────────────────────────────────────────
  const weekMid = (w: WeekRange) =>
    ((w.targetMilesMin ?? 0) + (w.targetMilesMax ?? 0)) / 2;
  // Tallest week sets the bar-height scale; floor at 1 to avoid /0.
  const rampMaxMid = Math.max(...weeks.map(weekMid), 1);

  // Coral dot when a week's floor jumps >10% over the prior week — the coach's
  // own ramp rule flagging itself. Intentional cutbacks never flag: the down /
  // taper week itself (a drop), AND the week rebounding from a down week back
  // to normal load — that rebound is expected, not an over-ramp.
  const rampWarn = (i: number): boolean => {
    if (i === 0) return false;
    const curPhase = weekPhases[weeks[i].weekNumber];
    const prevPhase = weekPhases[weeks[i - 1].weekNumber];
    if (curPhase === "down" || curPhase === "taper") return false;
    if (prevPhase === "down") return false;
    const prevMin = weeks[i - 1].targetMilesMin ?? 0;
    const curMin = weeks[i].targetMilesMin ?? 0;
    return curMin > prevMin * 1.1 + 0.01;
  };

  return (
    <div className="border border-divider rounded-lg bg-bg-base">
      {/* Header row — collapsed summary reads like a sentence. */}
      <button
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-between px-4 py-2.5 text-left"
      >
        <div className="flex items-baseline gap-3">
          <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
            Plan setup
          </span>
          <span className="text-xs text-text-secondary">{summary}</span>
        </div>
        <span className="text-xs text-text-tertiary">{open ? "Hide" : "Edit"}</span>
      </button>

      {open && (
        <div className="px-4 pb-4 space-y-5 border-t border-divider pt-4">
          {/* 1 — Weekly skeleton */}
          <div>
            <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary mb-2">
              Weekly skeleton
            </p>
            <div className="flex gap-1.5 flex-wrap">
              {DAYS.map((label, dow) => {
                const role = roleFor(dow);
                const styles: Record<ChipRole, string> = {
                  unset: "border-divider text-text-tertiary hover:text-text-secondary",
                  speed: "border-coral text-coral",
                  long_run: "border-[var(--color-mood-positive)] text-[var(--color-mood-positive)]",
                  rest: "border-text-tertiary text-text-secondary bg-bg-elevated",
                };
                return (
                  <button
                    key={dow}
                    onClick={() => cycleDay(dow)}
                    className={`flex flex-col items-center px-2.5 py-1.5 rounded-lg border transition-colors ${styles[role]}`}
                    title="Click to cycle: easy fill → quality → long run → rest"
                  >
                    <span className="text-xs font-medium">{label}</span>
                    <span className="font-mono text-[9px] uppercase tracking-wider opacity-80">
                      {ROLE_LABELS[role]}
                    </span>
                  </button>
                );
              })}
            </div>
            <p className="text-[11px] text-text-tertiary mt-1.5">
              Quality and long-run workouts land on these days for every athlete
              unless the athlete picks their own days at signup. Unmarked days
              auto-fill with easy volume.
            </p>
          </div>

          {/* 2 — Mileage ramp */}
          <div>
            <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary mb-2">
              Mileage ramp
            </p>

            {/* Pace-colored stacked ramp. Each bar is a week's mid-mileage;
                pale-sky base is easy fill, deeper blues are placed quality
                miles by zone. Coral dot flags a >10% week-over-week jump.
                Ported from prototypes/adaptive-plan-builder.html. */}
            {weeks.length > 0 && (
              <div className="flex items-end gap-2.5 h-24 mb-3 mt-1 px-0.5">
                {weeks.map((w, i) => {
                  const mid = weekMid(w);
                  const h = Math.max(6, Math.round((mid / rampMaxMid) * 78));
                  const zm: ZoneMiles = { ...(zoneMilesByWeek?.[w.weekNumber] ?? {}) };
                  const placed = PACE_ZONES.reduce(
                    (sum, z) => sum + (zm[z.value] ?? 0),
                    0,
                  );
                  // Everything not placed is easy fill — it joins the Easy
                  // segment at the base of the bar.
                  zm.easy = (zm.easy ?? 0) + Math.max(0, mid - placed);
                  const total = Math.max(mid, placed) || 1;
                  const warn = rampWarn(i);
                  const selected = selectedWeekNumber === w.weekNumber;
                  return (
                    <button
                      key={w.weekNumber}
                      type="button"
                      onClick={() => onSelectWeek?.(w.weekNumber)}
                      className="flex-1 flex flex-col justify-end items-center gap-1.5 h-full cursor-pointer"
                      title={`W${w.weekNumber} · ${w.targetMilesMin ?? 0}–${w.targetMilesMax ?? 0} mi`}
                    >
                      {/* Fixed-height flag slot keeps bar baselines aligned
                          whether or not the >10% dot shows. */}
                      <span
                        className="w-1.5 h-1.5 rounded-full shrink-0"
                        style={{ background: warn ? "var(--color-coral)" : "transparent" }}
                        title={warn ? "Jump over 10% — your ramp rule flags this" : undefined}
                      />
                      <div
                        className={`w-full rounded-t-[4px] overflow-hidden flex flex-col ${
                          selected ? "outline outline-[1.5px] outline-text-primary outline-offset-2" : ""
                        }`}
                        style={{ height: `${h}px` }}
                      >
                        {/* Stack fastest-on-top: reverse the slow→fast zone
                            list so Easy sits at the base. */}
                        {[...PACE_ZONES].reverse().map((z) => {
                          const mi = zm[z.value];
                          if (!mi || mi <= 0) return null;
                          return (
                            <div
                              key={z.value}
                              style={{
                                height: `${Math.max(2, (mi / total) * h)}px`,
                                background: PACE_ZONE_COLORS[z.value],
                              }}
                              title={`${paceShort(z.value)} · ${mi.toFixed(1)} mi`}
                            />
                          );
                        })}
                      </div>
                      <span
                        className={`font-mono text-[9px] tracking-wider ${
                          selected ? "text-text-primary font-semibold" : "text-text-tertiary"
                        }`}
                      >
                        W{w.weekNumber}
                      </span>
                    </button>
                  );
                })}
              </div>
            )}

            <div className="flex items-center gap-2 flex-wrap mb-3">
              <input
                type="number"
                min={0}
                placeholder="start"
                value={rampStart}
                onChange={(e) => setRampStart(e.target.value === "" ? "" : parseInt(e.target.value) || 0)}
                className="w-14 px-1 py-0.5 text-xs text-center border-b border-divider bg-transparent focus:outline-none focus:border-coral tabular-nums"
              />
              <span className="text-xs text-text-tertiary">→</span>
              <input
                type="number"
                min={0}
                placeholder="end"
                value={rampEnd}
                onChange={(e) => setRampEnd(e.target.value === "" ? "" : parseInt(e.target.value) || 0)}
                className="w-14 px-1 py-0.5 text-xs text-center border-b border-divider bg-transparent focus:outline-none focus:border-coral tabular-nums"
              />
              <span className="text-xs text-text-tertiary">mpw, range width</span>
              <input
                type="number"
                min={2}
                value={rampBand}
                onChange={(e) => setRampBand(parseInt(e.target.value) || 10)}
                className="w-11 px-1 py-0.5 text-xs text-center border-b border-divider bg-transparent focus:outline-none focus:border-coral tabular-nums"
              />
              <button
                onClick={applyLinearRamp}
                disabled={rampStart === "" || rampEnd === ""}
                className="px-2.5 py-1 text-xs border border-divider rounded-md text-text-secondary hover:text-text-primary hover:border-text-tertiary transition-colors disabled:opacity-40"
              >
                Apply ramp
              </button>
              <button
                onClick={applyDownWeeks}
                className="px-2.5 py-1 text-xs border border-divider rounded-md text-text-secondary hover:text-text-primary hover:border-text-tertiary transition-colors"
              >
                Down week every 4th (−20%)
              </button>
              <button
                onClick={applyTaper}
                className="px-2.5 py-1 text-xs border border-divider rounded-md text-text-secondary hover:text-text-primary hover:border-text-tertiary transition-colors"
              >
                Taper last 2 weeks
              </button>
            </div>

            {/* Per-week grid: W# / phase / min–max. Scrolls horizontally. */}
            <div className="overflow-x-auto">
              <div className="flex gap-1 min-w-max pb-1">
                {weeks.map((w) => (
                  <div
                    key={w.weekNumber}
                    className="flex flex-col items-center gap-1 px-1.5 py-1.5 rounded-md bg-bg-elevated border border-divider"
                  >
                    <span className="font-mono text-[9px] uppercase tracking-wider text-text-tertiary">
                      W{w.weekNumber}
                    </span>
                    <input
                      type="number"
                      min={0}
                      value={w.targetMilesMin || ""}
                      placeholder="–"
                      onChange={(e) => setWeekRange(w.weekNumber, "min", parseInt(e.target.value) || 0)}
                      className="w-9 text-center text-xs bg-transparent border-b border-divider focus:outline-none focus:border-coral tabular-nums"
                    />
                    <input
                      type="number"
                      min={0}
                      value={w.targetMilesMax || ""}
                      placeholder="–"
                      onChange={(e) => setWeekRange(w.weekNumber, "max", parseInt(e.target.value) || 0)}
                      className="w-9 text-center text-xs bg-transparent border-b border-divider focus:outline-none focus:border-coral tabular-nums"
                    />
                    <select
                      value={weekPhases[w.weekNumber] ?? ""}
                      onChange={(e) => setPhase(w.weekNumber, e.target.value as Phase | "")}
                      className="w-full text-[9px] font-mono uppercase tracking-wider bg-transparent text-text-tertiary focus:outline-none cursor-pointer"
                    >
                      <option value="">—</option>
                      {PHASES.map((p) => (
                        <option key={p} value={p}>
                          {p}
                        </option>
                      ))}
                    </select>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* 3 — Shape flags */}
          <div className="flex items-center gap-5 flex-wrap">
            <label className="flex items-center gap-2 text-xs text-text-secondary cursor-pointer">
              <input
                type="checkbox"
                checked={autoStrides}
                onChange={(e) => onAutoStridesChange(e.target.checked)}
                className="accent-[var(--color-coral,#E8764A)]"
              />
              Strides on the easy day before quality
            </label>
            <label className="flex items-center gap-2 text-xs text-text-secondary cursor-pointer">
              <input
                type="checkbox"
                checked={recoveryAfterLong}
                onChange={(e) => onRecoveryAfterLongChange(e.target.checked)}
                className="accent-[var(--color-coral,#E8764A)]"
              />
              Recovery run the day after the long run
            </label>
          </div>
        </div>
      )}
    </div>
  );
}

/** Convert per-week phase tags into the phase_config.phases range shape:
 * [{ name, startWeek, endWeek }], merging consecutive same-phase weeks. */
export function buildPhaseRanges(
  weekPhases: Record<number, Phase>,
  totalWeeks: number
): Array<{ name: Phase; startWeek: number; endWeek: number }> {
  const out: Array<{ name: Phase; startWeek: number; endWeek: number }> = [];
  let current: { name: Phase; startWeek: number; endWeek: number } | null = null;
  for (let wk = 1; wk <= totalWeeks; wk++) {
    const phase = weekPhases[wk];
    if (!phase) {
      current = null;
      continue;
    }
    if (current && current.name === phase && current.endWeek === wk - 1) {
      current.endWeek = wk;
    } else {
      current = { name: phase, startWeek: wk, endWeek: wk };
      out.push(current);
    }
  }
  return out;
}

/** Inverse of buildPhaseRanges — hydrate the per-week tags from a stored
 * phase_config.phases array. */
export function phasesToWeekMap(
  phases: unknown
): Record<number, Phase> {
  const out: Record<number, Phase> = {};
  if (!Array.isArray(phases)) return out;
  for (const p of phases) {
    const name = p?.name;
    if (!PHASES.includes(name)) continue;
    const start = typeof p?.startWeek === "number" ? p.startWeek : null;
    const end = typeof p?.endWeek === "number" ? p.endWeek : null;
    if (start === null || end === null) continue;
    for (let wk = start; wk <= end; wk++) out[wk] = name;
  }
  return out;
}
