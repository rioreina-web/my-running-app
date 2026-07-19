/**
 * Memory selection + longitudinal arc for the coaching prompt (plan Step 5).
 *
 * Two pure helpers, both unit-tested and free of I/O:
 *
 *   selectMemoriesForPrompt — replaces the old "top-12 by importance" with
 *   QUOTA-based selection so one loud category can't crowd out the rest. Within
 *   each quota, rank by importance × recency of last_confirmed_at (a fact the
 *   athlete keeps re-mentioning outranks a one-off). Episodes are returned
 *   separately so the renderer can quote them with their date + verbatim words.
 *
 *   buildYearAgoArc — the longitudinal "this time last year" line. Given the
 *   widened (365-day) block-history rows, summarizes the 4-week window ~52
 *   weeks ago into mpw + dominant mood. Returns null when data doesn't reach
 *   back that far (the common case until an athlete crosses 12 months).
 */

/** A memory as carried on AthleteState (post-DB-map). */
export interface StateMemory {
  category: string;
  content: string;
  their_words: string | null;
  importance: number;
  memory_date: string | null;
  last_confirmed_at: string | null;
  mention_count: number;
}

export interface SelectedMemories {
  /** Non-episode memories to render as "• content", in category order. */
  general: StateMemory[];
  /** Episodes, rendered with date + verbatim phrase. */
  episodes: StateMemory[];
}

// Per-category quotas (plan Step 5.1). pr and race share one bucket; gear is
// intentionally NOT surfaced in the Read (stored + shown in Model of You, but
// too low-signal to spend prompt budget on). Total ≤ 12 — same budget the old
// top-12 used.
const QUOTAS: Array<{ key: string; categories: string[]; limit: number }> = [
  { key: "constraint", categories: ["constraint"], limit: 3 },
  { key: "preference", categories: ["preference"], limit: 3 },
  { key: "life", categories: ["life"], limit: 2 },
  { key: "pr_race", categories: ["pr", "race"], limit: 2 },
];
const EPISODE_LIMIT = 2;

/** Recency factor in [0.3, 1]: a year-stale confirm is worth ~0.3 of fresh. */
function recencyFactor(lastConfirmedAt: string | null, nowMs: number): number {
  if (!lastConfirmedAt) return 0.5; // unknown → neutral-ish
  const ageDays = (nowMs - new Date(lastConfirmedAt).getTime()) / 86400000;
  if (!Number.isFinite(ageDays)) return 0.5;
  return Math.max(0.3, Math.min(1, 1 - ageDays / 365));
}

function score(m: StateMemory, nowMs: number): number {
  return (m.importance ?? 5) * recencyFactor(m.last_confirmed_at, nowMs);
}

/**
 * PURE: quota-based selection. Input should already be status='active' rows.
 * Deterministic: ties broken by mention_count desc, then content.
 */
export function selectMemoriesForPrompt(
  memories: StateMemory[],
  nowIso: string = new Date().toISOString(),
): SelectedMemories {
  const nowMs = new Date(nowIso).getTime();
  const byScore = (a: StateMemory, b: StateMemory) => {
    const s = score(b, nowMs) - score(a, nowMs);
    if (Math.abs(s) > 1e-9) return s;
    const mc = (b.mention_count ?? 1) - (a.mention_count ?? 1);
    if (mc !== 0) return mc;
    return a.content.localeCompare(b.content);
  };

  const general: StateMemory[] = [];
  for (const q of QUOTAS) {
    const pool = memories.filter((m) => q.categories.includes(m.category));
    pool.sort(byScore);
    general.push(...pool.slice(0, q.limit));
  }

  const episodes = memories.filter((m) => m.category === "episode").sort(byScore).slice(0, EPISODE_LIMIT);

  return { general, episodes };
}

/** One year-ago summary line, or null when history doesn't reach back. */
export interface YearAgoArc {
  weekly_avg_miles: number;
  mood_summary: string | null;
}

/**
 * PURE: summarize the 4-week window centered ~52 weeks ago (days 336–364 back)
 * from the widened block-history rows. Returns null if no runs fall in it.
 */
export function buildYearAgoArc(
  blockHistoryRows: Array<Record<string, unknown>>,
  now: Date,
): YearAgoArc | null {
  const endMs = now.getTime() - 336 * 86400000; // 48 weeks ago
  const startMs = now.getTime() - 364 * 86400000; // 52 weeks ago
  let totalMiles = 0;
  let count = 0;
  const moodCounts: Record<string, number> = {};
  for (const r of blockHistoryRows) {
    const t = new Date(String(r.workout_date ?? "")).getTime();
    if (!Number.isFinite(t) || t < startMs || t >= endMs) continue;
    totalMiles += (r.workout_distance_miles as number) || 0;
    count++;
    const mood = r.mood as string | undefined;
    if (mood) moodCounts[mood] = (moodCounts[mood] ?? 0) + 1;
  }
  if (count === 0) return null;
  const domMood = Object.entries(moodCounts).sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
  return {
    weekly_avg_miles: Math.round((totalMiles / 4) * 10) / 10,
    mood_summary: domMood,
  };
}
