import type { Acwr, WeeklyVolumeWeek } from "@/lib/coach-dashboard/types";
import { AcwrCard } from "./acwr-dial";
import { WeeklyVolume } from "./weekly-volume";

/**
 * LoadBand — macro load: 12-week volume-by-zone, next to the ACWR gauge when
 * an athlete_state read is available (otherwise volume runs full width).
 */
export function LoadBand({
  weeks,
  acwr,
}: {
  weeks: WeeklyVolumeWeek[];
  acwr?: Acwr;
}) {
  return (
    <div className={`grid gap-3.5 ${acwr ? "md:grid-cols-[1fr_300px] md:items-stretch" : ""}`}>
      <div className="rounded-xl border border-divider bg-bg-card p-5">
        <div className="mb-1.5 flex items-baseline justify-between">
          <div className="font-display text-[17px] font-bold text-text-primary">Weekly volume</div>
          <div className="font-mono text-[10px] uppercase tracking-[0.06em] text-text-tertiary">
            12 weeks · stacked by pace zone
          </div>
        </div>
        <WeeklyVolume weeks={weeks} />
      </div>
      {acwr ? <AcwrCard acwr={acwr} /> : null}
    </div>
  );
}
