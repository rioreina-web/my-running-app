"use client";

import {
  PACE_ZONES,
  PACE_ZONE_COLORS,
  paceShort,
  totalZoneMiles,
  type ZoneMiles,
} from "./workout-helpers";

/**
 * Daily volume-by-pace chart — one stacked bar per day, each segment a pace
 * zone (pale-sky Easy at the base → navy Mile on top), height = miles. Shared
 * by both surfaces: the coach builder feeds PROJECTED per-day miles (quality
 * from real steps, adaptive easy days estimated from the weekly range), the
 * athlete page feeds ACTUAL materialized scheduled_workouts. Purely
 * presentational — all the per-day zone math happens upstream.
 */

export interface DayVolume {
  /** Column label, e.g. "Mon". */
  label: string;
  /** Per-zone miles for the day. */
  zoneMiles: ZoneMiles;
  /** True for projected/estimated bars (adaptive easy fill) — rendered muted. */
  estimated?: boolean;
}

export function DailyVolumeChart({
  days,
  height = 112,
  emptyLabel = "No volume to show yet.",
}: {
  days: DayVolume[];
  height?: number;
  emptyLabel?: string;
}) {
  const totals = days.map((d) => totalZoneMiles(d.zoneMiles));
  const maxTotal = Math.max(...totals, 1);
  const barArea = height - 22; // leave room for the mi + day labels

  // Zones actually present across the week, slow→fast, for the legend.
  const presentZones = PACE_ZONES.filter((z) =>
    days.some((d) => (d.zoneMiles[z.value] ?? 0) > 0),
  );

  if (days.every((_, i) => totals[i] <= 0)) {
    return (
      <p className="text-[11px] italic text-text-tertiary py-2">{emptyLabel}</p>
    );
  }

  return (
    <div>
      <div className="flex items-end gap-2 px-0.5" style={{ height }}>
        {days.map((d, i) => {
          const total = totals[i];
          const h = total > 0 ? Math.max(4, Math.round((total / maxTotal) * barArea)) : 0;
          return (
            <div
              key={`${d.label}-${i}`}
              className="flex-1 flex flex-col justify-end items-center gap-1 h-full min-w-0"
              title={`${d.label} · ${total.toFixed(1)} mi${d.estimated ? " (projected)" : ""}`}
            >
              <span className="font-mono text-[9px] tabular-nums text-text-tertiary">
                {total > 0 ? total.toFixed(total < 10 ? 1 : 0) : ""}
              </span>
              <div
                className={`w-full rounded-t-[3px] overflow-hidden flex flex-col ${
                  d.estimated ? "opacity-70" : ""
                }`}
                style={{ height: `${h}px` }}
              >
                {/* Fastest on top → reverse the slow→fast zone list so Easy
                    sits at the base, matching the mileage-ramp bars. */}
                {[...PACE_ZONES].reverse().map((z) => {
                  const mi = d.zoneMiles[z.value];
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
              <span className="font-mono text-[9px] uppercase tracking-wider text-text-tertiary">
                {d.label}
              </span>
            </div>
          );
        })}
      </div>

      {presentZones.length > 0 && (
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mt-2">
          {presentZones.map((z) => (
            <span key={z.value} className="flex items-center gap-1">
              <span
                className="w-2 h-2 rounded-full shrink-0"
                style={{ background: PACE_ZONE_COLORS[z.value] }}
              />
              <span className="font-mono text-[9px] uppercase tracking-wider text-text-tertiary">
                {paceShort(z.value)}
              </span>
            </span>
          ))}
        </div>
      )}
    </div>
  );
}
