// Shared palette helpers for the coach dashboard.
//
// THE THREE-PALETTE RULE (CLAUDE.md): blue = pace, warm = mood, coral = alert.
// Pace colors come from PACE_ZONE_COLORS (workout-helpers); mood colors are the
// `--color-mood-*` tokens; coral is reserved for alerts (niggles / spike band).

import type { PaceZone } from "@/components/coach/workout-helpers";
import type { Mood } from "@/lib/coach-dashboard/types";

/** Mood label → its CSS custom property (mood-only palette). */
export const MOOD_COLOR: Record<Mood, string> = {
  energized: "var(--color-mood-energized)",
  positive: "var(--color-mood-positive)",
  neutral: "var(--color-mood-neutral)",
  tired: "var(--color-mood-tired)",
  struggling: "var(--color-mood-struggling)",
  injured: "var(--color-mood-injured)",
};

// Quality (non-aerobic) zones — hatched in the load charts so easy-vs-hard
// reads before you parse the blue. Aerobic base (recovery/easy/longRun/
// moderate/steady) is left solid.
const QUALITY_ZONES = new Set<PaceZone>([
  "mp",
  "hm",
  "threshold",
  "tenK",
  "fiveK",
  "threeK",
  "mile",
]);

export function isQualityZone(zone: PaceZone | null): boolean {
  return zone != null && QUALITY_ZONES.has(zone);
}

// Stacking order for bars, pale → navy. Unlike PACE_ZONES (which omits
// `longRun` by design), this includes EVERY zone so a long-run day actually
// renders. `longRun` shares moderate's blue stop via PACE_ZONE_COLORS.
export const ZONE_STACK_ORDER: PaceZone[] = [
  "recovery",
  "easy",
  "longRun",
  "moderate",
  "steady",
  "mp",
  "hm",
  "threshold",
  "tenK",
  "fiveK",
  "threeK",
  "mile",
];
