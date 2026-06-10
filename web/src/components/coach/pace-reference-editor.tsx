"use client";

// Compact pace-reference strip for the plan builder header. A coach sets
// either a goal race time (→ all zones derived) or explicit per-zone
// overrides. The resulting pace table cascades into the workout step editor
// via the `athletePaces` prop so dropdowns, ranges, and the reference card
// show this plan's actual numbers instead of the generic reference runner.

import { useMemo, useState } from "react";
import {
  PACE_ZONES,
  REFERENCE_PACE_SEC_PER_MILE,
  derivePaceTableFromGoal,
  formatPaceSecPerMile,
  parsePaceSecPerMile,
  trainingZoneRange,
  type PaceZone,
} from "./workout-helpers";

// Shape stored on plan_templates.phase_config.paceAnchor
export interface PaceAnchor {
  goalRaceSeconds?: number | null;   // total race seconds (e.g., 2:25:00 = 8700)
  goalRaceDistance?: string | null;  // matches plan.target_distance
  overrides?: Partial<Record<PaceZone, number>>; // per-zone sec/mi override
}

const MILES_FOR_DISTANCE: Record<string, number> = {
  marathon:      26.219,
  half_marathon: 13.109,
  "10k":          6.214,
  "5k":           3.107,
  mile:           1.000,
};

// Race-distance zones — these get a Time column the coach can edit directly.
// Editing a time back-computes the pace and stores it as the override.
const RACE_ZONE_MILES: Partial<Record<PaceZone, number>> = {
  mile:   1.000,
  threeK: 3000 / 1609.34,
  fiveK:  3.107,
  tenK:   6.214,
  hm:    13.109,
  mp:    26.219,
};

// Canonical 10-zone spectrum, MP-anchored. Display order matches
// the iOS Training tab — slowest (recovery) at the top of training
// zones, MP at the boundary, then fastest (mile) at the bottom of
// race zones. `threshold` and `longRun` were dropped from the
// canonical chart — HMP covers threshold effort, easy covers long
// run pace.
const RACE_ZONES_ORDERED:     PaceZone[] = ["mile", "threeK", "fiveK", "tenK", "hm", "mp"];
const TRAINING_ZONES_ORDERED: PaceZone[] = ["steady", "moderate", "easy", "recovery"];

// Turn a PaceAnchor into the full pace table the step editor consumes.
export function resolvePaceTable(
  anchor: PaceAnchor | null | undefined,
  planDistance: string,
): Record<PaceZone, number> {
  if (!anchor) return { ...REFERENCE_PACE_SEC_PER_MILE };
  let base: Record<PaceZone, number>;
  const goalSec = anchor.goalRaceSeconds ?? null;
  const distance = anchor.goalRaceDistance ?? planDistance;
  const miles = MILES_FOR_DISTANCE[distance] ?? 0;
  if (goalSec && miles > 0) {
    const goalSecPerMile = goalSec / miles;
    base = derivePaceTableFromGoal(goalSecPerMile, distance);
  } else {
    base = { ...REFERENCE_PACE_SEC_PER_MILE };
  }
  if (anchor.overrides) {
    for (const [zone, sec] of Object.entries(anchor.overrides)) {
      if (typeof sec === "number" && sec > 0) {
        base[zone as PaceZone] = sec;
      }
    }
  }
  return base;
}

function formatHms(totalSeconds: number): string {
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  return h > 0
    ? `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`
    : `${m}:${s.toString().padStart(2, "0")}`;
}

function parseHms(raw: string): number | null {
  const s = raw.trim();
  if (s === "") return null;
  const parts = s.split(":").map((p) => parseInt(p, 10));
  if (parts.some((n) => isNaN(n))) return null;
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 1) return parts[0];
  return null;
}

interface Props {
  anchor: PaceAnchor;
  onChange: (a: PaceAnchor) => void;
  planDistance: string;
}

export function PaceReferenceEditor({ anchor, onChange, planDistance }: Props) {
  const [expanded, setExpanded] = useState(false);
  const distance = anchor.goalRaceDistance ?? planDistance;
  const effective = useMemo(() => resolvePaceTable(anchor, planDistance), [anchor, planDistance]);

  function setGoalTime(raw: string) {
    const sec = parseHms(raw);
    onChange({ ...anchor, goalRaceSeconds: sec });
  }

  function setOverride(zone: PaceZone, raw: string) {
    const sec = parsePaceSecPerMile(raw);
    const next: PaceAnchor["overrides"] = { ...(anchor.overrides ?? {}) };
    if (sec == null) delete next[zone]; else next[zone] = sec;
    onChange({ ...anchor, overrides: next });
  }

  // Race-time edit → back-compute pace, store as override.
  function setOverrideTime(zone: PaceZone, raw: string) {
    const miles = RACE_ZONE_MILES[zone];
    if (!miles) return;
    const totalSec = parseHms(raw);
    const next: PaceAnchor["overrides"] = { ...(anchor.overrides ?? {}) };
    if (totalSec == null) delete next[zone];
    else next[zone] = Math.round(totalSec / miles);
    onChange({ ...anchor, overrides: next });
  }

  // Summary: highlight the 4 zones coaches reference most when authoring plans.
  // Threshold replaced by HMP per the canonical spectrum.
  const summaryZones: PaceZone[] = ["mp", "hm", "fiveK", "easy"];

  // Source label — makes the pace origin unambiguous at a glance.
  const hasGoal = !!anchor.goalRaceSeconds && anchor.goalRaceSeconds > 0;
  const hasOverrides = !!anchor.overrides && Object.values(anchor.overrides).some((v) => typeof v === "number" && v > 0);
  const sourceLabel = hasGoal
    ? `from ${formatHms(anchor.goalRaceSeconds!)} ${distance.replace("_", " ")}`
    : hasOverrides
      ? "coach overrides only"
      : "reference runner — set a goal time";

  return (
    <div className="rounded-md border border-[var(--color-divider)] bg-white">
      {/* Header bar — also the toggle. When expanded, the inline pace strip
          is hidden (redundant with the table below). */}
      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        className="w-full flex items-center gap-4 px-4 py-2.5 text-left hover:bg-[var(--color-bg-elevated)] transition-colors"
      >
        <div className="flex flex-col flex-shrink-0">
          <span className="text-xs font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
            Pace ref
          </span>
          <span className={`text-xs italic ${hasGoal ? "text-[var(--color-coral)]" : "text-[var(--color-text-tertiary)]"}`}>
            {sourceLabel}
          </span>
        </div>
        {!expanded && (
          <div className="flex items-baseline gap-4 font-mono text-sm flex-1 min-w-0 flex-wrap">
            {summaryZones.map((z) => {
              const zMeta = PACE_ZONES.find((p) => p.value === z)!;
              const isOverridden = !!anchor.overrides?.[z];
              // Training zones render as fast–slow when no override is set,
              // so the summary matches the expanded table's band-based view.
              // An override (coach-pinned single pace) wins regardless —
              // showing a range would lie about what the coach prescribed.
              const range = !isOverridden ? trainingZoneRange(z, effective.mp) : null;
              return (
                <span key={z} className="flex items-baseline gap-1.5">
                  <span className="text-xs text-[var(--color-text-tertiary)]">{zMeta.shortName}</span>
                  <span className={`tabular-nums ${isOverridden ? "text-[var(--color-coral)] font-semibold" : "text-[var(--color-text-primary)]"}`}>
                    {range
                      ? `${formatPaceSecPerMile(range.fastSec)}–${formatPaceSecPerMile(range.slowSec)}`
                      : formatPaceSecPerMile(effective[z])}
                  </span>
                </span>
              );
            })}
          </div>
        )}
        <span className={`text-xs ml-auto ${expanded ? "text-[var(--color-coral)] font-semibold" : "text-[var(--color-text-tertiary)]"}`}>
          {expanded ? "hide" : "edit"}
        </span>
      </button>

      {/* Expanded editor */}
      {expanded && (
        <div className="border-t border-[var(--color-divider)] px-4 py-4 space-y-4">
          {/* Goal time row */}
          <div className="flex items-center gap-3 flex-wrap">
            <label className="text-xs uppercase tracking-wider text-[var(--color-text-tertiary)] font-semibold">
              Goal race time
            </label>
            <input
              type="text"
              inputMode="numeric"
              placeholder="H:MM:SS"
              defaultValue={anchor.goalRaceSeconds ? formatHms(anchor.goalRaceSeconds) : ""}
              key={`goal-${anchor.goalRaceSeconds ?? "none"}`}
              onBlur={(e) => setGoalTime(e.target.value)}
              className="w-28 text-center text-sm font-mono border border-[var(--color-divider)] rounded px-2 py-1.5 focus:outline-none focus:border-[var(--color-coral)]"
            />
            <span className="text-xs text-[var(--color-text-tertiary)]">
              for {distance.replace("_", " ")}
            </span>
            <span className="text-xs text-[var(--color-text-tertiary)] italic ml-auto">
              Leave blank to use reference runner. Override any zone below.
            </span>
          </div>

          {/* Zone table — race paces on top (with race-time column), training zones below. */}
          <div className="border border-[var(--color-divider)] rounded-md overflow-hidden">
            <ZoneTableHeader />
            <ZoneSectionLabel label="Race paces" />
            {RACE_ZONES_ORDERED.map((zv) => {
              const z = PACE_ZONES.find((p) => p.value === zv)!;
              const derived = effective[zv];
              const override = anchor.overrides?.[zv];
              const miles = RACE_ZONE_MILES[zv]!;
              const derivedTime = formatHms(Math.round(derived * miles));
              return (
                <ZoneRow
                  key={zv}
                  shortName={z.shortName}
                  description={z.description}
                  derivedPace={formatPaceSecPerMile(derived)}
                  paceInputKey={`ov-pace-${zv}-${override ?? "none"}`}
                  paceDefault={override ? formatPaceSecPerMile(override) : ""}
                  onPaceBlur={(v) => setOverride(zv, v)}
                  timeInputKey={`ov-time-${zv}-${override ?? "none"}`}
                  timeDefault={override ? formatHms(Math.round(override * miles)) : ""}
                  timePlaceholder={derivedTime}
                  onTimeBlur={(v) => setOverrideTime(zv, v)}
                />
              );
            })}
            <ZoneSectionLabel label="Training zones" />
            {TRAINING_ZONES_ORDERED.map((zv) => {
              const z = PACE_ZONES.find((p) => p.value === zv)!;
              const derived = effective[zv];
              const override = anchor.overrides?.[zv];
              // Training zones display as MP%-derived ranges (e.g.,
              // "5:50–6:09/mi · 95–90% MP") rather than single points,
              // because aerobic intensity is legitimately a band — calling
              // it 5:59 implies a precision the physiology doesn't have.
              // Override + race zones stay as single points (race targets
              // are exact). See trainingZoneRange in workout-helpers.ts.
              const range = trainingZoneRange(zv, effective.mp);
              return (
                <ZoneRow
                  key={zv}
                  shortName={z.shortName}
                  description={z.description}
                  derivedPace={
                    range
                      ? `${formatPaceSecPerMile(range.fastSec)}–${formatPaceSecPerMile(range.slowSec)}`
                      : formatPaceSecPerMile(derived)
                  }
                  derivedSecondary={range?.bandLabel}
                  paceInputKey={`ov-pace-${zv}-${override ?? "none"}`}
                  paceDefault={override ? formatPaceSecPerMile(override) : ""}
                  onPaceBlur={(v) => setOverride(zv, v)}
                />
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

// 4-column grid: Zone | Derived pace | Override pace | Race time
const ZONE_GRID = "grid grid-cols-[1fr_5rem_5.5rem_6rem] gap-x-4 items-center px-3";

function ZoneTableHeader() {
  return (
    <div className={`${ZONE_GRID} py-2 text-xs uppercase tracking-wider text-[var(--color-text-tertiary)] font-semibold bg-[var(--color-bg-elevated)] border-b border-[var(--color-divider)]`}>
      <span>Zone</span>
      <span className="text-right">Derived</span>
      <span className="text-right">Pace /mi</span>
      <span className="text-right">Race time</span>
    </div>
  );
}

function ZoneSectionLabel({ label }: { label: string }) {
  return (
    <div className="px-3 py-1 text-[10px] uppercase tracking-wider text-[var(--color-text-tertiary)] font-semibold bg-[var(--color-bg-elevated)]/40 border-t border-[var(--color-divider)] first:border-t-0">
      {label}
    </div>
  );
}

interface ZoneRowProps {
  shortName: string;
  description: string;
  derivedPace: string;
  /// Secondary line shown under the derived pace — used for training
  /// zones' MP% band (e.g., "95–90% MP"). Absent for race zones, which
  /// render as a single line.
  derivedSecondary?: string;
  paceInputKey: string;
  paceDefault: string;
  onPaceBlur: (value: string) => void;
  timeInputKey?: string;
  timeDefault?: string;
  timePlaceholder?: string;
  onTimeBlur?: (value: string) => void;
}

function ZoneRow({
  shortName, description,
  derivedPace, derivedSecondary,
  paceInputKey, paceDefault, onPaceBlur,
  timeInputKey, timeDefault, timePlaceholder, onTimeBlur,
}: ZoneRowProps) {
  return (
    <div className={`${ZONE_GRID} py-1.5 border-t border-[var(--color-divider)]`}>
      <span className="flex items-baseline gap-2 min-w-0">
        <span className="text-sm font-semibold text-[var(--color-text-primary)] flex-shrink-0">
          {shortName}
        </span>
        <span className="text-xs text-[var(--color-text-tertiary)] truncate">
          {description}
        </span>
      </span>
      <span className="flex flex-col items-end">
        <span className="text-sm font-mono tabular-nums text-[var(--color-text-secondary)]">
          {derivedPace}
        </span>
        {derivedSecondary && (
          <span className="text-[10px] text-[var(--color-text-tertiary)] tabular-nums">
            {derivedSecondary}
          </span>
        )}
      </span>
      <input
        type="text"
        inputMode="numeric"
        placeholder="auto"
        defaultValue={paceDefault}
        key={paceInputKey}
        onBlur={(e) => onPaceBlur(e.target.value)}
        className="w-full text-center text-sm font-mono tabular-nums border border-[var(--color-divider)] rounded px-2 py-1 focus:outline-none focus:border-[var(--color-coral)] placeholder:italic placeholder:text-[var(--color-text-tertiary)]/60"
      />
      {onTimeBlur ? (
        <input
          type="text"
          inputMode="numeric"
          placeholder={timePlaceholder}
          defaultValue={timeDefault}
          key={timeInputKey}
          onBlur={(e) => onTimeBlur(e.target.value)}
          className="w-full text-center text-sm font-mono tabular-nums border border-[var(--color-divider)] rounded px-2 py-1 focus:outline-none focus:border-[var(--color-coral)] placeholder:text-[var(--color-text-tertiary)]/60"
        />
      ) : (
        <span className="text-right text-[10px] italic text-[var(--color-text-tertiary)]/70">
          n/a
        </span>
      )}
    </div>
  );
}
