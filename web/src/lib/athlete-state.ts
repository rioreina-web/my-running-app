import { createClient } from "./supabase/server";

/**
 * UI register gate (0..3) — drives editorial voice on Today and gates pull-quotes.
 * Source of truth: supabase/functions/_shared/athlete-state.ts:computeDataDepth.
 */
export type DataDepth = 0 | 1 | 2 | 3;

/**
 * Fetch the current athlete's data_depth. Returns 0 on any failure or unauth —
 * the safest default (empty/day-zero UI).
 */
export async function getDataDepth(): Promise<DataDepth> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("athlete_state")
    .select("data_depth")
    .limit(1)
    .maybeSingle();
  if (error || !data) return 0;
  const v = (data as { data_depth: number | null }).data_depth ?? 0;
  if (v <= 0) return 0;
  if (v === 1) return 1;
  if (v === 2) return 2;
  return 3;
}

/** True when editorial register (italics, pull-quotes, trend deltas) is allowed. */
export function allowsEditorialVoice(depth: DataDepth): boolean {
  return depth >= 2;
}
