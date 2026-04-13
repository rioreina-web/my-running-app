"use client";

import { useState } from "react";

const DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const ROLES = ["rest", "easy", "speed", "moderate", "long_run", "recovery", "strides"];
const ROLE_COLORS: Record<string, string> = {
  rest: "#9B9590",
  easy: "#4A9E6B",
  speed: "#D4592A",
  moderate: "#E8764A",
  long_run: "#2D8A4E",
  recovery: "#4A9E6B",
  strides: "#2D8A4E",
};
const ROLE_LABELS: Record<string, string> = {
  rest: "Rest",
  easy: "Easy",
  speed: "Speed",
  moderate: "Moderate",
  long_run: "Long Run",
  recovery: "Recovery",
  strides: "Strides",
};

const PHASES = ["base", "build", "specific", "taper"];
const PHASE_COLORS: Record<string, string> = {
  base: "#4A9E6B",
  build: "#E8764A",
  specific: "#D4592A",
  taper: "#9B9590",
};

export interface DayStructureEntry {
  dayOfWeek: number;
  role: string;
}

export interface PhaseConfig {
  phases: { name: string; startWeek: number; endWeek: number }[];
}

export interface WeeklyMileageTarget {
  weekNumber: number;
  targetMiles: number;
  phase: string;
}

interface AdaptivePlanConfigProps {
  durationWeeks: number;
  dayStructure: DayStructureEntry[];
  phaseConfig: PhaseConfig;
  weeklyMileage: WeeklyMileageTarget[];
  onDayStructureChange: (ds: DayStructureEntry[]) => void;
  onPhaseConfigChange: (pc: PhaseConfig) => void;
  onWeeklyMileageChange: (wm: WeeklyMileageTarget[]) => void;
}

export function AdaptivePlanConfig({
  durationWeeks,
  dayStructure,
  phaseConfig,
  weeklyMileage,
  onDayStructureChange,
  onPhaseConfigChange,
  onWeeklyMileageChange,
}: AdaptivePlanConfigProps) {
  const [editingMileage, setEditingMileage] = useState<number | null>(null);

  // ── Day Structure ──────────────────────────────────────

  function setDayRole(dayOfWeek: number, role: string) {
    const updated = dayStructure.map((d) =>
      d.dayOfWeek === dayOfWeek ? { ...d, role } : d
    );
    onDayStructureChange(updated);
  }

  // ── Phase Config ───────────────────────────────────────

  function autoDistributePhases() {
    const total = durationWeeks;
    const taperWeeks = Math.max(2, Math.round(total * 0.1));
    const remaining = total - taperWeeks;
    const baseWeeks = Math.round(remaining * 0.25);
    const buildWeeks = Math.round(remaining * 0.35);
    const specificWeeks = remaining - baseWeeks - buildWeeks;

    const phases = [
      { name: "base", startWeek: 1, endWeek: baseWeeks },
      { name: "build", startWeek: baseWeeks + 1, endWeek: baseWeeks + buildWeeks },
      { name: "specific", startWeek: baseWeeks + buildWeeks + 1, endWeek: total - taperWeeks },
      { name: "taper", startWeek: total - taperWeeks + 1, endWeek: total },
    ];
    onPhaseConfigChange({ phases });

    // Auto-generate mileage targets
    const baseMiles = weeklyMileage[0]?.targetMiles || 40;
    const peakMiles = baseMiles * 1.5;
    const newMileage: WeeklyMileageTarget[] = [];
    for (let w = 1; w <= total; w++) {
      const phase = phases.find((p) => w >= p.startWeek && w <= p.endWeek);
      let target: number;
      if (phase?.name === "base") {
        target = baseMiles + ((peakMiles - baseMiles) * 0.3 * ((w - phase.startWeek) / Math.max(phase.endWeek - phase.startWeek, 1)));
      } else if (phase?.name === "build") {
        target = baseMiles * 1.3 + ((peakMiles - baseMiles * 1.3) * ((w - phase.startWeek) / Math.max(phase.endWeek - phase.startWeek, 1)));
      } else if (phase?.name === "specific") {
        target = peakMiles * (1 - 0.05 * ((w - phase.startWeek) / Math.max(phase.endWeek - phase.startWeek, 1)));
      } else {
        target = peakMiles * 0.5 * (1 - ((w - (phase?.startWeek || w)) / Math.max((phase?.endWeek || w) - (phase?.startWeek || w), 1)));
      }
      // Recovery week every 4th week (reduce 20%)
      if (w % 4 === 0 && phase?.name !== "taper") target *= 0.8;
      newMileage.push({ weekNumber: w, targetMiles: Math.round(target), phase: phase?.name || "base" });
    }
    onWeeklyMileageChange(newMileage);
  }

  return (
    <div className="space-y-6">
      {/* Day Structure */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
            Weekly Structure
          </h3>
          <span className="text-[10px] text-[var(--color-text-tertiary)]">
            Assign a role to each day
          </span>
        </div>

        <div className="space-y-1.5">
          {DAY_NAMES.map((name, idx) => {
            const entry = dayStructure.find((d) => d.dayOfWeek === idx);
            const role = entry?.role || "rest";
            return (
              <div key={idx} className="flex items-center gap-3">
                <span className="text-xs text-[var(--color-text-secondary)] w-8 font-medium">
                  {name}
                </span>
                <div className="flex gap-1 flex-1">
                  {ROLES.map((r) => (
                    <button
                      key={r}
                      onClick={() => setDayRole(idx, r)}
                      className={`px-2 py-1 text-[10px] rounded-md transition-all ${
                        role === r
                          ? "text-white font-medium"
                          : "text-[var(--color-text-tertiary)] hover:text-[var(--color-text-secondary)]"
                      }`}
                      style={{
                        backgroundColor: role === r ? ROLE_COLORS[r] : "transparent",
                        border: role === r ? "none" : "1px solid var(--color-divider)",
                      }}
                    >
                      {ROLE_LABELS[r]}
                    </button>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Phase Config */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
            Periodization
          </h3>
          <button
            onClick={autoDistributePhases}
            className="text-[10px] text-[var(--color-coral)] hover:underline"
          >
            Auto-distribute
          </button>
        </div>

        {/* Phase bar */}
        <div className="flex rounded-lg overflow-hidden h-8 mb-2">
          {phaseConfig.phases.map((phase) => {
            const weeks = phase.endWeek - phase.startWeek + 1;
            const pct = (weeks / durationWeeks) * 100;
            return (
              <div
                key={phase.name}
                className="flex items-center justify-center text-white text-[10px] font-medium"
                style={{
                  width: `${pct}%`,
                  backgroundColor: PHASE_COLORS[phase.name] || "#9B9590",
                }}
              >
                {pct > 12 ? `${phase.name} (${weeks}w)` : weeks > 0 ? `${weeks}w` : ""}
              </div>
            );
          })}
        </div>

        {/* Phase week editors */}
        <div className="grid grid-cols-4 gap-2">
          {PHASES.map((phaseName) => {
            const phase = phaseConfig.phases.find((p) => p.name === phaseName);
            return (
              <div key={phaseName} className="text-center">
                <span
                  className="text-[9px] font-semibold uppercase tracking-wider"
                  style={{ color: PHASE_COLORS[phaseName] }}
                >
                  {phaseName}
                </span>
                <div className="flex items-center gap-1 mt-1 justify-center">
                  <input
                    type="number"
                    min={1}
                    max={durationWeeks}
                    value={phase?.startWeek || 1}
                    onChange={(e) => {
                      const val = parseInt(e.target.value) || 1;
                      const updated = phaseConfig.phases.map((p) =>
                        p.name === phaseName ? { ...p, startWeek: val } : p
                      );
                      onPhaseConfigChange({ phases: updated });
                    }}
                    className="w-10 text-center text-xs border border-[var(--color-divider)] rounded px-1 py-0.5"
                  />
                  <span className="text-[10px] text-[var(--color-text-tertiary)]">–</span>
                  <input
                    type="number"
                    min={1}
                    max={durationWeeks}
                    value={phase?.endWeek || 1}
                    onChange={(e) => {
                      const val = parseInt(e.target.value) || 1;
                      const updated = phaseConfig.phases.map((p) =>
                        p.name === phaseName ? { ...p, endWeek: val } : p
                      );
                      onPhaseConfigChange({ phases: updated });
                    }}
                    className="w-10 text-center text-xs border border-[var(--color-divider)] rounded px-1 py-0.5"
                  />
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Weekly Mileage Targets */}
      <div>
        <h3 className="text-xs font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)] mb-3">
          Weekly Mileage
        </h3>

        {/* Bar chart */}
        <div className="flex items-end gap-0.5 h-24 mb-2">
          {weeklyMileage.map((wm) => {
            const maxMiles = Math.max(...weeklyMileage.map((w) => w.targetMiles), 1);
            const heightPct = (wm.targetMiles / maxMiles) * 100;
            return (
              <button
                key={wm.weekNumber}
                onClick={() => setEditingMileage(editingMileage === wm.weekNumber ? null : wm.weekNumber)}
                className="flex-1 flex flex-col items-center justify-end relative group"
              >
                <div
                  className="w-full rounded-t-sm transition-all"
                  style={{
                    height: `${heightPct}%`,
                    backgroundColor: PHASE_COLORS[wm.phase] || "#9B9590",
                    opacity: editingMileage === wm.weekNumber ? 1 : 0.7,
                  }}
                />
                {/* Tooltip */}
                <div className="absolute -top-6 hidden group-hover:block bg-[var(--color-text-primary)] text-white text-[8px] px-1.5 py-0.5 rounded whitespace-nowrap">
                  W{wm.weekNumber}: {wm.targetMiles}mi
                </div>
              </button>
            );
          })}
        </div>

        {/* Editable mileage for selected week */}
        {editingMileage && (
          <div className="flex items-center gap-3 bg-[var(--color-bg)] rounded-lg px-3 py-2">
            <span className="text-xs text-[var(--color-text-secondary)]">
              Week {editingMileage}:
            </span>
            <input
              type="number"
              value={weeklyMileage.find((w) => w.weekNumber === editingMileage)?.targetMiles || 0}
              onChange={(e) => {
                const val = parseInt(e.target.value) || 0;
                onWeeklyMileageChange(
                  weeklyMileage.map((w) =>
                    w.weekNumber === editingMileage ? { ...w, targetMiles: val } : w
                  )
                );
              }}
              className="w-16 text-center text-sm border border-[var(--color-divider)] rounded px-2 py-1"
            />
            <span className="text-xs text-[var(--color-text-tertiary)]">miles</span>
          </div>
        )}
      </div>
    </div>
  );
}

// ── Default Builders ─────────────────────────────────────

export function buildDefaultDayStructure(): DayStructureEntry[] {
  return [
    { dayOfWeek: 0, role: "easy" },      // Mon
    { dayOfWeek: 1, role: "speed" },      // Tue
    { dayOfWeek: 2, role: "easy" },       // Wed
    { dayOfWeek: 3, role: "moderate" },   // Thu
    { dayOfWeek: 4, role: "rest" },       // Fri
    { dayOfWeek: 5, role: "long_run" },   // Sat
    { dayOfWeek: 6, role: "easy" },       // Sun
  ];
}

export function buildDefaultPhaseConfig(weeks: number): PhaseConfig {
  const taper = Math.max(2, Math.round(weeks * 0.1));
  const remaining = weeks - taper;
  const base = Math.round(remaining * 0.25);
  const build = Math.round(remaining * 0.35);
  const specific = remaining - base - build;
  return {
    phases: [
      { name: "base", startWeek: 1, endWeek: base },
      { name: "build", startWeek: base + 1, endWeek: base + build },
      { name: "specific", startWeek: base + build + 1, endWeek: weeks - taper },
      { name: "taper", startWeek: weeks - taper + 1, endWeek: weeks },
    ],
  };
}

export function buildDefaultMileage(weeks: number, startMiles: number = 40): WeeklyMileageTarget[] {
  const phases = buildDefaultPhaseConfig(weeks);
  const peak = startMiles * 1.5;
  return Array.from({ length: weeks }, (_, i) => {
    const w = i + 1;
    const phase = phases.phases.find((p) => w >= p.startWeek && w <= p.endWeek);
    let target = startMiles;
    if (phase?.name === "base") target = startMiles + (peak - startMiles) * 0.3 * ((w - phase.startWeek) / Math.max(phase.endWeek - phase.startWeek, 1));
    else if (phase?.name === "build") target = startMiles * 1.3 + (peak - startMiles * 1.3) * ((w - phase.startWeek) / Math.max(phase.endWeek - phase.startWeek, 1));
    else if (phase?.name === "specific") target = peak;
    else target = peak * 0.5;
    if (w % 4 === 0 && phase?.name !== "taper") target *= 0.8;
    return { weekNumber: w, targetMiles: Math.round(target), phase: phase?.name || "base" };
  });
}
