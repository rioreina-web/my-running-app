/**
 * buildBlocks — 6 × 4-week training-block rollups for block-over-block
 * coaching ("this block vs last"). Pure function extracted verbatim from
 * `rebuildAthleteState` (refactor §3). Owns the cross-source dedup of the
 * block-history rows.
 */

import { dedupBySourcePriority } from "../shared/dedup.ts";

export type BlockRow = Record<string, unknown>;

export interface TrainingBlock {
  block_start: string;
  block_end: string;
  total_miles: number;
  weekly_avg_miles: number;
  quality_sessions: number;
  easy_sessions: number;
  races_entered: number;
  avg_easy_pace_sec: number | null;
  injury_mentions: number;
  mood_summary: string | null;
}

export function buildBlocks(input: {
  /** Raw block-history training logs (24-week window); deduped internally. */
  blockHistoryRows: BlockRow[];
  /** Deduped niggle mention dates (YYYY-MM-DD) for per-block injury counts. */
  niggleMentionDates: string[];
  now: Date;
}): TrainingBlock[] {
  const { blockHistoryRows, niggleMentionDates, now } = input;

  // Cross-source dedup (same logic as current workouts) — blocks would
  // otherwise double-count. See _shared/shared/dedup.ts.
  const blockHistoryDeduped = dedupBySourcePriority(blockHistoryRows);

  const recentBlocks: TrainingBlock[] = [];
  for (let blockIdx = 0; blockIdx < 6; blockIdx++) {
    const blockEnd = new Date(now.getTime() - blockIdx * 28 * 86400000);
    const blockStart = new Date(blockEnd.getTime() - 28 * 86400000);

    const rowsInBlock = blockHistoryDeduped.filter((r) => {
      const t = new Date(r.workout_date as string).getTime();
      return t >= blockStart.getTime() && t < blockEnd.getTime();
    });
    if (rowsInBlock.length === 0) continue;

    const totalMiles = rowsInBlock.reduce((s, r) => s + ((r.workout_distance_miles as number) || 0), 0);
    let quality = 0;
    let easy = 0;
    let races = 0;
    // Niggle mentions that fall inside this block's window (was always 0 in v1).
    const injuryMentions = niggleMentionDates.filter((d) => {
      const t = new Date(d).getTime();
      return t >= blockStart.getTime() && t < blockEnd.getTime();
    }).length;
    const easyPaces: number[] = [];
    const moodCounts: Record<string, number> = {};

    for (const r of rowsInBlock) {
      const parsed = r.parsed_structure as Record<string, unknown> | null;
      const parsedType = parsed && typeof parsed === "object" ? parsed["type"] as string | undefined : undefined;
      const t = parsedType ?? "";
      if (t === "interval" || t === "tempo" || t === "progression") quality++;
      else if (t === "race") { quality++; races++; }
      else if (t === "easy" || t === "recovery" || t === "long_run") easy++;
      else easy++; // fallback unlabeled to easy

      // Easy pace for easy/recovery workouts — prefer workout_pace_per_mile column,
      // fall back to derived (duration/distance) when null (Strava imports often
      // don't populate the column but have distance + duration).
      if (t === "easy" || t === "recovery") {
        let paceSec: number | null = null;
        if (r.workout_pace_per_mile) {
          const parts = (r.workout_pace_per_mile as string).split(":").map(Number);
          if (parts.length === 2 && !isNaN(parts[0])) paceSec = parts[0] * 60 + parts[1];
        }
        if (paceSec === null) {
          const dist = r.workout_distance_miles as number;
          const dur = r.workout_duration_minutes as number;
          if (dist > 0 && dur > 0) paceSec = Math.round((dur * 60) / dist);
        }
        if (paceSec !== null && paceSec >= 300 && paceSec <= 840) {
          easyPaces.push(paceSec);
        }
      }
      if (r.mood) {
        const m = r.mood as string;
        moodCounts[m] = (moodCounts[m] ?? 0) + 1;
      }
    }
    const avgEasyPace = easyPaces.length > 0
      ? Math.round(easyPaces.reduce((a, b) => a + b, 0) / easyPaces.length)
      : null;
    const domMood = Object.entries(moodCounts).sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;

    recentBlocks.push({
      block_start: blockStart.toISOString().slice(0, 10),
      block_end: blockEnd.toISOString().slice(0, 10),
      total_miles: Math.round(totalMiles * 10) / 10,
      weekly_avg_miles: Math.round((totalMiles / 4) * 10) / 10,
      quality_sessions: quality,
      easy_sessions: easy,
      races_entered: races,
      avg_easy_pace_sec: avgEasyPace,
      injury_mentions: injuryMentions,
      mood_summary: domMood,
    });
  }

  return recentBlocks;
}
