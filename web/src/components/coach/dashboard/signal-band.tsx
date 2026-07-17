import type { CoachableMoment, WatchItem } from "@/lib/coach-dashboard/types";
import { Rich } from "./rich-text";

/**
 * SignalBand — the attention surface: a watch list of flags and the AI
 * coachable moments (observational — an italic soft question when present,
 * never a directive). Both degrade to a quiet line when empty.
 */
export function SignalBand({
  watchList,
  moments,
}: {
  watchList: WatchItem[];
  moments: CoachableMoment[];
}) {
  return (
    <div className="grid gap-3.5 md:grid-cols-[1fr_1.35fr]">
      <div className="rounded-xl border border-divider bg-bg-card p-5">
        <h4 className="mb-3 font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary">
          Watch list
        </h4>
        {watchList.length ? (
          watchList.map((w, i) => (
            <div
              key={i}
              className="flex items-start gap-2.5 border-t border-divider py-2.5 first:border-t-0 first:pt-0"
            >
              <span
                className={`mt-1.5 h-[7px] w-[7px] shrink-0 rounded-full ${
                  w.severity === "warn" ? "bg-coral" : "bg-text-tertiary"
                }`}
              />
              <div>
                <div className="font-body text-[14px] leading-snug text-text-primary">
                  <Rich
                    text={w.title}
                    strongClassName="font-mono text-[12px] font-semibold text-text-primary"
                  />
                </div>
                <div className="mt-0.5 font-body text-[12px] text-text-secondary">{w.detail}</div>
              </div>
            </div>
          ))
        ) : (
          <p className="py-3 font-body text-[13px] italic text-text-tertiary">
            Nothing flagged right now.
          </p>
        )}
      </div>

      <div className="rounded-xl border border-divider bg-bg-card p-5">
        <h4 className="mb-3 font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary">
          Coachable moments · AI observations
        </h4>
        {moments.length ? (
          moments.map((m) => (
            <div key={m.id} className="border-t border-divider py-3.5 first:border-t-0 first:pt-0">
              <div className="mb-1.5 flex items-center justify-between gap-3">
                <span className="rounded-full bg-bg-calendar px-2 py-[3px] font-mono text-[9.5px] uppercase tracking-[0.1em] text-text-secondary">
                  {m.kind}
                </span>
                {m.when ? <span className="font-mono text-[10px] text-text-tertiary">{m.when}</span> : null}
              </div>
              <div className="font-body text-[14px] leading-snug text-text-primary">
                <Rich text={m.observation} strongClassName="font-bold text-coral-dark" />
              </div>
              {m.softQuestion ? (
                <div className="mt-1.5 font-display text-[14px] italic text-text-secondary">
                  {m.softQuestion}
                </div>
              ) : null}
            </div>
          ))
        ) : (
          <p className="py-3 font-body text-[13px] italic text-text-tertiary">
            No open observations. The system surfaces patterns here as they emerge.
          </p>
        )}
      </div>
    </div>
  );
}
