import type { Acwr, StressLoad } from "@/lib/coach-dashboard/types";
import { Cell } from "./editorial";

/**
 * LoadCells — §05's headline row: volume, stress load and acute:chronic.
 *
 * The ratio was a 240×150 needle gauge. Direction I has no gauges — print
 * doesn't — so it is a number over a hairline scale marking the 0.80–1.30 band
 * with a red tick at the current value. Same information, no chrome.
 *
 * (File keeps its old name so the import in load-band.tsx stays put; the
 * needle it was named for is gone.)
 */
export function LoadCells({
  acwr,
  stress,
  milesThisWeek,
  milesPlanned,
  fourWeekAvg,
}: {
  acwr?: Acwr;
  stress?: StressLoad;
  milesThisWeek?: number;
  milesPlanned?: number;
  fourWeekAvg?: number;
}) {
  return (
    <div className="grid grid-cols-2 border-b border-divider md:grid-cols-4">
      <Cell
        label="This week"
        value={milesThisWeek != null ? milesThisWeek.toFixed(1) : "No runs yet"}
        unit={milesThisWeek != null ? "mi" : undefined}
        size={milesThisWeek != null ? "md" : "sm"}
        meta={milesPlanned ? `${milesPlanned} planned` : undefined}
      />
      <Cell
        label="4-week average"
        value={fourWeekAvg != null ? fourWeekAvg.toFixed(1) : "Not enough weeks"}
        unit={fourWeekAvg != null ? "mi" : undefined}
        size={fourWeekAvg != null ? "md" : "sm"}
      />
      <Cell
        label="Stress load · 7 day"
        value={stress ? String(stress.acute) : "Not scored"}
        size={stress ? "md" : "sm"}
        meta={stress ? `${stress.chronic} chronic · weighted minutes` : "No session has been scored yet"}
      />
      {acwr ? <AcwrScale acwr={acwr} /> : <Cell label="Acute : chronic" value="Not scored" size="sm" />}
    </div>
  );
}

/** The ratio, as a hairline scale. Only a spike is red. */
function AcwrScale({ acwr }: { acwr: Acwr }) {
  const MAX = 2.0;
  const pct = (v: number) => `${Math.min(100, Math.max(0, (v / MAX) * 100))}%`;
  const spike = acwr.band === "spike";

  return (
    <div className="min-w-0 py-3.5 pr-5">
      <span className="drip-eyebrow block">Acute : chronic</span>
      <span className={`drip-stat mt-2 block text-[24px] leading-none ${spike ? "text-coral-dark" : ""}`}>
        {acwr.value.toFixed(2)}
      </span>
      <div className="relative mt-3.5 h-6 border-t border-divider">
        <span
          className="absolute -top-px h-[2px] bg-text-tertiary"
          style={{ left: pct(0.8), width: `calc(${pct(1.3)} - ${pct(0.8)})` }}
        />
        <span
          className="absolute -top-[5px] h-3 w-[2px] bg-coral"
          style={{ left: pct(acwr.value) }}
        />
        <span
          className="drip-eyebrow absolute top-3 text-[9px] text-text-tertiary"
          style={{ left: pct(0.8) }}
        >
          0.80
        </span>
        <span
          className="drip-eyebrow absolute top-3 text-[9px] text-text-tertiary"
          style={{ left: pct(1.3) }}
        >
          1.30
        </span>
      </div>
      <span className="drip-eyebrow mt-1 block text-[9px] text-text-tertiary">{acwr.bandLabel}</span>
    </div>
  );
}
