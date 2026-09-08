/**
 * trends-insights — detector registry.
 *
 * Runs every detector against one shared `DetectCtx`, applies the Group C
 * convergence gate, drops `hidden` cards (an unmet gate renders as nothing,
 * never a stub), and sorts the survivors: group A → B → C, then active
 * before quiet, then higher confidence first. The view is a dumb renderer
 * over this list.
 */

import type { DetectCtx, TrendCard } from "./contract.ts";
import { detectA1, detectA2, detectA3, detectA4 } from "./detectorsA.ts";
import { detectB1, detectB2, detectB5, scaffoldBGated } from "./detectorsB.ts";
import { applyConvergence, scaffoldC } from "./detectorsC.ts";

const GROUP_ORDER: Record<string, number> = { A: 0, B: 1, C: 2 };
const STATUS_ORDER: Record<string, number> = { active: 0, quiet: 1, hidden: 2 };
const CONF_ORDER: Record<string, number> = { high: 0, medium: 1, low: 2 };

export function runDetectors(ctx: DetectCtx): TrendCard[] {
  const raw: TrendCard[] = [
    detectA1(ctx),
    detectA2(ctx),
    detectA3(ctx),
    detectA4(ctx),
    detectB1(ctx),
    detectB2(ctx),
    detectB5(ctx),
    ...scaffoldBGated(ctx),
    ...scaffoldC(ctx),
  ];

  const converged = applyConvergence(raw, ctx);

  return converged
    .filter((c) => c.status !== "hidden")
    .sort((a, b) => {
      if (GROUP_ORDER[a.group] !== GROUP_ORDER[b.group]) {
        return GROUP_ORDER[a.group] - GROUP_ORDER[b.group];
      }
      if (STATUS_ORDER[a.status] !== STATUS_ORDER[b.status]) {
        return STATUS_ORDER[a.status] - STATUS_ORDER[b.status];
      }
      return CONF_ORDER[a.confidence] - CONF_ORDER[b.confidence];
    });
}
