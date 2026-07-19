import {
  PACE_ZONES,
  PACE_ZONE_COLORS,
  paceShort,
  totalZoneMiles,
  type ZoneMiles,
} from "@/components/coach/workout-helpers";

// Pace × volume distribution — where the miles actually went, one
// horizontal bar per pace zone on the blue depth ramp. Pure presentation;
// the zone bucketing (actual run paces vs. the athlete's pace table)
// happens upstream. Observation, not prescription: no target mix, no
// "should" — just the shape of the training.

export function PaceVolumeDistribution({
  zoneMiles,
  windowLabel,
}: {
  zoneMiles: ZoneMiles;
  windowLabel: string;
}) {
  const total = totalZoneMiles(zoneMiles);
  if (total <= 0) {
    return (
      <p className="text-[11px] italic text-text-tertiary py-2">
        No logged miles in this window yet.
      </p>
    );
  }

  const present = PACE_ZONES.filter((z) => (zoneMiles[z.value] ?? 0) > 0);
  const maxMiles = Math.max(...present.map((z) => zoneMiles[z.value] ?? 0), 1);

  return (
    <div>
      <div className="flex items-baseline justify-between gap-3 mb-3">
        <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
          Pace × volume
        </p>
        <span className="font-mono text-[10px] uppercase tracking-wider text-text-tertiary tabular-nums">
          {windowLabel} · {total.toFixed(1)} mi
        </span>
      </div>
      <div className="space-y-1.5">
        {present.map((z) => {
          const miles = zoneMiles[z.value] ?? 0;
          const pct = (miles / total) * 100;
          const widthPct = Math.max(2, (miles / maxMiles) * 100);
          return (
            <div key={z.value} className="flex items-center gap-3">
              <span className="w-12 shrink-0 font-mono text-[10px] uppercase tracking-wider text-text-secondary text-right">
                {paceShort(z.value)}
              </span>
              <div className="flex-1 h-4 rounded-sm overflow-hidden bg-transparent">
                <div
                  className="h-full rounded-sm"
                  style={{
                    width: `${widthPct}%`,
                    background: PACE_ZONE_COLORS[z.value],
                  }}
                  title={`${miles.toFixed(1)} mi · ${pct.toFixed(0)}%`}
                />
              </div>
              <span className="w-20 shrink-0 font-mono text-[10px] tabular-nums text-text-tertiary">
                {miles.toFixed(1)} mi · {pct.toFixed(0)}%
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
