/**
 * The watch registry — the standing questions, in one place.
 *
 * Adding a watch: write a pure evaluator in this directory, import it here,
 * append it to ALL_WATCHES. The registry is meant to grow; Rio's three
 * domains are a starting set, not a boundary.
 *
 * The caller evaluates every watch against one assembled context and collects
 * findings, gaps, and clears separately — a gap is not an all-clear, and
 * flattening the two is how a blind spot starts reading as good news.
 */

import { easyDayDiscipline } from "./easyDayDiscipline.ts";
import { niggleFlare } from "./niggleFlare.ts";
import { recoveryTrend } from "./recoveryTrend.ts";
import type {
  Watch,
  WatchConfidence,
  WatchContext,
  WatchDomain,
  WatchFinding,
  WatchGap,
  WatchSeverity,
} from "./types.ts";

export const ALL_WATCHES: readonly Watch[] = [
  recoveryTrend,
  easyDayDiscipline,
  niggleFlare,
];

export * from "./types.ts";
export * from "./backtest.ts";
export { buildWatchContext, type WatchStateInput } from "./context.ts";
export { easyDayDiscipline, niggleFlare, recoveryTrend };

const SEVERITY_ORDER: Record<WatchSeverity, number> = {
  high: 0,
  med: 1,
  low: 2,
  info: 3,
};

/**
 * Tie-break when two watches shout equally loud.
 *
 * Without this, order fell out of registry position, which is arbitrary — a
 * recurring calf with a quality session two days out ranked below a mood
 * slide purely because recovery was declared first in the array.
 *
 * The ordering is by how quickly the window to act closes. A body signal
 * ahead of quality work is the most time-critical thing on the list; a pace
 * habit will still be there next week.
 */
const DOMAIN_PRIORITY: Record<WatchDomain, number> = {
  niggles: 0,
  recovery: 1,
  load: 2,
  pace: 3,
  consistency: 4,
};

const CONFIDENCE_ORDER: Record<WatchConfidence, number> = {
  high: 0,
  medium: 1,
  low: 2,
};

export interface WatchSweep {
  findings: WatchFinding[];
  gaps: WatchGap[];
  /** Watch ids that ran and found nothing wrong — the honest all-clear. */
  clear: string[];
}

/**
 * Run every watch. Findings come back loudest-first, which is the order a
 * coach with four minutes reads them in.
 *
 * A watch that throws is contained: one bad evaluator degrades to a gap
 * rather than taking the whole sweep down with it.
 */
export function runWatches(ctx: WatchContext, watches = ALL_WATCHES): WatchSweep {
  const sweep: WatchSweep = { findings: [], gaps: [], clear: [] };

  for (const w of watches) {
    let result;
    try {
      result = w.evaluate(ctx);
    } catch (_e) {
      sweep.gaps.push({
        watch_id: w.id,
        domain: w.domain,
        gap: "This watch failed to run.",
      });
      continue;
    }
    if (result.kind === "finding") sweep.findings.push(result.finding);
    else if (result.kind === "gap") sweep.gaps.push(result.gap);
    else sweep.clear.push(w.id);
  }

  // Loudest, then most time-critical, then most certain.
  sweep.findings.sort((a, b) =>
    SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity] ||
    DOMAIN_PRIORITY[a.domain] - DOMAIN_PRIORITY[b.domain] ||
    CONFIDENCE_ORDER[a.confidence] - CONFIDENCE_ORDER[b.confidence]
  );
  return sweep;
}
