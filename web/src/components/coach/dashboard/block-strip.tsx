import type { BlockStats } from "@/lib/coach-dashboard/types";
import { Cell } from "./editorial";

/**
 * BlockStrip — §03's lower half: where the athlete sits in the block.
 *
 * Two adherence numbers on purpose. "Sessions run" and "key sessions hit"
 * answer different questions, and a block can score 86% on the first while
 * missing every target on the second — which is exactly the block that needs a
 * coach. Showing only the first flatters it.
 */
export function BlockStrip({ block }: { block: BlockStats }) {
  const marks = Array.from({ length: block.totalWeeks }, (_, i) => i + 1);

  return (
    <div className="grid grid-cols-2 md:grid-cols-4">
      <div className="min-w-0 border-r border-divider py-3.5 pr-5">
        <span className="drip-eyebrow block">
          Week {block.weekNumber} of {block.totalWeeks}
        </span>
        <div className="mt-3 flex gap-[3px]">
          {marks.map((w) => (
            <span
              key={w}
              className={`h-[5px] flex-1 ${
                w === block.weekNumber
                  ? "bg-coral"
                  : w < block.weekNumber
                    ? "bg-text-tertiary"
                    : "bg-divider"
              }`}
            />
          ))}
        </div>
        {block.phaseLabel ? (
          <span className="drip-eyebrow mt-2.5 block whitespace-normal text-[9px] text-text-tertiary">
            {block.phaseLabel}
          </span>
        ) : null}
      </div>

      <Cell
        label="Sessions this week"
        value={
          <>
            {block.sessionsRun}
            {block.sessionsPlanned ? (
              <span className="ml-1 text-[11px] font-medium text-text-tertiary">
                / {block.sessionsPlanned}
              </span>
            ) : null}
          </>
        }
        meta={`${block.milesThisWeek.toFixed(1)} mi so far`}
        size="md"
      />

      {block.ranOf ? (
        <Cell
          label="Sessions run · 8 wk"
          value={`${block.ranPct}`}
          unit="%"
          meta={`${block.ranOf.run} of ${block.ranOf.prescribed} prescribed sessions run`}
        />
      ) : (
        <Cell label="Sessions run · 8 wk" value="Not scored" size="sm" meta="Needs an active plan" />
      )}

      {block.hitOf ? (
        <Cell
          label="Key sessions hit"
          value={
            <>
              {block.hitOf.hit}
              <span className="ml-1 text-[11px] font-medium text-text-tertiary">
                / {block.hitOf.total}
              </span>
            </>
          }
          meta="On target, heat-adjusted"
          accent={block.hitOf.hit * 2 < block.hitOf.total}
        />
      ) : (
        <Cell
          label="Last plan change"
          value={block.lastChangeLabel ?? "None yet"}
          size={block.lastChangeLabel ? "md" : "sm"}
          meta={block.lastChangeNote}
        />
      )}
    </div>
  );
}
