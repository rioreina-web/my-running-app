import type { Acwr, StressLoad, WeeklyVolumeWeek } from "@/lib/coach-dashboard/types";
import { LoadCells } from "./acwr-dial";
import { WeeklyVolume } from "./weekly-volume";

/**
 * LoadBand — §05. How much, and how hard.
 *
 * v1 was two cards side by side: a volume panel and a needle gauge. Now a
 * hairline cell row over the volume chart, so the numbers read as one line and
 * the chart is the only figure on the band.
 */
export function LoadBand({
  weeks,
  acwr,
  stress,
  milesThisWeek,
  milesPlanned,
}: {
  weeks: WeeklyVolumeWeek[];
  acwr?: Acwr;
  stress?: StressLoad;
  milesThisWeek?: number;
  milesPlanned?: number;
}) {
  // Mean of the four completed weeks before this one — the comparison the
  // coach actually makes. Excludes the current week, which is still filling.
  // This week's miles come from the block when there is a plan; without one,
  // the volume series still knows. "No plan" must not read as "no miles".
  const current = weeks.find((w) => w.current);
  const currentMiles =
    milesThisWeek ??
    (current ? Object.values(current.zoneMiles).reduce((a, b) => a + (b ?? 0), 0) : undefined);

  const done = weeks.filter((w) => !w.current);
  const last4 = done.slice(-4);
  const fourWeekAvg = last4.length
    ? last4.reduce((a, w) => a + Object.values(w.zoneMiles).reduce((x, y) => x + (y ?? 0), 0), 0) /
      last4.length
    : undefined;

  return (
    <>
      <LoadCells
        acwr={acwr}
        stress={stress}
        milesThisWeek={currentMiles}
        milesPlanned={milesPlanned}
        fourWeekAvg={fourWeekAvg}
      />
      <div className="py-5">
        <div className="mb-2 flex items-baseline justify-between">
          <span className="drip-eyebrow">Weekly volume · 12 weeks</span>
          <span className="drip-eyebrow text-text-tertiary">Stacked by pace zone</span>
        </div>
        <WeeklyVolume weeks={weeks} />
      </div>
    </>
  );
}
