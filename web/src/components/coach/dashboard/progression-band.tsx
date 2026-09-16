import { EmptyState } from "@/components/ui/empty-state";
import type { Progression } from "@/lib/coach-dashboard/types";
import { FitnessCurve } from "./fitness-curve";
import { Rich } from "./rich-text";

const CONF_FILLED = { low: 1, moderate: 2, high: 3 } as const;

/**
 * ProgressionBand — "is the training working?" Predicted race as range +
 * confidence (never a point), a plain-language trend that cites a number, the
 * goal, and the 26-week fitness curve. Each piece degrades independently: no
 * range → an empty prediction note; no series → an empty chart state.
 */
export function ProgressionBand({ progression }: { progression: Progression }) {
  const { prediction, trendArrow, trendText, goalTime, gapLabel } = progression;
  const arrow = trendArrow === "up" ? "↗" : trendArrow === "down" ? "↘" : "→";
  const hasSeries = progression.fitnessSeries.length > 1;

  return (
    <div className="grid gap-3.5 md:grid-cols-[340px_1fr] md:items-stretch">
      <div className="flex flex-col border-b border-divider py-5">
        <div className="font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary">
          Predicted marathon
        </div>

        {prediction ? (
          <>
            <div className="mt-3 mb-0.5 font-mono text-[38px] font-semibold leading-none tabular-nums text-text-primary">
              {prediction.low}–{prediction.high}
            </div>
            <div className="mt-0.5 inline-flex items-center gap-1.5 font-mono text-[10px] uppercase tracking-[0.1em] text-text-secondary">
              <span className="inline-flex gap-0.5">
                {[0, 1, 2, 3].map((i) => (
                  <span
                    key={i}
                    className={`inline-block h-[11px] w-[4px] rounded-[1px] ${
                      i < CONF_FILLED[prediction.confidence] ? "bg-pace-mp" : "bg-text-tertiary"
                    }`}
                  />
                ))}
              </span>
              {prediction.confidence.charAt(0).toUpperCase() + prediction.confidence.slice(1)} confidence
            </div>
            <p className="mt-3.5 font-body text-[13px] leading-normal text-text-secondary">
              <Rich
                text={`Based on **${prediction.basis}**. Range, never a single time — the seconds aren't signal.`}
                strongClassName="font-semibold text-text-primary"
              />
            </p>
          </>
        ) : (
          <p className="mt-3 mb-1 font-body text-[13.5px] leading-normal text-text-secondary">
            No race prediction yet — it needs a confirmed race or a plan anchor. Predictions ship as a
            range with a confidence tier, never a single time.
          </p>
        )}

        {trendText ? (
          <div className="mt-3.5 flex items-start gap-2.5 border-t border-divider pt-3.5">
            <span className="font-mono text-[15px] font-semibold text-pace-mp">{arrow}</span>
            <span className="font-body text-[13.5px] leading-snug text-text-primary">
              <Rich text={trendText} />
            </span>
          </div>
        ) : null}

        {goalTime ? (
          <div className="mt-auto flex items-baseline justify-between border-t border-divider pt-4">
            <div>
              <div className="font-mono text-[9.5px] uppercase tracking-[0.12em] text-text-tertiary">Goal</div>
              <div className="mt-0.5 font-mono text-[20px] font-semibold tabular-nums text-text-primary">
                {goalTime}
              </div>
            </div>
            {gapLabel ? (
              <div className="text-right font-body text-[12.5px] text-text-secondary">{gapLabel}</div>
            ) : null}
          </div>
        ) : null}
      </div>

      <div className="border-b border-divider py-5">
        <div className="mb-1.5 flex items-baseline justify-between">
          <div className="font-display text-[17px] font-bold text-text-primary">Fitness curve</div>
          <div className="font-mono text-[10px] uppercase tracking-[0.06em] text-text-tertiary">
            26 weeks · race anchors marked
          </div>
        </div>
        {hasSeries ? (
          <>
            <FitnessCurve progression={progression} />
            <div className="mt-2 flex flex-wrap gap-4 font-mono text-[10px] uppercase tracking-[0.04em] text-text-secondary">
              <span className="inline-flex items-center gap-1.5">
                <span className="inline-block w-4 border-t-2 border-pace-mp" /> Fitness
              </span>
              <span className="inline-flex items-center gap-1.5">
                <span className="inline-block w-4 border-t-2 border-dashed border-pace-easy" /> Projected
              </span>
              <span className="inline-flex items-center gap-1.5">
                <span className="inline-block h-3 border-l border-text-tertiary" /> Confirmed race
              </span>
            </div>
          </>
        ) : (
          <EmptyState
            variant="data-pending"
            title="The fitness curve plots once there's a run history to trend and a race to anchor the scale."
          />
        )}
      </div>
    </div>
  );
}
